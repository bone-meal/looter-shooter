# Purpose: pure layout of the bhop server's stages (polish1 item 26, data/bhop_server.json): turns a stage's recipe
# into a course dictionary that core/course_rules.gd runs and game/bhop_course.gd builds: `center` (world), `pads`
# (start / pad / checkpoint / finish, each `at` [x, z], `size` [w, d], `y` top height, optional `thick`) and `parts`
# (geometry the rules do not care about: surf `ramp`s, KZ `ladder`s and the towers they lean on), plus `stages` (the
# HUD's names, the speed / strafe a hop section is built for). A seed makes every stage the same for everyone. No nodes.
# Dependencies: data/bhop_server.json and data/course.json (handed in).
extends RefCounted


# The stage at index `i` of the server's list as a course dictionary.
static func course(server: Dictionary, i: int, old_course: Dictionary) -> Dictionary:
	var stage: Dictionary = server["stages"][i]
	var recipe: Dictionary = stage["recipe"]
	if String(recipe.get("kind", "")) == "fixed":
		var fixed := old_course.duplicate(true)
		fixed["parts"] = []
		return fixed
	var rng := RandomNumberGenerator.new()
	rng.seed = int(stage.get("seed", i + 1))
	var out := {"center": _center(server, i), "fall_below": float(server.get("fall_below", 3.0)), "thickness": float(server.get("thickness", 1.0)),
		"edge_reach": float(server.get("edge_reach", 0.28)), "pads": [], "parts": [],
		"stages": [{"name": "Start", "speed": 400, "strafe": false}, {"name": String(stage["name"]), "speed": int(recipe.get("speed", 400)), "strafe": bool(recipe.get("strafe", false))}]}
	match String(recipe["kind"]):
		"hops":
			_hops(out, recipe, rng)
		"long":
			_long(out, recipe)
		"climb":
			_climb(out, recipe, rng)
		"drops":
			_drops(out, recipe, rng)
		"surf":
			_surf(out, recipe, rng)
	return out


# Stages stand round the hub on a ring (the fixed one keeps its own place).
static func _center(server: Dictionary, i: int) -> Array:
	var hub: Array = server["hub"]["at"]
	var n := (server["stages"] as Array).size()
	var a := TAU * float(i) / float(n)
	var ring := float(server.get("ring", 300.0))
	return [float(hub[0]) + cos(a) * ring, float(hub[1]), float(hub[2]) + sin(a) * ring]


static func _pad(out: Dictionary, x: float, z: float, y: float, w: float, d: float, kind: String, extra: Dictionary = {}) -> void:
	var p := {"at": [snappedf(x, 0.01), snappedf(z, 0.01)], "y": snappedf(y, 0.01), "size": [snappedf(w, 0.01), snappedf(d, 0.01)], "kind": kind, "stage": 0 if kind == "start" else 1}
	p.merge(extra)
	(out["pads"] as Array).append(p)


# How far from a square pad's middle its edge lies along a direction (the ray leaves the box there).
static func _half(size: float, dir: Vector2) -> float:
	return size * 0.5 / maxf(absf(dir.x), absf(dir.y))


# Classic and air strafe: pads one after the other; each hop turns by `turn` degrees (left / right in turn when
# `alternate`, else either way), so the air strafe stages need a curve in the air.
static func _hops(out: Dictionary, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var count := int(r["pads"])
	var at := Vector2.ZERO
	var y := 0.0
	var heading := 0.0
	var size := 6.0
	_pad(out, 0.0, 0.0, 0.0, size, size, "start")
	var side := 1.0
	for k in range(1, count):
		var last := k == count - 1
		var kind := "finish" if last else ("checkpoint" if k % int(r.get("every", 6)) == 0 else "pad")
		var next_size := 6.0 if last else (4.0 if kind == "checkpoint" else float(r["pad"]))
		var turn := deg_to_rad(float(r.get("turn", 0.0))) * rng.randf_range(0.6, 1.0)
		if bool(r.get("alternate", false)):
			side = -side
		else:
			side = 1.0 if rng.randf() < 0.5 else -1.0
		heading += turn * side if k > 1 else 0.0
		var dir := Vector2(sin(heading), -cos(heading))
		var gap := rng.randf_range(float(r["gap"][0]), float(r["gap"][1]))
		at += dir * (_half(size, dir) + gap + _half(next_size, dir))
		y += rng.randf_range(-float(r.get("rise", 0.0)), float(r.get("rise", 0.0)))
		_pad(out, at.x, at.y, y, next_size, next_size, kind)
		size = next_size


# Long jumps: a runway, then each jump lands on a pad long enough to run up for the next one.
static func _long(out: Dictionary, r: Dictionary) -> void:
	var w := float(r["width"])
	var run := float(r["runway"])
	var z := 0.0
	_pad(out, 0.0, -run * 0.5, 0.0, w, run, "start")
	z = -run
	var jumps: Array = r["jumps"]
	for k in jumps.size():
		var last := k == jumps.size() - 1
		var length := float(r["landing"]) if last else float(r["landing"]) + run
		z -= float(jumps[k])
		_pad(out, 0.0, z - length * 0.5, 0.0, w if not last else 6.0, length, "finish" if last else "checkpoint")
		z -= length


# KZ: blocks that climb (a jump up each time), and at chosen steps a tower with a LADDER on the face toward you.
static func _climb(out: Dictionary, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var steps := int(r["steps"])
	var ladders: Array = r.get("ladders", [])
	var at_ladder := {}
	for k in ladders.size():
		at_ladder[int(float(k + 1) * float(steps) / float(ladders.size() + 1))] = float(ladders[k])
	var at := Vector2.ZERO
	var y := 0.0
	var size := 6.0
	_pad(out, 0.0, 0.0, 0.0, size, size, "start")
	var heading := 0.0
	for k in range(1, steps + 1):
		var last := k == steps
		var kind := "finish" if last else ("checkpoint" if at_ladder.has(k) or k % int(r.get("every", 5)) == 0 else "pad")
		var next_size := 6.0 if last else (3.0 if kind == "checkpoint" else float(r["block"]))
		heading += deg_to_rad(rng.randf_range(-40.0, 40.0))
		var dir := Vector2(sin(heading), -cos(heading))
		if at_ladder.has(k):  # a tower: walk to its foot, climb the ladder on its face, step off on top
			var tall := float(at_ladder[k])
			var foot := at + dir * (_half(size, dir) + 0.35 + _half(next_size, dir))  # a short step across to the ladder
			var face := foot - dir * _half(next_size, dir)
			_pad(out, foot.x, foot.y, y + tall, next_size, next_size, kind, {"thick": tall + 1.0})
			(out["parts"] as Array).append({"kind": "ladder", "at": [snappedf(face.x - dir.x * 0.12, 0.01), y + tall * 0.5, snappedf(face.y - dir.y * 0.12, 0.01)], "size": [1.0, tall + 0.4, 0.24], "yaw": snappedf(rad_to_deg(atan2(dir.x, dir.y)), 0.1)})
			at = foot
			y += tall
		else:
			var gap := rng.randf_range(float(r["gap"][0]), float(r["gap"][1]))
			at += dir * (_half(size, dir) + gap + _half(next_size, dir))
			y += rng.randf_range(float(r["rise"][0]), float(r["rise"][1]))
			_pad(out, at.x, at.y, y, next_size, next_size, kind)
		size = next_size


# Edgebug drops (my reading): from high up, drop onto small ledges far below while moving; a miss falls past them.
static func _drops(out: Dictionary, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var y := float(r["height"])
	var at := Vector2.ZERO
	var size := 6.0
	_pad(out, 0.0, 0.0, y, size, size, "start")
	var heading := 0.0
	var count := int(r["drops"])
	for k in range(1, count + 1):
		var last := k == count
		var kind := "finish" if last else ("checkpoint" if k % 3 == 0 else "pad")
		var next_size := 6.0 if last else float(r["target"])
		heading += deg_to_rad(rng.randf_range(-35.0, 35.0))
		var dir := Vector2(sin(heading), -cos(heading))
		at += dir * (_half(size, dir) + rng.randf_range(float(r["reach"][0]), float(r["reach"][1])) + _half(next_size, dir))
		y -= rng.randf_range(float(r["fall"][0]), float(r["fall"][1]))
		_pad(out, at.x, at.y, y, next_size, next_size, kind)
		size = next_size


# Surf: V-shaped ramps (two faces `angle` degrees steep meeting at a ridge) running downhill; you drop onto a face
# from the pad before it, ride it to its end and fly to the landing pad after it (a checkpoint), turning by `bend`.
static func _surf(out: Dictionary, r: Dictionary, rng: RandomNumberGenerator) -> void:
	var ramps := int(r["ramps"])
	var length := float(r["length"])
	var drop := float(r["drop"])
	var slope := deg_to_rad(float(r["angle"]))
	var face := float(r["width"])
	var y := float(ramps) * (drop + 4.0)
	var at := Vector2.ZERO
	var heading := 0.0
	_pad(out, 0.0, 0.0, y, 6.0, 6.0, "start")
	var edge := 3.0
	for k in ramps:
		var dir := Vector2(sin(heading), -cos(heading))
		var side := Vector2(-dir.y, dir.x)
		var ridge_top := y - 1.0  # just under the pad you leave
		var begin := at + dir * (edge + 1.0) + side * 1.5  # the ridge runs a little to the right: going straight you drop onto the left face
		var mid := begin + dir * length * 0.5
		var pitch := atan2(drop, length)
		for s: float in [-1.0, 1.0]:  # the two faces
			var off := side * s * face * cos(slope) * 0.5
			(out["parts"] as Array).append({"kind": "ramp", "at": [snappedf(mid.x + off.x, 0.01), snappedf(ridge_top - drop * 0.5 - face * sin(slope) * 0.5, 0.01), snappedf(mid.y + off.y, 0.01)],
				"size": [snappedf(face, 0.01), 0.4, snappedf(length / cos(pitch), 0.01)], "yaw": snappedf(rad_to_deg(atan2(-dir.x, -dir.y)), 0.1), "pitch": snappedf(-rad_to_deg(pitch), 0.1), "roll": snappedf(-rad_to_deg(slope) * s, 0.1)})  # each face rises toward the ridge
		var end := begin + dir * length
		y = ridge_top - drop - face * sin(slope) - 1.5
		heading += deg_to_rad(float(r.get("bend", 0.0))) * (1.0 if rng.randf() < 0.5 else -1.0)
		var next_dir := Vector2(sin(heading), -cos(heading))
		var last := k == ramps - 1
		at = end - side * 1.5 + next_dir * (float(r["gap"]) + 3.0)
		_pad(out, at.x, at.y, y, 6.0, 6.0, "finish" if last else "checkpoint")
		edge = 3.0
