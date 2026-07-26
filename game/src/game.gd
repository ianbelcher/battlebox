extends Node
## Roster + session state, shared by server and clients (autoload /root/Game).
## Much simpler than a round-based party: there are no teams, no phases and
## no lobby — players drop in and out of the persistent world at any time.
## The server (peer 1) owns the roster; the World node (created here, same
## path everywhere) handles everything spatial.

const MAX_PLAYERS := 16
const MAX_LOCAL := 4

const AUTO_NAMES: Array[String] = [
	"Fox", "Bear", "Frog", "Owl", "Cat", "Bee", "Wolf", "Duck",
	"Crab", "Lion", "Moth", "Seal", "Newt", "Hen", "Pug", "Elk",
]

signal roster_changed

## Key "peer:slot" -> {peer:int, slot:int, name:String, style:int}
var roster: Dictionary = {}
## This machine's local players: slot int -> InputSlot.
var local_inputs: Dictionary = {}
var world: Node = null

func _ready() -> void:
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
	var profile := _load_profile(input.claim_key())
	var pname: String = profile.name if profile.name != "" else ""
	var style: int = profile.style if profile.style >= 0 else randi() % AvatarFactory.STYLE_COUNT
	sv_register_player.rpc_id(1, slot, pname, style)

func leave_local(slot: int) -> void:
	if not local_inputs.has(slot):
		return
	local_inputs.erase(slot)
	sv_unregister_player.rpc_id(1, slot)

func set_local_name(slot: int, pname: String) -> void:
	sv_set_name.rpc_id(1, slot, pname)

func cycle_local_style(slot: int, direction: int) -> void:
	sv_cycle_style.rpc_id(1, slot, direction)

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
func sv_register_player(slot: int, pname: String, style := -1) -> void:
	if not multiplayer.is_server():
		return
	var peer := _sender_id()
	var id := player_id(peer, slot)
	if roster.has(id) or roster.size() >= MAX_PLAYERS:
		return
	pname = pname.strip_edges().left(12)
	if pname.is_empty():
		pname = _pick_name()
	if style < 0 or style >= AvatarFactory.STYLE_COUNT:
		style = randi() % AvatarFactory.STYLE_COUNT
	roster[id] = {"peer": peer, "slot": slot, "name": pname, "style": style}
	print("Player joined: %s (%s), %d in world" % [pname, id, roster.size()])
	_broadcast_roster()

@rpc("any_peer", "call_local", "reliable")
func sv_unregister_player(slot: int) -> void:
	if not multiplayer.is_server():
		return
	var id := player_id(_sender_id(), slot)
	if roster.has(id):
		print("Player left: %s (%s)" % [roster[id].name, id])
	roster.erase(id)
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
func sv_cycle_style(slot: int, direction: int) -> void:
	if not multiplayer.is_server():
		return
	var id := player_id(_sender_id(), slot)
	if roster.has(id):
		roster[id].style = posmod(roster[id].style + signi(direction), AvatarFactory.STYLE_COUNT)
		_broadcast_roster()

func _sender_id() -> int:
	var sender := multiplayer.get_remote_sender_id()
	return sender if sender != 0 else multiplayer.get_unique_id()

func _broadcast_roster() -> void:
	cl_roster.rpc(roster)

# ------------------------------------------------------------------
# Server -> client RPCs
# ------------------------------------------------------------------

const PROFILE_PATH := "user://characters.cfg"

func _load_profile(device_key: String) -> Dictionary:
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	return {
		"name": str(config.get_value(device_key, "name", "")),
		"style": int(config.get_value(device_key, "style", -1)),
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
		var device_key: String = local_inputs[entry.slot].claim_key()
		var style: int = entry.get("style", 0)
		if str(config.get_value(device_key, "name", "")) != entry.name \
				or int(config.get_value(device_key, "style", -1)) != style:
			config.set_value(device_key, "name", entry.name)
			config.set_value(device_key, "style", style)
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

func _on_peer_disconnected(peer: int) -> void:
	if not multiplayer.is_server():
		return
	for id: String in roster.keys().duplicate():
		if roster[id].peer == peer:
			roster.erase(id)
	_broadcast_roster()

## Called by main.gd when this client loses its connection.
func reset_to_disconnected() -> void:
	roster = {}
	local_inputs = {}
	remove_world()
	roster_changed.emit()
