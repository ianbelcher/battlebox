class_name WorldNode
extends Node
## The world node, added as /root/Game/World on server and clients alike
## (identical path = RPC routing). On the server it owns the ChunkStore, the
## day/night clock, critters, sapling growth and player persistence. On a
## client it owns the ChunkView, player avatars, critters and the sky.
##
## Wire protocol (client -> server sv_*, server -> clients cl_*):
##   sv_hello                      -> cl_world_info(spawn, clock, source)
##   sv_request_chunks([Vector2i]) -> cl_chunk(cx, cz, zstd_blob) each
##   sv_where(slot)                -> cl_where(slot, pos, treasures)
##   sv_pos(slot, pos, yaw, anim)     (unreliable, ~12 Hz per player)
##   sv_edit(slot, pos, block)     -> cl_edit(pos, block, by_id) + cl_treasures
##   sv_pet(slot, critter_id)      -> cl_pet(critter_id)
##   (server timers)               -> cl_clock(frac), cl_critters(payload)

const EDIT_RANGE := 10.0
const AUTOSAVE_SECONDS := 25.0
const MAX_CRITTERS := 56
const CRITTERS_PER_PLAYER := 9

signal world_ready
signal treasures_changed
signal edit_applied(pos: Vector3i, block: int, by_id: String)
signal survival_changed
signal hearts_changed
signal survival_ended(seconds: float, bonked: int)
signal match_changed
signal storm_changed
signal map_list_changed
signal battle_config_changed
var client_minutes := 5
var client_size := 250
var client_loot := false
var client_team_names: Array = ["A", "B", "C", "D"]
var client_world := ""
## player_id -> dragon critter id, replicated so everyone sees who rides.
var riding_map: Dictionary = {}

@rpc("any_peer", "call_local", "reliable")
func sv_set_riding(slot: int, dragon_id: int) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id() \
		if multiplayer.get_remote_sender_id() != 0 else multiplayer.get_unique_id(), slot)
	if dragon_id < 0:
		riding_map.erase(id)
	else:
		riding_map[id] = dragon_id
	cl_riding.rpc(riding_map)

@rpc("authority", "reliable")
func cl_riding(map: Dictionary) -> void:
	riding_map = map
var map_list: Array = []
## Low-res whole-island backdrop for the radar (192x192, 4 blocks/px) so
## the map shows the world beyond what's rendered, even on slow machines.
var overview := PackedByteArray()

func overview_block(wx: int, wz: int) -> int:
	if overview.is_empty():
		return 0
	var ox := wx / 4 + 96
	var oz := wz / 4 + 96
	if ox < 0 or ox >= 192 or oz < 0 or oz >= 192:
		return 0
	return overview[oz * 192 + ox]

## Server: rough top-block guess from the pure terrain function — cheap,
## no chunk generation needed. Imported maps skip it (no pure function).
func _build_overview() -> void:
	overview = PackedByteArray()
	if store == null or store.source != "procedural":
		return
	overview.resize(192 * 192)
	for oz in 192:
		for ox in 192:
			var wx := (ox - 96) * 4
			var wz := (oz - 96) * 4
			var h: int = store.gen.height_at(wx, wz)
			h -= store.gen.lake_depth_at(wx, wz, h)
			var block := Blocks.GRASS
			if h <= WorldGen.SEA_LEVEL:
				block = Blocks.WATER
			elif h <= WorldGen.SEA_LEVEL + 2:
				block = Blocks.SAND
			elif h > WorldGen.SEA_LEVEL + 22:
				block = Blocks.SNOW
			if store.theme == "desert":
				block = Blocks.SAND if h > WorldGen.SEA_LEVEL else Blocks.WATER
			overview[oz * 192 + ox] = block
signal reset_vote_started
signal reset_result(happened: bool)

## WORLD_FAST=1 shrinks the day and sapling growth for quick testing.
static func fast_mode() -> bool:
	return OS.get_environment("WORLD_FAST") == "1"

static func day_seconds() -> float:
	return 90.0 if fast_mode() else 600.0

static func growth_msec() -> int:
	return 8_000 if fast_mode() else 100_000

# Shared
var spawn_pos := Vector3i(0, 30, 0)
var clock := 0.35            # day fraction: 0 midnight, 0.25 dawn, 0.5 noon
var source := "procedural"
var treasures: Dictionary = {}   # player id -> int (client mirror)
var hearts: Dictionary = {}      # player id -> int, during survival
var survival_active := false
var survival_wave := 0
## Battle royale: IDLE / LOBBY / DROP / BATTLE / END (mirrored on clients).
const TEAM_NAMES := ["Red", "Blue", "Green", "Yellow", "Purple", "Orange",
	"Cyan", "Pink", "Lime", "Navy", "Brown", "White", "Maroon", "Teal",
	"Gold", "Magenta", "Olive", "Sky", "Coral", "Violet", "Mint", "Slate",
	"Peach", "Onyx"]
const TEAM_COLORS := [Color("ff5a5a"), Color("4a9df8"), Color("51c979"),
	Color("ffd166"), Color("b06df8"), Color("ff9a3d"), Color("46d8d8"),
	Color("ff7ab8"), Color("a8e05f"), Color("3550b8"), Color("a5713f"),
	Color("f0f0f0"), Color("b03040"), Color("2f8f8f"), Color("d8a818"),
	Color("e040e0"), Color("909020"), Color("7ec8ff"), Color("ff8a70"),
	Color("8858d8"), Color("90e8b8"), Color("708098"), Color("ffc8a0"),
	Color("484858")]
var team_count := 4
var selected_map := ""
## Kid-tuned battle health: plenty of hearts, and after any hit you're
## untouchable for a moment — no more getting deleted in one volley.
const MATCH_HP := 8
const MERCY_MS := 2000
var _last_hit_ms: Dictionary = {}
## Display names for the teams, A..X by default; renameable from the
## Players view. Size always equals team_count.
var team_names: Array = ["A", "B", "C", "D"]
var match_phase := "IDLE"
var match_seconds := 0.0
var storm_radius := 0.0
var storm_center := Vector3.ZERO

# Client
var chunks: ChunkView = null
var players: Node3D = null
var critter_view: CritterView = null
var monster_view: MonsterView = null
var orbs: OrbView = null
var crates: CrateView = null
var _storm_wall: MeshInstance3D = null
var sky: DayNight = null
var _ready_announced := false

# Server
var store: ChunkStore = null
var _player_state: Dictionary = {}   # id -> {pos: Vector3, treasures: int, name: String}
var _chunk_send_queues: Dictionary = {}  # peer -> Array[Vector2i]
var _saplings: Array = []            # [{pos: Vector3i, at_msec: int}]
var _bombs: Array = []               # [{pos: Vector3i, at_msec: int}]
var _rockets: Array = []             # [{pos: Vector3i, at_msec: int}]
var _critters: Dictionary = {}       # id -> {kind, pos, target, speed, think}
var _next_critter_id := 1
## Survival ("the attack"): server-side monster sim.
var _monsters: Dictionary = {}       # id -> {pos, hp, next_bonk_ms}
var _next_monster_id := 1
var _downed: Dictionary = {}
var _survival_started_ms := 0
var _wave_started_ms := 0
var _bonked_count := 0
var _known_roster_ids: Dictionary = {}
var _was_night := false
var _water_accum := 0.0
var _fire_accum := 0.0

func _ready() -> void:
	if multiplayer.is_server():
		_server_setup()
	else:
		_client_setup()

# ------------------------------------------------------------------
# Server
# ------------------------------------------------------------------

func _server_setup() -> void:
	store = ChunkStore.new()
	source = store.source
	spawn_pos = store.find_spawn()
	_build_overview()
	var config := ConfigFile.new()
	config.load(store.data_dir.path_join("world.cfg"))
	clock = float(config.get_value("world", "clock", 0.35))
	print("World spawn at %s, clock %.2f" % [spawn_pos, clock])
	_load_player_file()
	_load_battle_setup()
	var autosave := Timer.new()
	autosave.wait_time = AUTOSAVE_SECONDS
	autosave.timeout.connect(_server_autosave)
	add_child(autosave)
	autosave.start()
	var clock_timer := Timer.new()
	clock_timer.wait_time = 5.0
	clock_timer.timeout.connect(func() -> void: cl_clock.rpc(clock))
	add_child(clock_timer)
	clock_timer.start()
	var critter_timer := Timer.new()
	critter_timer.wait_time = 0.33
	critter_timer.timeout.connect(_server_tick_critters)
	add_child(critter_timer)
	critter_timer.start()
	var growth_timer := Timer.new()
	growth_timer.wait_time = 7.0
	growth_timer.timeout.connect(_server_tick_growth)
	add_child(growth_timer)
	growth_timer.start()
	Game.roster_changed.connect(_server_on_roster_changed)

func _process(delta: float) -> void:
	clock = fposmod(clock + delta / day_seconds(), 1.0)
	if multiplayer.is_server():
		_drain_chunk_queues()
		_server_dawn_check()
		_server_tick_bombs()
		_server_tick_match(delta)
		_server_tick_bots(delta)
		_water_accum += delta
		if _water_accum > 0.3:
			_water_accum = 0.0
			_server_tick_water()
		_fire_accum += delta
		if _fire_accum > 0.8:
			_fire_accum = 0.0
			_server_tick_fire()

## Flush everything on clean shutdown (docker stop / pod reschedule); the
## 25s autosave bounds losses if the process is killed hard.
func _exit_tree() -> void:
	if multiplayer.is_server() and store != null:
		store.save_dirty()
		_save_player_file()

func _server_autosave() -> void:
	if match_phase != "IDLE":
		return  # matches live in RAM; nothing touches disk mid-fight
	var saved := store.save_dirty()
	var config := ConfigFile.new()
	config.load(store.data_dir.path_join("world.cfg"))
	config.set_value("world", "clock", clock)
	config.save(store.data_dir.path_join("world.cfg"))
	_save_player_file()
	if saved > 0:
		print("Autosave: %d chunks" % saved)

func _player_file_path() -> String:
	return store.data_dir.path_join("players.cfg")

func _load_player_file() -> void:
	pass  # read lazily per name in _saved_state_for

func _saved_state_for(pname: String) -> Dictionary:
	var config := ConfigFile.new()
	config.load(_player_file_path())
	var key := pname.to_lower()
	if not config.has_section(key):
		return {}
	return {
		"pos": config.get_value(key, "pos", Vector3.ZERO),
		"treasures": int(config.get_value(key, "treasures", 0)),
	}

func _save_player_file() -> void:
	if _player_state.is_empty():
		return
	var config := ConfigFile.new()
	config.load(_player_file_path())
	for id: String in _player_state.keys():
		var state: Dictionary = _player_state[id]
		var key := str(state.name).to_lower()
		if key.is_empty():
			continue
		config.set_value(key, "pos", state.pos)
		config.set_value(key, "treasures", state.treasures)
	config.save(_player_file_path())

func _server_on_roster_changed() -> void:
	# Persist and forget players whose roster entries vanished.
	for id: String in _known_roster_ids.keys():
		if not Game.roster.has(id):
			_save_player_file()
			_player_state.erase(id)
	_known_roster_ids.clear()
	for id: String in Game.roster.keys():
		_known_roster_ids[id] = true

@rpc("any_peer", "reliable")
func sv_hello() -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	cl_world_info.rpc_id(peer, spawn_pos, clock, source)
	cl_map_list.rpc_id(peer, ChunkStore.list_maps())
	cl_overview.rpc_id(peer, overview)
	cl_battle_config.rpc_id(peer, int(storm_minutes), int(battle_size), loot_only)
	cl_teams.rpc_id(peer, team_names)
	cl_world_sel.rpc_id(peer, selected_map if not selected_map.is_empty() \
		else (store.current_map_key if not store.current_map_key.is_empty() else store.theme))
	var payload: Array = []
	for crate_id: int in _crates.keys():
		payload.append([crate_id, _crates[crate_id].weapon, _crates[crate_id].pos])
	cl_crates.rpc_id(peer, payload)

@rpc("any_peer", "reliable")
func sv_request_chunks(list: Array) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var queue: Array = _chunk_send_queues.get(peer, [])
	for item in list:
		if item is Vector2i and queue.size() < 400:
			queue.append(item)
	_chunk_send_queues[peer] = queue

## Sending is spread over frames so a join burst (~90 chunks) doesn't stall
## the server or overflow the socket buffer.
func _drain_chunk_queues() -> void:
	for peer: int in _chunk_send_queues.keys():
		if not (peer in multiplayer.get_peers()):
			_chunk_send_queues.erase(peer)
			continue
		var queue: Array = _chunk_send_queues[peer]
		var sent := 0
		while sent < 5 and not queue.is_empty():
			var cpos: Vector2i = queue.pop_front()
			cl_chunk.rpc_id(peer, cpos.x, cpos.y, store.get_chunk_compressed(cpos))
			sent += 1
		if queue.is_empty():
			_chunk_send_queues.erase(peer)

@rpc("any_peer", "reliable")
func sv_where(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var id := Game.player_id(peer, slot)
	var entry: Dictionary = Game.roster.get(id, {})
	if entry.is_empty():
		return
	var saved := _saved_state_for(str(entry.name))
	var pos: Vector3
	var count := 0
	if not saved.is_empty() and saved.pos != Vector3.ZERO:
		pos = saved.pos
		count = saved.treasures
	else:
		pos = _far_spawn()
	_player_state[id] = {"pos": pos, "treasures": count, "name": str(entry.name)}
	cl_treasures.rpc(id, count)
	cl_where.rpc_id(peer, slot, pos, count)

## Fresh characters spawn ~100 blocks from everyone already playing.
func _far_spawn() -> Vector3:
	var others: Array = []
	for state: Dictionary in _player_state.values():
		others.append(state.pos)
	if others.is_empty():
		return Vector3(spawn_pos) + Vector3(randf_range(-2, 2), 2.0, randf_range(-2, 2))
	var best := Vector3(spawn_pos) + Vector3(0, 2, 0)
	var best_score := -1e9
	for i in 24:
		var anchor: Vector3 = others[randi() % others.size()]
		var angle := randf() * TAU
		var dist := randf_range(85.0, 125.0)
		var wx := int(anchor.x + cos(angle) * dist)
		var wz := int(anchor.z + sin(angle) * dist)
		if Vector2(wx, wz).length() > WorldGen.ISLAND_RADIUS - 20.0:
			continue
		var y := store.surface_y(wx, wz)
		if y <= WorldGen.SEA_LEVEL or y >= WorldGen.CHUNK_H - 8:
			continue
		var nearest := 1e9
		for other: Vector3 in others:
			nearest = minf(nearest, Vector2(wx - other.x, wz - other.z).length())
		if nearest > best_score:
			best_score = nearest
			best = Vector3(wx + 0.5, y + 2.0, wz + 0.5)
	return best

@rpc("any_peer", "unreliable_ordered")
func sv_pos(slot: int, pos: Vector3, yaw: float, anim: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var id := Game.player_id(peer, slot)
	if not Game.roster.has(id):
		return
	var state: Dictionary = _player_state.get(id, {"pos": pos, "treasures": 0,
		"name": str(Game.roster[id].name)})
	state.pos = pos
	_player_state[id] = state
	cl_pos.rpc(id, pos, yaw, anim)

@rpc("any_peer", "reliable")
func sv_edit(slot: int, pos: Vector3i, block: int) -> void:
	if not multiplayer.is_server():
		return
	var peer := multiplayer.get_remote_sender_id()
	var id := Game.player_id(peer, slot)
	if not Game.roster.has(id):
		return
	var state: Dictionary = _player_state.get(id, {})
	if state.is_empty() or Vector3(pos).distance_to(state.pos) > EDIT_RANGE:
		return
	var current := store.get_block(pos)
	if block == Blocks.AIR:
		if not Blocks.is_breakable(current):
			return
		# Clicking a Boom Block lights it rather than digging it; clicking a
		# lit one snuffs the fuse and picks it up.
		if current == Blocks.BOOM:
			for i in _bombs.size():
				if _bombs[i].pos == pos:
					_bombs.remove_at(i)
					store.set_block(pos, Blocks.AIR)
					cl_edit.rpc(pos, Blocks.AIR, id)
					return
			_bombs.append({"pos": pos, "at_msec": Time.get_ticks_msec() + 2500})
			cl_fuse_fx.rpc(pos)
			return
		if Blocks.is_collectible(current):
			state.treasures = int(state.treasures) + 1
			_player_state[id] = state
			cl_treasures.rpc(id, state.treasures)
	else:
		if not (block in Blocks.HOTBAR):
			return
		if current != Blocks.AIR and current != Blocks.TALL_GRASS \
				and not Blocks.is_liquid(current):
			return
		var supported := false
		for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
				Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			if Blocks.is_solid(store.get_block(pos + off)):
				supported = true
				break
		if not supported:
			return
		match block:
			Blocks.SAPLING:
				_saplings.append({"pos": pos, "at_msec": Time.get_ticks_msec()})
			Blocks.FIREWORK:
				_rockets.append({"pos": pos, "at_msec": Time.get_ticks_msec() + 1200})
			Blocks.SPONGE:
				_server_drain(pos)
	store.set_block(pos, block)
	cl_edit.rpc(pos, block, id)
	if block == Blocks.AIR:
		_disturb_water([pos])

## Stamp a prefab structure: only air, liquids and plants are overwritten,
## so stamps can't wreck existing builds.
@rpc("any_peer", "reliable")
func sv_structure(slot: int, base: Vector3i, index: int, roll: int, facing := 0) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	var state: Dictionary = _player_state.get(id, {})
	if state.is_empty() or Vector3(base).distance_to(state.pos) > 12.0:
		return
	var pairs: Array = []
	for entry: Array in Structures.cells(index, roll, facing):
		var pos: Vector3i = base + (entry[0] as Vector3i)
		if pos.y <= 0 or pos.y >= WorldGen.CHUNK_H:
			continue
		var current := store.get_block(pos)
		if current == Blocks.AIR or Blocks.is_liquid(current) or Blocks.is_cross(current):
			store.set_block(pos, entry[1])
			pairs.append([pos, entry[1]])
	if not pairs.is_empty():
		cl_edits.rpc(pairs)

## Throwing orbs (always on): the shooter simulates the arc; everyone else
## renders it. Hits on players knock them about (no harm); hits on Grumps
## use the survival damage path.
@rpc("any_peer", "unreliable")
func sv_shoot(slot: int, origin: Vector3, dir: Vector3, kind: int) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	if Game.roster.has(id):
		cl_orb.rpc(id, origin, dir, kind)

@rpc("authority", "unreliable")
func cl_orb(shooter_id: String, origin: Vector3, dir: Vector3, kind: int) -> void:
	if orbs != null:
		orbs.spawn(shooter_id, origin, dir, kind)

## Projectile impact. Pellets pop the single block they hit (or light a Boom
## Block from afar); shells detonate like a lit charge, splashing Grumps too.
@rpc("any_peer", "reliable")
func sv_shot(slot: int, cell: Vector3i, kind: int) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	var state: Dictionary = _player_state.get(id, {})
	if state.is_empty() or Vector3(cell).distance_to(state.pos) > 300.0:
		return
	match kind:
		17:  # Dragon fire: a big orange boom, no lingering flames.
			_blast(cell, 4.5, [], cell)
			if match_phase == "BATTLE":
				for pid: String in _match_alive.keys():
					if pid != id and _teams_differ(id, pid) \
							and _player_state.has(pid) \
							and Vector3(cell).distance_to(_player_state[pid].pos) < 6.0:
						_match_hurt(pid, 2, Vector3(cell))
			return
		14:  # Flare: a sky light, nothing to break.
			return
		15:  # Big Shooter: one huge crater.
			_blast(cell, 5.6, [], cell)
			if match_phase == "BATTLE":
				for pid: String in _match_alive.keys():
					if pid != id and _teams_differ(id, pid) \
							and _player_state.has(pid) \
							and Vector3(cell).distance_to(_player_state[pid].pos) < 8.0:
						_match_hurt(pid, 3, Vector3(cell))
			return
		1:  # Bazooka
			_blast(cell, 3.4, [], cell)
			if match_phase == "BATTLE":
				for pid: String in _match_alive.keys():
					if pid != id and _teams_differ(id, pid) \
							and _player_state.has(pid) \
							and Vector3(cell).distance_to(_player_state[pid].pos) < 5.0:
						_match_hurt(pid, 2, Vector3(cell))
			for monster_id: int in _monsters.keys().duplicate():
				if Vector3(cell).distance_to(_monsters[monster_id].pos) < 4.5:
					_monsters[monster_id].hp = int(_monsters[monster_id].hp) - 2
					var dead: bool = _monsters[monster_id].hp <= 0
					if dead:
						_monsters.erase(monster_id)
						_bonked_count += 1
					cl_zap_hit.rpc(monster_id, dead)
			return
		2:  # Grapple: client-side pull only.
			return
		3:  # Freeze Ray: water -> ice, Grumps frozen solid for a bit.
			var iced: Array = []
			for dy in range(-3, 4):
				for dz in range(-3, 4):
					for dx in range(-3, 4):
						var pos: Vector3i = cell + Vector3i(dx, dy, dz)
						if store.get_block(pos) == Blocks.WATER:
							store.set_block(pos, Blocks.ICE)
							iced.append(pos)
			if not iced.is_empty():
				cl_batch.rpc(iced, Blocks.ICE)
			var now := Time.get_ticks_msec()
			for monster_id: int in _monsters.keys():
				if Vector3(cell).distance_to(_monsters[monster_id].pos) < 4.5:
					_monsters[monster_id].frozen_until = now + 4000
			return
		4:  # Block Sucker: the hit block flies into the shooter's hotbar.
			var block := store.get_block(cell)
			if block != Blocks.AIR and Blocks.is_breakable(block) \
					and Blocks.hardness(block) <= 2 and not Blocks.is_liquid(block):
				store.set_block(cell, Blocks.AIR)
				cl_edit.rpc(cell, Blocks.AIR, id)
				_disturb_water([cell])
				cl_suck.rpc(id, block)
			return
		5:  # Bridge Gun: a plank walkway growing back toward the shooter.
			var dir := Vector3(state.pos) - Vector3(cell)
			dir.y = 0
			if dir.length() < 0.5:
				return
			dir = dir.normalized()
			var planks: Array = []
			for i in range(0, 5):
				var pos := Vector3i((Vector3(cell) + dir * i).round())
				pos.y = cell.y
				if store.get_block(pos) == Blocks.AIR:
					store.set_block(pos, Blocks.PLANKS)
					planks.append(pos)
			if not planks.is_empty():
				cl_batch.rpc(planks, Blocks.PLANKS)
			return
		6:  # Party Popper: confetti and a harmless mass fling.
			cl_party_fx.rpc(cell)
			for pid: String in _player_state.keys():
				if Vector3(cell).distance_to(_player_state[pid].pos) < 7.0:
					cl_bonk.rpc(pid, Vector3(cell))
			for monster_id: int in _monsters.keys():
				var m: Dictionary = _monsters[monster_id]
				if Vector3(cell).distance_to(m.pos) < 7.0:
					m.pos += (m.pos - Vector3(cell)).normalized() * 4.0
			return
		7:  # Whirl Wand: skyward gust, Grumps scattered.
			for pid: String in _player_state.keys():
				if Vector3(cell).distance_to(_player_state[pid].pos) < 6.0:
					cl_fling.rpc(pid)
			for monster_id: int in _monsters.keys():
				var m: Dictionary = _monsters[monster_id]
				if Vector3(cell).distance_to(m.pos) < 6.0:
					m.pos += Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			return
		8:  # Paint Bomb: soft terrain becomes random wool.
			var wools := [Blocks.WOOL_RED, Blocks.WOOL_YELLOW, Blocks.WOOL_BLUE,
				Blocks.WOOL_GREEN, Blocks.WOOL_PINK, Blocks.WOOL_PURPLE, Blocks.WOOL_TEAL]
			var pairs: Array = []
			for dy in range(-3, 4):
				for dz in range(-3, 4):
					for dx in range(-3, 4):
						if Vector3(dx, dy, dz).length() > 3.2:
							continue
						var pos: Vector3i = cell + Vector3i(dx, dy, dz)
						var block := store.get_block(pos)
						if block != Blocks.AIR and Blocks.is_breakable(block) \
								and Blocks.hardness(block) == 0 and not Blocks.is_liquid(block) \
								and not Blocks.is_cross(block):
							var wool: int = wools[randi() % wools.size()]
							store.set_block(pos, wool)
							pairs.append([pos, wool])
			if not pairs.is_empty():
				cl_edits.rpc(pairs)
			return
		9:  # Napalm Rocket: no crater — it just sets the impact ablaze.
			cl_boom_fx.rpc(cell)
			var splashed: Array = []
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					for dy in range(-1, 2):
						var ring := maxi(absi(dx), absi(dz))
						if ring == 2 and randf() > 0.5:
							continue  # ragged outer edge
						var pos: Vector3i = cell + Vector3i(dx, dy, dz)
						var block := store.get_block(pos)
						if (block == Blocks.AIR or Blocks.is_flammable(block)) \
								and _fires.size() < 160:
							store.set_block(pos, Blocks.FIRE)
							_fires[pos] = Time.get_ticks_msec() + randi_range(6000, 14000)
							splashed.append(pos)
			if not splashed.is_empty():
				cl_batch.rpc(splashed, Blocks.FIRE)
			return
		11:  # Wings do their work while held; the trigger does nothing.
			return
		12:  # (impact does nothing extra — the tunnel was carved at fire time)
			if false:
				pass
			return
		10:  # Grump Whistle: a wild Grump, raid or not.
			if _monsters.size() < 30:
				_monsters[_next_monster_id] = {"pos": Vector3(cell) + Vector3(0.5, 1.0, 0.5),
					"hp": 3, "next_bonk_ms": 0}
				_next_monster_id += 1
			return
	var current := store.get_block(cell)
	if current == Blocks.AIR or Blocks.is_liquid(current) or not Blocks.is_breakable(current):
		return
	# Pellets only chew through soft materials and wood — stone+ shrugs.
	if Blocks.hardness(current) > 1 and current != Blocks.BOOM:
		return
	if current == Blocks.BOOM:
		for entry: Dictionary in _bombs:
			if entry.pos == cell:
				return
		_bombs.append({"pos": cell, "at_msec": Time.get_ticks_msec() + 2500})
		cl_fuse_fx.rpc(cell)
		return
	if Blocks.is_collectible(current):
		state.treasures = int(state.treasures) + 1
		cl_treasures.rpc(id, state.treasures)
	store.set_block(cell, Blocks.AIR)
	cl_edit.rpc(cell, Blocks.AIR, id)
	_disturb_water([cell])

@rpc("any_peer", "reliable")
func sv_orb_hit(slot: int, target_id: String, hit_pos: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var shooter := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	if not Game.roster.has(shooter) or not Game.roster.has(target_id):
		return
	var target_state: Dictionary = _player_state.get(target_id, {})
	if target_state.is_empty() or Vector3(target_state.pos).distance_to(hit_pos) > 4.0:
		return
	if match_phase == "BATTLE" and _teams_differ(shooter, target_id):
		_match_hurt(target_id, 1, hit_pos)
		return
	cl_bonk.rpc(target_id, hit_pos)

## Digger: carve a 3x3 tunnel 15 blocks along the aim line, at fire time.
@rpc("any_peer", "reliable")
func sv_dig_tunnel(slot: int, origin: Vector3, dir: Vector3) -> void:
	if not multiplayer.is_server():
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	var state: Dictionary = _player_state.get(id, {})
	if state.is_empty() or origin.distance_to(state.pos) > 14.0:
		return
	dir = dir.normalized()
	var bored: Array = []
	for step in range(1, 16):
		var center := Vector3i((origin + dir * step).round())
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var pos := center + Vector3i(dx, dy, dz)
					var block := store.get_block(pos)
					if block != Blocks.AIR and Blocks.is_breakable(block) \
							and Blocks.hardness(block) <= 2 and not Blocks.is_liquid(block):
						store.set_block(pos, Blocks.AIR)
						bored.append(pos)
	if not bored.is_empty():
		cl_batch.rpc(bored, Blocks.AIR)
		_disturb_water(bored)

@rpc("any_peer", "reliable")
func sv_shoot_critter(_slot: int, critter_id: int) -> void:
	if multiplayer.is_server() and _critters.has(critter_id):
		_critters.erase(critter_id)

@rpc("any_peer", "reliable")
func sv_pet(slot: int, critter_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _critters.has(critter_id):
		cl_pet.rpc(critter_id)

## Boom blocks explode after their fuse; fireworks launch. Both checked
## every frame (the lists are tiny).
func _server_tick_bombs() -> void:
	var now := Time.get_ticks_msec()
	var pending: Array = []
	for entry: Dictionary in _bombs:
		if now < entry.at_msec:
			pending.append(entry)
		elif store.get_block(entry.pos) == Blocks.BOOM:  # not defused by digging
			_server_explode(entry.pos)
	_bombs = pending
	pending = []
	for entry: Dictionary in _rockets:
		if now < entry.at_msec:
			pending.append(entry)
		elif store.get_block(entry.pos) == Blocks.FIREWORK:
			store.set_block(entry.pos, Blocks.AIR)
			cl_batch.rpc([entry.pos], Blocks.AIR)
			cl_firework_fx.rpc(entry.pos)
	_rockets = pending

const BOOM_RADIUS := 3.2

func _server_explode(origin: Vector3i) -> void:
	# Every Boom Block CONNECTED to this one goes up together: n charges make
	# one blast with ~cbrt(n) times the radius. Unconnected ones nearby still
	# chain with short fuses.
	var connected: Dictionary = {origin: true}
	var frontier: Array = [origin]
	while not frontier.is_empty() and connected.size() < 64:
		var at: Vector3i = frontier.pop_back()
		for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
				Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var next: Vector3i = at + off
			if not connected.has(next) and store.get_block(next) == Blocks.BOOM:
				connected[next] = true
				frontier.append(next)
	var center := Vector3.ZERO
	for pos: Vector3i in connected.keys():
		store.set_block(pos, Blocks.AIR)
		center += Vector3(pos)
		# A merged charge can't also be a pending fuse.
		for i in range(_bombs.size() - 1, -1, -1):
			if _bombs[i].pos == pos:
				_bombs.remove_at(i)
	center /= connected.size()
	var radius := BOOM_RADIUS * pow(connected.size(), 0.34)
	_blast(Vector3i(center.round()), radius, connected.keys())

func _blast(origin: Vector3i, radius: float, pre_cleared: Array, impact := Vector3i(0, -999, 0)) -> void:
	var cleared: Array = pre_cleared.duplicate()
	var reach := int(ceil(radius))
	for dy in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if Vector3(dx, dy, dz).length() > radius:
					continue
				var pos := origin + Vector3i(dx, dy, dz)
				var block := store.get_block(pos)
				if block == Blocks.AIR or Blocks.is_liquid(block) or not Blocks.is_breakable(block):
					continue
				# Material tiers: stone only breaks near the heart of the
				# blast, steel only on a direct hit, diamond never.
				var tier := Blocks.hardness(block)
				if tier >= 4:
					continue
				if tier == 3 and pos != impact:
					continue
				if tier == 2 and Vector3(dx, dy, dz).length() > radius * 0.65 and pos != impact:
					continue
				# Chain reaction: other boom blocks in the blast go off too.
				if block == Blocks.BOOM and pos != origin:
					var already := false
					for entry: Dictionary in _bombs:
						if entry.pos == pos:
							already = true
					if not already:
						_bombs.append({"pos": pos, "at_msec": Time.get_ticks_msec() + 350})
					continue
				store.set_block(pos, Blocks.AIR)
				cleared.append(pos)
	cl_batch.rpc(cleared, Blocks.AIR)
	# Scorch the crater floor.
	var charred: Array = []
	for pos: Vector3i in cleared:
		var below: Vector3i = pos + Vector3i(0, -1, 0)
		var floor_block := store.get_block(below)
		if floor_block != Blocks.AIR and not Blocks.is_liquid(floor_block) \
				and Blocks.hardness(floor_block) < 2 and Blocks.is_breakable(floor_block) \
				and WorldGen.hash01(below.x, below.z, below.y) < 0.6:
			store.set_block(below, Blocks.CHARRED)
			charred.append(below)
	if not charred.is_empty():
		cl_batch.rpc(charred, Blocks.CHARRED)
	# Explosions start fires in whatever flammable stuff rings the crater.
	var lit: Array = []
	for pos: Vector3i in cleared:
		for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, 1, 0)]:
			var next: Vector3i = pos + off
			if Blocks.is_flammable(store.get_block(next)) and not _fires.has(next) \
					and _fires.size() < 120 and WorldGen.hash01(next.x, next.z, next.y) < 0.35:
				store.set_block(next, Blocks.FIRE)
				_fires[next] = Time.get_ticks_msec() + randi_range(5000, 11000)
				lit.append(next)
	if not lit.is_empty():
		cl_batch.rpc(lit, Blocks.FIRE)
	cl_boom_fx.rpc(origin)
	_disturb_water(cleared)

## Fire: burning cells spread through flammable blocks, gutter out on
## steel/stone, and singe players and Grumps standing in them.
var _fires: Dictionary = {}   # Vector3i -> expiry msec
var _burn_hurt_ms: Dictionary = {}  # player id -> next hurt msec

func _ignite_at(cell: Vector3i) -> void:
	var placed: Array = []
	for off in [Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 0, 0),
			Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var pos: Vector3i = cell + off
		var block := store.get_block(pos)
		if (block == Blocks.AIR or Blocks.is_flammable(block)) and _fires.size() < 120:
			store.set_block(pos, Blocks.FIRE)
			_fires[pos] = Time.get_ticks_msec() + randi_range(5000, 10000)
			placed.append(pos)
	if not placed.is_empty():
		cl_batch.rpc(placed, Blocks.FIRE)

func _server_tick_fire() -> void:
	if _fires.is_empty():
		return
	var now := Time.get_ticks_msec()
	var out: Array = []
	var lit: Array = []
	for pos: Vector3i in _fires.keys():
		if now > int(_fires[pos]):
			_fires.erase(pos)
			if store.get_block(pos) == Blocks.FIRE:
				store.set_block(pos, Blocks.AIR)
				out.append(pos)
			continue
		# Spread into flammable neighbors (steel and stone never catch).
		if randf() < 0.55 and _fires.size() < 120:
			var offs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0),
				Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
			var off: Vector3i = offs[randi() % offs.size()]
			var next: Vector3i = pos + off
			if Blocks.is_flammable(store.get_block(next)) and not _fires.has(next):
				store.set_block(next, Blocks.FIRE)
				_fires[next] = now + randi_range(5000, 11000)
				lit.append(next)
	if not out.is_empty():
		cl_batch.rpc(out, Blocks.AIR)
	if not lit.is_empty():
		cl_batch.rpc(lit, Blocks.FIRE)
	# Ouch: players and Grumps in the flames.
	for id: String in _player_state.keys():
		if now < int(_burn_hurt_ms.get(id, 0)):
			continue
		var ppos: Vector3 = _player_state[id].pos
		var cell := Vector3i(floori(ppos.x), floori(ppos.y + 0.3), floori(ppos.z))
		if _fires.has(cell) or _fires.has(cell + Vector3i(0, -1, 0)) or _fires.has(cell + Vector3i(0, 1, 0)):
			_burn_hurt_ms[id] = now + 1500
			cl_bonk.rpc(id, ppos + Vector3(0.4, -0.5, 0.4))
			if survival_active and not _downed.has(id):
				var state: Dictionary = _player_state[id]
				state.hp = int(state.get("hp", 5)) - 1
				cl_hearts.rpc(id, state.hp)
				if state.hp <= 0:
					_downed[id] = true
					cl_downed.rpc(id)
	for monster_id: int in _monsters.keys().duplicate():
		var mcell := Vector3i(_monsters[monster_id].pos.floor())
		if _fires.has(mcell):
			_monsters[monster_id].hp = int(_monsters[monster_id].hp) - 1
			var dead: bool = _monsters[monster_id].hp <= 0
			if dead:
				_monsters.erase(monster_id)
				_bonked_count += 1
			cl_zap_hit.rpc(monster_id, dead)

## Water flow: when blocks vanish next to water (dig, blast), the hole
## fills and the fill spreads — ponds pour into TNT craters properly.
var _holes: Array = []

func _disturb_water(removed_cells: Array) -> void:
	for cell in removed_cells:
		if cell is Vector3i and _holes.size() < 400:
			_holes.append({"pos": cell, "range": 10})

func _server_tick_water() -> void:
	if _holes.is_empty():
		return
	var filled: Array = []
	var next_holes: Array = []
	var budget := 48
	while not _holes.is_empty() and budget > 0:
		var entry = _holes.pop_front()
		var hole: Vector3i = entry.pos
		var hole_range: int = entry.range
		if store.get_block(hole) != Blocks.AIR:
			continue
		var wet := false
		for off in [Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
				Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var neighbor_block := store.get_block(hole + off)
			if neighbor_block == Blocks.WATER:
				wet = true
				break
		if not wet:
			continue
		budget -= 1
		store.set_block(hole, Blocks.WATER)
		filled.append(hole)
		# The new water keeps flowing: down freely, sideways only ~10 blocks
		# from where the leak started (like Minecraft, but wider).
		for off in [Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
				Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var next: Vector3i = hole + off
			var next_range := 10 if off.y < 0 else hole_range - 1
			if next_range >= 0 and store.get_block(next) == Blocks.AIR \
					and next_holes.size() < 200:
				next_holes.append({"pos": next, "range": next_range})
	_holes.append_array(next_holes)
	if not filled.is_empty():
		cl_batch.rpc(filled, Blocks.WATER)

## Sponges drink every liquid within reach the moment they're placed.
func _server_drain(origin: Vector3i) -> void:
	var cleared: Array = []
	for dy in range(-4, 5):
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				if Vector3(dx, dy, dz).length() > 3.8:
					continue
				var pos := origin + Vector3i(dx, dy, dz)
				if Blocks.is_liquid(store.get_block(pos)):
					store.set_block(pos, Blocks.AIR)
					cleared.append(pos)
	if not cleared.is_empty():
		cl_batch.rpc(cleared, Blocks.AIR)

## Saplings grow into little trees after a couple of minutes.
func _server_tick_growth() -> void:
	var now := Time.get_ticks_msec()
	var remaining: Array = []
	for entry: Dictionary in _saplings:
		if now - entry.at_msec < growth_msec():
			remaining.append(entry)
			continue
		var base: Vector3i = entry.pos
		if store.get_block(base) != Blocks.SAPLING:
			continue  # someone dug it up
		_grow_tree(base)
	_saplings = remaining

func _grow_tree(base: Vector3i) -> void:
	var trunk := 3 + int(WorldGen.hash01(base.x, base.z, 77) * 3.0)
	for i in trunk:
		_server_place(base + Vector3i(0, i, 0), Blocks.LOG)
	var top := base + Vector3i(0, trunk, 0)
	for dy in range(-2, 3):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				if Vector3(dx, dy * 1.4, dz).length() > 2.45:
					continue
				var pos := top + Vector3i(dx, dy, dz)
				if store.get_block(pos) == Blocks.AIR:
					_server_place(pos, Blocks.LEAVES)

func _server_place(pos: Vector3i, block: int) -> void:
	store.set_block(pos, block)
	cl_edit.rpc(pos, block, "")

## At dawn, fresh flowers pop up near wherever people are playing.
func _server_dawn_check() -> void:
	var night := clock > 0.78 or clock < 0.22
	if _was_night and not night:
		for state: Dictionary in _player_state.values():
			for attempt in 8:
				var pos: Vector3 = state.pos
				var wx := int(pos.x) + int(WorldGen.hash01(attempt, int(pos.x), 91) * 40.0) - 20
				var wz := int(pos.z) + int(WorldGen.hash01(attempt, int(pos.z), 92) * 40.0) - 20
				var y := store.surface_y(wx, wz)
				var ground := store.get_block(Vector3i(wx, y, wz))
				var above := store.get_block(Vector3i(wx, y + 1, wz))
				if ground == Blocks.GRASS and above == Blocks.AIR and attempt % 2 == 0:
					var flowers := [Blocks.FLOWER_RED, Blocks.FLOWER_YELLOW, Blocks.FLOWER_PINK]
					_server_place(Vector3i(wx, y + 1, wz),
						flowers[int(WorldGen.hash01(wx, wz, 93) * 3.0)])
	_was_night = night

# --- Server critters ---

## Map reset: any player proposes, EVERY connected machine must agree, then
## the world regenerates with a brand-new random seed.
var _reset_votes: Dictionary = {}
var _reset_deadline_ms := 0

@rpc("any_peer", "reliable")
func sv_reset_request(_slot: int) -> void:
	if not multiplayer.is_server() or not _reset_votes.is_empty():
		return
	var peer := multiplayer.get_remote_sender_id()
	_reset_votes = {peer: true}
	_reset_deadline_ms = Time.get_ticks_msec() + 30_000
	cl_reset_vote.rpc()
	_check_reset_votes()

@rpc("any_peer", "reliable")
func sv_reset_answer(agree: bool) -> void:
	if not multiplayer.is_server() or _reset_votes.is_empty():
		return
	if not agree:
		_reset_votes.clear()
		cl_reset_result.rpc(false)
		return
	_reset_votes[multiplayer.get_remote_sender_id()] = true
	_check_reset_votes()

func _check_reset_votes() -> void:
	if Time.get_ticks_msec() > _reset_deadline_ms:
		_reset_votes.clear()
		cl_reset_result.rpc(false)
		return
	for peer: int in multiplayer.get_peers():
		if not _reset_votes.has(peer):
			return
	_reset_votes.clear()
	_do_world_reset()

@rpc("any_peer", "call_local", "reliable")
func sv_new_map(map_name: String) -> void:
	if not multiplayer.is_server() or match_phase != "IDLE":
		return
	if not _known_map(map_name):
		return
	_do_world_reset(map_name)

func _do_world_reset(map_name := "") -> void:
	var new_seed := randi() % 1000000000
	print("WORLD RESET: new seed %d map=%s" % [new_seed, map_name])
	store.reset_world(new_seed, map_name)
	spawn_pos = store.find_spawn()
	_build_overview()
	cl_overview.rpc(overview)
	clock = 0.35
	survival_active = false
	_monsters.clear()
	_fires.clear()
	_holes.clear()
	_bombs.clear()
	_saplings.clear()
	_critters.clear()
	for state: Dictionary in _player_state.values():
		state.pos = Vector3.ZERO  # everyone gets a fresh far spawn
	_player_state.clear()
	cl_reset_result.rpc(true)
	cl_world_info.rpc(spawn_pos, clock, source)
	cl_world_reset.rpc()

# ------------------------------------------------------------------
# Battle royale match
# ------------------------------------------------------------------
const LOBBY_SECONDS := 25.0
const STORM_START := 360.0

## Battle square side in blocks (the storm starts at its edge).
var battle_size := 250.0
## Game-loop mode: matches chain with a countdown + fresh map between.
var match_loop := true

# ---------------- Server-side computer players ----------------
# Bots live entirely on the server (peer 1): they appear in the roster
# like anyone else, replicate through the normal position channel, pick
# up crates, fight, flee the storm and revive teammates.
var _bots: Dictionary = {}
var _next_bot_slot := 100

@rpc("any_peer", "call_local", "reliable")
func sv_add_bot() -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if Game.roster.size() >= 24:
		return
	_spawn_bot()
	_save_battle_setup()

func _spawn_bot() -> void:
	if Game.roster.size() >= 24:
		return
	var slot := _next_bot_slot
	_next_bot_slot += 1
	var id := Game.player_id(1, slot)
	var number := 0
	for other: String in _bots.keys():
		number = maxi(number, int(str(Game.roster.get(other, {}).get("name", "0"))))
	Game.roster[id] = {"peer": 1, "slot": slot, "name": str(number + 1),
		"style": AvatarFactory.random_style(), "team": -1, "bot": true}
	var start := Vector3(spawn_pos) + Vector3(randf_range(-8, 8), 2, randf_range(-8, 8))
	_bots[id] = {"slot": slot, "pos": start, "yaw": 0.0, "think": 0.0,
		"weapon": 13, "shoot_cd": 0.0, "goal": start}
	_player_state[id] = {"pos": start, "treasures": 0, "name": Game.roster[id].name, "hp": 5}
	_redistribute_bots()

@rpc("any_peer", "call_local", "reliable")
func sv_remove_bot(target_id: String = "") -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if _bots.is_empty():
		return
	var id := target_id if _bots.has(target_id) else str(_bots.keys().back())
	_bots.erase(id)
	_player_state.erase(id)
	_match_alive.erase(id)
	Game.roster.erase(id)
	Game.cl_roster.rpc(Game.roster)
	_save_battle_setup()

## Teams are managed from the Players view: add/remove columns, rename.
## Computer players redistribute into contiguous, even groups (1,2,3 on
## the first team, 4,5,6 on the next...) whenever the layout changes;
## humans always keep the team they picked.
@rpc("any_peer", "call_local", "reliable")
func sv_add_team() -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if team_count >= 24:
		return
	team_count += 1
	team_names.append(char(65 + (team_count - 1) % 24))
	_redistribute_bots()
	cl_teams.rpc(team_names)
	_save_battle_setup()

@rpc("any_peer", "call_local", "reliable")
func sv_remove_team(index: int = -1) -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if team_count <= 2:
		return
	var gone := index if index >= 0 and index < team_count else team_count - 1
	team_names.remove_at(gone)
	team_count -= 1
	for id: String in Game.roster.keys():
		var team := int(Game.roster[id].get("team", -1))
		if team == gone:
			Game.roster[id].team = -1
		elif team > gone:
			Game.roster[id].team = team - 1
	_redistribute_bots()
	cl_teams.rpc(team_names)
	_save_battle_setup()

@rpc("any_peer", "call_local", "reliable")
func sv_rename_team(index: int, new_name: String) -> void:
	if not multiplayer.is_server():
		return
	if index >= 0 and index < team_names.size() and not new_name.strip_edges().is_empty():
		team_names[index] = new_name.strip_edges().left(10)
		cl_teams.rpc(team_names)
		_save_battle_setup()

@rpc("authority", "call_local", "reliable")
func cl_teams(names: Array) -> void:
	client_team_names = names
	if multiplayer.is_server():
		return
	battle_config_changed.emit()

func _redistribute_bots() -> void:
	var ids: Array = _bots.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return int(Game.roster[a].slot) < int(Game.roster[b].slot))
	var group := ceili(float(ids.size()) / float(team_count))
	for i in ids.size():
		Game.roster[ids[i]].team = mini(i / maxi(group, 1), team_count - 1)
	Game.cl_roster.rpc(Game.roster)

func _bot_nearest_enemy(id: String, pos: Vector3, radius: float) -> String:
	var best := ""
	var best_dist := radius
	for other: String in _match_alive.keys():
		if other == id or _downed_ids.has(other) or not _teams_differ(id, other):
			continue
		var other_state: Dictionary = _player_state.get(other, {})
		if other_state.is_empty():
			continue
		var d: float = pos.distance_to(other_state.pos)
		if d < best_dist:
			best_dist = d
			best = other
	return best

func _bot_pick_goal(id: String, bot: Dictionary) -> Vector3:
	var pos: Vector3 = bot.pos
	if match_phase == "BATTLE" and _match_alive.has(id):
		# Storm first: get inside.
		if Vector2(pos.x, pos.z).length() > storm_radius - 8.0:
			var inward := -Vector3(pos.x, 0, pos.z).normalized() * 20.0
			return pos + inward
		# Hurt? Break contact and look for loot instead of trading.
		var hp := int(_player_state.get(id, {}).get("hp", 5))
		if hp <= 2:
			var threat := _bot_nearest_enemy(id, pos, 26.0)
			if threat != "":
				var away := (pos - Vector3(_player_state[threat].pos)).normalized()
				return pos + away * 24.0 + Vector3(randf_range(-5, 5), 0, randf_range(-5, 5))
		# Revive a downed teammate.
		for mate: String in _downed_ids.keys():
			if mate != id and not _teams_differ(id, mate) and _player_state.has(mate) \
					and pos.distance_to(_player_state[mate].pos) < 34.0:
				return _player_state[mate].pos
		# Loot when unarmed.
		if int(bot.weapon) == 13:
			var best_crate := Vector3.INF
			var best_d := 70.0
			for crate: Dictionary in _crates.values():
				var d: float = pos.distance_to(crate.pos)
				if d < best_d:
					best_d = d
					best_crate = crate.pos
			if best_crate != Vector3.INF:
				return best_crate
		# Hunt — swordsmen close in, shooters hold their preferred range.
		var enemy := _bot_nearest_enemy(id, pos, 44.0)
		if enemy != "":
			var epos: Vector3 = _player_state[enemy].pos
			var standoff := 1.2 if int(bot.weapon) == 13 else randf_range(9.0, 14.0)
			return epos + (pos - epos).normalized() * standoff \
				+ Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
	# Otherwise wander somewhere nearby.
	return pos + Vector3(randf_range(-14, 14), 0, randf_range(-14, 14))

## True when a bot can walk from `pos` one step toward `dir` without a
## cliff-face climb or a swim: the ground ahead must be near walkable
## height and dry.
func _bot_step_ok(pos: Vector3, dir: Vector2) -> bool:
	var ahead := Vector2(pos.x, pos.z) + dir * 1.6
	var gy := store.surface_y(int(ahead.x), int(ahead.y))
	if float(gy) - pos.y > 1.6:
		return false
	var ground := store.get_block(Vector3i(int(ahead.x), gy, int(ahead.y)))
	return ground != Blocks.WATER

func _server_tick_bots(delta: float) -> void:
	for id: String in _bots.keys():
		if not Game.roster.has(id):
			continue
		var bot: Dictionary = _bots[id]
		bot.send_t = float(bot.get("send_t", 0.0)) - delta
		bot.shoot_cd = maxf(0.0, float(bot.shoot_cd) - delta)
		bot.think = float(bot.think) - delta
		var pos: Vector3 = bot.pos
		var downed := _downed_ids.has(id)
		if bot.think <= 0.0:
			bot.think = randf_range(0.35, 0.6)
			bot.goal = _bot_pick_goal(id, bot)
		var to_goal: Vector3 = Vector3(bot.goal) - pos
		var flat := Vector2(to_goal.x, to_goal.z)
		if flat.length() > 0.8 and not downed:
			var dir := flat.normalized()
			# Steer around cliffs and water: try straight, then angled
			# detours, before giving up and re-thinking.
			if not _bot_step_ok(pos, dir):
				var found := false
				for turn in [0.8, -0.8, 1.6, -1.6]:
					var side := dir.rotated(turn)
					if _bot_step_ok(pos, side):
						dir = side
						found = true
						break
				if not found:
					bot.think = 0.0
					dir = Vector2.ZERO
			if dir != Vector2.ZERO:
				pos.x += dir.x * 4.4 * delta
				pos.z += dir.y * 4.4 * delta
				bot.yaw = atan2(-dir.x, -dir.y)
			# Barely moving while far from the goal means wedged — re-think.
			bot.moved = float(bot.get("moved", 0.0)) + pos.distance_to(Vector3(bot.get("last_pos", pos)))
			bot.last_pos = pos
			if bot.think <= 0.05 and float(bot.moved) < 0.6 and flat.length() > 3.0:
				bot.goal = pos + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10))
			if bot.think <= 0.05:
				bot.moved = 0.0
		var gy := store.surface_y(int(pos.x), int(pos.z))
		pos.y = lerpf(pos.y, float(gy) + 1.0, minf(1.0, delta * 8.0))
		bot.pos = pos
		var state: Dictionary = _player_state.get(id, {})
		if not state.is_empty():
			state.pos = pos
		# Fight whatever is in range.
		if match_phase == "BATTLE" and _match_alive.has(id) and not downed:
			var enemy := _bot_nearest_enemy(id, pos, 30.0)
			if enemy != "" and bot.shoot_cd <= 0.0:
				var epos: Vector3 = _player_state[enemy].pos
				var dist := pos.distance_to(epos)
				if int(bot.weapon) != 13:
					bot.shoot_cd = 1.1
					cl_orb.rpc(id, pos + Vector3(0, 1.4, 0), (epos - pos).normalized(), int(bot.weapon))
					if randf() < clampf(1.1 - dist / 30.0, 0.15, 0.8):
						_match_hurt(enemy, 1, epos)
				elif dist < 2.6:
					bot.shoot_cd = 0.8
					cl_pos.rpc(id, pos, bot.yaw, 9)
					_match_hurt(enemy, 1, epos)
		if bot.send_t <= 0.0:
			bot.send_t = 1.0 / 12.0
			cl_pos.rpc(id, pos, bot.yaw, 1)

## Battle SETTINGS survive restarts (the world itself never does):
## length, size, loot mode, team layout and the computer players.
func _save_battle_setup() -> void:
	if store == null:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("battle", "minutes", storm_minutes)
	cfg.set_value("battle", "size", battle_size)
	cfg.set_value("battle", "loot", loot_only)
	cfg.set_value("battle", "team_names", team_names)
	cfg.set_value("battle", "bots", _bots.size())
	cfg.set_value("battle", "world", selected_map)
	cfg.save(store.data_dir.path_join("battle.cfg"))

func _load_battle_setup() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(store.data_dir.path_join("battle.cfg")) != OK:
		return
	storm_minutes = float(cfg.get_value("battle", "minutes", storm_minutes))
	battle_size = float(cfg.get_value("battle", "size", battle_size))
	loot_only = bool(cfg.get_value("battle", "loot", loot_only))
	var names: Array = cfg.get_value("battle", "team_names", team_names)
	if names.size() >= 2:
		team_names = names
		team_count = names.size()
	selected_map = str(cfg.get_value("battle", "world", ""))
	if not _known_map(selected_map):
		selected_map = ""
	var bot_count := int(cfg.get_value("battle", "bots", 0))
	for i in mini(bot_count, 23):
		_spawn_bot()
	print("Battle setup restored: %d min, %d blocks, %d teams, %d bots" % [
		int(storm_minutes), int(battle_size), team_count, _bots.size()])

func _is_host(sender: int) -> bool:
	var peer := sender if sender != 0 else multiplayer.get_unique_id()
	return Game.host_peer == 0 or peer == Game.host_peer

@rpc("any_peer", "call_local", "reliable")
func sv_set_loop(on: bool) -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	match_loop = on

func _storm_start() -> float:
	return battle_size * 0.5
const STORM_END := 16.0
var storm_minutes := 5.0
var loot_only := false

var _match_timer := 0.0
var _match_alive: Dictionary = {}   # id -> true while still fighting
var _storm_hurt_ms: Dictionary = {}

## Anyone may re-team a computer player from the lobby.
@rpc("any_peer", "reliable")
func sv_set_bot_team(target_id: String, team: int) -> void:
	if not multiplayer.is_server():
		return
	if Game.roster.has(target_id) and Game.roster[target_id].get("bot", false):
		Game.roster[target_id].team = clampi(team, -1, team_count - 1)
		Game.cl_roster.rpc(Game.roster)

@rpc("any_peer", "reliable")
func sv_match_config(minutes: int, loot: int, size: int = -1) -> void:
	if not multiplayer.is_server() or not (match_phase in ["IDLE", "LOBBY"]) \
			or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if minutes > 0:
		storm_minutes = clampf(float(minutes), 2.0, 99.0)
	if loot >= 0:
		loot_only = loot == 1
	if size > 0:
		battle_size = clampf(float(size), 25.0, 400.0)
	cl_battle_config.rpc(int(storm_minutes), int(battle_size), loot_only)
	_save_battle_setup()

@rpc("any_peer", "reliable")
func sv_match_start(_slot: int) -> void:
	if not multiplayer.is_server() or match_phase != "IDLE" or Game.roster.is_empty() \
			or not _is_host(multiplayer.get_remote_sender_id()):
		return
	# The battle plays on the SELECTED world — switch now if it differs.
	if not selected_map.is_empty() and selected_map != store.current_map_key \
			and not (selected_map == store.theme and store.current_map_key.is_empty()):
		_do_world_reset(selected_map)
	# Every human gets a team the moment the lobby opens; nobody is ever
	# team-less (they can still move themselves in the menu).
	_assign_stray_humans()
	match_phase = "LOBBY"
	_match_timer = LOBBY_SECONDS
	print("Battle royale lobby open")
	cl_match.rpc("LOBBY", LOBBY_SECONDS)

func _assign_stray_humans() -> void:
	var counts: Array[int] = []
	counts.resize(team_count)
	for id: String in Game.roster.keys():
		var team := int(Game.roster[id].get("team", -1))
		if team >= 0 and team < team_count:
			counts[team] += 1
	var changed := false
	for id: String in Game.roster.keys():
		if int(Game.roster[id].get("team", -1)) >= 0:
			continue
		var best := 0
		for t in team_count:
			if counts[t] < counts[best]:
				best = t
		Game.roster[id].team = best
		counts[best] += 1
		changed = true
	if changed:
		Game.cl_roster.rpc(Game.roster)

## World SELECTION (host): remembered, shown highlighted everywhere, and
## applied when the next battle starts — never an instant switch.
@rpc("any_peer", "call_local", "reliable")
func sv_select_world(map_name: String) -> void:
	if not multiplayer.is_server() or not _is_host(multiplayer.get_remote_sender_id()):
		return
	if not _known_map(map_name):
		return
	selected_map = map_name
	cl_world_sel.rpc(selected_map)
	_save_battle_setup()

@rpc("authority", "call_local", "reliable")
func cl_world_sel(map_name: String) -> void:
	client_world = map_name
	if not multiplayer.is_server():
		map_list_changed.emit()

func _known_map(map_name: String) -> bool:
	if map_name in ["classic", "desert", "isles", "castles", "city", "sky"]:
		return true
	for entry in ChunkStore.list_maps():
		if str(entry.key) == map_name:
			return true
	return false

func _server_tick_match(delta: float) -> void:
	if match_phase == "IDLE":
		return
	_match_timer -= delta
	match match_phase:
		"LOBBY":
			if _match_timer <= 0.0:
				_server_match_drop()
		"DROP":
			if _match_timer <= 0.0:
				match_phase = "BATTLE"
				_match_timer = storm_minutes * 60.0
				cl_match.rpc("BATTLE", _match_timer)
		"BATTLE":
			if storm_minutes >= 59.0:
				# Unlimited: the storm never closes and the match only ends
				# when one team is left standing.
				_match_timer = 9999.0
			var frac := 1.0 - clampf(_match_timer / (storm_minutes * 60.0), 0.0, 1.0)
			storm_radius = lerpf(_storm_start(), STORM_END, frac)
			cl_storm.rpc(storm_radius)
			_storm_damage()
			_storm_bite()
			_tick_revives()
			_check_match_win()
			if _match_timer <= 0.0:
				_server_match_end(-1)
		"END":
			if _match_timer <= 0.0:
				var humans := false
				for id: String in Game.roster.keys():
					if not bool(Game.roster[id].get("bot", false)):
						humans = true
						break
				if match_loop and humans:
					match_phase = "COUNTDOWN"
					_match_timer = 20.0
					cl_match.rpc("COUNTDOWN", 20.0)
				else:
					match_phase = "IDLE"
					cl_match.rpc("IDLE", 0.0)
		"COUNTDOWN":
			if _match_timer <= 0.0:
				# Fresh copy of the SAME map, then straight into a new lobby.
				_do_world_reset(selected_map if not selected_map.is_empty() \
					else store.current_map_key)
				match_phase = "LOBBY"
				_match_timer = LOBBY_SECONDS
				cl_match.rpc("LOBBY", LOBBY_SECONDS)
				print("Battle royale loop: fresh lobby open")

## Everyone gets a team (auto-balanced if unpicked), full hearts, and a drop
## point high above a spread ring. Gliding down is automatic.
func _server_match_drop() -> void:
	match_phase = "DROP"
	_match_timer = 6.0
	_match_alive.clear()
	_downed_ids.clear()
	_revive_progress.clear()
	var counts: Array[int] = []
	counts.resize(team_count)
	for id: String in Game.roster.keys():
		var team := int(Game.roster[id].get("team", -1))
		if team >= team_count:
			Game.roster[id].team = -1
		elif team >= 0:
			counts[team] += 1
	var i := 0
	for id: String in Game.roster.keys():
		var entry: Dictionary = Game.roster[id]
		if int(entry.get("team", -1)) < 0:
			var best := 0
			for t in team_count:
				if counts[t] < counts[best]:
					best = t
			entry.team = best
			counts[best] += 1
		_match_alive[id] = true
		# World resets between battles can drop server-side state for
		# bots — recreate instead of crashing the match start.
		if not _player_state.has(id):
			_player_state[id] = {"pos": Vector3(spawn_pos), "treasures": 0,
				"name": str(entry.get("name", "?")), "hp": MATCH_HP}
		var state: Dictionary = _player_state[id]
		state.hp = MATCH_HP
		cl_hearts.rpc(id, MATCH_HP)
		var angle := float(i) * TAU / maxf(Game.roster.size(), 1.0) + randf() * 0.3
		var dist := randf_range(_storm_start() * 0.25, _storm_start() * 0.42)
		var drop := Vector3(cos(angle) * dist, WorldGen.CHUNK_H - 4, sin(angle) * dist)
		cl_drop.rpc(id, drop, loot_only)
		if _bots.has(id):
			_bots[id].pos = drop
			_bots[id].weapon = 13
			_player_state[id].pos = drop
		i += 1
	# Fresh loot everywhere so late matches aren't scavenged dry — the
	# count scales with the battle square's area.
	_crates.clear()
	var crate_count := clampi(maxi(int(pow(_storm_start() / 125.0, 2.0) * 40.0),
		Game.roster.size() * 4), 8, 140)
	for n in crate_count:
		var langle := randf() * TAU
		var ldist := sqrt(randf()) * (_storm_start() * 0.85)
		var lx := int(cos(langle) * ldist)
		var lz := int(sin(langle) * ldist)
		var ly := store.surface_y(lx, lz)
		if ly > 2 and ly < WorldGen.CHUNK_H - 6 \
				and store.get_block(Vector3i(lx, ly, lz)) != Blocks.WATER \
				and (store.theme != "sky" or ly > WorldGen.SEA_LEVEL + 6):
			var lpool := [1, 1, 2, 2, 5, 6, 7, 8, 9, 9, 11, 11, 12, 12, 14, 14, 15]
			_crates[_next_crate_id] = {"weapon": lpool[randi() % lpool.size()],
				"pos": Vector3(lx + 0.5, ly + 1.0, lz + 0.5)}
			_next_crate_id += 1
	_broadcast_crates()
	Game.cl_roster.rpc(Game.roster)
	storm_radius = _storm_start()
	clock = 0.79  # dusk falls as the match starts: hunt loot in the dark
	cl_clock.rpc(clock)
	cl_match.rpc("DROP", 6.0)
	print("Battle royale: dropping %d players" % _match_alive.size())

func _storm_damage() -> void:
	var now := Time.get_ticks_msec()
	for id: String in _match_alive.keys():
		var state: Dictionary = _player_state.get(id, {})
		if state.is_empty() or now < int(_storm_hurt_ms.get(id, 0)):
			continue
		var pos: Vector3 = state.pos
		# The first dozen blocks outside the wall are a warning zone; deeper
		# than that the storm hits hard.
		if Vector2(pos.x, pos.z).length() > storm_radius + 12.0:
			_storm_hurt_ms[id] = now + 1600
			state.hp = int(state.get("hp", MATCH_HP)) - 1
			cl_hearts.rpc(id, state.hp)
			# No knockback from the storm: pushing players while they're
			# already outside fed back into more storm damage and once
			# launched Ian 142 km off the map.
			if state.hp <= 0:
				_match_eliminate(id)

var _next_bite_ms := 0

## The storm chews the world: surface blocks just outside the wall pop
## away, so the losing ground visibly crumbles.
func _storm_bite() -> void:
	var now := Time.get_ticks_msec()
	if now < _next_bite_ms:
		return
	_next_bite_ms = now + 500
	for n in 6:
		var a := randf() * TAU
		var r := storm_radius + randf_range(2.0, 14.0)
		var wx := int(cos(a) * r)
		var wz := int(sin(a) * r)
		var y := store.surface_y(wx, wz)
		if y <= WorldGen.SEA_LEVEL or y >= WorldGen.CHUNK_H - 2:
			continue
		var pos := Vector3i(wx, y, wz)
		if store.get_block(pos) == Blocks.AIR:
			continue
		store.set_block(pos, Blocks.AIR)
		cl_edit.rpc(pos, Blocks.AIR, "storm")
		if randf() < 0.12:
			cl_boom_fx.rpc(pos)

var _downed_ids: Dictionary = {}   # id -> downed_at_msec
var _revive_progress: Dictionary = {}

## Down-but-not-out: if living teammates remain you crawl and can be
## revived (teammate stands close for ~3s); alone, you're out.
func _match_eliminate(id: String) -> void:
	if not _match_alive.has(id) or _downed_ids.has(id):
		return
	var team := int(Game.roster.get(id, {}).get("team", -1))
	var has_standing_mate := false
	for other: String in _match_alive.keys():
		if other != id and not _downed_ids.has(other) \
				and int(Game.roster.get(other, {}).get("team", -2)) == team:
			has_standing_mate = true
	if has_standing_mate:
		_downed_ids[id] = Time.get_ticks_msec()
		cl_downed_state.rpc(id, true)
		return
	_match_alive.erase(id)
	_downed_ids.erase(id)
	cl_eliminated.rpc(id)
	_check_match_win()

func _tick_revives() -> void:
	var now := Time.get_ticks_msec()
	for id: String in _downed_ids.keys().duplicate():
		# Bleed out after 45s down.
		if now - int(_downed_ids[id]) > 45_000:
			_downed_ids.erase(id)
			_match_alive.erase(id)
			cl_eliminated.rpc(id)
			_check_match_win()
			continue
		var team := int(Game.roster.get(id, {}).get("team", -1))
		var pos: Vector3 = _player_state.get(id, {}).get("pos", Vector3.ZERO)
		var mate_close := false
		for other: String in _match_alive.keys():
			if other == id or _downed_ids.has(other):
				continue
			if int(Game.roster.get(other, {}).get("team", -2)) == team \
					and Vector3(_player_state.get(other, {}).get("pos", Vector3.INF)).distance_to(pos) < 3.0:
				mate_close = true
		if mate_close:
			_revive_progress[id] = float(_revive_progress.get(id, 0.0)) + 0.35
			# Reviving is LOUD — everyone nearby hears the alarm.
			cl_revive_noise.rpc(pos)
			if _revive_progress[id] >= 6.0:
				_downed_ids.erase(id)
				_revive_progress.erase(id)
				var state: Dictionary = _player_state.get(id, {})
				if not state.is_empty():
					state.hp = 3
				cl_hearts.rpc(id, 2)
				cl_downed_state.rpc(id, false)
				Sfx.play("collect")
		else:
			_revive_progress.erase(id)

func _check_match_win() -> void:
	var teams_alive: Dictionary = {}
	for id: String in _match_alive.keys():
		if Game.roster.has(id):
			teams_alive[int(Game.roster[id].get("team", 0))] = true
	if match_phase != "BATTLE":
		return
	var humans_alive := false
	for id: String in _match_alive.keys():
		if Game.roster.has(id) and not bool(Game.roster[id].get("bot", false)) \
				and not _downed_ids.has(id):
			humans_alive = true
			break
	if not humans_alive:
		_server_match_end(-2)  # every human is out: nobody wins
		return
	if teams_alive.size() <= 1:
		var winner := -1
		for t in teams_alive.keys():
			winner = t
		_server_match_end(winner)

func _server_match_end(winner: int) -> void:
	match_phase = "END"
	_match_timer = 10.0
	print("Battle royale over: team %d" % winner)
	cl_match_end.rpc(winner)

## Match damage between enemies (orbs and blast splash call this).
func _match_hurt(id: String, amount: int, from_pos: Vector3) -> void:
	if match_phase != "BATTLE" or not _match_alive.has(id):
		return
	if _downed_ids.has(id):
		return  # ghosts are untouchable — revive or bleed out, nothing else
	var now := Time.get_ticks_msec()
	if now - int(_last_hit_ms.get(id, -MERCY_MS)) < MERCY_MS:
		return  # mercy window: recently hit, briefly untouchable
	_last_hit_ms[id] = now
	var state: Dictionary = _player_state.get(id, {})
	if state.is_empty():
		return
	state.hp = int(state.get("hp", MATCH_HP)) - amount
	cl_hearts.rpc(id, state.hp)
	cl_bonk.rpc(id, from_pos)
	if state.hp <= 0:
		_match_eliminate(id)

func _teams_differ(a: String, b: String) -> bool:
	if not (Game.roster.has(a) and Game.roster.has(b)):
		return true
	return int(Game.roster[a].get("team", -1)) != int(Game.roster[b].get("team", -2))

@rpc("authority", "reliable")
func cl_match(phase: String, seconds: float) -> void:
	match_phase = phase
	match_seconds = seconds
	if chunks != null:
		chunks.match_mode = phase != "IDLE"
		if phase == "LOBBY":
			chunks.prefetch(15)  # whole arena in RAM before the drop
	match_changed.emit()
	if phase == "DROP":
		Sfx.play("whoosh")
	elif phase == "BATTLE":
		Sfx.play("boom", -8.0)

@rpc("authority", "reliable")
func cl_storm(radius: float) -> void:
	storm_radius = radius
	storm_changed.emit()

@rpc("authority", "reliable")
func cl_drop(id: String, pos: Vector3, loot := false) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			child.teleport(pos)
			child.start_drop_glide()
			child.fly_mode = false
			# PUBG rules: everyone drops with just a sword — the rest is loot.
			child.slots = [{"kind": "weapon", "id": 13}]
			for i in 7:
				child.slots.append({"kind": "empty", "id": 0})
			child.selected_slot = 0
			child.downed = false

@rpc("authority", "reliable")
func cl_downed_state(id: String, is_down: bool) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id:
			child.downed = is_down
			child.set_ghost(is_down)
			if child.is_local and is_down:
				Sfx.play("drop")

@rpc("authority", "unreliable")
func cl_revive_noise(pos: Vector3) -> void:
	var dist := 1e9
	for child in players.get_children():
		if child is Player and child.is_local:
			dist = minf(dist, child.position.distance_to(pos))
	if dist < 40.0:
		Sfx.play("warp", -2.0 - dist * 0.4, 0.6)

@rpc("authority", "reliable")
func cl_eliminated(id: String) -> void:
	hearts[id] = 0
	hearts_changed.emit()
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			child.teleport(Vector3(spawn_pos) + Vector3(0.5, 2.0, 0.5))
			Sfx.play("drop")

signal match_won(winner: int)

@rpc("authority", "reliable")
func cl_match_end(winner: int) -> void:
	match_phase = "END"
	match_changed.emit()
	match_won.emit(winner)
	Sfx.play("cheer")

@rpc("any_peer", "reliable")
func sv_survival_start(_slot: int) -> void:
	if not multiplayer.is_server() or survival_active or Game.roster.is_empty():
		return
	survival_active = true
	survival_wave = 1
	_monsters.clear()
	_downed.clear()
	_bonked_count = 0
	_survival_started_ms = Time.get_ticks_msec()
	_wave_started_ms = _survival_started_ms
	for id: String in Game.roster.keys():
		var state: Dictionary = _player_state.get(id, {})
		if not state.is_empty():
			state.hp = 5
	print("Survival started with %d players" % Game.roster.size())
	cl_survival.rpc(true, 0.0, 0)
	cl_wave.rpc(1)
	for id: String in Game.roster.keys():
		cl_hearts.rpc(id, 5)

func _server_end_survival() -> void:
	var seconds := (Time.get_ticks_msec() - _survival_started_ms) / 1000.0
	survival_active = false
	_monsters.clear()
	cl_monsters.rpc([])
	cl_survival.rpc(false, seconds, _bonked_count)
	print("Survival over: %.0fs, %d bonked" % [seconds, _bonked_count])

@rpc("any_peer", "reliable")
func sv_zap(slot: int, monster_id: int) -> void:
	if not multiplayer.is_server() or not survival_active:
		return
	var id := Game.player_id(multiplayer.get_remote_sender_id(), slot)
	var state: Dictionary = _player_state.get(id, {})
	if state.is_empty() or not _monsters.has(monster_id):
		return
	var monster: Dictionary = _monsters[monster_id]
	if Vector3(state.pos).distance_to(monster.pos) > 16.0:
		return
	monster.hp = int(monster.hp) - 1
	var dead: bool = monster.hp <= 0
	if dead:
		_monsters.erase(monster_id)
		_bonked_count += 1
	cl_zap_hit.rpc(monster_id, dead)

func _server_tick_survival() -> void:
	if not survival_active and _monsters.is_empty():
		return
	var now := Time.get_ticks_msec()
	# Escalate every 18s (raids only; whistled wild Grumps just roam).
	if survival_active and now - _wave_started_ms > 18_000:
		_wave_started_ms = now
		survival_wave += 1
		cl_wave.rpc(survival_wave)
	# Alive participants.
	var alive: Array = []
	for id: String in Game.roster.keys():
		if not _downed.has(id) and _player_state.has(id):
			alive.append(id)
	if alive.is_empty() or Game.roster.is_empty():
		if survival_active:
			_server_end_survival()
		else:
			_monsters.clear()
			cl_monsters.rpc([])
		return
	# Keep the horde growing.
	if survival_active:
		var cap := mini(4 + survival_wave * 2, 26)
		if _monsters.size() < cap:
			_spawn_monster(alive)
	# March.
	var speed := minf(1.5 + survival_wave * 0.06, 2.8) * 0.33
	var frozen_check := Time.get_ticks_msec()
	for monster_id: int in _monsters.keys():
		var monster: Dictionary = _monsters[monster_id]
		if frozen_check < int(monster.get("frozen_until", 0)):
			continue
		var target := _nearest_alive(monster.pos, alive)
		if target.is_empty():
			continue
		var target_pos: Vector3 = _player_state[target].pos
		var step: Vector3 = target_pos - monster.pos
		step.y = 0
		if step.length() > 0.6:
			step = step.normalized() * speed
			# Grumps can't jump: they step up at most one block, so walls
			# and forts genuinely keep them out. They wade water fine.
			# Grumps scale walls and scuttle over roofs — height is no refuge.
			var attempt: Vector3 = monster.pos + step
			var floor_y := store.surface_y(int(attempt.x), int(attempt.z))
			var rise: float = float(floor_y) + 1.0 - monster.pos.y
			if rise > 0.9:
				attempt = monster.pos
				attempt.y += minf(rise, speed * 1.4)  # climbing
			else:
				attempt.y = float(floor_y) + 1.0
			monster.pos = attempt
		# Bonk!
		if now >= int(monster.next_bonk_ms) 				and Vector3(_player_state[target].pos).distance_to(monster.pos) < 1.5:
			monster.next_bonk_ms = now + 1200
			var state: Dictionary = _player_state[target]
			cl_bonk.rpc(target, monster.pos)
			if not survival_active:
				continue
			state.hp = int(state.get("hp", 5)) - 1
			cl_hearts.rpc(target, state.hp)
			if state.hp <= 0:
				_downed[target] = true
				cl_downed.rpc(target)
	# Broadcast positions.
	var payload: Array = []
	for monster_id: int in _monsters.keys():
		payload.append([monster_id, _monsters[monster_id].pos])
	cl_monsters.rpc(payload)

func _nearest_alive(from: Vector3, alive: Array) -> String:
	var best := ""
	var best_dist := 1e9
	for id: String in alive:
		var dist: float = Vector3(_player_state[id].pos).distance_to(from)
		if dist < best_dist:
			best_dist = dist
			best = id
	return best

## Grumps rise from low ground and water, never from up on the fort.
func _spawn_monster(alive: Array) -> void:
	var anchor_id: String = alive[randi() % alive.size()]
	var anchor: Vector3 = _player_state[anchor_id].pos
	var best_pos := Vector3.INF
	var best_score := -1e9
	for i in 14:
		var angle := randf() * TAU
		var dist := randf_range(16.0, 28.0)
		var wx := int(anchor.x + cos(angle) * dist)
		var wz := int(anchor.z + sin(angle) * dist)
		var y := store.surface_y(wx, wz)
		if y <= 1 or y >= WorldGen.CHUNK_H - 6:
			continue
		var score := anchor.y - float(y)
		if store.get_block(Vector3i(wx, y, wz)) == Blocks.WATER:
			score += 3.0
		if score > best_score:
			best_score = score
			best_pos = Vector3(wx + 0.5, y + 1.0, wz + 0.5)
	if best_pos == Vector3.INF or best_score < -4.0:
		return
	_monsters[_next_monster_id] = {"pos": best_pos, "hp": 2 + survival_wave / 3,
		"next_bonk_ms": 0}
	_next_monster_id += 1

## Supply crates: keep ~14 scattered on land near-ish players; touching one
## hands over its weapon and it respawns somewhere else.
var _crates: Dictionary = {}
var _next_crate_id := 1

func _server_tick_crates() -> void:
	var positions: Array = []
	for state: Dictionary in _player_state.values():
		positions.append(state.pos)
	if positions.is_empty():
		return
	if _crates.size() < 14:
		var anchor: Vector3 = positions[randi() % positions.size()]
		var angle := randf() * TAU
		var dist := randf_range(14.0, 60.0)
		var wx := int(anchor.x + cos(angle) * dist)
		var wz := int(anchor.z + sin(angle) * dist)
		var y := store.surface_y(wx, wz)
		if y > 2 and y < WorldGen.CHUNK_H - 6 \
				and store.get_block(Vector3i(wx, y, wz)) != Blocks.WATER \
				and (store.theme != "sky" or y > WorldGen.SEA_LEVEL + 6):
			# Rarer weapons show up less often.
			var pool := [1, 1, 2, 2, 5, 6, 7, 8, 9, 9, 11, 11, 12, 12, 14, 15]
			_crates[_next_crate_id] = {"weapon": pool[randi() % pool.size()],
				"pos": Vector3(wx + 0.5, y + 1.0, wz + 0.5)}
			_next_crate_id += 1
			_broadcast_crates()
	# Pickup by touch.
	for id: String in _player_state.keys():
		var ppos: Vector3 = _player_state[id].pos
		for crate_id: int in _crates.keys():
			if ppos.distance_to(_crates[crate_id].pos) < 1.6:
				var weapon: int = _crates[crate_id].weapon
				_crates.erase(crate_id)
				cl_crate_taken.rpc(id, weapon)
				if _bots.has(id):
					_bots[id].weapon = weapon
				_broadcast_crates()
				break

func _broadcast_crates() -> void:
	var payload: Array = []
	for crate_id: int in _crates.keys():
		payload.append([crate_id, _crates[crate_id].weapon, _crates[crate_id].pos])
	cl_crates.rpc(payload)

@rpc("authority", "reliable")
func cl_crates(payload: Array) -> void:
	if crates != null:
		crates.update_crates(payload)

@rpc("authority", "reliable")
func cl_crate_taken(id: String, weapon: int) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			# Into the first non-weapon slot (or replace the last slot).
			var target := 7
			for i in 8:
				if child.slots[i].kind == "empty":
					target = i
					break
			if target == 7 and child.slots[7].kind != "empty":
				for i in 8:
					if child.slots[i].kind != "weapon":
						target = i
						break
			child.slots[target] = {"kind": "weapon", "id": weapon}
			child.selected_slot = target
			Sfx.play("collect")
	if crates != null:
		update_crates_after_take()

func update_crates_after_take() -> void:
	pass  # server broadcast handles the visual removal

func _server_tick_critters() -> void:
	_server_tick_survival()
	_server_tick_crates()
	var player_positions: Array = []
	for state: Dictionary in _player_state.values():
		player_positions.append(state.pos)
	if player_positions.is_empty():
		if not _critters.is_empty():
			_critters.clear()
		return
	var night := clock > 0.78 or clock < 0.22
	# Cull the far and the out-of-season.
	for id: int in _critters.keys().duplicate():
		var critter: Dictionary = _critters[id]
		var near := false
		for pos: Vector3 in player_positions:
			if pos.distance_to(critter.pos) < 60.0:
				near = true
				break
		if not near or (critter.kind == CritterView.FIREFLY and not night):
			_critters.erase(id)
	# Keep the population up around each player.
	if _critters.size() < mini(MAX_CRITTERS, CRITTERS_PER_PLAYER * player_positions.size()):
		var anchor: Vector3 = player_positions[randi() % player_positions.size()]
		_try_spawn_critter(anchor, night)
	# Wander + flee.
	var ridden := {}
	for rider_id in riding_map.keys():
		ridden[int(riding_map[rider_id])] = rider_id
	for id: int in _critters.keys():
		if ridden.has(id):
			# A ridden dragon goes wherever its rider goes.
			var rider: Dictionary = _player_state.get(ridden[id], {})
			if not rider.is_empty():
				_critters[id].pos = Vector3(rider.pos) + Vector3(0, -1.6, 0)
			continue
		_move_critter(_critters[id], player_positions)
	# Broadcast compact state.
	var payload: Array = []
	for id: int in _critters.keys():
		var critter: Dictionary = _critters[id]
		payload.append([id, critter.kind, critter.pos])
	cl_critters.rpc(payload)

func _try_spawn_critter(anchor: Vector3, night: bool) -> void:
	var angle := randf() * TAU
	var dist := randf_range(10.0, 26.0)
	var wx := int(anchor.x + cos(angle) * dist)
	var wz := int(anchor.z + sin(angle) * dist)
	var y := store.surface_y(wx, wz)
	if y <= 1 or y >= WorldGen.CHUNK_H - 4:
		return
	var ground := store.get_block(Vector3i(wx, y, wz))
	var kind := -1
	if WorldGen.hash01(wx, wz, 501) < 0.02:
		kind = CritterView.DRAGON
	elif WorldGen.hash01(wx, wz, 500) < 0.15:
		kind = CritterView.BIRD
	elif ground == Blocks.WATER:
		kind = CritterView.DUCK
	elif ground == Blocks.SAND:
		kind = CritterView.CRAB
	elif ground == Blocks.SNOW or (ground == Blocks.STONE and y > WorldGen.SEA_LEVEL + 14):
		kind = CritterView.PENGUIN
	elif ground == Blocks.GRASS:
		if night:
			kind = CritterView.FIREFLY if randf() < 0.6 else CritterView.BUNNY
		elif y <= WorldGen.SEA_LEVEL + 2 and randf() < 0.35:
			kind = CritterView.FROG
		else:
			var roll := randf()
			if roll < 0.28:
				kind = CritterView.SHEEP
			elif roll < 0.48:
				kind = CritterView.BUNNY
			elif roll < 0.64:
				kind = CritterView.CHICKEN
			elif roll < 0.78:
				kind = CritterView.DEER
			else:
				kind = CritterView.BUTTERFLY
	if kind < 0:
		return
	var pos := Vector3(wx + 0.5, y + 1.0, wz + 0.5)
	_critters[_next_critter_id] = {
		"kind": kind, "pos": pos, "target": pos,
		"speed": [1.2, 2.2, 1.6, 0.9, 1.1, 1.4, 0.8, 1.3, 1.8, 0.9, 3.0, 2.4][kind],
		"think": 0.0,
	}
	_next_critter_id += 1

func _move_critter(critter: Dictionary, player_positions: Array) -> void:
	var delta := 0.33
	# Flee players who get too close (except butterflies, who don't care).
	if critter.kind != CritterView.BUTTERFLY:
		for pos: Vector3 in player_positions:
			if pos.distance_to(critter.pos) < 2.6:
				var away: Vector3 = (critter.pos - pos)
				away.y = 0
				critter.target = critter.pos + away.normalized() * 7.0
				critter.think = 3.0
				break
	critter.think -= delta
	if critter.think <= 0.0:
		critter.think = randf_range(2.0, 5.0)
		var angle := randf() * TAU
		critter.target = critter.pos + Vector3(cos(angle), 0, sin(angle)) * randf_range(2.0, 8.0)
	var to_target: Vector3 = critter.target - critter.pos
	to_target.y = 0
	if to_target.length() > 0.3:
		var speed: float = critter.speed
		var step: Vector3 = to_target.limit_length(speed * delta)
		var next: Vector3 = critter.pos + step
		var y := store.surface_y(int(next.x), int(next.z))
		var ground := store.get_block(Vector3i(int(next.x), y, int(next.z)))
		if critter.kind == CritterView.DRAGON:
			next.y = float(y) + 1.0
			critter.pos = next
			return
		if critter.kind == CritterView.BIRD:
			next.y = float(y) + 1.0  # view adds soaring height
			critter.pos = next
			return
		if critter.kind == CritterView.DUCK:
			if ground != Blocks.WATER:
				critter.think = 0.0
				return
			next.y = float(y) + 0.9
		else:
			if ground == Blocks.WATER or absf(float(y) + 1.0 - critter.pos.y) > 2.2:
				critter.think = 0.0
				return
			next.y = float(y) + 1.0
		critter.pos = next

# ------------------------------------------------------------------
# Client
# ------------------------------------------------------------------

func _client_setup() -> void:
	chunks = ChunkView.new()
	chunks.name = "Chunks"
	chunks.world = self
	add_child(chunks)
	players = Node3D.new()
	players.name = "Players"
	add_child(players)
	critter_view = CritterView.new()
	critter_view.name = "Critters"
	add_child(critter_view)
	monster_view = MonsterView.new()
	monster_view.name = "Monsters"
	add_child(monster_view)
	orbs = OrbView.new()
	orbs.name = "Orbs"
	add_child(orbs)
	crates = CrateView.new()
	crates.name = "Crates"
	add_child(crates)
	_storm_wall = MeshInstance3D.new()
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = 1.0
	wall_mesh.bottom_radius = 1.0
	# Tube only — caps would draw a red roof over the whole arena.
	wall_mesh.cap_top = false
	wall_mesh.cap_bottom = false
	# A 12-block wall you can see marching in, not a full-sky red curtain.
	wall_mesh.height = 12.0
	wall_mesh.radial_segments = 96
	_storm_wall.mesh = wall_mesh
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.75, 0.12, 0.1, 0.82)
	wall_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wall_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_storm_wall.material_override = wall_mat
	_storm_wall.visible = false
	add_child(_storm_wall)
	storm_changed.connect(func() -> void:
		_storm_wall.visible = match_phase == "BATTLE"
		_storm_wall.scale = Vector3(storm_radius, 1.0, storm_radius)
		_storm_wall.position = Vector3(0, float(WorldGen.SEA_LEVEL) + 8.0, 0))
	match_changed.connect(func() -> void:
		if match_phase != "BATTLE":
			_storm_wall.visible = false)
	sky = DayNight.new()
	sky.name = "Sky"
	add_child(sky)
	chunks.first_chunks_ready.connect(func() -> void:
		if not _ready_announced:
			_ready_announced = true
			world_ready.emit())
	var focus_timer := Timer.new()
	focus_timer.wait_time = 0.4
	focus_timer.timeout.connect(_client_update_focus)
	add_child(focus_timer)
	focus_timer.start()
	Game.roster_changed.connect(_client_sync_players)
	_client_sync_players()
	sv_hello.rpc_id(1)

## Keep one Player node per roster entry; local ones get their InputSlot and
## ask the server where they should stand (saved spot or the spawn).
func _client_sync_players() -> void:
	if multiplayer == null or multiplayer.multiplayer_peer == null or players == null:
		return  # tearing down after a lost connection
	var me := multiplayer.get_unique_id()
	var wanted := {}
	for id: String in Game.roster.keys():
		var entry: Dictionary = Game.roster[id]
		wanted[id] = true
		var existing: Player = null
		for child in players.get_children():
			if child is Player and child.player_id == id:
				existing = child
				break
		if existing != null:
			existing.refresh_from_roster(entry)
			continue
		var is_local: bool = entry.peer == me and Game.local_inputs.has(entry.slot)
		var player := Player.new()
		player.name = "P_" + id.replace(":", "_")
		var input_slot: InputSlot = Game.local_inputs.get(entry.slot) if is_local else null
		player.setup(id, entry, is_local, input_slot, self)
		players.add_child(player)
		if is_local and input_slot is BotSlot:
			var brain := BotBrain.new()
			brain.player = player
			brain.bot = input_slot
			player.add_child(brain)
		if is_local:
			sv_where.rpc_id(1, int(entry.slot))
			Sfx.play("join")
	for child in players.get_children():
		if child is Player and not wanted.has(child.player_id):
			child.queue_free()

func _client_update_focus() -> void:
	var focus: Array = []
	for child in players.get_children():
		if child is Player and child.is_local:
			focus.append(child.position)
	if focus.is_empty():
		focus.append(Vector3(spawn_pos))
	chunks.set_focus(focus)
	if sky != null:
		sky.set_clock(clock)

func request_chunks(batch: Array) -> void:
	sv_request_chunks.rpc_id(1, batch)

func send_pos(slot: int, pos: Vector3, yaw: float, anim: int) -> void:
	sv_pos.rpc_id(1, slot, pos, yaw, anim)

func send_edit(slot: int, pos: Vector3i, block: int) -> void:
	# Predict locally: the block changes THIS frame (with an immediate
	# synchronous remesh of its chunk) instead of waiting for the server
	# echo to fight through the mesh queue. The echo re-applies the same
	# value, which is a no-op visually.
	if chunks != null:
		chunks.apply_edit_now(pos, block)
	sv_edit.rpc_id(1, slot, pos, block)

@rpc("authority", "reliable")
func cl_overview(bytes: PackedByteArray) -> void:
	overview = bytes

@rpc("authority", "reliable")
func cl_battle_config(minutes: int, size: int, loot: bool) -> void:
	client_minutes = minutes
	client_size = size
	client_loot = loot
	battle_config_changed.emit()

@rpc("authority", "reliable")
func cl_map_list(maps: Array) -> void:
	map_list = maps
	map_list_changed.emit()

@rpc("authority", "reliable")
func cl_world_info(p_spawn: Vector3i, p_clock: float, p_source: String) -> void:
	spawn_pos = p_spawn
	clock = p_clock
	source = p_source
	print("World info: spawn %s, clock %.2f, source %s" % [spawn_pos, clock, source])
	_client_update_focus()

@rpc("authority", "reliable")
func cl_chunk(cx: int, cz: int, blob: PackedByteArray) -> void:
	if chunks != null:
		chunks.receive_chunk(cx, cz, blob)

@rpc("authority", "reliable")
func cl_where(slot: int, pos: Vector3, count: int) -> void:
	var id := Game.player_id(multiplayer.get_unique_id(), slot)
	treasures[id] = count
	for child in players.get_children():
		if child is Player and child.player_id == id:
			child.teleport(pos)
	treasures_changed.emit()

@rpc("authority", "unreliable_ordered")
func cl_pos(id: String, pos: Vector3, yaw: float, anim: int) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and not child.is_local:
			child.remote_update(pos, yaw, anim)

func _nearest_local_dist(pos: Vector3) -> float:
	var best := 999.0
	if players == null:
		return best
	for child in players.get_children():
		if child is Player and child.is_local:
			best = minf(best, child.position.distance_to(pos))
	return best

@rpc("authority", "reliable")
func cl_edit(pos: Vector3i, block: int, by_id: String) -> void:
	if chunks == null:
		return
	var old := chunks.apply_edit(pos, block)
	edit_applied.emit(pos, block, by_id)
	if by_id.is_empty():
		return  # world magic (tree growth, dawn flowers) is quiet
	# Block sounds fall off with distance from the nearest local player
	# (the storm chews terrain constantly — it should be a distant
	# rumble, not a full-volume drumbeat everywhere).
	var edit_dist := _nearest_local_dist(Vector3(pos))
	var edit_vol := -edit_dist * 0.7
	if block == Blocks.AIR:
		if old == Blocks.CONFETTI:
			# Party popper! Confetti everywhere and a little cheer.
			Sfx.play("cheer", edit_vol)
			for color in [Color("ff6b6b"), Color("ffd166"), Color("4a9df8"), Color("ef8fc0")]:
				_burst_particles(pos, color)
			_flash_light(Vector3(pos) + Vector3(0.5, 0.5, 0.5), Color("ffd166"), 3.0)
		elif old > 0 and Blocks.is_collectible(old):
			Sfx.play("collect", edit_vol)
		elif edit_dist < 55.0:
			Sfx.play("dig", edit_vol)
		if old > 0 and old != Blocks.CONFETTI:
			_burst_particles(pos, Blocks.color_of(old))
	elif edit_dist < 55.0:
		Sfx.play("place", edit_vol)

## Mixed-block bulk change (structure stamps).
@rpc("authority", "reliable")
func cl_edits(pairs: Array) -> void:
	if chunks == null:
		return
	for entry in pairs:
		if entry is Array and entry.size() == 2 and entry[0] is Vector3i:
			chunks.apply_edit(entry[0], entry[1])
	Sfx.play("place")
	Sfx.play("whoosh", -8.0)

@rpc("authority", "reliable")
func cl_survival(active: bool, seconds: float, bonked: int) -> void:
	survival_active = active
	if active:
		survival_wave = 1
		hearts.clear()
		Sfx.play("boom", -8.0)
	else:
		survival_ended.emit(seconds, bonked)
		Sfx.play("cheer")
	survival_changed.emit()

@rpc("authority", "reliable")
func cl_wave(wave: int) -> void:
	survival_wave = wave
	if wave > 1:
		Sfx.play("whoosh", -4.0, 0.7)
	survival_changed.emit()

@rpc("authority", "unreliable")
func cl_monsters(payload: Array) -> void:
	if monster_view != null:
		monster_view.update_monsters(payload)

@rpc("authority", "reliable")
func cl_zap_hit(monster_id: int, dead: bool) -> void:
	if monster_view != null:
		monster_view.hit(monster_id, dead)

@rpc("authority", "reliable")
func cl_reset_vote() -> void:
	reset_vote_started.emit()

@rpc("authority", "reliable")
func cl_reset_result(happened: bool) -> void:
	reset_result.emit(happened)
	if happened:
		Sfx.play("cheer")

@rpc("authority", "reliable")
func cl_world_reset() -> void:
	if chunks != null:
		chunks.reset()
	# Everyone re-asks where to stand in the new world.
	for slot: int in Game.local_inputs.keys():
		sv_where.rpc_id(1, slot)

@rpc("authority", "reliable")
func cl_suck(id: String, block: int) -> void:
	Sfx.play("collect", -6.0)
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			var slot_index: int = (child.selected_slot + 1) % 8
			child.slots[slot_index] = {"kind": "block", "id": block}

@rpc("authority", "reliable")
func cl_fling(id: String) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			child.velocity.y += 22.0
			child.carry_time = 0.5
			child.on_floor = false
			Sfx.play("whoosh")

@rpc("authority", "reliable")
func cl_party_fx(pos: Vector3i) -> void:
	Sfx.play("cheer")
	for color in [Color("ff6b6b"), Color("ffd166"), Color("4a9df8"), Color("ef9fc8")]:
		_burst_particles(pos, color)
	_flash_light(Vector3(pos), Color("ffd166"), 4.0)

@rpc("authority", "reliable")
func cl_hearts(id: String, hp: int) -> void:
	hearts[id] = hp
	hearts_changed.emit()

signal local_hurt(id: String, from_pos: Vector3)

@rpc("authority", "reliable")
func cl_bonk(id: String, monster_pos: Vector3) -> void:
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			# A hit should HURT on screen, not launch you across the map.
			var away: Vector3 = child.position - monster_pos
			away.y = 0
			child.velocity += away.normalized() * 3.0 + Vector3.UP * 2.0
			child.velocity = child.velocity.limit_length(18.0)
			child.carry_time = 0.25
			Sfx.play("bonk", 2.0, 0.8)
			local_hurt.emit(id, monster_pos)

@rpc("authority", "reliable")
func cl_downed(id: String) -> void:
	hearts[id] = 0
	hearts_changed.emit()
	for child in players.get_children():
		if child is Player and child.player_id == id and child.is_local:
			child.teleport(Vector3(spawn_pos) + Vector3(0.5, 2.0, 0.5))
			Sfx.play("drop")

## Bulk terrain change (explosions, sponge drains) — one message, not one
## per block.
@rpc("authority", "reliable")
func cl_batch(cells: Array, block: int) -> void:
	if chunks == null:
		return
	for cell in cells:
		if cell is Vector3i:
			chunks.apply_edit(cell, block)

@rpc("authority", "reliable")
func cl_fuse_fx(pos: Vector3i) -> void:
	if chunks == null:
		return
	var sparks := CPUParticles3D.new()
	sparks.position = Vector3(pos) + Vector3(0.5, 1.05, 0.5)
	sparks.amount = 10
	sparks.lifetime = 0.4
	sparks.direction = Vector3.UP
	sparks.spread = 25.0
	sparks.initial_velocity_min = 1.0
	sparks.initial_velocity_max = 2.2
	sparks.gravity = Vector3(0, -4, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.08
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.2)
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	sparks.mesh = mesh
	add_child(sparks)
	sparks.emitting = true
	get_tree().create_timer(3.4).timeout.connect(func() -> void:
		if is_instance_valid(sparks):
			sparks.queue_free())

@rpc("authority", "reliable")
func cl_boom_fx(pos: Vector3i) -> void:
	if chunks == null:
		return
	var center := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	Sfx.play("boom")
	_explosion_particles(center)
	_flash_light(center, Color(1.0, 0.7, 0.35), 6.0)
	# Harmless, hilarious: anyone close gets launched.
	for child in players.get_children():
		if child is Player and child.is_local:
			var away: Vector3 = child.position - center
			var dist := away.length()
			if dist < 7.0:
				away.y = 0
				var push := (7.0 - dist) / 7.0
				child.velocity += away.normalized() * 10.0 * push + Vector3.UP * 9.0 * push
				child.velocity = child.velocity.limit_length(30.0)
				child.carry_time = 0.6
				child.on_floor = false

@rpc("authority", "reliable")
func cl_firework_fx(pos: Vector3i) -> void:
	if chunks == null:
		return
	Sfx.play("whoosh")
	var burst_at := Vector3(pos) + Vector3(0.5, 11.0, 0.5)
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		var colors := [Color("ff6b6b"), Color("ffd166"), Color("4a9df8"),
			Color("51c979"), Color("ef8fc0")]
		Sfx.play("pop")
		Sfx.play("collect", -4.0)
		_flash_light(burst_at, colors[randi() % colors.size()], 4.0)
		for ring in 2:
			var burst := CPUParticles3D.new()
			burst.position = burst_at
			burst.amount = 40
			burst.lifetime = 1.2
			burst.one_shot = true
			burst.explosiveness = 1.0
			burst.spread = 180.0
			burst.initial_velocity_min = 5.0 + ring * 3.0
			burst.initial_velocity_max = 7.0 + ring * 3.0
			burst.gravity = Vector3(0, -3, 0)
			var mesh := SphereMesh.new()
			mesh.radius = 0.06
			mesh.height = 0.12
			var mat := StandardMaterial3D.new()
			var color: Color = colors[(randi() + ring) % colors.size()]
			mat.albedo_color = color
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = 2.5
			mesh.material = mat
			burst.mesh = mesh
			add_child(burst)
			burst.emitting = true
			get_tree().create_timer(2.0).timeout.connect(func() -> void:
				if is_instance_valid(burst):
					burst.queue_free()))

func _explosion_particles(center: Vector3) -> void:
	var burst := CPUParticles3D.new()
	burst.position = center
	burst.amount = 40
	burst.lifetime = 0.8
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.spread = 180.0
	burst.initial_velocity_min = 6.0
	burst.initial_velocity_max = 11.0
	burst.gravity = Vector3(0, -8, 0)
	burst.mesh = BoxMesh.new()
	(burst.mesh as BoxMesh).size = Vector3(0.22, 0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.1)
	mat.emission_energy_multiplier = 2.0
	burst.mesh.material = mat
	add_child(burst)
	burst.emitting = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(burst):
			burst.queue_free())

func _flash_light(center: Vector3, color: Color, energy: float) -> void:
	var flash := OmniLight3D.new()
	flash.position = center
	flash.light_color = color
	flash.light_energy = energy
	flash.omni_range = 14.0
	flash.shadow_enabled = false
	add_child(flash)
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.5)
	tween.tween_callback(func() -> void:
		if is_instance_valid(flash):
			flash.queue_free())

@rpc("authority", "reliable")
func cl_treasures(id: String, count: int) -> void:
	treasures[id] = count
	treasures_changed.emit()

@rpc("authority", "reliable")
func cl_clock(frac: float) -> void:
	clock = frac

@rpc("authority", "unreliable")
func cl_critters(payload: Array) -> void:
	if critter_view != null:
		critter_view.update_critters(payload)

@rpc("authority", "reliable")
func cl_pet(critter_id: int) -> void:
	if critter_view != null:
		critter_view.pet(critter_id)
		Sfx.play("pet")

func _burst_particles(pos: Vector3i, color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.position = Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	particles.amount = 12
	particles.lifetime = 0.5
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.direction = Vector3.UP
	particles.spread = 60.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 4.0
	particles.gravity = Vector3(0, -14, 0)
	particles.mesh = BoxMesh.new()
	(particles.mesh as BoxMesh).size = Vector3(0.12, 0.12, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	particles.mesh.material = mat
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free())
