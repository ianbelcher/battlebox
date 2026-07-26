class_name SplitScreen
extends Control
## Dynamic 1-4 player split screen. Every cell is a SubViewportContainer whose
## SubViewport shares the root viewport's World3D (the world lives under the
## Game autoload), with its own isometric camera rig and HUD overlay.
##
## 0 players -> one full-screen spectator cell slowly orbiting the spawn with
## a big "press a button to join" prompt. 3 players -> the fourth cell is a
## join hint.

const ISO_OFFSET := Vector3(30.0, 37.0, 30.0)
const ORTHO_SIZE_SOLO := 18.0
const ORTHO_SIZE_SPLIT := 15.0

var world: Node = null
var _cells: Array = []   # [{slot:int(-1=spectator), container, viewport, rig, cam, hud}]
var _orbit_angle := 0.0

func _ready() -> void:
	# set_anchors_and_offsets_preset, NOT set_anchors_preset: inside _ready
	# the parent may still be laid out at size 0, and the anchors-only call
	# keeps offsets that freeze this control at that zero rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Rebuild the cell layout for the current set of local slots.
func update_layout() -> void:
	for cell: Dictionary in _cells:
		cell.container.queue_free()
	_cells.clear()
	if world == null:
		return
	var slots: Array = Game.local_inputs.keys()
	slots.sort()
	var count := slots.size()
	var rects := _layout_rects(maxi(count, 1))
	if count == 0:
		_add_cell(-1, rects[0])
		return
	for i in count:
		_add_cell(slots[i], rects[i])
	if count == 3:
		_add_join_hint(rects[3])

## Anchor rects (in fractions) per cell for a given player count.
func _layout_rects(count: int) -> Array:
	match count:
		1:
			return [Rect2(0, 0, 1, 1)]
		2:
			return [Rect2(0, 0, 0.5, 1), Rect2(0.5, 0, 0.5, 1)]
		_:
			return [Rect2(0, 0, 0.5, 0.5), Rect2(0.5, 0, 0.5, 0.5),
				Rect2(0, 0.5, 0.5, 0.5), Rect2(0.5, 0.5, 0.5, 0.5)]

func _place(control: Control, frac: Rect2) -> void:
	control.anchor_left = frac.position.x
	control.anchor_top = frac.position.y
	control.anchor_right = frac.position.x + frac.size.x
	control.anchor_bottom = frac.position.y + frac.size.y
	control.offset_left = 1
	control.offset_top = 1
	control.offset_right = -1
	control.offset_bottom = -1

func _add_cell(slot: int, frac: Rect2) -> void:
	var container := SubViewportContainer.new()
	container.stretch = true
	_place(container, frac)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.world_3d = get_tree().root.find_world_3d()
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var rig := Node3D.new()
	viewport.add_child(rig)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ORTHO_SIZE_SOLO if Game.local_inputs.size() <= 1 else ORTHO_SIZE_SPLIT
	cam.near = 0.5
	cam.far = 300.0
	viewport.add_child(cam)
	var hud: Control = null
	if slot >= 0:
		hud = PlayerHud.new()
		hud.slot = slot
		hud.world = world
		container.add_child(hud)
	else:
		container.add_child(_spectator_prompt())
	_cells.append({"slot": slot, "container": container, "viewport": viewport,
		"rig": rig, "cam": cam, "hud": hud})

func _spectator_prompt() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var title := Label.new()
	title.text = "BELCHER WORLD"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color("ffd166"))
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var prompt := Label.new()
	prompt.text = "Press SPACE, ENTER or a gamepad's A button to jump in!"
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.add_theme_color_override("font_color", Color.WHITE)
	prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(prompt)
	return center

func _add_join_hint(frac: Rect2) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1)
	style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", style)
	_place(panel, frac)
	add_child(panel)
	var label := Label.new()
	label.text = "Press a button\nto join!"
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	_cells.append({"slot": -2, "container": panel, "viewport": null,
		"rig": null, "cam": null, "hud": null})

func _find_player(slot: int) -> Player:
	if world == null or world.players == null:
		return null
	for child in world.players.get_children():
		if child is Player and child.is_local and child.slot == slot:
			return child
	return null

func _process(delta: float) -> void:
	_orbit_angle += delta * 0.12
	for cell: Dictionary in _cells:
		if cell.cam == null:
			continue
		var rig: Node3D = cell.rig
		var cam: Camera3D = cell.cam
		if cell.slot < 0:
			# Spectator: slow orbit around the spawn.
			var spawn := Vector3(world.spawn_pos) if world != null else Vector3.ZERO
			var offset := Vector3(cos(_orbit_angle), 0, sin(_orbit_angle)) * 34.0 + Vector3(0, 30, 0)
			cam.look_at_from_position(spawn + offset, spawn, Vector3.UP)
			cam.size = 22.0
			continue
		var player := _find_player(cell.slot)
		if player == null:
			continue
		# Smooth-follow the player from a fixed isometric direction.
		rig.position = rig.position.lerp(player.position, minf(1.0, delta * 6.0))
		cam.look_at_from_position(rig.position + ISO_OFFSET, rig.position + Vector3(0, 1.0, 0), Vector3.UP)
