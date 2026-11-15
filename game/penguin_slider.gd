# Purpose: PENGUIN RESCUE's freed penguin (diary/DESIGN_UNIQUES.md, region 4 chase gun): it pops out where a kill fell,
# flops onto its belly and slides along the ground into the nearest enemy, where it pops (a small blast). With nobody
# to slide into it slides ahead and pops anyway. The shooter's own penguin deals the damage; another player's copy
# (game/net_chase.gd "penguin") slides to the spot it was aimed at and only shows the pop.
# Dependencies: game/explosives.gd (blast, show_flash, enemy source, sounds), the penguin model.
extends Node3D

const MODEL := "res://assets/models/weapons/uniques/penguin.gltf"

var explosives: Node3D
var owned := true
var damage := 0.0
var radius := 2.5
var speed := 9.0
var target: Node3D  # whom it slides into (owned)
var goal := Vector3.INF  # where it slides to (a copy, or no target)

var _life := 4.0
var _body: Node3D
var _query := PhysicsRayQueryParameters3D.new()
var _flop := 0.0  # 0..1 tipping onto its belly


func _ready() -> void:
	if ResourceLoader.exists(MODEL):
		_body = (load(MODEL) as PackedScene).instantiate() as Node3D
		_body.scale = Vector3.ONE * 6.0  # a real-size little penguin (~35 cm)
		add_child(_body)


func _physics_process(delta: float) -> void:
	_life -= delta
	_flop = minf(1.0, _flop + delta * 4.0)
	var aim := goal
	if owned and target != null and is_instance_valid(target) and not target.health.is_dead():
		aim = target.global_position
	if aim == Vector3.INF:
		aim = global_position - global_transform.basis.z * 3.0
	var flat := Vector3(aim.x - global_position.x, 0.0, aim.z - global_position.z)
	if flat.length() < 0.9 or _life <= 0.0:
		_pop()
		return
	var dir := flat.normalized()
	global_position += dir * speed * delta
	_query.from = global_position + Vector3(0, 1.0, 0)  # follow the ground
	_query.to = global_position + Vector3(0, -2.0, 0)
	_query.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty() and not (hit.collider as Object).has_method("on_hit"):
		global_position.y = (hit.position as Vector3).y
	look_at(global_position + dir, Vector3.UP)
	if _body != null:
		_body.rotation = Vector3(-PI * 0.45 * _flop, 0.0, sin(Time.get_ticks_msec() * 0.02) * 0.15)  # belly down, wobbling


func _pop() -> void:
	if explosives != null:
		if owned:
			explosives.blast(global_position + Vector3(0, 0.4, 0), radius, damage)
		else:
			explosives.show_flash(global_position + Vector3(0, 0.4, 0), radius)
		if explosives.sounds != null:
			explosives.sounds.call("play", "explosion", global_position)
	queue_free()
