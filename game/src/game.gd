extends Node
## Roster + session state, shared by server and clients (autoload /root/Game).
## Much simpler than a round-based party: there are no teams, no phases and
## no lobby — players drop in and out of the persistent world at any time.
## The server (peer 1) owns the roster; the World node (created here, same
## path everywhere) handles everything spatial.

const MAX_PLAYERS := 24
const MAX_LOCAL := 4

## People get animals, computers get the phonetic alphabet. Two name
## pools, so you can tell at a glance who is real without reading the
## little robot face.
const AUTO_NAMES: Array[String] = [
	"Fox", "Bear", "Frog", "Owl", "Cat", "Bee", "Wolf", "Duck",
	"Crab", "Lion", "Moth", "Seal", "Newt", "Hen", "Pug", "Elk",
]

## The phonetic alphabet, in order — and because every word starts with
## the letter it stands for, sorting the roster by NAME puts the
## computers in that same order for free. The old names were "1", "2",
## … "10", which sorted as 1, 10, 2 and made the roster unreadable.
## 26 words against a 24-player cap, so the pool can never run dry.
const BOT_NAMES: Array[String] = [
	"Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf",
	"Hotel", "India", "Juliet", "Kilo", "Lima", "Mike", "November",
	"Oscar", "Papa", "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
	"Victor", "Whiskey", "Xray", "Yankee", "Zulu",
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

## The server this machine dials on launch. There is no server-picker
## screen any more — the client just connects — so the address lives here
## and is only ever changed from the world menu (or the rescue box that
## appears when the client can't reach anything).
func server_url() -> String:
	# In a browser there is nothing to choose: the page came from the
	# machine running the world, so that is the world we join. A saved
	# address would be a LAN one typed on someone's desktop, and following
	# it would leave the tab unable to connect to anything.
	if OS.has_feature("web"):
		return Net.default_server_url()
	var config := ConfigFile.new()
	if config.load(VIDEO_PATH) == OK:
		var saved := str(config.get_value("net", "server", ""))
		if not saved.is_empty():
			return saved
	return Net.default_server_url()

func set_server_url(url: String) -> void:
	var config := ConfigFile.new()
	config.load(VIDEO_PATH)
	config.set_value("net", "server", url)
	config.save(VIDEO_PATH)

func load_video() -> void:
	var config := ConfigFile.new()
	if config.load(VIDEO_PATH) != OK:
		return
	for key in video.keys():
		video[key] = config.get_value("video", key, video[key])

func save_video() -> void:
	var config := ConfigFile.new()
	# Load first: the file also holds the server address, and writing a
	# fresh one would drop it.
	config.load(VIDEO_PATH)
	for key in video.keys():
		config.set_value("video", key, video[key])
	config.save(VIDEO_PATH)

## Renderer switching needs a process restart; the saved preference is
## honored on every launch.
func relaunch_with_renderer(lite: bool) -> void:
	video["renderer"] = "lite" if lite else "full"
	save_video()
	var args := PackedStringArray()
	# ONLY editor-run dev needs --path; 4.7 export templates are built
	# without path overrides and ABORT if they ever see the flag.
	if OS.has_feature("editor"):
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

## Fonts covering the symbols the UI is built out of — hearts, the ⒶⒷⓍⓎ
## button caps, the weather and trophy icons.
##
## The game never shipped a font: on a desktop Godot quietly borrows
## glyphs it lacks from the operating system's own fonts, and every one of
## these came from there. A browser has no system fonts to borrow, so all
## 51 of them turned into empty boxes with their code point printed inside
## — the hearts read as "2665".
##
## Three, because no one of them has the lot: DejaVu has the box-drawing
## and card suits, Noto Sans Symbols has the circled letters (and ONLY it
## does — Symbols 2 does not, despite the name), Noto Emoji has the rest.
const WEB_FONTS := [
	"res://assets/fonts/DejaVuSans.ttf",
	"res://assets/fonts/NotoSansSymbols-Regular.ttf",
	"res://assets/fonts/NotoEmoji-Regular.ttf",
]

## The wrapped font, once built — null on desktop, where it isn't needed.
var ui_font: Font = null

func _ready() -> void:
	_install_fallback_fonts()
	load_video()
	video_changed.connect(save_video)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

## Web only, deliberately. On a desktop the system fonts already do this
## job and do it better — macOS draws these in colour — so bundling ours
## ahead of them would be a downgrade nobody asked for.
func _install_fallback_fonts() -> void:
	if not OS.has_feature("web"):
		return
	var extra: Array[Font] = []
	for path: String in WEB_FONTS:
		var font := load(path) as Font
		if font != null:
			extra.append(font)
	if extra.is_empty():
		push_warning("No fallback fonts loaded — symbols will show as boxes.")
		return
	# Wrap rather than mutate: the default font is a built-in resource, and
	# a FontVariation keeps the game's existing typeface as the base while
	# adding somewhere to look for the glyphs it doesn't have.
	var wrapper := FontVariation.new()
	wrapper.base_font = ThemeDB.fallback_font
	wrapper.fallbacks = extra
	ui_font = wrapper
	# BOTH of these, and the second one is the one that actually works.
	# ThemeDB.fallback_font alone changes nothing: it is only consulted
	# when a theme lookup finds nothing at all, and the default theme DOES
	# define a font, so the lookup succeeds and never reaches the fallback.
	# Setting the default theme's own font is what every Control without
	# an explicit font override actually reads. fallback_font still matters
	# for Label3D, which asks for it directly.
	ThemeDB.fallback_font = wrapper
	var default_theme := ThemeDB.get_default_theme()
	if default_theme != null:
		default_theme.default_font = wrapper

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
		if existing.kind == input.kind and existing.device == input.device:
			return
	var slot := 0
	while local_inputs.has(slot):
		slot += 1
	local_inputs[slot] = input
	# Each physical device remembers its character between sessions, so every
	# kid's character comes back when they grab "their" controller. Identical
	# controllers (same GUID) get #1, #2... suffixes so both can join.
	var base_key := input.claim_key()
	var ordinal := 0
	for used in profile_keys.values():
		if str(used) == base_key or str(used).begins_with(base_key + "#"):
			ordinal += 1
	var key := base_key if ordinal == 0 else "%s#%d" % [base_key, ordinal]
	profile_keys[slot] = key
	_migrate_profile(input.legacy_claim_key(), key)
	var profile := _load_profile(key)
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

func set_local_style(slot: int, style: Dictionary) -> void:
	sv_set_style.rpc_id(1, slot, style)

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
		# A person moving teams re-balances the computers around them, so
		# picking a side never leaves one team three-up on the other.
		if world != null and world.has_method("_redistribute_bots"):
			world._redistribute_bots()
		else:
			_broadcast_roster()

## Kick anyone from the world menu: a kid who's done playing, or a
## computer player nobody wants. Humans can rejoin by pressing start.
@rpc("any_peer", "call_local", "reliable")
func sv_kick_player(target_id: String) -> void:
	if not multiplayer.is_server() or not roster.has(target_id):
		return
	var was_bot: bool = bool(roster[target_id].get("bot", false))
	roster.erase(target_id)
	if was_bot and world != null and world.has_method("drop_bot"):
		world.drop_bot(target_id)
	if world != null and world.has_method("forget_player"):
		world.forget_player(target_id)
	_broadcast_roster()

## Rename ANY player from the world menu — typing a name on a controller
## is beyond the little ones, so a grown-up does it on the keyboard.
@rpc("any_peer", "call_local", "reliable")
func sv_rename_any(target_id: String, pname: String) -> void:
	if not multiplayer.is_server() or not roster.has(target_id):
		return
	var clean := pname.strip_edges().left(12)
	if clean.is_empty():
		return
	roster[target_id].name = clean
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
	# Characters are picked whole now: any attribute nudge steps through
	# the roster of Kenney characters instead.
	var all := AvatarFactory.characters()
	var index: int = all.find(str(style.get("who", "a")))
	style = {"who": all[posmod(index + signi(direction), all.size())]}
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

## One-time move of a saved character from the old device-number key to
## the stable GUID key.
func _migrate_profile(old_key: String, new_key: String) -> void:
	if old_key == new_key:
		return
	var config := ConfigFile.new()
	if config.load(PROFILE_PATH) != OK:
		return
	if config.has_section(new_key) or not config.has_section(old_key):
		return
	for section_key in config.get_section_keys(old_key):
		config.set_value(new_key, section_key, config.get_value(old_key, section_key))
	config.save(PROFILE_PATH)

func _load_profile(device_key: String) -> Dictionary:
	var config := ConfigFile.new()
	config.load(PROFILE_PATH)
	var style := AvatarFactory.random_style()
	if config.has_section_key(device_key, "who"):
		style = AvatarFactory.normalize_style(
			{"who": str(config.get_value(device_key, "who", "a"))})
	elif config.has_section_key(device_key, "body"):
		# Legacy editor profile: maps to a stable Kenney pick.
		var saved := {}
		for attr: String in ["body", "face", "hair", "hat", "shirt", "pants",
				"shoes", "gear"]:
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
		if str(config.get_value(device_key, "who", "")) != str(style.who):
			config.set_value(device_key, "who", str(style.who))
			dirty = true
		if str(config.get_value(device_key, "name", "")) != entry.name:
			config.set_value(device_key, "name", entry.name)
			dirty = true
	if dirty:
		config.save(PROFILE_PATH)

@rpc("authority", "call_local", "reliable")
func cl_roster(new_roster: Dictionary) -> void:
	roster = new_roster
	_drop_kicked_seats()
	_save_local_profiles()
	roster_changed.emit()

signal all_local_left

## A player on THIS machine who is no longer in the roster has been kicked
## — most likely by somebody hitting the ✕ next to their name in the world
## menu. Give up their seat.
##
## Without this the seat stayed: the split screen kept their quadrant, the
## controller kept steering a player the server had forgotten, and nothing
## brought a three-player game back down to two. Dropping the seat here
## makes a kick do what it looks like it does.
## Slots this machine has actually seen confirmed in a roster broadcast.
## A seat is only ever given up if it was CONFIRMED and then vanished.
var _seen_seats: Dictionary = {}

func _drop_kicked_seats() -> void:
	if multiplayer.multiplayer_peer == null or local_inputs.is_empty():
		return
	var me := multiplayer.get_unique_id()
	var lost := false
	for slot: int in local_inputs.keys():
		var id := player_id(me, slot)
		if roster.has(id):
			_seen_seats[slot] = true
			continue
		# NOT YET CONFIRMED is not the same as KICKED. Registration is a
		# round trip, and the server sends the roster on connect — before
		# this machine's players are in it. Dropping seats on that first
		# broadcast wiped every one of them the moment anybody was
		# kicked, or on a slow join.
		if not _seen_seats.has(slot):
			continue
		local_inputs.erase(slot)
		profile_keys.erase(slot)
		_seen_seats.erase(slot)
		lost = true
	if not lost:
		return
	if local_inputs.is_empty():
		# Nobody from this machine is playing any more. Back to the
		# "press Ⓐ to join" screen rather than a world with no one in it.
		all_local_left.emit()

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
	_seen_seats.clear()
	# Clear the device->profile claims too. Leaving them behind made every
	# reconnect hand the same controller a "#1" key, so the kid came back
	# as a stranger with a random name and character.
	profile_keys = {}
	remove_world()
	roster_changed.emit()
