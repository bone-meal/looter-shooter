# Purpose: pure inspect moves: for a thing in hand ("gun:<body>", "knife:<type>", "staff") how far it is moved and
# turned t seconds into its inspect, read from data/inspect.json and passed through the keys smoothly (Catmull-Rom).
# No nodes: game/player.gd and game/staff_caster.gd add the offset to the model in first person.
# Dependencies: data/inspect.json (handed in through setup).
extends RefCounted

var moves := {}  # id -> {"keys": [[t, x, y, z, pitch, yaw, roll], ...]}


func setup(cfg: Dictionary) -> void:
	moves = cfg.get("moves", {})


func has(id: String) -> bool:
	return moves.has(id)


func length(id: String) -> float:
	var keys: Array = moves.get(id, {}).get("keys", [])
	return float((keys[keys.size() - 1] as Array)[0]) if keys.size() > 1 else 0.0


# [Vector3 metres, Vector3 degrees] at t seconds; zero before 0 and after the end (whole turns are dropped there).
func pose(id: String, t: float) -> Array:
	var keys: Array = moves.get(id, {}).get("keys", [])
	if keys.size() < 2 or t <= 0.0 or t >= length(id):
		return [Vector3.ZERO, Vector3.ZERO]
	var i := 0
	while i < keys.size() - 2 and t > float((keys[i + 1] as Array)[0]):
		i += 1
	var a: Array = keys[maxi(i - 1, 0)]
	var b: Array = keys[i]
	var c: Array = keys[i + 1]
	var d: Array = keys[mini(i + 2, keys.size() - 1)]
	var span := float(c[0]) - float(b[0])
	var w := clampf((t - float(b[0])) / span, 0.0, 1.0) if span > 0.0 else 1.0
	var v := PackedFloat32Array()
	for n in range(1, 7):
		v.append(cubic_interpolate(float(b[n]), float(c[n]), float(a[n]), float(d[n]), w))
	return [Vector3(v[0], v[1], v[2]), Vector3(v[3], v[4], v[5])]


# Data mistakes for the checks.
func problems() -> Array:
	var out: Array = []
	for id: String in moves:
		var keys: Array = moves[id].get("keys", [])
		if keys.size() < 2:
			out.append("%s has fewer than two keys" % id)
			continue
		var last := -1.0
		for key: Array in keys:
			if key.size() != 7:
				out.append("%s: a key without 7 numbers" % id)
			elif float(key[0]) <= last:
				out.append("%s: keys out of time order" % id)
			else:
				last = float(key[0])
		var first: Array = keys[0]
		var end: Array = keys[keys.size() - 1]
		for n in range(1, 7):
			if not is_zero_approx(float(first[n])):
				out.append("%s: the first key is not the hold" % id)
				break
		for n in range(1, 4):
			if not is_zero_approx(float(end[n])):
				out.append("%s: the last key does not come back to the hold" % id)
				break
		for n in range(4, 7):
			if not is_zero_approx(fmod(float(end[n]), 360.0)):
				out.append("%s: the last key turns %s degrees (not whole circles)" % [id, str(end[n])])
				break
	return out
