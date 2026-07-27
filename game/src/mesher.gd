class_name Mesher
extends RefCounted
## Turns raw chunk bytes into render surfaces. No textures anywhere: the look
## is vertex colors + per-face shading + baked ambient occlusion + a subtle
## per-position jitter, with the Forward+ pipeline (sun shadows, SSAO, glow,
## fog) doing the rest.
##
## Outputs three surfaces per chunk:
##   opaque  - solid cubes
##   plants  - crossed quads (flowers, grass tufts...), double-sided, swaying
##   trans   - water / glass / ice, translucent
## plus light spec dicts for blocks that cast real light (lantern, campfire).

const SIZE := WorldGen.CHUNK_SIZE
const H := WorldGen.CHUNK_H

## Baked face shading kept subtle - the sun and SSAO do the heavy lifting.
const SHADE_TOP := 1.0
const SHADE_BOTTOM := 0.62
const SHADE_X := 0.86
const SHADE_Z := 0.78
const AO_STEP := 0.16

## Cross-quad footprint (width, height) per plant so flowers read as flowers
## rather than block-sized billboards.
const CROSS_SIZES := {
	Blocks.FLOWER_RED: Vector2(0.5, 0.7),
	Blocks.FLOWER_YELLOW: Vector2(0.5, 0.65),
	Blocks.FLOWER_PINK: Vector2(0.5, 0.75),
	Blocks.TALL_GRASS: Vector2(0.9, 0.65),
	Blocks.MUSHROOM: Vector2(0.45, 0.5),
	Blocks.SAPLING: Vector2(0.6, 0.9),
	Blocks.SHELL: Vector2(0.4, 0.35),
	Blocks.BERRY_BUSH: Vector2(0.95, 0.9),
}

## Face table: [normal, u_axis, v_axis, shade]. Vertices are laid out
## (-u,-v) (+u,-v) (+u,+v) (-u,+v) around the face center.
static var FACES := [
	[Vector3i(0, 1, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 0), SHADE_TOP],
	[Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), SHADE_BOTTOM],
	[Vector3i(1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 0, 1), SHADE_X],
	[Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 1, 0), SHADE_X],
	[Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 1, 0), SHADE_Z],
	[Vector3i(0, 0, -1), Vector3i(0, 1, 0), Vector3i(1, 0, 0), SHADE_Z],
]

var _data: PackedByteArray
var _neighbors: Dictionary  # Vector2i (unit offsets) -> PackedByteArray

## Per-surface accumulation.
var _verts := {}
var _normals := {}
var _colors := {}
var _uv2s := {}
var _indices := {}
var lights: Array = []
var teleporters: Array = []   # local-space Vector3i of warp stones

func _init() -> void:
	for key in ["opaque", "plants", "trans"]:
		_verts[key] = PackedVector3Array()
		_normals[key] = PackedVector3Array()
		_colors[key] = PackedColorArray()
		_uv2s[key] = PackedVector2Array()
		_indices[key] = PackedInt32Array()

## Block lookup that sees one block into neighboring chunks.
func _block_at(x: int, y: int, z: int) -> int:
	if y < 0 or y >= H:
		return Blocks.AIR
	if x >= 0 and x < SIZE and z >= 0 and z < SIZE:
		return _data[(y * SIZE + z) * SIZE + x]
	var off := Vector2i(0, 0)
	if x < 0:
		off.x = -1
		x += SIZE
	elif x >= SIZE:
		off.x = 1
		x -= SIZE
	if z < 0:
		off.y = -1
		z += SIZE
	elif z >= SIZE:
		off.y = 1
		z -= SIZE
	var neighbor: PackedByteArray = _neighbors.get(off, PackedByteArray())
	if neighbor.is_empty():
		return Blocks.AIR
	return neighbor[(y * SIZE + z) * SIZE + x]

func _occludes(x: int, y: int, z: int) -> bool:
	return Blocks.is_opaque(_block_at(x, y, z))

## Build all surfaces for a chunk. cx/cz are only used to seed color jitter
## so the pattern doesn't repeat chunk to chunk.
func build(data: PackedByteArray, neighbors: Dictionary, cx: int, cz: int) -> Dictionary:
	_data = data
	_neighbors = neighbors
	for y in H:
		for z in SIZE:
			for x in SIZE:
				var block := int(_data[(y * SIZE + z) * SIZE + x])
				if block == Blocks.AIR:
					continue
				if Blocks.is_cross(block):
					_add_cross(block, x, y, z, cx, cz)
					continue
				if Blocks.is_translucent(block):
					_add_cube(block, x, y, z, cx, cz, "trans")
					continue
				_add_cube(block, x, y, z, cx, cz, "opaque")
				if block == Blocks.TELEPORT:
					teleporters.append(Vector3i(x, y, z))
				var light := Blocks.light_of(block)
				if light > 0.0:
					lights.append({
						"pos": Vector3(x + 0.5, y + 0.6, z + 0.5),
						"energy": light,
						"color": Blocks.color_of(block),
						"flicker": block == Blocks.CAMPFIRE,
					})
	var result := {}
	for key in ["opaque", "plants", "trans"]:
		if _indices[key].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _verts[key]
		arrays[Mesh.ARRAY_NORMAL] = _normals[key]
		arrays[Mesh.ARRAY_COLOR] = _colors[key]
		arrays[Mesh.ARRAY_TEX_UV2] = _uv2s[key]
		arrays[Mesh.ARRAY_INDEX] = _indices[key]
		result[key] = arrays
	result["lights"] = lights
	result["teleporters"] = teleporters
	return result

func _jitter(x: int, y: int, z: int, cx: int, cz: int) -> float:
	return 0.94 + 0.09 * WorldGen.hash01(cx * SIZE + x, cz * SIZE + z, y * 31)

func _add_cube(block: int, x: int, y: int, z: int, cx: int, cz: int, key: String) -> void:
	var base_color := Blocks.color_of(block)
	var top_color := Blocks.top_color_of(block)
	var jitter := _jitter(x, y, z, cx, cz)
	var sway := Blocks.sway_of(block)
	var emit := Blocks.emit_of(block)
	var translucent := key == "trans"
	var is_liquid := Blocks.is_liquid(block)
	# Liquids drop their surface a bit below the block top, like Minecraft.
	var top_y := 0.875 if is_liquid and _block_at(x, y + 1, z) != block else 1.0

	for face_index in 6:
		var face: Array = FACES[face_index]
		var n: Vector3i = face[0]
		var neighbor := _block_at(x + n.x, y + n.y, z + n.z)
		if translucent:
			# Translucent faces show against air/plants only — never against
			# the same material (no internal water walls) or opaque blocks.
			if neighbor == block or Blocks.is_opaque(neighbor):
				continue
			if is_liquid and neighbor == Blocks.ICE:
				continue
		else:
			if Blocks.is_opaque(neighbor):
				continue
		var u: Vector3i = face[1]
		var v: Vector3i = face[2]
		var shade: float = face[3]
		var color := top_color if n.y == 1 else base_color
		var origin := Vector3(x, y, z)
		var center := origin + Vector3(0.5, 0.5, 0.5) + Vector3(n) * 0.5
		var half_u := Vector3(u) * 0.5
		var half_v := Vector3(v) * 0.5

		# Ambient occlusion per corner (0 open .. 3 boxed in).
		var ao := PackedFloat32Array([0, 0, 0, 0])
		var corner_signs := [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]
		if not translucent:
			for i in 4:
				var cs: Vector2i = corner_signs[i]
				var s1 := _occludes(x + n.x + u.x * cs.x, y + n.y + u.y * cs.x, z + n.z + u.z * cs.x)
				var s2 := _occludes(x + n.x + v.x * cs.y, y + n.y + v.y * cs.y, z + n.z + v.z * cs.y)
				var c := _occludes(x + n.x + u.x * cs.x + v.x * cs.y,
					y + n.y + u.y * cs.x + v.y * cs.y, z + n.z + u.z * cs.x + v.z * cs.y)
				ao[i] = 3.0 if (s1 and s2) else float(int(s1) + int(s2) + int(c))

		var start: int = _verts[key].size()
		for i in 4:
			var cs: Vector2i = corner_signs[i]
			var vert := center + half_u * float(cs.x) + half_v * float(cs.y)
			if top_y != 1.0 and vert.y > y + top_y:
				vert.y = y + top_y
			_verts[key].append(vert)
			_normals[key].append(Vector3(n))
			var brightness := shade * jitter * (1.0 - AO_STEP * ao[i])
			var out := Color(color.r * brightness, color.g * brightness, color.b * brightness, color.a)
			_colors[key].append(out)
			# Leaves sway everywhere; liquids wave only on their surface.
			var vertex_sway := sway
			if is_liquid:
				vertex_sway = 1.0 if n.y == 1 else 0.0
			_uv2s[key].append(Vector2(vertex_sway, emit))
		# Flip the quad diagonal to match the AO gradient (kills the classic
		# voxel AO anisotropy artifact).
		# Godot front faces wind clockwise.
		if ao[0] + ao[2] <= ao[1] + ao[3]:
			for index in [0, 2, 1, 0, 3, 2]:
				_indices[key].append(start + index)
		else:
			for index in [1, 3, 2, 1, 0, 3]:
				_indices[key].append(start + index)

func _add_cross(block: int, x: int, y: int, z: int, cx: int, cz: int) -> void:
	var color := Blocks.color_of(block)
	var jitter := _jitter(x, y, z, cx, cz)
	var sway := Blocks.sway_of(block)
	var emit := Blocks.emit_of(block)
	var o := Vector3(x, y, z)
	var half: float = CROSS_SIZES.get(block, Vector2(0.6, 0.75)).x * 0.5
	var tall: float = CROSS_SIZES.get(block, Vector2(0.6, 0.75)).y
	var lo := 0.5 - half
	var hi := 0.5 + half
	var quads := [
		[o + Vector3(lo, 0, lo), o + Vector3(hi, 0, hi)],
		[o + Vector3(lo, 0, hi), o + Vector3(hi, 0, lo)],
	]
	for quad: Array in quads:
		var a: Vector3 = quad[0]
		var b: Vector3 = quad[1]
		# Plants use an UP normal so they're lit like the ground they grow
		# from instead of like little dark walls.
		var normal := Vector3.UP
		var start: int = _verts["plants"].size()
		var corners := [
			Vector3(a.x, y, a.z), Vector3(b.x, y, b.z),
			Vector3(b.x, y + tall, b.z), Vector3(a.x, y + tall, a.z),
		]
		for i in 4:
			_verts["plants"].append(corners[i])
			_normals["plants"].append(normal)
			var brightness := jitter * (0.85 if i < 2 else 1.0)
			_colors["plants"].append(Color(color.r * brightness, color.g * brightness, color.b * brightness))
			# Only the top two verts sway, so plants stay rooted.
			_uv2s["plants"].append(Vector2(sway if i >= 2 else 0.0, emit))
		for index in [0, 2, 1, 0, 3, 2]:
			_indices["plants"].append(start + index)
