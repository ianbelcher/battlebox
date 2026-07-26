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

# Client
var chunks: ChunkView = null
var players: Node3D = null
var critter_view: CritterView = null
var sky: DayNight = null
var _ready_announced := false

# Server
var store: ChunkStore = null
var _player_state: Dictionary = {}   # id -> {pos: Vector3, treasures: int, name: String}
var _chunk_send_queues: Dictionary = {}  # peer -> Array[Vector2i]
var _saplings: Array = []            # [{pos: Vector3i, at_msec: int}]
var _critters: Dictionary = {}       # id -> {kind, pos, target, speed, think}
var _next_critter_id := 1
var _known_roster_ids: Dictionary = {}
var _was_night := false

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
	var config := ConfigFile.new()
	config.load(store.data_dir.path_join("world.cfg"))
	clock = float(config.get_value("world", "clock", 0.35))
	print("World spawn at %s, clock %.2f" % [spawn_pos, clock])
	_load_player_file()
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

## Flush everything on clean shutdown (docker stop / pod reschedule); the
## 25s autosave bounds losses if the process is killed hard.
func _exit_tree() -> void:
	if multiplayer.is_server() and store != null:
		store.save_dirty()
		_save_player_file()

func _server_autosave() -> void:
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
		pos = Vector3(spawn_pos) + Vector3(randf_range(-2, 2), 2.0, randf_range(-2, 2))
	_player_state[id] = {"pos": pos, "treasures": count, "name": str(entry.name)}
	cl_treasures.rpc(id, count)
	cl_where.rpc_id(peer, slot, pos, count)

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
		if Blocks.is_collectible(current):
			state.treasures = int(state.treasures) + 1
			_player_state[id] = state
			cl_treasures.rpc(id, state.treasures)
	else:
		if not (block in Blocks.HOTBAR):
			return
		if current != Blocks.AIR and current != Blocks.TALL_GRASS:
			return
		if block == Blocks.SAPLING:
			_saplings.append({"pos": pos, "at_msec": Time.get_ticks_msec()})
	store.set_block(pos, block)
	cl_edit.rpc(pos, block, id)

@rpc("any_peer", "reliable")
func sv_pet(slot: int, critter_id: int) -> void:
	if not multiplayer.is_server():
		return
	if _critters.has(critter_id):
		cl_pet.rpc(critter_id)

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

func _server_tick_critters() -> void:
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
	for id: int in _critters.keys():
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
	if ground == Blocks.WATER:
		kind = CritterView.DUCK
	elif ground == Blocks.GRASS:
		if night:
			kind = CritterView.FIREFLY if randf() < 0.6 else CritterView.BUNNY
		else:
			var roll := randf()
			if roll < 0.4:
				kind = CritterView.SHEEP
			elif roll < 0.7:
				kind = CritterView.BUNNY
			else:
				kind = CritterView.BUTTERFLY
	if kind < 0:
		return
	var pos := Vector3(wx + 0.5, y + 1.0, wz + 0.5)
	_critters[_next_critter_id] = {
		"kind": kind, "pos": pos, "target": pos,
		"speed": [1.2, 2.2, 1.6, 0.9, 1.1][kind],
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
		player.setup(id, entry, is_local,
			Game.local_inputs.get(entry.slot) if is_local else null, self)
		players.add_child(player)
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
	sv_edit.rpc_id(1, slot, pos, block)

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

@rpc("authority", "reliable")
func cl_edit(pos: Vector3i, block: int, by_id: String) -> void:
	if chunks == null:
		return
	var old := chunks.apply_edit(pos, block)
	edit_applied.emit(pos, block, by_id)
	if by_id.is_empty():
		return  # world magic (tree growth, dawn flowers) is quiet
	if block == Blocks.AIR:
		if old > 0 and Blocks.is_collectible(old):
			Sfx.play("collect")
		else:
			Sfx.play("dig")
		if old > 0:
			_burst_particles(pos, Blocks.color_of(old))
	else:
		Sfx.play("place")

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
