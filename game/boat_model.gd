# Purpose: builds the boat's model: an open wooden skiff (a hull lofted through a few stations from the transom to
# the bow, floor boards, three thwarts, a tiller, a short mast) with a small sail set high. One mesh, two surfaces (wood,
# cloth). Its middle is at the waterline, the bow looks along -Z.
# Dependencies: game/surface_library.gd (the plank surface).
extends RefCounted

const SurfaceLibrary = preload("res://game/surface_library.gd")

# Stations from stern to bow: [z, half width at the rail, half width at the bottom, height of the rail].
const STATIONS := [[2.3, 0.7, 0.42, 0.52], [1.2, 0.86, 0.56, 0.48], [0.0, 0.9, 0.6, 0.46], [-1.2, 0.76, 0.46, 0.5], [-2.0, 0.42, 0.2, 0.6], [-2.55, 0.03, 0.02, 0.7]]
const KEEL := -0.3  # how far the bottom lies under the waterline

static var _mesh: ArrayMesh


static func build() -> MeshInstance3D:
	if _mesh == null:
		_mesh = _make()
	var boat := MeshInstance3D.new()
	boat.mesh = _mesh
	return boat


static func _make() -> ArrayMesh:
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in STATIONS.size() - 1:
		var a: Array = STATIONS[i]
		var b: Array = STATIONS[i + 1]
		for side: float in [-1.0, 1.0]:  # the planking of one side, then the bottom half under it
			_quad(wood, Vector3(side * float(a[1]), a[3], a[0]), Vector3(side * float(b[1]), b[3], b[0]), Vector3(side * float(b[2]), KEEL, b[0]), Vector3(side * float(a[2]), KEEL, a[0]))
			_quad(wood, Vector3(side * float(a[2]), KEEL, a[0]), Vector3(side * float(b[2]), KEEL, b[0]), Vector3(0.0, KEEL - 0.06, b[0]), Vector3(0.0, KEEL - 0.06, a[0]))
	var stern: Array = STATIONS[0]
	_quad(wood, Vector3(-float(stern[1]), stern[3], stern[0]), Vector3(float(stern[1]), stern[3], stern[0]), Vector3(float(stern[2]), KEEL, stern[0]), Vector3(-float(stern[2]), KEEL, stern[0]))  # the transom
	_add_box(wood, Vector3(1.0, 0.04, 3.9), Vector3(0.0, 0.05, 0.2))  # floor boards
	for z: float in [1.75, 0.75, -0.3]:
		_add_box(wood, Vector3(1.6, 0.05, 0.26), Vector3(0.0, 0.34, z))  # thwarts
	_add_box(wood, Vector3(0.06, 0.06, 1.0), Vector3(0.0, 0.62, 2.0))  # tiller
	_add_box(wood, Vector3(0.09, 3.3, 0.09), Vector3(0.0, 1.7, -1.0))  # mast
	wood.generate_normals()
	var cloth := SurfaceTool.new()
	cloth.begin(Mesh.PRIMITIVE_TRIANGLES)
	# a small three-cornered sail set high (clear of the helmsman's view) and swung out to starboard
	_quad(cloth, Vector3(0.0, 3.25, -0.98), Vector3(0.0, 3.2, -0.94), Vector3(0.62, 2.0, 0.6), Vector3(0.0, 2.0, -0.98))
	cloth.generate_normals()
	var mesh := ArrayMesh.new()
	wood.commit(mesh)
	cloth.commit(mesh)
	var planks: StandardMaterial3D = SurfaceLibrary.material("boat_planks", Color(0.45, 0.31, 0.18))
	planks.cull_mode = BaseMaterial3D.CULL_DISABLED  # the hull is one skin: seen from outside and from inside
	mesh.surface_set_material(0, planks)
	var canvas := StandardMaterial3D.new()
	canvas.albedo_color = Color(0.86, 0.82, 0.7)
	canvas.roughness = 0.9
	canvas.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(1, canvas)
	return mesh


# Two triangles through four corners given round the face.
static func _quad(to: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for corner: Vector3 in [a, b, c, a, c, d]:
		to.set_uv(Vector2(corner.z * 0.5, corner.y * 0.5 + corner.x * 0.3))
		to.add_vertex(corner)


static func _add_box(to: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var half := size * 0.5
	for axis in 3:  # two faces across each axis
		var u := Vector3.ZERO
		var v := Vector3.ZERO
		var n := Vector3.ZERO
		n[axis] = half[axis]
		u[(axis + 1) % 3] = half[(axis + 1) % 3]
		v[(axis + 2) % 3] = half[(axis + 2) % 3]
		_quad(to, at + n - u - v, at + n + u - v, at + n + u + v, at + n - u + v)
		_quad(to, at - n - u - v, at - n - u + v, at - n + u + v, at - n + u - v)
