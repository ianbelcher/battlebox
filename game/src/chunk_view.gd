class_name ChunkView
extends Node3D
## Client-side chunk manager: keeps the blocks around the local players
## resident, meshes them (a few per frame so streaming never hitches), spawns
## real OmniLights for lanterns/campfires, and answers collision queries for
## the hand-rolled player physics.

## Chunks kept meshed around each local player; the split screen raises this
## when someone zooms far out so the horizon fills in.
var view_radius := 5
## During matches everything stays resident (prefetched in the lobby).
var match_mode := false
const MAX_INFLIGHT_MESHES := 3
var light_cap := 10
const REQUEST_BATCH := 40
const REQUEST_RETRY_SECONDS := 6.0

var world: Node = null           # set by world.gd; used to send chunk requests

var _data: Dictionary = {}       # Vector2i -> PackedByteArray
var _holders: Dictionary = {}    # Vector2i -> Node3D
var _pending: Dictionary = {}    # Vector2i -> request time (msec)
var _mesh_queue: Array[Vector2i] = []
var _queued: Dictionary = {}
var _flickers: Array = []        # [{light, base}]
var _materials: Dictionary = {}
var _focus_chunks: Array[Vector2i] = []
var _teleporters: Dictionary = {}   # Vector2i chunk -> Array[Vector3] world positions

signal first_chunks_ready

var _announced_ready := false

func _ready() -> void:
	var terrain := ShaderMaterial.new()
	terrain.shader = load("res://shaders/terrain.gdshader")
	var plants := ShaderMaterial.new()
	plants.shader = load("res://shaders/plants.gdshader")
	var water := ShaderMaterial.new()
	water.shader = load("res://shaders/water.gdshader")
	_materials = {"opaque": terrain, "plants": plants, "trans": water}

func has_chunk(cpos: Vector2i) -> bool:
	return _data.has(cpos)

## The world tells us where the local players (or the spectator) are looking.
func set_focus(positions: Array) -> void:
	_focus_chunks.clear()
	for pos: Vector3 in positions:
		var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
		if not _focus_chunks.has(cpos):
			_focus_chunks.append(cpos)
	_refresh_interest()

func _refresh_interest() -> void:
	if _focus_chunks.is_empty() or world == null:
		return
	# Wanted set: circle around each focus.
	var wanted: Dictionary = {}
	for focus in _focus_chunks:
		for dz in range(-view_radius, view_radius + 1):
			for dx in range(-view_radius, view_radius + 1):
				if dx * dx + dz * dz <= view_radius * view_radius + 2:
					wanted[focus + Vector2i(dx, dz)] = true
	# Request whatever is missing, nearest first.
	var missing: Array[Vector2i] = []
	var now := Time.get_ticks_msec()
	for cpos: Vector2i in wanted.keys():
		if _data.has(cpos):
			continue
		if _pending.has(cpos) and now - _pending[cpos] < REQUEST_RETRY_SECONDS * 1000.0:
			continue
		missing.append(cpos)
	if not missing.is_empty():
		missing.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return _dist_to_focus(a) < _dist_to_focus(b))
		var batch: Array = []
		for cpos in missing:
			batch.append(cpos)
			_pending[cpos] = now
			if batch.size() >= REQUEST_BATCH:
				break
		world.request_chunks(batch)
	if match_mode:
		return
	# Drop chunks far outside every focus.
	var unload := view_radius + 2
	for cpos: Vector2i in _data.keys().duplicate():
		var keep := false
		for focus in _focus_chunks:
			var d := cpos - focus
			if d.x * d.x + d.y * d.y <= unload * unload:
				keep = true
				break
		if not keep:
			_drop_chunk(cpos)

func _dist_to_focus(cpos: Vector2i) -> float:
	var best := 1e9
	for focus in _focus_chunks:
		best = minf(best, Vector2(cpos - focus).length_squared())
	return best

func receive_chunk(cx: int, cz: int, blob: PackedByteArray) -> void:
	var cpos := Vector2i(cx, cz)
	_pending.erase(cpos)
	var raw := blob.decompress(ChunkStore.RAW_CHUNK_BYTES, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != ChunkStore.RAW_CHUNK_BYTES:
		push_error("Bad chunk payload for %s" % cpos)
		return
	_data[cpos] = raw
	_queue_mesh(cpos)
	# Neighbors were meshed against air where this chunk borders them.
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if _data.has(cpos + off):
			_queue_mesh(cpos + off)

## Applies a replicated edit. Returns the previous block id (or -1 if the
## chunk isn't resident here).
func apply_edit(pos: Vector3i, block: int) -> int:
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	if not _data.has(cpos):
		return -1
	var lx := posmod(pos.x, 16)
	var lz := posmod(pos.z, 16)
	var data: PackedByteArray = _data[cpos]
	var index := WorldGen.idx(lx, pos.y, lz)
	var old := int(data[index])
	data[index] = block
	_data[cpos] = data
	_queue_mesh(cpos)
	# Border edits change neighbor face culling and AO.
	if lx == 0:
		_queue_mesh(cpos + Vector2i(-1, 0))
	elif lx == 15:
		_queue_mesh(cpos + Vector2i(1, 0))
	if lz == 0:
		_queue_mesh(cpos + Vector2i(0, -1))
	elif lz == 15:
		_queue_mesh(cpos + Vector2i(0, 1))
	return old

func get_block(pos: Vector3i) -> int:
	if pos.y < 0:
		return Blocks.BEDROCK   # nothing below the world: treat as floor
	if pos.y >= WorldGen.CHUNK_H:
		return Blocks.AIR
	var cpos := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
	var data: PackedByteArray = _data.get(cpos, PackedByteArray())
	if data.is_empty():
		return Blocks.STONE   # unloaded chunks are solid so nobody falls out
	return data[WorldGen.idx(posmod(pos.x, 16), pos.y, posmod(pos.z, 16))]

## Ground height (top of the highest standable block) at a world column.
func ground_height(wx: int, wz: int) -> int:
	for y in range(WorldGen.CHUNK_H - 1, -1, -1):
		if Blocks.is_solid(get_block(Vector3i(wx, y, wz))):
			return y + 1
	return WorldGen.SEA_LEVEL

func _queue_mesh(cpos: Vector2i) -> void:
	if _queued.has(cpos) or not _data.has(cpos):
		return
	_queued[cpos] = true
	_mesh_queue.append(cpos)

## One chunk meshed per frame, tops — streaming spreads over frames instead
## of spiking them, and the mesher itself skips empty slabs at C++ speed.
func _process(_delta: float) -> void:
	# Burst-mesh when a match is on or a big backlog piled up (prefetch),
	# one per frame otherwise to keep frames smooth.
	var mesh_budget: int = 4 if (match_mode or _mesh_queue.size() > 40) else 1
	for _mesh_pass in mesh_budget:
		if _mesh_queue.is_empty():
			break
		var cpos: Vector2i = _mesh_queue.pop_front()
		_queued.erase(cpos)
		if _data.has(cpos):
			var neighbors := {}
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: PackedByteArray = _data.get(cpos + off, PackedByteArray())
				if not n.is_empty():
					neighbors[off] = n
			var surfaces := Mesher.new().build(_data[cpos], neighbors, cpos.x, cpos.y)
			_topmaps[cpos] = surfaces.get("topmap", PackedByteArray())
			_apply_surfaces(cpos, surfaces)
	if not _announced_ready and _mesh_queue.is_empty() and _data.size() > 8:
		_announced_ready = true
		first_chunks_ready.emit()
	# Campfire/lantern flicker.
	var t := Time.get_ticks_msec() / 1000.0
	for entry: Dictionary in _flickers:
		var light: OmniLight3D = entry.light
		if is_instance_valid(light):
			var base: float = entry.base
			var phase: float = entry.phase
			light.light_energy = base * (0.86 + 0.22 * sin(t * 11.0 + phase) + 0.1 * sin(t * 27.0 + phase * 2.0))

func _apply_surfaces(cpos: Vector2i, surfaces: Dictionary) -> void:
	var warps: Array = []
	for local: Vector3i in surfaces.get("teleporters", []):
		warps.append(Vector3(cpos.x * 16 + local.x, local.y, cpos.y * 16 + local.z))
	if warps.is_empty():
		_teleporters.erase(cpos)
	else:
		_teleporters[cpos] = warps

	var holder: Node3D = _holders.get(cpos)
	if holder != null:
		_forget_flickers(holder)
		holder.queue_free()
	holder = Node3D.new()
	holder.position = Vector3(cpos.x * 16, 0, cpos.y * 16)
	add_child(holder)
	_holders[cpos] = holder

	for key in ["opaque", "plants", "trans"]:
		if not surfaces.has(key):
			continue
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[key])
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _materials[key]
		if key != "opaque":
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if key == "trans":
			instance.transparency = 0.0
		holder.add_child(instance)

	var lights: Array = surfaces.get("lights", [])
	var count := 0
	for spec: Dictionary in lights:
		if count >= light_cap:
			break
		count += 1
		var light := OmniLight3D.new()
		light.position = spec.pos
		light.light_color = spec.color
		light.light_energy = spec.energy
		light.omni_range = 7.5
		light.omni_attenuation = 1.4
		light.shadow_enabled = false
		holder.add_child(light)
		if spec.flicker:
			_flickers.append({"light": light, "base": spec.energy,
				"phase": float(spec.pos.x) * 1.7 + float(spec.pos.z) * 0.9})
			holder.add_child(_campfire_particles(spec.pos))

func _campfire_particles(pos: Vector3) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.position = pos - Vector3(0, 0.35, 0)
	particles.amount = 14
	particles.lifetime = 1.1
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 12.0
	mat.initial_velocity_min = 0.8
	mat.initial_velocity_max = 1.6
	mat.gravity = Vector3(0, 0.6, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	mat.color = Color(1.0, 0.6, 0.2, 0.8)
	particles.process_material = mat
	var draw := QuadMesh.new()
	draw.size = Vector2(0.16, 0.16)
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.emission_enabled = true
	draw_mat.emission = Color(1.0, 0.45, 0.1)
	draw_mat.emission_energy_multiplier = 2.0
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw.material = draw_mat
	particles.draw_pass_1 = draw
	return particles

func _forget_flickers(holder: Node3D) -> void:
	_flickers = _flickers.filter(func(entry: Dictionary) -> bool:
		var light: OmniLight3D = entry.light
		return is_instance_valid(light) and not holder.is_ancestor_of(light))

## Nearest OTHER warp stone (block position) to stand-on position `from`.
func nearest_teleporter(from: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_dist := 1e9
	for warps: Array in _teleporters.values():
		for pos: Vector3 in warps:
			var dist := from.distance_to(pos)
			if dist > 1.5 and dist < best_dist:
				best_dist = dist
				best = pos
	return best

## Ask for every chunk in a radius right now (match-lobby prefetch).
func prefetch(radius: int) -> void:
	var wanted: Array = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var cpos := Vector2i(dx, dz)
			if dx * dx + dz * dz <= radius * radius + 2 and not _data.has(cpos):
				wanted.append(cpos)
				_pending[cpos] = Time.get_ticks_msec()
	for i in range(0, wanted.size(), 38):
		world.request_chunks(wanted.slice(i, i + 38))

## Drop everything (map reset) so the interest loop re-streams the world.
func reset() -> void:
	for cpos: Vector2i in _data.keys().duplicate():
		_drop_chunk(cpos)
	_pending.clear()
	_mesh_queue.clear()
	_queued.clear()

## Top visible block for the minimap (uses cached per-chunk top maps).
var _topmaps: Dictionary = {}
func top_block(wx: int, wz: int) -> int:
	var cpos := Vector2i(floori(wx / 16.0), floori(wz / 16.0))
	var topmap: PackedByteArray = _topmaps.get(cpos, PackedByteArray())
	if topmap.is_empty():
		return -1
	return topmap[posmod(wz, 16) * 16 + posmod(wx, 16)]

func _drop_chunk(cpos: Vector2i) -> void:
	_topmaps.erase(cpos)
	_data.erase(cpos)
	_pending.erase(cpos)
	_teleporters.erase(cpos)
	var holder: Node3D = _holders.get(cpos)
	if holder != null:
		_forget_flickers(holder)
		holder.queue_free()
		_holders.erase(cpos)
