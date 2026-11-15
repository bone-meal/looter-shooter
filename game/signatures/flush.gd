# Purpose: FLUSH's red-text behaviour (diary/DESIGN_UNIQUES.md, region 7 chase gun): a toilet tank's float ball and
# flush handle on the grenade launcher. Its grenades blow up as usual and open a whirlpool where they land
# (game/whirlpool.gd): enemies swirl, the weak ones (below 15 %) are flushed. Others see it (game/net_chase.gd "whirl").
# Numbers in data/gun_uniques.json flush "cfg".
# Dependencies: game/whirlpool.gd; the holder's explosives (game/explosives.gd fire with on_land).
extends Node3D

const Whirlpool = preload("res://game/whirlpool.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var opened := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(_gimmick: Node3D) -> void:
	pass


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


func fire_projectile(origin: Vector3, dir: Vector3, stats: Dictionary) -> void:
	_player.get("explosives").call("fire", origin, dir, stats, landed)


func landed(point: Vector3, _normal: Vector3, _collider: Object) -> void:
	if not is_inside_tree() or not open(_player.get_parent(), _player.get("explosives"), point, true, _cfg):
		return
	opened += 1
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "whirl", -1, point, 0, point)


# A whirlpool in the world (ours; or another player's copy, owned = false). False = too many open.
static func open(world: Node, explosives: Node3D, at: Vector3, owned: bool, cfg: Dictionary) -> bool:
	if world == null or not Whirlpool.can_open(world.get_tree()):
		return false
	var pool := Whirlpool.new()
	pool.explosives = explosives
	pool.owned = owned
	pool.radius = float(cfg.get("radius", 4.0))
	pool.seconds = float(cfg.get("seconds", 4.0))
	pool.flush_share = float(cfg.get("flush_share", 0.15))
	pool.swirl = float(cfg.get("swirl", 6.0))
	world.add_child(pool)
	pool.global_position = at + Vector3(0, 0.05, 0)
	return true
