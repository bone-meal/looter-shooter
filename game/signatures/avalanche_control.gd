# Purpose: AVALANCHE CONTROL's red-text behaviour (diary/DESIGN_UNIQUES.md, region 4 chase gun): a ski pole is
# strapped to the rocket tube. Its rockets fly and blow up as usual, and one that hits the GROUND (not an enemy, not a
# wall) starts a rolling snowball there that grows and buries everything in its path (game/snowball.gd: freeze +
# push). Others see the snowball roll (game/net_chase.gd "snowball").
# Numbers in data/gun_uniques.json avalanche_control "cfg" (damage_share = a share of the rocket's splash damage).
# Dependencies: game/snowball.gd; the holder's explosives (game/explosives.gd fire with on_land).
extends Node3D

const Snowball = preload("res://game/snowball.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var started := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(_gimmick: Node3D) -> void:
	pass


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


# The rocket flies as usual; where it lands decides the snowball.
func fire_projectile(origin: Vector3, dir: Vector3, stats: Dictionary) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	flat = flat.normalized() if flat.length() > 0.05 else -_player.global_transform.basis.z
	var damage := float(stats.get("splash_damage", 0.0)) * float(_cfg.get("damage_share", 0.25))
	_player.get("explosives").call("fire", origin, dir, stats, landed.bind(flat, damage))


func landed(point: Vector3, normal: Vector3, collider: Object, flat: Vector3, damage: float) -> void:
	if normal.y < 0.6 or (collider != null and collider.has_method("on_hit")):
		return  # an enemy or a wall: just the blast
	if not is_inside_tree() or not roll(_player.get_parent(), _player.get("explosives"), point, flat, true, damage, _cfg):
		return
	started += 1
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "snowball", -1, point, 0, flat)


# A snowball in the world (ours; or another player's copy, owned = false: no damage). False = too many rolling.
static func roll(world: Node, explosives: Node3D, from: Vector3, flat: Vector3, owned: bool, damage: float, cfg: Dictionary) -> bool:
	if world == null or not Snowball.can_start(world.get_tree()):
		return false
	var ball := Snowball.new()
	ball.explosives = explosives
	ball.owned = owned
	ball.damage = damage
	ball.dir = flat
	ball.cfg = cfg
	world.add_child(ball)
	ball.global_position = from
	return true
