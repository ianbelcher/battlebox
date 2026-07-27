class_name BlockPicker
extends PanelContainer
## Minecraft-style selection view (E / D-pad up), one per split-screen cell.
## A grid of every block plus the prefab structures, with the focused entry's
## name in big letters. Navigate with WASD / stick / D-pad, choose with
## jump/place (or click), close with E again.

const COLUMNS := 10

signal picked(entry: Dictionary)

var entries: Array = []      # {kind: "block"/"structure", id, name, color}
var focus_index := 0
var _title: Label
var _chips: Array = []
var _nav_cooldown := 0.0

func _init() -> void:
	visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.92)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	style.border_color = Color("ffd166")
	style.set_border_width_all(2)
	add_theme_stylebox_override("panel", style)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

	for block: int in Blocks.HOTBAR:
		entries.append({"kind": "block", "id": block,
			"name": Blocks.display_name(block), "color": Blocks.color_of(block)})
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
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(34, 34)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		if entry.kind == "structure":
			var mark := Label.new()
			mark.text = "⌂"
			mark.add_theme_font_size_override("font_size", 20)
			mark.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
			mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			mark.grow_horizontal = Control.GROW_DIRECTION_BOTH
			mark.grow_vertical = Control.GROW_DIRECTION_BOTH
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(mark)
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
	var hint := Label.new()
	hint.text = "move: WASD / stick   choose: Space / A / click   close: E"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

func open(current_block_index: int, current_structure: int) -> void:
	focus_index = current_block_index if current_structure < 0 \
		else Blocks.HOTBAR.size() + current_structure
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
	close()

func _refresh() -> void:
	_title.text = str(entries[focus_index].name)
	for i in _chips.size():
		var chip: Panel = _chips[i]
		var entry: Dictionary = _chips[i].get_meta("entry", entries[i])
		var style := StyleBoxFlat.new()
		var color: Color = entries[i].color
		style.bg_color = Color(color.r, color.g, color.b, 1.0)
		style.set_corner_radius_all(6)
		if i == focus_index:
			style.border_color = Color.WHITE
			style.set_border_width_all(3)
		chip.add_theme_stylebox_override("panel", style)
