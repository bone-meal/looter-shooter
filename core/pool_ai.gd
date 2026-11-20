# Purpose: (polish1 item 71) the house player at the pool table, pure: for each ball it may hit and each pocket it
# finds the ghost-ball aim (where the cue ball must be at contact), skips cuts over 78 degrees and blocked paths, and
# takes the easiest (straightest, shortest); with no pot on it plays a soft safety at its nearest legal ball. Then
# its skill shakes the aim and the power. With ball in hand it first puts the cue ball behind its best pot.
# Dependencies: core/pool_sim.gd, core/pool_rules.gd (handed in).
extends RefCounted


# Returns {"angle", "power", "spin", "called"} for player `me`.
static func choose(sim: RefCounted, rules: RefCounted, me: int, skill: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var best := _best_pot(sim, rules, me)
	var shot: Dictionary
	if best.is_empty():
		shot = _safety(sim, rules, me)
	else:
		shot = best
	var err := deg_to_rad(float(skill.get("aim_error", 1.0)))
	shot["angle"] = float(shot["angle"]) + rng.randfn(0.0, err)
	shot["power"] = clampf(float(shot["power"]) * (1.0 + rng.randfn(0.0, float(skill.get("power_error", 0.08)))), 0.08, 1.0)
	return shot


# Where to put the cue ball with ball in hand: behind the easiest pot, else the head spot.
static func place_cue(sim: RefCounted, rules: RefCounted, me: int) -> Vector2:
	var on: PackedByteArray = sim.get("on_table")
	var pos: PackedVector2Array = sim.get("pos")
	var pockets: Array = sim.get("pockets")
	var r := float(sim.get("r"))
	var best_score := -1.0
	var best_at: Vector2 = sim.call("head_spot")
	for b: int in rules.call("legal_targets", me, on):
		for k in pockets.size():
			var to_pocket: Vector2 = (pockets[k] - pos[b]).normalized()
			var ghost: Vector2 = pos[b] - to_pocket * 2.0 * r
			var at := ghost - to_pocket * 0.3
			if not _clear(sim, pos[b], pockets[k], [b]) or not _free_spot(sim, at):
				continue
			var score := 1.0 / (0.3 + pos[b].distance_to(pockets[k]))
			if score > best_score:
				best_score = score
				best_at = at
	return best_at


static func _best_pot(sim: RefCounted, rules: RefCounted, me: int) -> Dictionary:
	var on: PackedByteArray = sim.get("on_table")
	var pos: PackedVector2Array = sim.get("pos")
	var pockets: Array = sim.get("pockets")
	var r := float(sim.get("r"))
	var cue := pos[0]
	var best := {}
	var best_score := 0.0
	for b: int in rules.call("legal_targets", me, on):
		for k in pockets.size():
			var to_pocket: Vector2 = (pockets[k] - pos[b])
			var dp := to_pocket.length()
			to_pocket /= dp
			var ghost: Vector2 = pos[b] - to_pocket * 2.0 * r
			var aim := ghost - cue
			var da := aim.length()
			if da < 0.001:
				continue
			var cut := acos(clampf(aim.normalized().dot(to_pocket), -1.0, 1.0))
			if cut > deg_to_rad(78.0):
				continue
			if not _clear(sim, cue, ghost, [0, b]) or not _clear(sim, pos[b], pockets[k], [b]):
				continue
			var score := cos(cut) * cos(cut) / (0.4 + da + dp * 1.3)
			if score > best_score:
				best_score = score
				var power := clampf(0.18 + (da + dp / maxf(cos(cut), 0.25)) * 0.16, 0.2, 0.85)
				best = {"angle": aim.angle(), "power": power, "spin": Vector2(0, -0.1), "called": k}
	return best


static func _safety(sim: RefCounted, rules: RefCounted, me: int) -> Dictionary:
	var on: PackedByteArray = sim.get("on_table")
	var pos: PackedVector2Array = sim.get("pos")
	var best_d := 99.0
	var aim := Vector2(1, 0)
	for b: int in rules.call("legal_targets", me, on):
		var d := pos[0].distance_to(pos[b])
		if d < best_d and _clear(sim, pos[0], pos[b], [0, b]):
			best_d = d
			aim = pos[b] - pos[0]
	if best_d == 99.0:  # every path blocked: hit the nearest legal ball anyway (likely a foul)
		for b: int in rules.call("legal_targets", me, on):
			var d2 := pos[0].distance_to(pos[b])
			if d2 < best_d:
				best_d = d2
				aim = pos[b] - pos[0]
	return {"angle": aim.angle(), "power": clampf(0.25 + best_d * 0.12, 0.25, 0.6), "spin": Vector2.ZERO, "called": -1}


# Is the straight path of a ball from a to b free of other balls (those in `skip` aside)?
static func _clear(sim: RefCounted, a: Vector2, b: Vector2, skip: Array) -> bool:
	var on: PackedByteArray = sim.get("on_table")
	var pos: PackedVector2Array = sim.get("pos")
	var r := float(sim.get("r"))
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return true
	for j in 16:
		if on[j] == 0 or skip.has(j):
			continue
		var t := clampf((pos[j] - a).dot(ab) / l2, 0.0, 1.0)
		if (a + ab * t).distance_to(pos[j]) < 2.0 * r * 0.98:
			return false
	return true


static func _free_spot(sim: RefCounted, at: Vector2) -> bool:
	var on: PackedByteArray = sim.get("on_table")
	var pos: PackedVector2Array = sim.get("pos")
	var r := float(sim.get("r"))
	if absf(at.x) > float(sim.get("length")) * 0.5 - r * 1.5 or absf(at.y) > float(sim.get("width")) * 0.5 - r * 1.5:
		return false
	for j in range(1, 16):
		if on[j] == 1 and pos[j].distance_to(at) < 2.2 * r:
			return false
	return true
