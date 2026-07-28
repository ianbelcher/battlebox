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
		var gem := MeshInstance3D.new()
		var gem_mesh := SphereMesh.new()
		gem_mesh.radius = 0.22
		gem_mesh.height = 0.44
		gem.mesh = gem_mesh
		var gem_mat := StandardMaterial3D.new()
		var color: Color = Weapons.spec(weapon).color
		gem_mat.albedo_color = color
		gem_mat.emission_enabled = true
		gem_mat.emission = color
		gem_mat.emission_energy_multiplier = 2.2
		gem.material_override = gem_mat
		gem.position = Vector3(0, 1.25, 0)
		node.add_child(gem)
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 1.6
		light.omni_range = 5.0
		light.shadow_enabled = false
		light.position = Vector3(0, 1.2, 0)
		node.add_child(light)
		var tag := Label3D.new()
		tag.text = str(Weapons.spec(weapon).name)
		tag.font_size = 52
		tag.pixel_size = 0.008
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.modulate = color
		tag.outline_size = 12
		tag.position = Vector3(0, 1.9, 0)
		node.add_child(tag)
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
