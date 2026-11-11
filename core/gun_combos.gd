# Purpose: pure rules for what a gun's PARTS do together, on top of each part's own modifiers (core/gun_stats.gd):
# named combos (certain part kinds on the same gun: extra stat changes, sometimes a buff effect and a name word) and the
# factory-matched bonus (several parts made by the gun's own manufacturer). Nothing is stored on the gun: it all follows
# from the parts, so saves and the host's gun check need no change.
# Dependencies: core/gun_db.gd (combos, matched). Data: data/gun_parts.json "combos", "matched".
extends RefCounted


# The combos active on a gun, strongest first (most parts needed). Each is the data entry: {id, name, needs, mods, buffs, desc}.
static func active(db: RefCounted, gun: Dictionary) -> Array:
	var found: Array = []
	var gun_parts: Dictionary = gun.get("parts", {})
	for combo: Dictionary in db.combos:
		var needs: Dictionary = combo["needs"]
		var fits := true
		for slot: String in needs:
			if not gun_parts.has(slot) or String((gun_parts[slot] as Dictionary)["kind"]) != String(needs[slot]):
				fits = false
		if fits:
			found.append(combo)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a["needs"] as Dictionary).size() > (b["needs"] as Dictionary).size())
	var same := matched_count(gun)
	var best := {}
	for rule: Dictionary in db.matched:
		if same >= int(rule["count"]) and (best.is_empty() or int(rule["count"]) > int(best["count"])):
			best = rule
	if not best.is_empty():
		found.append(best)
	return found


# How many of the gun's parts were made by the gun's own manufacturer.
static func matched_count(gun: Dictionary) -> int:
	var count := 0
	var gun_parts: Dictionary = gun.get("parts", {})
	for slot: String in gun_parts:
		if String((gun_parts[slot] as Dictionary)["maker"]) == String(gun.get("maker", "")):
			count += 1
	return count


# Checks the combo data against the part, stat and buff tables. Returns problems as text lines (empty = fine).
static func problems(db: RefCounted) -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for combo: Dictionary in db.combos + db.matched:
		var id := String(combo.get("id", ""))
		if id == "" or seen.has(id):
			out.append("combo id missing or repeated: '%s'" % id)
		seen[id] = true
		for slot: String in combo.get("needs", {}):
			if not db.parts.has(slot) or not (db.parts[slot] as Dictionary).has(String(combo["needs"][slot])):
				out.append("%s: unknown part %s/%s" % [id, slot, combo["needs"][slot]])
		for stat: String in combo.get("mods", {}):
			if not stat in ["damage", "fire_rate", "mag_size", "reload_time", "spread", "recoil", "ads_fov", "crit_chance"]:
				out.append("%s: unknown stat %s" % [id, stat])
		for buff: String in combo.get("buffs", {}):
			if db.buff_def(buff).is_empty():
				out.append("%s: unknown buff %s" % [id, buff])
	return out
