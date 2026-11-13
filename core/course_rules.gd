# Purpose: pure rules of the hop course (data/course.json): which platform a spot is on, the run's clock (starts when
# you leave the start pad, checkpoints, a fall puts you back on the last checkpoint with the clock running, the finish
# stops it and keeps the best time), the time as text, and a check that every hop can be made with the movement
# numbers (data/movement.json) while the strafe stage cannot be made without air strafing.
# Positions are metres from the course's `center` (x, z flat; y = up from the top of the pads). No nodes.
# Dependencies: data/course.json, data/movement.json, data/player.json sprint_multiplier (handed in).
extends RefCounted

const READY := "ready"  # standing on the start pad, clock at zero
const RUNNING := "running"
const DONE := "done"  # finished; back on the start pad = ready again

var cfg := {}
var pads: Array = []
var state := READY
var time := 0.0  # seconds of the run so far (or of the finished run)
var checkpoint := 0  # index of the pad you go back to after a fall
var best := 0.0  # best finished time of this character (0 = none yet)
var last := 0.0  # the latest finished time


func setup(course: Dictionary) -> void:
	cfg = course
	pads = course.get("pads", [])
	reset()


func reset() -> void:
	state = READY
	time = 0.0
	checkpoint = start_index()


func start_index() -> int:
	return _first_of("start")


func finish_index() -> int:
	return _first_of("finish")


# The pad whose top the flat spot (x, z) stands over (0.15 m to spare at the rims, the body is round), or -1.
func pad_at(x: float, z: float) -> int:
	for i in pads.size():
		var p: Dictionary = pads[i]
		if absf(x - float(p["at"][0])) <= float(p["size"][0]) * 0.5 + 0.15 and absf(z - float(p["at"][1])) <= float(p["size"][1]) * 0.5 + 0.15:
			return i
	return -1


# Where to stand on a pad (its middle, y 0) and which way to face: toward the next pad.
func stand_on(index: int) -> Dictionary:
	var p: Dictionary = pads[clampi(index, 0, pads.size() - 1)]
	var at := Vector3(float(p["at"][0]), 0.0, float(p["at"][1]))
	var ahead: Dictionary = pads[mini(index + 1, pads.size() - 1)]
	var way := Vector3(float(ahead["at"][0]), 0.0, float(ahead["at"][1])) - at
	return {"at": at, "yaw": atan2(-way.x, -way.z) if way.length() > 0.1 else 0.0}


func stage_of(index: int) -> int:
	return int(pads[clampi(index, 0, pads.size() - 1)].get("stage", 0))


func stage_name(index: int) -> String:
	var stages: Array = cfg.get("stages", [])
	var n := stage_of(index)
	return String(stages[n].get("name", "")) if n < stages.size() else ""


func stage_count() -> int:
	return (cfg.get("stages", []) as Array).size() - 1  # the start is stage 0


# One frame. `on_pad` = the pad stood on (-1 = in the air or nowhere); `fallen` = dropped under the course.
# Returns what happened: "", "start", "checkpoint", "fell", "restart" (fell before the first checkpoint), "finish", "record".
func update(delta: float, on_pad: int, fallen: bool) -> String:
	if fallen:
		if state == RUNNING and checkpoint != start_index():
			time += delta
			return "fell"
		reset()
		return "restart"
	match state:
		READY:
			if on_pad != start_index():
				state = RUNNING
				time = delta
				return "start"
		RUNNING:
			time += delta
			if on_pad == finish_index():
				state = DONE
				last = time
				if best <= 0.0 or time < best:
					best = time
					return "record"
				return "finish"
			if on_pad > checkpoint and String(pads[on_pad].get("kind", "")) == "checkpoint":
				checkpoint = on_pad
				return "checkpoint"
		DONE:
			if on_pad == start_index():
				reset()
	return ""


static func clock(seconds: float) -> String:
	var hundredths := roundi(maxf(seconds, 0.0) * 100.0)
	return "%d:%02d.%02d" % [floori(float(hundredths) / 6000.0), floori(float(hundredths) / 100.0) % 60, hundredths % 100]


# Every hop checked against the movement: the edge-to-edge gap must be at most 90 % of how far a jump carries at the
# stage's speed (with a little jump fatigue; a strafe stage: all of it), and on a strafe stage it must be MORE than a
# knife sprint jump carries.
# Returns [problems, lines describing every hop].
func hop_problems(move: Dictionary, sprint_multiplier: float) -> Array:
	var unit := float(move["unit_m"])
	var air := 2.0 * float(move["jump_impulse"]) / float(move["gravity"]) * 0.9  # seconds in the air with some fatigue
	var plain := float(move["base_speed"]) * sprint_multiplier * unit  # knife out, sprinting (data/player.json sprint_multiplier)
	var stages: Array = cfg.get("stages", [])
	var wrong := PackedStringArray()
	var lines := PackedStringArray()
	for i in range(1, pads.size()):
		var a: Dictionary = pads[i - 1]
		var b: Dictionary = pads[i]
		var raw := _gap(a, b)
		var gap := raw - 2.0 * float(cfg.get("edge_reach", 0.0))  # the round body stands and lands a little past the edges
		var stage: Dictionary = stages[mini(int(b.get("stage", 0)), stages.size() - 1)]
		var reach := float(stage.get("speed", 400.0)) * unit * air
		var strafe := bool(stage.get("strafe", false))
		lines.append("hop %d -> %d: gap %.2f m, reach at %d u/s %.2f m%s" % [i - 1, i, gap, int(stage.get("speed", 400)), reach, "  (knife sprint reaches %.2f m)" % (plain * air / 0.9) if strafe else ""])
		if gap > reach * (1.0 if strafe else 0.9):  # a strafe stage is built at the very top speed: no margin
			wrong.append("hop %d -> %d is too long (%.2f m of %.2f m)" % [i - 1, i, gap, reach])
		if strafe and gap > 0.5 and gap <= plain * air / 0.9:
			wrong.append("hop %d -> %d can be done without strafing (%.2f m)" % [i - 1, i, gap])
		if raw < -0.01:
			wrong.append("pads %d and %d overlap" % [i - 1, i])
	return [wrong, lines]


func problems() -> Array:
	var out: Array = []
	if start_index() < 0 or finish_index() < 0:
		out.append("the course needs a start and a finish pad")
	for p: Dictionary in pads:
		if float(p["size"][0]) <= 0.0 or float(p["size"][1]) <= 0.0:
			out.append("a pad without size")
		if int(p.get("stage", 0)) >= (cfg.get("stages", []) as Array).size():
			out.append("a pad of a stage that is not listed")
	return out


# Edge-to-edge distance between two pads along the line joining their middles.
func _gap(a: Dictionary, b: Dictionary) -> float:
	var way := Vector2(float(b["at"][0]) - float(a["at"][0]), float(b["at"][1]) - float(a["at"][1]))
	var length := way.length()
	if length < 0.01:
		return -1.0
	var dir := way / length
	var half_a := _half_along(a, dir)
	var half_b := _half_along(b, dir)
	return length - half_a - half_b


# How far from its middle a pad reaches in direction `dir` (the ray leaves the box there).
func _half_along(p: Dictionary, dir: Vector2) -> float:
	var hx := float(p["size"][0]) * 0.5
	var hz := float(p["size"][1]) * 0.5
	var tx := hx / absf(dir.x) if absf(dir.x) > 0.0001 else INF
	var tz := hz / absf(dir.y) if absf(dir.y) > 0.0001 else INF
	return minf(tx, tz)


func _first_of(kind: String) -> int:
	for i in pads.size():
		if String(pads[i].get("kind", "")) == kind:
			return i
	return -1
