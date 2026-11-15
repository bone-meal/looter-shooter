# Purpose: PENGUIN RESCUE's red-text behaviour (diary/DESIGN_UNIQUES.md, region 4 chase gun, kept from the first list):
# a little penguin rides on the pistol's slide. Every kill frees a penguin where the enemy fell; it belly-slides into
# the nearest other enemy and pops (game/penguin_slider.gd). Others see it slide and pop (game/net_chase.gd "penguin").
# Numbers in data/gun_uniques.json penguin_rescue "cfg".
# Dependencies: game/penguin_slider.gd; the holder's explosives (enemy source) and weapon.
extends Node3D

const PenguinSlider = preload("res://game/penguin_slider.gd")

var _player: Node3D
var _cfg: Dictionary = {}


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(_gimmick: Node3D) -> void:
	pass


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


func on_target_hit(target: Node, _at: Vector3, _amount: float, killed: bool) -> void:
	if not killed or not (target is Node3D):
		return
	var from := (target as Node3D).global_position
	var next := _nearest(from, target)
	var away := Vector3(from.x - _player.global_position.x, 0.0, from.z - _player.global_position.z).normalized()
	var goal := next.global_position if next != null else from + away * 4.0  # nobody left: it slides on away from us
	release(_player.get_parent(), _player.get("explosives"), from, next, goal, true, float(_player.get("weapon").damage) * float(_cfg.get("pop_damage", 3.0)), _cfg)
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "penguin", -1, from, 0, goal)


# A freed penguin in the world (ours; or another player's copy, owned = false: no damage, slides to `goal`).
static func release(world: Node, explosives: Node3D, from: Vector3, target: Node3D, goal: Vector3, owned: bool, damage: float, cfg: Dictionary) -> void:
	if world == null:
		return
	var bird := PenguinSlider.new()
	bird.explosives = explosives
	bird.owned = owned
	bird.damage = damage
	bird.target = target
	bird.goal = goal
	bird.radius = float(cfg.get("pop_radius", 2.5))
	bird.speed = float(cfg.get("slide_speed", 9.0))
	world.add_child(bird)
	bird.global_position = from


func _nearest(from: Vector3, not_this: Node) -> Node3D:
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	if source == null:
		return null
	var best: Node3D = null
	var best_d := float(_cfg.get("reach", 25.0))
	for enemy: Node3D in source.call("enemy_list"):
		if enemy == not_this or not is_instance_valid(enemy) or enemy.health.is_dead():
			continue
		var d := enemy.global_position.distance_to(from)
		if d < best_d:
			best = enemy
			best_d = d
	return best
