# Purpose: GRILLMASTER's red-text behaviour (diary/DESIGN_UNIQUES.md, region 3 chase gun): a little grill grate and
# tongs bolted to the shotgun. A burning enemy killed by its shot, or one it hit that burns to death within a few
# seconds (director: "burn to death should drop also"), drops grilled food that any player can eat for health (game/grill_food.gd: shared online, the host decides who ate it). Numbers in data/gun_uniques.json
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


# After a shot hit `target` (its total damage this shot); killed = it died of it. A target that lives is watched: if
# it dies burning within credit_seconds of our last hit (its burn did it, or anything else), it drops food too.
func on_target_hit(target: Node, _at: Vector3, _amount: float, killed: bool) -> void:
	if killed:
		_grilled(target)
		return
	target.set_meta("grill_hit", Time.get_ticks_msec() / 1000.0)
	if target.has_signal("died") and not target.is_connected("died", _on_died):
		target.connect("died", _on_died, CONNECT_ONE_SHOT)


func _on_died(enemy: Node) -> void:
	if Time.get_ticks_msec() / 1000.0 - float(enemy.get_meta("grill_hit", -100.0)) <= float(_cfg.get("credit_seconds", 10.0)):
		_grilled(enemy)


# A burning enemy we killed: food where it fell (once per enemy).
func _grilled(target: Node) -> void:
	if target.has_meta("grilled") or not target.has_method("is_burning") or not bool(target.call("is_burning")):
		return
	target.set_meta("grilled", true)
	var food := pool(_player)
	if food != null and target is Node3D:
		food.drop((target as Node3D).global_position, float(_cfg.get("heal_share", 0.25)), float(_cfg.get("food_seconds", 20.0)))


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
