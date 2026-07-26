class_name AvatarFactory
## Builds the 3D character model (blob + eyes + hat), the same one everywhere
## a player appears. A style index picks a body color and a hat (21 looks);
## players cycle theirs by clicking their portrait chip in the HUD, and the
## device remembers it (characters.cfg).

const BODY_COLORS: Array[Color] = [
	Color("ff6b6b"), Color("4a9df8"), Color("51c979"), Color("ffd166"),
	Color("b07df0"), Color("3ad4c2"), Color("ff9f68"),
]
const STYLE_COUNT := 21

static func body_color(style: int) -> Color:
	return BODY_COLORS[posmod(style, BODY_COLORS.size())]

static func material(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 0.8
	return mat

static func build_blob(style: int) -> Node3D:
	var root := Node3D.new()
	var color := body_color(style)
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.42
	sphere.height = 0.84
	body.mesh = sphere
	body.name = "Body"
	body.position = Vector3(0, 0.42, 0)
	body.material_override = material(color)
	root.add_child(body)
	# Big cartoon eyes with pupils, on the facing side (-Z forward).
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.13
		eye_mesh.height = 0.26
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.18, 0.58, -0.32)
		eye.material_override = material(Color.WHITE)
		root.add_child(eye)
		var pupil := MeshInstance3D.new()
		var pupil_mesh := SphereMesh.new()
		pupil_mesh.radius = 0.06
		pupil_mesh.height = 0.12
		pupil.mesh = pupil_mesh
		pupil.position = Vector3(side * 0.18, 0.58, -0.43)
		pupil.material_override = material(Color(0.08, 0.08, 0.12))
		root.add_child(pupil)
	attach_hat(root, style)
	root.set_meta("style", style)
	return root

## Every style gets *something* on its head; hats scale the character.
static func attach_hat(root: Node3D, style: int) -> void:
	var old := root.get_node_or_null("Hat")
	if old != null:
		old.queue_free()
	var hat := MeshInstance3D.new()
	hat.name = "Hat"
	var gold := Color("ffd166")
	var accent := body_color(style + 3).lightened(0.2)
	match posmod(style / BODY_COLORS.size() + style, 7):
		0:  # Bare head — a tuft.
			var tuft := SphereMesh.new()
			tuft.radius = 0.08
			tuft.height = 0.2
			hat.mesh = tuft
			hat.position = Vector3(0, 0.9, 0)
			hat.material_override = material(body_color(style).darkened(0.25))
		1:  # Party cone.
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = 0.2
			cone.height = 0.42
			hat.mesh = cone
			hat.position = Vector3(0, 1.02, 0)
			hat.material_override = material(gold)
		2:  # Crown.
			var crown := CylinderMesh.new()
			crown.top_radius = 0.24
			crown.bottom_radius = 0.19
			crown.height = 0.17
			hat.mesh = crown
			hat.position = Vector3(0, 0.9, 0)
			hat.material_override = material(gold)
		3:  # Cap.
			var cap := SphereMesh.new()
			cap.radius = 0.27
			cap.height = 0.28
			hat.mesh = cap
			hat.position = Vector3(0, 0.84, 0)
			hat.material_override = material(accent)
		4:  # Bow.
			var bow := SphereMesh.new()
			bow.radius = 0.14
			bow.height = 0.28
			hat.mesh = bow
			hat.position = Vector3(0.14, 0.88, 0)
			hat.material_override = material(Color("ff9ff3"))
		5:  # Bobble antenna.
			var ball := SphereMesh.new()
			ball.radius = 0.09
			ball.height = 0.18
			hat.mesh = ball
			hat.position = Vector3(0, 1.12, 0)
			hat.material_override = material(Color("1dd1a1"), true)
		6:  # Halo disc.
			var disc := CylinderMesh.new()
			disc.top_radius = 0.28
			disc.bottom_radius = 0.28
			disc.height = 0.06
			hat.mesh = disc
			hat.position = Vector3(0, 0.88, 0)
			hat.material_override = material(Color("f5f6fa"))
	root.add_child(hat)
