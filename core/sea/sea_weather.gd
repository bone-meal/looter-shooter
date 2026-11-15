# Purpose: pure rules for the sea's weather and wind (sea step 4). Every data/sea/world.json weather.slot_minutes of
# the shared clock each region draws its weather (calm, rain, fog, storm) from its weights by a fixed hash, so all
# machines agree without sending anything; the change blends over blend_seconds. Gives fog, rain, light, swell
# (metres, the region's calm swell times the weather's) and the wind (a slowly turning direction and a strength).
# Dependencies: core/sea/sea_map.gd (regions).
extends RefCounted

var _cfg: Dictionary
var _seed := 1


func _init(world: Dictionary, world_seed: int = 1) -> void:
	_cfg = world["weather"]
	_seed = world_seed


static func _hash01(a: int, b: int, salt: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFFFF) / float(0xFFFFFF)


# The weather kind a region draws for slot number `slot`.
func kind_in(region_id: String, region: Dictionary, slot: int) -> String:
	var weights: Dictionary = region["weather"]
	var total := 0.0
	for kind: String in weights:
		total += float(weights[kind])
	var roll := _hash01(slot, region_id.hash(), _seed) * total
	for kind: String in weights:
		roll -= float(weights[kind])
		if roll <= 0.0:
			return kind
	return String(weights.keys()[0])


# Everything the weather sets, for a region at a time of the shared clock: {"kind", "fog", "rain", "light",
# "swell", "wind" (0..1), "wind_dir" (radians, where the wind blows TO)}.
func at(region_id: String, region: Dictionary, seconds: float) -> Dictionary:
	var slot_len := float(_cfg["slot_minutes"]) * 60.0
	var slot := floori(seconds / slot_len)
	var into := seconds - float(slot) * slot_len
	var blend := clampf(into / float(_cfg["blend_seconds"]), 0.0, 1.0)
	var now := kind_in(region_id, region, slot)
	var before := kind_in(region_id, region, slot - 1)
	var a: Dictionary = _cfg["kinds"][before]
	var b: Dictionary = _cfg["kinds"][now]
	var out := {"kind": now}
	for key: String in ["fog", "rain", "wind", "swell", "light"]:
		out[key] = lerpf(float(a[key]), float(b[key]), blend)
	out["swell"] = float(region["swell"]) * float(out["swell"])
	out["wind"] = clampf(float(region["wind"]) + float(out["wind"]), 0.05, 1.0)
	# the wind turns slowly with the clock (a full turn in about 40 minutes, wandering)
	out["wind_dir"] = seconds / 2400.0 * TAU + sin(seconds / 517.0) * 0.6 + float(_seed % 7)
	return out
