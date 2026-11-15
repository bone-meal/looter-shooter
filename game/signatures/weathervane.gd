# Purpose: WEATHERVANE's red-text behaviour (diary/DESIGN_UNIQUES.md, region 5 chase gun): a little iron weathervane
# with a gilt rooster sits on the sniper's scope and turns with the wind (game/vane_turner.gd, on every machine).
# Damage follows the wind's strength (damage_mult: min_mult in calm air .. max_mult in a gale). In a storm the rooster
# draws lightning onto your target: a hit, once every bolt_every seconds, calls a bolt down on it (bolt_damage x gun
# damage; game/lightning_bolt.gd), seen by everyone (game/net_chase.gd "bolt").
# Wind and storm come from the island weather for now (game/island_weather.gd wind / storming); the sea's weather
# (sea step 4) is to answer the same calls. Outside storms (director 2026-11-15): every kills_per_charge kills the
# rooster stores a bolt, and the next hit calls it.
# Numbers in data/gun_uniques.json weathervane "cfg".
# Dependencies: game/island_weather.gd, game/lightning_bolt.gd; the holder's weapon.
extends Node3D

const LightningBolt = preload("res://game/lightning_bolt.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _next_bolt := 0.0
var bolts := 0
var force_storm := false  # dev steps: act as if it storms
var _kills := 0
var _charged := false  # every kills_per_charge kills: the next hit calls a bolt even without a storm


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(_gimmick: Node3D) -> void:
	pass


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


func _weather() -> Node:
	return get_tree().get_first_node_in_group("island_weather") if is_inside_tree() else null


func wind() -> float:
	var w := _weather()
	return float(w.call("wind")) if w != null else 0.25


func damage_mult() -> float:
	return lerpf(float(_cfg.get("min_mult", 0.8)), float(_cfg.get("max_mult", 1.6)), wind())


func storming() -> bool:
	var w := _weather()
	return force_storm or (w != null and bool(w.call("storming")))


func on_target_hit(target: Node, at: Vector3, _amount: float, killed: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if killed:
		_kills += 1
		if _kills >= int(_cfg.get("kills_per_charge", 8)):
			_kills = 0
			_charged = true  # the rooster has stored a bolt
		return
	if not (storming() and now >= _next_bolt) and not _charged:
		return
	if not (target is Node3D) or not target.has_method("on_hit"):
		return
	if storming() and now >= _next_bolt:
		_next_bolt = now + float(_cfg.get("bolt_every", 6.0))
	else:
		_charged = false
	bolts += 1
	var feet := (target as Node3D).global_position
	var dealt := float(_player.get("weapon").damage) * float(_cfg.get("bolt_damage", 4.0))
	target.call("on_hit", dealt, at, Vector3.UP)
	var numbers: Variant = _player.get("damage_numbers")
	if numbers != null and (numbers as Object).has_method("spawn"):
		numbers.call("spawn", at, dealt)
	LightningBolt.strike(_player.get_parent(), feet + Vector3(0, 40, 0), feet)
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "bolt", -1, feet + Vector3(0, 40, 0), 0, feet)


func charged() -> bool:
	return _charged
