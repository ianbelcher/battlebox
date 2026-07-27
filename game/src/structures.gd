class_name Structures
## Prefab structures the picker offers alongside single blocks: pick one and
## the place button stamps it into the world (server-validated; it never
## overwrites anything except air, liquids and plants, so existing builds
## survive careless stamping).
##
## Each entry builds a list of [Vector3i offset, block] pairs relative to
## the ground cell in front of the player.

const STRUCTURES := [
	{"id": "house", "name": "Little House", "color": Color("b08d5e")},
	{"id": "tower", "name": "Watchtower", "color": Color("7a7d80")},
	{"id": "big_tree", "name": "Giant Tree", "color": Color("4f8a3d")},
	{"id": "bridge", "name": "Bridge", "color": Color("d6c396")},
	{"id": "camp", "name": "Campsite", "color": Color("ff9d45")},
	{"id": "wall", "name": "Fort Wall", "color": Color("8d9296")},
	{"id": "pool", "name": "Pool", "color": Color("4a9df8")},
	{"id": "garden", "name": "Flower Garden", "color": Color("ef8fc0")},
	{"id": "fort", "name": "Fort", "color": Color("7a7d80")},
	{"id": "bunker", "name": "Steel Bunker", "color": Color("aab4c2")},
	{"id": "sniper", "name": "Sniper Tower", "color": Color("5d4430")},
	{"id": "barricade", "name": "Barricade", "color": Color("e6d29a")},
]

static func count() -> int:
	return STRUCTURES.size()

static func spec(index: int) -> Dictionary:
	return STRUCTURES[posmod(index, STRUCTURES.size())]

## The block list for a structure, expanded 2x (blocks are half a meter, so
## every prefab cell becomes a 2x2x2 cube to keep real-world proportions).
static func cells(index: int, roll: int) -> Array:
	return _cells_raw(index, roll)

static func _cells_raw(index: int, roll: int) -> Array:
	match spec(index).id:
		"house":
			return _house(roll)
		"tower":
			return _tower()
		"big_tree":
			return _big_tree(roll)
		"bridge":
			return _bridge()
		"camp":
			return _camp()
		"wall":
			return _wall()
		"pool":
			return _pool()
		"garden":
			return _garden(roll)
		"fort":
			return _fort()
		"bunker":
			return _bunker()
		"sniper":
			return _sniper()
		"barricade":
			return _barricade()
	return []

## 9x9 crenellated cobble fort with corner posts and a gate.
static func _fort() -> Array:
	var list: Array = []
	for x in range(-4, 5):
		for z in range(-4, 5):
			var edge: bool = absi(x) == 4 or absi(z) == 4
			if not edge:
				continue
			for y in range(0, 3):
				if z == -4 and absi(x) <= 1 and y < 2:
					continue  # gate
				_put(list, x, y, z, Blocks.COBBLE)
			if (absi(x) == 4 and absi(z) == 4):
				_put(list, x, 3, z, Blocks.COBBLE)
				_put(list, x, 4, z, Blocks.LANTERN)
			elif posmod(x + z, 2) == 0:
				_put(list, x, 3, z, Blocks.COBBLE)
	return list

## Small steel pillbox: pellet-proof, bazooka chips it one block at a time.
static func _bunker() -> Array:
	var list: Array = []
	for x in range(-2, 3):
		for z in range(-2, 3):
			for y in range(0, 3):
				var edge: bool = absi(x) == 2 or absi(z) == 2
				if y == 2:
					_put(list, x, y, z, Blocks.STEEL)
				elif edge:
					if z == -2 and x == 0 and y == 0:
						continue  # door
					if y == 1 and (absi(x) == 2 or z == 2) and posmod(x + z, 2) == 0:
						continue  # firing slits
					_put(list, x, y, z, Blocks.STEEL)
	return list

## Tall lookout with a ladder-ish block stack and rails.
static func _sniper() -> Array:
	var list: Array = []
	for y in range(0, 9):
		for corner in [Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(1, 0, 1)]:
			list.append([Vector3i(corner.x, y, corner.z), Blocks.DARK_PLANKS])
	var steps := [Vector3i(0, 0, 2), Vector3i(0, 2, 2), Vector3i(0, 4, 2), Vector3i(0, 6, 2), Vector3i(0, 8, 2)]
	for step in steps:
		list.append([step, Blocks.PLANKS])
	for x in range(-1, 2):
		for z in range(-1, 2):
			_put(list, x, 9, z, Blocks.PLANKS)
	for x in [-1, 1]:
		for z in [-1, 1]:
			_put(list, x, 10, z, Blocks.PLANKS)
	_put(list, 0, 10, 0, Blocks.LANTERN)
	return list

## Quick cover: a low sandbag wall.
static func _barricade() -> Array:
	var list: Array = []
	for x in range(-3, 4):
		_put(list, x, 0, 0, Blocks.SAND)
		if absi(x) < 3:
			_put(list, x, 1, 0, Blocks.SAND)
	return list

static func _put(list: Array, x: int, y: int, z: int, block: int) -> void:
	list.append([Vector3i(x, y, z), block])

## 5x5 plank cottage: door gap toward -z, window holes, lantern inside,
## pyramid roof.
static func _house(roll: int) -> Array:
	var list: Array = []
	var wood: int = [Blocks.PLANKS, Blocks.BIRCH_PLANKS, Blocks.DARK_PLANKS,
		Blocks.CHERRY_PLANKS][roll % 4]
	for y in range(0, 3):
		for x in range(-2, 3):
			for z in range(-2, 3):
				var edge: bool = absi(x) == 2 or absi(z) == 2
				if not edge:
					continue
				if z == -2 and x == 0 and y < 2:
					continue  # door
				if y == 1 and ((absi(x) == 2 and z == 0) or (z == 2 and x == 0)):
					list.append([Vector3i(x, y, z), Blocks.GLASS])
					continue
				_put(list, x, y, z, wood)
	for ring in range(0, 3):
		var size := 2 - ring
		for x in range(-size, size + 1):
			for z in range(-size, size + 1):
				if absi(x) == size or absi(z) == size or ring == 2:
					_put(list, x, 3 + ring, z, Blocks.BRICK)
	_put(list, 1, 2, 1, Blocks.LANTERN)
	return list

## 3x3 cobble tower with a lit lookout platform.
static func _tower() -> Array:
	var list: Array = []
	for y in range(0, 8):
		for x in range(-1, 2):
			for z in range(-1, 2):
				if absi(x) == 1 or absi(z) == 1:
					if y == 0 and z == -1 and x == 0:
						continue  # doorway
					_put(list, x, y, z, Blocks.COBBLE)
	# Stairs of blocks spiraling up the outside corner.
	var steps := [Vector3i(2, 0, 2), Vector3i(2, 1, 1), Vector3i(2, 2, 0),
		Vector3i(2, 3, -1), Vector3i(1, 4, -2), Vector3i(0, 5, -2),
		Vector3i(-1, 6, -2), Vector3i(-2, 7, -1)]
	for step in steps:
		list.append([step, Blocks.COBBLE])
	for x in range(-2, 3):
		for z in range(-2, 3):
			_put(list, x, 8, z, Blocks.PLANKS)
	for x in [-2, 2]:
		for z in [-2, 2]:
			_put(list, x, 9, z, Blocks.COBBLE)
	_put(list, 0, 9, 0, Blocks.LANTERN)
	return list

## A real canopy tree, far bigger than the saplings grow.
static func _big_tree(roll: int) -> Array:
	var list: Array = []
	var height := 10 + roll % 4
	for y in range(0, height):
		_put(list, 0, y, 0, Blocks.LOG)
		if y < 2:
			for off in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
				list.append([Vector3i(off.x, y, off.z), Blocks.LOG])
	for dy in range(-3, 4):
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var r := Vector3(dx, dy * 1.5, dz).length()
				if r <= 4.4 and (absi(dx) + absi(dz) + absi(dy)) > 0:
					list.append([Vector3i(dx, height - 1 + dy, dz), Blocks.LEAVES])
	return list

## A 9-long plank bridge with rails, spanning forward from the target.
static func _bridge() -> Array:
	var list: Array = []
	for z in range(0, -9, -1):
		for x in range(-1, 2):
			_put(list, x, 0, z, Blocks.PLANKS)
		if posmod(z, 2) == 0:
			_put(list, -2, 1, z, Blocks.LOG)
			_put(list, 2, 1, z, Blocks.LOG)
	_put(list, -2, 2, 0, Blocks.LANTERN)
	_put(list, 2, 2, -8, Blocks.LANTERN)
	return list

## Campfire, log seats and a little wool tent.
static func _camp() -> Array:
	var list: Array = []
	_put(list, 0, 0, 0, Blocks.CAMPFIRE)
	for off in [Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 0, 2)]:
		list.append([off, Blocks.LOG])
	for z in range(-3, -1):
		for x in range(-1, 2):
			_put(list, x, 0, z, Blocks.WOOL_RED if absi(x) == 1 else Blocks.AIR)
			_put(list, x, 1, z, Blocks.WOOL_RED if x == 0 else Blocks.AIR)
	list = list.filter(func(entry: Array) -> bool: return entry[1] != Blocks.AIR)
	return list

## Crenellated wall segment, 7 long and 3 high — fort building 101.
static func _wall() -> Array:
	var list: Array = []
	for x in range(-3, 4):
		for y in range(0, 3):
			_put(list, x, y, 0, Blocks.COBBLE)
		if posmod(x, 2) == 0:
			_put(list, x, 3, 0, Blocks.COBBLE)
	return list

## A sunken 5x5 pool with a marble rim.
static func _pool() -> Array:
	var list: Array = []
	for x in range(-2, 3):
		for z in range(-2, 3):
			if absi(x) == 2 or absi(z) == 2:
				_put(list, x, 0, z, Blocks.MARBLE)
			else:
				_put(list, x, 0, z, Blocks.WATER)
	return list

## Flowers, grass tufts and a berry bush in a ring.
static func _garden(roll: int) -> Array:
	var list: Array = []
	var flowers := [Blocks.FLOWER_RED, Blocks.FLOWER_YELLOW, Blocks.FLOWER_PINK, Blocks.TALL_GRASS]
	for x in range(-2, 3):
		for z in range(-2, 3):
			var pick := WorldGen.hash01(x + roll, z, 31)
			if pick < 0.55:
				_put(list, x, 0, z, flowers[int(pick * 20.0) % flowers.size()])
	_put(list, 0, 0, 0, Blocks.BERRY_BUSH)
	return list
