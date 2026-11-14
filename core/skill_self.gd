# Purpose: pure rules for what the caster's own Q/E skills do to the caster (sea step 1d): Bullet Storm (fire rate,
# no ammo), Blood Rush (speed, leech), Phase Step (next shots hit harder), Full Clip (damage), Overshield (soaks
# damage), War Banner (damage up / damage taken down near the banner). Holds the timers and numbers; game/player.gd
# asks it each shot, step and hit. No nodes, no rendering.
# Dependencies: none (the numbers come from core/skill_state.gd `value`, read by the caller).
extends RefCounted

var _storm_until := 0.0
var _storm_rate := 1.0
var _rush_until := 0.0
var _rush_speed := 0.0
var _rush_leech := 0.0
var _phase_until := 0.0
var _phase_shots := 0
var _phase_mult := 1.0
var _clip_until := 0.0
var _clip_pct := 0.0
var _shield_until := 0.0
var _shield := 0.0
var _banner_until := 0.0
var _banner_dmg := 0.0
var _banner_guard := 0.0


func clear() -> void:
	_storm_until = 0.0
	_rush_until = 0.0
	_phase_until = 0.0
	_phase_shots = 0
	_clip_until = 0.0
	_shield_until = 0.0
	_shield = 0.0
	_banner_until = 0.0


func start_storm(now: float, seconds: float, rate: float) -> void:
	_storm_until = now + seconds
	_storm_rate = maxf(rate, 1.0)


func start_rush(now: float, seconds: float, speed_pct: float, leech: float) -> void:
	_rush_until = now + seconds
	_rush_speed = speed_pct
	_rush_leech = leech


func start_phase(now: float, seconds: float, shots: int, mult: float) -> void:
	_phase_until = now + seconds
	_phase_shots = shots
	_phase_mult = mult


func start_clip(now: float, seconds: float, damage_pct: float) -> void:
	_clip_until = now + seconds
	_clip_pct = damage_pct


func start_shield(now: float, seconds: float, amount: float) -> void:
	_shield_until = now + seconds
	_shield = maxf(amount, 0.0)


func start_banner(now: float, seconds: float, damage_pct: float, guard_pct: float) -> void:
	_banner_until = now + seconds
	_banner_dmg = damage_pct
	_banner_guard = guard_pct


# Multiplier on the gun's fire rate (Bullet Storm).
func rate_mult(now: float) -> float:
	return _storm_rate if now < _storm_until else 1.0


# A shot uses no round (Bullet Storm).
func free_ammo(now: float) -> bool:
	return now < _storm_until


func speed_mult(now: float) -> float:
	return 1.0 + _rush_speed / 100.0 if now < _rush_until else 1.0


# Share of the damage dealt healed back (Blood Rush), in percent.
func leech_pct(now: float) -> float:
	return _rush_leech if now < _rush_until else 0.0


# Damage multiplier on every shot: Full Clip, the War Banner when standing near it, and Phase Step's charged shots.
func damage_mult(now: float, near_banner: bool) -> float:
	var mult := 1.0
	if now < _clip_until:
		mult *= 1.0 + _clip_pct / 100.0
	if near_banner and now < _banner_until:
		mult *= 1.0 + _banner_dmg / 100.0
	if _phase_shots > 0 and now < _phase_until:
		mult *= _phase_mult
	return mult


# A shot was fired: one of Phase Step's charged shots is spent.
func on_shot(now: float) -> void:
	if _phase_shots > 0 and now < _phase_until:
		_phase_shots -= 1


# Damage taken after the War Banner's guard (near it) and the Overshield (which soaks first). Returns what gets through.
func incoming(amount: float, now: float, near_banner: bool) -> float:
	var left := amount
	if near_banner and now < _banner_until:
		left *= 1.0 - _banner_guard / 100.0
	if now < _shield_until and _shield > 0.0:
		var soaked := minf(_shield, left)
		_shield -= soaked
		left -= soaked
	return left


# What is left of the Overshield (0 when it is gone or ran out of time).
func shield_left(now: float) -> float:
	return _shield if now < _shield_until else 0.0


func banner_active(now: float) -> bool:
	return now < _banner_until
