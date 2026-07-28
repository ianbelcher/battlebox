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
Your 8 hotbar slots hold blocks, kits AND weapons - press E to
fill the current slot, switch with 1-8 (bumpers / D-pad on pads).
Hold a weapon and RIGHT-CLICK (X / F) to fire: BLASTER sprays,
BAZOOKA booms. During a raid: NO FLYING, and Grumps climb walls!
Explosions set grass and wood ON FIRE - it spreads like Minecraft
and gutters out on stone. Materials matter: wood burns and breaks,
stone shrugs off pellets, STEEL only chips on a direct bazooka
hit, DIAMOND is untouchable.
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

var _swatches: Dictionary = {}   # attr -> ColorRect
var _hotbar: HBoxContainer
var _chips: Array = []
var _last_index := -1
var _last_style := -1
var _last_width := -1.0
var _slots_dirty := true
var _prev_slot_pick_menu := -1
var _autoopened := false
var _crosshair: Label

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
	add_child(chip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	chip.add_child(row)
	# Three swatches: skin tone, shirt, hat. Click to cycle that part.
	for attr in ["body", "shirt", "hat"]:
		var swatch := ColorRect.new()
		swatch.custom_minimum_size = Vector2(_us(24), _us(24))
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
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu)
	_tabs = TabContainer.new()
	_tabs.add_theme_font_size_override("font_size", _us(20))
	_menu.add_child(_tabs)
	var guide := Label.new()
	guide.name = "How to Play"
	guide.add_theme_font_size_override("font_size", _us(19))
	guide.text = GUIDE_TEXT
	_tabs.add_child(guide)
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

	_picker = BlockPicker.new()
	_picker.name = "Blocks & Kits"
	_picker.picked.connect(_on_picked)
	_tabs.add_child(_picker)
	_info = Label.new()
	_info.name = "World"
	_info.add_theme_font_size_override("font_size", _us(22))
	_tabs.add_child(_info)
	_build_character_tab()

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
	_picker.set_slot_label(player.selected_slot + 1)
	_picker.open()
	var id := Game.player_id(multiplayer.get_unique_id(), slot)
	_info.text = "%d playing right now\nYour treasures: %d\nWorld source: %s\n\nThe world is saved all the time - whatever\nyou build is still here tomorrow.\nFly up high... some islands float.\nDig deep... some caves glow." % [
		Game.roster.size(), int(world.treasures.get(id, 0)), str(world.source)]
	Sfx.play("card" if Sfx._streams.has("card") else "tick", -8.0)

## "Character" tab: big friendly buttons for name, skin, shirt and hat.
func _build_character_tab() -> void:
	var tab := VBoxContainer.new()
	tab.name = "Character"
	tab.add_theme_constant_override("separation", _us(14))
	_tabs.add_child(tab)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", _us(10))
	tab.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "Name:"
	name_label.add_theme_font_size_override("font_size", _us(22))
	name_row.add_child(name_label)
	var name_edit := LineEdit.new()
	name_edit.max_length = 12
	name_edit.custom_minimum_size = Vector2(_us(220), 0)
	name_edit.add_theme_font_size_override("font_size", _us(22))
	name_edit.text_submitted.connect(func(text: String) -> void:
		Game.set_local_name(slot, text)
		Sfx.play("pop", -4.0))
	name_row.add_child(name_edit)
	for attr in ["body", "shirt", "hat"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _us(10))
		tab.add_child(row)
		var attr_label := Label.new()
		attr_label.text = {"body": "Skin tone:", "shirt": "Shirt:", "hat": "Hat:"}[attr]
		attr_label.custom_minimum_size = Vector2(_us(140), 0)
		attr_label.add_theme_font_size_override("font_size", _us(22))
		row.add_child(attr_label)
		var attr_name := str(attr)
		for direction in [-1, 1]:
			var btn := Button.new()
			btn.text = "  ◀  " if direction < 0 else "  ▶  "
			btn.add_theme_font_size_override("font_size", _us(22))
			var d: int = direction
			btn.pressed.connect(func() -> void:
				Game.cycle_local_style(slot, attr_name, d)
				Sfx.play("pop", -6.0))
			row.add_child(btn)
	var hint := Label.new()
	hint.text = "Changes save to this controller and follow you between sessions."
	hint.add_theme_font_size_override("font_size", _us(16))
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	tab.add_child(hint)

func _on_picked(entry: Dictionary) -> void:
	var player := _player()
	if player == null:
		return
	player.slots[player.selected_slot] = {"kind": entry.kind, "id": entry.id}
	_slots_dirty = true
	# Stays open: press another number key and keep kitting out slots.
	_picker.set_slot_label(player.selected_slot + 1)

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
			_toggle_menu(player, 1)
		_prev_picker = picker_pressed
		var menu_pressed := input.is_menu_pressed()
		if menu_pressed and not _prev_menu:
			_toggle_menu(player, 0)
		_prev_menu = menu_pressed
		if _menu.visible:
			# 1-8 (or bumpers) keep working with the picker open, so kids can
			# fill slot after slot without closing it.
			var pick := input.slot_pick()
			if pick != _prev_slot_pick_menu and pick >= 0 and pick < 8:
				player.selected_slot = pick
				_slots_dirty = true
				_picker.set_slot_label(pick + 1)
				Sfx.play("tick", -10.0)
			_prev_slot_pick_menu = pick
			if _tabs.current_tab == 1:
				_picker.poll(input, _delta)
	if not _menu.visible and player.ui_locked:
		player.ui_locked = false
	if OS.get_environment("WORLD_AUTOTEST_MENU") == "1" and slot == 0 \
			and not _autoopened and Time.get_ticks_msec() > 9000:
		_autoopened = true
		_toggle_menu(player, 1)

	_crosshair.visible = player.fp_mode and not _menu.visible
	_crosshair.add_theme_font_size_override("font_size", _us(int(30 * (1.0 + player.fp_zoom * 0.8))))
	if size.x != _last_width:
		_last_width = size.x
		_selected_label.add_theme_font_size_override("font_size",
			int(clampf(size.x / 45.0, 16.0, 34.0)))
		_last_index = -1
	if player.selected_slot != _last_index or _slots_dirty:
		_last_index = player.selected_slot
		_slots_dirty = false
		var item: Dictionary = player.held()
		if item.kind == "weapon":
			_selected_label.text = "Blaster" if int(item.id) == 0 else "Bazooka"
		elif item.kind == "structure":
			_selected_label.text = str(Structures.spec(int(item.id)).name)
		else:
			_selected_label.text = Blocks.display_name(int(item.id))
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
