class_name AvatarFactory
## Builds the character model: a chunky, friendly mini-figure (think toy
## figure) with head, torso, swinging arms and legs. A style dictionary
## {body, shirt, hat} picks the skin tone, shirt color and hat; each part is
## cycled from the HUD swatches and remembered per device.
##
## Limb pivots are named LegL/LegR/ArmL/ArmR so the player animation can
## swing them while walking.

const SKIN_COLORS: Array[Color] = [
	Color("f5cfa8"), Color("e0ac7e"), Color("a9714b"), Color("6f4a2f"),
	Color("9fe2c5"), Color("c9a9f5"), Color("ffd97a"),
]
const SHIRT_COLORS: Array[Color] = [
	Color("ff6b6b"), Color("4a9df8"), Color("51c979"), Color("ffd166"),
	Color("b07df0"), Color("3ad4c2"), Color("ff9f68"),
]
const HAT_COUNT := 7

static func random_style() -> Dictionary:
	return {
		"body": randi() % SKIN_COLORS.size(),
		"shirt": randi() % SHIRT_COLORS.size(),
		"hat": randi() % HAT_COUNT,
	}

static func normalize_style(style) -> Dictionary:
	if not (style is Dictionary):
		return random_style()
	return {
		"body": posmod(int(style.get("body", 0)), SKIN_COLORS.size()),
		"shirt": posmod(int(style.get("shirt", 0)), SHIRT_COLORS.size()),
		"hat": posmod(int(style.get("hat", 0)), HAT_COUNT),
	}

static func skin_color(style: Dictionary) -> Color:
	return SKIN_COLORS[posmod(int(style.get("body", 0)), SKIN_COLORS.size())]

static func shirt_color(style: Dictionary) -> Color:
	return SHIRT_COLORS[posmod(int(style.get("shirt", 0)), SHIRT_COLORS.size())]

static func material(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	return mat

static func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material(color)
	return instance

static func _sphere(radius: float, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	instance.mesh = mesh
	instance.material_override = material(color)
	return instance

## The character faces -Z. Total height ~1.5 (fits the 1.25 collision box
## with the head poking into the generous 2-block clearance).
static func build_character(style: Dictionary) -> Node3D:
	style = normalize_style(style)
	var skin := skin_color(style)
	var shirt := shirt_color(style)
	var pants := shirt.darkened(0.45)
	var root := Node3D.new()

	for side in [-1.0, 1.0]:
		# Legs: pivot at the hip, mesh hanging below.
		var leg_pivot := Node3D.new()
		leg_pivot.name = "LegL" if side < 0 else "LegR"
		leg_pivot.position = Vector3(side * 0.12, 0.42, 0)
		var leg := _box(Vector3(0.17, 0.42, 0.22), pants)
		leg.position = Vector3(0, -0.21, 0)
		leg_pivot.add_child(leg)
		root.add_child(leg_pivot)
		# Arms: pivot at the shoulder, skin hands at the ends.
		var arm_pivot := Node3D.new()
		arm_pivot.name = "ArmL" if side < 0 else "ArmR"
		arm_pivot.position = Vector3(side * 0.33, 0.88, 0)
		var arm := _box(Vector3(0.15, 0.42, 0.18), shirt)
		arm.position = Vector3(0, -0.16, 0)
		arm_pivot.add_child(arm)
		var hand := _sphere(0.075, skin)
		hand.position = Vector3(0, -0.4, 0)
		arm_pivot.add_child(hand)
		root.add_child(arm_pivot)

	var torso := _box(Vector3(0.5, 0.5, 0.3), shirt)
	torso.position = Vector3(0, 0.67, 0)
	root.add_child(torso)

	var head := _box(Vector3(0.42, 0.4, 0.42), skin)
	head.name = "Head"
	head.position = Vector3(0, 1.13, 0)
	root.add_child(head)
	for side in [-1.0, 1.0]:
		var eye := _sphere(0.055, Color.WHITE)
		eye.position = Vector3(side * 0.1, 1.17, -0.21)
		root.add_child(eye)
		var pupil := _sphere(0.028, Color(0.08, 0.08, 0.12))
		pupil.position = Vector3(side * 0.1, 1.17, -0.245)
		root.add_child(pupil)
	var mouth := _box(Vector3(0.12, 0.03, 0.02), Color(0.45, 0.2, 0.18))
	mouth.position = Vector3(0, 1.03, -0.215)
	root.add_child(mouth)

	attach_hat(root, style)
	root.set_meta("style", str(style))
	return root

## Every hat sits on the head top (y ~1.33).
static func attach_hat(root: Node3D, style: Dictionary) -> void:
	var old := root.get_node_or_null("Hat")
	if old != null:
		old.queue_free()
	var hat := MeshInstance3D.new()
	hat.name = "Hat"
	var gold := Color("ffd166")
	var accent := shirt_color(style).lightened(0.2)
	match posmod(int(style.get("hat", 0)), HAT_COUNT):
		0:  # Hair tuft.
			var tuft := SphereMesh.new()
			tuft.radius = 0.1
			tuft.height = 0.16
			hat.mesh = tuft
			hat.position = Vector3(0, 1.36, 0)
			hat.material_override = material(skin_color(style).darkened(0.45))
		1:  # Party cone.
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = 0.18
			cone.height = 0.4
			hat.mesh = cone
			hat.position = Vector3(0, 1.5, 0)
			hat.material_override = material(gold)
		2:  # Crown.
			var crown := CylinderMesh.new()
			crown.top_radius = 0.22
			crown.bottom_radius = 0.18
			crown.height = 0.16
			hat.mesh = crown
			hat.position = Vector3(0, 1.4, 0)
			hat.material_override = material(gold)
		3:  # Cap.
			var cap := SphereMesh.new()
			cap.radius = 0.26
			cap.height = 0.24
			hat.mesh = cap
			hat.position = Vector3(0, 1.34, 0)
			hat.material_override = material(accent)
		4:  # Bow.
			var bow := SphereMesh.new()
			bow.radius = 0.12
			bow.height = 0.24
			hat.mesh = bow
			hat.position = Vector3(0.14, 1.36, 0)
			hat.material_override = material(Color("ff9ff3"))
		5:  # Bobble antenna.
			var ball := SphereMesh.new()
			ball.radius = 0.08
			ball.height = 0.16
			hat.mesh = ball
			hat.position = Vector3(0, 1.56, 0)
			hat.material_override = material(Color("1dd1a1"), true)
		6:  # Halo disc.
			var disc := CylinderMesh.new()
			disc.top_radius = 0.26
			disc.bottom_radius = 0.26
			disc.height = 0.05
			hat.mesh = disc
			hat.position = Vector3(0, 1.42, 0)
			hat.material_override = material(Color("f5f6fa"))
	root.add_child(hat)
