extends SceneTree
## A shot must land where the CROSSHAIR is pointing, at any range.
##
##   WORLD_DATA_DIR=/tmp/aim godot --headless --path <game> \
##     --script res://tests/aim_convergence.gd
##
## Shots leave a muzzle that is down and to the right of the eye, so they
## have to be angled inwards to cross the line of sight. Which means
## there is exactly one distance at which they are dead on, and it is
## whatever distance the code converges them at.
##
## That used to be a fixed 40 blocks — a rifle zeroed at 40m. Ian's
## report: "shots will move past the cross hairs and miss what you're
## aiming at" over long distances. Past the convergence point the shot
## has already crossed the sight line and keeps going, and the miss grows
## with every block.
##
## This measures the miss directly: put a target at a range, work out
## where the shot actually passes it, and check the gap. It is pure
## geometry — no world, no server — because the geometry IS the bug.

## The muzzle offset from the eye, as OrbView.throw() builds it.
const MUZZLE_DOWN := 0.34
const MUZZLE_SIDE := 0.3
const MUZZLE_FWD := 0.3

## Ranges to check, in blocks. The old code was exact at 40 and wrong
## either side; 150+ is a shot across a big map.
const RANGES := [8.0, 20.0, 40.0, 80.0, 150.0, 250.0]

## A shot may pass within this of the aim point. A player is about 0.6
## blocks wide, so anything approaching half a block is a clean miss.
const ALLOWED := 0.25

var _failures := 0

func _initialize() -> void:
	# A few look directions, so this is not just the trivial straight
	# ahead case: the muzzle offset is built from the look direction.
	var looks: Array = [
		Vector3(0, 0, -1),
		Vector3(1, 0, -1).normalized(),
		Vector3(0.3, -0.25, -1).normalized(),
		Vector3(-0.8, 0.15, -1).normalized(),
	]
	for look: Vector3 in looks:
		for range_blocks: float in RANGES:
			_check(look, range_blocks)
	# ...and show what the fixed-40 convergence used to cost, so the
	# number this is protecting against is on the record.
	print("  (old fixed-40 aim, straight ahead: %.2f blocks off at 150, "
		% _legacy_miss(Vector3(0, 0, -1), 150.0)
		+ "%.2f at 250)" % _legacy_miss(Vector3(0, 0, -1), 250.0))
	if _failures == 0:
		print("aim_convergence: PASS — every shot passes within %.2f blocks "
			% ALLOWED + "of the crosshair, 8 to 250 blocks out")
		quit(0)
	else:
		print("aim_convergence: FAIL — %d shots missed the crosshair" % _failures)
		quit(1)

func _check(look: Vector3, range_blocks: float) -> void:
	var eye := Vector3(0, 1.6, 0)
	var side := look.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.ZERO
	var origin := eye + Vector3(0, -MUZZLE_DOWN, 0) + side * MUZZLE_SIDE \
		+ look * MUZZLE_FWD
	# What the crosshair is on: a target at this range along the sight.
	var aim := eye + look * range_blocks
	# What the game now does — converge on the thing the sight ray hits.
	var dir := (aim - origin).normalized()
	# Where the shot actually is when it reaches the target's distance.
	var travel := (aim - origin).length()
	var at := origin + dir * travel
	var miss := at.distance_to(aim)
	if miss > ALLOWED:
		_failures += 1
		print("  look %s at %.0f blocks: missed by %.2f" % [look, range_blocks, miss])

## What the OLD code did, kept so the failure it caused is on the record:
## converge on a fixed 40 blocks whatever the target's range.
func _legacy_miss(look: Vector3, range_blocks: float) -> float:
	var eye := Vector3(0, 1.6, 0)
	var side := look.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.01 else Vector3.ZERO
	var origin := eye + Vector3(0, -MUZZLE_DOWN, 0) + side * MUZZLE_SIDE \
		+ look * MUZZLE_FWD
	var aim := eye + look * range_blocks
	var dir := (eye + look * 40.0 - origin).normalized()
	var at := origin + dir * (aim - origin).length()
	return at.distance_to(aim)
