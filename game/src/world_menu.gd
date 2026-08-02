class_name WorldMenu
extends Control
## The WORLD menu: everything that belongs to the whole table rather than
## to one player — the map, the battle setup, who's playing, and the video
## options. Escape opens it, it covers the entire screen (not one split
## cell), and it is KEYBOARD AND MOUSE ONLY: controllers keep driving their
## own players, so a grown-up can sort the game out while the kids run
## around. Per-player things (blocks, characters) live in PlayerHud.

var world: Node = null

var _dim: ColorRect
var _panel: PanelContainer
var _tabs: TabContainer
var _players_box: VBoxContainer
var _map_row: HBoxContainer
var _saved_label: Label
var _saved_row: HBoxContainer
var _mode_btns: Dictionary = {}
var _length_btns: Dictionary = {}
var _size_btns: Dictionary = {}
var _fly_btns: Dictionary = {}
var _length_head: HBoxContainer
var _length_row: HBoxContainer
var _server_edit: LineEdit
var _add_bot_btn: Button
var _update_state := "idle"
var _update_req: HTTPRequest

func _scale() -> float:
	# Text is sized off the PANEL, which is a fraction of the screen —
	# a full-width panel with small text was unreadable.
	return clampf(size.x / 1500.0, 0.9, 2.6)

func _s(n: int) -> int:
	return int(n * _scale())

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.72)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.98)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(18)
	style.border_color = Color(1, 1, 1, 0.1)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	# A centred window, not the whole screen: roughly 62% x 68%.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.anchor_left = 0.19
	_panel.anchor_right = 0.81
	_panel.anchor_top = 0.16
	_panel.anchor_bottom = 0.84
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = 0
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)
	var title := Label.new()
	title.text = "🌍  World  —  Esc to close"
	title.add_theme_font_size_override("font_size", _s(26))
	title.add_theme_color_override("font_color", Color("ffd166"))
	outer.add_child(title)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", _s(21))
	# Controllers must not reach into this menu at all: focus is how a
	# gamepad drives Godot's UI (ui_left/ui_right/ui_accept walk the focus
	# chain), so nothing in here is focusable except by clicking it.
	_tabs.focus_mode = Control.FOCUS_NONE
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	outer.add_child(_tabs)
	_build_map_tab()
	_build_battle_tab()
	_build_players_tab()
	_build_video_tab()
	_build_help_tab()
	_build_credits_tab()
	Game.roster_changed.connect(_refresh)

func open() -> void:
	visible = true
	_refresh()

func close() -> void:
	visible = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func _tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", _s(10))
	scroll.add_child(box)
	return box

func _heading(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _s(20))
	label.add_theme_color_override("font_color", Color("9fb3d1"))
	parent.add_child(label)

func _button(text: String, on_press: Callable) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = text
	btn.add_theme_font_size_override("font_size", _s(18))
	btn.pressed.connect(func() -> void:
		on_press.call()
		Sfx.play("tick", -8.0))
	return btn

func _mark(btn: Button, on: bool) -> void:
	if on:
		var sel := StyleBoxFlat.new()
		sel.bg_color = Color("ffd166")
		sel.set_corner_radius_all(8)
		sel.set_content_margin_all(_s(7))
		sel.content_margin_left = _s(14)
		sel.content_margin_right = _s(14)
		for state in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state, sel)
		btn.add_theme_color_override("font_color", Color("1c2333"))
	else:
		for state in ["normal", "hover", "pressed"]:
			btn.remove_theme_stylebox_override(state)
		btn.remove_theme_color_override("font_color")

# ------------------------------------------------------------------
# Map
# ------------------------------------------------------------------

func _build_map_tab() -> void:
	var box := _tab("Map")
	_map_row = HBoxContainer.new()
	_map_row.add_theme_constant_override("separation", _s(8))
	box.add_child(_map_row)
	_saved_label = Label.new()
	_saved_label.text = "Custom worlds"
	_saved_label.add_theme_font_size_override("font_size", _s(20))
	box.add_child(_saved_label)
	_saved_row = HBoxContainer.new()
	_saved_row.add_theme_constant_override("separation", _s(8))
	box.add_child(_saved_row)
	# The launcher no longer asks which server to join — it just connects —
	# so this is where a grown-up points the game somewhere else.
	box.add_child(HSeparator.new())
	_heading(box, "Server")
	var server_row := HBoxContainer.new()
	server_row.add_theme_constant_override("separation", _s(8))
	box.add_child(server_row)
	_server_edit = LineEdit.new()
	_server_edit.text = Game.server_url()
	_server_edit.focus_mode = Control.FOCUS_CLICK
	_server_edit.custom_minimum_size = Vector2(_s(420), 0)
	_server_edit.add_theme_font_size_override("font_size", _s(19))
	server_row.add_child(_server_edit)
	server_row.add_child(_button("Use this server", func() -> void:
		var url := _server_edit.text.strip_edges()
		if url.is_empty():
			return
		if not url.begins_with("ws://") and not url.begins_with("wss://"):
			url = "ws://" + url
		Game.set_server_url(url)
		# Dropping the link is enough: main.gd notices, shows the
		# reconnecting banner and dials the new address by itself.
		close()
		Net.disconnect_now()))

func _refresh_maps() -> void:
	if _map_row == null:
		return
	for child in _map_row.get_children():
		child.queue_free()
	for child in _saved_row.get_children():
		child.queue_free()
	for choice in [["classic", "Classic"], ["desert", "Desert"], ["isles", "Isles"],
			["castles", "Castle"], ["city", "City"], ["sky", "Skylands"],
			["space", "Space"]]:
		_map_row.add_child(_map_button(str(choice[0]), str(choice[1])))
	var have: bool = world != null and not world.map_list.is_empty()
	_saved_label.visible = have
	_saved_row.visible = have
	if have:
		for entry in world.map_list:
			_saved_row.add_child(_map_button(str(entry.key), str(entry.name)))

func _map_button(key: String, label: String) -> Button:
	var btn := _button(label, func() -> void:
		if Game.world != null:
			Game.world.sv_select_world.rpc_id(1, key))
	if world != null and key == world.client_world:
		_mark(btn, true)
	return btn

# ------------------------------------------------------------------
# Battle
# ------------------------------------------------------------------

func _build_battle_tab() -> void:
	var box := _tab("Battle")
	_heading(box, "Mode")
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", _s(8))
	box.add_child(mode_row)
	for spec in [["battle", "Battle royale"], ["creative", "Just building"]]:
		var key := str(spec[0])
		var btn := _button(str(spec[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_set_mode.rpc_id(1, key))
		mode_row.add_child(btn)
		_mode_btns[key] = btn

	# Arena size and flying are NOT battle settings — they shape the world
	# in both modes — so they sit above the battle-only ones and always
	# show. Everything here applies immediately, mid-battle included.
	_heading(box, "Arena size")
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", _s(8))
	box.add_child(size_row)
	for arena in [50, 100, 150, 200, 250, 300, 350]:
		var blocks: int = arena
		var btn := _button(str(arena), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, -1, -1, blocks, -1))
		size_row.add_child(btn)
		_size_btns[arena] = btn

	_heading(box, "Flying")
	var fly_row := HBoxContainer.new()
	fly_row.add_theme_constant_override("separation", _s(8))
	box.add_child(fly_row)
	for spec in [[1, "Allowed"], [0, "No flying"]]:
		var val: int = spec[0]
		var btn := _button(str(spec[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, -1, -1, -1, val))
		fly_row.add_child(btn)
		_fly_btns[val] = btn

	# Battle-only, and last: how long a round runs for.
	_length_head = HBoxContainer.new()
	_length_head.add_theme_constant_override("separation", _s(8))
	box.add_child(_length_head)
	_heading(_length_head, "Game length")
	_length_row = HBoxContainer.new()
	_length_row.add_theme_constant_override("separation", _s(8))
	box.add_child(_length_row)
	for preset in [[3, "3 min"], [5, "5 min"], [8, "8 min"], [60, "Unlimited"]]:
		var minutes: int = preset[0]
		var btn := _button(str(preset[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, minutes, -1, -1, -1))
		_length_row.add_child(btn)
		_length_btns[minutes] = btn

# ------------------------------------------------------------------
# Players
# ------------------------------------------------------------------

func _build_players_tab() -> void:
	var box := _tab("Players")
	var manage := HBoxContainer.new()
	manage.add_theme_constant_override("separation", _s(10))
	box.add_child(manage)
	manage.add_child(_button("➕ Team", func() -> void:
		if Game.world != null:
			Game.world.sv_add_team.rpc_id(1)))
	manage.add_child(_button("➖ Team", func() -> void:
		if Game.world != null:
			Game.world.sv_remove_team.rpc_id(1, -1)))
	_add_bot_btn = _button("➕ Computer player", func() -> void:
		if Game.world != null:
			Game.world.sv_add_bot.rpc_id(1))
	manage.add_child(_add_bot_btn)
	manage.add_child(_button("➖ Computer player", func() -> void:
		if Game.world != null:
			Game.world.sv_remove_bot.rpc_id(1, "")))
	for child in manage.get_children():
		var mb := child as Button
		if mb != null:
			mb.add_theme_font_size_override("font_size", _s(22))
			mb.custom_minimum_size = Vector2(_s(190), _s(44))
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", _s(6))
	box.add_child(_players_box)

func _refresh_players() -> void:
	if _players_box == null:
		return
	for child in _players_box.get_children():
		child.queue_free()
	if _add_bot_btn != null:
		_add_bot_btn.disabled = Game.roster.size() >= 24
	var team_count: int = world.team_count if world != null else 4
	var ids: Array = Game.roster.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var a_bot: bool = bool(Game.roster[a].get("bot", false))
		var b_bot: bool = bool(Game.roster[b].get("bot", false))
		if a_bot != b_bot:
			return b_bot  # humans first
		return str(Game.roster[a].name) < str(Game.roster[b].name))
	for id: String in ids:
		var entry: Dictionary = Game.roster[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _s(8))
		_players_box.add_child(row)
		var is_bot: bool = bool(entry.get("bot", false))
		var tag := Label.new()
		tag.text = "🤖" if is_bot else "🙂"
		tag.add_theme_font_size_override("font_size", _s(20))
		row.add_child(tag)
		# Names are typed here: a keyboard beats a controller for spelling.
		var name_edit := LineEdit.new()
		name_edit.text = str(entry.name)
		name_edit.max_length = 12
		name_edit.custom_minimum_size = Vector2(_s(170), 0)
		name_edit.add_theme_font_size_override("font_size", _s(19))
		var target := id
		name_edit.text_submitted.connect(func(text: String) -> void:
			Game.sv_rename_any.rpc_id(1, target, text)
			Sfx.play("pop", -6.0))
		name_edit.focus_exited.connect(func() -> void:
			Game.sv_rename_any.rpc_id(1, target, name_edit.text))
		row.add_child(name_edit)
		var team := int(entry.get("team", -1))
		for t in team_count:
			var cell := Button.new()
			cell.focus_mode = Control.FOCUS_NONE
			cell.custom_minimum_size = Vector2(_s(56), _s(28))
			cell.text = WorldNode.TEAM_NAMES[t] if t < WorldNode.TEAM_NAMES.size() else str(t)
			cell.add_theme_font_size_override("font_size", _s(15))
			var cell_style := StyleBoxFlat.new()
			cell_style.bg_color = WorldNode.TEAM_COLORS[t] * (1.0 if t == team else 0.32)
			cell_style.bg_color.a = 1.0
			cell_style.set_corner_radius_all(6)
			if t == team:
				cell_style.border_color = Color.WHITE
				cell_style.set_border_width_all(2)
			for state in ["normal", "hover", "pressed"]:
				cell.add_theme_stylebox_override(state, cell_style)
			cell.add_theme_color_override("font_color", Color(0.1, 0.1, 0.14))
			var pick := t
			var slot := int(entry.slot)
			var mine: bool = int(entry.peer) == multiplayer.get_unique_id() \
				and Game.local_inputs.has(slot)
			cell.pressed.connect(func() -> void:
				if mine:
					Game.set_local_team(slot, pick)
				elif Game.world != null:
					Game.world.sv_set_bot_team.rpc_id(1, target, pick)
				Sfx.play("tick", -8.0))
			row.add_child(cell)
		# X at the end of the row: done playing, out you go.
		var kick := Button.new()
		kick.focus_mode = Control.FOCUS_NONE
		kick.text = "✕"
		kick.tooltip_text = "Remove this player"
		kick.custom_minimum_size = Vector2(_s(34), _s(28))
		kick.add_theme_font_size_override("font_size", _s(18))
		kick.add_theme_color_override("font_color", Color("ff6b6b"))
		kick.pressed.connect(func() -> void:
			Game.sv_kick_player.rpc_id(1, target)
			Sfx.play("pop", -6.0))
		row.add_child(kick)

# ------------------------------------------------------------------
# Video + Help
# ------------------------------------------------------------------

func _build_video_tab() -> void:
	var box := _tab("Video")
	_slider(box, "Draw distance", "dist_blocks", 32, 208, 16, "%d blocks")
	_slider(box, "3D resolution", "render_scale", 1, 100, 1, "%d%%")
	_slider(box, "Shadow quality", "shadow_quality", 0, 2, 1, "%d")
	for spec in [["shadows", "Shadows"], ["ssao", "Contact shading (SSAO)"],
			["glow", "Glow"], ["lights", "Dynamic lights"],
			["water_shine", "Shiny water"], ["ao", "Corner shading"],
			["wire", "Wireframe"]]:
		var key := str(spec[0])
		var label := str(spec[1])
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", _s(19))
		btn.text = ("☑  " if Game.video[key] else "☐  ") + label
		btn.pressed.connect(func() -> void:
			Game.video[key] = not bool(Game.video[key])
			btn.text = ("☑  " if Game.video[key] else "☐  ") + label
			Game.video_changed.emit()
			Sfx.play("tick", -10.0))
		box.add_child(btn)
	var is_lite := RenderingServer.get_rendering_device() == null
	box.add_child(_button("🎨  Renderer: " + ("Lite" if is_lite else "Full")
		+ "  (restart required)", func() -> void:
		Game.relaunch_with_renderer(not is_lite)))
	if not OS.has_feature("editor") and (OS.has_feature("windows") or OS.has_feature("linux")):
		var upd := Button.new()
		upd.focus_mode = Control.FOCUS_NONE
		upd.alignment = HORIZONTAL_ALIGNMENT_LEFT
		upd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		upd.add_theme_font_size_override("font_size", _s(19))
		upd.text = "🔄  Check for updates"
		upd.pressed.connect(func() -> void: _updater_step(upd))
		box.add_child(upd)

func _slider(parent: Control, label: String, key: String, low: int, high: int,
		step: int, fmt: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _s(10))
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(_s(200), 0)
	name_label.add_theme_font_size_override("font_size", _s(19))
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = float(Game.video[key])
	slider.custom_minimum_size = Vector2(_s(320), 0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = fmt % int(Game.video[key])
	value_label.custom_minimum_size = Vector2(_s(150), 0)
	value_label.add_theme_font_size_override("font_size", _s(19))
	row.add_child(value_label)
	slider.value_changed.connect(func(v: float) -> void:
		Game.video[key] = int(v)
		value_label.text = fmt % int(v)
		Game.video_changed.emit())

func _build_help_tab() -> void:
	var box := _tab("Help")
	for line in ["Esc  —  this world menu (keyboard and mouse)",
			"X  —  blocks and kits (controller)",
			"LB / RB  —  flip through the picker's tabs (your character is one of them)",
			"D-pad ◀ ▶  —  swap what you're holding",
			"A / Space  —  jump.  Double-tap to fly (when allowed)",
			"RT / R  —  throw or shoot.  LT  —  dig",
			"Walk into a dragon to ride it; double-tap A to hop off",
			"Grapple a block and it reels you up on top of it"]:
		var label := Label.new()
		label.text = "• " + str(line)
		label.add_theme_font_size_override("font_size", _s(19))
		box.add_child(label)

func _build_credits_tab() -> void:
	var box := _tab("Credits")
	_heading(box, "This game stands on other people's work — thank you")
	for group: String in Credits.groups():
		var head := Label.new()
		head.text = group
		head.add_theme_font_size_override("font_size", _s(21))
		head.add_theme_color_override("font_color", Color("ffd166"))
		box.add_child(head)
		for entry: Dictionary in Credits.in_group(group):
			var line := Label.new()
			line.text = "   %s — %s  (%s)\n      %s" % [str(entry.name),
				str(entry.by), str(entry.license), str(entry.what)]
			line.add_theme_font_size_override("font_size", _s(17))
			box.add_child(line)
	if not Credits.builds().is_empty():
		var builds_head := Label.new()
		builds_head.text = "Imported builds"
		builds_head.add_theme_font_size_override("font_size", _s(21))
		builds_head.add_theme_color_override("font_color", Color("ffd166"))
		box.add_child(builds_head)
		for entry: Dictionary in Credits.builds():
			var line := Label.new()
			line.text = "   %s — built by %s  (%s)" % [str(entry.get("name", "?")),
				str(entry.get("by", "unknown")), str(entry.get("license", "?"))]
			line.add_theme_font_size_override("font_size", _s(17))
			box.add_child(line)

# ------------------------------------------------------------------
# Self-updater
# ------------------------------------------------------------------

func _updater_base() -> String:
	return "http://%s:30811/downloads" % Net.last_host

func _local_version() -> String:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else "dev"

func _updater_step(btn: Button) -> void:
	if _update_state == "busy":
		return
	if _update_req == null:
		_update_req = HTTPRequest.new()
		add_child(_update_req)
	if _update_state == "idle":
		_update_state = "busy"
		btn.text = "🔄  Checking…"
		_update_req.download_file = ""
		_update_req.request_completed.connect(
			func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
				_update_state = "idle"
				if code != 200:
					btn.text = "🔄  Update check failed — try again"
					return
				var remote := body.get_string_from_utf8().strip_edges()
				if remote.is_empty() or remote == _local_version():
					btn.text = "✅  Up to date — check again"
				else:
					_update_state = "ready"
					btn.text = "⬇  Update available — install now",
			CONNECT_ONE_SHOT)
		_update_req.request(_updater_base() + "/version.txt")
	elif _update_state == "ready":
		_update_state = "busy"
		btn.text = "⬇  Downloading… (the game restarts itself)"
		var fname := "voxel-battle-windows.exe" if OS.has_feature("windows") \
			else "voxel-battle-linux.x86_64"
		var dest := ProjectSettings.globalize_path("user://update-download")
		_update_req.download_file = dest
		_update_req.request_completed.connect(
			func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
				if code != 200:
					_update_state = "idle"
					btn.text = "🔄  Download failed — try again"
					return
				_apply_update(dest),
			CONNECT_ONE_SHOT)
		_update_req.request(_updater_base() + "/" + fname)

func _apply_update(new_file: String) -> void:
	var exe := OS.get_executable_path()
	if OS.has_feature("windows"):
		var bat_path := ProjectSettings.globalize_path("user://apply-update.bat")
		var bat := FileAccess.open(bat_path, FileAccess.WRITE)
		bat.store_string("@echo off\r\n"
			+ "timeout /t 2 /nobreak >nul\r\n"
			+ ":loop\r\n"
			+ "del \"%~1\" 2>nul\r\n"
			+ "if exist \"%~1\" (timeout /t 1 /nobreak >nul\r\ngoto loop)\r\n"
			+ "move /y \"%~2\" \"%~1\" >nul\r\n"
			+ "start \"\" \"%~1\"\r\n")
		bat.close()
		OS.create_process("cmd.exe", ["/C", bat_path, exe, new_file])
	else:
		DirAccess.rename_absolute(exe, exe + ".old")
		DirAccess.rename_absolute(new_file, exe)
		OS.execute("chmod", ["+x", exe])
		OS.create_process(exe, [])
	get_tree().quit()

# ------------------------------------------------------------------

func _refresh() -> void:
	if not visible:
		return
	_refresh_maps()
	_refresh_players()
	if world == null:
		return
	for key: String in _mode_btns:
		_mark(_mode_btns[key], key == world.client_mode)
	for minutes: int in _length_btns:
		_mark(_length_btns[minutes], minutes == world.client_minutes)
	for arena: int in _size_btns:
		_mark(_size_btns[arena], arena == world.client_size)
	for val: int in _fly_btns:
		_mark(_fly_btns[val], (val == 1) == world.client_fly)
	# Game length only means anything in battle mode. There is no start
	# button: picking Battle royale IS starting it.
	var battling: bool = world.client_mode == "battle"
	if _length_head != null:
		_length_head.visible = battling
	if _length_row != null:
		_length_row.visible = battling

var _auto_ms := 0

func _process(delta: float) -> void:
	if OS.get_environment("WORLD_MENU_TEST") == "1" and not visible:
		_auto_ms += int(delta * 1000.0)
		if _auto_ms > 12000:
			open()
			# WORLD_MENU_TAB=<n> opens straight onto one tab for screenshots.
			var want := OS.get_environment("WORLD_MENU_TAB")
			if want.is_valid_int() and _tabs != null:
				_tabs.current_tab = clampi(want.to_int(), 0,
					_tabs.get_tab_count() - 1)
	if visible:
		_refresh()
