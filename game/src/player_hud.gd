class_name PlayerHud
extends Control
## Per-player overlay inside their split-screen cell: name chip (click the
## swatch to change your look, click the name to type a new one), treasure
## counter, and the block hotbar along the bottom.

var slot := -1
var world: Node = null

var _name_label: Label
var _treasure_label: Label
var _swatch: ColorRect
var _hotbar: HBoxContainer
var _chips: Array = []
var _last_index := -1
var _last_style := -1

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
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(22, 22)
	_swatch.mouse_filter = Control.MOUSE_FILTER_STOP
	_swatch.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			Game.cycle_local_style(slot, 1)
			Sfx.play("pop", -4.0))
	row.add_child(_swatch)
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
	_hotbar.add_theme_constant_override("separation", 4)
	bar_panel.add_child(_hotbar)
	for block: int in Blocks.HOTBAR:
		var chip_rect := ColorRect.new()
		var color := Blocks.color_of(block)
		chip_rect.color = Color(color.r, color.g, color.b, 1.0)
		chip_rect.custom_minimum_size = Vector2(22, 22)
		_hotbar.add_child(chip_rect)
		_chips.append(chip_rect)

	if world != null:
		world.treasures_changed.connect(_refresh_identity)
	Game.roster_changed.connect(_refresh_identity)
	_refresh_identity()

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
	_swatch.color = AvatarFactory.body_color(int(entry.get("style", 0)))
	var id := Game.player_id(multiplayer.get_unique_id(), slot)
	var count: int = world.treasures.get(id, 0) if world != null else 0
	_treasure_label.text = "✦ %d" % count

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
	if player.hotbar_index != _last_index:
		_last_index = player.hotbar_index
		for i in _chips.size():
			var chip: ColorRect = _chips[i]
			var selected := i == _last_index
			chip.custom_minimum_size = Vector2(30, 30) if selected else Vector2(22, 22)
			var color := Blocks.color_of(Blocks.HOTBAR[i])
			chip.color = Color(color.r, color.g, color.b, 1.0) if selected \
				else Color(color.r * 0.75, color.g * 0.75, color.b * 0.75, 0.85)
