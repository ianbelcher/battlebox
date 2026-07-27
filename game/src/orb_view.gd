class_name OrbView
extends Node3D
## Thrown orbs — soft glowing spheres anyone can lob any time (R / middle
## click / right trigger). The thrower's client simulates its own orbs and
## reports hits; everyone else's orbs are visual-only (the server told us
## about them via cl_orb).

var _orbs: Array = []   # {node, vel, shooter_id, age, mine, slot, boom}

## Kind: 0 blaster pellet, 1 bazooka shell, 2 incendiary. All share the same
## fast, flat arc — gravity nudges them but long shots stay honest.
const KIND_COLORS := [Color("ffe08a"), Color("ff7a3d"), Color("ff4426")]

func spawn(shooter_id: String, origin: Vector3, dir: Vector3, kind: int) -> void:
	var me := multiplayer.get_unique_id()
	# The shooter already spawned their own copy locally.
	if shooter_id.begins_with("%d:" % me):
		return
	_add_orb(shooter_id, origin, dir, false, -1, kind)

func shoot_local(player: Player, kind: int) -> void:
	var world: Node = get_parent()
	var origin: Vector3 = player.position + Vector3(0, 2.6, 0)
	var dir: Vector3
	if player.fp_mode:
		dir = player.look_dir()
	else:
		dir = (player.heading + Vector3(0, 0.12, 0)).normalized()
	_add_orb(player.player_id, origin, dir, true, player.slot, kind)
	world.sv_shoot.rpc_id(1, player.slot, origin, dir, kind)
	if kind == 0:
		Sfx.play("pew", -8.0)
	else:
		Sfx.play("whoosh", -3.0, 0.7 if kind == 1 else 1.1)

func _add_orb(shooter_id: String, origin: Vector3, dir: Vector3, mine: bool, slot: int, kind: int) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09 if kind == 0 else 0.22
	mesh.height = mesh.radius * 2.0
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	var color: Color = KIND_COLORS[clampi(kind, 0, 2)]
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.8
	node.material_override = mat
	node.position = origin
	add_child(node)
	var speed := 70.0 if kind == 0 else 54.0
	_orbs.append({"node": node, "vel": dir.normalized() * speed,
		"shooter_id": shooter_id, "age": 0.0, "mine": mine, "slot": slot,
		"kind": kind})

func _physics_process(delta: float) -> void:
	var world: Node = get_parent()
	if world == null or world.chunks == null:
		return
	for i in range(_orbs.size() - 1, -1, -1):
		var orb: Dictionary = _orbs[i]
		orb.age += delta
		orb.vel.y -= 4.4 * delta
		var node: Node3D = orb.node
		node.position += orb.vel * delta
		var cell := Vector3i(floori(node.position.x), floori(node.position.y), floori(node.position.z))
		# Shots never fizzle mid-air: they fly until they hit something (or
		# leave the world), and heavy shells still detonate wherever they end.
		var died: bool = orb.age > 6.0 or node.position.y < -4.0
		if died and orb.mine and orb.kind > 0 and node.position.y >= -4.0:
			world.sv_shot.rpc_id(1, orb.slot, cell, orb.kind)
		if not died and Blocks.is_solid(world.chunks.get_block(cell)):
			died = true
			if orb.mine:
				world.sv_shot.rpc_id(1, orb.slot, cell, orb.kind)
		if not died and orb.mine:
			# Player hits (anyone but the shooter): pellets bonk, shells boom.
			for child in world.players.get_children():
				if child is Player and child.player_id != orb.shooter_id \
						and child.position.distance_to(node.position - Vector3(0, 1.6, 0)) < 2.0:
					if orb.kind > 0:
						world.sv_shot.rpc_id(1, orb.slot, cell, orb.kind)
					else:
						world.sv_orb_hit.rpc_id(1, orb.slot, child.player_id, node.position)
					died = true
					break
			# Direct Grump hits (shell splash is handled server-side).
			if not died and world.survival_active and orb.kind == 0:
				var monster: int = world.monster_view.nearest_to(node.position, 2.0)
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
