# Purpose: a HIT BOX on a part of a sea super boss (sea step 10): an eye stalk or the soft belly (weak points that take
# more than the armoured body) or a breakable barnacle cluster (its own health; breaking all of a phase's cracks the
# shell). Shots, blasts and cannon balls that hit it are handed to the boss fight (game/sea_boss.gd part_hit), which
# decides what reaches the boss (the host) or asks the host (a client). It moves with the model node it hangs under.
# It looks like an enemy to the shooters (on_hit, health, status effects go to the boss itself).
# Dependencies: game/sea_boss.gd (fight: part_hit), game/enemy.gd (the boss's body: target).
extends StaticBody3D

var fight: Node
var target: Node3D
var part_id := ""
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


func on_hit(damage: float, _point: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.UP) -> void:
	if is_instance_valid(fight):
		fight.call("part_hit", part_id, damage)


func apply_burn(dps: float, seconds: float) -> void:
	if is_instance_valid(target):
		target.call("apply_burn", dps, seconds)


func apply_slow(amount: float, seconds: float) -> void:
	if is_instance_valid(target):
		target.call("apply_slow", amount, seconds)


func is_burning() -> bool:
	return is_instance_valid(target) and bool(target.call("is_burning"))


# Shown and hittable, or gone (a broken barnacle cluster).
func set_live(on: bool) -> void:
	collision_layer = 2 if on else 0
