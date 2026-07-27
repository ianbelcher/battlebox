class_name OrbView
extends Node3D
## Thrown orbs — soft glowing spheres anyone can lob any time (R / middle
## click / right trigger). The thrower's client simulates its own orbs and
## reports hits; everyone else's orbs are visual-only (the server told us
## about them via cl_orb).

var _orbs: Array = []   # {node, vel, shooter_id, age, mine, slot, boom}

func spawn(shooter_id: String, origin: Vector3, dir: Vector3, boom: bool) -> void:
	var me := multiplayer.get_unique_id()
	# The shooter already spawned their own copy locally.
	if shooter_id.begins_with("%d:" % me):
		return
	_add_orb(shooter_id, origin, dir, false, -1, boom)

func shoot_local(player: Player, boom: bool) -> void:
	var world: Node = get_parent()
	var origin: Vector3 = player.position + Vector3(0, 1.2, 0)
	var dir: Vector3
	if player.fp_mode:
		dir = player.look_dir()
	else:
		dir = (player.heading + Vector3(0, 0.35 if boom else 0.15, 0)).normalized()
	_add_orb(player.player_id, origin, dir, true, player.slot, boom)
	world.sv_shoot.rpc_id(1, player.slot, origin, dir, boom)
	if boom:
		Sfx.play("whoosh", -2.0, 0.7)
	else:
		Sfx.play("pew", -6.0)

func _add_orb(shooter_id: String, origin: Vector3, dir: Vector3, mine: bool, slot: int, boom: bool) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.24 if boom else 0.1
	mesh.height = mesh.radius * 2.0
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	var color := Color("ff7a3d") if boom else Color("ffe08a")
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.6
	node.material_override = mat
	node.position = origin
	add_child(node)
	# Pellets are fast and flat; shells lob slowly like a thrown TNT.
	var speed := 12.0 if boom else 30.0
	_orbs.append({"node": node, "vel": dir.normalized() * speed,
		"shooter_id": shooter_id, "age": 0.0, "mine": mine, "slot": slot,
		"boom": boom})

func _physics_process(delta: float) -> void:
	var world: Node = get_parent()
	if world == null or world.chunks == null:
		return
	for i in range(_orbs.size() - 1, -1, -1):
		var orb: Dictionary = _orbs[i]
		orb.age += delta
		orb.vel.y -= (9.0 if orb.boom else 3.0) * delta
		var node: Node3D = orb.node
		node.position += orb.vel * delta
		var died: bool = orb.age > (3.5 if orb.boom else 1.4)
		var cell := Vector3i(floori(node.position.x), floori(node.position.y), floori(node.position.z))
		if not died and Blocks.is_solid(world.chunks.get_block(cell)):
			died = true
			if orb.mine:
				world.sv_shot.rpc_id(1, orb.slot, cell, orb.boom)
		if not died and orb.mine:
			# Player hits (anyone but the shooter): pellets bonk, shells boom.
			for child in world.players.get_children():
				if child is Player and child.player_id != orb.shooter_id \
						and child.position.distance_to(node.position - Vector3(0, 0.8, 0)) < 1.1:
					if orb.boom:
						world.sv_shot.rpc_id(1, orb.slot, cell, true)
					else:
						world.sv_orb_hit.rpc_id(1, orb.slot, child.player_id, node.position)
					died = true
					break
			# Direct Grump hits (shell splash is handled server-side).
			if not died and world.survival_active and not orb.boom:
				var monster: int = world.monster_view.nearest_to(node.position, 1.1)
				if monster >= 0:
					world.sv_zap.rpc_id(1, orb.slot, monster)
					world.monster_view.hit(monster, false)
					died = true
		if died:
			_poof(node.position)
			node.queue_free()
			_orbs.remove_at(i)

func _poof(at: Vector3) -> void:
	var puff := CPUParticles3D.new()
	puff.position = at
	puff.amount = 6
	puff.lifetime = 0.3
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.spread = 180.0
	puff.initial_velocity_min = 1.0
	puff.initial_velocity_max = 2.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("aef7f0")
	mesh.material = mat
	puff.mesh = mesh
	add_child(puff)
	puff.emitting = true
	get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(puff):
			puff.queue_free())
