extends SceneTree
## Offline importer: real Minecraft structure blocks (.nbt) -> a generated
## src/structures_imported.gd that the Kits picker stamps into the world.
##
## We use .nbt (and, later, Sponge .schem) rather than MagicaVoxel .vox
## because they carry real Minecraft BLOCK TYPES — oak planks, cobble,
## stairs, glass — which map onto our palette through McaWorld.map_entry()
## and stay diggable. A .vox would import as anonymous coloured cubes.
##
##   WORLD_NBT_DIR=<dir of .nbt>  WORLD_NBT_BY="Author"
##   WORLD_NBT_LICENSE=MIT        WORLD_NBT_SOURCE=<url>
##   WORLD_NBT_OUT=<abs path to structures_imported.gd>
##   godot --headless --path <game> --script res://tests/import_structures.gd
##
## Anything taller or wider than the caps below is skipped: a kit has to be
## something a child can stamp down and walk around, not a whole village.

const MAX_W := 26
const MAX_H := 30
const MAX_CELLS := 9000

## Hand-picked from the pack: a spread of ideas a child would want to
## stamp down — houses, a stable, a library, wells, ponds, shrines and
## temples — each small enough to place and walk into.
const WANTED := [
	"temple/shrine",
	"temple/temple_cherry",
	"temple/temple_plains",
	"temple/temple_snow",
	"temple/temple_snowyplains",
	"village/ganlan/buildings/ganlan_house_1",
	"village/ganlan/buildings/ganlan_house_2",
	"village/ganlan/buildings/ganlan_house_6",
	"village/ganlan/buildings/ganlan_shrine",
	"village/ganlan/decor/ganlan_pond",
	"village/grotto/buildings/yaodong_1",
	"village/grotto/buildings/yaodong_2",
	"village/grotto/center/grotto_well",
	"village/hui/hui_pond_1",
	"village/hui/plains_blacksmith_1",
	"village/hui/plains_butcher_1",
	"village/hui/plains_fisher_cottage_1",
	"village/hui/plains_hotel_1",
	"village/hui/plains_library_1",
	"village/hui/plains_mid_house_1",
	"village/hui/plains_small_house_1",
	"village/hui/plains_stable_1",
	"village/hui/plains_temple_1",
	"village/hui/plains_town_center_1",
	"village/hui/plains_well_1",
	"village/yurt/buildings/yurt_03",
	"village/yurt/buildings/yurt_05",
	"village/yurt/buildings/yurt_stable_01",
]

## Friendlier names than the datapack's filenames.
const RENAME := {
	"shrine": "Stone Shrine",
	"temple cherry": "Cherry Temple",
	"temple plains": "Meadow Temple",
	"temple snow": "Snow Temple",
	"temple snowyplains": "Little Snow Shrine",
	"ganlan house 1": "Stilt House",
	"ganlan house 2": "Big Stilt House",
	"ganlan house 6": "Stilt Hut",
	"ganlan shrine": "Wooden Shrine",
	"ganlan pond": "Lily Pond",
	"yaodong 1": "Cave House",
	"yaodong 2": "Cave Dwelling",
	"grotto well": "Deep Well",
	"hui pond 1": "Koi Pond",
	"plains blacksmith 1": "Blacksmith",
	"plains butcher 1": "Butcher",
	"plains fisher cottage 1": "Fisher Cottage",
	"plains hotel 1": "Inn",
	"plains library 1": "Library",
	"plains mid house 1": "Town House",
	"plains small house 1": "Little Cottage",
	"plains stable 1": "Stable",
	"plains temple 1": "Village Temple",
	"plains town center 1": "Town Square",
	"plains well 1": "Village Well",
	"yurt 03": "Yurt",
	"yurt 05": "Small Yurt",
	"yurt stable 01": "Yurt Stable",
}

var _nbt := McaWorld.new("")

func _initialize() -> void:
	var dir := OS.get_environment("WORLD_NBT_DIR")
	var out := OS.get_environment("WORLD_NBT_OUT")
	var by := OS.get_environment("WORLD_NBT_BY")
	var license := OS.get_environment("WORLD_NBT_LICENSE")
	var source := OS.get_environment("WORLD_NBT_SOURCE")
	if dir.is_empty() or out.is_empty():
		push_error("WORLD_NBT_DIR and WORLD_NBT_OUT are required")
		quit(1)
		return
	var files := _find_nbt(dir)
	print("found %d .nbt under %s" % [files.size(), dir])
	var entries: Array = []
	var skipped: Array = []
	for path: String in files:
		var rel := path.trim_prefix(dir).trim_prefix("/").trim_suffix(".nbt")
		if OS.get_environment("WORLD_NBT_ALL") != "1" \
				and not WANTED.is_empty() and not WANTED.has(rel):
			continue
		var built := _import_one(path, rel)
		if built.is_empty():
			skipped.append(rel)
			continue
		built["by"] = by
		built["license"] = license
		built["source"] = source
		entries.append(built)
		print("  %-40s %s  %d cells" % [rel, built.size_v, built.count])
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.id) < str(b.id))
	_write(out, entries, by, license, source)
	print("wrote %s: %d kits (%d skipped: %s)" % [out, entries.size(),
		skipped.size(), ", ".join(skipped)])
	quit()

func _find_nbt(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	da.list_dir_begin()
	var name := da.get_next()
	while not name.is_empty():
		var path := dir.path_join(name)
		if da.current_is_dir():
			out.append_array(_find_nbt(path))
		elif name.ends_with(".nbt"):
			out.append(path)
		name = da.get_next()
	da.list_dir_end()
	out.sort()
	return out

## Structure-block .nbt: gzipped NBT holding `size` (3 ints), a `palette`
## of block states and `blocks` as {state, pos} — no bit-packing to undo,
## unlike the chunk sections McaWorld normally reads.
func _import_one(path: String, rel: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var raw := file.get_buffer(file.get_length())
	var plain := raw.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
	if plain.is_empty():
		return {}
	var stream := StreamPeerBuffer.new()
	stream.data_array = plain
	stream.big_endian = true
	# Root is an unnamed TAG_Compound wrapper.
	if stream.get_u8() != McaWorld.TAG_COMPOUND:
		return {}
	var _root_name := _read_string(stream)
	var root: Dictionary = _nbt._read_compound(stream)
	var size: Array = root.get("size", [])
	var palette: Array = root.get("palette", [])
	var blocks: Array = root.get("blocks", [])
	if size.size() != 3 or palette.is_empty() or blocks.is_empty():
		return {}
	var sx := int(size[0])
	var sy := int(size[1])
	var sz := int(size[2])
	if sx > MAX_W or sz > MAX_W or sy > MAX_H or sx < 2 or sz < 2:
		return {}
	# Map the palette once, then every block is a lookup.
	var mapped: Array = []
	for entry in palette:
		mapped.append(McaWorld.map_entry(entry as Dictionary))
	var raw_cells: Array = []
	var min_y := 1 << 30
	for b in blocks:
		var pos: Array = (b as Dictionary).get("pos", [])
		if pos.size() != 3:
			continue
		var block: int = mapped[int((b as Dictionary).get("state", 0))]
		if block == Blocks.AIR:
			continue
		# Centre on x/z so a kit stamps around the player's target.
		raw_cells.append([int(pos[0]) - sx / 2, int(pos[1]),
			int(pos[2]) - sz / 2, block])
		min_y = mini(min_y, int(pos[1]))
		if raw_cells.size() > MAX_CELLS:
			return {}
	if raw_cells.size() < 30:
		return {}
	# Sit the kit ON the ground. Some builds (the cave dwellings, the deep
	# well) have their lowest block well above the structure block's own
	# origin, and stamped as-is they hovered in mid-air.
	# The block the build is mostly made of, so the picker tile can wear
	# the build's own colour instead of 28 identical tan squares.
	var max_y := 0
	for c: Array in raw_cells:
		max_y = maxi(max_y, int(c[1]))
	var tally := {}
	var roof_tally := {}
	for c: Array in raw_cells:
		var b := int(c[3])
		if b == Blocks.GRASS or b == Blocks.DIRT or Blocks.is_liquid(b):
			continue
		tally[b] = int(tally.get(b, 0)) + 1
		if int(c[1]) >= max_y - maxi(1, (max_y - min_y) / 5):
			roof_tally[b] = int(roof_tally.get(b, 0)) + 1
	var top := _most_common(tally, Blocks.PLANKS)
	# Roofs on these builds are usually a different material from the
	# walls, which is what makes one picker tile tell from another.
	var roof := _most_common(roof_tally, top)
	var cells := PackedByteArray()
	for c: Array in raw_cells:
		cells.append(int(c[0]) + 128)
		cells.append(int(c[1]) - min_y)
		cells.append(int(c[2]) + 128)
		cells.append(int(c[3]))
	var count := raw_cells.size()
	return {
		"id": "mc_" + rel.replace("/", "_"),
		"name": _pretty(rel),
		"size_v": Vector3i(sx, sy, sz),
		"count": count,
		"top": top,
		"roof": roof,
		"data": Marshalls.raw_to_base64(cells),
	}

static func _most_common(tally: Dictionary, fallback: int) -> int:
	var best := 0
	var winner := fallback
	for b: int in tally:
		if int(tally[b]) > best:
			best = int(tally[b])
			winner = b
	return winner

func _read_string(stream: StreamPeerBuffer) -> String:
	var length := stream.get_u16()
	return "" if length == 0 else stream.get_utf8_string(length)

func _pretty(rel: String) -> String:
	var leaf := rel.get_file().replace("_", " ")
	if RENAME.has(leaf):
		return str(RENAME[leaf])
	var words := leaf.split(" ")
	var out: Array = []
	for w: String in words:
		out.append(w.capitalize() if w.length() > 1 else w.to_upper())
	return " ".join(out)

func _write(out: String, entries: Array, by: String, license: String,
		source: String) -> void:
	var text := """class_name StructuresImported
## GENERATED by tests/import_structures.gd — do not edit by hand.
##
## Real Minecraft builds (structure-block .nbt) mapped onto our palette,
## so they arrive as oak planks, cobble, stairs and glass rather than
## anonymous coloured cubes — and stay diggable like anything else.
##
## Source: %s
## Author: %s   License: %s
##
## Each kit's cells are packed 4 bytes per block: x+128, y, z+128, block.

const KITS := [
""" % [source, by, license]
	for entry: Dictionary in entries:
		text += '\t{"id": "%s", "name": "%s", "by": "%s", "license": "%s",\n' % [
			entry.id, entry.name, by, license]
		text += '\t\t"size": Vector3i%s, "cells": %d, "top": %d, "roof": %d,\n' % [
			str(entry.size_v), entry.count, entry.top, entry.roof]
		text += '\t\t"data": "%s"},\n' % entry.data
	text += "]\n"
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(text)
	file.close()
