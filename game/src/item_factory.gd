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
		# Hold the actual thing, not an anonymous colored cube: plants are
		# little crossed sprigs, torches glow, slabs are half-height,
		# stairs are stepped, fences are posts — full blocks keep their
		# distinct top color like the world mesh does.
		var color := Blocks.color_of(id)
		var shape := Blocks.shape_of(id)
		if id == Blocks.TORCH:
			root.add_child(_box(Vector3(0.05, 0.26, 0.05), Color("8a6242"), Vector3(0, 0.1, 0)))
			root.add_child(_box(Vector3(0.07, 0.07, 0.07), Color("ffd166"), Vector3(0, 0.27, 0), true))
			return root
		if Blocks.is_cross(id):
			for angle in [45.0, -45.0]:
				var sprig := _box(Vector3(0.24, 0.3, 0.02), color, Vector3(0, 0.12, 0))
				sprig.rotation_degrees.y = angle
				root.add_child(sprig)
			return root
		match shape:
			"slab":
				root.add_child(_box(Vector3(0.3, 0.15, 0.3), color, Vector3(0, 0.05, 0)))
			"carpet":
				root.add_child(_box(Vector3(0.3, 0.05, 0.3), color, Vector3(0, 0.02, 0)))
			"stairs":
				root.add_child(_box(Vector3(0.3, 0.15, 0.3), color, Vector3(0, 0.04, 0)))
				root.add_child(_box(Vector3(0.3, 0.15, 0.15), color.lightened(0.06), Vector3(0, 0.19, 0.075)))
			"fence":
				root.add_child(_box(Vector3(0.06, 0.32, 0.06), color, Vector3(0, 0.12, 0)))
				root.add_child(_box(Vector3(0.3, 0.05, 0.04), color.lightened(0.1), Vector3(0, 0.16, 0)))
				root.add_child(_box(Vector3(0.3, 0.05, 0.04), color.lightened(0.1), Vector3(0, 0.04, 0)))
			"wall":
				root.add_child(_box(Vector3(0.14, 0.3, 0.14), color, Vector3(0, 0.11, 0)))
				root.add_child(_box(Vector3(0.3, 0.24, 0.1), color.darkened(0.1), Vector3(0, 0.08, 0)))
			"pane":
				root.add_child(_box(Vector3(0.3, 0.3, 0.03), color.lightened(0.15), Vector3(0, 0.12, 0)))
			_:
				var glow := Blocks.emit_of(id) > 0.6
				root.add_child(_box(Vector3(0.3, 0.3, 0.3), color, Vector3(0, 0.1, 0), glow))
				var top := Blocks.top_color_of(id)
				if top != color:
					root.add_child(_box(Vector3(0.31, 0.02, 0.31), top, Vector3(0, 0.26, 0)))
		return root
	if kind == "dragon_head":
		# The neck-and-head you see while riding: gray-purple, crest, eyes.
		var hide := Color("8d7ca8")
		root.add_child(_box(Vector3(0.34, 0.3, 0.7), hide, Vector3(0, 0.05, -0.4)))
		root.add_child(_box(Vector3(0.42, 0.34, 0.5), hide.lightened(0.08), Vector3(0, 0.12, -0.95)))
		root.add_child(_box(Vector3(0.3, 0.14, 0.44), hide.darkened(0.12), Vector3(0, -0.06, -1.1)))
		root.add_child(_cyl(0.0, 0.1, 0.4, hide.darkened(0.15), Vector3(0, 0.36, -0.72), Vector3(-135, 0, 0)))
		for side in [-1.0, 1.0]:
			root.add_child(_box(Vector3(0.07, 0.07, 0.07), Color("ffd166"), Vector3(side * 0.16, 0.2, -1.12), true))
		return root
	if kind == "structure":
		root.add_child(_box(Vector3(0.34, 0.2, 0.3), Structures.spec(id).color, Vector3(0, 0.06, 0)))
		root.add_child(_box(Vector3(0.4, 0.1, 0.36), Structures.spec(id).color.darkened(0.3), Vector3(0, 0.2, 0)))
		return root
	match id:
		0:  # Blaster: compact pistol with shroud + bead sight
			root.add_child(_box(Vector3(0.09, 0.12, 0.3), Color("6c6f78"), Vector3(0, 0.08, -0.1)))
			root.add_child(_box(Vector3(0.11, 0.06, 0.16), Color("52555e"), Vector3(0, 0.1, -0.18)))
			root.add_child(_box(Vector3(0.07, 0.14, 0.09), Color("4a4c54"), Vector3(0, -0.02, 0.02)))
			root.add_child(_box(Vector3(0.02, 0.03, 0.02), Color("ffe08a"), Vector3(0, 0.16, -0.2), true))
			root.add_child(_cyl(0.035, 0.035, 0.16, Color("ffe08a"), Vector3(0, 0.08, -0.31), Vector3(90, 0, 0), true))
		1:  # Bazooka: shoulder tube with grip, exhaust bell and sight
			root.add_child(_cyl(0.09, 0.09, 0.7, Color("5f6a52"), Vector3(0, 0.1, -0.1), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.12, 0.12, 0.12, Color("ff7a3d"), Vector3(0, 0.1, -0.46), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.09, 0.13, 0.12, Color("47503d"), Vector3(0, 0.1, 0.3), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.07, 0.14, 0.08), Color("35363c"), Vector3(0, -0.03, 0.0)))
			root.add_child(_box(Vector3(0.03, 0.08, 0.03), Color("8a9478"), Vector3(0, 0.22, -0.18)))
		2:  # Grapple: launcher with a three-prong hook and rope drum
			root.add_child(_box(Vector3(0.1, 0.12, 0.24), Color("6c6f78"), Vector3(0, 0.06, -0.04)))
			root.add_child(_cyl(0.02, 0.05, 0.16, Color("c9b3ff"), Vector3(0, 0.1, -0.24), Vector3(90, 0, 0)))
			for hook_a in [0.0, 120.0, 240.0]:
				var prong := _box(Vector3(0.025, 0.09, 0.025), Color("d8cfff"),
					Vector3(0, 0.1, -0.34))
				prong.rotation_degrees = Vector3(25, 0, hook_a)
				root.add_child(prong)
			root.add_child(_cyl(0.06, 0.06, 0.08, Color("4a4c54"), Vector3(0, 0.14, 0.06), Vector3(0, 0, 90)))
		9:  # Napalm: red rocket with tail fins
			root.add_child(_cyl(0.07, 0.07, 0.5, Color("b33a2a"), Vector3(0, 0.1, -0.1), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.0, 0.07, 0.14, Color("ffd166"), Vector3(0, 0.1, -0.42), Vector3(90, 0, 0), true))
			for fin_a in [0.0, 90.0, 180.0, 270.0]:
				var fin := _box(Vector3(0.02, 0.1, 0.12), Color("7d251a"), Vector3(0, 0.1, 0.12))
				fin.rotation_degrees = Vector3(0, 0, fin_a + 45.0)
				root.add_child(fin)
		12:  # Digger: threaded drill cone + grip
			root.add_child(_box(Vector3(0.12, 0.14, 0.2), Color("8a6a42"), Vector3(0, 0.05, 0.02)))
			root.add_child(_cyl(0.0, 0.09, 0.3, Color("b5975f"), Vector3(0, 0.08, -0.24), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.065, 0.065, 0.03, Color("7d6540"), Vector3(0, 0.08, -0.2), Vector3(90, 0, 0)))
			root.add_child(_cyl(0.045, 0.045, 0.03, Color("7d6540"), Vector3(0, 0.08, -0.28), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.06, 0.12, 0.07), Color("4a4c54"), Vector3(0, -0.04, 0.08)))
		16:  # X-Ray Goggles: teal visor
			root.add_child(_box(Vector3(0.34, 0.12, 0.08), Color("7de8e0"), Vector3(0, 0.04, 0)))
			root.add_child(_box(Vector3(0.38, 0.03, 0.03), Color("35363c"), Vector3(0, 0.12, 0)))
		15:  # Big Shooter: genuinely double-barreled, ringed muzzles, grip
			for bs_side in [-1.0, 1.0]:
				root.add_child(_cyl(0.085, 0.085, 0.52, Color("d63d2e"),
					Vector3(bs_side * 0.09, 0.04, -0.02), Vector3(90, 0, 0)))
				root.add_child(_cyl(0.105, 0.105, 0.1, Color("8a2a20"),
					Vector3(bs_side * 0.09, 0.04, -0.26), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.26, 0.1, 0.16), Color("5c1d16"), Vector3(0, 0.04, 0.16)))
			root.add_child(_box(Vector3(0.1, 0.18, 0.12), Color("35363c"), Vector3(0, -0.1, 0.16)))
			root.add_child(_box(Vector3(0.05, 0.05, 0.05), Color("ffd166"), Vector3(0, 0.13, 0.1), true))
		14:  # Flare gun: stubby wide-mouth pistol
			root.add_child(_box(Vector3(0.1, 0.14, 0.1), Color("c94f4f"), Vector3(0, -0.04, 0.1)))
			root.add_child(_cyl(0.09, 0.11, 0.2, Color("ff8ac2"), Vector3(0, 0.05, -0.06), Vector3(90, 0, 0)))
		13:  # Sword: long bright blade with a ridge, gold guard, pommel
			root.add_child(_box(Vector3(0.055, 0.055, 0.2), Color("4a3524"), Vector3(0, 0, 0.11)))
			root.add_child(_cyl(0.05, 0.05, 0.05, Color("d9a832"), Vector3(0, 0, 0.23), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.26, 0.06, 0.06), Color("d9a832"), Vector3(0, 0, -0.01)))
			root.add_child(_box(Vector3(0.11, 0.035, 0.62), Color("dfe6f0"), Vector3(0, 0, -0.36)))
			root.add_child(_box(Vector3(0.035, 0.045, 0.58), Color("f7fafd"), Vector3(0, 0, -0.34)))
			root.add_child(_box(Vector3(0.065, 0.037, 0.12), Color("f4f8fc"), Vector3(0, 0, -0.72)))
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
		3:  # Freeze ray: icy emitter with a glowing crystal muzzle
			root.add_child(_box(Vector3(0.09, 0.12, 0.26), Color("5f7d8a"), Vector3(0, 0.05, -0.02)))
			root.add_child(_cyl(0.06, 0.09, 0.12, Color("aef7f0"), Vector3(0, 0.08, -0.22), Vector3(90, 0, 0), true))
			root.add_child(_box(Vector3(0.07, 0.12, 0.08), Color("44525c"), Vector3(0, -0.04, 0.08)))
		4:  # Block sucker: vacuum bell on a green rig
			root.add_child(_box(Vector3(0.1, 0.12, 0.22), Color("4c6a44"), Vector3(0, 0.05, 0.02)))
			root.add_child(_cyl(0.13, 0.05, 0.18, Color("62a851"), Vector3(0, 0.07, -0.2), Vector3(90, 0, 0)))
		10:  # Grump whistle: purple pipe with a mouthpiece
			root.add_child(_cyl(0.045, 0.045, 0.2, Color("8a5fd0"), Vector3(0, 0.05, -0.05), Vector3(90, 0, 0)))
			root.add_child(_box(Vector3(0.1, 0.1, 0.1), Color("6a44a8"), Vector3(0, 0.03, 0.08)))
		11:  # Wings (folded)
			for side in [-1.0, 1.0]:
				var wing := _box(Vector3(0.26, 0.02, 0.14), Color("eceff4"), Vector3(side * 0.16, 0.1, 0))
				wing.rotation_degrees = Vector3(0, 0, side * 20.0)
				root.add_child(wing)
		_:
			root.add_child(_box(Vector3(0.14, 0.14, 0.14), Weapons.spec(id).color, Vector3(0, 0.08, 0), true))
	return root
