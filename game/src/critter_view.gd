class_name CritterView
extends Node3D
## Client-side critters. The server simulates coarse positions at ~3 Hz;
## here they glide, bob, flap and face their travel — and get petted.

enum { SHEEP = 0, BUNNY = 1, BUTTERFLY = 2, FIREFLY = 3, DUCK = 4,
	CHICKEN = 5, CRAB = 6, FROG = 7, DEER = 8, PENGUIN = 9 }

## Animal voices: clip + pitch range; played at random intervals, faded by
## distance, so the world chatters without ever sounding like a metronome.
const CALLS := {
	SHEEP: ["baa", 0.9, 1.15],
	DUCK: ["quack", 0.9, 1.1],
	CHICKEN: ["cluck", 0.9, 1.3],
	FROG: ["ribbit", 0.85, 1.2],
	PENGUIN: ["quack", 1.4, 1.7],
	DEER: ["cluck", 0.5, 0.6],
}

var _nodes: Dictionary = {}    # id -> {node: Node3D, target: Vector3, kind: int, phase: float}

func update_critters(payload: Array) -> void:
	var seen := {}
	for entry in payload:
		if not (entry is Array) or entry.size() < 3:
			continue
		var id := int(entry[0])
		var kind := int(entry[1])
		var pos: Vector3 = entry[2]
		seen[id] = true
		if _nodes.has(id):
			_nodes[id].target = pos
		else:
			var node := _build(kind)
			node.position = pos
			add_child(node)
			_nodes[id] = {"node": node, "target": pos, "kind": kind,
				"phase": randf() * TAU,
				"next_call": Time.get_ticks_msec() / 1000.0 + randf_range(2.0, 14.0)}
	for id: int in _nodes.keys().duplicate():
		if not seen.has(id):
			var node: Node3D = _nodes[id].node
			node.queue_free()
			_nodes.erase(id)

func nearest_id(pos: Vector3, radius: float) -> int:
	var best := -1
	var best_dist := radius
	for id: int in _nodes.keys():
		var node: Node3D = _nodes[id].node
		var dist: float = node.position.distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best = id
	return best

func pet(id: int) -> void:
	if not _nodes.has(id):
		return
	var node: Node3D = _nodes[id].node
	# Happy hop...
	var tween := create_tween()
	tween.tween_property(node, "position:y", node.position.y + 0.5, 0.15) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "position:y", node.position.y, 0.2) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	# ...plus a burst of hearts.
	var hearts := CPUParticles3D.new()
	hearts.position = node.position + Vector3(0, 0.9, 0)
	hearts.amount = 7
	hearts.lifetime = 0.9
	hearts.one_shot = true
	hearts.explosiveness = 1.0
	hearts.direction = Vector3.UP
	hearts.spread = 45.0
	hearts.initial_velocity_min = 1.2
	hearts.initial_velocity_max = 2.2
	hearts.gravity = Vector3(0, -1.5, 0)
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ff6b9d")
	mat.emission_enabled = true
	mat.emission = Color("ff6b9d")
	mesh.material = mat
	hearts.mesh = mesh
	add_child(hearts)
	hearts.emitting = true
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(hearts):
			hearts.queue_free())

func _nearest_local_player_dist(pos: Vector3) -> float:
	var world := get_parent()
	if world == null or world.players == null:
		return 1e9
	var best := 1e9
	for child in world.players.get_children():
		if child is Player and child.is_local:
			best = minf(best, child.position.distance_to(pos))
	return best

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _nodes.values():
		# Random animal calls, quieter with distance.
		if CALLS.has(entry.kind) and t > float(entry.get("next_call", 0.0)):
			entry.next_call = t + randf_range(7.0, 18.0)
			var node_pos: Vector3 = (entry.node as Node3D).position
			var dist := _nearest_local_player_dist(node_pos)
			if dist < 24.0:
				var call: Array = CALLS[entry.kind]
				Sfx.play(call[0], -4.0 - dist * 0.9, randf_range(call[1], call[2]))
	for entry: Dictionary in _nodes.values():
		var node: Node3D = entry.node
		var target: Vector3 = entry.target
		var kind: int = entry.kind
		var phase: float = entry.phase
		var to_target := target - node.position
		node.position = node.position.lerp(target, minf(1.0, delta * 4.0))
		if Vector2(to_target.x, to_target.z).length() > 0.15:
			node.rotation.y = lerp_angle(node.rotation.y,
				atan2(-to_target.x, -to_target.z), minf(1.0, delta * 6.0))
		var visual: Node3D = node.get_child(0) if node.get_child_count() > 0 else null
		if visual == null:
			continue
		match kind:
			BUTTERFLY:
				visual.position.y = 0.8 + sin(t * 2.0 + phase) * 0.25
				for wing in visual.get_children():
					if wing.name.begins_with("Wing"):
						var side := 1.0 if wing.name == "WingL" else -1.0
						wing.rotation.z = side * (0.5 + sin(t * 14.0 + phase) * 0.55)
			FIREFLY:
				visual.position.y = 0.7 + sin(t * 1.6 + phase) * 0.3
				visual.position.x = sin(t * 0.9 + phase) * 0.2
			FROG:
				# Hops: mostly grounded, periodic boings.
				visual.position.y = maxf(0.0, sin(t * 3.2 + phase)) * 0.35
			CRAB:
				visual.position.y = 0.0
				visual.rotation.y = PI / 2.0  # scuttles sideways
			DUCK:
				visual.position.y = sin(t * 2.4 + phase) * 0.05
			_:
				if Vector2(to_target.x, to_target.z).length() > 0.2:
					visual.position.y = absf(sin(t * 8.0 + phase)) * 0.1
				else:
					visual.position.y = 0.0

func _mat(color: Color, emissive := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 2.4
	return mat

func _sphere(radius: float, color: Color, squash := 1.0, emissive := false) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0 * squash
	instance.mesh = mesh
	instance.material_override = _mat(color, emissive)
	return instance

func _build(kind: int) -> Node3D:
	var root := Node3D.new()
	var visual := Node3D.new()
	root.add_child(visual)
	match kind:
		SHEEP:
			var body := _sphere(0.42, Color("f2efe6"), 0.85)
			body.position = Vector3(0, 0.42, 0)
			body.scale = Vector3(1.25, 1.0, 0.95)
			visual.add_child(body)
			var head := _sphere(0.2, Color("4a4038"))
			head.position = Vector3(0, 0.6, -0.45)
			visual.add_child(head)
			for spec in [Vector3(0.2, 0.12, 0.22), Vector3(-0.2, 0.12, 0.22),
					Vector3(0.2, 0.12, -0.22), Vector3(-0.2, 0.12, -0.22)]:
				var leg := MeshInstance3D.new()
				var mesh := CylinderMesh.new()
				mesh.top_radius = 0.06
				mesh.bottom_radius = 0.06
				mesh.height = 0.26
				leg.mesh = mesh
				leg.position = spec
				leg.material_override = _mat(Color("4a4038"))
				visual.add_child(leg)
		BUNNY:
			var body := _sphere(0.22, Color("cbb9a4"), 0.9)
			body.position = Vector3(0, 0.22, 0)
			visual.add_child(body)
			var head := _sphere(0.15, Color("d8c8b4"))
			head.position = Vector3(0, 0.42, -0.15)
			visual.add_child(head)
			for side in [-1.0, 1.0]:
				var ear := MeshInstance3D.new()
				var mesh := CapsuleMesh.new()
				mesh.radius = 0.045
				mesh.height = 0.3
				ear.mesh = mesh
				ear.position = Vector3(side * 0.07, 0.62, -0.13)
				ear.rotation_degrees = Vector3(-12, 0, side * -10)
				ear.material_override = _mat(Color("d8c8b4"))
				visual.add_child(ear)
			var tail := _sphere(0.07, Color.WHITE)
			tail.position = Vector3(0, 0.24, 0.22)
			visual.add_child(tail)
		BUTTERFLY:
			var body := _sphere(0.06, Color("3a3d45"), 1.6)
			visual.add_child(body)
			for side in [-1.0, 1.0]:
				var wing := MeshInstance3D.new()
				wing.name = "WingL" if side > 0 else "WingR"
				var mesh := QuadMesh.new()
				mesh.size = Vector2(0.28, 0.22)
				wing.mesh = mesh
				wing.position = Vector3(side * 0.12, 0.02, 0)
				var mat := _mat(Color("7bb8f0") if randf() < 0.5 else Color("f2a3c2"))
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				wing.material_override = mat
				visual.add_child(wing)
		FIREFLY:
			var glow := _sphere(0.055, Color("d8ffa0"), 1.0, true)
			visual.add_child(glow)
		CHICKEN:
			var body := _sphere(0.19, Color("f2efe6"), 0.85)
			body.position = Vector3(0, 0.24, 0)
			visual.add_child(body)
			var head := _sphere(0.11, Color("f2efe6"))
			head.position = Vector3(0, 0.45, -0.14)
			visual.add_child(head)
			var comb := _sphere(0.05, Color("d63d2e"))
			comb.position = Vector3(0, 0.55, -0.12)
			visual.add_child(comb)
			var beak := MeshInstance3D.new()
			var beak_mesh := BoxMesh.new()
			beak_mesh.size = Vector3(0.06, 0.04, 0.09)
			beak.mesh = beak_mesh
			beak.position = Vector3(0, 0.44, -0.24)
			beak.material_override = _mat(Color("e08c3a"))
			visual.add_child(beak)
		CRAB:
			var body := _sphere(0.2, Color("d95f4b"), 0.55)
			body.position = Vector3(0, 0.12, 0)
			body.scale = Vector3(1.3, 1.0, 1.0)
			visual.add_child(body)
			for side in [-1.0, 1.0]:
				var claw := _sphere(0.08, Color("e2745f"))
				claw.position = Vector3(side * 0.3, 0.12, -0.16)
				visual.add_child(claw)
				var eye := _sphere(0.04, Color(0.1, 0.1, 0.14))
				eye.position = Vector3(side * 0.08, 0.28, -0.12)
				visual.add_child(eye)
		FROG:
			var body := _sphere(0.14, Color("5da944"), 0.7)
			body.position = Vector3(0, 0.11, 0)
			visual.add_child(body)
			for side in [-1.0, 1.0]:
				var eye := _sphere(0.05, Color("cfe86b"))
				eye.position = Vector3(side * 0.08, 0.24, -0.08)
				visual.add_child(eye)
				var pupil := _sphere(0.025, Color(0.1, 0.1, 0.14))
				pupil.position = Vector3(side * 0.08, 0.24, -0.12)
				visual.add_child(pupil)
		DEER:
			var body := _sphere(0.3, Color("9a6f4a"), 0.8)
			body.position = Vector3(0, 0.5, 0)
			body.scale = Vector3(1.0, 1.0, 1.4)
			visual.add_child(body)
			var head := _sphere(0.15, Color("a87e56"))
			head.position = Vector3(0, 0.85, -0.4)
			visual.add_child(head)
			for side in [-1.0, 1.0]:
				var antler := MeshInstance3D.new()
				var antler_mesh := CylinderMesh.new()
				antler_mesh.top_radius = 0.02
				antler_mesh.bottom_radius = 0.03
				antler_mesh.height = 0.3
				antler.mesh = antler_mesh
				antler.position = Vector3(side * 0.1, 1.05, -0.38)
				antler.rotation_degrees = Vector3(0, 0, side * -20.0)
				antler.material_override = _mat(Color("6e523a"))
				visual.add_child(antler)
				for fz in [0.35, -0.35]:
					var leg := MeshInstance3D.new()
					var leg_mesh := CylinderMesh.new()
					leg_mesh.top_radius = 0.045
					leg_mesh.bottom_radius = 0.045
					leg_mesh.height = 0.45
					leg.mesh = leg_mesh
					leg.position = Vector3(side * 0.15, 0.22, fz)
					leg.material_override = _mat(Color("7a563a"))
					visual.add_child(leg)
		PENGUIN:
			var body := _sphere(0.2, Color("2e3440"), 1.3)
			body.position = Vector3(0, 0.3, 0)
			visual.add_child(body)
			var belly := _sphere(0.15, Color("eceff4"), 1.2)
			belly.position = Vector3(0, 0.28, -0.09)
			visual.add_child(belly)
			var beak := MeshInstance3D.new()
			var beak_mesh := BoxMesh.new()
			beak_mesh.size = Vector3(0.06, 0.05, 0.1)
			beak.mesh = beak_mesh
			beak.position = Vector3(0, 0.5, -0.18)
			beak.material_override = _mat(Color("e08c3a"))
			visual.add_child(beak)
		DUCK:
			var body := _sphere(0.2, Color("e8d44f"), 0.8)
			body.position = Vector3(0, 0.05, 0)
			body.scale = Vector3(1.0, 1.0, 1.25)
			visual.add_child(body)
			var head := _sphere(0.12, Color("e8d44f"))
			head.position = Vector3(0, 0.3, -0.2)
			visual.add_child(head)
			var beak := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.1, 0.04, 0.12)
			beak.mesh = mesh
			beak.position = Vector3(0, 0.28, -0.33)
			beak.material_override = _mat(Color("e08c3a"))
			visual.add_child(beak)
	return root
