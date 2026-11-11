# Purpose: pure enemy decisions: which way to move at a given distance, and when an attack is ready.
# Dependencies: none. Stats come from data/enemies.json (see tools/validate_data.gd).
extends RefCounted

var attack_range: float
var preferred_range: float  # 0 = melee: close in until within attack range
var _attack_interval: float
var _next_attack_time := 0.0


func _init(stats: Dictionary) -> void:
	attack_range = float(stats["attack_range"])
	preferred_range = float(stats.get("preferred_range", 0.0))
	_attack_interval = float(stats["attack_interval"])


# +1 move toward the target, -1 move away, 0 hold position.
func move_sign(distance: float) -> int:
	if preferred_range <= 0.0:
		return 1 if distance > attack_range * 0.8 else 0
	if distance > preferred_range + 2.0:
		return 1
	if distance < preferred_range - 2.0:
		return -1
	return 0


# Returns true if an attack fires now (cooldown started).
func try_attack(distance: float, now: float) -> bool:
	if distance > attack_range or now < _next_attack_time:
		return false
	_next_attack_time = now + _attack_interval
	return true
