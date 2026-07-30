class_name PlayerHud
extends Control
## Per-player overlay inside their split-screen cell: name chip (click the
## swatch to change your look, click the name to type a new one), treasure
## counter, and the block hotbar along the bottom.

var slot := -1
var world: Node = null

## Hat swatch colors: the hat itself is 3D, so the chip just needs a
## distinct color per index so clicks visibly cycle something.
const HAT_CHIP_COLORS: Array[Color] = [
	Color("8d6748"), Color("ffd166"), Color("f0b429"), Color("4a9df8"),
	Color("ff9ff3"), Color("1dd1a1"), Color("f5f6fa"),
]

var _name_label: Label
var _name_edit: LineEdit
var _treasure_label: Label
var _hearts_label: Label
var _selected_label: Label
var _picker: BlockPicker
var _pickers: Array = []
var _menu_slots_row: HBoxContainer
var _menu_slot_buttons: Array = []

func _uscale() -> float:
	return clampf(DisplayServer.window_get_size().x / 1100.0, 1.15, 3.0)
var _menu: PanelContainer
var _tabs: TabContainer
var _prev_picker := false
var _prev_menu := false


var _chip: PanelContainer
var _hotbar: HBoxContainer
var _chips: Array = []
var _last_index := -1
var _last_style := -1
var _last_width := -1.0
var _last_held := ""
var _slots_dirty := true
var _prev_slot_pick_menu := -1
var _menu_tab_latch := false
var _preview_viewport: SubViewport
var _preview_avatar: Node3D
var _preview_angle := PI
var _last_tab := 1
var _tab_guard := false
var _radar: TextureRect
var _radar_tick := 0
var _clock: Label
var _storm_tint: ColorRect
var _water_tint: ColorRect
var _autoopened := false
var _crosshair: Label
var _storm_arrow: Label

func _us(n: int) -> int:
	return int(n * clampf(DisplayServer.window_get_size().x / 1100.0, 1.15, 3.0))

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Top-left: identity chip.
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08, 0.72)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	chip.add_theme_stylebox_override("panel", style)
	chip.position = Vector2(10, 10)
	_chip = chip
	add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", _us(22))
	_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_edit_name())
	row.add_child(_name_label)
	_treasure_label = Label.new()
	_treasure_label.add_theme_font_size_override("font_size", _us(22))
	_treasure_label.add_theme_color_override("font_color", Color("ffd166"))
	row.add_child(_treasure_label)
	_hearts_label = Label.new()
	_hearts_label.add_theme_font_size_override("font_size", _us(22))
	_hearts_label.add_theme_color_override("font_color", Color("ff6b6b"))
	row.add_child(_hearts_label)

	# Bottom: hotbar.
	var bar_holder := CenterContainer.new()
	bar_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_holder.offset_top = -150
	bar_holder.offset_bottom = -8
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_holder)
	var bar_panel := PanelContainer.new()
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.04, 0.05, 0.08, 0.6)
	bar_style.set_corner_radius_all(10)
	bar_style.set_content_margin_all(6)
	bar_panel.add_theme_stylebox_override("panel", bar_style)
	bar_holder.add_child(bar_panel)
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 2)
	bar_panel.add_child(_hotbar)
	# Eight big Minecraft-style slots; 1-8 keys (or bumpers/D-pad) select.
	for i in 8:
		var frame := Panel.new()
		frame.custom_minimum_size = Vector2(52, 52)
		var icon := BlockIcon.new(0)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 7
		icon.offset_top = 7
		icon.offset_right = -7
		icon.offset_bottom = -7
		frame.add_child(icon)
		var num := Label.new()
		num.text = str(i + 1)
		num.add_theme_font_size_override("font_size", _us(12))
		num.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
		frame.add_child(num)
		_hotbar.add_child(frame)
		_chips.append(frame)
	_selected_label = Label.new()
	_selected_label.add_theme_font_size_override("font_size", _us(15))
	_selected_label.add_theme_color_override("font_color", Color("ffd166"))
	_selected_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_selected_label.add_theme_constant_override("outline_size", 5)
	_selected_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_selected_label.offset_top = -168
	_selected_label.offset_bottom = -134
	_selected_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_selected_label)

	# Tabbed menu (Esc / Start), also home of the block picker (E jumps
	# straight to the Blocks tab). Minecraft brains expected this.
	_menu = PanelContainer.new()
	var menu_style := StyleBoxFlat.new()
	menu_style.bg_color = Color(0.05, 0.06, 0.1, 0.94)
	menu_style.set_corner_radius_all(14)
	menu_style.set_content_margin_all(12)
	menu_style.border_color = Color(1, 1, 1, 0.08)
	menu_style.set_border_width_all(1)
	_menu.add_theme_stylebox_override("panel", menu_style)
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = Color(0.14, 0.16, 0.23)
	btn_normal.set_corner_radius_all(9)
	btn_normal.content_margin_left = _us(14)
	btn_normal.content_margin_right = _us(14)
	btn_normal.content_margin_top = _us(7)
	btn_normal.content_margin_bottom = _us(7)
	var btn_hover: StyleBoxFlat = btn_normal.duplicate()
	btn_hover.bg_color = Color(0.22, 0.25, 0.35)
	var btn_pressed: StyleBoxFlat = btn_normal.duplicate()
	btn_pressed.bg_color = Color(0.55, 0.44, 0.15)
	var menu_theme := Theme.new()
	menu_theme.set_stylebox("normal", "Button", btn_normal)
	menu_theme.set_stylebox("hover", "Button", btn_hover)
	menu_theme.set_stylebox("pressed", "Button", btn_pressed)
	menu_theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	var tab_sel := StyleBoxFlat.new()
	tab_sel.bg_color = Color(0.2, 0.23, 0.33)
	tab_sel.set_corner_radius_all(8)
	tab_sel.corner_radius_bottom_left = 0
	tab_sel.corner_radius_bottom_right = 0
	tab_sel.content_margin_left = _us(16)
	tab_sel.content_margin_right = _us(16)
	tab_sel.content_margin_top = _us(8)
	tab_sel.content_margin_bottom = _us(8)
	tab_sel.border_width_bottom = 3
	tab_sel.border_color = Color("ffd166")
	var tab_un: StyleBoxFlat = tab_sel.duplicate()
	tab_un.bg_color = Color(0.09, 0.1, 0.15)
	tab_un.border_width_bottom = 0
	menu_theme.set_stylebox("tab_selected", "TabContainer", tab_sel)
	menu_theme.set_stylebox("tab_unselected", "TabContainer", tab_un)
	menu_theme.set_stylebox("tab_hovered", "TabContainer", tab_sel.duplicate())
	menu_theme.set_color("font_selected_color", "TabContainer", Color("ffd166"))
	_menu.theme = menu_theme
	# Fill ~90% of this player's cell whatever its size — quarter-screen
	# split or a huge fullscreen window alike.
	_menu.anchor_left = 0.1
	_menu.anchor_right = 0.9
	_menu.anchor_top = 0.08
	_menu.anchor_bottom = 0.86
	_menu.visible = false
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu)
	_tabs = TabContainer.new()
	_tabs.get_tab_bar().focus_mode = Control.FOCUS_NONE
	_tabs.add_theme_font_size_override("font_size", _us(20))
	_menu.add_child(_tabs)
	_tabs.tab_changed.connect(func(tab: int) -> void:
		if not _tab_guard:
			_last_tab = tab)
	_storm_tint = ColorRect.new()
	_storm_tint.color = Color(0.9, 0.15, 0.1, 0.0)
	_storm_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_storm_tint)
	_water_tint = ColorRect.new()
	_water_tint.color = Color(0.1, 0.3, 0.6, 0.0)
	_water_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water_tint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_water_tint)
	_clock = Label.new()
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.add_theme_font_size_override("font_size", _us(14))
	_clock.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_clock.add_theme_constant_override("outline_size", 4)
	add_child(_clock)
	_radar = TextureRect.new()
	_radar.stretch_mode = TextureRect.STRETCH_SCALE
	_radar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_radar)
	var radar_timer := Timer.new()
	radar_timer.wait_time = 0.6
	radar_timer.timeout.connect(_update_radar)
	add_child(radar_timer)
	radar_timer.start()
	_storm_arrow = Label.new()
	_storm_arrow.add_theme_font_size_override("font_size", _us(30))
	_storm_arrow.add_theme_color_override("font_color", Color("ff5a4a"))
	_storm_arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_storm_arrow.add_theme_constant_override("outline_size", 8)
	_storm_arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_storm_arrow.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_storm_arrow.offset_top = _us(70)
	_storm_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_storm_arrow.visible = false
	add_child(_storm_arrow)
	# First-person crosshair.
	_crosshair = Label.new()
	_crosshair.text = "+"
	_crosshair.add_theme_font_size_override("font_size", _us(30))
	_crosshair.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	_crosshair.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_crosshair.add_theme_constant_override("outline_size", 4)
	_crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_crosshair.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_crosshair.grow_vertical = Control.GROW_DIRECTION_BOTH
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)

	_pickers = []
	for spec in [["Tools", "tools"], ["Blocks", "blocks"], ["Special", "special"], ["Kits", "kits"]]:
		var picker := BlockPicker.new(spec[1])
		picker.name = spec[0]
		picker.picked.connect(_on_picked)
		_tabs.add_child(picker)
		_pickers.append(picker)
	_picker = _pickers[0]
	_build_character_tab()
	_build_game_tab()
	_build_video_tab()
	# The 8 slots live inside the menu too: click a slot, then click items.
	_menu_slots_row = HBoxContainer.new()
	_menu_slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_menu_slots_row.add_theme_constant_override("separation", int(6 * _uscale()))
	var menu_box := _menu.get_child(0)
	_menu.remove_child(menu_box)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", int(8 * _uscale()))
	_menu.add_child(outer)
	outer.add_child(menu_box)
	menu_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(_menu_slots_row)
	_menu_slots_row.visible = false  # the bottom hotbar is the real one
	for i in 8:
		var slot_btn := Button.new()
		slot_btn.focus_mode = Control.FOCUS_NONE
		slot_btn.custom_minimum_size = Vector2(_us(46), _us(46))
		var icon := BlockIcon.new(0)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		slot_btn.add_child(icon)
		var index := i
		slot_btn.pressed.connect(func() -> void:
			var player := _player()
			if player != null:
				player.selected_slot = index
				_slots_dirty = true
				Sfx.play("tick", -10.0))
		_menu_slots_row.add_child(slot_btn)
		_menu_slot_buttons.append(slot_btn)

	if world != null:
		world.treasures_changed.connect(_refresh_identity)
		world.survival_changed.connect(_refresh_identity)
		world.hearts_changed.connect(_refresh_identity)
		world.match_changed.connect(_on_match_changed)
	Game.roster_changed.connect(_refresh_identity)
	_refresh_identity()

func is_ui_open() -> bool:
	return _menu != null and _menu.visible

func _toggle_menu(player: Player, _tab: int) -> void:
	if _menu.visible:
		_close_menu()
		return
	_menu.visible = true
	_tabs.set_tab_disabled(0, world != null and world.match_phase != "IDLE")
	_refresh_preview()
	player.ui_locked = true
	# picker.open() flips child visibility, which yanks the TabContainer onto
	# whichever picker was shown last (the "always opens on Kits" bug) — so
	# the pickers open FIRST and the real tab is set after, guarded so the
	# churn doesn't pollute _last_tab.
	_tab_guard = true
	for picker: BlockPicker in _pickers:
		picker.fit(size * Vector2(0.75, 0.66))
		picker.open()
	_tabs.current_tab = 1 if _tabs.is_tab_disabled(_last_tab) else _last_tab
	_tab_guard = false
	var entry := _entry()
	if _name_edit != null and not entry.is_empty():
		_name_edit.text = str(entry.name)
	Sfx.play("tick", -8.0)

## "Character" tab: big friendly buttons for name, skin, shirt and hat.
func _build_character_tab() -> void:
	var char_scroll := ScrollContainer.new()
	char_scroll.name = "Character"
	char_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(char_scroll)
	var split := HBoxContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", _us(36))
	char_scroll.add_child(split)
	var char_right := VBoxContainer.new()
	char_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	char_right.add_theme_constant_override("separation", _us(10))
	var tab := VBoxContainer.new()
	tab.add_theme_constant_override("separation", _us(14))
	split.add_child(tab)
	var prof_row := HBoxContainer.new()
	prof_row.add_theme_constant_override("separation", _us(10))
	tab.add_child(prof_row)
	var prof_label := Label.new()
	prof_label.text = "Character:"
	prof_label.custom_minimum_size = Vector2(_us(140), 0)
	prof_label.add_theme_font_size_override("font_size", _us(22))
	prof_row.add_child(prof_label)
	for direction in [-1, 1]:
		var pbtn := Button.new()
		pbtn.focus_mode = Control.FOCUS_NONE
		pbtn.text = "◀" if direction < 0 else "▶"
		pbtn.add_theme_font_size_override("font_size", _us(15))
		var pd: int = direction
		pbtn.pressed.connect(func() -> void:
			var profiles: Array = Game.list_profiles()
			if profiles.is_empty():
				return
			var current := str(Game.profile_keys.get(slot, ""))
			var index := profiles.find(current)
			index = posmod(index + pd, profiles.size())
			Game.select_profile(slot, str(profiles[index]))
			Sfx.play("pop", -6.0))
		prof_row.add_child(pbtn)
	tab.add_child(HSeparator.new())
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", _us(10))
	char_right.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.add_theme_font_size_override("font_size", _us(22))
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	var name_edit := _name_edit
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(_us(220), 0)
	name_edit.add_theme_font_size_override("font_size", _us(22))
	name_edit.text_submitted.connect(func(text: String) -> void:
		Game.set_local_name(slot, text)
		Sfx.play("pop", -4.0))
	name_row.add_child(name_edit)
	for attr in AvatarFactory.ATTRS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _us(10))
		tab.add_child(row)
		var attr_label := Label.new()
		attr_label.text = {"body": "Skin tone:", "face": "Face:", "hair": "Hair:",
			"hat": "Hat:", "shirt": "Shirt:", "pants": "Pants:", "shoes": "Shoes:",
			"gear": "Gear:"}[attr]
		attr_label.custom_minimum_size = Vector2(_us(140), 0)
		attr_label.add_theme_font_size_override("font_size", _us(22))
		row.add_child(attr_label)
		var attr_name := str(attr)
		for direction in [-1, 1]:
			var btn := Button.new()
			btn.text = "◀" if direction < 0 else "▶"
			btn.add_theme_font_size_override("font_size", _us(15))
			var d: int = direction
			btn.pressed.connect(func() -> void:
				Game.cycle_local_style(slot, attr_name, d)
				Sfx.play("pop", -6.0))
			row.add_child(btn)
	_preview_viewport = SubViewport.new()
	_preview_viewport.own_world_3d = true
	_preview_viewport.transparent_bg = true
	_preview_viewport.size = Vector2i(_us(330), _us(430))
	var holder := SubViewportContainer.new()
	holder.stretch = false
	holder.add_child(_preview_viewport)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseMotion \
				and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_preview_angle = fposmod(_preview_angle + event.relative.x * 0.012, TAU)
			if _preview_avatar != null and is_instance_valid(_preview_avatar):
				_preview_avatar.rotation.y = _preview_angle)
	char_right.add_child(holder)
	split.add_child(char_right)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.9, 2.6)
	_preview_viewport.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	_preview_viewport.add_child(sun)


## "Game" tab: battle royale (with options and teams inline), world picker
## and computer players — grouped into tidy sections.
func _build_game_tab() -> void:
	var tab := _scrolled_tab("Game")
	tab.add_theme_constant_override("separation", _us(10))
	_add_section(tab, "⚔  BATTLE ROYALE")
	var br := Button.new()
	br.focus_mode = Control.FOCUS_NONE
	br.text = "🏆  Start Battle Royale"
	br.add_theme_font_size_override("font_size", _us(24))
	br.pressed.connect(func() -> void:
		if Game.world != null and Game.world.match_phase == "IDLE":
			Game.world.sv_match_start.rpc_id(1, 0)
			Sfx.play("cheer", -10.0))
	tab.add_child(br)
	var length_row := HBoxContainer.new()
	length_row.add_theme_constant_override("separation", _us(8))
	tab.add_child(length_row)
	var length_label := Label.new()
	length_label.text = "Game length:"
	length_label.add_theme_font_size_override("font_size", _us(20))
	length_row.add_child(length_label)
	for preset in [[3, "3 min"], [5, "5 min"], [8, "8 min"], [60, "Unlimited"]]:
		var preset_btn := Button.new()
		preset_btn.focus_mode = Control.FOCUS_NONE
		preset_btn.text = str(preset[1])
		preset_btn.add_theme_font_size_override("font_size", _us(18))
		var minutes: int = preset[0]
		preset_btn.pressed.connect(func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, minutes, -1)
			Sfx.play("tick", -8.0))
		length_row.add_child(preset_btn)
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", _us(8))
	tab.add_child(size_row)
	var size_label := Label.new()
	size_label.text = "Arena size:"
	size_label.add_theme_font_size_override("font_size", _us(20))
	size_row.add_child(size_label)
	for arena in [50, 100, 150, 200, 250]:
		var size_btn := Button.new()
		size_btn.focus_mode = Control.FOCUS_NONE
		size_btn.text = str(arena)
		size_btn.add_theme_font_size_override("font_size", _us(18))
		var blocks: int = arena
		size_btn.pressed.connect(func() -> void:
			if Game.world != null:
				Game.world.sv_match_config.rpc_id(1, -1, -1, blocks)
			Sfx.play("tick", -8.0))
		size_row.add_child(size_btn)
	var teams_label := Label.new()
	teams_label.text = "Teams:"
	teams_label.add_theme_font_size_override("font_size", _us(20))
	tab.add_child(teams_label)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", _us(4))
	tab.add_child(_team_box)
	_add_section(tab, "🌍  WORLD")
	var gen_label := Label.new()
	gen_label.text = "Generated worlds:"
	gen_label.add_theme_font_size_override("font_size", _us(18))
	tab.add_child(gen_label)
	_world_row = HBoxContainer.new()
	_world_row.add_theme_constant_override("separation", _us(6))
	tab.add_child(_world_row)
	_maps_label = Label.new()
	_maps_label.text = "Maps:"
	_maps_label.add_theme_font_size_override("font_size", _us(18))
	tab.add_child(_maps_label)
	_maps_row = HBoxContainer.new()
	_maps_row.add_theme_constant_override("separation", _us(6))
	tab.add_child(_maps_row)
	_rebuild_world_row()
	if world != null:
		world.map_list_changed.connect(_rebuild_world_row)
	_add_section(tab, "👥  PLAYERS")
	var bot_row := HBoxContainer.new()
	bot_row.add_theme_constant_override("separation", _us(8))
	tab.add_child(bot_row)
	var bot_btn := Button.new()
	bot_btn.focus_mode = Control.FOCUS_NONE
	bot_btn.text = "➕  Add computer player"
	bot_btn.add_theme_font_size_override("font_size", _us(20))
	bot_btn.pressed.connect(func() -> void:
		Game.join_local(BotSlot.new(randi() % 1000))
		Sfx.play("join"))
	bot_row.add_child(bot_btn)
	var bot_off := Button.new()
	bot_off.focus_mode = Control.FOCUS_NONE
	bot_off.text = "➖  Remove computer player"
	bot_off.add_theme_font_size_override("font_size", _us(20))
	bot_off.pressed.connect(func() -> void:
		var slots: Array = Game.local_inputs.keys()
		slots.sort()
		slots.reverse()
		for bot_slot: int in slots:
			if Game.local_inputs[bot_slot] is BotSlot:
				Game.leave_local(bot_slot)
				Sfx.play("pop")
				return)
	bot_row.add_child(bot_off)

## Generated themes on one row; the server's imported map library below.
func _rebuild_world_row() -> void:
	if _world_row == null:
		return
	for child in _world_row.get_children():
		child.queue_free()
	for child in _maps_row.get_children():
		child.queue_free()
	for choice in [["classic", "Classic"], ["desert", "Desert"], ["isles", "Isles"],
			["castles", "Castle"], ["city", "City"], ["sky", "Skylands"]]:
		_world_row.add_child(_map_button(str(choice[0]), str(choice[1])))
	var have_maps: bool = world != null and not world.map_list.is_empty()
	_maps_label.visible = have_maps
	_maps_row.visible = have_maps
	if have_maps:
		for entry in world.map_list:
			_maps_row.add_child(_map_button(str(entry.key), str(entry.name)))

func _map_button(map_key: String, map_name: String) -> Button:
	var map_btn := Button.new()
	map_btn.focus_mode = Control.FOCUS_NONE
	map_btn.text = map_name
	map_btn.add_theme_font_size_override("font_size", _us(18))
	map_btn.pressed.connect(func() -> void:
		if Game.world != null:
			Game.world.sv_new_map.rpc_id(1, map_key)
			_close_menu()
		Sfx.play("warp", -8.0))
	return map_btn

## A tab whose content scrolls vertically instead of overflowing.
func _scrolled_tab(tab_name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box

func _add_section(tab: Control, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", _us(16))
	lbl.add_theme_color_override("font_color", Color("ffd166"))
	tab.add_child(lbl)
	tab.add_child(HSeparator.new())

func _refresh_preview() -> void:
	if _preview_viewport == null:
		return
	if _preview_avatar != null:
		_preview_avatar.queue_free()
	var entry := _entry()
	_preview_viewport.size = Vector2i(
		maxi(150, mini(_us(520), int(size.x * 0.42))),
		maxi(200, mini(_us(660), int(size.y * 0.72))))
	_preview_avatar = AvatarFactory.build_character(entry.get("style", {}))
	_preview_avatar.position = Vector3(0, 0, 0)
	_preview_avatar.rotation.y = _preview_angle
	_preview_viewport.add_child(_preview_avatar)

## Personal radar: terrain around YOU, plus blips — crates gold, other
## players team-colored, yourself white. One per player, centered on them.
func _update_radar() -> void:
	var player := _player()
	if player == null or world == null or world.chunks == null or world.players == null:
		if _radar != null:
			_radar.visible = false
		return
	_radar.visible = not _menu.visible
	# On struggling machines rebuild the radar a third as often.
	_radar_tick += 1
	if Engine.get_frames_per_second() < 20 and _radar_tick % 3 != 0:
		return
	var center := player.position
	# Radar convention: whatever you're facing is UP on the map.
	var yaw: float = player.camera_yaw
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for py in 128:
		for px in 128:
			var off := Vector2(px - 64, py - 64).rotated(-yaw) * 1.5
			var wx := int(center.x + off.x)
			var wz := int(center.z + off.y)
			var block: int = world.chunks.top_block(wx, wz)
			if block <= 0:
				block = world.overview_block(wx, wz)
			var color := Color(0.06, 0.07, 0.1)
			if block > 0:
				color = Blocks.top_color_of(block).darkened(
					WorldGen.hash01(wx, wz, 9) * 0.22)
			image.set_pixel(px, py, color)
	if world.match_phase == "BATTLE":
		var ring: float = world.storm_radius
		for angle_i in 200:
			var a := angle_i * TAU / 200.0
			var rs := Vector2(cos(a) * ring - center.x,
				sin(a) * ring - center.z).rotated(yaw) / 1.5
			var rx := 64 + int(rs.x)
			var ry := 64 + int(rs.y)
			if rx >= 0 and rx < 128 and ry >= 0 and ry < 128:
				image.set_pixel(rx, ry, Color(1.0, 0.25, 0.2))
	if world.crates != null:
		for crate in world.crates.get_children():
			if crate is Node3D:
				_blip(image, center, yaw, crate.position, Color("ffd166"))
	for child in world.players.get_children():
		if child is Player and child != player:
			var team := int(Game.roster.get(child.player_id, {}).get("team", -1))
			_blip(image, center, yaw, child.position,
				WorldNode.TEAM_COLORS[team] if team >= 0 else Color("ff4426"))
	_blip(image, center, yaw, player.position, Color.WHITE)
	_radar.texture = ImageTexture.create_from_image(image)
	_update_clock()

## Each player gets the clock + player count under their own radar.
func _update_clock() -> void:
	if _clock == null or world == null:
		return
	var hour := int(fposmod(world.clock * 24.0, 24.0))
	var night: bool = world.clock > 0.78 or world.clock < 0.22
	_clock.text = "%s %02d:00 · %d playing" % ["☾" if night else "☀", hour, Game.roster.size()]

func _blip(image: Image, center: Vector3, yaw: float, pos: Vector3, color: Color) -> void:
	var s := Vector2(pos.x - center.x, pos.z - center.z).rotated(yaw) / 1.5
	var px := 64 + int(s.x)
	var py := 64 + int(s.y)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if px + dx >= 0 and px + dx < 128 and py + dy >= 0 and py + dy < 128:
				image.set_pixel(px + dx, py + dy, color)

var _team_box: VBoxContainer
var _world_row: HBoxContainer
var _maps_row: HBoxContainer
var _maps_label: Label

## Battle lobby lives in the menu now: when a match opens, EVERYONE's menu
## pops open on the Game tab so each player can pick a team with their own
## controls.
func _on_match_changed() -> void:
	var player := _player()
	if player == null or world == null:
		return
	_refresh_identity()
	if world.match_phase == "LOBBY":
		if not _menu.visible:
			_toggle_menu(player, 5)
		_tabs.current_tab = 5
		_refresh_team_box()
	elif _menu.visible and world.match_phase == "DROP":
		_close_menu()

func _refresh_team_box() -> void:
	if _team_box == null:
		return
	for child in _team_box.get_children():
		child.queue_free()
	if world == null:
		return
	var me := multiplayer.get_unique_id()
	for id: String in Game.roster.keys():
		var entry: Dictionary = Game.roster[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _us(10))
		_team_box.add_child(row)
		var name_label := Label.new()
		name_label.text = str(entry.name) + ("  🤖" if entry.get("bot", false) else "")
		name_label.custom_minimum_size = Vector2(_us(170), 0)
		name_label.add_theme_font_size_override("font_size", _us(22))
		var team := int(entry.get("team", -1))
		name_label.add_theme_color_override("font_color",
			WorldNode.TEAM_COLORS[team] if team >= 0 else Color.WHITE)
		row.add_child(name_label)
		var mine: bool = int(entry.peer) == me and int(entry.slot) == slot
		var bot: bool = bool(entry.get("bot", false))
		if mine or bot:
			var team_btn := Button.new()
			team_btn.focus_mode = Control.FOCUS_NONE
			team_btn.text = "  " + (WorldNode.TEAM_NAMES[team] if team >= 0 else "Pick team") + "  "
			team_btn.add_theme_font_size_override("font_size", _us(20))
			var next_team := (team + 1) % 4
			var target_id := id
			var target_slot := int(entry.slot)
			team_btn.pressed.connect(func() -> void:
				if bot and not mine:
					if Game.world != null:
						Game.world.sv_set_bot_team.rpc_id(1, target_id, next_team)
				else:
					Game.set_local_team(target_slot, next_team)
				Sfx.play("tick", -8.0))
			row.add_child(team_btn)
		else:
			var wait_label := Label.new()
			wait_label.text = WorldNode.TEAM_NAMES[team] if team >= 0 else "picking..."
			wait_label.add_theme_font_size_override("font_size", _us(20))
			wait_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
			row.add_child(wait_label)

## Its own tab: every video setting individually — numbers get sliders,
## switches get checkboxes. No presets, no magic.
func _build_video_tab() -> void:
	var tab := _scrolled_tab("Video")
	tab.add_theme_constant_override("separation", _us(10))
	_add_video_slider(tab, "Draw distance", "dist_blocks", 32, 208, 16, "%d blocks (16 per chunk)")
	_add_video_slider(tab, "3D resolution", "render_scale", 1, 100, 1, "%d%%")
	_add_video_slider(tab, "Shadow quality", "shadow_quality", 0, 2, 1, "%d")
	for spec in [["shadows", "Shadows"], ["ssao", "Contact shading (SSAO)"],
			["glow", "Glow"], ["lights", "Dynamic lights"],
			["water_shine", "Shiny water (sun glints)"],
			["ao", "Corner shading on blocks"], ["wire", "Wireframe"]]:
		var key := str(spec[0])
		var tbtn := Button.new()
		tbtn.focus_mode = Control.FOCUS_NONE
		tbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tbtn.add_theme_font_size_override("font_size", _us(20))
		tbtn.text = ("☑  " if Game.video[key] else "☐  ") + str(spec[1])
		var label_text := str(spec[1])
		tbtn.pressed.connect(func() -> void:
			Game.video[key] = not bool(Game.video[key])
			tbtn.text = ("☑  " if Game.video[key] else "☐  ") + label_text
			Game.video_changed.emit()
			Sfx.play("tick", -10.0))
		tab.add_child(tbtn)
	# Renderer: Full (Vulkan, all effects) vs Lite (OpenGL, Minecraft-class
	# speed on old computers). Switching restarts the game.
	var is_lite := RenderingServer.get_rendering_device() == null
	var lite_btn := Button.new()
	lite_btn.focus_mode = Control.FOCUS_NONE
	lite_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	lite_btn.add_theme_font_size_override("font_size", _us(20))
	lite_btn.text = "🎨  Renderer: " + ("Lite — fast, for old computers" if is_lite \
		else "Full — all the fancy effects") + "   (switch = quick restart)"
	lite_btn.pressed.connect(func() -> void:
		Game.relaunch_with_renderer(not is_lite))
	tab.add_child(lite_btn)

func _add_video_slider(tab: Control, label_text: String, key: String,
		minv: int, maxv: int, step: int, suffix: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _us(10))
	tab.add_child(row)
	var name_label := Label.new()
	name_label.text = label_text + ":"
	name_label.custom_minimum_size = Vector2(_us(190), 0)
	name_label.add_theme_font_size_override("font_size", _us(20))
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = minv
	slider.max_value = maxv
	slider.step = step
	slider.value = int(Game.video.get(key, minv))
	slider.custom_minimum_size = Vector2(_us(230), _us(24))
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = suffix % int(slider.value)
	value_label.add_theme_font_size_override("font_size", _us(20))
	row.add_child(value_label)
	slider.value_changed.connect(func(val: float) -> void:
		Game.video[key] = int(val)
		value_label.text = suffix % int(val)
		Game.video_changed.emit())

func _close_menu() -> void:
	_menu.visible = false
	var player := _player()
	if player != null:
		player.ui_locked = false

func _on_picked(entry: Dictionary) -> void:
	var player := _player()
	if player == null:
		return
	player.slots[player.selected_slot] = {"kind": entry.kind, "id": entry.id}
	_slots_dirty = true

func _entry() -> Dictionary:
	return Game.roster.get(Game.player_id(multiplayer.get_unique_id(), slot), {})

func _player() -> Player:
	if world == null or world.players == null:
		return null
	for child in world.players.get_children():
		if child is Player and child.is_local and child.slot == slot:
			return child
	return null

func _refresh_identity() -> void:
	_refresh_team_box()
	var entry := _entry()
	if entry.is_empty():
		return
	_name_label.text = str(entry.name)
	if _menu != null and _menu.visible and _tabs.current_tab == 4:
		_refresh_preview()
	var team := int(entry.get("team", -1))
	_name_label.add_theme_color_override("font_color",
		WorldNode.TEAM_COLORS[team] if team >= 0 else Color.WHITE)
	_treasure_label.text = ""
	var id := Game.player_id(multiplayer.get_unique_id(), slot)
	if world != null and (world.survival_active or world.match_phase in ["DROP", "BATTLE"]):
		var hp: int = world.hearts.get(id, 5)
		_hearts_label.text = "♥".repeat(maxi(hp, 0))
		_hearts_label.visible = true
	else:
		_hearts_label.visible = false

func _edit_name() -> void:
	var entry := _entry()
	if entry.is_empty():
		return
	var edit := LineEdit.new()
	edit.text = str(entry.name)
	edit.max_length = 12
	edit.add_theme_font_size_override("font_size", _us(18))
	edit.custom_minimum_size = Vector2(120, 0)
	var parent := _name_label.get_parent()
	parent.add_child(edit)
	parent.move_child(edit, _name_label.get_index())
	_name_label.visible = false
	edit.grab_focus()
	edit.select_all()
	var commit := func() -> void:
		if is_instance_valid(edit):
			Game.set_local_name(slot, edit.text)
			edit.queue_free()
			_name_label.visible = true
	edit.text_submitted.connect(func(_text: String) -> void: commit.call())
	edit.focus_exited.connect(commit)

func _process(_delta: float) -> void:
	var player := _player()
	if player == null:
		return
	# Menu toggling: E opens straight onto the Blocks tab, Esc/Start onto
	# the guide; either closes it again.
	var input: InputSlot = Game.local_inputs.get(slot)
	if input != null:
		var picker_pressed := input.is_picker_pressed()
		if picker_pressed and not _prev_picker:
			_toggle_menu(player, 0)
		_prev_picker = picker_pressed
		var menu_pressed := input.is_menu_pressed()
		if menu_pressed and not _prev_menu:
			_toggle_menu(player, 1)
		_prev_menu = menu_pressed
		if _menu.visible:
			# Controller-first: bumpers change tabs, stick/D-pad moves the
			# grid, A picks (then hops to the next slot), 1-8 jump slots,
			# and view/menu buttons close.
			var pick := input.slot_pick()
			if pick != _prev_slot_pick_menu and pick >= 0 and pick < 8:
				player.selected_slot = pick
				_slots_dirty = true
				Sfx.play("tick", -10.0)
			_prev_slot_pick_menu = pick
			var tab_cycle := input.cycle_direction()
			if tab_cycle != 0 and not _menu_tab_latch:
				var next_tab := _tabs.current_tab
				for attempt in 6:
					next_tab = posmod(next_tab + tab_cycle, 7)
					if not _tabs.is_tab_disabled(next_tab):
						break
				_tabs.current_tab = next_tab
				Sfx.play("tick", -12.0)
			_menu_tab_latch = tab_cycle != 0
			if input.is_view_toggle_pressed():
				_close_menu()
			if _tabs.current_tab < 4:
				_pickers[_tabs.current_tab].poll(input, _delta)
	if not _menu.visible and player.ui_locked:
		player.ui_locked = false
	if OS.get_environment("WORLD_AUTOTEST_MENU") == "1" and slot == 0 \
			and not _autoopened and Time.get_ticks_msec() > 9000:
		_autoopened = true
		_toggle_menu(player, 1)
	if _autoopened and _menu.visible and not OS.get_environment("WORLD_AUTOTEST_TAB").is_empty():
		_tabs.current_tab = int(OS.get_environment("WORLD_AUTOTEST_TAB"))

	_crosshair.visible = player.fp_mode and not _menu.visible
	_crosshair.add_theme_font_size_override("font_size", _us(int(30 * (1.0 + player.fp_zoom * 0.8))))
	if size.x != _last_width:
		_last_width = size.x
		var map_px := clampf(size.y * 0.24, 110.0, 380.0)
		# Hotbar chips scale with the cell so small screens aren't swamped.
		var chip_px := clampf(size.y * 0.05, 34.0, 72.0)
		for hb_frame in _hotbar.get_children():
			(hb_frame as Control).custom_minimum_size = Vector2(chip_px, chip_px)
		_radar.position = Vector2(size.x - map_px - 10, 10)
		_radar.size = Vector2(map_px, map_px)
		_clock.position = Vector2(size.x - map_px - 10, 12 + map_px)
		_clock.size.x = map_px
		_clock.add_theme_font_size_override("font_size", maxi(11, int(map_px / 11.0)))
		# Split-screen: fonts are sized for the full window, so shrink the
		# whole menu to fit this player's cell instead of spilling over.
		var win_w := float(DisplayServer.window_get_size().x)
		var cell_frac := clampf(size.x / maxf(win_w, 1.0), 0.25, 1.0)
		if cell_frac < 0.95:
			_menu.scale = Vector2.ONE * (cell_frac * 1.42)
			_menu.anchor_left = 0.02
			_menu.anchor_right = 0.98
			_menu.anchor_top = 0.04
			_menu.anchor_bottom = 0.94
		else:
			_menu.scale = Vector2.ONE
			_menu.anchor_left = 0.1
			_menu.anchor_right = 0.9
		_selected_label.add_theme_font_size_override("font_size",
			int(clampf(size.x / 45.0, 16.0, 34.0)))
		_last_index = -1
	if _chip != null:
		_chip.visible = not _menu.visible
	if _water_tint != null and world != null and world.chunks != null:
		var eye := player.position + Vector3(0, Player.EYE_HEIGHT, 0)
		var under: bool = Blocks.is_liquid(world.chunks.get_block(
			Vector3i(floori(eye.x), floori(eye.y), floori(eye.z))))
		_water_tint.color.a = lerpf(_water_tint.color.a, 0.35 if under else 0.0, 0.25)
	if _storm_tint != null and world != null:
		var danger := 0.0
		if world.match_phase == "BATTLE" \
				and Vector2(player.position.x, player.position.z).length() > world.storm_radius:
			danger = 0.25
		_storm_tint.color.a = lerpf(_storm_tint.color.a, danger, 0.1)
	# Caught outside the storm: a big arrow home plus the distance.
	if world != null and world.match_phase == "BATTLE":
		var flat := Vector2(player.position.x, player.position.z)
		var outside: float = flat.length() - world.storm_radius
		if outside > 0.0:
			var to_center := -flat
			var angle := atan2(to_center.x, -to_center.y) - player.camera_yaw
			var arrows := ["⬆", "⬈", "➡", "⬊", "⬇", "⬋", "⬅", "⬉"]
			var arrow: String = arrows[posmod(int(round(angle / (PI / 4.0))), 8)]
			_storm_arrow.text = "%s  STORM! run %dm  %s" % [arrow, int(outside), arrow]
			_storm_arrow.visible = true
		else:
			_storm_arrow.visible = false
	else:
		_storm_arrow.visible = false
	var held_now := str(player.held())
	if player.selected_slot != _last_index or _slots_dirty or held_now != _last_held:
		_last_index = player.selected_slot
		_last_held = held_now
		_slots_dirty = false
		_selected_label.text = ""
		var slot_px := clampf(size.x / 13.0, 44.0, 96.0)
		for i in _chips.size():
			var frame: Panel = _chips[i]
			var entry: Dictionary = player.slots[i]
			var selected := i == _last_index
			frame.custom_minimum_size = Vector2(slot_px, slot_px) * (1.18 if selected else 1.0)
			var style := StyleBoxFlat.new()
			style.bg_color = Color(0.08, 0.09, 0.14, 0.85)
			style.set_corner_radius_all(8)
			style.border_color = Color("ffd166") if selected else Color(1, 1, 1, 0.25)
			style.set_border_width_all(4 if selected else 2)
			frame.add_theme_stylebox_override("panel", style)
			var icon: BlockIcon = frame.get_child(0)
			icon.block_id = int(entry.id)
			icon.kind = str(entry.kind)
			icon.dimmed = not selected
			icon.queue_redraw()
			if i < _menu_slot_buttons.size():
				var menu_btn: Button = _menu_slot_buttons[i]
				var menu_icon: BlockIcon = menu_btn.get_child(0)
				menu_icon.block_id = int(entry.id)
				menu_icon.kind = str(entry.kind)
				menu_icon.dimmed = not selected
				menu_icon.queue_redraw()
				menu_btn.modulate = Color(1, 1, 1, 1.0) if selected else Color(1, 1, 1, 0.6)
