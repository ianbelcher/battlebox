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
var _treasure_label: Label
var _hearts_label: Label
var _selected_label: Label
var _picker: BlockPicker
var _menu: PanelContainer
var _tabs: TabContainer
var _info: Label
var _prev_picker := false
var _prev_menu := false

const GUIDE_TEXT := """Move: WASD / left stick        Jump: Space / A
Double-tap jump = FLY (hold jump to rise, Shift / LT to sink, land to stop)

Break block: LEFT CLICK / B         Place block: RIGHT CLICK / F / X
Shoot: R / middle click / RT. TAP = fast pellet (pops one block,
lights Boom Blocks from afar). HOLD then release = bazooka shell
that explodes where it lands. Both bonk friends and Grumps!
Blocks & building kits: E / D-pad up      Quick cycle: Tab / bumpers

T / Y: switch between first person and overview
In the overview: Z C spin the view, X V zoom (right stick on gamepads)

Boom Blocks are safe until you CLICK them - then run! Stack them
together and they all go up in one giant blast. Click a lit one to defuse.
Warp Stones teleport to each other. Music Blocks sing when stepped on.
Sponges drink ponds. Party Poppers are best discovered.

The [sword] Attack! button starts a Grump raid: they climb ONE block at
most, so walls keep them out. Orbs bonk them. Last as long as you can!

Hold Q / Back to leave. Everything is always saved."""
var _last_structure := -2
var _swatches: Dictionary = {}   # attr -> ColorRect
var _hotbar: HBoxContainer
var _chips: Array = []
var _last_index := -1
var _last_style := -1
var _last_width := -1.0

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
	add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	# Three swatches: skin tone, shirt, hat. Click to cycle that part.
	for attr in ["body", "shirt", "hat"]:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.mouse_filter = Control.MOUSE_FILTER_STOP
		swatch.tooltip_text = attr
		var attr_name := str(attr)
		swatch.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				Game.cycle_local_style(slot, attr_name, 1)
				Sfx.play("pop", -4.0))
		row.add_child(swatch)
		_swatches[attr_name] = swatch
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_edit_name())
	row.add_child(_name_label)
	_treasure_label = Label.new()
	_treasure_label.add_theme_font_size_override("font_size", 18)
	_treasure_label.add_theme_color_override("font_color", Color("ffd166"))
	row.add_child(_treasure_label)
	_hearts_label = Label.new()
	_hearts_label.add_theme_font_size_override("font_size", 18)
	_hearts_label.add_theme_color_override("font_color", Color("ff6b6b"))
	row.add_child(_hearts_label)

	# Bottom: hotbar.
	var bar_holder := CenterContainer.new()
	bar_holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar_holder.offset_top = -54
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
	# ~48 chips have to fit half a screen, so they're small; the selected one
	# grows and its name shows above the bar.
	for block: int in Blocks.HOTBAR:
		var chip_rect := ColorRect.new()
		var color := Blocks.color_of(block)
		chip_rect.color = Color(color.r, color.g, color.b, 1.0)
		chip_rect.custom_minimum_size = Vector2(11, 18)
		chip_rect.tooltip_text = Blocks.display_name(block)
		_hotbar.add_child(chip_rect)
		_chips.append(chip_rect)
	_selected_label = Label.new()
	_selected_label.add_theme_font_size_override("font_size", 15)
	_selected_label.add_theme_color_override("font_color", Color("ffd166"))
	_selected_label.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	_selected_label.add_theme_constant_override("outline_size", 5)
	_selected_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_selected_label.offset_top = -76
	_selected_label.offset_bottom = -58
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
	menu_style.border_color = Color("ffd166")
	menu_style.set_border_width_all(2)
	_menu.add_theme_stylebox_override("panel", menu_style)
	# Fill ~90% of this player's cell whatever its size — quarter-screen
	# split or a huge fullscreen window alike.
	_menu.anchor_left = 0.05
	_menu.anchor_right = 0.95
	_menu.anchor_top = 0.05
	_menu.anchor_bottom = 0.95
	_menu.visible = false
	add_child(_menu)
	_tabs = TabContainer.new()
	_menu.add_child(_tabs)
	var guide := Label.new()
	guide.name = "How to Play"
	guide.add_theme_font_size_override("font_size", 15)
	guide.text = GUIDE_TEXT
	_tabs.add_child(guide)
	_picker = BlockPicker.new()
	_picker.name = "Blocks & Kits"
	_picker.picked.connect(_on_picked)
	_tabs.add_child(_picker)
	_info = Label.new()
	_info.name = "World"
	_info.add_theme_font_size_override("font_size", 16)
	_tabs.add_child(_info)

	if world != null:
		world.treasures_changed.connect(_refresh_identity)
		world.survival_changed.connect(_refresh_identity)
		world.hearts_changed.connect(_refresh_identity)
	Game.roster_changed.connect(_refresh_identity)
	_refresh_identity()

func is_ui_open() -> bool:
	return _menu != null and _menu.visible

func _toggle_menu(player: Player, tab: int) -> void:
	if _menu.visible and _tabs.current_tab == tab:
		_menu.visible = false
		player.ui_locked = false
		return
	_menu.visible = true
	_tabs.current_tab = tab
	player.ui_locked = true
	_picker.fit(size)
	_picker.open(player.hotbar_index, player.selected_structure)
	var id := Game.player_id(multiplayer.get_unique_id(), slot)
	_info.text = "%d playing right now\nYour treasures: %d\nWorld source: %s\n\nThe world is saved all the time - whatever\nyou build is still here tomorrow.\nFly up high... some islands float.\nDig deep... some caves glow." % [
		Game.roster.size(), int(world.treasures.get(id, 0)), str(world.source)]
	Sfx.play("card" if Sfx._streams.has("card") else "tick", -8.0)

func _on_picked(entry: Dictionary) -> void:
	var player := _player()
	if player == null:
		return
	if entry.kind == "block":
		player.hotbar_index = Blocks.HOTBAR.find(int(entry.id))
		player.selected_structure = -1
	else:
		player.selected_structure = int(entry.id)
	_menu.visible = false
	player.ui_locked = false

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
	var entry := _entry()
	if entry.is_empty():
		return
	_name_label.text = str(entry.name)
	var style: Dictionary = AvatarFactory.normalize_style(entry.get("style"))
	_swatches["body"].color = AvatarFactory.skin_color(style)
	_swatches["shirt"].color = AvatarFactory.shirt_color(style)
	_swatches["hat"].color = HAT_CHIP_COLORS[int(style.hat) % HAT_CHIP_COLORS.size()]
	var id := Game.player_id(multiplayer.get_unique_id(), slot)
	var count: int = world.treasures.get(id, 0) if world != null else 0
	_treasure_label.text = "✦ %d" % count
	if world != null and world.survival_active:
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
	edit.add_theme_font_size_override("font_size", 18)
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
			_toggle_menu(player, 1)
		_prev_picker = picker_pressed
		var menu_pressed := input.is_menu_pressed()
		if menu_pressed and not _prev_menu:
			_toggle_menu(player, 0)
		_prev_menu = menu_pressed
		if _menu.visible and _tabs.current_tab == 1:
			_picker.poll(input, _delta)
	if not _menu.visible and player.ui_locked:
		player.ui_locked = false
	# Selected-structure label beats the block label.
	if player.selected_structure != _last_structure:
		_last_structure = player.selected_structure
		if player.selected_structure >= 0:
			_selected_label.text = str(Structures.spec(player.selected_structure).name)
			_last_index = -1
	if size.x != _last_width:
		_last_width = size.x
		var chip_w := clampf(size.x / 58.0, 9.0, 26.0)
		for chip: ColorRect in _chips:
			chip.custom_minimum_size = Vector2(chip_w, chip_w * 1.6)
		_selected_label.add_theme_font_size_override("font_size",
			int(clampf(size.x / 55.0, 14.0, 30.0)))
		_last_index = -1
	if player.hotbar_index != _last_index and player.selected_structure < 0:
		_last_index = player.hotbar_index
		_selected_label.text = Blocks.display_name(Blocks.HOTBAR[_last_index])
		for i in _chips.size():
			var chip: ColorRect = _chips[i]
			var selected := i == _last_index
			var chip_w := clampf(size.x / 58.0, 9.0, 26.0)
			chip.custom_minimum_size = Vector2(chip_w * 1.5, chip_w * 2.2) if selected \
				else Vector2(chip_w, chip_w * 1.6)
			var color := Blocks.color_of(Blocks.HOTBAR[i])
			chip.color = Color(color.r, color.g, color.b, 1.0) if selected \
				else Color(color.r * 0.75, color.g * 0.75, color.b * 0.75, 0.85)
