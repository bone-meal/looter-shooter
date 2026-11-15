# Purpose: VOLCANO SAUCE's red-text behaviour (diary/DESIGN_UNIQUES.md, region 3 chase gun): a bottle of hot sauce is
# taped to the pistol's grip. Every bullet that hits adds heat to its target (shown over it: MILD, MEDIUM, HOT, EXTRA
# HOT); at 5 heat the target erupts in a geyser of fire (game/fire_geyser.gd), which also burns enemies near it.
# Heat cools off after a few seconds without a hit. Others see the geyser (game/net_chase.gd "geyser").
# Numbers in data/gun_uniques.json volcano_sauce "cfg".
# Dependencies: game/fire_geyser.gd; the holder's explosives, weapon and damage_numbers.
extends Node3D

const FireGeyser = preload("res://game/fire_geyser.gd")
const WORDS := ["MILD", "MEDIUM", "HOT", "EXTRA HOT"]

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


# A joiner's kill credited later by the host: its heat was already counted by the shot itself.
func on_kill_credit(_target: Node, _at: Vector3, _amount: float) -> void:
	pass


func on_target_hit(target: Node, at: Vector3, _amount: float, _killed: bool) -> void:
	if not (target is Node3D) or not target.has_method("on_hit"):
		return
	var now := Time.get_ticks_msec() / 1000.0
	var heat := int(target.get_meta("sauce_heat", 0))
	if now - float(target.get_meta("sauce_at", -100.0)) > float(_cfg.get("cool_seconds", 4.0)):
		heat = 0  # it cooled off
	heat += 1
	target.set_meta("sauce_at", now)
	if heat < int(_cfg.get("erupt_at", 5)):
		target.set_meta("sauce_heat", heat)
		_say(at, WORDS[mini(heat - 1, WORDS.size() - 1)], Color(1.0, 0.55 - 0.1 * float(heat), 0.15))
		return
	target.set_meta("sauce_heat", 0)
	var ground := (target as Node3D).global_position
	erupt(_player.get_parent(), _player.get("explosives"), ground, true, float(_player.get("weapon").damage) * float(_cfg.get("erupt_damage", 6.0)), _cfg)
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "geyser", -1, ground)


# A geyser in the world (ours; or another player's copy, owned = false: no damage here).
static func erupt(world: Node, explosives: Node3D, at: Vector3, owned: bool, damage: float, cfg: Dictionary) -> void:
	if world == null:
		return
	var geyser := FireGeyser.new()
	geyser.explosives = explosives
	geyser.owned = owned
	geyser.damage = damage
	geyser.radius = float(cfg.get("erupt_radius", 2.5))
	geyser.burn_share = float(cfg.get("burn_share", 0.2))
	world.add_child(geyser)
	geyser.erupt(at)


func _say(at: Vector3, words: String, color: Color) -> void:
	var numbers: Variant = _player.get("damage_numbers") if _player != null else null
	if numbers is Node:
		(numbers as Node).call("say", at, words, color)
