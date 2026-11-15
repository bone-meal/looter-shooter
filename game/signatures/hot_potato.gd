# Purpose: HOT POTATO's red-text behaviour (diary/DESIGN_UNIQUES.md, region 3 chase gun): a foil-wrapped potato is
# strapped to the grenade launcher, and the whole gun glows hotter with every shot (data cool_per_second may let it
# cool when it rests: 0 = never; once red-hot it stays so until thrown).
# At full heat the RELOAD key throws the gun as a big bomb (game/potato_bomb.gd); it is back in your hands 5 s later,
# cooled. While it is away the gun is gone from your hands and cannot fire. Others see the glow and the gun gone
# (held_suffix: "h0".."h9" heat, "out" thrown) and the bomb fly (game/net_chase.gd "potato").
# Numbers in data/gun_uniques.json hot_potato "cfg".
# Dependencies: game/potato_bomb.gd; the holder's explosives and weapon; the gun model = the gimmick's parent.
extends Node3D

const PotatoBomb = preload("res://game/potato_bomb.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _gimmick: Node3D
var _gun_model: Node3D
var _heat := 0.0  # 0..1
var _away := 0.0  # seconds until the gun is back in hand
var _shown_heat := -1.0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_gimmick = gimmick
	_gun_model = gimmick.get_parent() as Node3D if gimmick != null else null
	_shown_heat = -1.0
	_show_heat()


func stop() -> void:
	paint(_gun_model, 0.0)
	if _gun_model != null and is_instance_valid(_gun_model):
		_gun_model.visible = true


func on_inspect() -> void:
	pass


# Every shot of the gun: hotter.
func on_fired() -> void:
	_heat = minf(1.0, _heat + float(_cfg.get("heat_per_shot", 0.125)))


# The reload key: at full heat the gun is thrown instead (true = the key was used here, no reload).
func on_reload() -> bool:
	if _away > 0.0:
		return true
	if _heat < 1.0:
		return false
	var camera := get_viewport().get_camera_3d()
	var dir := -camera.global_transform.basis.z if camera != null else -_player.global_transform.basis.z
	var from: Vector3 = (_gun_model.global_position if _gun_model != null and is_instance_valid(_gun_model) else _player.global_position + Vector3(0, 1.4, 0)) + dir * 0.5
	var vel := dir * float(_cfg.get("throw_speed", 16.0)) + Vector3.UP * float(_cfg.get("throw_lift", 3.5))
	var rids: Array = [(_player as CollisionObject3D).get_rid()] if _player is CollisionObject3D else []
	throw_bomb(_player.get_parent(), _player.get("explosives"), from, vel, true, float(_player.get("weapon").damage) * float(_cfg.get("bomb_damage", 8.0)), float(_cfg.get("bomb_radius", 6.0)), rids)
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "potato", -1, from, 0, vel)
	_away = float(_cfg.get("back_seconds", 5.0))
	_heat = 0.0
	return true


# While the gun is away it cannot fire.
func blocks_fire() -> bool:
	return _away > 0.0


func held_suffix() -> String:
	return "out" if _away > 0.0 else "h%d" % mini(9, int(_heat * 10.0))


static func throw_bomb(world: Node, explosives: Node3D, from: Vector3, vel: Vector3, owned: bool, damage: float, radius: float, ignore: Array) -> void:
	if world == null:
		return
	var bomb := PotatoBomb.new()
	bomb.explosives = explosives
	bomb.owned = owned
	bomb.damage = damage
	bomb.radius = radius
	world.add_child(bomb)
	var rids: Array[RID] = []
	for rid: RID in ignore:
		rids.append(rid)
	bomb.throw(from, vel, rids)


# The glow over a gun model at `how_hot` 0..1 (also another player's copy: game/unique_attach.gd show_extra).
static func paint(model: Node3D, how_hot: float) -> void:
	if model == null or not is_instance_valid(model):
		return
	var glow: StandardMaterial3D = model.get_meta("potato_glow") if model.has_meta("potato_glow") else null
	if glow == null:
		glow = StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		model.set_meta("potato_glow", glow)
	glow.albedo_color = Color(1.0, 0.32, 0.04) * how_hot * 0.9
	for mesh in model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_overlay = glow if how_hot > 0.02 else null


func _process(delta: float) -> void:
	if _away > 0.0:
		_away -= delta
		if _gun_model != null and is_instance_valid(_gun_model):
			_gun_model.visible = _away <= 0.0
	elif _heat > 0.0 and _heat < 1.0:  # (once full it stays full until thrown)
		_heat = maxf(0.0, _heat - float(_cfg.get("cool_per_second", 0.02)) * delta)
	_show_heat()


func _show_heat() -> void:
	if absf(_heat - _shown_heat) < 0.02:
		return
	_shown_heat = _heat
	paint(_gun_model, _heat)


func heat() -> float:
	return _heat
