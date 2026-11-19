# Purpose: the Lantern Queen's own ARENA RULES (sea step 13 R2d, design approved in diary/DESIGN_BOSSES.md): how thick
# the Root Crown's fog is (by phase, thinned by lit braziers), when a lit brazier burns out, whether she is EXPOSED
# (inside a lit brazier's circle: her body takes all of a hit and her gills are live), the LURE PULL (a player who
# keeps her lure in view long enough is walked toward the pool), spore CLOUDS (where a spore pod landed: standing in
# one blinds). Pure: no nodes, no drawing, no network (game/sea_boss_lantern.gd runs it).
# Dependencies: none (the boss's "lantern" block of data/sea/bosses.json is passed in).
extends RefCounted

var cfg: Dictionary  # bosses.json lantern_queen "lantern"
var lit_at := {}  # host: brazier char -> fight time it was seen lit
var clouds: Array = []  # [[arena-local point, radius, seconds left, blind seconds]]
var hold := 0.0  # this player's seconds looking at the lure
var pulled := false


func setup(lantern: Dictionary) -> void:
	cfg = lantern
	lit_at.clear()
	clouds.clear()
	hold = 0.0
	pulled = false


# The arena's fog density in this phase with this many braziers lit.
func fog(phase: int, lit: int) -> float:
	var list: Array = cfg.get("fog", [0.1])
	var base := float(list[clampi(phase, 0, list.size() - 1)])
	if phase == 0:
		base -= float(cfg.get("lit_thin", 0.0)) * float(lit)
	return maxf(base, 0.02)


# Host: braziers that have burned for their burn_s (given {char: burn_s} of the lit ones) and must go out now.
func burnt_out(lit_now: Dictionary, now: float) -> Array:
	var out: Array = []
	for ch: String in lit_at.keys():
		if not lit_now.has(ch):
			lit_at.erase(ch)  # (put out some other way: the clock starts again next time)
	for ch: String in lit_now:
		if not lit_at.has(ch):
			lit_at[ch] = now
		elif float(lit_now[ch]) > 0.0 and now - float(lit_at[ch]) >= float(lit_now[ch]):
			out.append(ch)
			lit_at.erase(ch)
	return out


# Is this arena-local point inside a lit brazier's circle (points of the lit braziers given)?
func exposed(at: Vector3, lit_points: Array) -> bool:
	var r := float(cfg.get("light_r", 7.0))
	for p: Vector3 in lit_points:
		if Vector2(at.x - p.x, at.z - p.z).length() <= r:
			return true
	return false


# This player's view: is the lure within view_deg of where he looks and within reach? Returns true once he has looked
# for hold_s (then he is pulled while he keeps looking).
func watch_lure(eye: Vector3, look: Vector3, bulb: Vector3, can_see: bool, delta: float) -> bool:
	var l: Dictionary = cfg.get("lure", {})
	var to := bulb - eye
	var looking := can_see and to.length() <= float(l.get("reach_m", 30.0)) and to.length() > 0.5 \
		and rad_to_deg(look.normalized().angle_to(to.normalized())) <= float(l.get("view_deg", 9.0))
	hold = hold + delta if looking else 0.0
	pulled = hold >= float(l.get("hold_s", 2.0))
	return pulled


# Where the pull takes him: toward the pool's middle, flat, at pull_mps.
func pull_toward(at: Vector3, pool: Vector3) -> Vector3:
	var to := Vector3(pool.x - at.x, 0.0, pool.z - at.z)
	if to.length() < 0.5:
		return Vector3.ZERO
	return to.normalized() * float((cfg.get("lure", {}) as Dictionary).get("pull_mps", 1.5))


func add_cloud(at: Vector3, radius: float, seconds: float, blind: float) -> void:
	clouds.append([at, radius, seconds, blind])
	if clouds.size() > 12:
		clouds.pop_front()


# Time passes for the clouds; returns the blind seconds of a cloud this point stands in (0 = none).
func cloud_step(at: Vector3, delta: float) -> float:
	var blind := 0.0
	var left: Array = []
	for c: Array in clouds:
		c[2] = float(c[2]) - delta
		if float(c[2]) <= 0.0:
			continue
		left.append(c)
		var p: Vector3 = c[0]
		if Vector2(at.x - p.x, at.z - p.z).length() <= float(c[1]) and absf(at.y - p.y) < 2.5:
			blind = maxf(blind, float(c[3]))
	clouds = left
	return blind
