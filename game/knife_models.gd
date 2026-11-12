# Purpose: builds the model of a knife type from its parts in data/knives.json. Blades and grips are lofted between
# "stations" (a diamond cross-section for a blade, an oval one for a grip); guards, pommels and rings are boxes and
# rings. Own low-polygon designs after real knife kinds. One mesh per type, one surface per material, built once.
# Dependencies: core/knife_db.gd, core/data_store.gd.
extends RefCounted

const KnifeDb = preload("res://core/knife_db.gd")
const DataStore = preload("res://core/data_store.gd")

const GRIP_SIDES := 8
const RING_STEPS := 14
const RING_SIDES := 6
const HOLD := Vector2(-0.066, 0.0)  # where the hand grips when a type does not say ("hold")

static var _db: KnifeDb
static var _meshes := {}  # knife id -> ArrayMesh
static var _materials := {}  # material id -> StandardMaterial3D


static func db() -> KnifeDb:
	if _db == null:
		_db = KnifeDb.new(DataStore.load_json("res://data/knives.json"))
	return _db


# The knife of type `id` (an unknown id gives the plain combat knife): the tip points forward (-Z), the spine up,
# and the origin is where the hand grips it.
static func build(id: String) -> Node3D:
	var known := db().known(id)
	if not _meshes.has(known):
		_meshes[known] = _mesh(known)
	var holder := Node3D.new()
	var instance := MeshInstance3D.new()
	instance.mesh = _meshes[known]
	instance.rotation.y = PI * 0.5  # the data's x (guard to tip) becomes forward
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(instance)
	return holder


# Triangles of a built type (for the developer check).
static func triangles(id: String) -> int:
	var known := db().known(id)
	if not _meshes.has(known):
		_meshes[known] = _mesh(known)
	var count := 0
	var mesh: ArrayMesh = _meshes[known]
	for surface in mesh.get_surface_count():
		count += roundi((mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3.0)
	return count


static func _mesh(id: String) -> ArrayMesh:
	var hold := HOLD
	var own: Array = db().hold(id)
	if own.size() == 2:
		hold = Vector2(float(own[0]), float(own[1]))
	var shift := Vector3(-hold.x, -hold.y, 0.0)
	var tools := {}  # material id -> SurfaceTool
	for part: Dictionary in db().parts(id):
		var mat := String(part["mat"])
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		var tool: SurfaceTool = tools[mat]
		match String(part["kind"]):
			"blade":
				_loft(tool, part["stations"], 4, float(part.get("ridge", 0.8)), shift)
			"grip":
				_loft(tool, part["stations"], GRIP_SIDES, 0.5, shift)
			"box":
				_box(tool, part, shift)
			"ring":
				_ring(tool, part, shift)
	var mesh := ArrayMesh.new()
	for mat: String in tools:
		(tools[mat] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(mat))
	return mesh


static func _material(id: String) -> StandardMaterial3D:
	if not _materials.has(id):
		var def: Dictionary = db().material(id)
		var material := StandardMaterial3D.new()
		var c: Array = def["color"]
		material.albedo_color = Color(c[0], c[1], c[2])
		material.metallic = float(def["metal"])
		material.roughness = float(def["rough"])
		_materials[id] = material
	return _materials[id]


# A tube through the stations [spine x, spine y, edge x, edge y, thickness]: 4 sides = a blade (thickest at `ridge`
# of the way from edge to spine), more = an oval grip. Closed at both ends.
static func _loft(st: SurfaceTool, stations: Array, sides: int, ridge: float, shift: Vector3) -> void:
	var rings: Array[PackedVector3Array] = []
	var centres := PackedVector3Array()
	for s: Array in stations:
		var spine := Vector3(float(s[0]), float(s[1]), 0.0) + shift
		var edge := Vector3(float(s[2]), float(s[3]), 0.0) + shift
		var half := float(s[4]) * 0.5
		var ring := PackedVector3Array()
		if sides == 4:
			var mid := edge.lerp(spine, ridge)
			ring = PackedVector3Array([spine, mid + Vector3(0, 0, half), edge, mid - Vector3(0, 0, half)])
		else:
			var middle := (spine + edge) * 0.5
			for k in sides:
				var a := TAU * float(k) / float(sides)
				ring.append(middle + (spine - middle) * cos(a) + Vector3(0, 0, half) * sin(a))
		rings.append(ring)
		centres.append((spine + edge) * 0.5)
	for i in rings.size() - 1:
		var axis := (centres[i] + centres[i + 1]) * 0.5
		for k in sides:
			var n := (k + 1) % sides
			_tri(st, rings[i][k], rings[i][n], rings[i + 1][n], axis)
			_tri(st, rings[i][k], rings[i + 1][n], rings[i + 1][k], axis)
	var last := rings.size() - 1
	for k in sides:
		var n := (k + 1) % sides
		_tri(st, centres[0], rings[0][k], rings[0][n], centres[1])
		_tri(st, centres[last], rings[last][k], rings[last][n], centres[last - 1])


static func _box(st: SurfaceTool, part: Dictionary, shift: Vector3) -> void:
	var at: Array = part["at"]
	var size: Array = part["size"]
	var centre := Vector3(float(at[0]), float(at[1]), float(at[2])) + shift
	var turn := Basis(Vector3(0, 0, 1), deg_to_rad(float(part.get("tilt", 0.0))))
	var half := Vector3(float(size[0]), float(size[1]), float(size[2])) * 0.5
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(centre + turn * Vector3(half.x if i & 1 else -half.x, half.y if i & 2 else -half.y, half.z if i & 4 else -half.z))
	for face: Array in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]]:
		_tri(st, corners[face[0]], corners[face[1]], corners[face[2]], centre)
		_tri(st, corners[face[0]], corners[face[2]], corners[face[3]], centre)


# A ring whose hole points along z (a finger ring) or along x (a muzzle ring).
static func _ring(st: SurfaceTool, part: Dictionary, shift: Vector3) -> void:
	var at: Array = part["at"]
	var centre := Vector3(float(at[0]), float(at[1]), float(at[2])) + shift
	var radius := float(part["radius"])
	var tube := float(part["tube"])
	var hole := Vector3(1, 0, 0) if String(part.get("axis", "z")) == "x" else Vector3(0, 0, 1)
	var u := Vector3(0, 1, 0)
	var v := hole.cross(u)
	var circles: Array[PackedVector3Array] = []
	var cores := PackedVector3Array()
	for i in RING_STEPS:
		var a := TAU * float(i) / float(RING_STEPS)
		var out := u * cos(a) + v * sin(a)
		var core := centre + out * radius
		var circle := PackedVector3Array()
		for k in RING_SIDES:
			var b := TAU * float(k) / float(RING_SIDES)
			circle.append(core + out * (tube * cos(b)) + hole * (tube * sin(b)))
		circles.append(circle)
		cores.append(core)
	for i in RING_STEPS:
		var j := (i + 1) % RING_STEPS
		var axis := (cores[i] + cores[j]) * 0.5
		for k in RING_SIDES:
			var n := (k + 1) % RING_SIDES
			_tri(st, circles[i][k], circles[i][n], circles[j][n], axis)
			_tri(st, circles[i][k], circles[j][n], circles[j][k], axis)


# One flat-shaded triangle facing away from `inside` (the engine's front faces wind clockwise). Slivers are skipped.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 1e-14:
		return
	normal = normal.normalized()
	if normal.dot((a + b + c) / 3.0 - inside) > 0.0:  # counter-clockwise seen from outside: turn it round
		var keep := b
		b = c
		c = keep
		normal = -normal
	st.set_normal(-normal)
	st.add_vertex(a)
	st.set_normal(-normal)
	st.add_vertex(b)
	st.set_normal(-normal)
	st.add_vertex(c)
