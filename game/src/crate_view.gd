class_name CrateView
extends Node3D
## Supply crates: spinning wooden boxes with a weapon-colored glow. Walk
## into one and that weapon drops into your hotbar — scavenger style.

var _nodes: Dictionary = {}   # id -> {node, weapon}

func update_crates(payload: Array) -> void:
	var seen := {}
	for entry in payload:
		if not (entry is Array) or entry.size() < 3:
			continue
		var id := int(entry[0])
		seen[id] = true
		if _nodes.has(id):
			continue
		var weapon := int(entry[1])
		var pos: Vector3 = entry[2]
		var node := Node3D.new()
		node.position = pos
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.7, 0.7, 0.7)
		box.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("8a6a42")
		box.material_override = mat
		box.position = Vector3(0, 0.5, 0)
		node.add_child(box)
		var color: Color = Weapons.spec(weapon).color
		var gem := ItemFactory.build("weapon", weapon)
		gem.scale = Vector3(1.6, 1.6, 1.6)
		gem.position = Vector3(0, 1.25, 0)
		node.add_child(gem)
		# A real light AND an emissive beam, on purpose.
		#
		# The light alone used to switch itself off and on again as you
		# moved: the renderer only lets so many omni lights affect one
		# object, so with a field full of crates they fought each other
		# for the slots and popped in and out. Now the light fades out
		# smoothly with distance instead of popping (so only the few
		# nearby ones ever compete), and the thing you actually spot a
		# crate BY is the beam, which is emissive geometry and cannot
		# flicker at all — it does not depend on a light slot, or even on
		# dynamic lights being switched on in the video settings.
		var light := OmniLight3D.new()
		light.light_color = color.lightened(0.35)
		light.light_energy = 1.6
		light.omni_range = 5.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 18.0
		light.distance_fade_length = 10.0
		light.position = Vector3(0, 1.2, 0)
		node.add_child(light)
		var beam := MeshInstance3D.new()
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(0.16, 6.0, 0.16)
		beam.mesh = beam_mesh
		var beam_mat := StandardMaterial3D.new()
		beam_mat.albedo_color = Color(color.r, color.g, color.b, 0.42)
		beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam_mat.emission_enabled = true
		beam_mat.emission = color
		beam_mat.emission_energy_multiplier = 2.4
		beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		beam.material_override = beam_mat
		beam.position = Vector3(0, 3.4, 0)
		node.add_child(beam)
		for part in node.find_children("*", "GeometryInstance3D", true, false):
			(part as GeometryInstance3D).visibility_range_end = 140.0
		# ...except the beam, which is the long-range marker.
		beam.visibility_range_end = 0.0
		add_child(node)
		_nodes[id] = {"node": node, "weapon": weapon}
	for id: int in _nodes.keys().duplicate():
		if not seen.has(id):
			_nodes[id].node.queue_free()
			_nodes.erase(id)

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _nodes.values():
		var node: Node3D = entry.node
		node.rotation.y += delta * 1.2
		node.get_child(1).position.y = 1.25 + sin(t * 2.0) * 0.12
