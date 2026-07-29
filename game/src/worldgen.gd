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
var _caves2 := FastNoiseLite.new()
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
	_caves2.seed = p_seed + 608
	_caves2.frequency = 0.045
	_caves2.fractal_octaves = 2
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
	if theme == "city":
		return clampi(SEA_LEVEL + 4 + int(detail * 1.2), 2, CHUNK_H - 12)
	if theme == "sky":
		# Skylands: a shallow ocean below, all the action up on the islands.
		return clampi(SEA_LEVEL - 3 + int(detail * 0.8), 2, CHUNK_H - 12)
	if theme == "desert":
		# Flat rolling dunes well above the water table.
		var dune := 14.0 + (base * 18.0 + hills * hills * 30.0) * falloff + detail * 1.8
		return clampi(int(SEA_LEVEL + 4.0 + maxf(dune - SEA_LEVEL, 0.0) * 0.35), 2, CHUNK_H - 12)
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
				if h > SEA_LEVEL + 2 and h + 1 < CHUNK_H and hash01(wx, wz, 61) < 0.015:
					data[idx(lx, h + 1, lz)] = Blocks.DEAD_BUSH
			elif h == SEA_LEVEL + 1 and h + 1 < CHUNK_H and hash01(wx, wz, 62) < 0.1:
				data[idx(lx, h + 1, lz)] = Blocks.CATTAIL
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
	# Two noise worms whose intersection is a CONNECTED tunnel network you
	# can actually run through, plus vast cheese caverns lower down with
	# water pools on their floors.
	for y in range(4, h - 3):
		var carve := false
		if absf(_caves.get_noise_3d(wx, y * 1.6, wz)) < 0.085 \
				and absf(_caves2.get_noise_3d(wx, y * 1.6, wz)) < 0.085:
			carve = true
		elif y < 22 and _caves.get_noise_3d(wx * 0.5, y * 1.1, wz * 0.5) > 0.52:
			carve = true
		if carve:
			data[idx(lx, y, lz)] = Blocks.WATER if y <= 8 else Blocks.AIR
	# Walkable funnel entrances from the surface on a wide grid.
	var ax := roundi(float(wx - 48) / 96.0) * 96 + 48
	var az := roundi(float(wz - 48) / 96.0) * 96 + 48
	if hash01(ax, az, 909) < 0.4:
		var dist := Vector2(wx - ax, wz - az).length()
		if dist < 9.0:
			for y in range(maxi(4, h - 9 + int(dist)), h + 1):
				data[idx(lx, y, lz)] = Blocks.AIR
	# Stalagmites, stalactites, crystals, glowstone and mushrooms.
	for y in range(5, h - 3):
		if data[idx(lx, y, lz)] != Blocks.AIR:
			continue
		var roll := hash01(wx, y, wz * 7)
		if data[idx(lx, y - 1, lz)] == Blocks.STONE:
			if roll < 0.02:
				var crystals := [Blocks.CRYSTAL_PINK, Blocks.CRYSTAL_BLUE, Blocks.CRYSTAL_GREEN]
				data[idx(lx, y, lz)] = crystals[int(roll * 150.0) % 3]
			elif roll < 0.03:
				data[idx(lx, y - 1, lz)] = Blocks.GLOWSTONE
			elif roll < 0.05:
				data[idx(lx, y, lz)] = Blocks.MUSHROOM
			elif roll < 0.1:
				data[idx(lx, y, lz)] = Blocks.COBBLE  # stalagmite
		elif y + 1 < CHUNK_H and data[idx(lx, y + 1, lz)] == Blocks.STONE and roll > 0.94:
			data[idx(lx, y, lz)] = Blocks.COBBLE  # stalactite

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
	if theme == "city":
		_city_column(data, lx, lz, wx, wz, h)
		return
	if theme == "castles":
		_megacastle_column(data, lx, lz, wx, wz, h)
		return
	if theme == "desert" and roll < 0.65:
		# Pyramids sit ON the dunes: base from the terrain at their center,
		# and never in the water.
		var base := height_at(cx, cz)
		if base <= SEA_LEVEL + 1:
			return
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
	elif false:
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

## CITY: a street grid with procedural buildings, sidewalks and glass.
func _city_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int) -> void:
	if Vector2(wx, wz).length() > ISLAND_RADIUS - 40.0 or h <= SEA_LEVEL:
		return
	var street_x := posmod(wx, 26)
	var street_z := posmod(wz, 26)
	# Wide roads every 26 blocks, with a paler sidewalk strip on the edges.
	if street_x < 6 or street_z < 6:
		var sidewalk: bool = street_x == 5 or street_z == 5 \
			or street_x == 0 or street_z == 0
		data[idx(lx, h, lz)] = Blocks.SANDSTONE if sidewalk else Blocks.PATH
		for y in range(h + 1, mini(h + 8, CHUNK_H)):
			data[idx(lx, y, lz)] = Blocks.AIR
		# Traffic lights at every intersection corner.
		if street_x == 1 and street_z == 1:
			for k in range(1, 4):
				data[idx(lx, h + k, lz)] = Blocks.SLATE
			if h + 6 < CHUNK_H:
				data[idx(lx, h + 4, lz)] = Blocks.WOOL_GREEN
				data[idx(lx, h + 5, lz)] = Blocks.WOOL_YELLOW
				data[idx(lx, h + 6, lz)] = Blocks.WOOL_RED
		# Street lamps midway along blocks.
		elif street_x == 2 and street_z == 13:
			for k in range(1, 5):
				data[idx(lx, h + k, lz)] = Blocks.SLATE if k < 4 else Blocks.LANTERN
		return
	# City lot: one building per 22-grid cell, inset 2 from streets.
	var bx := floori(wx / 26.0)
	var bz := floori(wz / 26.0)
	var build_roll := hash01(bx, bz, 800)
	if build_roll < 0.42 and build_roll >= 0.3:
		# Car park: striped lot with chunky parked cars.
		if h + 2 >= CHUNK_H:
			return
		data[idx(lx, h, lz)] = Blocks.PATH
		if posmod(street_z, 4) == 0 and street_x > 7 and street_x < 24:
			data[idx(lx, h, lz)] = Blocks.SANDSTONE  # painted stripe
		# Cars: 2x3 colored boxes with a glass cabin, in neat rows.
		var carx := posmod(street_x - 8, 5)
		var carz := posmod(street_z - 8, 4)
		if street_x >= 8 and street_x <= 22 and street_z >= 8 and street_z <= 22 \
				and carx < 2 and carz < 3 \
				and hash01(bx * 40 + (street_x - 8) / 5, bz * 40 + (street_z - 8) / 4, 812) < 0.6:
			var paint: int = [Blocks.WOOL_RED, Blocks.WOOL_BLUE, Blocks.WOOL_YELLOW,
				Blocks.WOOL_GREEN][int(hash01(bx * 40 + (street_x - 8) / 5,
				bz * 40 + (street_z - 8) / 4, 813) * 4.0)]
			data[idx(lx, h + 1, lz)] = paint
			if carz == 1:
				data[idx(lx, h + 2, lz)] = Blocks.GLASS  # cabin
		return
	if build_roll < 0.3:
		# Park lot: grass, flowers and little bushes break up the blocks.
		var proll := hash01(wx, wz, 806)
		if h + 2 < CHUNK_H:
			if proll < 0.012:
				data[idx(lx, h + 1, lz)] = Blocks.LEAVES
				data[idx(lx, h + 2, lz)] = Blocks.LEAVES
			elif proll < 0.06:
				data[idx(lx, h + 1, lz)] = Blocks.TALL_GRASS
			elif proll < 0.09:
				data[idx(lx, h + 1, lz)] = [Blocks.FLOWER_RED,
					Blocks.FLOWER_YELLOW, Blocks.FLOWER_PINK][int(proll * 100.0) % 3]
		return
	# Every building gets its own footprint and height.
	var inset := 7 + int(hash01(bx, bz, 804) * 4.0)
	var height := 5 + int(hash01(bx, bz, 801) * 22.0)
	if street_x < inset or street_z < inset \
			or street_x > 31 - inset or street_z > 31 - inset:
		return  # sidewalk margin
	var wall: bool = street_x == inset or street_z == inset \
		or street_x == 31 - inset or street_z == 31 - inset
	# Interior features: a staircase lane along one wall (climb a block per
	# step, hole in each slab above the top step) and, in towers, an open
	# lift shaft in the far corner — grapple straight up it.
	var stair: int = -1
	if (street_x == inset + 1 or street_x == inset + 2) \
			and street_z > inset and street_z <= inset + 4:
		stair = street_z - inset  # steps 1..4, then land on the slab itself
	var stair_hole: bool = (street_x == inset + 1 or street_x == inset + 2) \
		and street_z >= inset + 2 and street_z <= inset + 4
	var shaft: bool = height > 16 \
		and street_x >= 29 - inset and street_x <= 30 - inset \
		and street_z >= 29 - inset and street_z <= 30 - inset
	var material: int = [Blocks.BRICK, Blocks.MARBLE, Blocks.SLATE, Blocks.SANDSTONE][int(hash01(bx, bz, 802) * 4.0)]
	for k in range(1, height + 1):
		var y := h + k
		if y >= CHUNK_H - 2:
			break
		if wall:
			# Window bands, with the odd ivy patch creeping up the side.
			var window: bool = k % 3 != 1 and posmod(wx + wz, 3) != 0
			if not window and hash01(wx, wz + k, 805) < 0.07:
				data[idx(lx, y, lz)] = Blocks.LEAVES
			else:
				data[idx(lx, y, lz)] = Blocks.GLASS if window else material
		elif k == height:
			# Roof — shaft and stairwell stay open so you can reach the top.
			if shaft or stair_hole:
				data[idx(lx, y, lz)] = Blocks.AIR
			else:
				data[idx(lx, y, lz)] = material
				# Rooftop gardens on some buildings.
				if y + 1 < CHUNK_H - 1 and hash01(bx, bz, 808) < 0.35 \
						and hash01(wx, wz, 809) < 0.2:
					data[idx(lx, y + 1, lz)] = Blocks.TALL_GRASS
		elif shaft:
			# Open shaft all the way up, glowstone marking each floor.
			data[idx(lx, y, lz)] = Blocks.GLOWSTONE if k % 5 == 0 \
				and street_x == 29 - inset and street_z == 29 - inset else Blocks.AIR
		elif stair >= 0 and k % 5 == stair:
			# Staircase: one step per level, repeating every floor.
			data[idx(lx, y, lz)] = Blocks.PLANKS
		elif k % 5 == 0:
			# Real floors every five levels, with stairwell holes.
			data[idx(lx, y, lz)] = Blocks.AIR if stair_hole else Blocks.PLANKS
		elif k % 5 == 1 and hash01(wx, wz, 810) < 0.02:
			data[idx(lx, y, lz)] = Blocks.GLOWSTONE
		else:
			data[idx(lx, y, lz)] = Blocks.AIR
	# Rooftop lantern sometimes.
	if wall and hash01(wx, wz, 803) < 0.02 and h + height + 1 < CHUNK_H:
		data[idx(lx, h + height + 1, lz)] = Blocks.LANTERN

## CASTLES: one enormous central castle — curtain walls, corner towers,
## and a tall keep with floors you can fight through.
func _megacastle_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int, h: int) -> void:
	var m := maxi(absi(wx), absi(wz))
	if h <= SEA_LEVEL:
		return
	# Curtain wall ring at |max| = 56..58, height 10, gate on the north.
	if m >= 56 and m <= 58:
		var gate: bool = wz <= -56 and absi(wx) <= 3
		if not gate:
			for k in range(1, 11):
				if h + k < CHUNK_H:
					var crenel: bool = k == 10 and posmod(wx + wz, 2) == 1
					if not crenel:
						data[idx(lx, h + k, lz)] = Blocks.COBBLE
		return
	# Corner towers.
	if absi(absi(wx) - 57) <= 4 and absi(absi(wz) - 57) <= 4:
		var tower_r := maxi(absi(absi(wx) - 57), absi(absi(wz) - 57))
		if tower_r <= 4:
			for k in range(1, 16):
				if h + k >= CHUNK_H:
					break
				if tower_r >= 3 or k >= 14:
					data[idx(lx, h + k, lz)] = Blocks.COBBLE
				else:
					data[idx(lx, h + k, lz)] = Blocks.AIR
			if tower_r == 0 and h + 16 < CHUNK_H:
				data[idx(lx, h + 16, lz)] = Blocks.LANTERN
		return
	# The keep: 24x24 at the center — a real great hall, not bumpy terrain.
	# Everything sits on a FLAT court at a fixed height: marble floor, red
	# carpet from the gate to a golden throne, banners, chandeliers, and
	# the staircase up through every floor.
	if m <= 12:
		var base := 28
		if h > base + 20:
			return
		for fy in range(mini(h, base), base):
			data[idx(lx, fy, lz)] = Blocks.STONE  # foundation up to the court
		for k in range(0, 27):
			var y := base + k
			if y >= CHUNK_H - 1:
				break
			var shell: bool = m >= 11
			var floor_slab: bool = k % 6 == 0 and k > 0
			var door: bool = wz <= -11 and absi(wx) <= 2 and k >= 1 and k <= 4
			var window: bool = shell and k % 6 >= 2 and k % 6 <= 3 and posmod(wx + wz, 4) == 0
			var stair_step := -1
			if (wx == 9 or wx == 10) and wz >= 3 and wz <= 7:
				stair_step = wz - 2  # 1..5, then land on the slab
			var stair_hole: bool = (wx == 9 or wx == 10) and wz >= 5 and wz <= 7
			var carpet: bool = absi(wx) <= 1 and wz >= -10 and wz <= 6
			var throne: bool = absi(wx) <= 1 and wz >= 8 and wz <= 9
			if door:
				data[idx(lx, y, lz)] = Blocks.AIR
			elif shell:
				data[idx(lx, y, lz)] = Blocks.GLASS if window else Blocks.STONE
			elif k == 0:
				data[idx(lx, y, lz)] = Blocks.WOOL_RED if carpet else Blocks.MARBLE
			elif throne and (k <= 2 or (k == 3 and wz == 9)):
				data[idx(lx, y, lz)] = Blocks.GOLD
			elif stair_step > 0 and k % 6 == stair_step % 6 and not floor_slab:
				data[idx(lx, y, lz)] = Blocks.PLANKS
			elif floor_slab:
				data[idx(lx, y, lz)] = Blocks.AIR if stair_hole else Blocks.PLANKS
			elif k % 6 == 5 and absi(wx) <= 1 and absi(wz) <= 1:
				data[idx(lx, y, lz)] = Blocks.GLOWSTONE  # chandeliers
			elif m == 10 and k % 6 >= 2 and k % 6 <= 4 and posmod(wx + 3 * wz, 9) == 0:
				data[idx(lx, y, lz)] = Blocks.WOOL_RED  # hall banners
			else:
				data[idx(lx, y, lz)] = Blocks.AIR
		# Clear terrain or trees poking through above the roof.
		for cy in range(base + 27, mini(h + 8, CHUNK_H)):
			data[idx(lx, cy, lz)] = Blocks.AIR
		return

## Rare floating islands high above the world — fly up and explore. Grass
## on top, a crystal heart inside the bigger ones.
func _sky_island(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int) -> void:
	if theme == "sky":
		_skylands_column(data, lx, lz, wx, wz)
		return
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

## SKYLANDS: floating islands with jittered positions, a mix of small and
## MEGA islands, satellites stacked above the big ones (with waterfalls
## pouring between them), and gentle parabolic plank bridges.
func _sky_params(gx: int, gz: int) -> Dictionary:
	if hash01(gx, gz, 950) >= 0.75 and not (gx == 0 and gz == 0):
		return {}
	var mega := hash01(gx, gz, 955) < 0.15 and not (gx == 0 and gz == 0)
	return {
		"ax": gx * 48 + int((hash01(gx, gz, 956) - 0.5) * 20.0),
		"az": gz * 48 + int((hash01(gx, gz, 957) - 0.5) * 20.0),
		"r": (18.0 + hash01(gx, gz, 951) * 8.0) if mega else (7.0 + hash01(gx, gz, 951) * 7.0),
		"top": 34 + int(hash01(gx, gz, 952) * 22.0),
		"mega": mega,
	}

func _stamp_island(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int,
		ax: int, az: int, r: float, top: int) -> void:
	var dist := Vector2(wx - ax, wz - az).length()
	if dist >= r or top >= CHUNK_H - 2:
		return
	var depth := int((r - dist) * 0.7) + 1
	data[idx(lx, top, lz)] = Blocks.GRASS
	for dy in range(1, depth + 1):
		if top - dy > SEA_LEVEL + 4:
			data[idx(lx, top - dy, lz)] = Blocks.DIRT if dy == 1 else Blocks.STONE
	var roll := hash01(wx, wz, 46)
	if roll < 0.04:
		data[idx(lx, top + 1, lz)] = [Blocks.FLOWER_PINK,
			Blocks.FLOWER_RED, Blocks.BLUEBELL][int(roll * 100.0) % 3]
	elif roll < 0.1:
		data[idx(lx, top + 1, lz)] = Blocks.TALL_GRASS

func _skylands_column(data: PackedByteArray, lx: int, lz: int, wx: int, wz: int) -> void:
	var gx := roundi(float(wx) / 48.0)
	var gz := roundi(float(wz) / 48.0)
	for dgx in range(gx - 1, gx + 2):
		for dgz in range(gz - 1, gz + 2):
			var p := _sky_params(dgx, dgz)
			if p.is_empty():
				continue
			_stamp_island(data, lx, lz, wx, wz, p.ax, p.az, p.r, p.top)
			# Mega islands carry a small satellite floating above them.
			if p.mega:
				var sat_x: int = p.ax + int((hash01(dgx, dgz, 958) - 0.5) * 16.0)
				var sat_z: int = p.az + int((hash01(dgx, dgz, 959) - 0.5) * 16.0)
				var sat_top: int = p.top + 13
				_stamp_island(data, lx, lz, wx, wz, sat_x, sat_z, 5.5, sat_top)
				# A waterfall pours off the satellite onto the big island.
				if wx == sat_x + 2 and wz == sat_z:
					for y in range(p.top + 1, mini(sat_top, CHUNK_H - 1)):
						if data[idx(lx, y, lz)] == Blocks.AIR:
							data[idx(lx, y, lz)] = Blocks.WATER
			# Waterfall off one rim point of some islands.
			if hash01(dgx, dgz, 953) < 0.35:
				var fall_a := hash01(dgx, dgz, 954) * TAU
				var fx: int = p.ax + int(cos(fall_a) * (p.r - 1.5))
				var fz: int = p.az + int(sin(fall_a) * (p.r - 1.5))
				if wx == fx and wz == fz:
					for y in range(SEA_LEVEL - 1, p.top + 1):
						if data[idx(lx, y, lz)] == Blocks.AIR:
							data[idx(lx, y, lz)] = Blocks.WATER
			# Bridges to the +x and +z neighbor islands.
			for step_axis in 2:
				var np := _sky_params(dgx + (1 if step_axis == 0 else 0),
					dgz + (0 if step_axis == 0 else 1))
				if np.is_empty():
					continue
				var a_pos := Vector2(p.ax, p.az)
				var b_pos := Vector2(np.ax, np.az)
				var seg := b_pos - a_pos
				if seg.length_squared() < 1.0:
					continue
				var t := clampf((Vector2(wx, wz) - a_pos).dot(seg) / seg.length_squared(), 0.0, 1.0)
				var closest := a_pos + seg * t
				if Vector2(wx, wz).distance_to(closest) < 1.0 and t > 0.02 and t < 0.98:
					var by := int(lerpf(float(p.top), float(np.top), t) - 3.0 * sin(PI * t))
					if by > SEA_LEVEL and by < CHUNK_H - 4 \
							and data[idx(lx, by, lz)] == Blocks.AIR:
						data[idx(lx, by, lz)] = Blocks.PLANKS

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
			elif hash01(wx, wz, 14) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.DAISY
			elif hash01(wx, wz, 15) < 0.02:
				data[idx(lx, ground + 1, lz)] = Blocks.BLUEBELL
		Biome.FOREST:
			if interior and tree_roll < 0.03:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 0)
			elif hash01(wx, wz, 9) < 0.1:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 12) < 0.007:
				data[idx(lx, ground + 1, lz)] = Blocks.MUSHROOM
			elif hash01(wx, wz, 14) < 0.08:
				data[idx(lx, ground + 1, lz)] = Blocks.FERN
		Biome.PINE:
			if lx >= 2 and lx < 14 and lz >= 2 and lz < 14 and tree_roll < 0.05:
				_plant_tree(data, lx, ground + 1, lz, hash01(wx, wz, 8), 2)
			elif hash01(wx, wz, 9) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.TALL_GRASS
			elif hash01(wx, wz, 14) < 0.05:
				data[idx(lx, ground + 1, lz)] = Blocks.FERN
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
			elif hash01(wx, wz, 16) < 0.06:
				data[idx(lx, ground + 1, lz)] = Blocks.WHEAT_PLANT
			elif hash01(wx, wz, 17) < 0.03:
				data[idx(lx, ground + 1, lz)] = Blocks.BLUEBELL
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
	if theme == "sky":
		# The (0,0) island always exists; land on top of it.
		return Vector3i(0, 36 + int(hash01(0, 0, 952) * 22.0), 0)
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
