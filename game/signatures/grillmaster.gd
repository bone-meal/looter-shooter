# Purpose: GRILLMASTER's red-text behaviour (diary/DESIGN_UNIQUES.md, region 3 chase gun): a little grill grate and
# tongs bolted to the shotgun. A burning enemy killed by its shot drops grilled food that any player can eat for
# health (game/grill_food.gd: shared online, the host decides who ate it). Numbers in data/gun_uniques.json
# grillmaster "cfg".
# Dependencies: game/grill_food.gd.
extends Node3D

const GrillFood = preload("res://game/grill_food.gd")

var _player: Node3D
var _cfg: Dictionary = {}


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(_gimmick: Node3D) -> void:
	pool(_player)


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


# After a shot hit `target` (its total damage this shot); killed = it died of it.
func on_target_hit(target: Node, at: Vector3, _amount: float, killed: bool) -> void:
	if not killed or not target.has_method("is_burning") or not bool(target.call("is_burning")):
		return
	var ground: Vector3 = (target as Node3D).global_position if target is Node3D else at
	var food := pool(_player)
	if food != null:
		food.drop(ground, float(_cfg.get("heal_share", 0.25)), float(_cfg.get("food_seconds", 20.0)))


# This world's food (made on first use next to `player`, the local player, who eats).
static func pool(player: Node3D) -> GrillFood:
	if player == null or not player.is_inside_tree():
		return null
	var found := player.get_tree().get_first_node_in_group("grill_food") as GrillFood
	if found == null and player.get_parent() != null:
		found = GrillFood.new()
		found.name = "GrillFood"
		player.get_parent().add_child(found)
	if found != null:
		found.eater = player
	return found
