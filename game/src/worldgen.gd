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
var theme := "classic"   # classic / desert / isles / castles

enum Biome { MEADOW, FOREST, JUNGLE, PINE, FLOWERS, SWAMP }

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _moisture := FastNoiseLite.new()
var _temperature := FastNoiseLite.new()
var _lakes := FastNoiseLite.new()
var _caves := FastNoiseLite.new()
var _sky := FastNoiseLite.new()

func _init(p_seed: int, p_theme := "classic") -> void:
	seed_value = p_seed
	theme = p_theme
	_continent.seed = p_seed
	_continent.frequency = 0.004
	_continent.fractal_octaves = 3
	_hills.seed = p_seed + 101
	_hills.frequency = 0.012
	_hills.fractal_octaves = 4
	_detail.seed = p_seed + 202
	_detail.frequency = 0.06
	_detail.fractal_octaves = 2
	# Small biome patches (~40-70 blocks) so a walk crosses several: dense
	# jungle into pine grove into flower field.
	_moisture.seed = p_seed + 303
	_moisture.frequency = 0.018
	_moisture.fractal_octaves = 2
	_temperature.seed = p_seed + 505
	_temperature.frequency = 0.016
	_temperature.fractal_octaves = 2
	_lakes.seed = p_seed + 404
	_lakes.frequency = 0.02
	_lakes.fractal_octaves = 2
	_caves.seed = p_seed + 606
	_caves.frequency = 0.05
	_caves.fractal_octaves = 2
	_sky.seed = p_seed + 707
	_sky.frequency = 0.011
	_sky.fractal_octaves = 2

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
	if theme == "isles":
		# Mostly ocean, steep little islands everywhere.
		var bump := maxf(0.0, hills - 0.58) * 110.0
		return clampi(int(16.0 + bump * falloff + detail * 1.2), 2, CHUNK_H - 12)
	var h := 14.0 + (base * 18.0 + hills * hills * 30.0) * falloff + detail * 1.8
	return clampi(int(h), 2, CHUNK_H - 12)

func moisture_at(wx: int, wz: int) -> float:
	return _moisture.get_noise_2d(wx, wz) * 0.5 + 0.5

func biome_at(wx: int, wz: int, h: int) -> int:
	var moist := moisture_at(wx, wz)
	var temp := _temperature.get_noise_2d(wx, wz) * 0.5 + 0.5
	if moist > 0.52 and h <= SEA_LEVEL + 2:
		return Biome.SWAMP
	if moist > 0.6 and temp > 0.55:
		return Biome.JUNGLE
	if moist > 0.55:
		return Biome.FOREST
	if temp < 0.36 and moist < 0.5:
		return Biome.PINE
	if temp > 0.5 and moist > 0.38:
		return Biome.FLOWERS
	return Biome.MEADOW

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
			if theme == "desert":
				for y in range(1, h + 1):
					var b := data[idx(lx, y, lz)]
					if b == Blocks.GRASS or b == Blocks.DIRT:
						data[idx(lx, y, lz)] = Blocks.SAND if y == h else Blocks.SANDSTONE
			_carve_caves(data, lx, lz, wx, wz, h)
			_sky_island(data, lx, lz, wx, wz)
			_landmark_column(data, lx, lz, wx, wz, h)
	_scatter_features(data, cx, cz)
	return data

## Winding underground caverns, lit by crystals and glowstone. Only under
## dry land (never below sea/lakes, so nothing floods).
func _carve_caves(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int) -> void:
	if h <= SEA_LEVEL + 1:
		return
	for y in range(4, h - 3):
		if _caves.get_noise_3d(wx, y * 1.4, wz) > 0.56:
			data[idx(lx, y, lz)] = Blocks.AIR
	# Decorate fresh cave floors.
	for y in range(5, h - 3):
		if data[idx(lx, y, lz)] == Blocks.AIR and data[idx(lx, y - 1, lz)] == Blocks.STONE:
			var roll := hash01(wx, y, wz * 7)
			if roll < 0.02:
				var crystals := [Blocks.CRYSTAL_PINK, Blocks.CRYSTAL_BLUE, Blocks.CRYSTAL_GREEN]
				data[idx(lx, y, lz)] = crystals[int(roll * 150.0) % 3]
			elif roll < 0.028:
				data[idx(lx, y - 1, lz)] = Blocks.GLOWSTONE
			elif roll < 0.05:
				data[idx(lx, y, lz)] = Blocks.MUSHROOM

## Theme landmarks are laid out on a 96-block anchor grid; each column asks
## the pure landmark function what it contributes, so structures far bigger
## than one chunk generate seamlessly: hollow desert pyramids you can
## explore, castle walls in castle-lands, wooden ships among the isles.
func _landmark_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int) -> void:
	var ax := floori(wx / 96.0)
	var az := floori(wz / 96.0)
	var roll := hash01(ax, az, 900)
	var cx := ax * 96 + 48
	var cz := az * 96 + 48
	var dx := wx - cx
	var dz := wz - cz
	if Vector2(cx, cz).length() > ISLAND_RADIUS - 30.0:
		return
	if theme == "desert" and roll < 0.65:
		var base := SEA_LEVEL + 2
		var size := 14 + int(hash01(ax, az, 901) * 6.0)
		var m := maxi(absi(dx), absi(dz))
		if m > size:
			return
		for k in range(0, size + 1):
			if m > size - k:
				continue
			var y := base + k
			if y >= CHUNK_H:
				break
			var shell: bool = m == size - k or k == 0
			# Entrance tunnel at ground level on the north face.
			if k <= 2 and dz == -(size - k) and absi(dx) <= 1:
				shell = false
			if shell:
				data[idx(lx, y, lz)] = Blocks.SANDSTONE
			else:
				data[idx(lx, y, lz)] = Blocks.AIR
				if k % 5 == 1 and hash01(wx, wz, 902 + k) < 0.02:
					data[idx(lx, y, lz)] = Blocks.GLOWSTONE
	elif theme == "castles" and roll < 0.45:
		var m := maxi(absi(dx), absi(dz))
		var wall_r := 13
		if m == wall_r or (absi(dx) >= wall_r - 1 and absi(dz) >= wall_r - 1 and m <= wall_r + 1):
			var tower: bool = absi(dx) >= wall_r - 1 and absi(dz) >= wall_r - 1
			var height := 8 if tower else 5
			if not tower and dz == -wall_r and absi(dx) <= 1:
				height = 0  # gate
			for k in range(1, height + 1):
				if h + k < CHUNK_H:
					var crenel: bool = k == height and not tower and posmod(wx + wz, 2) == 1
					if not crenel:
						data[idx(lx, h + k, lz)] = Blocks.COBBLE
			if tower and h + 9 < CHUNK_H:
				data[idx(lx, h + 9, lz)] = Blocks.LANTERN
	elif theme == "isles" and roll < 0.6 and h < SEA_LEVEL - 3:
		# A wooden ship at anchor.
		if absi(dx) > 7 or absi(dz) > 3:
			return
		var hull_w := 3 - maxi(0, absi(dx) - 5)
		if absi(dz) > hull_w:
			return
		var deck := SEA_LEVEL + 1
		for y in range(SEA_LEVEL - 1, deck):
			if absi(dz) == hull_w or absi(dx) == 7:
				data[idx(lx, y, lz)] = Blocks.DARK_PLANKS
			else:
				data[idx(lx, y, lz)] = Blocks.AIR
		data[idx(lx, deck, lz)] = Blocks.PLANKS
		if dx == 0 and dz == 0:
			for k in range(1, 9):
				data[idx(lx, deck + k, lz)] = Blocks.LOG
		elif dz == 0 and absi(dx) <= 3 and dx != 0:
			for k in range(3, 8):
				data[idx(lx, deck + k, lz)] = Blocks.WOOL_WHITE
		elif absi(dx) == 7 and dz == 0:
			data[idx(lx, deck + 1, lz)] = Blocks.LANTERN

## Rare floating islands high above the world — fly up and explore. Grass
## on top, a crystal heart inside the bigger ones.
func _sky_island(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int) -> void:
	var n := _sky.get_noise_2d(wx, wz) * 0.5 + 0.5
	if n < 0.8:
		return
	var body := (n - 0.8) * 40.0   # 0..~4 thickness
	var top := 66
	data[idx(lx, top, lz)] = Blocks.GRASS
	for dy in range(1, int(body) + 1):
		data[idx(lx, top - dy, lz)] = Blocks.DIRT if dy == 1 else Blocks.STONE
	if body > 2.5 and hash01(wx, wz, 44) < 0.1:
		var crystals := [Blocks.CRYSTAL_PINK, Blocks.CRYSTAL_BLUE, Blocks.CRYSTAL_GREEN]
		data[idx(lx, top - 2, lz)] = crystals[int(hash01(wx, wz, 45) * 3.0)]
	var roll := hash01(wx, wz, 46)
	if roll < 0.05:
		data[idx(lx, top + 1, lz)] = Blocks.FLOWER_PINK
	elif roll < 0.09:
		data[idx(lx, top + 1, lz)] = Blocks.TALL_GRASS

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
			if surface == Blocks.GRASS:
				_scatter_grass_column(data, lx, lz, wx, wz, ground)
			elif surface == Blocks.SAND and ground <= SEA_LEVEL + 2:
				if hash01(wx, wz, 15) < 0.008:
					data[idx(lx, ground + 1, lz)] = Blocks.SHELL

## Per-biome surface decoration. Trees only fully inside the chunk so
## canopies never cross borders (generation stays independent per chunk).
func _scatter_grass_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, ground: int) -> void:
	var biome := biome_at(wx, wz, ground)
	var interior := lx >= 3 and lx < 13 and lz >= 3 and lz < 13
	var tree_roll := hash01(wx, wz, 7)
	match biome:
		Biome.SWAMP:
			if hash01(wx, wz, 20) < 0.14:
				data[idx(lx, ground, lz)] = Blocks.WATER
				return
			if hash01(wx, wz, 12) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.MUSHROOM
			elif hash01(wx, wz, 9) < 0.16:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif interior and tree_roll < 0.012:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
		Biome.JUNGLE:
			if lx >= 4 and lx < 12 and lz >= 4 and lz < 12 and tree_roll < 0.09:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 1)
			elif hash01(wx, wz, 9) < 0.22:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 12) < 0.012:
				data[idx(lx, ground + 1, lz)] = Blocks.MUSHROOM
			elif hash01(wx, wz, 10) < 0.02:
				data[idx(lx, ground + 1, lz)] = Blocks.FLOWER_PINK
		Biome.FOREST:
			if interior and tree_roll < 0.03:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
			elif hash01(wx, wz, 9) < 0.1:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 12) < 0.007:
				data[idx(lx, ground + 1, lz)] = Blocks.MUSHROOM
		Biome.PINE:
			if lx >= 2 and lx < 14 and lz >= 2 and lz < 14 and tree_roll < 0.05:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 2)
			elif hash01(wx, wz, 9) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
		Biome.FLOWERS:
			if hash01(wx, wz, 10) < 0.15:
				var pick := hash01(wx, wz, 11)
				var flower := Blocks.FLOWER_RED
				if pick > 0.66:
					flower = Blocks.FLOWER_PINK
				elif pick > 0.33:
					flower = Blocks.FLOWER_YELLOW
				data[idx(lx, ground + 1, lz)] = flower
			elif hash01(wx, wz, 9) < 0.08:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 13) < 0.01:
				data[idx(lx, ground + 1, lz)] = Blocks.BERRY_BUSH
			elif interior and tree_roll < 0.004:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
		_:
			# Shooter cover: rare ruined wall stubs and stone crags.
			if interior and hash01(wx, wz, 50) < 0.0012:
				var h := 2 + int(hash01(wx, wz, 51) * 3.0)
				for dy in h:
					if hash01(wx, dy, wz) < 0.8:
						data[idx(lx, ground + 1 + dy, lz)] = Blocks.COBBLE
				if lx < 13:
					data[idx(lx + 1, ground + 1, lz)] = Blocks.COBBLE
				return
			if interior and hash01(wx, wz, 52) < 0.0012:
				for dy in 3 + int(hash01(wx, wz, 53) * 4.0):
					data[idx(lx, ground + 1 + dy, lz)] = Blocks.STONE
				return
			if interior and tree_roll < 0.006:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
			elif hash01(wx, wz, 9) < 0.05:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 10) < 0.02:
				var pick := hash01(wx, wz, 11)
				data[idx(lx, ground + 1, lz)] = Blocks.FLOWER_YELLOW if pick > 0.5 else Blocks.FLOWER_RED
			elif hash01(wx, wz, 13) < 0.004:
				data[idx(lx, ground + 1, lz)] = Blocks.BERRY_BUSH
			elif hash01(wx, wz, 14) < 0.0016:
				data[idx(lx, ground + 1, lz)] = Blocks.PUMPKIN

## Highest non-air, non-water block of a local column (during generation).
func _surface_of(data: PackedByteArray, lx: int, lz: int) -> int:
	for y in range(CHUNK_H - 1, -1, -1):
		var b := data[idx(lx, y, lz)]
		if b != Blocks.AIR and b != Blocks.WATER:
			return y
	return -1

## kind: 0 = oak blob, 1 = tall wide jungle canopy, 2 = narrow pine.
func _plant_tree(data: PackedByteArray, lx: int, base_y: int, lz: int, size_roll: float, kind := 0) -> void:
	var trunk := 3 + int(size_roll * 3.0)
	var radius := 2.45
	var squash := 1.4
	if kind == 1:
		trunk = 7 + int(size_roll * 4.0)
		radius = 3.4
		squash = 2.0
	elif kind == 2:
		trunk = 5 + int(size_roll * 3.0)
		radius = 1.4
		squash = 0.8
	if base_y + trunk + 3 >= CHUNK_H:
		return
	for i in trunk:
		data[idx(lx, base_y + i, lz)] = Blocks.LOG
	var top := base_y + trunk
	var reach := int(ceil(radius))
	for dy in range(-2, 3):
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var r := Vector3(dx, dy * squash, dz).length()
				if r > radius:
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
