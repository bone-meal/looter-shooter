# Purpose: CARBON COPY's red-text behaviour (diary/DESIGN_UNIQUES.md, raid chase gun): an office photocopier rides on the
# shotgun. Every shot prints a paper copy of you beside you (alternating sides) that fires once at what you aim at
# (copy_damage x gun damage), falls over and lies there (game/paper_copies.gd). Others see the copies print and fire
# (game/net_chase.gd "copy"). The copier's sheet slides out and its scan light blinks with each print.
# Numbers in data/gun_uniques.json carbon_copy "cfg".
# Dependencies: game/paper_copies.gd; the holder's weapon and camera; the photocopier gimmick ("Sheet", "Scan").
extends Node3D

const PaperCopies = preload("res://game/paper_copies.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _sheet: Node3D
var _scan: Node3D
var _side := 1.0
var _flash := 0.0
var printed := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_sheet = gimmick.find_child("Sheet", true, false) as Node3D if gimmick != null else null
	_scan = gimmick.find_child("Scan", true, false) as Node3D if gimmick != null else null


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


func on_fired() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var forward := -camera.global_transform.basis.z if camera != null else -_player.global_transform.basis.z
	var eye := camera.global_position if camera != null else _player.global_position + Vector3(0, 1.6, 0)
	var flat := Vector3(forward.x, 0.0, forward.z).normalized() if Vector2(forward.x, forward.z).length() > 0.05 else Vector3.FORWARD
	var right := flat.cross(Vector3.UP)
	var at := _player.global_position + right * _side * float(_cfg.get("spacing", 1.1))
	_side = -_side
	var aim := eye + forward * 40.0
	var yaw := atan2(-flat.x, -flat.z)
	var rids: Array = [(_player as CollisionObject3D).get_rid()] if _player is CollisionObject3D else []
	var copies := PaperCopies.pool(_player.get_parent())
	if copies == null:
		return
	copies.call("print_copy", at, yaw, aim, true, float(_player.get("weapon").damage) * float(_cfg.get("copy_damage", 3.0)), rids)
	printed += 1
	_flash = 0.25
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", "copy", -1, at, 0, aim)


func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	if _sheet != null and is_instance_valid(_sheet):
		_sheet.position.z = 0.0 if _flash <= 0.0 else -0.03 * (_flash / 0.25)  # the sheet slides out toward the muzzle (-z)
	if _scan != null and is_instance_valid(_scan):
		_scan.visible = _flash > 0.0
