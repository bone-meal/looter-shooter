# Purpose: the buildable boat as a thing in the world: its model, set where core/boat_rules.gd says it is, rocking a
# little on the water. Draws only; it has no collider (people aboard sit in the rules' seats, placed by the session).
# Dependencies: game/boat_model.gd. Data: data/boat.json "bob", passed to setup().
extends Node3D

const BoatModel = preload("res://game/boat_model.gd")

var _hull: MeshInstance3D
var _bob: Dictionary


func setup(config: Dictionary) -> void:
	_bob = config["bob"]
	_hull = BoatModel.build()
	add_child(_hull)


# at = its middle at the waterline (world), yaw = where the bow points, time = seconds for the rocking.
func show_at(at: Vector3, yaw: float, time: float) -> void:
	position = at
	rotation.y = yaw
	var wave := time * TAU / float(_bob["seconds"])
	_hull.position.y = sin(wave) * float(_bob["height"])
	_hull.rotation.z = deg_to_rad(float(_bob["roll_deg"])) * sin(wave * 0.7 + 1.0)
	_hull.rotation.x = deg_to_rad(float(_bob["pitch_deg"])) * sin(wave * 1.3)
