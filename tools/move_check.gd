# Purpose: developer check of the movement rules (core/move_rules.gd with data/movement.json) without a body: plays
# standard situations tick by tick on flat ground and logs what a player would feel, in Source units: time to full
# speed, stopping, counter-strafing, jump height, the slow-down after landing, bunny-hop chains (perfect, late, with
# and without air strafing). Log tools/move_check.log (ends MOVE_CHECK_DONE problems=n). The problems are sanity
# limits, not taste: taste is the director's, by editing the data.
# Dependencies: core/move_rules.gd, core/data_store.gd.
extends Node

const MoveRules = preload("res://core/move_rules.gd")
const DataStore = preload("res://core/data_store.gd")

var _cfg := {}
var _lines := PackedStringArray()
var _problems := 0
var _u := 0.0254


func _ready() -> void:
	_cfg = DataStore.load_json("res://data/movement.json")
	_u = float(_cfg["unit_m"])
	var top := float(_cfg["base_speed"]) * _u
	var forward := Vector3(0, 0, -1)

	var rules := MoveRules.new(_cfg)
	var v := Vector3.ZERO
	var ticks := 0
	while v.length() < top * 0.99 and ticks < 640:
		v = rules.step(v, forward, top, top, true, false)
		ticks += 1
	_say("0 to full speed (%d u/s): %.2f s" % [roundi(top / _u), ticks * rules.tick], ticks * rules.tick > 0.3 and ticks * rules.tick < 0.9)

	v = forward * top
	ticks = 0
	var way := 0.0
	while v.length() > 0.001 and ticks < 640:
		v = rules.step(v, Vector3.ZERO, top, top, true, false)
		way += v.length() * rules.tick
		ticks += 1
	_say("letting go at full speed: stops after %.2f s and %d units" % [ticks * rules.tick, roundi(way / _u)], ticks * rules.tick > 0.2 and ticks * rules.tick < 0.8)

	v = forward * top
	ticks = 0
	while v.dot(forward) > top * 0.34 and ticks < 640:
		v = rules.step(v, -forward, top, top, true, false)
		ticks += 1
	_say("counter-strafe (opposite key) to a third of full speed: %.2f s" % [ticks * rules.tick], ticks * rules.tick < 0.2)

	var jump := _jump(MoveRules.new(_cfg), Vector3.ZERO, Vector3.ZERO, top, 0)
	_say("standing jump: %.1f units high, %.2f s in the air" % [float(jump["apex"]) / _u, float(jump["ticks"]) * rules.tick], absf(float(jump["apex"]) / _u - 57.0) < 4.0)

	# run, jump, land, keep holding forward
	rules = MoveRules.new(_cfg)
	jump = _jump(rules, forward * top, Vector3.ZERO, top, 0)
	v = jump["velocity"]
	var low := v.length()
	ticks = 0
	var back := -1
	while ticks < 128:
		v = rules.step(v, forward, top, top, true, false)
		low = minf(low, v.length())
		ticks += 1
		if back < 0 and v.length() >= top * 0.99 and ticks > 3:
			back = ticks
	_say("running jump, then landing with forward held: speed dips to %d %% and is back after %.2f s" % [roundi(100.0 * low / top), back * rules.tick], low / top > 0.4 and low / top < 0.95)

	rules = MoveRules.new(_cfg)
	jump = _jump(rules, Vector3.ZERO, Vector3.ZERO, top, 0)
	jump = _jump(rules, Vector3.ZERO, Vector3.ZERO, top, 0)
	_say("second jump straight after the first (standing): %.1f units high" % [float(jump["apex"]) / _u], float(jump["apex"]) / _u < 57.0 and float(jump["apex"]) / _u > 25.0)

	for late: int in [0, 1, 2, 4]:
		_say(_chain("hops %d tick(s) late, no air strafing" % late, late, 0.0), true)
	_say(_chain("perfect hops, strafing every third tick", 0, 0.34), true)
	_say(_chain("perfect hops, flawless strafing (the ceiling)", 0, 1.0), true)

	var guns: Dictionary = DataStore.load_json("res://data/weapons.json")["weapons"]
	var listed := PackedStringArray()
	for body: String in guns:
		var run := float(guns[body].get("move_speed", 0.0))
		var aim := float(guns[body].get("aim_speed", run))
		_say("gun %s: move_speed %d, aim_speed %d" % [body, roundi(run), roundi(aim)], run >= 100.0 and run <= float(_cfg["base_speed"]) and aim > 0.0 and aim <= run)
		listed.append(body)
	_lines.append("MOVE_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/move_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


# One jump from the ground until the ground again. strafe: share of air ticks on which a key pushes exactly sideways
# to the flight (what turning the mouse with a strafe key does at best). late: ticks spent on the ground first.
func _jump(rules: MoveRules, velocity: Vector3, _wish: Vector3, top: float, late: int, strafe := 0.0, cap_top := -1.0) -> Dictionary:
	var v := velocity
	for i in late:
		v = rules.step(v, Vector3.ZERO, top, top, true, false)
	v = rules.step(v, Vector3.ZERO, top, top if cap_top < 0.0 else cap_top, true, true)
	var height := v.y * rules.tick
	var apex := height
	var ticks := 1
	var fall := 0.0
	var owed := 0.0
	while height > 0.0 and ticks < 640:
		var side := Vector3.ZERO
		owed += strafe
		if owed >= 1.0 and Vector2(v.x, v.z).length() > 0.01:
			owed -= 1.0
			side = Vector3(v.x, 0.0, v.z).normalized().cross(Vector3.UP)
		fall = -v.y
		v = rules.step(v, side, top, top, false, false)
		height += v.y * rules.tick
		apex = maxf(apex, height)
		ticks += 1
	rules.land(maxf(fall, 0.0))
	return {"velocity": Vector3(v.x, 0.0, v.z), "apex": apex, "ticks": ticks}


func _chain(title: String, late: int, strafe: float) -> String:
	var rules := MoveRules.new(_cfg)
	var top := float(_cfg["base_speed"]) * _u
	var sprint_top := top * float(DataStore.load_json("res://data/player.json")["sprint_multiplier"])
	var v := Vector3(0, 0, -1) * top
	var speeds := PackedStringArray()
	var apex := 0.0
	for hop in 8:
		var jump := _jump(rules, v, Vector3.ZERO, top, late if hop > 0 else 0, strafe, sprint_top)
		v = jump["velocity"]
		apex = float(jump["apex"])
		speeds.append(str(roundi(v.length() / _u)))
	return "%s, from a %d u/s run: speed after each of 8 hops %s; the last hop is %.0f units high" % [title, roundi(top / _u), " ".join(speeds), apex / _u]


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
