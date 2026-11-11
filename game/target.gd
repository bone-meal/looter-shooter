# Purpose: stand-in shootable dummy (colored box) that flashes when hit.
# Dependencies: none. Replaced by real enemies in milestone 3.
extends StaticBody3D

const BASE_COLOR := Color(0.8, 0.25, 0.25)
const FLASH_COLOR := Color(1, 1, 1)

var _material := StandardMaterial3D.new()


func _ready() -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 2, 1)
	mesh.mesh = box
	_material.albedo_color = BASE_COLOR
	mesh.material_override = _material
	add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = box.size
	shape.shape = box_shape
	add_child(shape)


func on_hit(_damage: float) -> void:
	_material.albedo_color = FLASH_COLOR
	get_tree().create_timer(0.12).timeout.connect(_reset_color)


func _reset_color() -> void:
	_material.albedo_color = BASE_COLOR
