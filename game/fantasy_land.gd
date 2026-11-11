# Purpose: draws the ground of the fantasy world around the player: square chunks of terrain (mesh coloured per corner
# + collision) are worked out on background threads and shown a few per frame, far ones are dropped, a coarse mesh of
# the whole land shows distant hills, and one sheet of water marks the sea. Emits chunk_loaded / chunk_unloaded so
# other scripts can dress and undress the chunks.
# Dependencies: core/fantasy_terrain.gd (heights and colours), game/fantasy_models.gd (the shared paint material).
extends Node3D

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const FantasyGround = preload("res://game/fantasy_ground.gd")
const WaterSurface = preload("res://game/water_surface.gd")

signal chunk_loaded(key: Vector2i, origin: Vector3)
signal chunk_unloaded(key: Vector2i)

const CELLS := 12  # squares along one side of a chunk
const FAR_CELLS := 56  # squares along one side of the whole-land mesh
const FAR_DROP := 5.0  # the far mesh sits this much lower so near ground always covers it
const APPLY_PER_FRAME := 2

var terrain: FantasyTerrain
var radius := 5  # chunks kept around the player

var _chunk: float
var _half: int  # chunks from the middle of the land to its edge
var _chunks := {}  # Vector2i -> Node3D (null while it is being worked out)
var _grids := {}  # Vector2i -> [vertices, blend] of a shown chunk's mesh: cheap ground look-ups (see `ground`)
var _ready_list: Array = []  # [key, arrays, faces] from the threads
var _lock := Mutex.new()
var _center := Vector2i(9999, 9999)


func setup(land: FantasyTerrain) -> void:
	terrain = land
	_chunk = float(terrain.data["chunk"])
	_half = ceili(terrain.size / _chunk / 2.0)
	_add_far_mesh()
	var water := MeshInstance3D.new()
	var sheet := PlaneMesh.new()
	sheet.size = Vector2(terrain.size * 1.6, terrain.size * 1.6)
	water.mesh = sheet
	water.material_override = WaterSurface.material(Color(0.16, 0.42, 0.62))  # the same sea as around the island
	water.position.y = terrain.sea
	add_child(water)
	var lava := StandardMaterial3D.new()
	lava.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lava.albedo_color = Color(1.0, 0.42, 0.08)
	for lake: Dictionary in terrain.lakes:  # ponds and lakes: a sheet of water at each one's own level
		var pool := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = float(lake["r"]) + 1.5
		disc.bottom_radius = disc.top_radius
		disc.height = 0.02
		disc.radial_segments = 24
		disc.rings = 1
		pool.mesh = disc
		pool.material_override = lava if String(lake["water"]) == "lava" else water.material_override
		pool.position = Vector3(float(lake["x"]), float(lake["level"]), float(lake["z"]))
		pool.visibility_range_end = 700.0
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pool)


func chunk_size() -> float:
	return _chunk


func key_at(local: Vector3) -> Vector2i:
	return Vector2i(floori(local.x / _chunk), floori(local.z / _chunk))


func loaded(key: Vector2i) -> bool:
	return _chunks.get(key) != null


# Height and how trodden the ground is at a point, read from the shown chunk's own mesh (x = height, y = trodden
# 0..1). About twenty times cheaper than asking the terrain rules, and exactly what is drawn. Grass uses it.
# Returns Vector2(NAN, 0) where no chunk is shown.
func ground(x: float, z: float) -> Vector2:
	var key := Vector2i(floori(x / _chunk), floori(z / _chunk))
	if not _grids.has(key):
		return Vector2(NAN, 0.0)
	var verts: PackedVector3Array = _grids[key][0]
	var blend: PackedFloat32Array = _grids[key][1]
	var cell := _chunk / float(CELLS)
	var fx := (x - float(key.x) * _chunk) / cell
	var fz := (z - float(key.y) * _chunk) / cell
	var gx := clampi(int(fx), 0, CELLS - 1)
	var gz := clampi(int(fz), 0, CELLS - 1)
	var tx := fx - float(gx)
	var tz := fz - float(gz)
	var i := gz * (CELLS + 1) + gx
	var j := i + CELLS + 1
	return Vector2(lerpf(lerpf(verts[i].y, verts[i + 1].y, tx), lerpf(verts[j].y, verts[j + 1].y, tx), tz),
		lerpf(lerpf(blend[i * 4 + 2], blend[i * 4 + 6], tx), lerpf(blend[j * 4 + 2], blend[j * 4 + 6], tx), tz))


# How many chunks are on screen and how many are still being worked out.
func counts() -> Vector2i:
	var shown := 0
	for key: Vector2i in _chunks:
		if _chunks[key] != null:
			shown += 1
	return Vector2i(shown, _chunks.size() - shown)


# Call often with the player's position (in this node's space): starts and drops chunks as needed.
func follow(local: Vector3) -> void:
	var at := key_at(local)
	if at == _center:
		return
	_center = at
	for key: Vector2i in _chunks.keys():
		if maxi(absi(key.x - at.x), absi(key.y - at.y)) > radius + 1:
			if _chunks[key] != null:
				(_chunks[key] as Node3D).queue_free()
				chunk_unloaded.emit(key)
			_chunks.erase(key)
			_grids.erase(key)
	var wanted: Array[Vector2i] = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var key := Vector2i(at.x + dx, at.y + dz)
			if absi(key.x) <= _half and absi(key.y) <= _half and not _chunks.has(key):
				wanted.append(key)
	wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - at).length_squared() < (b - at).length_squared())
	for key in wanted:
		_chunks[key] = null
		WorkerThreadPool.add_task(_work.bind(key), true)  # high priority: every pool thread may take them (low priority gets very few)


# The player arrives (behind the fade): waits only for the ground under and right around the point. Everything
# further out is already queued nearest first and streams in over the next moments, with the far mesh showing
# meanwhile. (Waiting for every chunk held the game for seconds: round 4, load times.)
func load_now(local: Vector3) -> void:
	follow(local)
	var at := key_at(local)
	var waited := 0
	while not _ground_ready(at) and waited < 4000:
		_apply(64)
		OS.delay_msec(2)
		waited += 1


func _ground_ready(at: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := Vector2i(at.x + dx, at.y + dz)
			if _chunks.has(key) and _chunks[key] == null:
				return false
	return true


func _process(_delta: float) -> void:
	_apply(APPLY_PER_FRAME)


func _apply(limit: int) -> void:
	for _i in limit:
		_lock.lock()
		var job: Variant = _ready_list.pop_front() if not _ready_list.is_empty() else null
		_lock.unlock()
		if job == null:
			return
		var key: Vector2i = job[0]
		if not _chunks.has(key) or _chunks[key] != null:
			continue  # dropped again while it was being worked out
		var holder := Node3D.new()
		holder.position = Vector3(float(key.x) * _chunk, 0.0, float(key.y) * _chunk)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, job[1], [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		mesh.surface_set_material(0, FantasyGround.material(job[3], job[4], job[5]))
		var ground := MeshInstance3D.new()
		ground.mesh = mesh
		holder.add_child(ground)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var faces := ConcavePolygonShape3D.new()
		faces.backface_collision = true  # spells and shots aim at the ground with rays: both sides must stop them
		faces.set_faces(job[2])
		shape.shape = faces
		body.add_child(shape)
		holder.add_child(body)
		add_child(holder)
		_chunks[key] = holder
		_grids[key] = [job[1][Mesh.ARRAY_VERTEX], job[1][Mesh.ARRAY_CUSTOM0]]
		chunk_loaded.emit(key, holder.position)


# Runs on a worker thread: heights, normals and colours of one chunk.
func _work(key: Vector2i) -> void:
	# the two regions that matter most here, and the trodden ground of the nearest place
	var mid_x := (float(key.x) + 0.5) * _chunk
	var mid_z := (float(key.y) + 0.5) * _chunk
	var w := terrain.weights(mid_x, mid_z)
	var first := 0
	var second := -1
	for i in w.size():
		if w[i] > w[first]:
			first = i
	for i in w.size():
		if i != first and w[i] > 0.02 and (second < 0 or w[i] > w[second]):
			second = i
	if second < 0:
		second = first
	var yard := "g_dirt"
	for p: Dictionary in terrain.places:
		if Vector2(mid_x - float(p["pos"][0]), mid_z - float(p["pos"][1])).length() < float(p["flat"]) + _chunk:
			yard = String(p.get("yard", "g_dirt"))
	var job := [key, _arrays(float(key.x) * _chunk, float(key.y) * _chunk, _chunk / float(CELLS), CELLS, 0.0, true, first, second), null,
		String(terrain.regions[first].get("surface", "g_grass")), String(terrain.regions[second].get("surface", "g_grass")), yard]
	var verts: PackedVector3Array = job[1][Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = job[1][Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	faces.resize(index.size())
	for i in index.size():
		faces[i] = verts[index[i]]
	job[2] = faces
	_lock.lock()
	_ready_list.append(job)
	_lock.unlock()


# Mesh arrays for a square patch of land starting at world (x0, z0); vertices are relative to that corner when
# `relative`, otherwise in land space.
# `first` and `second` are the region numbers whose grounds this patch blends (-1 = no blending wanted: the far land).
func _arrays(x0: float, z0: float, cell: float, cells: int, drop: float, relative: bool, first := -1, second := -1) -> Array:
	var side := cells + 1
	var heights := PackedFloat32Array()
	heights.resize((side + 2) * (side + 2))
	for gz in side + 2:
		for gx in side + 2:
			heights[gz * (side + 2) + gx] = terrain.height(x0 + float(gx - 1) * cell, z0 + float(gz - 1) * cell)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var blend := PackedFloat32Array()
	for gz in side:
		for gx in side:
			var i := (gz + 1) * (side + 2) + gx + 1
			var h := heights[i]
			var n := Vector3(heights[i - 1] - heights[i + 1], 2.0 * cell, heights[i - side - 2] - heights[i + side + 2]).normalized()
			var x := float(gx) * cell
			var z := float(gz) * cell
			verts.append(Vector3(x if relative else x0 + x, h - drop, z if relative else z0 + z))
			normals.append(n)
			colors.append(terrain.color(x0 + x, z0 + z, h, 1.0 - n.y))
			if first >= 0:
				var w := terrain.weights(x0 + x, z0 + z)
				var share := 0.0 if first == second else w[second] / maxf(w[first] + w[second], 0.001)
				blend.append_array(PackedFloat32Array([share, smoothstep(0.3, 0.6, 1.0 - n.y), terrain.trodden(x0 + x, z0 + z), 0.0]))
	var index := PackedInt32Array()
	for gz in cells:
		for gx in cells:
			var a := gz * side + gx
			index.append_array(PackedInt32Array([a, a + 1, a + side, a + 1, a + side + 1, a + side]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	if first >= 0:
		arrays[Mesh.ARRAY_CUSTOM0] = blend
	arrays[Mesh.ARRAY_INDEX] = index
	return arrays


func _add_far_mesh() -> void:
	var cell := terrain.size / float(FAR_CELLS)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(-terrain.size / 2.0, -terrain.size / 2.0, cell, FAR_CELLS, FAR_DROP, false))
	mesh.surface_set_material(0, FantasyModels.paint())
	var far := MeshInstance3D.new()
	far.mesh = mesh
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far)
