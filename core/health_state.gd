# Purpose: pure hit points for the player or an enemy. No nodes, no rendering.
# Dependencies: none.
extends RefCounted

var max_hp: float
var hp: float
var no_heal := false  # while true nothing heals (a colosseum modifier)


func _init(max_value: float) -> void:
	max_hp = max_value
	hp = max_value


func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)


func heal(amount: float) -> void:
	if not no_heal:
		hp = minf(hp + amount, max_hp)


func is_dead() -> bool:
	return hp <= 0.0


func reset() -> void:
	hp = max_hp
