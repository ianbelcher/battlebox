class_name Player
extends Node3D
## One character in the world. Local players run hand-rolled voxel AABB
## physics against the ChunkView data (no physics engine — deterministic,
## cheap, and 16 players cost nothing); remote players glide toward their
## replicated positions. The avatar visual is the shared blob model.

const GRAVITY := 22.0
const JUMP_VELOCITY := 8.6
const WALK_SPEED := 4.6
const SWIM_SPEED := 3.0
const HALF_WIDTH := 0.32
const HEIGHT := 1.25
const SEND_HZ := 12.0
const EDIT_REPEAT := 0.24
## Eye level for first person — near the top of the head, so blocks read
## about waist height like they should.
const EYE_HEIGHT := 1.5
## Default camera yaw; the split-screen rig updates camera_yaw as the view
## spins so "stick up" always moves away from the camera.
const ISO_ROT := PI / 4.0

enum Anim { IDLE, WALK, AIR, SWIM, FLY }

var player_id := ""
var slot := -1
var is_local := false
var input: InputSlot = null
var world: Node = null

var velocity := Vector3.ZERO
var camera_yaw := ISO_ROT
var on_floor := false
var in_water := false
var heading := Vector3(0, 0, -1)
var hotbar_index := 0
var anim: int = Anim.IDLE
var leave_hold := 0.0

## First-person state (driven by the split-screen cell).
var fp_mode := false
var look_yaw := 0.0
var look_pitch := 0.0

## Set while this player's picker is open: input drives the UI, not the body.
var ui_locked := false
## Picked prefab from the picker (-1 = placing single blocks).
var selected_structure := -1

## Flight (double-tap jump toggles; landing exits).
var fly_mode := false
var _prev_jump := false
var _last_jump_ms := -10000
var _launch_latched := false
var _shoot_hold := 0.0
var _last_note_cell := Vector3i(0, -99, 0)
var _warp_cooldown := 0.0

var _avatar: Node3D
var _tag: Label3D
var _highlight: MeshInstance3D
var _send_accum := 0.0
var _edit_cooldown := 0.0
var _cycle_latch := false
var _remote_target := Vector3.ZERO
var _remote_yaw := 0.0
var _bob_time := 0.0
var _spawned := false
var _debug_ticks := 0

func setup(p_id: String, entry: Dictionary, p_local: bool, p_input: InputSlot, p_world: Node) -> void:
	player_id = p_id
	slot = int(entry.slot)
	is_local = p_local
	input = p_input
	world = p_world
	_avatar = AvatarFactory.build_character(entry.get("style", {}))
	add_child(_avatar)
	_tag = Label3D.new()
	_tag.text = str(entry.name)
	_tag.font_size = 64
	_tag.pixel_size = 0.006
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.modulate = Color.WHITE
	_tag.outline_modulate = Color(0.05, 0.05, 0.1, 0.9)
	_tag.outline_size = 16
	_tag.position = Vector3(0, 1.85, 0)
	add_child(_tag)
	if is_local:
		_highlight = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.04, 1.04, 1.04)
		_highlight.mesh = box
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.22)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = false
		box.material = mat
		_highlight.top_level = true
		_highlight.visible = false
		add_child(_highlight)
	_apply_render_layer()

func refresh_from_roster(entry: Dictionary) -> void:
	_tag.text = str(entry.name)
	var style: Dictionary = AvatarFactory.normalize_style(entry.get("style"))
	if str(_avatar.get_meta("style", "")) != str(style):
		var old := _avatar
		_avatar = AvatarFactory.build_character(style)
		_avatar.rotation = old.rotation
		add_child(_avatar)
		old.queue_free()
		_apply_render_layer()

## Local players' visuals live on a per-slot render layer so their own
## first-person camera can cull them (everyone else still sees them).
func render_layer_bit() -> int:
	return 1 << (1 + slot)

func _apply_render_layer() -> void:
	if not is_local:
		return
	for node in _avatar.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = render_layer_bit()
	_tag.layers = render_layer_bit()

func set_fp(enabled: bool) -> void:
	if fp_mode == enabled:
		return
	fp_mode = enabled
	if enabled:
		look_yaw = atan2(-heading.x, -heading.z)
		look_pitch = -0.2
	else:
		heading = Vector3(-sin(look_yaw), 0, -cos(look_yaw))

## Unit vector the player is looking along in first person.
func look_dir() -> Vector3:
	var cp := cos(look_pitch)
	return Vector3(-sin(look_yaw) * cp, sin(look_pitch), -cos(look_yaw) * cp)

## Mouse look for the keyboard player while in first person.
func _input(event: InputEvent) -> void:
	if not (is_local and fp_mode and input != null \
			and input.kind == InputSlot.Kind.KEYBOARD_WASD):
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look_yaw -= event.relative.x * 0.0032
		look_pitch = clampf(look_pitch - event.relative.y * 0.0032, -1.45, 1.45)

func teleport(pos: Vector3) -> void:
	position = pos
	_remote_target = pos
	velocity = Vector3.ZERO
	_spawned = true

func remote_update(pos: Vector3, yaw: float, p_anim: int) -> void:
	_remote_target = pos
	_remote_yaw = yaw
	anim = p_anim
	if not _spawned:
		position = pos
		_spawned = true

func selected_block() -> int:
	return Blocks.HOTBAR[hotbar_index]

func _physics_process(delta: float) -> void:
	if is_local:
		if _spawned and not ui_locked:
			_local_move(delta)
			_local_actions(delta)
		if _spawned:
			_send_state(delta)
	else:
		position = position.lerp(_remote_target, minf(1.0, delta * 10.0))
		rotation.y = lerp_angle(rotation.y, _remote_yaw, minf(1.0, delta * 10.0))
	_animate(delta)

# ------------------------------------------------------------------
# Local physics
# ------------------------------------------------------------------

func _chunks() -> ChunkView:
	return world.chunks

func _solid_at(pos: Vector3) -> bool:
	return Blocks.is_solid(_chunks().get_block(Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))))

## Any solid block overlapping the AABB at a candidate position?
func _collides(at: Vector3) -> bool:
	var min_x := floori(at.x - HALF_WIDTH)
	var max_x := floori(at.x + HALF_WIDTH)
	var min_y := floori(at.y)
	var max_y := floori(at.y + HEIGHT)
	var min_z := floori(at.z - HALF_WIDTH)
	var max_z := floori(at.z + HALF_WIDTH)
	for y in range(min_y, max_y + 1):
		for z in range(min_z, max_z + 1):
			for x in range(min_x, max_x + 1):
				if Blocks.is_solid(_chunks().get_block(Vector3i(x, y, z))):
					return true
	return false

func _local_move(delta: float) -> void:
	# In first person the gamepad right stick steers the look; movement is
	# relative to wherever you're facing (camera_yaw tracks look_yaw).
	if fp_mode:
		var look := input.get_look_vector()
		look_yaw -= look.x * 2.8 * delta
		look_pitch = clampf(look_pitch - look.y * 2.2 * delta, -1.45, 1.45)
		camera_yaw = look_yaw
	var move := input.get_move_vector()
	var dir := Vector3(move.x, 0, move.y).rotated(Vector3.UP, camera_yaw)
	var feet := Vector3i(floori(position.x), floori(position.y + 0.3), floori(position.z))
	in_water = Blocks.is_liquid(_chunks().get_block(feet))

	# If a block appears where we're standing (a place raced our movement, or
	# a friend walled us in), gently pop upward instead of being entombed.
	# Only once our own chunk is streamed — before that everything is
	# phantom-solid on purpose.
	var own_cpos := Vector2i(floori(position.x / 16.0), floori(position.z / 16.0))
	if _chunks().has_chunk(own_cpos) and _collides(position):
		position.y += 5.0 * delta
		velocity = Vector3.ZERO
		return

	# Double-tap jump toggles flight (tap again or land to come down).
	var jump_now := input.is_jump_pressed()
	if jump_now and not _prev_jump:
		var now := Time.get_ticks_msec()
		if now - _last_jump_ms < 320:
			fly_mode = not fly_mode
			if fly_mode:
				velocity.y = 3.0
				Sfx.play("whoosh", -6.0)
		_last_jump_ms = now
	_prev_jump = jump_now

	var speed := SWIM_SPEED if in_water else WALK_SPEED
	if fly_mode:
		speed = 7.5
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	if dir.length_squared() > 0.01:
		heading = dir.normalized()

	if fly_mode:
		var vert := 0.0
		if jump_now:
			vert = 5.5
		elif input.is_descend_pressed():
			vert = -5.5
		velocity.y = lerpf(velocity.y, vert, minf(1.0, delta * 8.0))
	elif in_water:
		velocity.y -= GRAVITY * 0.25 * delta
		velocity.y = maxf(velocity.y, -2.0)
		if jump_now:
			velocity.y = minf(velocity.y + 30.0 * delta, 4.0)
		# Buoyancy beats gravity so kids bob back up to the surface.
		velocity.y = minf(velocity.y + 8.0 * delta, 2.5)
	else:
		velocity.y -= GRAVITY * delta
		if jump_now and on_floor:
			velocity.y = JUMP_VELOCITY
			Sfx.play("jump", -6.0)

	# Axis-separated sweep against the voxel grid.
	var next := position
	var blocked_h := false
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var step: float = velocity.dot(axis) * delta
		if absf(step) < 0.0001:
			continue
		var attempt := next + axis * step
		if _collides(attempt):
			blocked_h = true
		else:
			next = attempt
	# Kid-friendly auto-hop: walking into a single block steps you up it —
	# and swimming into a bank hops you out of the water.
	if blocked_h and (on_floor or in_water) and dir.length_squared() > 0.01:
		var up_attempt := next + Vector3(velocity.x * delta, 1.05, velocity.z * delta)
		if not _collides(up_attempt) and not _collides(next + Vector3(0, 1.05, 0)):
			velocity.y = 7.2
	var vertical := velocity.y * delta
	var v_attempt := next + Vector3(0, vertical, 0)
	if _collides(v_attempt):
		var impact := velocity.y
		if velocity.y < 0.0:
			if not on_floor and velocity.y < -8.0:
				Sfx.play("land", -8.0)
			on_floor = true
			fly_mode = false  # touching down ends flight, like Minecraft
			# Land exactly on top of the block we hit (unless we're inside
			# not-yet-streamed terrain, where we just hold position).
			var landed := next
			landed.y = floorf(v_attempt.y) + 1.001
			if landed.y <= next.y and not _collides(landed):
				next = landed
		velocity.y = 0.0
		# Bouncy blocks throw you back up with most of your fall.
		if impact < -3.0:
			var under := Vector3i(floori(next.x), floori(next.y) - 1, floori(next.z))
			if _chunks().get_block(under) == Blocks.BOUNCY:
				velocity.y = clampf(-impact * 0.85, 6.0, 16.0)
				on_floor = false
				Sfx.play("boing")
	else:
		next = v_attempt
		on_floor = false
	position = next
	if fp_mode:
		heading = Vector3(-sin(look_yaw), 0, -cos(look_yaw))
		rotation.y = look_yaw
	else:
		rotation.y = lerp_angle(rotation.y, atan2(-heading.x, -heading.z), minf(1.0, delta * 12.0))
	_check_floor_machines(delta)

	if fly_mode:
		anim = Anim.FLY
	elif in_water:
		anim = Anim.SWIM
	elif not on_floor:
		anim = Anim.AIR
	elif dir.length_squared() > 0.01:
		anim = Anim.WALK
	else:
		anim = Anim.IDLE

## Blocks that do something when stood on: launch pads, music blocks and
## warp stones (teleport to the nearest other warp stone).
func _check_floor_machines(delta: float) -> void:
	_warp_cooldown = maxf(0.0, _warp_cooldown - delta)
	var below := Vector3i(floori(position.x), floori(position.y) - 1, floori(position.z))
	var block := _chunks().get_block(below)
	if block != Blocks.LAUNCHER:
		_launch_latched = false
	if block != Blocks.NOTE:
		_last_note_cell = NO_TARGET
	if not on_floor:
		return
	match block:
		Blocks.LAUNCHER:
			if not _launch_latched:
				_launch_latched = true
				velocity.y = 17.0
				on_floor = false
				Sfx.play("whoosh")
		Blocks.NOTE:
			if below != _last_note_cell:
				_last_note_cell = below
				var semitone := posmod(below.y * 3 + below.x + below.z, 13)
				Sfx.play("note", -2.0, pow(2.0, semitone / 12.0))
		Blocks.TELEPORT:
			if _warp_cooldown <= 0.0:
				var target: Vector3 = _chunks().nearest_teleporter(Vector3(below))
				if target != Vector3.INF:
					world._burst_particles(below, Blocks.color_of(Blocks.TELEPORT))
					position = target + Vector3(0.5, 1.01, 0.5)
					velocity = Vector3.ZERO
					_warp_cooldown = 3.0
					world._burst_particles(Vector3i(target), Blocks.color_of(Blocks.TELEPORT))
					Sfx.play("warp")

# ------------------------------------------------------------------
# Local actions: dig / place / hotbar / leave
# ------------------------------------------------------------------

func _local_actions(delta: float) -> void:
	_edit_cooldown = maxf(0.0, _edit_cooldown - delta)
	var cycle := input.cycle_direction()
	if cycle != 0 and not _cycle_latch:
		hotbar_index = posmod(hotbar_index + cycle, Blocks.HOTBAR.size())
		Sfx.play("tick", -10.0)
	_cycle_latch = cycle != 0

	var dig_target: Vector3i
	var place_target: Vector3i
	if fp_mode:
		var targets := _find_fp_targets()
		dig_target = targets[0]
		place_target = targets[1]
	else:
		dig_target = _find_dig_target()
		place_target = _find_place_target()
	if _highlight != null:
		var show := dig_target if input.is_dig_pressed() or not input.is_place_pressed() else place_target
		if input.is_place_pressed():
			show = place_target
		if show != Vector3i(0, -99, 0):
			_highlight.visible = true
			_highlight.global_position = Vector3(show) + Vector3(0.5, 0.5, 0.5)
		else:
			_highlight.visible = false

	# Shooting: TAP = fast pellet that pops the one block it hits (and can
	# light Boom Blocks from a distance). HOLD half a second and release =
	# slow bazooka shell that explodes like a lit Boom Block where it lands.
	if input.is_shoot_pressed():
		_shoot_hold += delta
		return
	if _shoot_hold > 0.0:
		var boom := _shoot_hold >= 0.5
		if _edit_cooldown <= 0.0:
			world.orbs.shoot_local(self, boom)
			_edit_cooldown = 1.2 if boom else 0.28
		_shoot_hold = 0.0
		return
	if _edit_cooldown > 0.0:
		return
	# In first person the keyboard player can also mouse-click: left digs,
	# right places (mouse is captured for looking anyway).
	var mouse_ok: bool = fp_mode and input.kind == InputSlot.Kind.KEYBOARD_WASD \
		and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var wants_dig: bool = input.is_dig_pressed() \
		or (mouse_ok and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	var wants_place: bool = input.is_place_pressed() \
		or (mouse_ok and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT))
	if wants_dig:
		# Petting beats digging when a critter is close.
		var critter: int = world.critter_view.nearest_id(position, 1.9)
		if critter >= 0:
			world.sv_pet.rpc_id(1, slot, critter)
			_edit_cooldown = EDIT_REPEAT * 2.0
			return
		if dig_target != Vector3i(0, -99, 0):
			world.send_edit(slot, dig_target, Blocks.AIR)
			_edit_cooldown = EDIT_REPEAT
	elif wants_place:
		if place_target != Vector3i(0, -99, 0):
			if selected_structure >= 0:
				world.sv_structure.rpc_id(1, slot, place_target, selected_structure,
					randi() % 1000)
				_edit_cooldown = 1.0
			else:
				world.send_edit(slot, place_target, selected_block())
				_edit_cooldown = EDIT_REPEAT

func _front_cell(dy: int) -> Vector3i:
	var front := position + heading * 0.95
	return Vector3i(floori(front.x), floori(position.y + 0.3) + dy, floori(front.z))

const NO_TARGET := Vector3i(0, -99, 0)

## First person: march a ray from the eyes along the look direction. The
## first breakable block is the dig target; the last open cell before it is
## the place target — so you can dig straight up out of a hole, or look down
## and build under your feet mid-jump.
func _find_fp_targets() -> Array:
	var chunks := _chunks()
	var eye := position + Vector3(0, EYE_HEIGHT, 0)
	var dir := look_dir()
	var last_open := NO_TARGET
	var last_cell := Vector3i(floori(eye.x), floori(eye.y), floori(eye.z))
	var t := 0.3
	while t < 4.4:
		var sample := eye + dir * t
		var cell := Vector3i(floori(sample.x), floori(sample.y), floori(sample.z))
		if cell != last_cell:
			last_cell = cell
			var block := chunks.get_block(cell)
			if block != Blocks.AIR and not Blocks.is_liquid(block) and not Blocks.is_cross(block):
				if Blocks.is_breakable(block):
					return [cell, last_open]
				return [NO_TARGET, last_open]
			if Blocks.is_cross(block) and Blocks.is_breakable(block):
				return [cell, last_open]
			if not _cell_overlaps_self(cell):
				last_open = cell
		t += 0.12
	return [NO_TARGET, last_open]

func _cell_overlaps_self(cell: Vector3i) -> bool:
	var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	var delta := center - (position + Vector3(0, HEIGHT * 0.5, 0))
	return absf(delta.x) < HALF_WIDTH + 0.5 and absf(delta.z) < HALF_WIDTH + 0.5 \
		and delta.y > -HEIGHT * 0.5 - 0.5 and delta.y < HEIGHT * 0.5 + 0.5

func _find_dig_target() -> Vector3i:
	var chunks := _chunks()
	# The flower you're standing in comes first.
	var own := Vector3i(floori(position.x), floori(position.y + 0.3), floori(position.z))
	if Blocks.is_cross(chunks.get_block(own)):
		return own
	for dy in [0, 1, -1]:
		var cell := _front_cell(dy)
		var block := chunks.get_block(cell)
		if block != Blocks.AIR and not Blocks.is_liquid(block) and Blocks.is_breakable(block):
			return cell
	# Nothing ahead: dig straight down (staircase into the hill).
	var below := own + Vector3i(0, -1, 0)
	var under := chunks.get_block(below)
	if Blocks.is_breakable(under) and not Blocks.is_liquid(under):
		return below
	return NO_TARGET

func _find_place_target() -> Vector3i:
	var chunks := _chunks()
	var candidates := [_front_cell(0), _front_cell(1), _front_cell(-1)]
	for cell: Vector3i in candidates:
		var block := chunks.get_block(cell)
		if block == Blocks.AIR or block == Blocks.TALL_GRASS or Blocks.is_liquid(block):
			# Never place a block inside yourself.
			var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
			var delta := center - (position + Vector3(0, HEIGHT * 0.5, 0))
			if absf(delta.x) < HALF_WIDTH + 0.5 and absf(delta.z) < HALF_WIDTH + 0.5 \
					and delta.y > -HEIGHT * 0.5 - 0.5 and delta.y < HEIGHT * 0.5 + 0.5:
				continue
			return cell
	return NO_TARGET

func _send_state(delta: float) -> void:
	_send_accum += delta
	if _send_accum < 1.0 / SEND_HZ:
		return
	_send_accum = 0.0
	world.send_pos(slot, position, rotation.y, anim)
	if OS.get_environment("WORLD_DEBUG") == "1":
		_debug_ticks += 1
		if _debug_ticks % 24 == 0:
			var feet := Vector3i(floori(position.x), floori(position.y + 0.3), floori(position.z))
			print("DBG %s pos=%v floor=%s water=%s feet_block=%d" % [
				player_id, position, on_floor, in_water, _chunks().get_block(feet)])

# ------------------------------------------------------------------
# Shared animation
# ------------------------------------------------------------------

func _animate(delta: float) -> void:
	if _avatar == null:
		return
	_bob_time += delta
	var swing := 0.0
	var arms_up := 0.0
	match anim:
		Anim.WALK:
			_avatar.position.y = absf(sin(_bob_time * 9.0)) * 0.05
			_avatar.scale = _avatar.scale.lerp(Vector3.ONE, minf(1.0, delta * 8.0))
			swing = sin(_bob_time * 9.0) * 0.7
		Anim.AIR:
			_avatar.position.y = 0.05
			_avatar.scale = _avatar.scale.lerp(Vector3(0.96, 1.06, 0.96), minf(1.0, delta * 6.0))
			arms_up = 2.6
		Anim.SWIM:
			_avatar.position.y = sin(_bob_time * 4.0) * 0.06 - 0.35
			_avatar.scale = _avatar.scale.lerp(Vector3.ONE, minf(1.0, delta * 6.0))
			swing = sin(_bob_time * 5.0) * 0.9
		Anim.FLY:
			# Superhero hover: arms out, legs together, gentle bob.
			_avatar.position.y = 0.15 + sin(_bob_time * 2.6) * 0.05
			_avatar.scale = _avatar.scale.lerp(Vector3.ONE, minf(1.0, delta * 6.0))
			arms_up = 1.35
		_:
			_avatar.position.y = sin(_bob_time * 2.2) * 0.015
			_avatar.scale = _avatar.scale.lerp(Vector3.ONE, minf(1.0, delta * 8.0))
			swing = sin(_bob_time * 2.2) * 0.06
	_swing_limb("LegL", swing, delta)
	_swing_limb("LegR", -swing, delta)
	_swing_limb("ArmL", -swing, delta, arms_up)
	_swing_limb("ArmR", swing, delta, arms_up)

## Limbs ease toward their pose so animation switches never pop. arms_up
## rotates the pivot so hands point skyward (jumping — kids love it).
func _swing_limb(limb: String, angle: float, delta: float, up := 0.0) -> void:
	var pivot: Node3D = _avatar.get_node_or_null(limb)
	if pivot == null:
		return
	var target := angle if up == 0.0 else 0.0
	pivot.rotation.x = lerp_angle(pivot.rotation.x, target, minf(1.0, delta * 10.0))
	pivot.rotation.z = lerp_angle(pivot.rotation.z,
		(up if limb == "ArmR" else -up) if up > 0.0 and limb.begins_with("Arm") else 0.0,
		minf(1.0, delta * 8.0))
