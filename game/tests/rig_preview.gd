extends Node3D
## Contact sheet for the rigged Little People (see tools/rig_people.py).
## Lines up characters, poses their limbs mid-stride and screenshots them,
## so a rig change can be eyeballed without launching the whole game.
##
##   godot --path <game> --headless=false res://tests/rig_preview.tscn
##   WORLD_RIG_SHOT=/tmp/rig.png  WORLD_RIG_FROM=0  WORLD_RIG_ROT=0

const COLUMNS := 6
const SPACING := 1.1
const ROW_HEIGHT := 2.2

var _shot := ""
var _frames := 0

func _ready() -> void:
	_shot = OS.get_environment("WORLD_RIG_SHOT")
	var first := int(OS.get_environment("WORLD_RIG_FROM"))
	var yaw := float(OS.get_environment("WORLD_RIG_ROT"))
	# WORLD_RIG_WHO=a,b,p0,p1 lines up an explicit cast (handy for checking
	# the Little People end up the same size as the Kenney kids).
	var who_list: Array = []
	if OS.get_environment("WORLD_RIG_WHO") != "":
		who_list = Array(OS.get_environment("WORLD_RIG_WHO").split(","))
	else:
		var count := int(OS.get_environment("WORLD_RIG_COUNT")) if \
			OS.get_environment("WORLD_RIG_COUNT") != "" else 12
		for i in count:
			who_list.append("p%d" % (first + i))
	var rows := int(ceil(float(who_list.size()) / COLUMNS))

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42, -35, 0)
	light.light_energy = 0.9
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.18, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.environment.ambient_light_energy = 0.35
	add_child(env)

	for i in who_list.size():
		var who := str(who_list[i])
		var avatar := AvatarFactory.build_character({"who": who})
		avatar.position = Vector3(
			(i % COLUMNS) * SPACING - (COLUMNS - 1) * SPACING * 0.5,
			-float(i / COLUMNS) * ROW_HEIGHT, 0)
		avatar.rotation.y = deg_to_rad(yaw)
		# Mid-stride: opposite arms and legs swung, so a broken pivot or a
		# limb attached to the wrong side is obvious at a glance.
		_pose(avatar, "LegL", 0.7)
		_pose(avatar, "LegR", -0.7)
		_pose(avatar, "ArmL", -0.7)
		_pose(avatar, "ArmR", 0.7)
		add_child(avatar)
		var label := Label3D.new()
		label.text = who
		label.font_size = 48
		label.pixel_size = 0.0025
		label.position = avatar.position + Vector3(0, -0.18, 0.4)
		add_child(label)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.size = COLUMNS * SPACING + 0.4
	cam.position = Vector3(0, 0.85 - (rows - 1) * ROW_HEIGHT * 0.5, 8)
	add_child(cam)
	cam.current = true

func _pose(avatar: Node3D, limb: String, angle: float) -> void:
	var pivot: Node3D = avatar.get_node_or_null(limb)
	if pivot != null:
		pivot.rotation.x = angle

func _process(_delta: float) -> void:
	if _shot.is_empty():
		return
	_frames += 1
	if _frames < 4:
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot)
	get_tree().quit()
