class_name WorldGen
extends RefCounted
## Deterministic procedural island generator (server-side only). Chunks are
## 16x16 columns of CHUNK_H blocks; index = (y * 16 + z) * 16 + x.
##
## The world is a big friendly island ringed by ocean: meadows and forests
## in the middle, beaches at the shore, rolling stone hills with snow caps,
## a few lakes. Scatter (trees, flowers, crit-treats) is hash-based so the
## same seed always builds the same world.

const CHUNK_SIZE := 16
const CHUNK_H := 80
const SEA_LEVEL := 24
## Playable radius in blocks; beyond it the terrain sinks into open ocean.
const ISLAND_RADIUS := 220.0

var seed_value: int

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _lakes := FastNoiseLite.new()

func _init(p_seed: int) -> void:
	seed_value = p_seed
	_continent.seed = p_seed
	_continent.frequency = 0.004
	_continent.fractal_octaves = 3
	_hills.seed = p_seed + 101
	_hills.frequency = 0.012
	_hills.fractal_octaves = 4
	_detail.seed = p_seed + 202
	_detail.frequency = 0.06
	_detail.fractal_octaves = 2
	_moisture.seed = p_seed + 303
	_moisture.frequency = 0.008
	_moisture.fractal_octaves = 2
	_lakes.seed = p_seed + 404
	_lakes.frequency = 0.02
	_lakes.fractal_octaves = 2

## Deterministic per-position hash in [0, 1).
static func hash01(x: int, z: int, salt: int) -> float:
	var h := int(x) * 374761393 + int(z) * 668265263 + salt * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)

## Terrain height at a world column, before carving lakes.
func height_at(wx: int, wz: int) -> int:
	var dist := Vector2(wx, wz).length()
	# Island falloff: 1 in the middle, 0 past the radius.
	var falloff := clampf(1.0 - (dist / ISLAND_RADIUS) * (dist / ISLAND_RADIUS), 0.0, 1.0)
	var base := _continent.get_noise_2d(wx, wz) * 0.5 + 0.5      # 0..1
	var hills := _hills.get_noise_2d(wx, wz) * 0.5 + 0.5
	var detail := _detail.get_noise_2d(wx, wz)
	# Ocean floor ~14, beaches just above sea, hills up to ~+30 over sea.
	var h := 14.0 + (base * 18.0 + hills * hills * 30.0) * falloff + detail * 1.8
	return clampi(int(h), 2, CHUNK_H - 12)

func moisture_at(wx: int, wz: int) -> float:
	return _moisture.get_noise_2d(wx, wz) * 0.5 + 0.5

## Lake carving: dips terrain below sea level inland where the lake noise
## peaks (only where the land is low-ish already, so hills keep their shape).
func lake_depth_at(wx: int, wz: int, h: int) -> int:
	if h > SEA_LEVEL + 8:
		return 0
	var n := _lakes.get_noise_2d(wx, wz)
	if n < 0.45:
		return 0
	return int((n - 0.45) * 26.0)

## Fill a chunk's blocks. Returns a PackedByteArray of CHUNK_SIZE^2 * CHUNK_H.
func generate_chunk(cx: int, cz: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(CHUNK_SIZE * CHUNK_SIZE * CHUNK_H)
	for lz in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var wx := cx * CHUNK_SIZE + lx
			var wz := cz * CHUNK_SIZE + lz
			var h := height_at(wx, wz)
			h -= lake_depth_at(wx, wz, h)
			var moist := moisture_at(wx, wz)
			_fill_column(data, lx, lz, wx, wz, h, moist)
	_scatter_features(data, cx, cz)
	return data

static func idx(lx: int, y: int, lz: int) -> int:
	return (y * CHUNK_SIZE + lz) * CHUNK_SIZE + lx

func _fill_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int, moist: float) -> void:
	var snow_line := SEA_LEVEL + 22
	var beach_top := SEA_LEVEL + 2
	for y in range(0, mini(h + 1, CHUNK_H)):
		var block := Blocks.STONE
		if y == 0:
			block = Blocks.BEDROCK
		elif y > h - 3 and h <= beach_top:
			block = Blocks.SAND
		elif y == h:
			if h >= snow_line:
				block = Blocks.SNOW
			elif h >= snow_line - 6:
				block = Blocks.STONE
			else:
				block = Blocks.GRASS
		elif y > h - 4:
			block = Blocks.DIRT if h < snow_line - 6 else Blocks.STONE
		data[idx(lx, y, lz)] = block
	# Water fills anything below sea level.
	for y in range(h + 1, SEA_LEVEL + 1):
		if y < CHUNK_H:
			data[idx(lx, y, lz)] = Blocks.WATER

## Surface decoration: trees, flowers, grass tufts, shells, mushrooms,
## pumpkins, berry bushes. All placement is hash-driven per world column.
func _scatter_features(data: PackedByteArray, cx: int, cz: int) -> void:
	for lz in CHUNK_SIZE:
		for lx in CHUNK_SIZE:
			var wx := cx * CHUNK_SIZE + lx
			var wz := cz * CHUNK_SIZE + lz
			var ground := _surface_of(data, lx, lz)
			if ground <= 0 or ground + 1 >= CHUNK_H:
				continue
			var surface := data[idx(lx, ground, lz)]
			var moist := moisture_at(wx, wz)
			if surface == Blocks.GRASS:
				var forest := moist > 0.55
				# Trees only fully inside the chunk so canopies never cross
				# chunk borders (keeps generation independent per chunk).
				if forest and lx >= 2 and lx < 14 and lz >= 2 and lz < 14 \
						and hash01(wx, wz, 7) < 0.028:
					_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8))
				elif hash01(wx, wz, 9) < (0.10 if forest else 0.05):
					data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
				elif hash01(wx, wz, 10) < 0.022:
					var pick := hash01(wx, wz, 11)
					var flower := Blocks.FLOWER_RED
					if pick > 0.66:
						flower = Blocks.FLOWER_PINK
					elif pick > 0.33:
						flower = Blocks.FLOWER_YELLOW
					data[idx(lx, ground + 1, lz)] = flower
				elif forest and hash01(wx, wz, 12) < 0.006:
					data[idx(lx, ground + 1, lz)] = Blocks.MUSHROOM
				elif not forest and hash01(wx, wz, 13) < 0.004:
					data[idx(lx, ground + 1, lz)] = Blocks.BERRY_BUSH
				elif not forest and hash01(wx, wz, 14) < 0.0016:
					data[idx(lx, ground + 1, lz)] = Blocks.PUMPKIN
			elif surface == Blocks.SAND and ground <= SEA_LEVEL + 2:
				if hash01(wx, wz, 15) < 0.008:
					data[idx(lx, ground + 1, lz)] = Blocks.SHELL

## Highest non-air, non-water block of a local column (during generation).
func _surface_of(data: PackedByteArray, lx: int, lz: int) -> int:
	for y in range(CHUNK_H - 1, -1, -1):
		var b := data[idx(lx, y, lz)]
		if b != Blocks.AIR and b != Blocks.WATER:
			return y
	return -1

func _plant_tree(data: PackedByteArray, lx: int, base_y: int, lz: int, size_roll: float) -> void:
	var trunk := 3 + int(size_roll * 3.0)
	if base_y + trunk + 3 >= CHUNK_H:
		return
	for i in trunk:
		data[idx(lx, base_y + i, lz)] = Blocks.LOG
	var top := base_y + trunk
	# Rounded leaf blob.
	for dy in range(-2, 3):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var r := Vector3(dx, dy * 1.4, dz).length()
				if r > 2.45:
					continue
				var px := lx + dx
				var pz := lz + dz
				var py := top + dy
				if px < 0 or px >= CHUNK_SIZE or pz < 0 or pz >= CHUNK_SIZE:
					continue
				if py <= 0 or py >= CHUNK_H:
					continue
				if data[idx(px, py, pz)] == Blocks.AIR:
					data[idx(px, py, pz)] = Blocks.LEAVES

## A decent spawn: walk outward from the middle until we find grass above sea
## level. Returns the block position of the ground (players stand on top).
func find_spawn() -> Vector3i:
	for radius in range(0, 12):
		for attempt in 24:
			var angle := hash01(radius, attempt, 55) * TAU
			var wx := int(cos(angle) * radius * 8.0)
			var wz := int(sin(angle) * radius * 8.0)
			var h := height_at(wx, wz)
			h -= lake_depth_at(wx, wz, h)
			if h > SEA_LEVEL + 1 and h < SEA_LEVEL + 14:
				return Vector3i(wx, h, wz)
	return Vector3i(0, height_at(0, 0), 0)
