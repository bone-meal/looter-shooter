# Purpose: RANDOM ENCOUNTERS at sea (sea step 8; director: enemies come as random encounters while sailing, weighted
# by region, weather and night): the chance of an encounter at one check, which kind comes (weights, the first region
# each kind sails in, night-only kinds), where it comes in (ahead of the player's bow, out of sight), and what a sunk
# foe leaves floating (doubloons, materials, a gun chance, scaled by the region). Pure: no nodes, no randomness of its
# own (rolls are passed in).
# Dependencies: data/sea/encounters.json (passed in).
extends RefCounted

var cfg: Dictionary


func _init(data: Dictionary) -> void:
	cfg = data


# "region_4" -> 4; anything else (open water, raid cells) counts as region 1.
static func region_number(region_id: String) -> int:
	return maxi(int(region_id.trim_prefix("region_")), 1) if region_id.begins_with("region_") else 1


func in_safe_waters(x: float, z: float) -> bool:
	var c: Array = cfg["safe_centre"]
	return Vector2(x, z).distance_to(Vector2(float(c[0]), float(c[1]))) < float(cfg["safe_radius"])


# The chance that one check brings an encounter.
func chance(region_id: String, weather_kind: String, night: bool, anchored: bool) -> float:
	var p := float(cfg["base_chance"]) * float((cfg["region_mult"] as Dictionary).get(region_id, 1.0))
	p *= float((cfg["weather_mult"] as Dictionary).get(weather_kind, 1.0))
	if night:
		p *= float(cfg["night_mult"])
	if anchored:
		p *= float(cfg["anchored_mult"])
	return clampf(p, 0.0, 1.0)


# The kinds that may come here and now, with their weights: {kind id: weight}.
func allowed(region_id: String, night: bool) -> Dictionary:
	var out := {}
	var n := region_number(region_id)
	for id: String in cfg["kinds"]:
		var k: Dictionary = cfg["kinds"][id]
		if n < int(k.get("regions", 1)) or (bool(k.get("night_only", false)) and not night):
			continue
		out[id] = float(k.get("weight", 1.0))
	return out


# Which kind comes for a roll in [0, 1); "" when none may.
func pick(region_id: String, night: bool, roll: float) -> String:
	var kinds := allowed(region_id, night)
	var total := 0.0
	for id: String in kinds:
		total += float(kinds[id])
	if total <= 0.0:
		return ""
	var left := clampf(roll, 0.0, 0.9999) * total
	for id: String in kinds:
		left -= float(kinds[id])
		if left < 0.0:
			return id
	return String(kinds.keys().back())


# Where it comes in (sea x, z): spawn_m away, inside the cone round `heading` (a ship's yaw: forward = (-sin, -cos)).
func spawn_point(x: float, z: float, heading: float, roll_angle: float, roll_far: float) -> Vector2:
	var cone := deg_to_rad(float(cfg["spawn_cone_deg"]))
	var a := heading + (roll_angle * 2.0 - 1.0) * cone
	var far: Array = cfg["spawn_m"]
	var d := lerpf(float(far[0]), float(far[1]), roll_far)
	return Vector2(x - sin(a) * d, z - cos(a) * d)


# The yaw that points a ship from (x, z) towards (tx, tz).
static func yaw_towards(x: float, z: float, tx: float, tz: float) -> float:
	return atan2(-(tx - x), -(tz - z))


# One floating piece's loot: {"doubloons": n, "items": {id: n}, "gun": bool}. rolls = 2 + items + 1 numbers in [0, 1).
func loot(loot_id: String, region_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var spec: Dictionary = cfg["loot"].get(loot_id, {})
	var mult := float((cfg["loot_mult"] as Dictionary).get(region_id, 1.0))
	var d: Array = spec.get("doubloons", [0, 0])
	var out := {"doubloons": roundi(float(rng.randi_range(int(d[0]), int(d[1]))) * mult), "items": {}, "gun": rng.randf() < float(spec.get("gun_chance", 0.0))}
	var items: Dictionary = spec.get("items", {})
	for id: String in items:
		var n := rng.randi_range(int(items[id][0]), int(items[id][1]))
		if n > 0:
			out["items"][id] = n
	return out


func pieces(loot_id: String, rng: RandomNumberGenerator) -> int:
	var p: Array = cfg["loot"].get(loot_id, {}).get("pieces", [3, 4])
	return rng.randi_range(int(p[0]), int(p[1]))
