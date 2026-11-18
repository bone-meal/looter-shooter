# Purpose: walking on a SHIP'S DECK without physics (sea step 8b: pirate crews and boarders): one step in ship space
# (x across, y up, z along: the bow is -z) kept inside the bulwarks and off the masts, up and down the raised decks
# only by their stairs, at the deck's height (on a stair: along its ramp); in a ship with a HOLD (sea step 8b-2) a body
# below the main deck stays inside the hold and comes up only by its companion stair (the hatch on deck leads down
# it). The same on every machine. Pure.
# Dependencies: a ship spec of data/sea/ships.json (outline, deck, levels, masts), passed in.
extends RefCounted

const RAIL := 0.55  # m kept off the bulwark
const ENDS := 0.8  # m kept off the bow and the stern
const MAST := 0.5  # m kept off a mast's middle
const STAIR := 0.5  # m either side of a stair's middle that counts as on it


static func half_width(spec: Dictionary, z: float) -> float:
	var outline: Array = spec["outline"]
	for i in range(1, outline.size()):
		var a: Array = outline[i - 1]
		var b: Array = outline[i]
		if z <= float(a[0]) and z >= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), (float(a[0]) - z) / maxf(float(a[0]) - float(b[0]), 0.001))
	return 0.0


# The raised deck at z ({} = none).
static func level_at(spec: Dictionary, z: float) -> Dictionary:
	for level: Dictionary in spec.get("levels", []):
		if z >= float(level["from"]) and z <= float(level["to"]):
			return level
	return {}


# The stair under (x, z) ({} = none) and how far up it, 0..1.
static func stair_at(spec: Dictionary, x: float, z: float) -> Array:
	for level: Dictionary in spec.get("levels", []):
		for stair: Dictionary in level["stairs"]:
			var lo := minf(float(stair["low"]), float(stair["high"]))
			var hi := maxf(float(stair["low"]), float(stair["high"]))
			if absf(x - float(stair["x"])) <= STAIR and z >= lo and z <= hi:
				var t := (z - float(stair["low"])) / maxf(float(stair["high"]) - float(stair["low"]), 0.001)
				return [level, clampf(t, 0.0, 1.0)]
	return [{}, 0.0]


# The hold's companion stair: is (x, z) on it, and its height there.
static func on_hatch(spec: Dictionary, x: float, z: float) -> bool:
	var hold: Dictionary = spec.get("hold", {})
	if hold.is_empty():
		return false
	var st: Dictionary = hold["stair"]
	return absf(x - float(st["x"])) <= float(st["w"]) * 0.5 and z >= minf(float(st["low"]), float(st["high"])) and z <= maxf(float(st["low"]), float(st["high"]))


const HEADROOM := 1.1  # (game/sea_ship.gd: the hatch opening runs on past the stair's foot)


# In the hatch opening but not over the stair: a body walking there drops into the hold.
static func in_opening(spec: Dictionary, x: float, z: float) -> bool:
	var hold: Dictionary = spec.get("hold", {})
	if hold.is_empty():
		return false
	var st: Dictionary = hold["stair"]
	var foot_aft := float(st["low"]) > float(st["high"])
	var lo := minf(float(st["low"]), float(st["high"])) - (0.0 if foot_aft else HEADROOM)
	var hi := maxf(float(st["low"]), float(st["high"])) + (HEADROOM if foot_aft else 0.0)
	return absf(x - float(st["x"])) <= float(st["w"]) * 0.5 and z >= lo and z <= hi and not on_hatch(spec, x, z)


static func hatch_height(spec: Dictionary, z: float) -> float:
	var hold: Dictionary = spec["hold"]
	var st: Dictionary = hold["stair"]
	var t := clampf((z - float(st["low"])) / (float(st["high"]) - float(st["low"])), 0.0, 1.0)
	return lerpf(float(hold["floor"]), float(spec["deck"]), t)


# Is a body at this ship-space point below the main deck (in the hold)?
static func below(spec: Dictionary, p: Vector3) -> bool:
	var hold: Dictionary = spec.get("hold", {})
	return not hold.is_empty() and p.y < float(spec["deck"]) - 0.4 and p.z >= float(hold["from"]) - 0.5 and p.z <= float(hold["to"]) + 0.5


static func height_at(spec: Dictionary, x: float, z: float, in_hold := false) -> float:
	if on_hatch(spec, x, z):
		return hatch_height(spec, z)
	if in_hold:
		return float(spec["hold"]["floor"])
	var deck := float(spec["deck"])
	var on := stair_at(spec, x, z)
	if not (on[0] as Dictionary).is_empty():
		return deck + float(on[0]["height"]) * float(on[1])
	var level := level_at(spec, z)
	return deck + (float(level["height"]) if not level.is_empty() else 0.0)


# Where a body at `from` ends up after trying to move by `step` (both ship space).
static func step(spec: Dictionary, from: Vector3, by: Vector3) -> Vector3:
	var outline: Array = spec["outline"]
	var to := from + Vector3(by.x, 0.0, by.z)
	if below(spec, from) or (on_hatch(spec, from.x, from.z) and from.y < float(spec["deck"]) - 0.05):
		return _in_hold(spec, from, to)
	to.z = clampf(to.z, float(outline[outline.size() - 1][0]) + ENDS, float(outline[0][0]) - ENDS)
	var was := level_at(spec, from.z)
	var now := level_at(spec, to.z)
	if was != now and (stair_at(spec, from.x, from.z)[0] as Dictionary).is_empty() and (stair_at(spec, to.x, to.z)[0] as Dictionary).is_empty():
		to.z = from.z  # up or down a raised deck's edge only by its stairs
	var hw := maxf(half_width(spec, to.z) - RAIL, 0.0)
	to.x = clampf(to.x, -hw, hw)
	for mast: Array in spec["masts"]:
		var mz := float(mast[0])
		if absf(to.z - mz) < MAST and absf(to.x) < MAST:
			to.x = MAST * (1.0 if from.x >= 0.0 else -1.0)  # round the mast on the side it came from
	to.y = float(spec["hold"]["floor"]) if in_opening(spec, to.x, to.z) else height_at(spec, to.x, to.z)  # (into the open hatch: down he goes)
	return to


# A step in the hold: inside its walls, on its floor, onto the stair (and up it: off its head onto the deck).
static func _in_hold(spec: Dictionary, from: Vector3, to: Vector3) -> Vector3:
	var hold: Dictionary = spec["hold"]
	if on_hatch(spec, to.x, to.z):
		to.y = hatch_height(spec, to.z)
		return to
	if on_hatch(spec, from.x, from.z) and hatch_height(spec, from.z) > float(spec["deck"]) - 0.4:
		to.y = float(spec["deck"])  # off the stair's head: on deck
		return to
	to.x = clampf(to.x, -float(hold["hw"]) + 0.45, float(hold["hw"]) - 0.45)
	to.z = clampf(to.z, float(hold["from"]) + 0.45, float(hold["to"]) - 0.45)
	to.y = float(hold["floor"])
	return to


# A spot in the hold for a crewman below (n-th of count), clear of the stair.
static func hold_muster(spec: Dictionary, n: int, count: int) -> Vector3:
	var hold: Dictionary = spec["hold"]
	var z := lerpf(float(hold["from"]) + 0.8, float(hold["to"]) - 0.8, (float(n) + 0.5) / maxf(float(count), 1.0))
	var x := (float(hold["hw"]) - 0.7) * (1.0 if n % 2 == 0 else -1.0)
	return Vector3(x, float(hold["floor"]), z)


# A free spot on deck for a crewman: n-th of count, spread along the waist, alternating sides (ship space).
static func muster(spec: Dictionary, n: int, count: int, jitter: float) -> Vector3:
	var outline: Array = spec["outline"]
	var stern := float(outline[0][0]) - ENDS * 2.0
	var bow := float(outline[outline.size() - 1][0]) + ENDS * 2.0
	var z := lerpf(stern, bow, (float(n) + 0.5 + jitter * 0.4) / maxf(float(count), 1.0))
	var x := (half_width(spec, z) - RAIL - 0.3) * (0.55 if n % 2 == 0 else -0.55)
	return step(spec, Vector3(x, height_at(spec, x, z), z), Vector3.ZERO)
