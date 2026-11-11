# Purpose: streams the baked Omaha map (data/omaha) around the player: per 192 m chunk one flat mesh (parks, water, rails, roads),
#   one building mesh with window texture + box colliders. Wasteland look. Flat ground (no elevation data).
# Dependencies: core/data_store.gd, core/omaha_geo.gd, data/omaha/map.json + chunks/r_RX_RZ.json (made by tools/omaha_bake.py).
# Map data (c) OpenStreetMap contributors, ODbL.
extends Node3D

const DataStore = preload("res://core/data_store.gd")
const OmahaGeo = preload("res://core/omaha_geo.gd")

const OFFSET := Vector3(10000.0, 0.0, 0.0)  # world position of the map origin (Old Market)
const LOAD_RADIUS := 3  # chunks kept loaded around the player
const BUILDS_PER_FRAME := 2
const REGION_CACHE := 6
const ROAD_W := [11.0, 9.0, 8.0, 7.0, 5.0, 2.6]  # road classes 0..4, 5 = rail
const ROAD_Y := [0.16, 0.14, 0.12, 0.10, 0.08, 0.06]
const PARK_Y := 0.02
const WATER_Y := 0.04
const GROUND_COLOR := Color(0.47, 0.40, 0.29)
const ROAD_COLORS := [Color(0.20, 0.19, 0.18), Color(0.23, 0.22, 0.20), Color(0.26, 0.25, 0.22), Color(0.29, 0.27, 0.24), Color(0.33, 0.31, 0.27), Color(0.22, 0.17, 0.12)]
const PARK_COLOR := Color(0.36, 0.40, 0.20)
const WATER_COLOR := Color(0.25, 0.36, 0.32)
const KIND_COLOR := {
	"office": Color(0.48, 0.56, 0.60), "commercial": Color(0.60, 0.54, 0.46), "retail": Color(0.66, 0.57, 0.47),
	"apartments": Color(0.62, 0.48, 0.42), "residential": Color(0.60, 0.50, 0.42), "industrial": Color(0.50, 0.49, 0.43),
	"hospital": Color(0.72, 0.68, 0.62), "university": Color(0.66, 0.58, 0.50), "school": Color(0.64, 0.52, 0.42),
	"church": Color(0.58, 0.54, 0.50), "garage": Color(0.52, 0.52, 0.50), "parking": Color(0.52, 0.52, 0.50),
	"hotel": Color(0.58, 0.54, 0.56), "yes": Color(0.58, 0.52, 0.45)}
const TOWER_COLOR := Color(0.42, 0.52, 0.58)

var map: Dictionary
var spawn_xz := Vector2.ZERO
var _target: Node3D
var _regions: Dictionary = {}  # "rx_rz" -> {"cx_cz": chunk dict}
var _region_order: Array = []
var _chunks: Dictionary = {}  # "cx_cz" -> Node3D
var _queue: Array = []  # chunk keys waiting to be built, nearest first
var _timer := 0.0
var _flat_mat := StandardMaterial3D.new()
var _wall_mat := StandardMaterial3D.new()
var _chunk := 192.0
var _region := 6
var _have: Dictionary = {}  # "cx_cz" -> true for chunks that exist in map.json
var _last_center := Vector2i(1 << 20, 1 << 20)


func _ready() -> void:
	map = DataStore.load_json("res://data/omaha/map.json")
	_chunk = float(map["chunk"])
	_region = int(map["region"])
	for k: Array in map["chunks"]:
		_have["%d_%d" % [k[0], k[1]]] = true
	var sp: Array = map.get("spawn", [0.0, 0.0])
	spawn_xz = Vector2(float(sp[0]), float(sp[1]))
	_flat_mat.vertex_color_use_as_albedo = true
	_flat_mat.roughness = 1.0
	_flat_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_wall_mat.vertex_color_use_as_albedo = true
	_wall_mat.albedo_texture = _window_texture()
	_wall_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_wall_mat.roughness = 1.0
	_wall_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_build_ground()


func setup(target: Node3D) -> void:
	_target = target


# World position for a map coordinate (x east, z south).
func to_world(xz: Vector2) -> Vector3:
	return OFFSET + Vector3(xz.x, 0.0, xz.y)


func to_map(world: Vector3) -> Vector2:
	return Vector2(world.x - OFFSET.x, world.z - OFFSET.z)


func spawn_world() -> Vector3:
	return to_world(spawn_xz) + Vector3(0.0, 0.1, 0.0)


# Builds everything around `world_pos` right now (used when entering, behind a fade).
func load_around(world_pos: Vector3) -> void:
	_stream(to_map(world_pos), 100)


func chunk_count() -> int:
	return _chunks.size()


# Is a map point inside a building box (grown by pad) or open water? Used by the spawner to avoid bad spots.
func blocked(xz: Vector2, pad: float = 1.0) -> bool:
	var c := _chunk_of(xz)
	var data := _chunk_data(c.x, c.y)
	if data.is_empty():
		return false
	for b: Array in data["b"]:
		if OmahaGeo.in_rect(xz, float(b[0]), float(b[1]), float(b[2]), float(b[3]), float(b[4]), pad):
			return true
	for p: Array in data["p"]:
		if OmahaGeo.point_in_poly(xz, p):
			return true
	return false


func _process(delta: float) -> void:
	if _target == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.3
		_stream(to_map(_target.global_position), BUILDS_PER_FRAME)
	elif not _queue.is_empty():
		_stream(to_map(_target.global_position), BUILDS_PER_FRAME)


func _stream(xz: Vector2, budget: int) -> void:
	var c := _chunk_of(xz)
	if c != _last_center:
		_last_center = c
		_queue.clear()
		for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
				var key := "%d_%d" % [c.x + dx, c.y + dz]
				if _have.has(key) and not _chunks.has(key):
					_queue.append([dx * dx + dz * dz, key])
		_queue.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for key: String in _chunks.keys():
			var p := key.split("_")
			if absi(int(p[0]) - c.x) > LOAD_RADIUS + 1 or absi(int(p[1]) - c.y) > LOAD_RADIUS + 1:
				_chunks[key].queue_free()
				_chunks.erase(key)
	while budget > 0 and not _queue.is_empty():
		var key: String = _queue.pop_front()[1]
		var p := key.split("_")
		_build_chunk(int(p[0]), int(p[1]))
		budget -= 1


func _chunk_of(xz: Vector2) -> Vector2i:
	return Vector2i(int(floorf(xz.x / _chunk)), int(floorf(xz.y / _chunk)))


func _chunk_data(cx: int, cz: int) -> Dictionary:
	var rx := floori(float(cx) / float(_region))
	var rz := floori(float(cz) / float(_region))
	var rkey := "%d_%d" % [rx, rz]
	if not _regions.has(rkey):
		var path := "res://data/omaha/chunks/r_%d_%d.json" % [rx, rz]
		_regions[rkey] = DataStore.load_json(path) if FileAccess.file_exists(path) else {}
		_region_order.append(rkey)
		while _region_order.size() > REGION_CACHE:
			_regions.erase(_region_order.pop_front())
	var region: Dictionary = _regions.get(rkey, {})
	return region.get("%d_%d" % [cx, cz], {})


func _build_chunk(cx: int, cz: int) -> void:
	var key := "%d_%d" % [cx, cz]
	var data := _chunk_data(cx, cz)
	if data.is_empty():
		return
	var origin := Vector2(float(cx) * _chunk, float(cz) * _chunk)
	var root := Node3D.new()
	root.position = OFFSET + Vector3(origin.x, 0.0, origin.y)
	var flat := _flat_mesh(data, origin)
	if flat != null:
		var mi := MeshInstance3D.new()
		mi.mesh = flat
		mi.material_override = _flat_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var bld: Array = data["b"]
	if not bld.is_empty():
		var bm := _building_mesh(bld, origin)
		var bi := MeshInstance3D.new()
		bi.mesh = bm
		bi.material_override = _wall_mat
		root.add_child(bi)
		root.add_child(_building_bodies(bld, origin))
	add_child(root)
	_chunks[key] = root


# ---------- flat layer: parks, water, rails, roads ----------

func _flat_mesh(data: Dictionary, origin: Vector2) -> ArrayMesh:
	var v := PackedVector3Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	for g: Array in data["g"]:
		_fill(v, col, idx, g, origin, PARK_Y, PARK_COLOR)
	for p: Array in data["p"]:
		_fill(v, col, idx, p, origin, WATER_Y, WATER_COLOR)
	for w: Array in data["w"]:
		_ribbon(v, col, idx, w, 1, origin, float(w[0]), WATER_Y + 0.01, WATER_COLOR)
	var roads: Array = data["r"]
	for r: Array in roads:
		var cls := int(r[0])
		_ribbon(v, col, idx, r, 1, origin, ROAD_W[cls], ROAD_Y[cls], ROAD_COLORS[cls])
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(v.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _fill(v: PackedVector3Array, col: PackedColorArray, idx: PackedInt32Array, flat: Array, origin: Vector2, y: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for i in flat.size() >> 1:
		pts.append(Vector2(float(flat[i * 2]) - origin.x, float(flat[i * 2 + 1]) - origin.y))
	var tri := Geometry2D.triangulate_polygon(pts)
	if tri.is_empty():
		return
	var base := v.size()
	for p in pts:
		v.append(Vector3(p.x, y, p.y))
		col.append(color)
	for t in tri:
		idx.append(base + t)


# `a[start..]` is [x,z,x,z...] (road: index 0 is the class, so start = 1).
func _ribbon(v: PackedVector3Array, col: PackedColorArray, idx: PackedInt32Array, a: Array, start: int, origin: Vector2, width: float, y: float, color: Color) -> void:
	var half := width * 0.5
	var n := (a.size() - start) >> 1
	for i in n - 1:
		var x0 := float(a[start + i * 2]) - origin.x
		var z0 := float(a[start + i * 2 + 1]) - origin.y
		var x1 := float(a[start + i * 2 + 2]) - origin.x
		var z1 := float(a[start + i * 2 + 3]) - origin.y
		var dx := x1 - x0
		var dz := z1 - z0
		var length := sqrt(dx * dx + dz * dz)
		if length < 0.01:
			continue
		var nx := -dz / length * half
		var nz := dx / length * half
		var base := v.size()
		v.append(Vector3(x0 + nx, y, z0 + nz))
		v.append(Vector3(x0 - nx, y, z0 - nz))
		v.append(Vector3(x1 - nx, y, z1 - nz))
		v.append(Vector3(x1 + nx, y, z1 + nz))
		for k in 4:
			col.append(color)
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	for i in range(1, n - 1):  # a small square at inner joints hides the wedge gaps between segments
		var jx := float(a[start + i * 2]) - origin.x
		var jz := float(a[start + i * 2 + 1]) - origin.y
		var base := v.size()
		v.append(Vector3(jx - half, y, jz - half))
		v.append(Vector3(jx + half, y, jz - half))
		v.append(Vector3(jx + half, y, jz + half))
		v.append(Vector3(jx - half, y, jz + half))
		for k in 4:
			col.append(color)
		idx.append_array(PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2]))


# ---------- buildings ----------

# b = [x, z, w, d, ang, h, kind, name]. Wasteland: some buildings are cut down to half height and darkened.
func _building_mesh(bld: Array, origin: Vector2) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	for b: Array in bld:
		var rnd := fposmod(float(b[0]) * 12.9898 + float(b[1]) * 78.233, 97.0) / 97.0
		var h := float(b[5])
		var tower := h > 30.0
		var tint: Color = TOWER_COLOR if tower else KIND_COLOR.get(String(b[6]), KIND_COLOR["yes"])
		tint = tint.darkened(0.15 + rnd * 0.25)
		if not tower and rnd > 0.65:
			h *= 0.5 + rnd * 0.3  # collapsed upper floors
		_box(v, n, uv, col, Vector2(float(b[0]) - origin.x, float(b[1]) - origin.y), float(b[2]), float(b[3]), float(b[4]), h, tint)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _box(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, col: PackedColorArray, c: Vector2, w: float, d: float, ang: float, h: float, tint: Color) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var hw := w * 0.5
	var hd := d * 0.5
	var corners: Array[Vector2] = []
	for s in [Vector2(-hw, -hd), Vector2(hw, -hd), Vector2(hw, hd), Vector2(-hw, hd)]:
		corners.append(Vector2(c.x + s.x * ca - s.y * sa, c.y + s.x * sa + s.y * ca))
	for i in 4:  # four walls, each two triangles (outward winding for Godot: clockwise from outside)
		var a := corners[i]
		var b := corners[(i + 1) % 4]
		var edge := b - a
		var normal := Vector3(edge.y, 0.0, -edge.x).normalized()
		var length := edge.length()
		var u1 := length / 4.0
		var v1 := h / 3.6
		var p0 := Vector3(a.x, 0.0, a.y)
		var p1 := Vector3(b.x, 0.0, b.y)
		var p2 := Vector3(b.x, h, b.y)
		var p3 := Vector3(a.x, h, a.y)
		_tri(v, n, uv, col, [p0, p3, p2], [Vector2(0, 0), Vector2(0, v1), Vector2(u1, v1)], normal, tint)
		_tri(v, n, uv, col, [p0, p2, p1], [Vector2(0, 0), Vector2(u1, v1), Vector2(u1, 0)], normal, tint)
	var r0 := Vector3(corners[0].x, h, corners[0].y)
	var r1 := Vector3(corners[1].x, h, corners[1].y)
	var r2 := Vector3(corners[2].x, h, corners[2].y)
	var r3 := Vector3(corners[3].x, h, corners[3].y)
	var roof := tint.darkened(0.35)
	_tri(v, n, uv, col, [r0, r1, r2], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP, roof)
	_tri(v, n, uv, col, [r0, r2, r3], [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO], Vector3.UP, roof)


func _tri(v: PackedVector3Array, n: PackedVector3Array, uv: PackedVector2Array, col: PackedColorArray, p: Array, t: Array, normal: Vector3, tint: Color) -> void:
	for i in 3:
		v.append(p[i])
		n.append(normal)
		uv.append(t[i])
		col.append(tint)


func _building_bodies(bld: Array, origin: Vector2) -> StaticBody3D:
	var body := StaticBody3D.new()
	for b: Array in bld:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(b[2]), maxf(float(b[5]), 3.0), float(b[3]))
		cs.shape = box
		cs.position = Vector3(float(b[0]) - origin.x, box.size.y * 0.5, float(b[1]) - origin.y)
		cs.rotation.y = -float(b[4])
		body.add_child(cs)
	return body


# ---------- ground + textures ----------

func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(30000.0, 30000.0)
	ground.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GROUND_COLOR
	mat.roughness = 1.0
	ground.material_override = mat
	ground.position = OFFSET + Vector3(-2500.0, 0.0, 0.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30000.0, 2.0, 30000.0)
	shape.shape = box
	body.position = OFFSET + Vector3(-2500.0, -1.0, 0.0)
	body.add_child(shape)
	add_child(body)


# 32x32 wall texture: concrete with a dark window block per 4 m x 3.6 m tile (tiles with texture_repeat in the material).
func _window_texture() -> ImageTexture:
	var img := Image.create(32, 32, true, Image.FORMAT_RGB8)
	img.fill(Color(0.85, 0.85, 0.85))
	for y in range(8, 24):
		for x in range(7, 25):
			img.set_pixel(x, y, Color(0.30, 0.34, 0.38) if (x + y) % 9 != 0 else Color(0.42, 0.46, 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
