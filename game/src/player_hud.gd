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
var _menu_dim: ColorRect
# Two-level menu: a top row of groups, each holding a row of small tabs.
# Pages are addressed by a flat index so controllers can just bump LB/RB
# through everything: 0-3 pickers, 4 Battle, 5 Players, 6 World,
# 7 Character, 8 Video.
var _groups: TabContainer
var _build_tabs: TabContainer
var _game_tabs: TabContainer
var _opt_tabs: TabContainer
var _char_tabs: TabContainer
var _video_tabs: TabContainer
const PAGE_PLAYERS := 9
const PAGE_CHARACTER := 10
const _PAGES := [[0, 0], [0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6],
	[1, 0], [1, 1], [1, 2], [2, 0], [3, 0], [3, 1]]
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
var _menu_group_latch := false
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
	_hearts_label.add_theme_font_size_override("font_size", _us(17))
	_hearts_label.add_theme_color_override("font_color", Color("ff4438"))
	_hearts_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hearts_label.add_theme_constant_override("outline_size", 5)
	_hearts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.visible = false

	# Bottom: hotbar.
	var bar_holder := CenterContainer.new()
	bar_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_holder.offset_top = -175
	bar_holder.offset_bottom = -8
	bar_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_holder)
	var bar_stack := VBoxContainer.new()
	bar_stack.add_theme_constant_override("separation", 2)
	bar_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_holder.add_child(bar_stack)
	var bar_panel := PanelContainer.new()
	bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.04, 0.05, 0.08, 0.6)
	bar_style.set_corner_radius_all(10)
	bar_style.set_content_margin_all(6)
	bar_panel.add_theme_stylebox_override("panel", bar_style)
	# Hearts live in the same stack as the hotbar: aligned by construction.
	bar_stack.add_child(_hearts_label)
	bar_stack.add_child(bar_panel)
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
	_menu_dim = ColorRect.new()
	_menu_dim.color = Color(0, 0, 0, 0.38)
	_menu_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu_dim.visible = false
	add_child(_menu_dim)
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
	_groups = TabContainer.new()
	_groups.get_tab_bar().focus_mode = Control.FOCUS_NONE
	_groups.add_theme_font_size_override("font_size", _us(21))
	_menu.add_child(_groups)
	_build_tabs = TabContainer.new()
	_build_tabs.name = "Build"
	_game_tabs = TabContainer.new()
	_game_tabs.name = "World"
	_char_tabs = TabContainer.new()
	_char_tabs.name = "Character"
	_video_tabs = TabContainer.new()
	_video_tabs.name = "Video"
	_opt_tabs = _char_tabs
	var on_page_change := func(_t: int) -> void:
		if not _tab_guard:
			_last_tab = _current_page()
	var game_wrap := VBoxContainer.new()
	game_wrap.name = "World"
	game_wrap.add_theme_constant_override("separation", _us(8))
	_battle_start = Button.new()
	_battle_start.focus_mode = Control.FOCUS_NONE
	_battle_start.text = "🏆  Start Battle"
	_battle_start.add_theme_font_size_override("font_size", _us(24))
	var start_style := StyleBoxFlat.new()
	start_style.bg_color = Color("ffd166")
	start_style.set_corner_radius_all(10)
	start_style.set_content_margin_all(_us(9))
	_battle_start.add_theme_stylebox_override("normal", start_style)
	var start_hover: StyleBoxFlat = start_style.duplicate()
	start_hover.bg_color = Color("ffd166").lightened(0.12)
	_battle_start.add_theme_stylebox_override("hover", start_hover)
	_battle_start.add_theme_stylebox_override("pressed", start_hover)
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		_battle_start.add_theme_color_override(state, Color("1c2333"))
	_battle_start.pressed.connect(func() -> void:
		if Game.world != null and Game.world.match_phase == "IDLE":
			Game.world.sv_match_start.rpc_id(1, 0)
			Sfx.play("cheer", -10.0))
	game_wrap.add_child(_battle_start)
	for inner_tc: TabContainer in [_build_tabs, _game_tabs, _char_tabs, _video_tabs]:
		inner_tc.get_tab_bar().focus_mode = Control.FOCUS_NONE
		inner_tc.add_theme_font_size_override("font_size", _us(17))
		if inner_tc == _game_tabs:
			inner_tc.size_flags_vertical = Control.SIZE_EXPAND_FILL
			game_wrap.add_child(inner_tc)
			_groups.add_child(game_wrap)
		else:
			_groups.add_child(inner_tc)
		inner_tc.tab_changed.connect(on_page_change)
	_groups.tab_changed.connect(on_page_change)
	_groups.set_tab_title(0, "🔨 Build")
	_groups.set_tab_title(1, "🌍 World")
	_groups.set_tab_title(2, "🙂 Character")
	_groups.set_tab_title(3, "🎨 Video")
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
	# Big center note for match phases (lobby countdown, next-battle).
	_center_note = Label.new()
	_center_note.add_theme_font_size_override("font_size", _us(26))
	_center_note.add_theme_color_override("font_color", Color("ffd166"))
	_center_note.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_center_note.add_theme_constant_override("outline_size", 6)
	_center_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_center_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center_note.offset_top = _us(120)
	_center_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_note.visible = false
	add_child(_center_note)
	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", _us(17))
	_score_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	_score_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_score_label.add_theme_constant_override("outline_size", 5)
	_score_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_score_label.offset_top = _us(8)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.visible = false
	add_child(_score_label)
	_team_panel = VBoxContainer.new()
	_team_panel.add_theme_constant_override("separation", _us(1))
	_team_panel.visible = false
	add_child(_team_panel)
	_feed_box = VBoxContainer.new()
	_feed_box.add_theme_constant_override("separation", _us(2))
	_feed_box.position = Vector2(_us(10), _us(60))
	add_child(_feed_box)
	_vignette = TextureRect.new()
	var vg := Gradient.new()
	vg.colors = PackedColorArray([Color(0.7, 0.05, 0.02, 0.0), Color(0.7, 0.05, 0.02, 0.85)])
	vg.offsets = PackedFloat32Array([0.55, 1.0])
	var vg_tex := GradientTexture2D.new()
	vg_tex.gradient = vg
	vg_tex.fill = GradientTexture2D.FILL_RADIAL
	vg_tex.fill_from = Vector2(0.5, 0.5)
	vg_tex.fill_to = Vector2(0.5, 0.0)
	_vignette.texture = vg_tex
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.modulate.a = 0.0
	add_child(_vignette)
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.9, 0.1, 0.05, 0.0)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_damage_flash)
	_damage_arrow = Label.new()
	_damage_arrow.text = "⌃"
	_damage_arrow.add_theme_font_size_override("font_size", _us(46))
	_damage_arrow.add_theme_color_override("font_color", Color("ff3b2f"))
	_damage_arrow.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_damage_arrow.add_theme_constant_override("outline_size", 8)
	_damage_arrow.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_damage_arrow.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_damage_arrow.grow_vertical = Control.GROW_DIRECTION_BOTH
	_damage_arrow.visible = false
	add_child(_damage_arrow)
	_ride_hint = Label.new()
	_ride_hint.add_theme_font_size_override("font_size", _us(17))
	_ride_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	_ride_hint.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_ride_hint.add_theme_constant_override("outline_size", 5)
	_ride_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_ride_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_ride_hint.offset_top = -_us(190)
	_ride_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ride_hint.visible = false
	add_child(_ride_hint)
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
	# The menu (and its dim) must sit ABOVE the water/storm/damage tints —
	# opening the menu underwater used to render it behind the blue wash.
	move_child(_menu_dim, get_child_count() - 1)
	move_child(_menu, get_child_count() - 1)

	_pickers = []
	for spec in [["Tools", "tools"], ["Building", "building"],
			["Natural", "nature"], ["Colored", "colors"],
			["Functional", "lights"], ["Special", "special"], ["Kits", "kits"]]:
		var picker := BlockPicker.new(spec[1])
		picker.name = spec[0]
		picker.picked.connect(_on_picked)
		_build_tabs.add_child(picker)
		_pickers.append(picker)
	_picker = _pickers[0]
	_build_character_tab()
	_build_game_tab()
	_build_video_tab()
	_build_help_tab()
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
		world.local_hurt.connect(func(hurt_id: String, from_pos: Vector3) -> void:
			if hurt_id == Game.player_id(multiplayer.get_unique_id(), slot):
				_damage_t = 1.8
				_damage_from = from_pos)
		world.hearts_changed.connect(func() -> void:
			var my_hp := int(world.hearts.get(Game.player_id(
				multiplayer.get_unique_id(), slot), 8))
			if my_hp < _prev_hp:
				_damage_t = maxf(_damage_t, 1.2)
			_prev_hp = my_hp)
		world.treasures_changed.connect(_refresh_identity)
		world.survival_changed.connect(_refresh_identity)
		world.hearts_changed.connect(_refresh_identity)
		world.match_changed.connect(_on_match_changed)
		world.battle_config_changed.connect(_refresh_battle_highlights)
		world.match_score_changed.connect(_refresh_team_panel)
		world.match_changed.connect(func() -> void:
			if world.match_phase == "DROP" and _feed_box != null:
				for old_line in _feed_box.get_children():
					old_line.queue_free())
		world.knockout.connect(func(attacker: String, victim: String) -> void:
			var line := Label.new()
			line.text = ("%s  💥  %s" % [attacker, victim]) if not attacker.is_empty() \
				else "☁💥  %s" % victim
			line.add_theme_font_size_override("font_size", _us(15))
			line.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			line.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
			line.add_theme_constant_override("outline_size", 4)
			_feed_box.add_child(line)
			if _feed_box.get_child_count() > 10:
				_feed_box.get_child(0).queue_free())
	Game.roster_changed.connect(_refresh_identity)
	_refresh_identity()

func is_ui_open() -> bool:
	return _menu != null and _menu.visible

# ---- Controller navigation over regular menu pages (not the pickers,
# they have their own grid cursor): left stick moves a highlight between
# buttons/sliders, A presses, sliders adjust with left/right. ----
var _nav_focus: Control = null
var _nav_repeat := 0.0
var _prev_nav_select := true

func _page_control(page: int) -> Control:
	var spec: Array = _PAGES[clampi(page, 0, _PAGES.size() - 1)]
	return _inner_tabs(spec[0]).get_child(spec[1])

func _poll_page_nav(input: InputSlot, delta: float) -> void:
	var controls: Array = []
	var root := _page_control(_current_page())
	for kind in ["BaseButton", "HSlider"]:
		for node in root.find_children("*", kind, true, false):
			if (node as Control).is_visible_in_tree():
				controls.append(node)
	if controls.is_empty():
		_set_nav_focus(null)
		return
	if _nav_focus == null or not is_instance_valid(_nav_focus) \
			or not _nav_focus.is_visible_in_tree() or not controls.has(_nav_focus):
		_set_nav_focus(controls[0])
	var dir := input.get_move_vector()
	_nav_repeat -= delta
	if dir.length() > 0.55:
		if _nav_repeat <= 0.0:
			_nav_repeat = 0.24
			if _nav_focus is HSlider and absf(dir.x) > absf(dir.y):
				var slider: HSlider = _nav_focus
				slider.value += slider.step * signf(dir.x)
				Sfx.play("tick", -14.0)
			else:
				_nav_move(controls, dir)
	else:
		_nav_repeat = 0.0
	var select := input.is_primary_pressed()
	if select and not _prev_nav_select and _nav_focus is BaseButton:
		var btn: BaseButton = _nav_focus
		if btn.toggle_mode:
			btn.button_pressed = not btn.button_pressed
		else:
			btn.pressed.emit()
	_prev_nav_select = select

## Spatial move: nearest control mostly in the pushed direction.
func _nav_move(controls: Array, dir: Vector2) -> void:
	if _nav_focus == null:
		return
	var from: Vector2 = _nav_focus.get_global_rect().get_center()
	var n := dir.normalized()
	var best: Control = null
	var best_score := INF
	for c: Control in controls:
		if c == _nav_focus:
			continue
		var to := c.get_global_rect().get_center() - from
		var along := to.dot(n)
		if along <= 4.0:
			continue
		var score := along + absf(to.cross(n)) * 2.2
		if score < best_score:
			best_score = score
			best = c
	if best != null:
		_set_nav_focus(best)
		Sfx.play("tick", -14.0)

func _set_nav_focus(c: Control) -> void:
	if _nav_focus == c:
		return
	if _nav_focus != null and is_instance_valid(_nav_focus):
		_nav_focus.modulate = Color.WHITE
	if _nav_focus != null and is_instance_valid(_nav_focus):
		_nav_focus.scale = Vector2.ONE
	_nav_focus = c
	if c != null:
		c.modulate = Color(1.5, 1.35, 0.85)
		c.pivot_offset = c.size / 2.0
		c.scale = Vector2.ONE * 1.06
		var p: Node = c.get_parent()
		while p != null and not (p is ScrollContainer):
			p = p.get_parent()
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)

func _toggle_menu(player: Player, open_tab: int) -> void:
	if _menu.visible:
		_close_menu()
		return
	_menu.visible = true
	_menu_dim.visible = true
	_build_tabs.set_tab_disabled(0, world != null and world.match_phase != "IDLE")
	_refresh_preview()
	player.ui_locked = true
	# picker.open() flips child visibility, which yanks the TabContainer onto
	# whichever picker was shown last (the "always opens on Kits" bug) — so
	# the pickers open FIRST and the real tab is set after, guarded so the
	# churn doesn't pollute _last_tab.
	_tab_guard = true
	for picker: BlockPicker in _pickers:
		picker.fit(size * Vector2(0.75, 0.6))
		picker.open()
	if open_tab == 0:
		_set_page(1)  # the blocks button always lands on Building
	else:
		_set_page(1 if _page_disabled(_last_tab) else _last_tab)
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
	_opt_tabs.add_child(char_scroll)
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
	var dice := Button.new()
	dice.focus_mode = Control.FOCUS_NONE
	dice.text = "🎲  Surprise me!"
	dice.add_theme_font_size_override("font_size", _us(20))
	dice.pressed.connect(func() -> void:
		for dice_attr in ["body", "face", "hair", "hat", "shirt", "pants", "shoes", "gear"]:
			Game.cycle_local_style(slot, str(dice_attr), randi_range(1, 5))
		Sfx.play("cheer", -12.0))
	tab.add_child(dice)
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
	var tab := _scrolled_tab("Mode", _game_tabs)
	tab.add_theme_constant_override("separation", _us(10))
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", _us(8))
	tab.add_child(mode_row)
	var mode_tag := Label.new()
	mode_tag.text = "Mode:"
	mode_tag.add_theme_font_size_override("font_size", _us(20))
	mode_row.add_child(mode_tag)
	for mode_spec in [["🏆 Battle", "battle"], ["🔨 Creative", "creative"]]:
		var mode_btn := Button.new()
		mode_btn.focus_mode = Control.FOCUS_NONE
		mode_btn.text = str(mode_spec[0])
		mode_btn.add_theme_font_size_override("font_size", _us(20))
		var mode_key := str(mode_spec[1])
		mode_btn.pressed.connect(func() -> void:
			if Game.world != null:
				Game.world.sv_set_mode.rpc_id(1, mode_key)
			Sfx.play("tick", -8.0))
		mode_row.add_child(mode_btn)
		_mode_btns[mode_key] = mode_btn
	_battle_opts = VBoxContainer.new()
	_battle_opts.add_theme_constant_override("separation", _us(10))
	tab.add_child(_battle_opts)
	var length_row := HBoxContainer.new()
	length_row.add_theme_constant_override("separation", _us(8))
	_battle_opts.add_child(length_row)
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
				Game.world.sv_match_config.rpc_id(1, minutes, -1, -1)
			Sfx.play("tick", -8.0))
		length_row.add_child(preset_btn)
		_length_btns[minutes] = preset_btn
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", _us(8))
	_battle_opts.add_child(size_row)
	var size_label := Label.new()
	size_label.text = "Arena size:"
	size_label.add_theme_font_size_override("font_size", _us(20))
	size_row.add_child(size_label)
	for arena in [50, 100, 150, 200, 250, 300, 350]:
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
		_size_btns[arena] = size_btn
	tab = _scrolled_tab("Players", _game_tabs)
	tab.add_theme_constant_override("separation", _us(10))
	_lobby_countdown = Label.new()
	_lobby_countdown.add_theme_font_size_override("font_size", _us(22))
	_lobby_countdown.add_theme_color_override("font_color", Color("ffd166"))
	_lobby_countdown.visible = false
	tab.add_child(_lobby_countdown)
	var manage_row := HBoxContainer.new()
	manage_row.add_theme_constant_override("separation", _us(8))
	tab.add_child(manage_row)
	for spec in [["➕ Team", "add_team"], ["➖ Team", "remove_team"],
			["➕ Computer player", "add_bot"], ["➖ Computer player", "remove_bot"]]:
		var manage_btn := Button.new()
		manage_btn.focus_mode = Control.FOCUS_NONE
		manage_btn.text = str(spec[0])
		manage_btn.add_theme_font_size_override("font_size", _us(19))
		var action := str(spec[1])
		manage_btn.pressed.connect(func() -> void:
			if Game.world == null:
				return
			match action:
				"add_team": Game.world.sv_add_team.rpc_id(1)
				"remove_team": Game.world.sv_remove_team.rpc_id(1, -1)
				"add_bot": Game.world.sv_add_bot.rpc_id(1)
				"remove_bot": Game.world.sv_remove_bot.rpc_id(1, "")
			Sfx.play("tick", -8.0))
		manage_row.add_child(manage_btn)
		if action == "add_bot":
			_add_bot_btn = manage_btn
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", _us(4))
	tab.add_child(_team_box)
	tab = _scrolled_tab("Map", _game_tabs)
	tab.add_theme_constant_override("separation", _us(10))
	var gen_label := Label.new()
	gen_label.text = "Generated maps:"
	gen_label.add_theme_font_size_override("font_size", _us(18))
	tab.add_child(gen_label)
	_world_row = HBoxContainer.new()
	_world_row.add_theme_constant_override("separation", _us(6))
	tab.add_child(_world_row)
	_maps_label = Label.new()
	_maps_label.text = "Designed maps:"
	_maps_label.add_theme_font_size_override("font_size", _us(18))
	tab.add_child(_maps_label)
	_maps_row = HBoxContainer.new()
	_maps_row.add_theme_constant_override("separation", _us(6))
	tab.add_child(_maps_row)
	_rebuild_world_row()
	if world != null:
		world.map_list_changed.connect(_rebuild_world_row)
	_game_tabs.move_child(_game_tabs.get_node("Map"), 0)

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
	if world != null and map_key == world.client_world:
		_mark_selected(map_btn, true)
	map_btn.pressed.connect(func() -> void:
		if Game.world != null:
			Game.world.sv_select_world.rpc_id(1, map_key)
		Sfx.play("tick", -8.0))
	return map_btn

## A tab whose content scrolls vertically instead of overflowing.
func _scrolled_tab(tab_name: String, parent: TabContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		pad.add_theme_constant_override(side, _us(14))
	scroll.add_child(pad)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(box)
	return box

func _inner_tabs(group: int) -> TabContainer:
	return [_build_tabs, _game_tabs, _char_tabs, _video_tabs][group]

func _current_page() -> int:
	for page in _PAGES.size():
		if _PAGES[page][0] == _groups.current_tab \
				and _PAGES[page][1] == _inner_tabs(_groups.current_tab).current_tab:
			return page
	return 0

func _set_page(page: int) -> void:
	var spec: Array = _PAGES[clampi(page, 0, _PAGES.size() - 1)]
	_groups.current_tab = spec[0]
	_inner_tabs(spec[0]).current_tab = spec[1]

func _page_disabled(page: int) -> bool:
	var spec: Array = _PAGES[clampi(page, 0, _PAGES.size() - 1)]
	return _inner_tabs(spec[0]).is_tab_disabled(spec[1])

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
	if world.match_phase == "BATTLE" and world.storm_radius > 0.0:
		var ring: float = world.storm_radius
		for angle_i in 200:
			var a := angle_i * TAU / 200.0
			var rs := Vector2(world.storm_center.x + cos(a) * ring - center.x,
				world.storm_center.z + sin(a) * ring - center.z).rotated(yaw) / 1.5
			var rx := 64 + int(rs.x)
			var ry := 64 + int(rs.y)
			for ro in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				if rx + ro.x >= 0 and rx + ro.x < 128 and ry + ro.y >= 0 and ry + ro.y < 128:
					image.set_pixel(rx + ro.x, ry + ro.y, Color(1.0, 0.25, 0.2))
	if world.crates != null:
		for crate in world.crates.get_children():
			if crate is Node3D:
				_blip(image, center, yaw, crate.position, Color("ffd166"))
	var my_team := int(Game.roster.get(Game.player_id(multiplayer.get_unique_id(), slot),
		{}).get("team", -1))
	for child in world.players.get_children():
		if child is Player and child != player and child.visible \
				and not world.ghost_ids.has(child.player_id):
			var team := int(Game.roster.get(child.player_id, {}).get("team", -1))
			var blip_color: Color = WorldNode.TEAM_COLORS[team] if team >= 0 \
				else Color("ff4426")
			if team == my_team and my_team >= 0:
				# Teammates draw as a fat bright cross so they pop.
				blip_color = blip_color.lightened(0.4)
				for off in [Vector3(0, 0, 0), Vector3(1.6, 0, 0), Vector3(-1.6, 0, 0),
						Vector3(0, 0, 1.6), Vector3(0, 0, -1.6)]:
					_blip(image, center, yaw, child.position + off, blip_color)
			else:
				_blip(image, center, yaw, child.position, blip_color)
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
var _length_btns: Dictionary = {}
var _size_btns: Dictionary = {}
var _lobby_countdown: Label
var _mode_btns: Dictionary = {}
var _battle_opts: VBoxContainer
var _battle_start: Button
var _add_bot_btn: Button
var _center_note: Label
var _score_label: Label
var _team_panel: VBoxContainer
var _feed_box: VBoxContainer
var _ride_hint: Label
var _damage_flash: ColorRect
var _vignette: TextureRect
var _damage_arrow: Label
var _damage_t := 0.0
var _damage_from := Vector3.ZERO
var _prev_hp := 8
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
		_refresh_team_box()
	elif _menu.visible and world.match_phase == "DROP":
		_close_menu()

## The selected battle options glow gold so everyone can see the setup.
## Selected choice buttons get a gold BACKGROUND, not just gold text —
## the text-only version read as "stuck hover".
func _mark_selected(btn: Button, on: bool) -> void:
	if on:
		var sel := StyleBoxFlat.new()
		sel.bg_color = Color("ffd166")
		sel.set_corner_radius_all(9)
		sel.content_margin_left = _us(14)
		sel.content_margin_right = _us(14)
		sel.content_margin_top = _us(7)
		sel.content_margin_bottom = _us(7)
		for state in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state, sel)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			btn.add_theme_color_override(state, Color("1c2333"))
	else:
		for state in ["normal", "hover", "pressed"]:
			btn.remove_theme_stylebox_override(state)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			btn.remove_theme_color_override(state)

func _refresh_battle_highlights() -> void:
	if world == null:
		return
	for minutes: int in _length_btns.keys():
		_mark_selected(_length_btns[minutes], minutes == world.client_minutes)
	for arena: int in _size_btns.keys():
		_mark_selected(_size_btns[arena], arena == world.client_size)
	for mode_key: String in _mode_btns.keys():
		_mark_selected(_mode_btns[mode_key], mode_key == world.client_mode)
	if _battle_opts != null:
		_battle_opts.visible = world.client_mode == "battle"
	_refresh_team_box()

## The team matrix: one row per player, one column per team. You can move
## yourself and any computer player; other humans only move themselves,
## so their rows are read-only dots.
func _refresh_team_box() -> void:
	if _team_box == null:
		return
	for child in _team_box.get_children():
		child.queue_free()
	if world == null:
		return
	if _add_bot_btn != null:
		_add_bot_btn.disabled = Game.roster.size() >= 24
	var me := multiplayer.get_unique_id()
	var names: Array = world.client_team_names
	var team_count: int = maxi(names.size(), 2)
	var cell_w := _us(46) if team_count <= 8 else _us(32)
	var hscroll := ScrollContainer.new()
	hscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hscroll.custom_minimum_size = Vector2(0, _us(25) * (Game.roster.size() + 2) + _us(14))
	_team_box.add_child(hscroll)
	var grid := GridContainer.new()
	grid.columns = team_count + 2
	grid.add_theme_constant_override("h_separation", _us(4))
	grid.add_theme_constant_override("v_separation", _us(4))
	hscroll.add_child(grid)
	grid.add_child(Label.new())
	for t in team_count:
		# Team header: colored name, click to rename in place.
		var head := Button.new()
		head.focus_mode = Control.FOCUS_NONE
		head.flat = true
		head.text = str(names[t]) if t < names.size() else str(t + 1)
		head.add_theme_font_size_override("font_size", _us(14))
		var head_style := StyleBoxFlat.new()
		head_style.bg_color = Color(0, 0, 0, 0)
		head_style.set_content_margin_all(_us(2))
		for head_state in ["normal", "hover", "pressed"]:
			head.add_theme_stylebox_override(head_state, head_style)
		head.add_theme_color_override("font_color", WorldNode.TEAM_COLORS[t])
		head.custom_minimum_size = Vector2(cell_w, 0)
		var team_index := t
		head.pressed.connect(func() -> void:
			_rename_team(head, team_index))
		grid.add_child(head)
	grid.add_child(Label.new())
	var ordered_ids: Array = Game.roster.keys()
	ordered_ids.sort_custom(func(a_id: String, b_id: String) -> bool:
		var a_bot := bool(Game.roster[a_id].get("bot", false))
		var b_bot := bool(Game.roster[b_id].get("bot", false))
		if a_bot != b_bot:
			return b_bot  # humans first
		return a_id < b_id)
	for id: String in ordered_ids:
		var entry: Dictionary = Game.roster[id]
		var team := int(entry.get("team", -1))
		var mine: bool = int(entry.peer) == me and int(entry.slot) == slot
		var bot: bool = bool(entry.get("bot", false))
		var name_label := Label.new()
		name_label.text = str(entry.name) + (" (you)" if mine else "") + ("  🤖" if bot else "")
		name_label.custom_minimum_size = Vector2(_us(120), 0)
		name_label.add_theme_font_size_override("font_size", _us(15))
		name_label.add_theme_color_override("font_color",
			WorldNode.TEAM_COLORS[team] if team >= 0 else Color.WHITE)
		grid.add_child(name_label)
		var target_id := id
		var target_slot := int(entry.slot)
		for t in team_count:
			if mine or bot:
				var cell_btn := Button.new()
				cell_btn.focus_mode = Control.FOCUS_NONE
				cell_btn.custom_minimum_size = Vector2(cell_w, _us(20))
				var style := StyleBoxFlat.new()
				style.bg_color = WorldNode.TEAM_COLORS[t] * (1.0 if t == team else 0.3)
				style.bg_color.a = 1.0
				style.set_corner_radius_all(6)
				if t == team:
					style.border_color = Color.WHITE
					style.set_border_width_all(2)
				for state in ["normal", "hover", "pressed"]:
					cell_btn.add_theme_stylebox_override(state, style)
				var pick_team := t
				cell_btn.pressed.connect(func() -> void:
					if bot and not mine:
						if Game.world != null:
							Game.world.sv_set_bot_team.rpc_id(1, target_id, pick_team)
					else:
						Game.set_local_team(target_slot, pick_team)
					Sfx.play("tick", -8.0))
				grid.add_child(cell_btn)
			else:
				var dot := Label.new()
				dot.text = "●" if t == team else "·"
				dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				dot.add_theme_font_size_override("font_size", _us(18))
				dot.add_theme_color_override("font_color",
					WorldNode.TEAM_COLORS[t] if t == team else Color(1, 1, 1, 0.25))
				grid.add_child(dot)
		if bot:
			var kick := Button.new()
			kick.focus_mode = Control.FOCUS_NONE
			kick.text = "✕"
			kick.add_theme_font_size_override("font_size", _us(13))
			var kick_style := StyleBoxFlat.new()
			kick_style.bg_color = Color(0.14, 0.16, 0.23)
			kick_style.set_corner_radius_all(6)
			kick_style.set_content_margin_all(_us(3))
			for kick_state in ["normal", "hover", "pressed"]:
				kick.add_theme_stylebox_override(kick_state, kick_style)
			kick.add_theme_color_override("font_color", Color("ff6b6b"))
			kick.pressed.connect(func() -> void:
				if Game.world != null:
					Game.world.sv_remove_bot.rpc_id(1, target_id)
				Sfx.play("pop"))
			grid.add_child(kick)
		else:
			grid.add_child(Label.new())
	# Bottom row: an ✕ under each column deletes that team (its computer
	# players spread themselves over the remaining teams).
	if team_count > 2:
		grid.add_child(Label.new())
		for t in team_count:
			var del_btn := Button.new()
			del_btn.focus_mode = Control.FOCUS_NONE
			del_btn.flat = true
			del_btn.text = "✕"
			del_btn.add_theme_font_size_override("font_size", _us(14))
			del_btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
			var gone := t
			del_btn.pressed.connect(func() -> void:
				if Game.world != null:
					Game.world.sv_remove_team.rpc_id(1, gone)
				Sfx.play("pop"))
			grid.add_child(del_btn)
		grid.add_child(Label.new())

## Under-radar panel: one colored row per team with its alive count.
func _refresh_team_panel() -> void:
	if _team_panel == null or world == null:
		return
	for child in _team_panel.get_children():
		child.queue_free()
	var names: Array = world.client_team_names
	for t in names.size():
		var alive := 0
		var total := 0
		for rid: String in Game.roster.keys():
			if int(Game.roster[rid].get("team", -1)) == t:
				total += 1
				if world.alive_ids.has(rid):
					alive += 1
		if total == 0:
			continue
		var row_label := Label.new()
		row_label.text = "%s  %d/%d" % [str(names[t]), alive, total]
		row_label.add_theme_font_size_override("font_size", _us(14))
		row_label.add_theme_color_override("font_color", WorldNode.TEAM_COLORS[t])
		row_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
		row_label.add_theme_constant_override("outline_size", 4)
		row_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_team_panel.add_child(row_label)

## Swap a team header button for a LineEdit; commit renames server-side.
func _rename_team(head: Button, index: int) -> void:
	var edit := LineEdit.new()
	edit.text = head.text
	edit.max_length = 10
	edit.add_theme_font_size_override("font_size", _us(15))
	edit.custom_minimum_size = Vector2(_us(70), 0)
	head.add_sibling(edit)
	head.visible = false
	edit.grab_focus()
	edit.select_all()
	var commit := func() -> void:
		if Game.world != null and not edit.text.strip_edges().is_empty():
			Game.world.sv_rename_team.rpc_id(1, index, edit.text)
		edit.queue_free()
		head.visible = true
	edit.text_submitted.connect(func(_t: String) -> void: commit.call())
	edit.focus_exited.connect(commit)

## A controls cheat-sheet so nobody has to memorize the pad layout.
func _build_help_tab() -> void:
	var tab := _scrolled_tab("Help", _video_tabs)
	tab.add_theme_constant_override("separation", _us(6))
	_add_section(tab, "🎮  CONTROLLER")
	for line in ["Left stick — move      L3 (click stick) — creep quietly",
			"Right stick — orbit the camera, up and down too",
			"Ⓐ — jump / select      Ⓑ or RB — dig",
			"RT — fire / place      LB — fly up      LT — descend",
			"D-pad up/down — zoom      D-pad left/right — weapon",
			"Ⓨ — camera view (orbit / top-down / first person)",
			"Start or Ⓧ — menu      in menu: LB/RB pages, LT/RT groups",
			"Hold Ⓑ — leave the game"]:
		var pad_line := Label.new()
		pad_line.text = str(line)
		pad_line.add_theme_font_size_override("font_size", _us(17))
		tab.add_child(pad_line)
	_add_section(tab, "⌨  KEYBOARD + MOUSE")
	for line in ["WASD — move      Shift — creep      Space — jump",
			"Z / X — spin camera      E — blocks      Esc — menu",
			"Click — dig      Right-click — place      1-8 — hotbar",
			"T — camera view      F — fly (when idle)"]:
		var key_line := Label.new()
		key_line.text = str(line)
		key_line.add_theme_font_size_override("font_size", _us(17))
		tab.add_child(key_line)
	_add_section(tab, "🏆  BATTLE ROYALE")
	for line in ["Set up teams and computer players on Game ▸ Players.",
			"Grab crates for weapons — the sword alone won't win it.",
			"Stay inside the storm circle (watch the radar ring).",
			"Downed teammates revive if you stand close to them.",
			"Winner sticks around — battles loop until the host stops them."]:
		var tip_line := Label.new()
		tip_line.text = "• " + str(line)
		tip_line.add_theme_font_size_override("font_size", _us(17))
		tab.add_child(tip_line)

## Its own tab: every video setting individually — numbers get sliders,
## switches get checkboxes. No presets, no magic.
func _build_video_tab() -> void:
	var tab := _scrolled_tab("Video", _video_tabs)
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
	lite_btn.text = "🎨  Renderer: " + ("Lite" if is_lite else "Full") \
		+ " — restart required"
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
	_menu_dim.visible = false
	_set_nav_focus(null)
	_prev_nav_select = true
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
	if _menu != null and _menu.visible and _current_page() == PAGE_CHARACTER:
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
			var group_cycle := input.group_cycle_direction()
			if group_cycle != 0 and not _menu_group_latch:
				_groups.current_tab = posmod(_groups.current_tab + group_cycle, 4)
				Sfx.play("tick", -12.0)
			_menu_group_latch = group_cycle != 0
			var tab_cycle := input.cycle_direction()
			if tab_cycle != 0 and not _menu_tab_latch:
				var next_tab := _current_page()
				for attempt in _PAGES.size() - 1:
					next_tab = posmod(next_tab + tab_cycle, _PAGES.size())
					if not _page_disabled(next_tab):
						break
				_set_page(next_tab)
				Sfx.play("tick", -12.0)
			_menu_tab_latch = tab_cycle != 0
			if input.is_view_toggle_pressed():
				_close_menu()
			var page := _current_page()
			if page < _pickers.size():
				_pickers[page].poll(input, _delta)
			else:
				_poll_page_nav(input, _delta)
	if not _menu.visible and player.ui_locked:
		player.ui_locked = false
	if OS.get_environment("WORLD_AUTOTEST_MENU") == "1" and slot == 0 \
			and not _autoopened and Time.get_ticks_msec() > 9000:
		_autoopened = true
		_toggle_menu(player, 1)
	if _autoopened and _menu.visible and not OS.get_environment("WORLD_AUTOTEST_TAB").is_empty():
		_set_page(int(OS.get_environment("WORLD_AUTOTEST_TAB")))

	var am_host: bool = Game.host_peer == multiplayer.get_unique_id()
	if _game_tabs != null and _game_tabs.get_tab_count() >= 3:
		_game_tabs.set_tab_hidden(0, not am_host)
		_game_tabs.set_tab_hidden(1, not am_host)
		if not am_host and _game_tabs.current_tab != 2:
			_game_tabs.current_tab = 2
	if _battle_start != null and world != null:
		_battle_start.visible = am_host and world.client_mode == "battle"
		match world.match_phase:
			"IDLE":
				_battle_start.disabled = false
				_battle_start.text = "🏆  Start Battle"
			"LOBBY":
				_battle_start.disabled = true
				_battle_start.text = "⚔  Battle starts in %d…" % int(ceil(world.match_seconds))
			"COUNTDOWN":
				_battle_start.disabled = true
				_battle_start.text = "🏆  Next battle in %d…" % int(ceil(world.match_seconds))
			_:
				_battle_start.disabled = true
				_battle_start.text = "⚔  Battle in progress"
	if _lobby_countdown != null and world != null:
		var in_lobby: bool = world.match_phase == "LOBBY"
		_lobby_countdown.visible = in_lobby
		if in_lobby:
			_lobby_countdown.text = "🏆  Battle starts in %d — pick your team!" \
				% int(ceil(world.match_seconds))
	if _ride_hint != null and world != null and world.critter_view != null:
		var mate_down := ""
		if world.match_phase == "BATTLE":
			var my_team := int(Game.roster.get(Game.player_id(
				multiplayer.get_unique_id(), slot), {}).get("team", -1))
			for down_id: String in world.client_downed.keys():
				if int(Game.roster.get(down_id, {}).get("team", -2)) != my_team:
					continue
				for child in world.players.get_children():
					if child is Player and child.player_id == down_id \
							and child.position.distance_to(player.position) < 6.0:
						mate_down = str(Game.roster.get(down_id, {}).get("name", "?"))
		if not mate_down.is_empty() and player.riding < 0:
			_ride_hint.visible = true
			_ride_hint.text = "⛑  Stay close to revive %s!" % mate_down
		elif player.riding >= 0:
			_ride_hint.visible = true
			_ride_hint.text = "🐉  RT breathe fire · look to steer · Ⓐ climb · LT dive · Ⓐ Ⓐ hop off"
		elif not _menu.visible and player.on_floor \
				and world.critter_view.nearest_dragon(player.position, 9.0) >= 0:
			_ride_hint.visible = true
			_ride_hint.text = "🐉  A dragon! Walk up to it to climb on"
		else:
			_ride_hint.visible = false
	if _center_note != null and world != null:
		var secs := int(ceil(world.match_seconds))
		if world.match_phase == "LOBBY" and not _menu.visible:
			_center_note.visible = true
			_center_note.text = "🏆  Next battle in %d — pick your team in the menu!" % secs
		elif world.match_phase == "DROP":
			_center_note.visible = true
			_center_note.text = "🪂  Dropping in — steer with the stick, land near loot!"
		else:
			_center_note.visible = false
	if _team_panel != null and world != null:
		_team_panel.visible = world.match_phase == "BATTLE"
	if _score_label != null and world != null:
		var in_battle: bool = world.match_phase == "BATTLE"
		_score_label.visible = in_battle
		if in_battle:
			var me_id := Game.player_id(multiplayer.get_unique_id(), slot)
			var team := int(Game.roster.get(me_id, {}).get("team", -1))
			var mates_alive := 0
			var mates_total := 0
			for rid: String in Game.roster.keys():
				if int(Game.roster[rid].get("team", -2)) == team:
					mates_total += 1
					if world.alive_ids.has(rid):
						mates_alive += 1
			var team_name := "?"
			if team >= 0 and team < world.client_team_names.size():
				team_name = str(world.client_team_names[team])
			_score_label.text = "🚩 %s  %d/%d alive   ·   %d players left" % [
				team_name, mates_alive, mates_total, world.alive_ids.size()]
	if _vignette != null and world != null:
		# The hurt vignette: strongest when hearts are low, eases back as
		# regen tops you up.
		var vg_hp := int(world.hearts.get(Game.player_id(
			multiplayer.get_unique_id(), slot), 8))
		var vg_target := clampf((5.0 - vg_hp) / 5.0, 0.0, 0.75) \
			if world.match_phase == "BATTLE" else 0.0
		_vignette.modulate.a = lerpf(_vignette.modulate.a, vg_target, 0.06)
	if _damage_flash != null:
		_damage_t = maxf(0.0, _damage_t - _delta)
		_damage_flash.color.a = minf(_damage_t, 0.45) * 0.8
		_damage_arrow.visible = _damage_t > 0.0
		if _damage_arrow.visible:
			var to_threat := _damage_from - player.position
			var threat_angle := atan2(to_threat.x, -to_threat.z) + player.camera_yaw
			_damage_arrow.rotation = threat_angle
			_damage_arrow.pivot_offset = _damage_arrow.size / 2.0
			_damage_arrow.position = size / 2.0 - _damage_arrow.size / 2.0 \
				+ Vector2(sin(threat_angle), -cos(threat_angle)) * _us(90)
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
		if _team_panel != null:
			_team_panel.position = Vector2(size.x - map_px - 10,
				12 + map_px + maxf(map_px / 8.0, _us(22)))
			_team_panel.custom_minimum_size = Vector2(map_px, 0)
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
	if _menu != null:
		# Scale around the middle so the shrunken menu stays centered in
		# this player's cell instead of hugging the top-left corner.
		_menu.pivot_offset = _menu.size / 2.0
	if _chip != null:
		_chip.visible = not _menu.visible and _treasure_label.text != ""
	if _water_tint != null and world != null and world.chunks != null:
		var eye := player.position + Vector3(0, Player.EYE_HEIGHT, 0)
		var under: bool = Blocks.is_liquid(world.chunks.get_block(
			Vector3i(floori(eye.x), floori(eye.y), floori(eye.z))))
		_water_tint.color.a = lerpf(_water_tint.color.a, 0.35 if under else 0.0, 0.25)
	if _storm_tint != null and world != null:
		var danger := 0.0
		if world.match_phase == "BATTLE" and world.storm_radius > 0.0 \
				and Vector2(player.position.x - world.storm_center.x,
					player.position.z - world.storm_center.z).length() > world.storm_radius:
			danger = 0.25
		_storm_tint.color.a = lerpf(_storm_tint.color.a, danger, 0.1)
	# Caught outside the storm: a big arrow home plus the distance.
	if world != null and world.match_phase == "BATTLE" and world.storm_radius > 0.0:
		var flat := Vector2(player.position.x - world.storm_center.x,
			player.position.z - world.storm_center.z)
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
