# Purpose: AVALANCHE CONTROL's rolling snowball (diary/DESIGN_UNIQUES.md, region 4 chase gun): started where a rocket
# hits the ground, it rolls on in the rocket's flat direction, following the ground and growing as it goes, and
# buries every enemy it rolls over once (freeze + push along its way, a little damage). It breaks up against a wall or
# when its time is out. The shooter's own snowball does all that; another player's copy (game/net_chase.gd
# "snowball") rolls the same way and only shows. At most MAX_ROLLING at once (the host budget).
# Dependencies: game/explosives.gd (enemy source, damage numbers), the snowball model, game/fx_kit.gd (snow).
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

const MODEL := "res://assets/models/weapons/uniques/snowball.gltf"
const MAX_ROLLING := 6
const GROUP := "snowballs"

var explosives: Node3D
var owned := true
var damage := 0.0
var dir := Vector3.FORWARD  # flat
var cfg: Dictionary = {}

var _age := 0.0
var _body: Node3D
var _query := PhysicsRayQueryParameters3D.new()
var _hit := {}  # enemies already buried by this ball
var _spin := 0.0


static func can_start(tree: SceneTree) -> bool:
	return tree.get_nodes_in_group(GROUP).size() < MAX_ROLLING


func _ready() -> void:
	add_to_group(GROUP)
	if ResourceLoader.exists(MODEL):
		_body = (load(MODEL) as PackedScene).instantiate() as Node3D
		add_child(_body)
	_query.collision_mask = 1
	_size_body()
	var trail := FxKit.particles(Color(0.95, 0.97, 1.0, 0.9), 12, 0.8, 0.35, 1.5, 60.0, -2.0, false, false)  # snow kicked up as it rolls
	trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	trail.emission_sphere_radius = 0.4
	add_child(trail)


func radius() -> float:
	var t := clampf(_age / float(cfg.get("roll_seconds", 4.0)), 0.0, 1.0)
	return lerpf(float(cfg.get("start_radius", 0.5)), float(cfg.get("end_radius", 1.6)), t)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= float(cfg.get("roll_seconds", 4.0)):
		_break()
		return
	var r := radius()
	var step := dir * float(cfg.get("roll_speed", 7.0)) * delta
	var space := get_world_3d().direct_space_state
	_query.from = global_position + Vector3(0, r, 0)  # a wall ahead breaks it up
	_query.to = _query.from + dir * (r + step.length())
	var wall := space.intersect_ray(_query)
	if not wall.is_empty() and not (wall.collider as Object).has_method("on_hit") and (wall.normal as Vector3).y < 0.5:
		_break()
		return
	global_position += step
	_query.from = global_position + Vector3(0, r + 1.0, 0)  # follow the ground
	_query.to = global_position + Vector3(0, -2.0, 0)
	var ground := space.intersect_ray(_query)
	if not ground.is_empty() and not (ground.collider as Object).has_method("on_hit"):
		global_position.y = (ground.position as Vector3).y
	_spin += step.length() / maxf(r, 0.1)
	_size_body()
	if owned:
		_bury(r)


func _size_body() -> void:
	if _body == null:
		return
	var r := radius()
	_body.position = Vector3(0, r * 0.9, 0)
	_body.basis = Basis(dir.cross(Vector3.UP).normalized() if dir.length() > 0.1 else Vector3.RIGHT, -_spin).scaled(Vector3.ONE * r)


func _bury(r: float) -> void:
	if explosives == null or explosives.get("source") == null:
		return
	var center := global_position + Vector3(0, r * 0.9, 0)
	for enemy: Node3D in explosives.get("source").call("enemy_list"):
		if not is_instance_valid(enemy) or _hit.has(enemy) or enemy.health.is_dead():
			continue
		var feet := enemy.global_position
		if Vector2(feet.x - center.x, feet.z - center.z).length() > r + 0.5 or absf(feet.y - global_position.y) > r + 1.5:
			continue
		_hit[enemy] = true
		enemy.call("on_hit", damage, feet + Vector3(0, 1.0, 0), Vector3.UP)
		if enemy.has_method("apply_freeze"):
			enemy.call("apply_freeze", float(cfg.get("freeze_seconds", 2.0)))
		if enemy.has_method("push"):
			enemy.call("push", dir * float(cfg.get("push", 8.0)))
		if explosives.get("numbers") != null:
			explosives.get("numbers").call("spawn", feet + Vector3(0, 1.0, 0), damage)


func _break() -> void:  # it bursts into powder: swells a little, then shrinks away
	set_physics_process(false)
	FxKit.burst(get_parent(), global_position + Vector3(0, radius() * 0.9, 0), Color(0.95, 0.97, 1.0, 0.9), 20, 0.9, 0.5, 3.0)
	remove_from_group(GROUP)
	if _body == null:
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(_body, "scale", _body.scale * 1.35, 0.08)
	tween.tween_property(_body, "scale", Vector3.ONE * 0.01, 0.2)
	tween.tween_callback(queue_free)


func buried() -> int:
	return _hit.size()
