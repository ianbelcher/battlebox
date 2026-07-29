class_name SplitScreen
extends Control
## Dynamic 1-4 player split screen. Every cell is a SubViewportContainer whose
## SubViewport shares the root viewport's World3D (the world lives under the
## Game autoload), with its own isometric camera rig and HUD overlay.
##
## 0 players -> one full-screen spectator cell slowly orbiting the spawn with
## a big "press a button to join" prompt. 3 players -> the fourth cell is a
## join hint.

## Camera orbit: fixed pitch, four 90-degree yaw stops (spin to see behind
## things), and stepped zoom. Both tween smoothly toward their snap targets.
const CAM_DISTANCE := 42.4
const CAM_HEIGHT := 37.0
## From nearly-on-your-shoulder to a big map-like overview.
const ZOOM_SIZES: Array[float] = [5.0, 7.0, 10.0, 15.0, 22.0, 32.0, 48.0, 70.0, 100.0]
const FP_FOVS: Array[float] = [78.0, 45.0, 20.0, 8.0]
const DEFAULT_ZOOM := 3

var world: Node = null
var big_map: TextureRect = null
var low_fx := false

## Render cheaper: fewer pixels, no MSAA. Applied to current and future cells.
func set_low_fx(low: bool) -> void:
	low_fx = low
	for cell: Dictionary in _cells:
		if cell.viewport != null:
			var viewport: SubViewport = cell.viewport
			viewport.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
			viewport.scaling_3d_scale = 0.7 if low else 1.0
var _cells: Array = []   # [{slot:int(-1=spectator), container, viewport, rig, cam, hud,
                         #   yaw_index, yaw, zoom_index, size, prev_rot, prev_zoom}]
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
	viewport.msaa_3d = Viewport.MSAA_DISABLED if low_fx else Viewport.MSAA_2X
	viewport.scaling_3d_scale = 0.7 if low_fx else 1.0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var rig := Node3D.new()
	viewport.add_child(rig)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ZOOM_SIZES[DEFAULT_ZOOM]
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
		"rig": rig, "cam": cam, "hud": hud,
		"yaw_index": 0, "yaw": Player.ISO_ROT, "zoom_index": DEFAULT_ZOOM,
		"size": ZOOM_SIZES[DEFAULT_ZOOM], "prev_rot": 0, "prev_zoom": 0,
		"fp": true, "prev_view": false, "fp_zoom": 0})

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
	prompt.text = "Press SPACE or a gamepad's A button to jump in!"
	prompt.add_theme_font_size_override("font_size", 26)
	prompt.add_theme_color_override("font_color", Color.WHITE)
	prompt.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1, 0.9))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(prompt)
	return center

## With three players the spare quarter becomes a big battle map of the
## whole area (main.gd redraws it alongside the corner minimaps).
func _add_join_hint(frac: Rect2) -> void:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.08)
	style.set_corner_radius_all(0)
	panel.add_theme_stylebox_override("panel", style)
	_place(panel, frac)
	add_child(panel)
	big_map = TextureRect.new()
	big_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_child(big_map)
	_cells.append({"slot": -2, "container": panel, "viewport": null,
		"rig": null, "cam": null, "hud": null})

## First-person hand: the held item bottom-right of your own camera, on a
## render layer only your own camera draws.
func _update_viewmodel(cell: Dictionary, player: Player) -> void:
	var cam: Camera3D = cell.cam
	var sig := str(player.held())
	if cell.get("vm_sig", "") != sig:
		cell.vm_sig = sig
		if cell.get("vm") != null and is_instance_valid(cell.vm):
			cell.vm.queue_free()
			cell.vm = null
		var item: Dictionary = player.held()
		if item.kind != "empty":
			var model := ItemFactory.build(str(item.kind), int(item.id))
			model.scale = Vector3(0.9, 0.9, 0.9)
			var vm_layer := 1 << (10 + player.slot)
			for node in model.find_children("*", "VisualInstance3D", true, false):
				(node as VisualInstance3D).layers = vm_layer
			cam.add_child(model)
			var base := Vector3(0.3, -0.42, -0.72)
			# Long weapons sit further out so you never see their back end.
			if item.kind == "weapon" and int(item.id) in [1, 9]:
				base += Vector3(0.04, -0.04, -0.4)
			model.position = base
			model.rotation_degrees = Vector3(0, 6, 0)
			cell.vm = model
			cell.vm_base = base
	# camera masks: see own viewmodel layer, never others'
	var all_vm := 0
	for i in 4:
		all_vm |= 1 << (10 + i)
	cam.cull_mask = (((1 << 20) - 1) & ~player.render_layer_bit() & ~all_vm) | (1 << (10 + player.slot))

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
		var input: InputSlot = Game.local_inputs.get(cell.slot)
		# First-person toggle (T / gamepad Y); Esc also exits on keyboard.
		if input != null:
			var view := input.is_view_toggle_pressed()
			if view and not cell.prev_view:
				cell.fp = not cell.fp
				Sfx.play("tick", -8.0)
			cell.prev_view = view
		player.set_fp(cell.fp)
		if cell.fp:
			# Sniper zoom: the zoom controls step the FOV down; the mouse
			# slows to match and the crosshair grows (see PlayerHud).
			if input != null:
				var fp_zoom := input.zoom_direction()
				if fp_zoom != 0 and cell.prev_zoom == 0:
					cell.fp_zoom = clampi(int(cell.fp_zoom) + fp_zoom, 0, FP_FOVS.size() - 1)
					Sfx.play("tick", -14.0)
				cell.prev_zoom = fp_zoom
			player.fp_zoom = cell.fp_zoom
			# Through the character's eyes: perspective, own body culled.
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = lerpf(cam.fov, FP_FOVS[cell.fp_zoom], 0.25)
			cam.near = 0.05
			cam.cull_mask = ((1 << 20) - 1) & ~player.render_layer_bit()
			var eye: Vector3 = player.position + Vector3(0, Player.EYE_HEIGHT, 0)
			cam.look_at_from_position(eye, eye + player.look_dir(), Vector3.UP)
			_update_viewmodel(cell, player)
			var vm: Node3D = cell.get("vm")
			if vm != null and is_instance_valid(vm):
				# Tuck the gun away while zoomed in (aiming down sights).
				vm.visible = int(cell.get("fp_zoom", 0)) == 0
				# Doom-style bob: the gun sweeps a parabolic arc while running.
				var run := Vector2(player.velocity.x, player.velocity.z).length()
				if not player.on_floor:
					run = 0.0
				cell.bob_amp = lerpf(float(cell.get("bob_amp", 0.0)), clampf(run / 7.0, 0.0, 1.0), minf(1.0, delta * 6.0))
				cell.bob_phase = float(cell.get("bob_phase", 0.0)) + delta * (4.0 + run * 0.9)
				var amp: float = 0.055 * float(cell.bob_amp)
				vm.position = Vector3(cell.get("vm_base", Vector3(0.3, -0.42, -0.72))) \
					+ Vector3(cos(float(cell.bob_phase)) * amp, -absf(sin(float(cell.bob_phase))) * amp * 1.3, 0)
				# Sword rests held UP at guard and sweeps across when swung;
				# other weapons just kick back.
				if str(player.held().kind) == "weapon" and int(player.held().id) == 13:
					var arc := sin(clampf(1.0 - player.swing_time / 0.25, 0.0, 1.0) * PI) \
						if player.swing_time > 0.0 else 0.0
					vm.rotation_degrees = Vector3(35.0 - 130.0 * arc, 6.0 - 40.0 * arc, -25.0 * arc)
				else:
					vm.rotation_degrees = Vector3(-75.0 * (player.swing_time / 0.25), 6, 0)
			continue
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.near = 0.5
		var all_vm := 0
		for i in 4:
			all_vm |= 1 << (10 + i)
		cam.cull_mask = ((1 << 20) - 1) & ~all_vm
		if cell.get("vm") != null and is_instance_valid(cell.vm):
			cell.vm.queue_free()
			cell.vm = null
			cell.vm_sig = ""
		# Poll this player's spin/zoom controls (edge-latched so one press or
		# stick flick = one step).
		if input != null:
			var rot := input.rotate_direction()
			if rot != 0 and cell.prev_rot == 0:
				cell.yaw_index = posmod(cell.yaw_index + rot, 5)
				Sfx.play("tick", -12.0)
			cell.prev_rot = rot
			var zoom := input.zoom_direction()
			if zoom != 0 and cell.prev_zoom == 0:
				cell.zoom_index = clampi(int(cell.zoom_index) - zoom, 0, ZOOM_SIZES.size() - 1)
			cell.prev_zoom = zoom
		# Tween toward the snap targets.
		var target_yaw: float = Player.ISO_ROT + cell.yaw_index * PI / 2.0
		cell.yaw = lerp_angle(cell.yaw, target_yaw, minf(1.0, delta * 5.0))
		cell.size = lerpf(cell.size, ZOOM_SIZES[cell.zoom_index], minf(1.0, delta * 5.0))
		cam.size = cell.size
		player.camera_yaw = cell.yaw
		# Smooth-follow the player from the current orbit direction.
		rig.position = rig.position.lerp(player.position, minf(1.0, delta * 6.0))
		if cell.yaw_index == 4:
			# Top-down map view, north up.
			player.camera_yaw = 0.0
			cam.look_at_from_position(rig.position + Vector3(0.01, CAM_HEIGHT + 20.0, 0.01),
				rig.position, Vector3(0, 0, -1))
			continue
		var yaw: float = cell.yaw
		var offset := Vector3(sin(yaw) * CAM_DISTANCE, CAM_HEIGHT, cos(yaw) * CAM_DISTANCE)
		cam.look_at_from_position(rig.position + offset, rig.position + Vector3(0, 1.0, 0), Vector3.UP)
	# Stream more chunks when someone is zoomed way out.
	if world != null and world.chunks != null:
		var max_size := 0.0
		for cell: Dictionary in _cells:
			if cell.cam != null and not cell.get("fp", false):
				max_size = maxf(max_size, float(cell.size))
		world.chunks.view_radius = clampi(6 + int(max_size / 7.0), 7, 13)
	# The mouse belongs to the keyboard player while they're in first person.
	var want_capture := false
	for cell: Dictionary in _cells:
		var input: InputSlot = Game.local_inputs.get(cell.slot)
		if cell.get("fp", false) and input != null \
				and input.kind == InputSlot.Kind.KEYBOARD_WASD \
				and (cell.hud == null or not cell.hud.is_ui_open()):
			want_capture = true
	var target_mode := Input.MOUSE_MODE_CAPTURED if want_capture else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != target_mode:
		Input.mouse_mode = target_mode


## Video toggle: draw the whole world as wireframes (retro debug look, and
## the ultimate old-computer mode).
func set_wireframe(on: bool) -> void:
	for cell: Dictionary in _cells:
		if cell.cam != null:
			(cell.cam.get_viewport() as SubViewport).debug_draw = \
				Viewport.DEBUG_DRAW_WIREFRAME if on else Viewport.DEBUG_DRAW_DISABLED
