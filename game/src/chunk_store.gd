class_name ChunkStore
extends RefCounted
## Server-side authoritative world storage. Chunks come from one of two
## sources — the procedural generator or a read-only Minecraft world — and
## every edited chunk is persisted to the data dir as its own zstd blob, so
## the source world is never modified and the server can restart freely.
##
## Layout on disk (WORLD_DATA_DIR, default user://world):
##   world.cfg          seed, source, world clock
##   chunks/c_X_Z.bin   zstd-compressed block bytes for edited chunks

const RAW_CHUNK_BYTES := WorldGen.CHUNK_SIZE * WorldGen.CHUNK_SIZE * WorldGen.CHUNK_H
## Chunks farther than this (in chunks) from the origin are ocean border.
const WORLD_RADIUS_CHUNKS := 24

var data_dir: String
var source := "procedural"  # or "mca"
var theme := "classic"
## Side of the square world, in blocks — a size of 50 is a 50x50 slab
## centred on the origin. Changing it regenerates the world, because the
## terrain itself is cut to this shape.
var world_size := 250
var gen: WorldGen
var mca: McaWorld = null

var _cache: Dictionary = {}       # Vector2i -> PackedByteArray
var _dirty: Dictionary = {}       # Vector2i -> true (needs saving)
var _edited: Dictionary = {}      # Vector2i -> true (has a disk file)

func _init() -> void:
	data_dir = OS.get_environment("WORLD_DATA_DIR")
	if data_dir.is_empty():
		data_dir = "user://world"
	DirAccess.make_dir_recursive_absolute(data_dir.path_join("chunks"))
	var config := ConfigFile.new()
	config.load(data_dir.path_join("world.cfg"))
	source = OS.get_environment("WORLD_SOURCE")
	if source.is_empty():
		source = str(config.get_value("world", "source", "procedural"))
	var seed_env := OS.get_environment("WORLD_SEED")
	var seed_value: int
	if seed_env.is_valid_int():
		seed_value = seed_env.to_int()
	else:
		seed_value = int(config.get_value("world", "seed", 20260726))
	theme = OS.get_environment("WORLD_THEME")
	if theme.is_empty():
		theme = str(config.get_value("world", "theme", "classic"))
	world_size = int(config.get_value("world", "size", world_size))
	gen = WorldGen.new(seed_value, theme, world_size)
	if source == "mca":
		var mca_dir := OS.get_environment("WORLD_MCA_DIR")
		mca = McaWorld.new(mca_dir)
		if not mca.is_valid():
			push_error("WORLD_SOURCE=mca but no region files at '%s'; falling back to procedural" % mca_dir)
			source = "procedural"
			mca = null
	config.set_value("world", "seed", seed_value)
	config.set_value("world", "source", source)
	config.set_value("world", "theme", theme)
	config.set_value("world", "size", world_size)
	config.save(data_dir.path_join("world.cfg"))
	# Worlds are ephemeral: block edits never survive a restart — every
	# boot starts from clean generation (only SETTINGS persist). This
	# also means a crash can't strand everyone in a half-eaten map.
	var dir := DirAccess.open(data_dir.path_join("chunks"))
	if dir != null:
		for file in dir.get_files():
			if file.begins_with("c_") and file.ends_with(".bin"):
				dir.remove(file)
	# ...and saved positions must die with the world they were valid in —
	# restoring an old position into fresh terrain buried players alive.
	var boot_players := ConfigFile.new()
	boot_players.load(data_dir.path_join("players.cfg"))
	for section in boot_players.get_sections():
		if boot_players.has_section_key(section, "pos"):
			boot_players.erase_section_key(section, "pos")
	boot_players.save(data_dir.path_join("players.cfg"))
	print("World store: source=%s seed=%d data=%s edited_chunks=%d" % [
		source, seed_value, data_dir, _edited.size()])

func in_bounds(cpos: Vector2i) -> bool:
	return absi(cpos.x) <= WORLD_RADIUS_CHUNKS and absi(cpos.y) <= WORLD_RADIUS_CHUNKS

## Half the slab, in blocks. The world is a square `world_size` on a side
## centred on the origin, so anything placed outside ±this is off the map.
func half_extent() -> int:
	return world_size / 2

## THE bounds check for anything the server puts in the world — crates,
## kits, animals, structures, players at the drop. Everything used to
## work off its own radius (the storm's, the arena's, a hard-coded
## number), and on a small world those all reached past the edge of the
## slab and dropped things into the void.
##
## `margin` keeps a thing clear of the very edge, so a crate is never
## half-buried in the border wall.
func inside_world(wx: int, wz: int, margin := 2) -> bool:
	var limit := half_extent() - margin
	return absi(wx) <= limit and absi(wz) <= limit

## The same point, pulled back inside the slab instead of rejected. Use
## this where a thing MUST exist somewhere (a player's drop) rather than
## where it can simply be skipped (one crate out of forty).
func clamp_inside(pos: Vector3, margin := 3) -> Vector3:
	var limit := float(half_extent() - margin)
	return Vector3(clampf(pos.x, -limit, limit), pos.y,
		clampf(pos.z, -limit, limit))

## Cut ONE way out of a crater — a narrow ramp, nothing more.
##
## The job is to stop a blast trapping somebody, and that is all. An
## earlier version of this relaxed the whole heightmap around the crater
## until no column stood more than a block above its neighbour, which
## does guarantee escape — by flattening a bowl two radii wide. A big
## shooter round ate hundreds of blocks and left a smooth circular arena.
## That is far more destructive than the explosion it was meant to be
## cleaning up after, and it is not what a crater should look like.
##
## So instead: find the crater floor, pick the direction where the
## surrounding ground sits LOWEST, and cut a three-wide furrow out that
## way, rising one block per step until it meets ground level. Escape is
## guaranteed by construction — every step of the ramp is exactly one
## block above the last — and the cost is a few dozen blocks in one
## direction rather than everything in a circle.
##
## Returns what it cleared, for broadcasting.
func carve_exit_ramp(origin: Vector3i, radius: float) -> Array:
	var cleared: Array = []
	# The crater floor: fall down the origin column through the hole the
	# blast just made.
	var floor_y := origin.y
	while floor_y > 2 and get_block(Vector3i(origin.x, floor_y - 1, origin.z)) == Blocks.AIR:
		floor_y -= 1
	var reach := int(ceil(radius)) + 2
	# Out towards the lowest ground: the shortest ramp, and the one that
	# looks most like the blast simply threw the dirt that way.
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	var best_dir: Vector2i = dirs[0]
	var best_h := 1 << 30
	for d: Vector2i in dirs:
		var h := surface_y(origin.x + d.x * reach, origin.z + d.y * reach)
		if h < best_h:
			best_h = h
			best_dir = d
	var perp := Vector2i(-best_dir.y, best_dir.x)
	# Walk outwards keeping a promise: each column along the way is at
	# most ONE block higher than the one before it. Following the real
	# height of the previous column is the whole trick — an earlier
	# version compared against an idealised "floor + step" line instead,
	# which rises even while the crater floor is flat, so by the time it
	# reached the rim the budget was already generous enough to accept a
	# two-block wall and it cut nothing at all.
	var prev := surface_y(origin.x, origin.z)
	for step in range(1, reach + int(ceil(radius)) + 6):
		var cx := origin.x + best_dir.x * step
		var cz := origin.z + best_dir.y * step
		var ground := surface_y(cx, cz)
		var want := prev + 1
		if ground > want:
			for w: int in [-1, 0, 1]:
				var px: int = cx + perp.x * w
				var pz: int = cz + perp.y * w
				var col_top := surface_y(px, pz)
				for y in range(want + 1, col_top + 1):
					var pos := Vector3i(px, y, pz)
					var block := get_block(pos)
					if block == Blocks.AIR:
						continue
					# Steel and diamond stop the ramp dead, same as they
					# stop the blast. Better a short ramp than a hole
					# through a vault door.
					if not Blocks.is_breakable(block) or Blocks.hardness(block) >= 3:
						break
					set_block(pos, Blocks.AIR)
					cleared.append(pos)
			ground = mini(ground, want)
		prev = ground
		# Past the rim and standing on ground that needed no help: the
		# way out is complete.
		if float(step) > radius and ground <= want:
			break
	return cleared

func get_chunk(cpos: Vector2i) -> PackedByteArray:
	if _cache.has(cpos):
		return _cache[cpos]
	var data: PackedByteArray
	if _edited.has(cpos):
		data = _load_chunk_file(cpos)
	if data.is_empty():
		if not in_bounds(cpos):
			data = _border_chunk()
		elif mca != null:
			data = mca.read_chunk(cpos.x, cpos.y)
			if data.is_empty():
				data = _border_chunk()
		else:
			data = gen.generate_chunk(cpos.x, cpos.y)
	_cache[cpos] = data
	return data

## Compressed payload for the wire.
func get_chunk_compressed(cpos: Vector2i) -> PackedByteArray:
	return get_chunk(cpos).compress(FileAccess.COMPRESSION_ZSTD)

func get_block(pos: Vector3i) -> int:
	if pos.y < 0 or pos.y >= WorldGen.CHUNK_H:
		return Blocks.AIR
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	var data := get_chunk(cpos)
	var lx := posmod(pos.x, 16)
	var lz := posmod(pos.z, 16)
	return data[WorldGen.idx(lx, pos.y, lz)]

func set_block(pos: Vector3i, block: int) -> void:
	if pos.y <= 0 or pos.y >= WorldGen.CHUNK_H:
		return
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	if not in_bounds(cpos):
		return
	var data := get_chunk(cpos)
	var lx := posmod(pos.x, 16)
	var lz := posmod(pos.z, 16)
	data[WorldGen.idx(lx, pos.y, lz)] = block
	_cache[cpos] = data
	_dirty[cpos] = true
	_edited[cpos] = true

## Top solid/water surface for spawning things on.
func surface_y(wx: int, wz: int) -> int:
	var cpos := Vector2i(floori(wx / 16.0), floori(wz / 16.0))
	var data := get_chunk(cpos)
	var lx := posmod(wx, 16)
	var lz := posmod(wz, 16)
	for y in range(WorldGen.CHUNK_H - 1, -1, -1):
		var b := data[WorldGen.idx(lx, y, lz)]
		if b != Blocks.AIR and not Blocks.is_cross(b):
			return y
	return 0

func find_spawn() -> Vector3i:
	if mca != null:
		return mca.find_spawn()
	return gen.find_spawn()

## Where imported Minecraft maps live (env override, docker, or repo dir).
static func maps_root() -> String:
	var override := OS.get_environment("WORLD_MCA_DIR")
	if not override.is_empty():
		return override
	for candidate in ["/opt/world/maps",
			ProjectSettings.globalize_path("res://").path_join("../maps")]:
		if DirAccess.dir_exists_absolute(candidate):
			return candidate
	return "maps"

## The map library: loose region files = "Ian's World"; each subfolder
## with .mca files inside = its own selectable map (name from map.cfg).
static func list_maps() -> Array:
	var out: Array = []
	var root := maps_root()
	var dir := DirAccess.open(root)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".mca"):
			out.append({"key": "mca", "name": "Ian's World"})
			break
	for sub in dir.get_directories():
		var sub_dir := DirAccess.open(root.path_join(sub))
		if sub_dir == null:
			continue
		var has_region := false
		for file in sub_dir.get_files():
			if file.ends_with(".mca"):
				has_region = true
				break
		if not has_region and DirAccess.dir_exists_absolute(root.path_join(sub).path_join("region")):
			has_region = true
		if has_region:
			var map_cfg := ConfigFile.new()
			map_cfg.load(root.path_join(sub).path_join("map.cfg"))
			out.append({"key": "mca:" + sub,
				"name": str(map_cfg.get_value("map", "name", sub.capitalize()))})
	return out

## Wipe every edit and regenerate from a brand-new seed (map reset vote).
func reset_world(new_seed: int, map_name := "", new_size := 0) -> void:
	if new_size > 0:
		world_size = new_size
	_cache.clear()
	_dirty.clear()
	var dir := DirAccess.open(data_dir.path_join("chunks"))
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
	_edited.clear()
	_apply_map(map_name, new_seed)

## Wipe edits and switch to a chosen theme, or "mca" for an imported
## Minecraft map (Ian's world in maps/).
func set_map(map_name: String, new_seed: int) -> void:
	reset_world(new_seed, map_name)

var current_map_key := ""

func _apply_map(map_name: String, new_seed: int) -> void:
	if map_name.is_empty():
		map_name = WorldGen.THEMES[randi() % WorldGen.THEMES.size()]
	current_map_key = map_name
	if map_name == "mca" or map_name.begins_with("mca:"):
		source = "mca"
		var mca_dir := maps_root()
		if map_name.begins_with("mca:"):
			mca_dir = mca_dir.path_join(map_name.trim_prefix("mca:"))
		mca = McaWorld.new(mca_dir)
		if mca.is_valid():
			# Per-map settings, else Ian's-world defaults.
			var map_cfg := ConfigFile.new()
			map_cfg.load(mca_dir.path_join("map.cfg"))
			mca.center = Vector2i(
				int(map_cfg.get_value("map", "center_x", 256)),
				int(map_cfg.get_value("map", "center_z", 256)))
			mca.y0 = int(map_cfg.get_value("map", "y0", mca.y0))
		else:
			push_error("No importable map found at '%s'" % mca_dir)
			source = "procedural"
			mca = null
	else:
		source = "procedural"
		mca = null
		theme = map_name
	gen = WorldGen.new(new_seed, theme, world_size)
	var config := ConfigFile.new()
	config.load(data_dir.path_join("world.cfg"))
	config.set_value("world", "seed", new_seed)
	config.set_value("world", "source", source)
	config.set_value("world", "theme", theme)
	config.set_value("world", "size", world_size)
	config.save(data_dir.path_join("world.cfg"))
	# Forget saved positions (treasures survive).
	var players := ConfigFile.new()
	players.load(data_dir.path_join("players.cfg"))
	for section in players.get_sections():
		if players.has_section_key(section, "pos"):
			players.erase_section_key(section, "pos")
	players.save(data_dir.path_join("players.cfg"))

func save_dirty() -> int:
	var saved := 0
	for cpos: Vector2i in _dirty.keys():
		var file := FileAccess.open(_chunk_path(cpos), FileAccess.WRITE)
		if file != null:
			file.store_buffer(_cache[cpos].compress(FileAccess.COMPRESSION_ZSTD))
			file.close()
			saved += 1
	_dirty.clear()
	# Keep memory bounded on long-running servers: drop far, clean chunks.
	if _cache.size() > 1400:
		for cpos: Vector2i in _cache.keys():
			if not _dirty.has(cpos) and _cache.size() > 1000:
				_cache.erase(cpos)
	return saved

func _chunk_path(cpos: Vector2i) -> String:
	return data_dir.path_join("chunks/c_%d_%d.bin" % [cpos.x, cpos.y])

func _load_chunk_file(cpos: Vector2i) -> PackedByteArray:
	var file := FileAccess.open(_chunk_path(cpos), FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var blob := file.get_buffer(file.get_length())
	file.close()
	var data := blob.decompress(RAW_CHUNK_BYTES, FileAccess.COMPRESSION_ZSTD)
	if data.size() != RAW_CHUNK_BYTES:
		push_error("Corrupt chunk file %s" % _chunk_path(cpos))
		return PackedByteArray()
	return data

## Open ocean for everything outside the playable radius / missing MCA chunks.
func _border_chunk() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(RAW_CHUNK_BYTES)
	for lz in 16:
		for lx in 16:
			data[WorldGen.idx(lx, 0, lz)] = Blocks.BEDROCK
			for y in range(1, 12):
				data[WorldGen.idx(lx, y, lz)] = Blocks.STONE
			for y in range(12, WorldGen.SEA_LEVEL + 1):
				data[WorldGen.idx(lx, y, lz)] = Blocks.WATER
	return data
