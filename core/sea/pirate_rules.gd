# Purpose: how a PIRATE SHIP sails a fight (sea step 8; director: small pirate ships sail and fire broadsides from
# range, big ones also come alongside and board): from her own state and her target's place and motion, the mode
# (approach / engage / veer off / flee), the heading she wants, her rudder and the side she shows the target. The
# sail stage is picked by the game from the ship rules (the fastest of oars and sail for that heading). Pure.
# Dependencies: data/sea/encounters.json "pirate" (passed in). Ship yaw: forward = (-sin yaw, -cos yaw), starboard =
# (cos yaw, -sin yaw) in sea x, z.
extends RefCounted

var cfg: Dictionary  # encounters.json "pirate"


func _init(pirate_cfg: Dictionary) -> void:
	cfg = pirate_cfg


static func heading_of(v: Vector2) -> float:
	return atan2(-v.x, -v.y)


# {"mode", "want" (yaw), "rudder", "side" (+1 starboard / -1 port: the side the target lies on)}.
# me: x, z, yaw, hull, hull_max; target: Vector2 place, its velocity. `keep` = [near, far] m to keep instead of
# range_m (a boarder closing to swing her crew across, sea step 8b).
func plan(me: Dictionary, target: Vector2, target_vel: Vector2, keep: Array = []) -> Dictionary:
	var here := Vector2(float(me["x"]), float(me["z"]))
	var yaw := float(me["yaw"])
	var to := target - here
	var d := to.length()
	var bearing := heading_of(to)
	var ahead := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(cos(yaw), -sin(yaw))
	var side := 1.0 if to.dot(right) >= 0.0 else -1.0
	var near_far: Array = keep if keep.size() == 2 else cfg["range_m"]
	var mode := "engage"
	var want := yaw
	if float(me["hull"]) < float(me["hull_max"]) * float(cfg["flee_hull"]):
		mode = "flee"
		want = heading_of(-to)
	elif d > float(near_far[1]):
		mode = "approach"
		# aim beside her, on the side we are already on, a little ahead of where she is going
		var lead := target + target_vel * 6.0
		var beside := (here - lead).normalized().rotated(0.0) * float(near_far[0])
		want = heading_of(lead + beside - here)
	else:
		# lay her abeam: steer square to the bearing, on whichever way is nearer the heading we have; too near = the
		# same, opened out 25 degrees so the guns still bear while the gap grows
		var open_out := deg_to_rad(25.0) if d < float(near_far[0]) else 0.0
		if open_out > 0.0:
			mode = "veer"
		var a := wrapf(bearing + PI * 0.5 + open_out, -PI, PI)
		var b := wrapf(bearing - PI * 0.5 - open_out, -PI, PI)
		want = a if absf(wrapf(a - yaw, -PI, PI)) < absf(wrapf(b - yaw, -PI, PI)) else b
	var diff := wrapf(want - yaw, -PI, PI)
	# the rudder: positive turns to starboard (yaw grows clockwise from above when the ship rules apply rudder)
	var rudder := clampf(-diff * float(cfg["turn_gain"]), -1.0, 1.0)
	return {"mode": mode, "want": want, "rudder": rudder, "side": side, "d": d, "ahead": ahead.dot(to.normalized()) if d > 0.01 else 1.0}
