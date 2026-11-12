# Purpose: Counter-Strike-style player movement as pure maths: ground friction and acceleration, air strafing, the jump,
# jump fatigue (stamina) and the bunny-hop speed cap. The numbers in data are Source units (1 unit = 1 inch); everything
# here is in metres. No nodes: game/player.gd owns the body, calls `land` when it touches down and `step` once per tick.
# Dependencies: none. Numbers: data/movement.json (its _about explains every one).
extends RefCounted

var tick := 1.0 / 64.0  # seconds per movement step
var unit := 0.0254  # metres in one Source unit
var gravity := 0.0
var jump_speed := 0.0
var base_speed := 0.0  # top speed with empty hands
var stamina := 0.0  # jump fatigue, 0 = fresh (see data "stamina")
var no_fatigue := false  # set by the player while a thing that removes fatigue is worn

var _friction := 0.0
var _stop_speed := 0.0
var _accelerate := 0.0
var _air_accelerate := 0.0
var _air_cap := 0.0
var _bunny_cap := 0.0
var _stamina_max := 0.0
var _recover := 0.0
var _jump_cost := 0.0
var _land_cost := 0.0
var _drag_rate := 0.0


func _init(cfg: Dictionary) -> void:
	unit = float(cfg["unit_m"])
	tick = 1.0 / float(cfg["tick_hz"])
	gravity = float(cfg["gravity"]) * unit
	jump_speed = float(cfg["jump_impulse"]) * unit
	base_speed = float(cfg["base_speed"]) * unit
	_friction = float(cfg["friction"])
	_stop_speed = float(cfg["stop_speed"]) * unit
	_accelerate = float(cfg["accelerate"])
	_air_accelerate = float(cfg["air_accelerate"])
	_air_cap = float(cfg["air_cap"]) * unit
	_bunny_cap = float(cfg["bunny_cap"])
	var tired: Dictionary = cfg["stamina"]
	_stamina_max = float(tired["max"])
	_recover = float(tired["recover"])
	_jump_cost = float(tired["jump_cost"])
	_land_cost = float(tired["land_cost"])
	_drag_rate = float(tired["drag_rate"])


# The body touched the ground after falling at `fall_speed` m/s.
func land(fall_speed: float) -> void:
	if not no_fatigue:
		stamina = minf(stamina + _land_cost * fall_speed / unit, _stamina_max)


# One tick. velocity in m/s; wish = the flat unit direction the keys ask for (ZERO = none); top = the top speed that
# applies right now (gun, sprint, crouch, slows); cap_top = the sprint top speed the bunny-hop cap is measured from;
# grounded = standing on something; jump = a jump starts this tick (only looked at when grounded). Returns the new velocity.
func step(velocity: Vector3, wish: Vector3, top: float, cap_top: float, grounded: bool, jump: bool) -> Vector3:
	stamina = maxf(stamina - _recover * tick, 0.0)
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var up := velocity.y
	var fall := gravity * tick
	if grounded and jump:
		fall *= 0.5  # half a tick of gravity on the way off the ground, so the jump tops out where the numbers say (57 units)
		var speed := flat.length()
		if _bunny_cap > 0.0 and speed > cap_top * _bunny_cap:
			flat *= cap_top * _bunny_cap / speed
		up = jump_speed * maxf(1.0 - stamina / 100.0, 0.0)
		if not no_fatigue:
			stamina = minf(stamina + _jump_cost * jump_speed / unit, _stamina_max)
		grounded = false  # it leaves the ground this very tick: no friction, no fatigue drag (a perfect hop keeps its speed)
	if grounded:
		if stamina > 0.0:
			flat *= pow(maxf(1.0 - stamina / 100.0, 0.0), tick * _drag_rate)
		flat = _rub(flat)
		flat = _push(flat, wish, top, top, _accelerate)
	else:
		flat = _push(flat, wish, minf(top, _air_cap), top, _air_accelerate)
		up -= fall
	return Vector3(flat.x, up, flat.z)


# Ground friction: below stop_speed it bites as if you still moved at stop_speed, so you come to a dead stop.
func _rub(flat: Vector3) -> Vector3:
	var speed := flat.length()
	if speed < 0.001:
		return Vector3.ZERO
	var drop := maxf(speed, _stop_speed) * _friction * tick
	return flat * (maxf(speed - drop, 0.0) / speed)


# Adds speed along `wish` until the part of the velocity that points that way reaches `limit`. On the ground limit = top.
# In the air limit is tiny (air_cap) while the push itself stays strong: that is the whole trick of air strafing.
func _push(flat: Vector3, wish: Vector3, limit: float, top: float, rate: float) -> Vector3:
	if wish == Vector3.ZERO:
		return flat
	var room := limit - flat.dot(wish)
	if room <= 0.0:
		return flat
	return flat + wish * minf(rate * top * tick, room)
