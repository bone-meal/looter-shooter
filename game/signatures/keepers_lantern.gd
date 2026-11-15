# Purpose: KEEPER'S LANTERN's red-text behaviour (diary/DESIGN_UNIQUES.md, region 2 chase gun): an oil lantern swings
# under the pistol's barrel. While it is lit, enemies in its light glow and the fog thins round it for everyone near
# (game/lantern_glow.gd, also for other players' lanterns). The inspect key throws the lantern as a firebomb
# (game/firebomb.gd); a new one is lit on the hook 10 s later. Others see it go out on the gun (held_suffix "out"),
# the bomb fly and burn (game/net_chase.gd "bomb"). Numbers in data/gun_uniques.json keepers_lantern "cfg".
# Dependencies: game/lantern_glow.gd, game/firebomb.gd, game/net_chase.gd (optional), the gimmick's "Swing" node.
extends Node3D

const LanternGlow = preload("res://game/lantern_glow.gd")
const Firebomb = preload("res://game/firebomb.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _gimmick: Node3D
var _out_left := 0.0  # seconds until the next lantern is lit (0 = lit now)


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_gimmick = gimmick
	if _gimmick != null:
		_gimmick.set_meta("lantern_held", true)
	LanternGlow.ensure(_player.get_parent() if _player != null else null)
	_show_lit(_out_left <= 0.0)


func stop() -> void:
	pass


# The inspect key: throw the lit lantern as a firebomb.
func on_inspect() -> void:
	if _out_left > 0.0 or _player == null or _player.get_parent() == null:
		return
	var camera := get_viewport().get_camera_3d()
	var dir := -camera.global_transform.basis.z if camera != null else -_player.global_transform.basis.z
	var from: Vector3 = (_gimmick.global_position if _gimmick != null and is_instance_valid(_gimmick) else _player.global_position + Vector3(0, 1.4, 0)) + dir * 0.3
	var vel := dir * float(_cfg.get("throw_speed", 14.0)) + Vector3.UP * float(_cfg.get("throw_lift", 3.0))
	throw_bomb(_player.get_parent(), _player.get("explosives"), from, vel, true, float(_player.get("weapon").damage) * float(_cfg.get("bomb_damage", 4.0)), _cfg, [(_player as CollisionObject3D).get_rid()] if _player is CollisionObject3D else [])
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "bomb", -1, from, 0, vel)
	_out_left = float(_cfg.get("relight_seconds", 10.0))
	_show_lit(false)


# A bomb in the world (ours, or a copy of another player's: owned = false deals no damage).
static func throw_bomb(world: Node, explosives: Node3D, from: Vector3, vel: Vector3, owned: bool, damage: float, cfg: Dictionary, ignore: Array) -> void:
	var bomb := Firebomb.new()
	bomb.explosives = explosives
	bomb.owned = owned
	bomb.cfg = cfg
	bomb.damage = damage
	world.add_child(bomb)
	var rids: Array[RID] = []
	for rid: RID in ignore:
		rids.append(rid)
	bomb.throw(from, vel, rids)


# What others see on our gun after the body id ("out" while the lantern is thrown; game/remote_player.gd).
func held_suffix() -> String:
	return "out" if _out_left > 0.0 else ""


func lit() -> bool:
	return _out_left <= 0.0


func _process(delta: float) -> void:
	if _out_left > 0.0:
		_out_left -= delta
		if _out_left <= 0.0:
			_show_lit(true)


func _show_lit(on: bool) -> void:
	if _gimmick == null or not is_instance_valid(_gimmick):
		return
	var swing := _gimmick.find_child("Swing", true, false) as Node3D
	if swing != null:
		swing.visible = on
