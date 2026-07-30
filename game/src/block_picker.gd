class_name BlockPicker
extends PanelContainer
## Minecraft-style selection view (E / D-pad up), one per split-screen cell.
## A grid of every block plus the prefab structures, with the focused entry's
## name in big letters. Navigate with WASD / stick / D-pad, choose with
## jump/place (or click), close with E again.

var COLUMNS := 10

signal picked(entry: Dictionary)

var entries: Array = []      # {kind: "block"/"structure", id, name, color}
var focus_index := 0
var _title: Label
var _chips: Array = []
var _scroll: ScrollContainer
var _nav_cooldown := 0.0

var category := "blocks"

func _init(p_category := "blocks") -> void:
	category = p_category
	if category == "tools":
		COLUMNS = 7
	elif category == "blocks":
		COLUMNS = 8  # one material family per line
	elif category == "kits":
		COLUMNS = 4  # big preview chips
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	style.set_border_width_all(0)
	add_theme_stylebox_override("panel", style)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	match category:
		"tools":
			for w in Weapons.WEAPONS:
				if not w.get("hidden", false):
					entries.append({"kind": "weapon", "id": w.id, "name": w.name, "color": w.color})
		"blocks":
			for block in Blocks.family_blocks():
				entries.append({"kind": "block", "id": block,
					"name": Blocks.display_name(block), "color": Blocks.color_of(block)})
		"special":
			for block in Blocks.SPECIAL_BLOCKS:
				entries.append({"kind": "block", "id": block,
					"name": Blocks.display_name(block), "color": Blocks.color_of(block)})
		"kits":
			for i in Structures.count():
				var spec := Structures.spec(i)
				entries.append({"kind": "structure", "id": i,
					"name": spec.name, "color": spec.color})

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color("ffd166"))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	# Chips keep their size on small screens; the grid scrolls instead of
	# squashing everything to fit.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_scroll)
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	_scroll.add_child(grid)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(40, 40)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		var icon := BlockIcon.new(int(entry.id), entry.kind)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 4
		icon.offset_top = 4
		icon.offset_right = -4
		icon.offset_bottom = -4
		chip.add_child(icon)
		var index := i
		chip.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed \
					and event.button_index == MOUSE_BUTTON_LEFT:
				focus_index = index
				_select()
			elif event is InputEventMouseMotion:
				if focus_index != index:
					focus_index = index
					_refresh())
		grid.add_child(chip)
		_chips.append(chip)


## Scale chips and text so the grid uses the space it's given — tiny
## quarter-screen cells and huge fullscreen windows both read well.
func fit(avail: Vector2) -> void:
	# Width decides the chip size (the columns must fit); running out of
	# HEIGHT just means the grid scrolls, so chips never shrink for it.
	var chip := clampf((avail.x * 0.92 - 50.0) / COLUMNS - 5.0, 44.0, 130.0)
	for panel: Panel in _chips:
		panel.custom_minimum_size = Vector2(chip, chip)
		for child in panel.get_children():
			if child is Label:
				child.add_theme_font_size_override("font_size", int(chip * 0.55))
	_title.add_theme_font_size_override("font_size", int(clampf(chip * 0.75, 22.0, 48.0)))

var _slot_label := 1
func set_slot_label(n: int) -> void:
	_slot_label = n
	if visible:
		_refresh()

func open(_a := 0, _b := 0) -> void:
	visible = true
	_refresh()

func close() -> void:
	visible = false

## Poll navigation/choose from this player's InputSlot; PlayerHud calls this
## every frame while open. Returns true while staying open.
func poll(input: InputSlot, delta: float) -> void:
	_nav_cooldown = maxf(0.0, _nav_cooldown - delta)
	var nav := input.get_ui_vector()
	if _nav_cooldown <= 0.0 and nav.length() > 0.5:
		var step := Vector2i(0, 0)
		if absf(nav.x) > absf(nav.y):
			step.x = 1 if nav.x > 0 else -1
		else:
			step.y = 1 if nav.y > 0 else -1
		var next := focus_index + step.x + step.y * COLUMNS
		if next >= 0 and next < entries.size():
			focus_index = next
			_nav_cooldown = 0.16
			Sfx.play("tick", -14.0)
			_refresh()
	if input.is_primary_pressed() or input.is_place_pressed():
		_select()

func _select() -> void:
	Sfx.play("pop", -4.0)
	picked.emit(entries[focus_index])

func _refresh() -> void:
	_title.text = str(entries[focus_index].name)
	if _scroll != null and focus_index < _chips.size():
		_scroll.ensure_control_visible(_chips[focus_index])
	for i in _chips.size():
		var chip: Panel = _chips[i]
		var entry: Dictionary = _chips[i].get_meta("entry", entries[i])
		var style := StyleBoxFlat.new()
		var color: Color = entries[i].color
		style.bg_color = Color(0.1, 0.11, 0.16)
		style.set_corner_radius_all(6)
		if i == focus_index:
			style.border_color = Color.WHITE
			style.set_border_width_all(3)
		chip.add_theme_stylebox_override("panel", style)
