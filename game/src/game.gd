extends Node
## Roster + session state, shared by server and clients (autoload /root/Game).
## Much simpler than a round-based party: there are no teams, no phases and
## no lobby — players drop in and out of the persistent world at any time.
## The server (peer 1) owns the roster; the World node (created here, same
## path everywhere) handles everything spatial.

const MAX_PLAYERS := 24
const MAX_LOCAL := 4

const AUTO_NAMES: Array[String] = [
	"Fox", "Bear", "Frog", "Owl", "Cat", "Bee", "Wolf", "Duck",
	"Crab", "Lion", "Moth", "Seal", "Newt", "Hen", "Pug", "Elk",
]

signal roster_changed
signal video_changed
## Video settings: every switch is its own boolean, every scale its own
## number. Persisted to disk so they survive restarts.
var video: Dictionary = {
	"dist_blocks": 128,     # draw distance in BLOCKS (like Minecraft)
	"render_scale": 40,     # 3D resolution percent (flat voxels upscale well)
	"shadows": true,
	"shadow_quality": 2,    # 0/1/2 -> 1024/2048/4096 shadow atlas
	"ssao": true,           # contact shading
	"glow": true,           # bloom on bright things
	"lights": true,         # dynamic lights (lanterns, crystals...)
	"water_shine": true,    # sun glints + gloss on water
	"ao": true,             # baked corner shading on blocks
	"wire": false,          # wireframe
	"renderer": "full",     # full (Vulkan) or lite (OpenGL) — needs restart
}
const VIDEO_PATH := "user://video.cfg"

func load_video() -> void:
	var config := ConfigFile.new()
	if config.load(VIDEO_PATH) != OK:
		return
	for key in video.keys():
		video[key] = config.get_value("video", key, video[key])

func save_video() -> void:
	var config := ConfigFile.new()
	for key in video.keys():
		config.set_value("video", key, video[key])
	config.save(VIDEO_PATH)

## Renderer switching needs a process restart; the saved preference is
## honored on every launch.
func relaunch_with_renderer(lite: bool) -> void:
	video["renderer"] = "lite" if lite else "full"
	save_video()
	var args := PackedStringArray()
	if not OS.has_feature("standalone"):
		args.append("--path")
		args.append(ProjectSettings.globalize_path("res://"))
	args.append("--rendering-method")
	args.append("gl_compatibility" if lite else "forward_plus")
	OS.create_process(OS.get_executable_path(), args)
	get_tree().quit()

## Key "peer:slot" -> {peer:int, slot:int, name:String, style:int}
var roster: Dictionary = {}
## This machine's local players: slot int -> InputSlot.
var local_inputs: Dictionary = {}
var world: Node = null
## The first human to join is the battle host (their peer id).
var host_peer := 0
## Which saved character (characters.cfg section) each local slot is using.
var profile_keys: Dictionary = {}

func _ready() -> void:
	load_video()
	video_changed.connect(save_video)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## Creates /root/Game/World (identical path on every peer, for RPC routing).
func create_world() -> Node:
	remove_world()
	world = preload("res://src/world.gd").new()
	world.name = "World"
	add_child(world)
	return world

func remove_world() -> void:
	if world != null:
		remove_child(world)  # frees the name immediately for a reconnect
		world.queue_free()
		world = null

# ------------------------------------------------------------------
# Local player management
# ------------------------------------------------------------------

func join_local(input: InputSlot) -> void:
	if local_inputs.size() >= MAX_LOCAL:
		return
	for existing: InputSlot in local_inputs.values():
		if existing.claim_key() == input.claim_key():
			return
	var slot := 0
	while local_inputs.has(slot):
		slot += 1
	local_inputs[slot] = input
	# Each physical device remembers its character between sessions, so every
	# kid's character comes back when they grab "their" controller.
	profile_keys[slot] = input.claim_key()
	var profile := _load_profile(input.claim_key())
	sv_register_player.rpc_id(1, slot, profile.name, profile.style, input is BotSlot)

func leave_local(slot: int) -> void:
	if not local_inputs.has(slot):
		return
	local_inputs.erase(slot)
	sv_unregister_player.rpc_id(1, slot)

func set_local_name(slot: int, pname: String) -> void:
	sv_set_name.rpc_id(1, slot, pname)

## attr is "body", "shirt" or "hat" — each HUD swatch cycles one part.
func cycle_local_style(slot: int, attr: String, direction: int) -> void:
	sv_cycle_style.rpc_id(1, slot, attr, direction)

func local_player_ids() -> Array[String]:
	var ids: Array[String] = []
	var me := multiplayer.get_unique_id()
	for slot: int in local_inputs.keys():
		ids.append(player_id(me, slot))
	return ids

static func player_id(peer: int, slot: int) -> String:
	return "%d:%d" % [peer, slot]

func _pick_name() -> String:
	var taken := {}
	for entry: Dictionary in roster.values():
		taken[entry.name] = true
	var pool := AUTO_NAMES.duplicate()
	pool.shuffle()
	for candidate: String in pool:
		if not taken.has(candidate):
			return candidate
	return "Player %d" % (roster.size() + 1)

# ------------------------------------------------------------------
# Client -> server RPCs
# ------------------------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func sv_register_player(slot: int, pname: String, style: Dictionary, bot := false) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_id()
	var id := player_id(peer, slot)
	if roster.has(id):
		return
	if roster.size() >= MAX_PLAYERS:
		if bot:
			return
		# Humans ALWAYS get a seat: a full roster evicts a computer
		# player rather than silently ignoring a real person (this
		# stranded joins as unplaced ghosts when restored bots filled
		# the server).
		var evict := ""
		for other: String in roster.keys():
			if bool(roster[other].get("bot", false)):
				evict = other
		if evict.is_empty():
			return
		roster.erase(evict)
		if world != null:
			world.drop_bot(evict)
	pname = pname.strip_edges().left(12)
	if pname.is_empty():
		pname = _pick_name()
	roster[id] = {"peer": peer, "slot": slot, "name": pname,
		"style": AvatarFactory.normalize_style(style), "team": -1, "bot": bot}
	if host_peer == 0 and not bot:
		host_peer = peer
	print("Player joined: %s (%s), %d in world" % [pname, id, roster.size()])
	_broadcast_roster()
	if not bot and world != null and world.has_method("auto_team"):
		world.auto_team(id)

@rpc("any_peer", "call_local", "reliable")
func sv_unregister_player(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var id := player_id(_sender_id(), slot)
	if roster.has(id):
		print("Player left: %s (%s)" % [roster[id].name, id])
	roster.erase(id)
	_broadcast_roster()

func set_local_team(slot: int, team: int) -> void:
	sv_set_team.rpc_id(1, slot, team)

@rpc("any_peer", "call_local", "reliable")
func sv_set_team(slot: int, team: int) -> void:
	if not multiplayer.is_server():
		return
	var id := player_id(_sender_id(), slot)
	if roster.has(id):
		roster[id].team = clampi(team, -1, 23)
		_broadcast_roster()

@rpc("any_peer", "call_local", "reliable")
func sv_set_name(slot: int, pname: String) -> void:
	if not multiplayer.is_server():
		return
	var id := player_id(_sender_id(), slot)
	if not roster.has(id):
		return
	pname = pname.strip_edges().left(12)
	if pname.is_empty():
		return
	roster[id].name = pname
	_broadcast_roster()

@rpc("any_peer", "call_local", "reliable")
func sv_set_style(slot: int, style: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := player_id(_sender_id(), slot)
	if roster.has(id):
		roster[id].style = AvatarFactory.normalize_style(style)
		_broadcast_roster()

@rpc("any_peer", "call_local", "reliable")
func sv_cycle_style(slot: int, attr: String, direction: int) -> void:
	if not multiplayer.is_server():
		return
	var id := player_id(_sender_id(), slot)
	if not roster.has(id) or not (attr in AvatarFactory.ATTRS):
		return
	var style: Dictionary = AvatarFactory.normalize_style(roster[id].style)
	style[attr] = int(style[attr]) + signi(direction)
	roster[id].style = AvatarFactory.normalize_style(style)
	_broadcast_roster()

func _sender_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()

func _broadcast_roster() -> void:
	cl_roster.rpc(roster)
	cl_host.rpc(host_peer)

## Clients need to know who the host is too — the World menu (Map/Mode/
## Start) only shows for them. This was server-only before, so the check
## failed on every client and NOBODY saw the battle controls.
@rpc("authority", "call_local", "reliable")
func cl_host(peer: int) -> void:
	host_peer = peer

# ------------------------------------------------------------------
# Server -> client RPCs
# ------------------------------------------------------------------

const PROFILE_PATH := "user://characters.cfg"

func _load_profile(device_key: String) -> Dictionary:
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	var style := AvatarFactory.random_style()
	if config.has_section_key(device_key, "body"):
		var saved := {}
		for attr in AvatarFactory.ATTRS:
			saved[attr] = int(config.get_value(device_key, attr, 0))
		style = AvatarFactory.normalize_style(saved)
	return {
		"name": str(config.get_value(device_key, "name", "")),
		"style": style,
	}

func _save_local_profiles() -> void:
	if multiplayer.is_server() or local_inputs.is_empty():
		return
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	var me := multiplayer.get_unique_id()
	var dirty := false
	for entry: Dictionary in roster.values():
		if entry.peer != me or not local_inputs.has(entry.slot):
			continue
		var device_key: String = str(profile_keys.get(entry.slot,
			local_inputs[entry.slot].claim_key()))
		var style: Dictionary = AvatarFactory.normalize_style(entry.get("style"))
		for attr in AvatarFactory.ATTRS:
			if int(config.get_value(device_key, attr, -1)) != int(style[attr]):
				config.set_value(device_key, attr, int(style[attr]))
				dirty = true
		if str(config.get_value(device_key, "name", "")) != entry.name:
			config.set_value(device_key, "name", entry.name)
			dirty = true
	if dirty:
		config.save(PROFILE_PATH)

@rpc("authority", "call_local", "reliable")
func cl_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	_save_local_profiles()
	roster_changed.emit()

# ------------------------------------------------------------------
# Peer lifecycle (server)
# ------------------------------------------------------------------

func _on_peer_connected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	print("Peer %d connected (%d peers total)" % [peer, multiplayer.get_peers().size()])
	cl_roster.rpc_id(peer, roster)
	cl_host.rpc_id(peer, host_peer)
	# Late joiners need the CURRENT battle phase — cl_match broadcasts only
	# fire on transitions, and a stale "IDLE" leaves them out of sync (the
	# old "everything's frozen and I have no hearts" moment).
	if world != null:
		world.cl_match.rpc_id(peer, world.match_phase, world.match_seconds)
		world.cl_storm.rpc_id(peer, world.storm_radius, world.storm_center)

func _on_peer_disconnected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for id: String in roster.keys().duplicate():
		if roster[id].peer == peer:
			roster.erase(id)
	if peer == host_peer:
		host_peer = 0
		for id: String in roster.keys():
			if not bool(roster[id].get("bot", false)):
				host_peer = int(roster[id].peer)
				break
	_broadcast_roster()

## All saved characters (sections in characters.cfg), for the picker.
func list_profiles() -> Array:
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	var sections: Array = Array(config.get_sections())
	sections.sort()
	return sections

## Switch a local slot to a different saved character — characters are no
## longer welded to one controller.
func select_profile(slot: int, key: String) -> void:
	profile_keys[slot] = key
	var profile := _load_profile(key)
	if not str(profile.name).is_empty():
		sv_set_name.rpc_id(1, slot, str(profile.name))
	sv_set_style.rpc_id(1, slot, profile.style)

## Called by main.gd when this client loses its connection.
func reset_to_disconnected() -> void:
	roster = {}
	local_inputs = {}
	remove_world()
	roster_changed.emit()
