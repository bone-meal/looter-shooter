# Purpose: pure rules of the mystery box: where it stands, a spin, the offer that waits to be taken, and its move to
# another spot after a few spins. No nodes; the gun itself is rolled by the caller.
# Dependencies: none. Data: data/mystery_box.json, passed to the constructor. Time is the caller's clock in seconds.
extends RefCounted

var cfg: Dictionary
var spot := 0  # which of cfg.spots it stands on (while moving: where it is going)
var state := "idle"  # idle | spinning | offer | moving

var _until := 0.0
var _spins_left := 0


func _init(config: Dictionary, rng: RandomNumberGenerator) -> void:
	cfg = config
	_spins_left = _fresh(rng)


func _fresh(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(int(cfg["moves_after"][0]), int(cfg["moves_after"][1]))


func spot_count() -> int:
	return (cfg["spots"] as Array).size()


# Gun luck of a spin in this round.
func luck(island_round: int) -> float:
	return float(cfg["luck_base"]) + float(cfg["luck_per_round"]) * float(maxi(island_round, 0))


# A spin starts (the caller has taken the price); false unless the box stands idle.
func spin(now: float) -> bool:
	if state != "idle":
		return false
	state = "spinning"
	_until = now + float(cfg["spin_seconds"])
	_spins_left -= 1
	return true


# The offered gun is taken; false when nothing is on offer. Returns through `after` what the box does next.
func take(now: float, rng: RandomNumberGenerator) -> bool:
	if state != "offer":
		return false
	_after_offer(now, rng)
	return true


# Moves the clock on. Returns what just happened: "" nothing, "offer" a spin ended (roll the gun now), "idle" an
# offer ran out, "move" the offer ran out and the box is being carried off, "landed" it stands on its new spot.
func update(now: float, rng: RandomNumberGenerator) -> String:
	if state == "spinning" and now >= _until:
		state = "offer"
		_until = now + float(cfg["take_seconds"])
		return "offer"
	if state == "offer" and now >= _until:
		return _after_offer(now, rng)
	if state == "moving" and now >= _until:
		state = "idle"
		return "landed"
	return ""


func _after_offer(now: float, rng: RandomNumberGenerator) -> String:
	if _spins_left > 0 or spot_count() < 2:
		state = "idle"
		return "idle"
	_spins_left = _fresh(rng)
	spot = (spot + 1 + rng.randi() % (spot_count() - 1)) % spot_count()  # any spot but this one
	state = "moving"
	_until = now + float(cfg["move_seconds"])
	return "move"


# Game over: back on the first spot, doing nothing.
func reset(rng: RandomNumberGenerator) -> void:
	spot = 0
	state = "idle"
	_spins_left = _fresh(rng)


# What the host says (as a client).
func mirror(new_state: String, new_spot: int) -> void:
	if new_state in ["idle", "spinning", "offer", "moving"]:
		state = new_state
	spot = clampi(new_spot, 0, spot_count() - 1)
