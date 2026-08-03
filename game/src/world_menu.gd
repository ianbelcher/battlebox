class_name WorldMenu
extends Control
## The WORLD menu (Escape): everything belonging to the whole table rather
## than to one player. Per-player things (blocks, characters) live in
## PlayerHud.
##
## Tabs follow what each thing actually IS, not which code owns it:
##   Map     what world you're in and how play works in it — the map, its
##           size, whether flying is on. True in every mode.
##   Game    creative or battle royale, plus the battle-only settings.
##   Players who's here, their names, teams, and computer players.
##   Video / Help / Credits
##
## KEYBOARD AND MOUSE, both:
##   mouse     click anything
##   keyboard  Tab/arrows move the highlight, Enter presses, Escape closes
##   pads      cannot reach it: _input() swallows joypad EVENTS while open.
##             Players are driven by POLLING, so the kids keep running
##             around on their controllers while a grown-up sorts things.
##
## TWO RULES, both learned the hard way:
##
## 1. NEVER rebuild on a timer. This menu used to rebuild every row every
##    frame, which destroyed the text box you were typing in and the
##    button you were half way through clicking. Rows are rebuilt only
##    when their data actually changed — see _sig_of_roster().
## 2. NEVER read `size` during _ready(). The control has no size yet, so
##    every font baked itself at the minimum scale and never grew: tiny
##    text beside theme-scaled buttons, and sliders one hairline high
##    stretched across a 4K screen. Scale comes from the VIEWPORT and is
##    re-applied on every resize — see _apply_scale().

var world: Node = null

var _panel: PanelContainer
var _tabs: TabContainer
var _players_box: VBoxContainer
var _map_row: HBoxContainer
var _saved_label: Label
var _saved_row: HBoxContainer
var _server_edit: LineEdit
var _mode_btns: Dictionary = {}
var _length_btns: Dictionary = {}
var _size_btns: Dictionary = {}
var _fly_btns: Dictionary = {}
var _battle_only: Array = []
var _add_bot_btn: Button
var _update_state := "idle"
var _update_req: HTTPRequest
var _update_btn: Button

## Everything that must resize with the window, with the size it was
## designed at. Registered at build time, re-applied whenever the window
## changes — never baked in once.
var _fonts: Array = []   # [[Control, base_px], ...]
var _tab_styles: Array = []  # [[StyleBoxFlat, base_h_margin, base_v_margin]]
var _mins: Array = []    # [[Control, base_w, base_h], ...]
var _last_scale := 0.0

## What each list was last built from. Rebuild only when these change.
var _roster_sig := ""
var _maps_sig := ""

# ------------------------------------------------------------------
# Scale
# ------------------------------------------------------------------

## Sized off the real screen, never off this control's not-yet-known size.
## A 4K TV gets big text, a small window gets small text, both readable.
func _scale() -> float:
	var vp := get_viewport_rect().size
	if vp.x < 1.0:
		vp = Vector2(DisplayServer.window_get_size())
	return clampf(minf(vp.x / 1600.0, vp.y / 900.0), 0.75, 3.2)

func _s(n: int) -> int:
	return int(n * _scale())

## Registers a font so it grows with the window.
func _font(c: Control, base: int) -> Control:
	_fonts.append([c, base])
	c.add_theme_font_size_override("font_size", int(base * _scale()))
	return c

## Registers a minimum size, in design units.
func _min(c: Control, w: int, h: int) -> Control:
	_mins.append([c, w, h])
	c.custom_minimum_size = Vector2(w * _scale(), h * _scale())
	return c

func _apply_scale() -> void:
	var sc := _scale()
	if is_equal_approx(sc, _last_scale):
		return
	_last_scale = sc
	for entry: Array in _fonts:
		var c: Control = entry[0]
		if is_instance_valid(c):
			c.add_theme_font_size_override("font_size", int(int(entry[1]) * sc))
	for entry: Array in _mins:
		var c: Control = entry[0]
		if is_instance_valid(c):
			c.custom_minimum_size = Vector2(int(entry[1]) * sc, int(entry[2]) * sc)
	for entry: Array in _tab_styles:
		var sb: StyleBoxFlat = entry[0]
		sb.content_margin_left = int(entry[1]) * sc
		sb.content_margin_right = int(entry[1]) * sc
		sb.content_margin_top = int(entry[2]) * sc
		sb.content_margin_bottom = int(entry[2]) * sc
	if _panel != null:
		var style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
		if style != null:
			style.set_content_margin_all(int(18 * sc))

# ------------------------------------------------------------------
# Build
# ------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.98)
	style.set_corner_radius_all(16)
	style.set_content_margin_all(18)
	style.border_color = Color(1, 1, 1, 0.1)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.anchor_left = 0.12
	_panel.anchor_right = 0.88
	_panel.anchor_top = 0.10
	_panel.anchor_bottom = 0.90
	_panel.offset_left = 0
	_panel.offset_right = 0
	_panel.offset_top = 0
	_panel.offset_bottom = 0
	add_child(_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	_panel.add_child(outer)
	var title := Label.new()
	title.text = "🌍  World      Esc to close"
	title.add_theme_color_override("font_color", Color("ffd166"))
	outer.add_child(_font(title, 26))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Focusable: that is how the KEYBOARD drives this menu. Pads are kept
	# out in _input(), not by making everything unfocusable (which locked
	# the keyboard out along with them).
	_tabs.focus_mode = Control.FOCUS_ALL
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_ALL
	_fonts.append([_tabs, 26])
	_tabs.add_theme_font_size_override("font_size", _s(26))
	# Tabs need breathing room or they read as one run-on word.
	var tab_bar := _tabs.get_tab_bar()
	for state in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var tb := StyleBoxFlat.new()
		tb.bg_color = Color("ffd166") if state == "tab_selected" \
			else Color(1, 1, 1, 0.10 if state == "tab_hovered" else 0.04)
		tb.set_corner_radius_all(10)
		tb.content_margin_left = 26
		tb.content_margin_right = 26
		tb.content_margin_top = 12
		tb.content_margin_bottom = 12
		_tab_styles.append([tb, 26, 12])
		tab_bar.add_theme_stylebox_override(state, tb)
	tab_bar.add_theme_color_override("font_selected_color", Color("1c2333"))
	tab_bar.add_theme_color_override("font_unselected_color", Color(1, 1, 1, 0.75))
	tab_bar.add_theme_constant_override("h_separation", 8)
	outer.add_child(_tabs)
	_build_map_tab()
	_build_game_tab()
	_build_players_tab()
	_build_video_tab()
	_build_help_tab()
	_build_credits_tab()
	Game.roster_changed.connect(_mark_dirty)
	get_viewport().size_changed.connect(_apply_scale)
	_apply_scale.call_deferred()

func _mark_dirty() -> void:
	_roster_sig = ""

func _input(event: InputEvent) -> void:
	if not visible:
		return
	# Controllers are locked out; their PLAYERS are not (player input is
	# polled, never event-driven), so the kids keep playing regardless.
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		return
	# A focused text box would otherwise eat Escape and trap you in here.
	if event is InputEventKey and event.pressed \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is LineEdit:
			focused.release_focus()

func open() -> void:
	visible = true
	_last_scale = 0.0
	_apply_scale()
	_refresh(true)
	_tabs.get_tab_bar().grab_focus.call_deferred()

func close() -> void:
	visible = false
	# Don't leave the highlight parked on a hidden button — the next Enter
	# in the game world would press it.
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()

func toggle() -> void:
	if visible:
		close()
	else:
		open()

# ------------------------------------------------------------------
# Widgets
# ------------------------------------------------------------------

func _tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	return box

func _heading(parent: Control, text: String, note := "") -> Control:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	parent.add_child(group)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("9fb3d1"))
	group.add_child(_font(label, 21))
	if not note.is_empty():
		var sub := Label.new()
		sub.text = note
		sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
		group.add_child(_font(sub, 15))
	return group

func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row

func _button(text: String, on_press: Callable, base := 19) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.text = text
	_font(btn, base)
	_min(btn, 0, 40)
	btn.pressed.connect(func() -> void:
		on_press.call()
		Sfx.play("tick", -8.0))
	return btn

func _mark(btn: Button, on: bool) -> void:
	if not is_instance_valid(btn):
		return
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
# Map — the world, and how play works in it (both modes)
# ------------------------------------------------------------------

func _build_map_tab() -> void:
	var box := _tab("Map")
	_heading(box, "World")
	_map_row = _row(box)
	_saved_label = Label.new()
	_saved_label.text = "Your own worlds"
	box.add_child(_font(_saved_label, 20))
	_saved_row = _row(box)

	# Size and flying belong to the MAP: they describe how play works
	# here, in whatever mode. They used to live under Battle, which is why
	# changing them looked like it did nothing while just building.
	box.add_child(HSeparator.new())
	_heading(box, "Size of the world",
		"How far out you can roam, in blocks. Applies in both modes.")
	var size_row := _row(box)
	for arena in [50, 100, 150, 200, 250, 300, 350]:
		var blocks: int = arena
		var btn := _button(str(arena), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, -1, -1, blocks, -1))
		_min(btn, 80, 44)
		size_row.add_child(btn)
		_size_btns[arena] = btn

	_heading(box, "Flying", "Double-tap jump to fly. Applies in both modes.")
	var fly_row := _row(box)
	for spec in [[1, "Flying allowed"], [0, "No flying"]]:
		var val: int = spec[0]
		var btn := _button(str(spec[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, -1, -1, -1, val))
		_min(btn, 200, 44)
		fly_row.add_child(btn)
		_fly_btns[val] = btn

	box.add_child(HSeparator.new())
	_heading(box, "Server", "The game connects here by itself on start-up.")
	var server_row := _row(box)
	_server_edit = LineEdit.new()
	_server_edit.text = Game.server_url()
	_server_edit.focus_mode = Control.FOCUS_ALL
	_min(_server_edit, 420, 44)
	_font(_server_edit, 19)
	server_row.add_child(_server_edit)
	var use := _button("Use this server", func() -> void:
		var url := _server_edit.text.strip_edges()
		if url.is_empty():
			return
		if not url.begins_with("ws://") and not url.begins_with("wss://"):
			url = "ws://" + url
		Game.set_server_url(url)
		close()
		# Dropping the link is enough — main.gd shows the reconnecting
		# banner and dials the new address by itself.
		Net.disconnect_now())
	_min(use, 210, 44)
	server_row.add_child(use)

func _refresh_maps() -> void:
	if _map_row == null:
		return
	var current: String = str(world.client_world) if world != null else ""
	var listed := ""
	if world != null:
		for entry in world.map_list:
			listed += str(entry.key) + ","
	var sig := current + "|" + listed
	if sig == _maps_sig:
		return
	_maps_sig = sig
	for child in _map_row.get_children():
		child.queue_free()
	for child in _saved_row.get_children():
		child.queue_free()
	for choice in [["classic", "Island"], ["desert", "Desert"], ["isles", "Isles"],
			["castles", "Castles"], ["city", "City"], ["sky", "Skylands"],
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
	_min(btn, 132, 46)
	if world != null and key == world.client_world:
		_mark(btn, true)
	return btn

# ------------------------------------------------------------------
# Game — what kind of game this is
# ------------------------------------------------------------------

func _build_game_tab() -> void:
	var box := _tab("Game")
	_heading(box, "How are we playing?")
	var mode_row := _row(box)
	for spec in [["creative", "Just building"], ["battle", "Battle royale"]]:
		var key := str(spec[0])
		var btn := _button(str(spec[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_set_mode.rpc_id(1, key), 22)
		_min(btn, 250, 58)
		mode_row.add_child(btn)
		_mode_btns[key] = btn
	var note := Label.new()
	note.text = "Just building is the calm one: no storm, no hearts, nothing can hurt you."
	note.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	box.add_child(_font(note, 15))

	box.add_child(HSeparator.new())
	# Battle-only settings are hidden outright in creative rather than
	# greyed out — one less thing for a child to poke at.
	_battle_only.append(_heading(box, "Battle settings",
		"Only used in battle royale. The world's size and flying live on the Map tab."))
	_battle_only.append(_heading(box, "How long a battle lasts"))
	var len_row := _row(box)
	_battle_only.append(len_row)
	for preset in [[3, "3 min"], [5, "5 min"], [8, "8 min"], [60, "Unlimited"]]:
		var minutes: int = preset[0]
		var btn := _button(str(preset[1]), func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, minutes, -1, -1, -1))
		_min(btn, 132, 44)
		len_row.add_child(btn)
		_length_btns[minutes] = btn

# ------------------------------------------------------------------
# Players
# ------------------------------------------------------------------

func _build_players_tab() -> void:
	var box := _tab("Players")
	_heading(box, "Teams and computer players")
	var manage := _row(box)
	var add_team := _button("Add a team", func() -> void:
		if Game.world != null:
			Game.world.sv_add_team.rpc_id(1))
	_min(add_team, 210, 48)
	manage.add_child(add_team)
	var rm_team := _button("Remove a team", func() -> void:
		if Game.world != null:
			Game.world.sv_remove_team.rpc_id(1, -1))
	_min(rm_team, 220, 48)
	manage.add_child(rm_team)
	_add_bot_btn = _button("Add a computer player", func() -> void:
		if Game.world != null:
			Game.world.sv_add_bot.rpc_id(1))
	_min(_add_bot_btn, 280, 48)
	manage.add_child(_add_bot_btn)
	var rm_bot := _button("Remove one", func() -> void:
		if Game.world != null:
			Game.world.sv_remove_bot.rpc_id(1, ""))
	_min(rm_bot, 190, 48)
	manage.add_child(rm_bot)

	_heading(box, "Everyone playing",
		"Click a name to type a new one. Click a colour to change team.")
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 6)
	box.add_child(_players_box)

## Rows are rebuilt ONLY when this changes — never on a timer. Rebuilding
## every frame destroyed the text box you were typing into.
func _sig_of_roster() -> String:
	var teams: int = world.team_count if world != null else 4
	var ids: Array = Game.roster.keys()
	ids.sort()
	var out := "t%d|" % teams
	for id: String in ids:
		var e: Dictionary = Game.roster[id]
		out += "%s:%s:%s:%s;" % [id, e.get("name", ""), e.get("team", -1),
			e.get("bot", false)]
	return out

func _refresh_players() -> void:
	if _players_box == null:
		return
	var sig := _sig_of_roster()
	if sig == _roster_sig:
		return
	# Never yank a text box out from under someone mid-rename.
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit and _players_box.is_ancestor_of(focused):
		return
	_roster_sig = sig
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
		_players_box.add_child(_player_row(id, team_count))

func _player_row(id: String, team_count: int) -> HBoxContainer:
	var entry: Dictionary = Game.roster[id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var tag := Label.new()
	tag.text = "🤖" if bool(entry.get("bot", false)) else "🙂"
	row.add_child(_font(tag, 22))
	var name_edit := LineEdit.new()
	name_edit.text = str(entry.name)
	name_edit.max_length = 12
	name_edit.focus_mode = Control.FOCUS_ALL
	_min(name_edit, 210, 44)
	_font(name_edit, 20)
	name_edit.text_submitted.connect(func(text: String) -> void:
		Game.sv_rename_any.rpc_id(1, id, text)
		name_edit.release_focus()
		Sfx.play("pop", -6.0))
	name_edit.focus_exited.connect(func() -> void:
		if name_edit.text != str(Game.roster.get(id, {}).get("name", "")):
			Game.sv_rename_any.rpc_id(1, id, name_edit.text))
	row.add_child(name_edit)
	var team := int(entry.get("team", -1))
	for t in team_count:
		row.add_child(_team_cell(id, t, team))
	var kick := _button("✕", func() -> void:
		Game.sv_kick_player.rpc_id(1, id)
		Sfx.play("pop", -6.0), 20)
	kick.tooltip_text = "Remove this player"
	kick.add_theme_color_override("font_color", Color("ff6b6b"))
	_min(kick, 50, 44)
	row.add_child(kick)
	return row

func _team_cell(id: String, t: int, current: int) -> Button:
	var entry: Dictionary = Game.roster[id]
	var cell := Button.new()
	cell.focus_mode = Control.FOCUS_ALL
	_min(cell, 80, 42)
	cell.text = WorldNode.TEAM_NAMES[t] if t < WorldNode.TEAM_NAMES.size() else str(t)
	_font(cell, 16)
	var cell_style := StyleBoxFlat.new()
	cell_style.bg_color = WorldNode.TEAM_COLORS[t] * (1.0 if t == current else 0.32)
	cell_style.bg_color.a = 1.0
	cell_style.set_corner_radius_all(6)
	if t == current:
		cell_style.border_color = Color.WHITE
		cell_style.set_border_width_all(2)
	for state in ["normal", "hover", "pressed"]:
		cell.add_theme_stylebox_override(state, cell_style)
	cell.add_theme_color_override("font_color", Color(0.1, 0.1, 0.14))
	var slot := int(entry.slot)
	var mine: bool = int(entry.peer) == multiplayer.get_unique_id() \
		and Game.local_inputs.has(slot)
	cell.pressed.connect(func() -> void:
		if mine:
			Game.set_local_team(slot, t)
		elif Game.world != null:
			Game.world.sv_set_bot_team.rpc_id(1, id, t)
		Sfx.play("tick", -8.0))
	return cell

# ------------------------------------------------------------------
# Video / Help / Credits
# ------------------------------------------------------------------

func _build_video_tab() -> void:
	var box := _tab("Video")
	_stepper(box, "Draw distance", "dist_blocks", 32, 208, 16, "%d blocks")
	_stepper(box, "3D resolution", "render_scale", 10, 100, 5, "%d%%")
	_stepper(box, "Shadow quality", "shadow_quality", 0, 2, 1, "%d")
	for spec in [["shadows", "Shadows"], ["ssao", "Contact shading (SSAO)"],
			["glow", "Glow"], ["lights", "Dynamic lights"],
			["water_shine", "Shiny water"], ["ao", "Corner shading"],
			["wire", "Wireframe"]]:
		var key := str(spec[0])
		var label := str(spec[1])
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_ALL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_font(btn, 19)
		_min(btn, 0, 44)
		btn.text = ("☑  " if Game.video[key] else "☐  ") + label
		btn.pressed.connect(func() -> void:
			Game.video[key] = not bool(Game.video[key])
			btn.text = ("☑  " if Game.video[key] else "☐  ") + label
			Game.video_changed.emit()
			Sfx.play("tick", -10.0))
		box.add_child(btn)
	var is_lite := RenderingServer.get_rendering_device() == null
	var rb := _button("Renderer: " + ("Lite" if is_lite else "Full")
		+ "   (restarts the game)", func() -> void:
		Game.relaunch_with_renderer(not is_lite))
	rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(rb)
	if not OS.has_feature("editor") and (OS.has_feature("windows") or OS.has_feature("linux")):
		_update_btn = _button("Check for updates", func() -> void: _updater_step())
		_update_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_update_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(_update_btn)

## A stepper: [ − ]  value  [ + ].
##
## NOT a slider. Godot draws a slider's track and knob from fixed-pixel
## theme textures that ignore custom_minimum_size, so on a 4K screen the
## "Shadow quality 0/1/2" setting rendered as a hairline stretched across
## the whole TV. Buttons scale with everything else, and for a
## three-value setting they're easier for a child to hit anyway.
func _stepper(parent: Control, label: String, key: String, low: int, high: int,
		step: int, fmt: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)
	var name_label := Label.new()
	name_label.text = label
	_min(name_label, 260, 0)
	row.add_child(_font(name_label, 20))
	var value_label := Label.new()
	value_label.text = fmt % int(Game.video[key])
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_min(value_label, 190, 0)
	_font(value_label, 20)
	var nudge := func(dir: int) -> void:
		var v := clampi(int(Game.video[key]) + dir * step, low, high)
		Game.video[key] = v
		value_label.text = fmt % v
		Game.video_changed.emit()
	var minus := _button("−", func() -> void: nudge.call(-1), 24)
	_min(minus, 78, 48)
	row.add_child(minus)
	row.add_child(value_label)
	var plus := _button("+", func() -> void: nudge.call(1), 24)
	_min(plus, 78, 48)
	row.add_child(plus)

func _build_help_tab() -> void:
	var box := _tab("Help")
	for line in ["Esc  —  this menu (keyboard and mouse)",
			"X / Start  —  your own blocks, kits and character (controller)",
			"E  —  the same picker on the keyboard",
			"LB / RB  —  flip through the picker's tabs",
			"D-pad ◀ ▶  —  swap what you're holding",
			"A / Space  —  jump.  Double-tap to fly (when it's allowed)",
			"RT / R  —  throw or shoot.  LT  —  dig",
			"Walk into a dragon to ride it; double-tap A to hop off",
			"Grapple a block and it reels you up on top of it"]:
		var label := Label.new()
		label.text = "•  " + str(line)
		box.add_child(_font(label, 19))

func _build_credits_tab() -> void:
	var box := _tab("Credits")
	_heading(box, "This game stands on other people's work — thank you")
	for group: String in Credits.groups():
		var head := Label.new()
		head.text = group
		head.add_theme_color_override("font_color", Color("ffd166"))
		box.add_child(_font(head, 21))
		for entry: Dictionary in Credits.in_group(group):
			var line := Label.new()
			line.text = "   %s — %s  (%s)\n      %s" % [str(entry.name),
				str(entry.by), str(entry.license), str(entry.what)]
			box.add_child(_font(line, 17))
	if not Credits.builds().is_empty():
		var builds_head := Label.new()
		builds_head.text = "Imported builds"
		builds_head.add_theme_color_override("font_color", Color("ffd166"))
		box.add_child(_font(builds_head, 21))
		for entry: Dictionary in Credits.builds():
			var line := Label.new()
			line.text = "   %s — built by %s  (%s)" % [str(entry.get("name", "?")),
				str(entry.get("by", "unknown")), str(entry.get("license", "?"))]
			box.add_child(_font(line, 17))

# ------------------------------------------------------------------
# Self-updater
# ------------------------------------------------------------------

func _updater_base() -> String:
	return "http://%s:30811/downloads" % Net.last_host

func _local_version() -> String:
	var f := FileAccess.open("res://version.txt", FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else "dev"

func _set_update_text(text: String) -> void:
	if _update_btn != null:
		_update_btn.text = text

func _updater_step() -> void:
	if _update_state == "busy":
		return
	if _update_req == null:
		_update_req = HTTPRequest.new()
		add_child(_update_req)
	if _update_state == "idle":
		_update_state = "busy"
		_set_update_text("Checking…")
		_update_req.download_file = ""
		_update_req.request_completed.connect(
			func(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
				_update_state = "idle"
				if code != 200:
					_set_update_text("Couldn't reach the server — try again")
					return
				var remote := body.get_string_from_utf8().strip_edges()
				if remote.is_empty() or remote == _local_version():
					_set_update_text("Up to date — check again")
				else:
					_update_state = "ready"
					_set_update_text("Update ready — click to install"),
			CONNECT_ONE_SHOT)
		_update_req.request(_updater_base() + "/version.txt")
	elif _update_state == "ready":
		_update_state = "busy"
		_set_update_text("Downloading… (the game restarts itself)")
		var fname := "voxel-battle-windows.exe" if OS.has_feature("windows") \
			else "voxel-battle-linux.x86_64"
		var dest := ProjectSettings.globalize_path("user://update-download")
		_update_req.download_file = dest
		_update_req.request_completed.connect(
			func(_r: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
				if code != 200 or not _downloaded_a_program(dest):
					DirAccess.remove_absolute(dest)
					_update_state = "idle"
					_set_update_text("Download failed — try again")
					return
				_apply_update(dest),
			CONNECT_ONE_SHOT)
		_update_req.request(_updater_base() + "/" + fname)

## Never hand a half-download (or a 404 page) to _apply_update: it is
## about to replace the game with it. Real builds are tens of MB and start
## with MZ (Windows) or ELF (Linux).
func _downloaded_a_program(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var size := f.get_length()
	var magic := f.get_buffer(4)
	f.close()
	if size < 4 * 1024 * 1024 or magic.size() < 4:
		return false
	if OS.has_feature("windows"):
		return magic[0] == 0x4D and magic[1] == 0x5A          # "MZ"
	return magic[0] == 0x7F and magic[1] == 0x45 \
		and magic[2] == 0x4C and magic[3] == 0x46             # "\x7FELF"

## Swap the running program for the downloaded one, keeping the old file
## until the new one is safely in place — a failure must leave a working
## game behind, not no game at all.
func _apply_update(new_file: String) -> void:
	var exe := OS.get_executable_path()
	if OS.has_feature("windows"):
		var bat_path := ProjectSettings.globalize_path("user://apply-update.bat")
		var bat := FileAccess.open(bat_path, FileAccess.WRITE)
		# %1 = running exe, %2 = downloaded file.
		#
		# The old script DELETED the exe first and only then moved the new
		# one in, so anything going wrong after the delete (a locked file,
		# a bad path, the move failing) left no executable at all — which
		# is exactly what happened on Windows: the app vanished and the
		# file was never replaced. Now the old exe is RENAMED aside, and
		# put back if the move fails.
		bat.store_string("@echo off\r\n"
			+ "set \"TARGET=%~1\"\r\n"
			+ "set \"FRESH=%~2\"\r\n"
			+ "set \"BACKUP=%~1.old\"\r\n"
			+ "del \"%BACKUP%\" >nul 2>&1\r\n"
			+ "set /a TRIES=0\r\n"
			+ ":retry\r\n"
			+ "timeout /t 1 /nobreak >nul\r\n"
			+ "move /y \"%TARGET%\" \"%BACKUP%\" >nul 2>&1\r\n"
			+ "if not exist \"%TARGET%\" goto swap\r\n"
			+ "set /a TRIES+=1\r\n"
			+ "if %TRIES% LSS 15 goto retry\r\n"
			+ "start \"\" \"%TARGET%\"\r\n"
			+ "exit /b\r\n"
			+ ":swap\r\n"
			+ "move /y \"%FRESH%\" \"%TARGET%\" >nul 2>&1\r\n"
			+ "if not exist \"%TARGET%\" move /y \"%BACKUP%\" \"%TARGET%\" >nul 2>&1\r\n"
			+ "start \"\" \"%TARGET%\"\r\n"
			+ "del \"%BACKUP%\" >nul 2>&1\r\n")
		bat.close()
		OS.create_process("cmd.exe", ["/C", bat_path, exe, new_file])
	else:
		DirAccess.remove_absolute(exe + ".old")
		if DirAccess.rename_absolute(exe, exe + ".old") != OK:
			_update_state = "idle"
			_set_update_text("Couldn't replace the game — try again")
			return
		if DirAccess.rename_absolute(new_file, exe) != OK:
			DirAccess.rename_absolute(exe + ".old", exe)
			_update_state = "idle"
			_set_update_text("Couldn't replace the game — try again")
			return
		OS.execute("chmod", ["+x", exe])
		OS.create_process(exe, [])
	get_tree().quit()

# ------------------------------------------------------------------

func _refresh(force := false) -> void:
	if not visible:
		return
	if force:
		_maps_sig = ""
		_roster_sig = ""
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
	var battling: bool = world.client_mode == "battle"
	for node in _battle_only:
		if is_instance_valid(node):
			(node as Control).visible = battling

var _auto_ms := 0
var _tick := 0.0

func _process(delta: float) -> void:
	if OS.get_environment("WORLD_MENU_TEST") == "1" and not visible:
		_auto_ms += int(delta * 1000.0)
		if _auto_ms > 12000:
			open()
			var want := OS.get_environment("WORLD_MENU_TAB")
			if want.is_valid_int() and _tabs != null:
				_tabs.current_tab = clampi(want.to_int(), 0,
					_tabs.get_tab_count() - 1)
	if not visible:
		return
	# Four times a second, and a no-op unless something actually changed.
	# This used to run every frame and rebuild every row from scratch.
	_tick += delta
	if _tick < 0.25:
		return
	_tick = 0.0
	_refresh()
