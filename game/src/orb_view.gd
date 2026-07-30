class_name OrbView
extends Node3D
## Thrown orbs — soft glowing spheres anyone can lob any time (R / middle
## click / right trigger). The thrower's client simulates its own orbs and
## reports hits; everyone else's orbs are visual-only (the server told us
## about them via cl_orb).

var _orbs: Array = []   # {node, vel, shooter_id, age, mine, slot, boom}

## Kind = weapon id from the Weapons registry.

func spawn(shooter_id: String, origin: Vector3, dir: Vector3, kind: int) -> void:
	var me := multiplayer.get_unique_id()
	# The shooter already spawned their own copy locally.
	if shooter_id.begins_with("%d:" % me):
		return
	_add_orb(shooter_id, origin, dir, false, -1, kind)

func shoot_local(player: Player, kind: int) -> void:
	var world: Node = get_parent()
	var dir: Vector3
	if player.fp_mode:
		dir = player.look_dir()
	elif kind == 17:
		# Dragon fire streams out wherever the camera looks.
		dir = player.camera_look_dir()
	else:
		dir = player.heading.normalized()
	# Shots leave from the right-hand muzzle, then converge on the point the
	# crosshair actually looks at (so aim stays true at range).
	var eye: Vector3 = player.position + Vector3(0, Player.EYE_HEIGHT, 0)
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.ZERO
	var origin: Vector3 = eye + Vector3(0, -0.34, 0) + side * 0.3 + dir * 0.3
	dir = (eye + dir * 40.0 - origin).normalized()
	_add_orb(player.player_id, origin, dir, true, player.slot, kind)
	world.sv_shoot.rpc_id(1, player.slot, origin, dir, kind)
	if kind == 12:
		world.sv_dig_tunnel.rpc_id(1, player.slot, origin, dir)
	if kind == 0:
		Sfx.play("click", -6.0)
	elif kind == 1 or kind == 9 or kind == 15 or kind == 17:
		Sfx.play("thoomp", -2.0)
	else:
		Sfx.play("whoosh", -3.0, 1.1)

func _add_orb(shooter_id: String, origin: Vector3, dir: Vector3, mine: bool, slot: int, kind: int) -> void:
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09 if kind == 0 else (0.32 if kind == 15 or kind == 17 else 0.22)
	mesh.height = mesh.radius * 2.0
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	var color: Color = Weapons.spec(kind).color
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.8
	node.material_override = mat
	node.position = origin
	add_child(node)
	var speed: float = Weapons.spec(kind).speed
	if kind == 14:
		# Flares launch mostly upward no matter where you aim.
		dir = (dir * 0.35 + Vector3.UP).normalized()
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
		var node: Node3D = orb.node
		node.position += orb.vel * delta
		if orb.kind == 14:
			if orb.age > 1.1:
				_spawn_flare(node.position)
				node.queue_free()
				_orbs.remove_at(i)
			continue
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
				if orb.kind == 2:
					# Grapple: launch the shooter in an arc that lands them ON
					# TOP of the block they hooked (ceilings just bonk you).
					for child in world.players.get_children():
						if child is Player and child.player_id == orb.shooter_id:
							var target := Vector3(cell) + Vector3(0.5, 1.2, 0.5)
							var delta_v: Vector3 = target - child.position
							var rise: float = maxf(delta_v.y + 1.6, 1.5)
							var vy := sqrt(2.0 * 22.0 * rise)
							var flight := vy / 22.0 + 0.25
							child.velocity = Vector3(delta_v.x / flight, vy, delta_v.z / flight)
							child.carry_time = flight + 0.3
							child.on_floor = false
							Sfx.play("warp", -4.0)
		if not died and orb.mine:
			# Player hits (anyone but the shooter): pellets bonk, shells boom.
			for child in world.players.get_children():
				if child is Player and child.player_id != orb.shooter_id \
						and child.position.distance_to(node.position - Vector3(0, 0.8, 0)) < 1.1:
					if orb.kind == 1 or orb.kind >= 5:
						world.sv_shot.rpc_id(1, orb.slot, cell, orb.kind)
					else:
						world.sv_orb_hit.rpc_id(1, orb.slot, child.player_id, node.position)
					died = true
					break
			# Grapple a DRAGON and you climb aboard.
			if not died and orb.kind == 2:
				var dragon: int = world.critter_view.nearest_id(node.position, 3.5)
				if dragon >= 0 and world.critter_view.is_dragon(dragon):
					for child in world.players.get_children():
						if child is Player and child.player_id == orb.shooter_id:
							child._set_riding(dragon)
							Sfx.play("warp")
					died = true
			# Critters poof when shot (kind 0 pellets only — be humane-ish).
			if not died and orb.kind == 0:
				var critter: int = world.critter_view.nearest_id(node.position, 1.2)
				if critter >= 0:
					world.sv_shoot_critter.rpc_id(1, orb.slot, critter)
					world.critter_view.pop(critter)
					died = true
			# Direct Grump hits (shell splash is handled server-side).
			if not died and world.survival_active and orb.kind == 0:
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


## A drifting sky light: bright star + real light that sinks slowly.
func _spawn_flare(pos: Vector3) -> void:
	var flare := Node3D.new()
	flare.position = pos
	var star := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.32
	mesh.height = 0.64
	star.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("fff0f6")
	mat.emission_enabled = true
	mat.emission = Color("ff9ac0")
	mat.emission_energy_multiplier = 6.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	star.material_override = mat
	flare.add_child(star)
	var light := OmniLight3D.new()
	light.omni_range = 55.0
	light.light_energy = 4.5
	light.light_color = Color("ffd6e6")
	light.shadow_enabled = false
	flare.add_child(light)
	add_child(flare)
	Sfx.play("collect", -4.0)
	var tween := create_tween()
	tween.tween_property(flare, "position", pos + Vector3(0, -9.0, 0), 8.0)
	tween.parallel().tween_property(light, "light_energy", 0.0, 8.0)
	tween.tween_callback(func() -> void:
		if is_instance_valid(flare):
			flare.queue_free())
