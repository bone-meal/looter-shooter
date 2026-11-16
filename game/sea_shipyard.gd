# Purpose: the shipyard of sea step 5c (director: a SLIPWAY on region 1's test island until the home port's dockyard
# of step 7): the slipway model with a walkable ramp and the shipwright's workbench, whose interact key opens the
# Carpentry station "shipyard" (data/fantasy/skilling.json recipes build_<ship>; the side ships also need their found
# plan), and where a launched ship lies off the foot of the ramp (one beside the other).
# Dependencies: game/fantasy_models.gd, assets/models/sea/slipway.gltf, data/sea/ships.json "shipyard"; the fantasy
# world (its work's station_opened opens the window) through the sea world's skills.
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const MODEL := "res://assets/models/sea/slipway.gltf"
const REACH := 2.2

var cfg: Dictionary  # data/sea/ships.json "shipyard"

var _sea: Node3D
var _player: CharacterBody3D


func setup(sea_world: Node3D, player: CharacterBody3D, shipyard_cfg: Dictionary) -> void:
	_sea = sea_world
	_player = player
	cfg = shipyard_cfg
	position = Vector3(float(cfg["at"][0]), 0.0, float(cfg["at"][1]))
	rotation.y = deg_to_rad(float(cfg["yaw"]))
	if ResourceLoader.exists(MODEL):
		var model := (load(MODEL) as PackedScene).instantiate() as Node3D
		for found in model.find_children("*", "MeshInstance3D", true, false):
			FantasyModels.dress((found as MeshInstance3D).mesh)
		add_child(model)
	var body := StaticBody3D.new()
	add_child(body)
	var ramp := BoxShape3D.new()  # the planked ramp, 22 m long, sloping into the sea
	ramp.size = Vector3(5.2, 0.3, 22.4)
	var slope := atan2(2.6, 22.0)
	_solid(body, ramp, Transform3D(Basis(Vector3.RIGHT, -slope), Vector3(0.0, -0.7, -3.0)))
	var top := BoxShape3D.new()
	top.size = Vector3(2.4, 1.0, 1.0)
	_solid(body, top, Transform3D(Basis.IDENTITY, Vector3(float(cfg["bench"][0]), 0.5, float(cfg["bench"][1]))))


func _solid(body: StaticBody3D, shape: Shape3D, at: Transform3D) -> void:
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.transform = at
	body.add_child(holder)


func _near_bench() -> bool:
	var spot := global_transform * Vector3(float(cfg["bench"][0]), 0.0, float(cfg["bench"][1]))
	return Vector2(spot.x - _player.global_position.x, spot.z - _player.global_position.z).length() <= REACH


func prompt(key: String) -> String:
	return "[%s] Shipyard: build a ship" % key if _near_bench() and _sea.get("skills") != null else ""


func interact() -> bool:
	var skills: Variant = _sea.get("skills")
	if not _near_bench() or skills == null:
		return false
	((skills as Node).get("work") as Object).emit_signal("station_opened", "shipyard")
	return true


# Where the k-th launched ship lies (sea coordinates x, z and yaw in degrees): off the ramp's foot, bow to the sea,
# the next ones alternately beside it.
func launch_spot(k: int, half_length: float) -> Vector3:
	var yaw := deg_to_rad(float(cfg["yaw"]))
	var ahead := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(cos(yaw), -sin(yaw))
	var lane := float((k + 1) >> 1) * (1.0 if k % 2 == 1 else -1.0)
	var at := Vector2(float(cfg["at"][0]), float(cfg["at"][1])) + ahead * (float(cfg["launch"]) + half_length) + side * lane * float(cfg["spread"])
	return Vector3(at.x, at.y, float(cfg["yaw"]))
