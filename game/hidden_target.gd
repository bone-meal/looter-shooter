# Purpose: a small thing that can be shot (a song's glass float, a quest lamp): a static body on the world layer
# whose `on_hit` calls `hit_by` once (shots call on_hit on whatever they hit). Draws nothing itself.
# Dependencies: none. Set `hit_by` and add a collision shape; `armed` = false makes it ignore shots.
extends StaticBody3D

var hit_by := Callable()
var armed := true


func on_hit(_damage: float, _point: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.UP) -> void:
	if armed and hit_by.is_valid():
		hit_by.call()
