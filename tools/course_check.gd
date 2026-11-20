# Purpose: developer check of the hop course (core/course_rules.gd with data/course.json and the movement numbers):
# the data is whole, every hop can be made and the strafe stage cannot be made without strafing, and a run's clock
# starts, keeps checkpoints, sends a fall back, finishes and keeps only a better best time.
# Log tools/course_check.log (ends COURSE_CHECK_DONE problems=n; lists every hop with its gap and reach).
# Dependencies: core/course_rules.gd, core/data_store.gd.
extends Node

const CourseRules = preload("res://core/course_rules.gd")
const DataStore = preload("res://core/data_store.gd")
const BhopStages = preload("res://core/bhop_stages.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var course := CourseRules.new()
	course.setup(DataStore.load_json("res://data/course.json"))
	var wrong := course.problems()
	_say("the data is whole%s" % ("" if wrong.is_empty() else ": " + "; ".join(wrong)), wrong.is_empty())
	var hops := course.hop_problems(DataStore.load_json("res://data/movement.json"), float(DataStore.load_json("res://data/player.json")["sprint_multiplier"]))
	_lines.append_array(hops[1])
	_say("every hop fits the movement; the leap needs strafing%s" % ("" if (hops[0] as PackedStringArray).is_empty() else ": " + "; ".join(hops[0])), (hops[0] as PackedStringArray).is_empty())
	var first := course.start_index()
	var check := -1
	for i in course.pads.size():
		if String(course.pads[i]["kind"]) == "checkpoint":
			check = i
			break
	var on_start := course.update(0.5, first, false)
	var away := course.update(0.1, -1, false)
	course.update(1.0, first + 1, false)
	var early_fall := course.update(0.1, -1, true)
	_say("the clock waits on the start pad, starts when you leave it, a fall before the first checkpoint starts again", on_start == "" and away == "start" and early_fall == "restart" and course.state == CourseRules.READY and is_zero_approx(course.time))
	course.update(0.1, -1, false)
	var reached := course.update(2.0, check, false)
	var fell := course.update(0.5, -1, true)
	_say("a checkpoint is kept and a later fall puts you back there with the clock running", reached == "checkpoint" and fell == "fell" and course.checkpoint == check and course.state == CourseRules.RUNNING and is_equal_approx(course.time, 2.6))
	var done := course.update(10.0, course.finish_index(), false)
	var first_best := course.best
	course.update(0.1, first, false)
	course.update(0.1, -1, false)
	var slower := course.update(30.0, course.finish_index(), false)
	_say("the finish stops the clock; a slower run does not replace the best (best %s, last %s)" % [CourseRules.clock(course.best), CourseRules.clock(course.last)], done == "record" and slower == "finish" and is_equal_approx(course.best, first_best) and course.last > course.best)
	_say("times read like 1:05.07", CourseRules.clock(65.07) == "1:05.07" and CourseRules.clock(0.0) == "0:00.00" and CourseRules.clock(600.999) == "10:01.00")
	var spot := course.stand_on(first)
	_say("the start faces the first hop", absf(float(spot["yaw"])) < 0.01 and course.pad_at(0.0, 0.0) == first and course.pad_at(0.0, -5.0) == -1)

	# (polish1 C7) the bhop server: every stage laid out whole, the hop stages fit the movement, the rest sane
	var server: Dictionary = DataStore.load_json("res://data/bhop_server.json")
	var move: Dictionary = DataStore.load_json("res://data/movement.json")
	var sprint := float(DataStore.load_json("res://data/player.json")["sprint_multiplier"])
	var old: Dictionary = DataStore.load_json("res://data/course.json")
	var types := {}
	for i in (server["stages"] as Array).size():
		var st: Dictionary = server["stages"][i]
		types[String(st["type"])] = int(types.get(String(st["type"]), 0)) + 1
		var c := CourseRules.new()
		c.setup(BhopStages.course(server, i, old))
		var bad := c.problems()
		var kind := String(st["recipe"]["kind"])
		var note := ""
		if kind in ["hops", "long", "fixed"]:
			var h := c.hop_problems(move, sprint)
			bad.append_array(h[0])
		var low := c.lowest()
		var high := -INF
		for k in c.pads.size():
			high = maxf(high, c.top_of(k))
		if kind == "climb":
			var steps_ok := true
			for k in range(1, c.pads.size()):
				var rise := c.top_of(k) - c.top_of(k - 1)
				steps_ok = steps_ok and (rise <= 1.3 or (c.cfg["parts"] as Array).size() > 0)
			note = "%d ladders" % (c.cfg["parts"] as Array).size()
			if not steps_ok:
				bad.append("a step higher than a jump without a ladder")
		if kind == "surf":
			note = "%d ramp faces" % (c.cfg["parts"] as Array).size()
		if kind == "edgebug":  # each drop: the floor and the pillar's top land too hard, the bug's short drop does not, the pillar is in reach
			var unit := float(move["unit_m"])
			var g := float(move["gravity"]) * unit
			var hard := float(server["edgebug"]["hard_landing"]) * unit
			var run := float(move["base_speed"]) * sprint * unit
			var worst := 0.0
			for bug: Dictionary in c.cfg["bugs"]:
				var fall := c.top_of(int(bug["from"])) - c.top_of(int(bug["to"]))
				var pillar := float(bug["pillar"])
				var air := sqrt(2.0 * maxf(fall - pillar, 0.0) / g)
				worst = maxf(worst, float(bug["reach"]) / maxf(run * air, 0.01))
				if sqrt(2.0 * g * (fall - pillar)) <= hard:
					bad.append("drop %d: the pillar's top is a safe landing" % int(bug["to"]))
				if sqrt(2.0 * g * pillar) >= hard * 0.95:
					bad.append("drop %d: the drop after the edgebug lands too hard" % int(bug["to"]))
				if float(bug["reach"]) + 0.4 > run * air:
					bad.append("drop %d: the pillar is out of reach (%.1f m, %.1f m in the air)" % [int(bug["to"]), float(bug["reach"]), run * air])
			note = "%d edgebugs, the farthest pillar needs %d %% of a sprint" % [(c.cfg["bugs"] as Array).size(), roundi(worst * 100.0)]
		_say("%s (%s %d): %d pads from %.1f to %.1f m%s%s" % [st["id"], st["type"], int(st["tier"]), c.pads.size(), low, high, (", " + note) if note != "" else "", "" if bad.is_empty() else "  PROBLEMS: " + "; ".join(bad)], bad.is_empty() and c.start_index() == 0 and c.finish_index() == c.pads.size() - 1)
	_say("6 types x 3 stages: %s" % str(types), types.size() == 6 and types.values().all(func(n: int) -> bool: return n == 3))

	_lines.append("COURSE_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/course_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
