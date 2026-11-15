# Purpose: KITE FLYER's red-text behaviour (diary/DESIGN_UNIQUES.md, region 5 chase gun): a string reel is bolted to
# the machine gun and a kite flies high behind the holder (game/kite.gd). In a storm it CATCHES LIGHTNING: every
# lightning flash of the weather (island_weather lightning_flash) strikes the kite, which dives onto the nearest enemy
# within reach and lets the bolt go there (blast: dive_damage x gun damage, radius dive_radius). Everyone sees the
# catch and the dive (game/net_chase.gd "kite_dive"); a teammate can grab the string from the air and glide behind
# the holder (game/kite.gd, on his machine).
# Numbers in data/gun_uniques.json kite_flyer "cfg".
# Dependencies: game/kite.gd, game/lightning_bolt.gd, game/island_weather.gd; the holder's explosives and weapon.
extends Node3D

const Kite = preload("res://game/kite.gd")
const LightningBolt = preload("res://game/lightning_bolt.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _kite: Node3D
var _weather: Node
var caught := 0
var _kills := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	if gimmick == null:
		return
	_kite = Kite.new()
	_kite.owned = true
	gimmick.add_child(_kite)
	_weather = get_tree().get_first_node_in_group("island_weather") if is_inside_tree() else null
	if _weather != null and _weather.has_signal("lightning_flash") and not _weather.is_connected("lightning_flash", catch_lightning):
		_weather.connect("lightning_flash", catch_lightning)


func stop() -> void:
	if _weather != null and is_instance_valid(_weather) and _weather.has_signal("lightning_flash") and _weather.is_connected("lightning_flash", catch_lightning):
		_weather.disconnect("lightning_flash", catch_lightning)
	if _kite != null and is_instance_valid(_kite):
		_kite.queue_free()
	_kite = null


func on_inspect() -> void:
	pass


# Outside storms too (director 2026-11-15): every kills_per_charge kills the kite catches a bolt of its own.
func on_target_hit(_target: Node, _at: Vector3, _amount: float, killed: bool) -> void:
	if not killed:
		return
	_kills += 1
	if _kills >= int(_cfg.get("kills_per_charge", 8)):
		_kills = 0
		catch_lightning()


func kite() -> Node3D:
	return _kite


# A flash: the kite takes the bolt and dives with it onto the nearest enemy (nobody near: it just lights up).
func catch_lightning() -> void:
	if _kite == null or not is_instance_valid(_kite) or bool(_kite.call("diving")) or not _kite.is_visible_in_tree():
		return
	caught += 1
	var top: Vector3 = _kite.global_position + Vector3(0, 40, 0)
	LightningBolt.strike(_player.get_parent(), top, _kite.global_position)
	var enemy := _nearest(_kite.global_position)
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if enemy == null:
		if link != null:
			link.call("send", "kite_dive", -1, top, 0, top)  # (spot = top: only the catch)
		return
	var spot: Vector3 = enemy.global_position + Vector3(0, 1.0, 0)
	var explosives: Node3D = _player.get("explosives")
	var damage := float(_player.get("weapon").damage) * float(_cfg.get("dive_damage", 6.0))
	var radius := float(_cfg.get("dive_radius", 3.0))
	var world := _player.get_parent()
	var from: Vector3 = _kite.global_position
	_kite.call("dive", spot, func() -> void:
		LightningBolt.strike(world, from, spot)
		if explosives != null:
			explosives.call("blast", spot, radius, damage))
	if link != null:
		link.call("send", "kite_dive", -1, top, 0, spot)


func _nearest(from: Vector3) -> Node3D:
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	if source == null:
		return null
	var best: Node3D = null
	var best_d := float(_cfg.get("reach", 35.0))
	for enemy: Node3D in source.call("enemy_list"):
		if not is_instance_valid(enemy) or enemy.health.is_dead():
			continue
		var d := enemy.global_position.distance_to(from)
		if d < best_d:
			best = enemy
			best_d = d
	return best
