# Purpose: GOLDEN GOOSE's red-text behaviour (diary/DESIGN_UNIQUES.md, Vault chase gun): a small golden goose rides on
# the grenade launcher. Every honk_every seconds it HONKS at enemies (its head bobs, "HONK"): those within honk_reach come
# for it (set_target the holder). Its grenades are golden eggs (game/golden_egg.gd): they sit for 3 s, then hatch into a
# blast and chips. Others see the eggs (game/net_chase.gd "egg") and the honk ("honk": their copy's head bobs).
# Numbers in data/gun_uniques.json golden_goose "cfg".
# Dependencies: game/golden_egg.gd; the holder's explosives (enemy source, blast), damage numbers; the goose's "Head".
extends Node3D

const GoldenEgg = preload("res://game/golden_egg.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _head: Node3D
var _next_honk := 0.0
var honks := 0
var laid := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_head = gimmick.find_child("Head", true, false) as Node3D if gimmick != null else null
	_next_honk = Time.get_ticks_msec() / 1000.0 + float(_cfg.get("honk_every", 6.0))


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next_honk and _player != null:
		_next_honk = now + float(_cfg.get("honk_every", 6.0))
		honk()


func honk() -> void:
	honks += 1
	bob(_head)
	var numbers: Variant = _player.get("damage_numbers")
	if numbers != null and (numbers as Object).has_method("say") and _head != null and _head.is_inside_tree():
		numbers.call("say", _head.global_position + Vector3(0, 0.3, 0), "HONK", Color(1.0, 0.9, 0.4))
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	if source != null:
		for enemy: Node3D in source.call("enemy_list"):
			if is_instance_valid(enemy) and not enemy.health.is_dead() and enemy.global_position.distance_to(_player.global_position) <= float(_cfg.get("honk_reach", 20.0)) and enemy.has_method("set_target"):
				enemy.call("set_target", _player)
	var link: Node = get_tree().get_first_node_in_group("net_chase") if is_inside_tree() else null
	if link != null:
		link.call("send", "honk", -1, _player.global_position, 0, _player.global_position)


# Golden eggs instead of grenades.
func fire_projectile(origin: Vector3, dir: Vector3, stats: Dictionary) -> void:
	var vel := dir * float(stats.get("speed", 20.0)) * float(_cfg.get("egg_speed_share", 0.7))
	var rids: Array = [(_player as CollisionObject3D).get_rid()] if _player is CollisionObject3D else []
	lay(_player.get_parent(), _player.get("explosives"), origin, vel, true, float(stats.get("splash_damage", 0.0)), float(stats.get("splash_radius", 4.0)), int(_cfg.get("chips", 5)), float(_cfg.get("hatch_seconds", 3.0)), rids, _player.get("damage_numbers"))
	laid += 1
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "egg", -1, origin, 0, vel)


static func lay(world: Node, explosives: Node3D, from: Vector3, vel: Vector3, owned: bool, damage: float, radius: float, chips: int, hatch: float, ignore: Array, numbers: Variant) -> void:
	if world == null:
		return
	var egg := GoldenEgg.new()
	egg.explosives = explosives
	egg.owned = owned
	egg.damage = damage
	egg.radius = radius
	egg.chips = chips
	egg.hatch_seconds = hatch
	egg.numbers = numbers as Node
	world.add_child(egg)
	var rids: Array[RID] = []
	for rid: RID in ignore:
		rids.append(rid)
	egg.throw(from, vel, rids)


# The goose's honk: its head stretches up and back (also another player's copy).
static func bob(head: Node3D) -> void:
	if head == null or not is_instance_valid(head):
		return
	var tween := head.create_tween()
	tween.tween_property(head, "rotation:x", -0.5, 0.08)
	tween.tween_property(head, "rotation:x", 0.0, 0.25)
