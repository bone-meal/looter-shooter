# Purpose: a rope thrown from a ship's rail to someone in the water (sea step 5b): the cork float lying on the water
# where it landed (riding the surface) and the line from the rail to it, redrawn every frame as the ship moves. It
# lasts `seconds`; game/sea_swim.gd hauls up whoever reaches the float.
# Dependencies: game/fantasy_models.gd (materials), assets/models/sea/rope_float.gltf.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const FLOAT_MODEL := "res://assets/models/sea/rope_float.gltf"

var ship: Node3D  # game/sea_ship.gd it was thrown from
var rail_local := Vector3.ZERO  # ship-space point on the rail it is tied to
var left := 15.0  # seconds before it is pulled back in

var _float := Node3D.new()
var _line := MeshInstance3D.new()


func setup(from_ship: Node3D, rail: Vector3, lands_at: Vector3, seconds: float) -> void:
	ship = from_ship
	rail_local = rail
	left = seconds
	add_child(_float)
	if ResourceLoader.exists(FLOAT_MODEL):
		var model := (load(FLOAT_MODEL) as PackedScene).instantiate() as Node3D
		for found in model.find_children("*", "MeshInstance3D", true, false):
			FantasyModels.dress((found as MeshInstance3D).mesh)
		_float.add_child(model)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.025
	cyl.bottom_radius = 0.025
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	cyl.material = FantasyModels.tinted("leather", Color(0.62, 0.52, 0.36))
	_line.mesh = cyl
	add_child(_line)
	_float.global_position = lands_at


# Each frame: the float on the water (scene height `surface`), the line from the rail to it.
func follow(surface: float, delta: float) -> void:
	left -= delta
	_float.global_position.y = surface - 0.05
	var a: Vector3 = ship.global_transform * rail_local
	var b := _float.global_position + Vector3(0, 0.1, 0)
	var length := a.distance_to(b)
	_line.global_position = (a + b) * 0.5
	if length > 0.01:
		_line.global_basis = Basis(Quaternion(Vector3.UP, (b - a) / length)) * Basis.from_scale(Vector3(1.0, length, 1.0))


func float_at() -> Vector3:
	return _float.global_position
