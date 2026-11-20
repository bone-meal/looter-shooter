# Purpose: the LOOT FILTER (polish1 item 68, Payday 2 / Diablo 2 style): how a gun drop shows on the ground for this
# player. A filtered drop STAYS on the ground (it can still be picked up) but has no beam, no name and no chime; a
# highlighted one gets a star and a gold edge on its name. The player's choices live in the settings (`loot_filter`):
# {"min": lowest tier shown (tier id), "no_beam": [tier ids whose beams are off], "chase": highlight chase guns,
#  "traits": highlight guns with a trait, "makers": [maker ids to highlight]}. Pure rules, no nodes.
# Dependencies: core/gun_db.gd (tiers, uniques, makers), read only.
extends RefCounted

const DEFAULTS := {"min": "grey", "no_beam": [], "chase": true, "traits": false, "makers": []}


# A settings value made safe: unknown keys dropped, wrong types replaced by the defaults.
static func clean(raw: Variant) -> Dictionary:
	var out := DEFAULTS.duplicate(true)
	if not raw is Dictionary:
		return out
	var d: Dictionary = raw
	if d.get("min") is String:
		out["min"] = String(d["min"])
	for key: String in ["no_beam", "makers"]:
		if d.get(key) is Array:
			var kept: Array = []
			for v: Variant in d[key]:
				if v is String and not kept.has(v):
					kept.append(String(v))
			out[key] = kept
	for key: String in ["chase", "traits"]:
		if d.get(key) is bool:
			out[key] = bool(d[key])
	return out


# How this gun shows: {"shown": beam / name / chime at all, "beam": its beam, "mark": highlighted}.
static func look(filter: Dictionary, db: RefCounted, gun: Dictionary) -> Dictionary:
	var tier := String(gun.get("tier", ""))
	var shown: bool = int(db.tier_index(tier)) >= maxi(int(db.tier_index(String(filter.get("min", "grey")))), 0)
	var mark := false
	if bool(filter.get("chase", true)) and gun.has("unique") and (db.uniques.get(String(gun["unique"]), {}) as Dictionary).has("red"):
		mark = true
	if bool(filter.get("traits", false)) and not (gun.get("traits", []) as Array).is_empty():
		mark = true
	if (filter.get("makers", []) as Array).has(String(gun.get("maker", ""))) and not gun.has("unique"):
		mark = true
	if mark:
		shown = true  # a highlighted gun is never filtered away
	return {"shown": shown, "beam": shown and not (filter.get("no_beam", []) as Array).has(tier), "mark": mark}
