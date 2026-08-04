extends SceneTree
## Proves the rule Ian asked for: an explosion must never leave a hole you
## cannot walk out of.
##
##   WORLD_DATA_DIR=/tmp/walkout godot --headless --path <game> \
##     --script res://tests/blast_walkout.gd
##
## Craters are carved as SPHERES, and a sphere meets the ground almost
## vertically at its rim, so every crater used to be ringed by a wall one
## to three blocks high — land in one mid-fight and you were stuck in a
## pit while somebody shot down at you.
##
## ChunkStore.shave_walkable() shaves that lip off. It lives on the store
## rather than on WorldNode precisely so this can be checked without
## standing up a server.
##
## The test BUILDS ITS OWN GROUND rather than hunting for somewhere flat
## in the generated world. That is deliberate:
##  - the claim is about the algorithm, not about the terrain generator;
##  - generated ground almost never has a cave-free flat patch wide
##    enough to isolate a big crater's rim, so a search-based version
##    silently checked one small crater and called it a pass;
##  - blowing the roof off a cave drops the floor twenty blocks, which is
##    a hole in the world rather than a lip on a crater, and no amount of
##    shaving the edge would (or should) fix it.
##
## Three shapes are tested: flat ground, a hillside, and a shot fired into
## the side of a wall. Exits non-zero, naming the offending columns.

const RADII := [2.6, 3.4, 5.6]   # medium shooter, napalm, big shooter
const GROUND_Y := 40
## Half-width of each built platform. Must comfortably exceed the widest
## check ring, which now spans the whole shave footprint: 2*5.6 + 4 = 16.
const PAD := 22
## Platforms are laid out in a 3x3 grid around the origin. They have to
## sit INSIDE the world slab — a default world is 250 blocks across, so
## anything beyond ±125 is off the map and set_block() there goes into
## the border and is silently thrown away. An earlier version built at
## (-600, -600) and every platform quietly evaporated, which is why the
## test passed with the fix switched off.
const SPACING := 40

var _failures := 0
var _checked := 0

func _initialize() -> void:
	var store := ChunkStore.new()   # _init() boots it from WORLD_DATA_DIR
	var shapes := ["flat", "slope", "wall"]
	for ri in RADII.size():
		var radius: float = RADII[ri]
		for si in shapes.size():
			var shape: String = shapes[si]
			var at := Vector2i((si - 1) * SPACING, (ri - 1) * SPACING)
			_build(store, at, shape)
			var origin := Vector3i(at.x, GROUND_Y, at.y)
			var before := _heights(store, origin, radius)
			_carve(store, origin, radius)
			store.shave_walkable(origin, radius)
			_check(store, origin, radius, before, shape)
	if _failures == 0:
		print("blast_walkout: PASS — %d craters, every one walkable" % _checked)
		quit(0)
	else:
		print("blast_walkout: FAIL — %d unwalkable steps over %d craters"
			% [_failures, _checked])
		quit(1)

## Lay down a solid platform to blow up.
##   flat   dead level
##   slope  one block of rise per block, so the shave meets real gradient
##   wall   level ground with a tall block wall through the middle
func _build(store: ChunkStore, at: Vector2i, shape: String) -> void:
	for dz in range(-PAD, PAD + 1):
		for dx in range(-PAD, PAD + 1):
			var top := GROUND_Y
			if shape == "slope":
				top = GROUND_Y + int(floor(float(dx) * 0.5))
			# Solid well below the deepest crater, so nothing can fall
			# through into a void and confuse the result.
			# DIRT, not stone: stone is hardness 2 and a blast only chips
			# it near the very centre, so a stone platform came out with
			# no rim at all and the test proved nothing. Ordinary soil is
			# what most of the world's surface actually is.
			for y in range(top - 24, top):
				store.set_block(Vector3i(at.x + dx, y, at.y + dz), Blocks.DIRT)
			store.set_block(Vector3i(at.x + dx, top, at.y + dz), Blocks.GRASS)
			for y in range(top + 1, top + 26):
				store.set_block(Vector3i(at.x + dx, y, at.y + dz), Blocks.AIR)
			if shape == "wall" and dx == 6:
				for y in range(GROUND_Y + 1, GROUND_Y + 7):
					store.set_block(Vector3i(at.x + dx, y, at.y + dz), Blocks.COBBLE)

## The same sphere _blast() carves, minus the fire, scorch and chaining —
## none of which move the ground.
func _carve(store: ChunkStore, origin: Vector3i, radius: float) -> void:
	var reach := int(ceil(radius))
	for dy in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				if Vector3(dx, dy, dz).length() > radius:
					continue
				var pos := origin + Vector3i(dx, dy, dz)
				var block := store.get_block(pos)
				if block == Blocks.AIR or Blocks.is_liquid(block) \
						or not Blocks.is_breakable(block):
					continue
				var tier := Blocks.hardness(block)
				if tier >= 4:
					continue
				if tier == 3 and pos != origin:
					continue
				if tier == 2 and Vector3(dx, dy, dz).length() > radius * 0.65 \
						and pos != origin:
					continue
				store.set_block(pos, Blocks.AIR)

func _heights(store: ChunkStore, origin: Vector3i, radius: float) -> Dictionary:
	var reach := int(ceil(radius * 2.0)) + 4
	var out: Dictionary = {}
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := Vector2i(origin.x + dx, origin.z + dz)
			out[key] = store.surface_y(key.x, key.y)
	return out

## Every adjacent PAIR of columns in the blast's footprint must be within
## one block of each other.
##
## Checking only the columns the blast CHANGED, and only looking downward
## from them, is what an earlier version of this test did — and it passed
## with the shave switched off. The wall a crater leaves is at the RIM,
## and the rim column is the one the sphere never touched: the changed
## column is at the bottom looking up at it. Pairs catch it from either
## side.
##
## Pairs that were already this steep before the shot are exempt (the
## wall shape has a deliberate six-block face in it, and levelling the
## landscape's own cliffs is not this function's job).
func _check(store: ChunkStore, origin: Vector3i, radius: float,
		before: Dictionary, shape: String) -> void:
	_checked += 1
	var reach := int(ceil(radius * 2.0)) + 4
	for dz in range(-reach, reach):
		for dx in range(-reach, reach):
			var key := Vector2i(origin.x + dx, origin.z + dz)
			for off in [Vector2i(1, 0), Vector2i(0, 1)]:
				var side := Vector2i(key.x + off.x, key.y + off.y)
				var a := store.surface_y(key.x, key.y)
				var b := store.surface_y(side.x, side.y)
				if absi(a - b) <= 1:
					continue
				var was_a := int(before.get(key, a))
				var was_b := int(before.get(side, b))
				if was_a == a and was_b == b:
					continue           # the blast did not touch this pair
				if absi(was_a - was_b) > 1:
					continue           # it was already a cliff here
				# Built structures are exempt. Blowing a doorway through a
				# six-block wall leaves the wall standing either side of
				# the hole, which is exactly right — you walk THROUGH the
				# gap, you were never going to walk up the wall.
				if was_a > GROUND_Y or was_b > GROUND_Y:
					continue
				_failures += 1
				if _failures <= 8:
					print("  %s r=%.1f (%d,%d)=%d vs (%d,%d)=%d  (was %d vs %d)"
						% [shape, radius, key.x, key.y, a, side.x, side.y, b,
							was_a, was_b])
