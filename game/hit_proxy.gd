# Purpose: a HIT BOX that belongs to a bigger creature (sea step 8c: each body segment of the Tide Wyrm): shots, blasts
# and cannon balls that hit it are passed on to `target` (a game/enemy.gd) at `share` of their damage; the box moves
# with whatever node it hangs under. It looks like an enemy to the shooters (on_hit, health, the status effects).
# Dependencies: game/enemy.gd (the target).
extends StaticBody3D

var target: Node3D
var share := 0.6
var radius := 0.7
var enemy_id: String:
	get:
		return String(target.get("enemy_id")) if is_instance_valid(target) else ""
var health: RefCounted:
	get:
		return target.get("health") if is_instance_valid(target) else null


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var ball := SphereShape3D.new()
	ball.radius = radius
	shape.shape = ball
	add_child(shape)


func on_hit(damage: float, point: Vector3 = Vector3.ZERO, normal: Vector3 = Vector3.UP) -> void:
	if is_instance_valid(target):
		target.call("on_hit", damage * share, point, normal)


func apply_burn(dps: float, seconds: float) -> void:
	if is_instance_valid(target):
		target.call("apply_burn", dps, seconds)


func apply_slow(amount: float, seconds: float) -> void:
	if is_instance_valid(target):
		target.call("apply_slow", amount, seconds)


func is_burning() -> bool:
	return is_instance_valid(target) and bool(target.call("is_burning"))
