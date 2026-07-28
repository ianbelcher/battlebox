class_name ItemFactory
## Chunky procedural 3D models for weapons and blocks — used by supply
## crates, the hand viewmodel and other players' held items. Built like the
## critters: primitive meshes, no assets.

static func _mat(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.6
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 1.4
	return mat

static func _box(size: Vector3, color: Color, pos: Vector3, emissive := false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = _mat(color, emissive)
	instance.position = pos
	return instance

static func _cyl(top: float, bottom: float, height: float, color: Color, pos: Vector3, rot := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	instance.mesh = mesh
	instance.material_override = _mat(color, emissive)
	instance.position = pos
	instance.rotation_degrees = rot
	return instance

## An item model, roughly 0.5-0.8 units long, origin at the grip.
static func build(kind: String, id: int) -> Node3D:
	var root := Node3D.new()
	if kind == "block":
		var cube := _box(Vector3(0.3, 0.3, 0.3), Blocks.color_of(id), Vector3(0, 0.1, 0))
		root.add_child(cube)
		return root
	if kind == "structure":
		root.add_child(_box(Vector3(0.34, 0.2, 0.3), Structures.spec(id).color, Vector3(0, 0.06, 0)))
		root.add_child(_box(Vector3(0.4, 0.1, 0.36), Structures.spec(id).color.darkened(0.3), Vector3(0, 0.2, 0)))
		return root
	match id:
		0:  # Blaster: compact pistol
			root.add_child(_box(Vector3(0.09, 0.12, 0.3), Color("6c6f78"), Vector3(0, 0.08, -0.1)))
			root.add_child(_box(Vector3(0.07, 0.14, 0.09), Color("4a4c54"), Vector3(0, -0.02, 0.02)))
			root.add_child(_cyl(0.03, 0.03, 0.14, Color("ffe08a"), Vector3(0, 0.08, -0.3), Vector3(90, 0, 0), true))
		1:  # Bazooka: shoulder tube
			root.add_child(_cyl(0.09, 0.09, 0.7, Color("5f6a52"), Vector3(0, 0.1, -0.1), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.12, 0.12, 0.12, Color("ff7a3d"), Vector3(0, 0.1, -0.46), Vector3(90, 0, 0)))
		2:  # Grapple: hook launcher
			root.add_child(_box(Vector3(0.1, 0.12, 0.24), Color("6c6f78"), Vector3(0, 0.06, -0.04)))
			root.add_child(_cyl(0.02, 0.05, 0.16, Color("c9b3ff"), Vector3(0, 0.1, -0.24), Vector3(90, 0, 0)))
		9:  # Napalm: red rocket
			root.add_child(_cyl(0.07, 0.07, 0.5, Color("b33a2a"), Vector3(0, 0.1, -0.1), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.0, 0.07, 0.14, Color("ffd166"), Vector3(0, 0.1, -0.42), Vector3(90, 0, 0), true))
		12:  # Digger: drill
			root.add_child(_box(Vector3(0.12, 0.14, 0.2), Color("8a6a42"), Vector3(0, 0.05, 0.02)))
			root.add_child(_cyl(0.0, 0.09, 0.3, Color("b5975f"), Vector3(0, 0.08, -0.24), Vector3(90, 0, 0)))
		14:  # Flare gun: stubby wide-mouth pistol
			root.add_child(_box(Vector3(0.1, 0.14, 0.1), Color("c94f4f"), Vector3(0, -0.04, 0.1)))
			root.add_child(_cyl(0.09, 0.11, 0.2, Color("ff8ac2"), Vector3(0, 0.05, -0.06), Vector3(90, 0, 0)))
		13:  # Sword
			root.add_child(_box(Vector3(0.05, 0.05, 0.16), Color("6e523a"), Vector3(0, 0, 0.08)))
			root.add_child(_box(Vector3(0.16, 0.04, 0.05), Color("9a9da6"), Vector3(0, 0, -0.02)))
			root.add_child(_box(Vector3(0.06, 0.03, 0.5), Color("dfe4ea"), Vector3(0, 0, -0.3)))
		5:  # Bridge gun: plank thrower
			root.add_child(_box(Vector3(0.1, 0.1, 0.3), Color("8a6a42"), Vector3(0, 0.06, -0.06)))
			root.add_child(_box(Vector3(0.18, 0.04, 0.2), Color("d6c396"), Vector3(0, 0.14, -0.16)))
		6:  # Party popper: striped cone
			root.add_child(_cyl(0.1, 0.02, 0.4, Color("ef9fc8"), Vector3(0, 0.08, -0.12), Vector3(90, 0, 0)))
		7:  # Whirl wand
			root.add_child(_cyl(0.02, 0.02, 0.4, Color("2ea89a"), Vector3(0, 0.08, -0.08), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.14, 0.14, 0.04), Color("3ad4c2"), Vector3(0, 0.08, -0.3), true))
		8:  # Paint bomb: bucket
			root.add_child(_cyl(0.11, 0.09, 0.16, Color("b07df0"), Vector3(0, 0.04, -0.06)))
		11:  # Wings (folded)
			for side in [-1.0, 1.0]:
				var wing := _box(Vector3(0.26, 0.02, 0.14), Color("eceff4"), Vector3(side * 0.16, 0.1, 0))
				wing.rotation_degrees = Vector3(0, 0, side * 20.0)
				root.add_child(wing)
		_:
			root.add_child(_box(Vector3(0.14, 0.14, 0.14), Weapons.spec(id).color, Vector3(0, 0.08, 0), true))
	return root
