# Purpose: a ship's hull as pure rules (sea step 5d, LOCKED "hull bar + 3 leak zones"): hull points out of a maximum
# per ship, three fixed leak zones (bow, midships, stern; data/sea/ships.json "leaks" or placed from the outline),
# each with a hole 0..1, and the water in the hold 0..1. A hard hit opens or widens the hole at the nearest zone; open
# holes flood the hold, sound ones let the pumps drain it; water slows the ship and sits her lower; a full hold or an
# empty hull sinks her. A plank patches a hole (and mends a little hull) or, with no holes, mends hull.
# State keys added to core/sea/ship_rules.gd's ship state: hull, leaks (Array of 3 floats), water.
# Dependencies: none (data/sea/hull.json and a ship's spec are passed in).
extends RefCounted

var cfg: Dictionary


func _init(hull_cfg: Dictionary) -> void:
	cfg = hull_cfg


func max_hull(ship_id: String) -> float:
	return float((cfg["hull"] as Dictionary).get(ship_id, 400.0))


# Adds the hull keys to a ship state that lacks them (new ships, fleets saved before step 5d).
func fill(state: Dictionary) -> void:
	if not state.has("hull"):
		state["hull"] = max_hull(String(state["ship"]))
	if not state.has("leaks") or (state["leaks"] as Array).size() != 3:
		state["leaks"] = [0.0, 0.0, 0.0]
	if not state.has("water"):
		state["water"] = 0.0


# The three leak zones in ship space [x, z] (bow -z, stern +z), on alternate sides.
static func zones(spec: Dictionary) -> Array:
	if spec.has("leaks"):
		return spec["leaks"]
	var outline: Array = spec["outline"]
	var stern_z := float(outline[0][0])
	var bow_z := float(outline.back()[0])
	var widest := 0.0
	for station: Array in outline:
		widest = maxf(widest, float(station[1]))
	return [[widest * 0.75, bow_z * 0.6], [-widest * 0.85, 0.0], [widest * 0.75, stern_z * 0.6]]


static func nearest_zone(spec: Dictionary, local_x: float, local_z: float) -> int:
	var best := 0
	var best_d := INF
	var list := zones(spec)
	for i in list.size():
		var d := Vector2(local_x - float(list[i][0]), local_z - float(list[i][1])).length()
		if d < best_d:
			best_d = d
			best = i
	return best


# A blow to the hull at a ship-space spot. Returns the zone it holed (-1 = none: too light to break through).
func hit(state: Dictionary, spec: Dictionary, local_x: float, local_z: float, amount: float) -> int:
	if amount <= 0.0 or not is_finite(amount):
		return -1
	var most := max_hull(String(state["ship"]))
	state["hull"] = maxf(float(state["hull"]) - amount, 0.0)
	var share := amount / most
	if share < float(cfg["open_share"]):
		return -1
	var zone := nearest_zone(spec, local_x, local_z)
	var leaks: Array = state["leaks"]
	leaks[zone] = minf(float(leaks[zone]) + share * float(cfg["hole_per_share"]), 1.0)
	return zone


func holes(state: Dictionary) -> float:
	var sum := 0.0
	for hole: float in state["leaks"]:
		sum += hole
	return sum


# One step: the hold floods through the holes or the pumps drain it. Returns true when she founders this step.
func step(state: Dictionary, delta: float) -> bool:
	var open := holes(state)
	var water := float(state["water"])
	if open > 0.0:
		water += open * float(cfg["flood_per_second"]) * delta
	else:
		water -= float(cfg["drain_per_second"]) * delta
	state["water"] = clampf(water, 0.0, 1.0)
	return sunk(state)


func sunk(state: Dictionary) -> bool:
	return float(state["hull"]) <= 0.0 or float(state["water"]) >= float(cfg["sink_water"])


# Speed share left by the water in the hold (1 = dry).
func speed_mult(state: Dictionary) -> float:
	return 1.0 - float(cfg["slow_at_full_water"]) * float(state["water"])


# Metres she sits lower with water in the hold.
func sit_lower(state: Dictionary, spec: Dictionary) -> float:
	return float(cfg["sit_lower"]) * float(spec["draft"]) * float(state["water"])


# Damage from running aground at a speed (m/s): nothing under aground_from.
func aground_damage(speed: float) -> float:
	var over := absf(speed) - float(cfg["aground_from"])
	return float(cfg["aground_damage"]) * over * over if over > 0.0 else 0.0


# A plank used at a zone: closes its hole (+ a little hull), or with no hole anywhere mends hull. Returns what it did:
# "patched", "mended" or "" (nothing to do).
func use_plank(state: Dictionary, zone: int) -> String:
	var most := max_hull(String(state["ship"]))
	var leaks: Array = state["leaks"]
	if zone >= 0 and zone < leaks.size() and float(leaks[zone]) > 0.0:
		leaks[zone] = 0.0
		state["hull"] = minf(float(state["hull"]) + most * float(cfg["patch_hull"]), most)
		return "patched"
	if holes(state) <= 0.0 and float(state["hull"]) < most:
		state["hull"] = minf(float(state["hull"]) + most * float(cfg["mend_hull"]), most)
		return "mended"
	return ""


# After she sank: back at the shipyard with little hull, a dry hold and no holes (mended there with planks).
func refloat(state: Dictionary) -> void:
	state["hull"] = max_hull(String(state["ship"])) * float(cfg["refloat_hull"])
	state["leaks"] = [0.0, 0.0, 0.0]
	state["water"] = 0.0


# She may only weigh anchor with at least this share of her hull (a refloated wreck must be mended first).
func seaworthy(state: Dictionary) -> bool:
	return float(state["hull"]) >= max_hull(String(state["ship"])) * float(cfg["seaworthy"])
