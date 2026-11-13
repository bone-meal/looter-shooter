# Purpose: builds the shield's model: a ship's hatch door of four planks held by two iron bands, with a grip on the
# inside. One mesh with two surfaces (wood, iron), so a carried shield is two draw calls. Its face looks along -Z
# (the way a held weapon points); the grip is on the +Z side.
# Dependencies: game/surface_library.gd (the plank surface).
extends RefCounted

const SurfaceLibrary = preload("res://game/surface_library.gd")

const WIDE := 0.62
const TALL := 0.96
const THICK := 0.045

static var _mesh: ArrayMesh


static func build() -> MeshInstance3D:
	if _mesh == null:
		_mesh = _make()
	var shield := MeshInstance3D.new()
	shield.mesh = _mesh
	return shield


static func _make() -> ArrayMesh:
	var wood := SurfaceTool.new()
	wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plank := WIDE / 4.0
	for i in 4:  # planks of slightly different length, like a door knocked together
		_add_box(wood, Vector3(plank - 0.012, TALL - 0.03 * float((i * 3) % 4), THICK), Vector3((float(i) - 1.5) * plank, 0.0, 0.0))
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y: float in [0.27, -0.27]:
		_add_box(iron, Vector3(WIDE + 0.03, 0.07, THICK + 0.02), Vector3(0.0, y, 0.0))
	_add_box(iron, Vector3(0.04, 0.26, 0.03), Vector3(0.0, 0.0, THICK * 0.5 + 0.05))  # the grip, on two short posts
	_add_box(iron, Vector3(0.04, 0.03, 0.05), Vector3(0.0, 0.115, THICK * 0.5 + 0.025))
	_add_box(iron, Vector3(0.04, 0.03, 0.05), Vector3(0.0, -0.115, THICK * 0.5 + 0.025))
	var mesh := ArrayMesh.new()
	wood.commit(mesh)
	iron.commit(mesh)
	mesh.surface_set_material(0, SurfaceLibrary.material("painting_post", Color(0.42, 0.3, 0.17)))
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.27, 0.28, 0.3)
	metal.metallic = 0.5
	metal.roughness = 0.55
	mesh.surface_set_material(1, metal)
	return mesh


static func _add_box(to: SurfaceTool, size: Vector3, at: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	to.append_from(box, 0, Transform3D(Basis.IDENTITY, at))
