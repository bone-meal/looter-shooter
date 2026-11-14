# Purpose: what the held gun's TRAITS do (locked 2026-11-14, diary/DECISIONS_SEA.md; data/gun_traits.json): the big
# build-defining effects above the small buffs. The pony families' own traits are game/pony_traits.gd (`pony`), called
# from the same hooks. The player calls these hooks from its shot, hit, kill, damage and
# swap code; `traits` is the held gun's {id: value} (core/gun_stats.gd final_stats "traits").
# Dependencies: the player (game/player.gd: weapon, health, skills, explosives, allies_close).
extends RefCounted

const PonyTraits = preload("res://game/pony_traits.gd")

const OVERCHARGE_EVERY := 5
const RICOCHET_RANGE := 10.0
const LAST_STAND_AT := 0.25
const LAST_STAND_REST := 30.0
const EXECUTE_AT := 0.25
const MOMENTUM_STEP := 2.0

var player: Node:
	set(value):
		player = value
		pony.player = value
var pony := PonyTraits.new()
var _shots := 0
var _streak := 0
var _swap_shots := 0
var _stand_until := 0.0
var _stand_ready_at := 0.0
var _charged := false  # this shot is an Overcharge shot


func on_swapped(traits: Dictionary, mag: int) -> void:
	pony.on_swapped()
	_swap_shots = mag if traits.has("quick_change") else 0
	_streak = 0


# A trigger pull: counts toward Overcharge; true = Last Stand is on and the round comes back.
func on_shot(traits: Dictionary, now: float) -> bool:
	_shots += 1
	_charged = traits.has("overcharge") and _shots % OVERCHARGE_EVERY == 0
	pony.on_shot(traits, now)
	return traits.has("last_stand") and now < _stand_until


# One pellet's damage multiplier from the traits.
func damage_mult(traits: Dictionary, target: Node) -> float:
	if traits.is_empty():
		return 1.0
	var mult := 1.0
	if _charged:
		mult *= 1.0 + float(traits["overcharge"]) / 100.0
	if traits.has("pack_hunter"):
		mult *= 1.0 + float(traits["pack_hunter"]) * float(int(player.get("allies_close"))) / 100.0
	if _swap_shots > 0:
		mult *= 1.0 + float(traits["quick_change"]) / 100.0
	if traits.has("executioner") and target.get("health") != null and float(target.health.hp) < float(target.health.max_hp) * EXECUTE_AT:
		mult *= 1.0 + float(traits["executioner"]) / 100.0
	if traits.has("momentum"):
		mult *= 1.0 + minf(float(_streak) * MOMENTUM_STEP, float(traits["momentum"])) / 100.0
	if traits.has("twin_shot") and randf() * 100.0 < float(traits["twin_shot"]):
		mult *= 2.0
	return mult * pony.damage_mult(traits)


# After the shot's pellets: Momentum keeps counting or starts over, Quick Change spends one round.
func after_shot(hit_something: bool) -> void:
	_streak = _streak + 1 if hit_something else 0
	_swap_shots = maxi(_swap_shots - 1, 0)
	pony.after_shot()


func on_hit(traits: Dictionary, target: Node, point: Vector3, dealt: float) -> void:
	var blasts: Node = player.get("explosives")
	if traits.has("ricochet"):
		var other: Node = _nearest_other(target, point)
		if other != null:
			other.on_hit(dealt * float(traits["ricochet"]) / 100.0, other.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	if traits.has("tempest") and randf() * 100.0 < float(traits["tempest"]):
		if target.has_method("apply_burn"):
			target.apply_burn(dealt * 0.4, 3.0)
		if blasts != null:
			blasts.blast(point, 4.0, dealt * 0.4, false)
	if _charged and blasts != null:
		blasts.blast(point, 3.0, dealt * 0.5)
	pony.on_hit(traits, target, point, dealt)


func on_kill(traits: Dictionary, point: Vector3, dealt: float, now: float, _victim: Node = null) -> void:
	pony.on_kill(traits, point, now)
	var blasts: Node = player.get("explosives")
	if traits.has("chain_reaction") and blasts != null:
		blasts.blast(point, 4.0, dealt * float(traits["chain_reaction"]) / 100.0)
	if traits.has("blood_tide"):
		player.health.heal(float(player.health.max_hp) * float(traits["blood_tide"]) / 100.0)
		var w: Variant = player.get("weapon")
		if w != null:
			w.ammo = mini(int(w.ammo) + ceili(float(w.mag_size) / 3.0), int(w.mag_size))
	if traits.has("skill_surge") and player.get("skills") != null:
		player.skills.reduce_all(float(traits["skill_surge"]), now)


# After the player was hurt: Last Stand starts when health drops below a quarter (once every 30 s).
func on_hurt(traits: Dictionary, now: float) -> void:
	if not traits.has("last_stand") or now < _stand_ready_at:
		return
	if float(player.health.hp) > 0.0 and float(player.health.hp) < float(player.health.max_hp) * LAST_STAND_AT:
		_stand_until = now + float(traits["last_stand"])
		_stand_ready_at = now + LAST_STAND_REST


func _nearest_other(from: Node, point: Vector3) -> Node:
	var blasts: Node = player.get("explosives")
	if blasts == null or blasts.get("source") == null:
		return null
	var best: Node = null
	var best_d := RICOCHET_RANGE
	for e: Node in blasts.source.enemy_list():
		if e == from or not is_instance_valid(e) or e.health.is_dead():
			continue
		var d: float = (e as Node3D).global_position.distance_to(point)
		if d <= best_d:
			best_d = d
			best = e
	return best


# A gun skill was cast (Spellweave).
func on_skill_cast(traits: Dictionary) -> void:
	pony.on_skill_cast(traits)


# Share of incoming damage that gets through (Stand Fast).
func taken_mult(traits: Dictionary) -> float:
	return pony.taken_mult(traits)


# Multiplier on the gun's fire rate (Joyburst).
func rate_mult(traits: Dictionary, now: float) -> float:
	return pony.rate_mult(traits, now)


# Extra move speed share (Skystreak).
func speed_mult(now: float) -> float:
	return pony.speed_mult(now)


# False while a trait forbids critical hits (Honest Work).
func crits_allowed(traits: Dictionary) -> bool:
	return not traits.has("honest_work")
