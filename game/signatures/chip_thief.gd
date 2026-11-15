# Purpose: CHIP THIEF's red-text behaviour (diary/DESIGN_UNIQUES.md, region 5 chase gun): a bag of chips is taped to
# the shotgun and seagulls circle the holder (game/gull_flock.gd). Each kill tosses a chip onto the nearest other enemy
# and a gull dives at it to steal it, pecking (pecks x peck_damage x gun damage). The INSPECT key opens the bag: every
# idle gull dives at once, each at one of the nearest enemies (then a wait of bag_seconds). Everyone sees the gulls
# circle (game/unique_attach.gd gives other players' copies a flock) and dive (game/net_chase.gd "gull").
# Numbers in data/gun_uniques.json chip_thief "cfg".
# Dependencies: game/gull_flock.gd; the holder's explosives (enemy source), weapon and damage numbers.
extends Node3D

const GullFlock = preload("res://game/gull_flock.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _flock: Node3D
var _bag_after := 0.0
var sent := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	if gimmick == null:
		return
	_flock = make_flock(gimmick, _cfg)


func stop() -> void:
	if _flock != null and is_instance_valid(_flock):
		_flock.queue_free()
	_flock = null


func flock() -> Node3D:
	return _flock


# A flock over a gimmick (ours, or another player's copy: game/unique_attach.gd).
static func make_flock(gimmick: Node3D, cfg: Dictionary) -> Node3D:
	var f := GullFlock.new()
	f.count = int(cfg.get("gulls", 4))
	f.pecks = int(cfg.get("pecks", 4))
	gimmick.add_child(f)
	return f


func on_target_hit(target: Node, at: Vector3, _amount: float, killed: bool) -> void:
	if not killed or _flock == null:
		return
	var next := _nearest_list(at, target, 1)
	if not next.is_empty():
		_send(at, next[0])


# Opens the bag: every idle gull at once.
func on_inspect() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _flock == null or now < _bag_after:
		return
	_bag_after = now + float(_cfg.get("bag_seconds", 12.0))
	var from := _player.global_position
	for enemy: Node3D in _nearest_list(from, null, int(_flock.call("idle_count"))):
		_send(from, enemy)


func _send(from: Vector3, enemy: Node3D) -> void:
	if not bool(_flock.call("send_gull", from, enemy, enemy.global_position, _peck)):
		return
	sent += 1
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "gull", -1, from, 0, enemy.global_position)


func _peck(target: Node3D) -> void:
	if not is_instance_valid(target) or target.health.is_dead():
		return
	var dealt := float(_player.get("weapon").damage) * float(_cfg.get("peck_damage", 0.5))
	var head := target.global_position + Vector3(0, 1.6, 0)
	target.call("on_hit", dealt, head, Vector3.UP)
	var numbers: Variant = _player.get("damage_numbers")
	if numbers != null and (numbers as Object).has_method("spawn"):
		numbers.call("spawn", head, dealt)


# The nearest living enemies to `from` within reach (not `not_this`), closest first, at most `n`.
func _nearest_list(from: Vector3, not_this: Node, n: int) -> Array:
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	if source == null or n <= 0:
		return []
	var found: Array = []
	var reach := float(_cfg.get("reach", 20.0))
	for enemy: Node3D in source.call("enemy_list"):
		if enemy != not_this and is_instance_valid(enemy) and not enemy.health.is_dead() and enemy.global_position.distance_to(from) <= reach:
			found.append(enemy)
	found.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	return found.slice(0, n)
