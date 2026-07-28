class_name BotBrain
extends Node
## Makes computer players actually play: grab crates when hands are empty,
## chase and shoot enemies, stand by downed teammates to revive them, and
## wander otherwise. Attached to bot Player nodes client-side.

var player: Player
var bot: BotSlot

func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 0.35
	timer.timeout.connect(_think)
	add_child(timer)
	timer.start()

func _drive_toward(target: Vector3, run := 1.0) -> void:
	var to_target := target - player.position
	var world_dir := Vector2(to_target.x, to_target.z).normalized() * run
	bot.drive = world_dir.rotated(player.camera_yaw)
	bot.drive_until = Time.get_ticks_msec() / 1000.0 + 0.45

func _think() -> void:
	if player == null or not is_instance_valid(player) or player.world == null:
		return
	var world: Node = player.world
	bot.brain_shoot = false
	if player.downed:
		return
	var my_team := int(Game.roster.get(player.player_id, {}).get("team", -1))
	for child in world.players.get_children():
		if child is Player and child != player and child.downed \
				and int(Game.roster.get(child.player_id, {}).get("team", -2)) == my_team \
				and child.position.distance_to(player.position) < 26.0:
			_drive_toward(child.position)
			return
	var armed := false
	for i in 8:
		var it: Dictionary = player.slots[i]
		if it.kind == "weapon" and int(it.id) != 13:
			armed = true
			if player.held().kind != "weapon":
				player.selected_slot = i
			break
	var enemy: Player = null
	var best := 34.0
	for child in world.players.get_children():
		if child is Player and child != player and not child.downed \
				and int(Game.roster.get(child.player_id, {}).get("team", -2)) != my_team:
			var d: float = child.position.distance_to(player.position)
			if d < best:
				best = d
				enemy = child
	if enemy != null and (armed or best < 5.0):
		_drive_toward(enemy.position)
		player.heading = (enemy.position - player.position).normalized()
		bot.brain_shoot = best < 26.0
		return
	var has_empty := false
	for it: Dictionary in player.slots:
		if it.kind == "empty":
			has_empty = true
	if has_empty and world.crates != null:
		var target := Vector3.INF
		var crate_best := 70.0
		for entry: Dictionary in world.crates._nodes.values():
			var pos: Vector3 = entry.node.position
			var d: float = pos.distance_to(player.position)
			if d < crate_best:
				crate_best = d
				target = pos
		if target != Vector3.INF:
			_drive_toward(target)
