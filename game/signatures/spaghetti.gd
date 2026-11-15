# Purpose: SPAGHETTI's red-text behaviour (diary/DESIGN_UNIQUES.md, region 7 chase gun): the sniper's barrel is
# stretched far too long (long_barrel model). Hold the scope up for charge_seconds and the next shot is CHARGED: double
# damage (damage_mult), and every enemy near the line of the shot is stretched into a noodle for a moment and pulled
# into the line. The gun glows while charged; others see the glow (held_suffix "c") and the noodles
# (game/net_chase.gd "noodle": each machine stretches the enemies near that line).
# Numbers in data/gun_uniques.json spaghetti "cfg".
# Dependencies: the holder's scope_amount, explosives (enemy source); the gun model = the gimmick's parent.
extends Node3D

var _player: Node3D
var _cfg: Dictionary = {}
var _gun_model: Node3D
var _aimed := 0.0
var _charged := false
var noodled := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_gun_model = gimmick.get_parent() as Node3D if gimmick != null else null


func stop() -> void:
	glow(_gun_model, false)


func on_inspect() -> void:
	pass


func charged() -> bool:
	return _charged


func charge_now() -> void:  # dev steps
	_charged = true
	glow(_gun_model, true)


func _process(delta: float) -> void:
	if _player == null:
		return
	if float(_player.call("scope_amount")) > 0.9:
		_aimed += delta
		if not _charged and _aimed >= float(_cfg.get("charge_seconds", 2.0)):
			charge_now()
	else:
		_aimed = 0.0


func damage_mult() -> float:
	return float(_cfg.get("charged_mult", 2.0)) if _charged else 1.0


func held_suffix() -> String:
	return "c" if _charged else ""


func after_shot(origin: Vector3, dir: Vector3) -> void:
	if not _charged:
		return
	_charged = false
	_aimed = 0.0
	glow(_gun_model, false)
	noodled += stretch_line(get_tree(), _player.get("explosives"), origin, dir, _cfg, true)
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "noodle", -1, origin, 0, dir)


# Stretches every enemy near the line into a noodle; `pull` (the shooter's own) also pulls them into it. Returns how many.
static func stretch_line(_tree: SceneTree, explosives: Node3D, origin: Vector3, dir: Vector3, cfg: Dictionary, pull: bool) -> int:
	var source: Variant = explosives.get("source") if explosives != null else null
	if source == null:
		return 0
	var n := 0
	var reach := float(cfg.get("line_reach", 1.5))
	for enemy: Node3D in source.call("enemy_list"):
		if not is_instance_valid(enemy) or enemy.health.is_dead():
			continue
		var mid := enemy.global_position + Vector3(0, 1.0, 0)
		var t := (mid - origin).dot(dir)
		if t < 0.0 or t > float(cfg.get("length", 80.0)):
			continue
		var on_line := origin + dir * t
		if mid.distance_to(on_line) > reach:
			continue
		n += 1
		noodle(enemy)
		if pull and not String(enemy.get("enemy_id")).begins_with("boss"):
			var toward := Vector3(on_line.x - mid.x, 0.0, on_line.z - mid.z)
			if toward.length() > 0.05:
				enemy.call("push", toward.normalized() * float(cfg.get("pull", 6.0)))
	return n


# The noodle look: the body's pieces stretched tall and thin, then back.
static func noodle(enemy: Node3D) -> void:
	for child in enemy.get_children():
		if child is Node3D and not (child is CollisionShape3D) and not (child is Label3D):
			var piece := child as Node3D
			if piece.has_meta("noodle_scale"):
				continue
			piece.set_meta("noodle_scale", piece.scale)
			var back: Vector3 = piece.scale
			var tween := piece.create_tween()
			tween.tween_property(piece, "scale", Vector3(back.x * 0.5, back.y * 1.8, back.z * 0.5), 0.12)
			tween.tween_property(piece, "scale", back, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			tween.tween_callback(piece.remove_meta.bind("noodle_scale"))


static func glow(model: Node3D, on: bool) -> void:
	if model == null or not is_instance_valid(model):
		return
	var mat: StandardMaterial3D = model.get_meta("noodle_glow") if model.has_meta("noodle_glow") else null
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(0.55, 0.45, 0.12)
		model.set_meta("noodle_glow", mat)
	for mesh in model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_overlay = mat if on else null
