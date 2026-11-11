# Purpose: pure damped spring for soft-body secondary motion (jiggle): a point that lags behind its anchor when the anchor accelerates, overshoots and settles. No nodes.
# Dependencies: none.
extends RefCounted

var offset := Vector3.ZERO  # displacement from rest (meters, in the anchor's local axes)
var velocity := Vector3.ZERO
var omega := 44.0  # natural frequency, radians per second
var zeta := 0.14  # damping ratio: below 1 = bouncy, 1 = no overshoot
var limit := 0.035  # the offset never grows beyond this many meters


func setup(frequency_hz: float, damping_ratio: float, max_offset: float) -> void:
	omega = TAU * frequency_hz
	zeta = damping_ratio
	limit = max_offset


# Advances the spring by `delta` seconds. `drive` is the force on the point (negative acceleration of the anchor, in local axes, times a gain).
func step(delta: float, drive: Vector3) -> void:
	var steps := maxi(1, ceili(delta / 0.008))  # small sub-steps keep a stiff spring stable
	var h := delta / float(steps)
	for _i in steps:
		var accel := drive - offset * (omega * omega) - velocity * (2.0 * zeta * omega)
		velocity += accel * h
		offset += velocity * h
	var length := offset.length()
	if length > limit:
		offset *= limit / length
		velocity *= 0.5


func reset() -> void:
	offset = Vector3.ZERO
	velocity = Vector3.ZERO
