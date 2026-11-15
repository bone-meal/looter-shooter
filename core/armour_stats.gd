# Purpose: the numbers of a rolled armour piece (defense by item level and tier, its bonus rolls), the set bonuses of
# what is worn, and the readable lines for cards. Bonus keys: health_pct, speed_pct, reload_pct, cooldown_pct,
# damage_pct, defense_pct (percent) and block, fire, ice, toxic (shares 0..1).
# Dependencies: core/item_db.gd (passed in; `armour` = data/items.json "armour_loot"). Pure, no nodes.
extends RefCounted

const SHARES := ["block", "fire", "ice", "toxic"]


# {"defense", "block", "resist": {element: share}, "bonus": {key: value}} of one worn stack (plain or rolled).
static func piece(items: RefCounted, stack: Dictionary) -> Dictionary:
	var s: Dictionary = items.stats(String(stack["id"]))
	var out := {"defense": float(s.get("defense", 0)), "block": float(s.get("block", 0)), "resist": (s.get("resist", {}) as Dictionary).duplicate(), "bonus": {}}
	var arm: Dictionary = stack.get("arm", {})
	if arm.is_empty():
		return out
	var cfg: Dictionary = items.armour
	out["defense"] *= pow(float(cfg["defense_growth"]), float(int(arm["lvl"]) - 1)) * float(cfg["tiers"][String(arm["tier"])]["defense"])
	for roll: String in arm["rolls"]:
		var def: Dictionary = cfg["rolls"][roll]
		var key := String(def["stat"])
		out["bonus"][key] = float(out["bonus"].get(key, 0.0)) + lerpf(float(def["min"]), float(def["max"]), float(arm["rolls"][roll]))
	return out


# Set id -> pieces of it worn.
static func set_counts(equipment: Dictionary) -> Dictionary:
	var counts := {}
	for slot: String in equipment:
		var arm: Dictionary = (equipment[slot] as Dictionary).get("arm", {})
		if String(arm.get("set", "")) != "":
			counts[arm["set"]] = int(counts.get(arm["set"], 0)) + 1
	return counts


# The bonus of every set step reached by the worn pieces.
static func set_bonus(items: RefCounted, counts: Dictionary) -> Dictionary:
	var out := {}
	var sets: Dictionary = items.armour.get("sets", {})
	for set_id: String in counts:
		if not sets.has(set_id):
			continue
		for need: String in sets[set_id]["bonus"]:
			if int(counts[set_id]) >= int(need):
				var step: Dictionary = sets[set_id]["bonus"][need]
				for key: String in step:
					out[key] = float(out.get(key, 0.0)) + float(step[key])
	return out


# "Epic Tidecaller Iron Helm": tier word (from data/gun_loot.json, passed in), set, item.
static func display_name(items: RefCounted, stack: Dictionary, tier_name: String) -> String:
	var arm: Dictionary = stack.get("arm", {})
	var base: String = items.item_name(String(stack["id"]))
	if arm.is_empty():
		return base
	var set_id := String(arm.get("set", ""))
	var set_word := (String(items.armour["sets"][set_id]["name"]) + " ") if set_id != "" else ""
	return "%s %s%s" % [tier_name, set_word, base]


# The stat lines of a stack: defense, block, resists, abilities (as the plain item says), then the rolls.
static func lines(items: RefCounted, stack: Dictionary) -> Array[String]:
	var arm: Dictionary = stack.get("arm", {})
	var out: Array[String] = items.stat_lines(String(stack["id"]))
	if arm.is_empty():
		return out
	var p := piece(items, stack)
	for i in out.size():
		if out[i].begins_with("Defense "):
			out[i] = "Defense %d" % roundi(float(p["defense"]))
	var cfg: Dictionary = items.armour
	for roll: String in arm["rolls"]:
		var def: Dictionary = cfg["rolls"][roll]
		var value := lerpf(float(def["min"]), float(def["max"]), float(arm["rolls"][roll]))
		out.append(String(def["desc"]) % _shown(value * (100.0 if SHARES.has(String(def["stat"])) else 1.0)))
	return out


# The set's lines for a card: [text, reached?] (the name line first, then each step).
static func set_lines(items: RefCounted, set_id: String, worn: int) -> Array:
	var sets: Dictionary = items.armour.get("sets", {})
	if not sets.has(set_id):
		return []
	var out: Array = [["%s set (%d worn)" % [String(sets[set_id]["name"]), worn], true]]
	for need: String in sets[set_id]["bonus"]:
		var words: PackedStringArray = []
		var step: Dictionary = sets[set_id]["bonus"][need]
		for key: String in step:
			words.append(bonus_text(key, float(step[key])))
		out.append(["%s pieces: %s" % [need, ", ".join(words)], worn >= int(need)])
	return out


static func bonus_text(key: String, value: float) -> String:
	var words := {"health_pct": "max health", "speed_pct": "move speed", "reload_pct": "reload speed", "cooldown_pct": "skill cooldowns",
		"damage_pct": "gun damage", "defense_pct": "defense", "block": "block chance", "fire": "fire resist", "ice": "ice resist", "toxic": "toxic resist"}
	return "+%s%% %s" % [_shown(value * (100.0 if SHARES.has(key) else 1.0)), String(words.get(key, key))]


static func _shown(value: float) -> String:
	return ("%.1f" % value) if value < 10.0 else ("%d" % roundi(value))
