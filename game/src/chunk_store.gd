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
	gen = WorldGen.new(seed_value, theme)
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
	config.save(data_dir.path_join("world.cfg"))
	# Remember which chunks already have edit files so misses stay cheap.
	var dir := DirAccess.open(data_dir.path_join("chunks"))
	if dir != null:
		for file in dir.get_files():
			if file.begins_with("c_") and file.ends_with(".bin"):
				var parts := file.trim_suffix(".bin").split("_")
				if parts.size() == 3:
					_edited[Vector2i(parts[1].to_int(), parts[2].to_int())] = true
	print("World store: source=%s seed=%d data=%s edited_chunks=%d" % [
		source, seed_value, data_dir, _edited.size()])

func in_bounds(cpos: Vector2i) -> bool:
	return absi(cpos.x) <= WORLD_RADIUS_CHUNKS and absi(cpos.y) <= WORLD_RADIUS_CHUNKS

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

## Wipe every edit and regenerate from a brand-new seed (map reset vote).
func reset_world(new_seed: int) -> void:
	_cache.clear()
	_dirty.clear()
	var dir := DirAccess.open(data_dir.path_join("chunks"))
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
	_edited.clear()
	# Every reset rolls a new theme too: classic island, desert with
	# explorable pyramids, ship-dotted isles, or castle-lands.
	var themes := ["classic", "classic", "desert", "isles", "castles"]
	theme = themes[randi() % themes.size()]
	gen = WorldGen.new(new_seed, theme)
	mca = null
	source = "procedural"
	var config := ConfigFile.new()
	config.load(data_dir.path_join("world.cfg"))
	config.set_value("world", "seed", new_seed)
	config.set_value("world", "source", source)
	config.set_value("world", "theme", theme)
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
