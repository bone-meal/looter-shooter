# Purpose: a card table on the club island beach (build step 5: plain; mats, figures and the 3D card view come in step
# 12): wooden top with a green mat, four legs, two stools, a pink parasol with a white hem and a small sign. The top has a collider.
# Built from primitive meshes (about a dozen draws, shared materials).
# Dependencies: none.
extends Node3D

const TOP_Y := 0.78
const SIZE := Vector3(1.6, 0.06, 1.0)

static var _wood: StandardMaterial3D
static var _mat_green: StandardMaterial3D
static var _cloth_a: StandardMaterial3D
static var _cloth_b: StandardMaterial3D


func _ready() -> void:
	if _wood == null:
		_wood = _material(Color(0.55, 0.38, 0.22))
		_mat_green = _material(Color(0.1, 0.38, 0.26))
		_cloth_a = _material(Color(0.95, 0.95, 0.9))
		_cloth_b = _material(Color(0.9, 0.2, 0.45))
	_box(SIZE, Vector3(0, TOP_Y, 0), _wood)
	_box(Vector3(1.42, 0.012, 0.84), Vector3(0, TOP_Y + 0.036, 0), _mat_green)
	for x: float in [-0.7, 0.7]:
		for z: float in [-0.4, 0.4]:
			_box(Vector3(0.07, TOP_Y, 0.07), Vector3(x, TOP_Y * 0.5, z), _wood)
	for z: float in [-0.85, 0.85]:  # stools: player side (-z) and dealer side (+z)
		_cyl(0.22, 0.22, 0.05, Vector3(0, 0.48, z), _wood)
		_cyl(0.04, 0.04, 0.46, Vector3(0, 0.23, z), _wood)
	_cyl(0.03, 0.03, 2.4, Vector3(0, 1.2, 0), _cloth_a)  # parasol pole through the table
	_cyl(0.0, 1.5, 0.45, Vector3(0, 2.45, 0), _cloth_b)  # canopy
	_cyl(1.5, 1.5, 0.08, Vector3(0, 2.2, 0), _cloth_a)  # white hem
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(SIZE.x, TOP_Y, SIZE.z)
	shape.shape = box
	shape.position = Vector3(0, TOP_Y * 0.5, 0)
	body.add_child(shape)
	add_child(body)
	var sign_label := Label3D.new()
	sign_label.text = "You got me Lobster?\ncard table"
	sign_label.font_size = 48
	sign_label.pixel_size = 0.006
	sign_label.outline_size = 10
	sign_label.modulate = Color(1.0, 0.85, 0.3)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign_label.position = Vector3(0, 2.95, 0)
	add_child(sign_label)


# Where the cards are looked at from (the player's side of the mat).
func look_point() -> Vector3:
	return to_global(Vector3(0, TOP_Y, 0.1))


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _box(box_size: Vector3, pos: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	add_child(n)


func _cyl(top: float, bottom: float, height: float, pos: Vector3, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	add_child(n)
