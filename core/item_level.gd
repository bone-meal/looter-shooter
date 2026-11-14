# Purpose: pure item-level rules (locked: diary/DECISIONS_SEA.md batch 5): what level a drop has where it falls, and
# what a level does to a gun's damage. A gun stores its level as "lvl" (core/gun_gen.gd VERSION 3); older guns count as 1.
# Dependencies: data/item_levels.json (read once).
extends RefCounted

static var _cfg := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/item_levels.json"))
	return _cfg


static func max_level() -> int:
	return int(cfg()["max"])


# A gun's level (1 for guns from before levels existed).
static func of(gun: Dictionary) -> int:
	return int(gun.get("lvl", 1))


static func damage_mult(level: int) -> float:
	return pow(float(cfg()["damage_growth"]), float(clampi(level, 1, max_level()) - 1))


# Island rounds: one level every few rounds, never above the island's cap.
static func for_round(round_number: int) -> int:
	return clampi(1 + floori(float(maxi(round_number, 1) - 1) / float(cfg()["rounds_per_level"])), 1, int(cfg()["island_cap"]))


# The colosseum: by the wave (1-based); past the list = its last level.
static func for_wave(wave: int) -> int:
	var list: Array = cfg()["colosseum_levels"]
	return mini(int(list[clampi(wave, 1, list.size()) - 1]), int(cfg()["island_cap"]))


# Sea region n (1-7): its lowest and highest drop level.
static func region_band(region: int) -> Vector2i:
	var band := int(cfg()["region_band"])
	return Vector2i(band * (region - 1) + 1, mini(band * region, max_level()))


# A level inside [lo, hi] (crates, the mystery box, the upgrade machine: the island's band).
static func roll(rng: RandomNumberGenerator, lo: int, hi: int) -> int:
	return rng.randi_range(clampi(lo, 1, max_level()), clampi(hi, lo, max_level()))


static func island_band() -> Vector2i:
	var b: Array = cfg()["island_band"]
	return Vector2i(int(b[0]), mini(int(b[1]), int(cfg()["island_cap"])))
