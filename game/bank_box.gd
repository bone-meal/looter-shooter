# Purpose: the bank as it stands on the spawn island: a letter box on a post with a brass coin slot (code-built) and a
# small solid body so nobody walks through it. What it does is in core/bank_state.gd and the inventory screen.
# Dependencies: none.
extends StaticBody3D

const REACH := 3.0  # metres from which it can be opened


func _ready() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.2, 0.36, 0.55)
	paint.roughness = 0.55
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.25, 0.15)
	wood.roughness = 0.85
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.82, 0.65, 0.25)
	brass.metallic = 0.8
	brass.roughness = 0.35
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.75, 0.12, 0.1)
	_box(Vector3(0.12, 1.1, 0.12), Vector3(0, 0.55, 0), wood)  # post
	_box(Vector3(0.5, 0.42, 0.7), Vector3(0, 1.3, 0), paint)  # the box
	var roof := CylinderMesh.new()  # its rounded top
	roof.top_radius = 0.25
	roof.bottom_radius = 0.25
	roof.height = 0.7
	roof.radial_segments = 12
	var top := MeshInstance3D.new()
	top.mesh = roof
	top.rotation.x = PI * 0.5
	top.position = Vector3(0, 1.51, 0)
	top.material_override = paint
	add_child(top)
	_box(Vector3(0.3, 0.035, 0.02), Vector3(0, 1.4, 0.36), brass)  # coin slot
	_box(Vector3(0.34, 0.2, 0.02), Vector3(0, 1.2, 0.355), brass)  # door plate
	_box(Vector3(0.03, 0.3, 0.03), Vector3(0.27, 1.5, 0.1), wood)  # flag pole
	_box(Vector3(0.02, 0.14, 0.2), Vector3(0.27, 1.6, 0.0), red)  # flag
	var shape := CollisionShape3D.new()
	var solid := BoxShape3D.new()
	solid.size = Vector3(0.5, 1.8, 0.7)
	shape.shape = solid
	shape.position.y = 0.9
	add_child(shape)


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = material
	add_child(part)
