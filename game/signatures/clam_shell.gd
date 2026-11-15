# Purpose: CLAM SHELL's red-text behaviour (diary/DESIGN_UNIQUES.md, region 6 chase gun): the double shotgun is closed
# in a giant clam. It opens to fire (node "Lid" of the clam_shell model swings up on every shot) and SNAPS SHUT on the
# reload key, biting whatever is right in front (bite x gun damage, within bite_reach in a forward cone). HOLD the
# trigger after a shot to grow a pearl (node "Pearl"; the gun holds its fire meanwhile); let go to fire it: a straight
# shot through up to pierce enemies (pearl_damage x gun damage x charge). Others see the snap ("clam"), the pearl
# growing (held_suffix "p0".."p4") and the pearl's flight ("pearl") on game/net_chase.gd.
# Numbers in data/gun_uniques.json clam_shell "cfg".
# Dependencies: the holder's weapon, explosives (enemy source), damage numbers; the camera.
extends Node3D

var _player: Node3D
var _cfg: Dictionary = {}
var _lid: Node3D
var _pearl: Node3D
var _open := 0.0  # 0..1 how far the lid is up
var _held_for := 0.0  # seconds the trigger has stayed down since the last shot
var _charge := 0.0  # 0..1, > 0 while a pearl grows
var _fired := false
var bites := 0
var pearls := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_lid = gimmick.find_child("Lid", true, false) as Node3D if gimmick != null else null
	_pearl = gimmick.find_child("Pearl", true, false) as Node3D if gimmick != null else null
	show_pearl(_pearl, 0.0)


func stop() -> void:
	_charge = 0.0


func on_inspect() -> void:
	pass


func on_fired() -> void:
	_open = 1.0
	_fired = true
	_held_for = 0.0


# The reload key: the clam snaps shut and bites (the reload itself goes on as usual).
func on_reload() -> bool:
	_open = 0.0
	bite()
	return false


func bite() -> void:
	bites += 1
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var ahead := -camera.global_transform.basis.z if camera != null else -_player.global_transform.basis.z
	var from := _player.global_position + Vector3(0, 1.2, 0)
	var dealt := float(_player.get("weapon").damage) * float(_cfg.get("bite", 8.0))
	for enemy: Node3D in _enemies():
		var to := enemy.global_position + Vector3(0, 1.0, 0) - from
		if to.length() <= float(_cfg.get("bite_reach", 2.5)) and to.normalized().dot(ahead) > 0.5:
			enemy.call("on_hit", dealt, enemy.global_position + Vector3(0, 1.0, 0), Vector3.UP)
			_number(enemy.global_position + Vector3(0, 1.2, 0), dealt)
	_tell("clam", from, from)


func blocks_fire() -> bool:
	return _charge > 0.0


func held_suffix() -> String:
	return "p%d" % mini(4, int(_charge * 5.0)) if _charge > 0.0 else ""


func charge() -> float:
	return _charge


func _process(delta: float) -> void:
	_open = move_toward(_open, 0.0, delta * 2.5)
	if _lid != null and is_instance_valid(_lid):
		_lid.rotation.x = -_open * 0.6
	var held := InputMap.has_action("shoot") and Input.is_action_pressed("shoot") and _player.has_method("_mouse_held") and bool(_player.call("_mouse_held")) and bool(_player.get("controls_enabled"))
	if held and _fired:
		_held_for += delta
		if _held_for >= float(_cfg.get("hold_start", 0.35)):
			_charge = minf(1.0, _charge + delta / float(_cfg.get("charge_seconds", 1.5)))
			_open = maxf(_open, 0.5)
	elif _charge > 0.0:
		release_pearl(_charge)
	if not held:
		_held_for = 0.0
		_fired = false
	show_pearl(_pearl, _charge)


# Fires the grown pearl: straight through up to `pierce` enemies.
func release_pearl(how_big: float) -> void:
	_charge = 0.0
	if how_big < float(_cfg.get("min_charge", 0.25)):
		return
	pearls += 1
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var from := camera.global_position
	var dir := -camera.global_transform.basis.z
	var to := from + dir * 80.0
	var dealt := float(_player.get("weapon").damage) * float(_cfg.get("pearl_damage", 10.0)) * how_big
	var query := PhysicsRayQueryParameters3D.create(from, to, 3)
	var skip: Array[RID] = []
	if _player is CollisionObject3D:
		skip.append((_player as CollisionObject3D).get_rid())
	var left := int(_cfg.get("pierce", 4))
	var space := get_world_3d().direct_space_state
	while left > 0:
		query.exclude = skip
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		var thing: Object = hit.collider
		if thing == null or not thing.has_method("on_hit"):
			to = hit.position
			break
		thing.call("on_hit", dealt, hit.position, hit.normal)
		_number(hit.position, dealt)
		skip.append((thing as CollisionObject3D).get_rid())
		left -= 1
	fly_pearl(_player.get_parent(), from + dir * 0.8, to)
	_tell("pearl", from + dir * 0.8, to)


func _number(at: Vector3, dealt: float) -> void:
	var numbers: Variant = _player.get("damage_numbers")
	if numbers != null and (numbers as Object).has_method("spawn"):
		numbers.call("spawn", at, dealt)


func _enemies() -> Array:
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	var out: Array = []
	if source != null:
		for enemy: Node3D in source.call("enemy_list"):
			if is_instance_valid(enemy) and not enemy.health.is_dead():
				out.append(enemy)
	return out


func _tell(kind: String, at: Vector3, b: Vector3) -> void:
	var link: Node = get_tree().get_first_node_in_group("net_chase") if is_inside_tree() else null
	if link != null:
		link.call("send", kind, -1, at, 0, b)


static func show_pearl(pearl: Node3D, how_big: float) -> void:
	if pearl == null or not is_instance_valid(pearl):
		return
	pearl.visible = how_big > 0.0
	pearl.scale = Vector3.ONE * (0.4 + how_big * 1.4)


# A pearl flying from `from` to `to` (a quick white ball; also another player's copy).
static func fly_pearl(world: Node, from: Vector3, to: Vector3) -> void:
	if world == null:
		return
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	ball.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.95, 1.0)
	mat.metallic_specular = 1.0
	mat.roughness = 0.15
	ball.material_override = mat
	world.add_child(ball)
	ball.global_position = from
	var tween := ball.create_tween()
	tween.tween_property(ball, "global_position", to, maxf(0.05, from.distance_to(to) / 90.0))
	tween.tween_callback(ball.queue_free)


# Another player's clam snapping shut (its "Lid").
static func snap(piece: Node3D) -> void:
	var lid := piece.find_child("Lid", true, false) as Node3D if piece != null else null
	if lid == null:
		return
	var tween := lid.create_tween()
	tween.tween_property(lid, "rotation:x", -0.6, 0.08)
	tween.tween_property(lid, "rotation:x", 0.0, 0.06)
