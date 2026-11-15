# Purpose: pure armor rules: adds up equipped items into totals, and turns an incoming hit into the damage actually taken.
# Dependencies: core/item_db.gd, core/inventory_state.gd (equipment dictionary), core/armour_stats.gd. Numbers live in data/items.json.
extends RefCounted

const ArmourStats = preload("res://core/armour_stats.gd")

const ELEMENTS := ["fire", "ice", "toxic"]
const MAX_BLOCK := 0.6
const MAX_RESIST := 0.75
const DEFENSE_SCALE := 100.0  # damage multiplier = scale / (scale + defense)


# Returns {"defense": float, "block": float, "resist": {element: float}, "abilities": Array[String], "bonus": {key: value},
# "sets": {set id: pieces}} for the equipped items. Rolled pieces count with their level, tier and rolls
# (core/armour_stats.gd), and the set steps reached add to "bonus"; defense_pct raises the defense, block / resist
# bonuses add to the item's own before the caps.
static func totals(inventory: RefCounted, db: RefCounted) -> Dictionary:
	var out := {"defense": 0.0, "block": 0.0, "resist": {"fire": 0.0, "ice": 0.0, "toxic": 0.0}, "abilities": [], "bonus": {}, "sets": {}}
	for slot in inventory.equipment:
		var stack: Dictionary = inventory.equipment[slot]
		if stack.is_empty():
			continue
		var p := ArmourStats.piece(db, stack)
		out["defense"] += float(p["defense"])
		out["block"] += float(p["block"])
		for e in ELEMENTS:
			out["resist"][e] += float(p["resist"].get(e, 0.0))
		for key: String in p["bonus"]:
			out["bonus"][key] = float(out["bonus"].get(key, 0.0)) + float(p["bonus"][key])
		var s: Dictionary = db.stats(stack["id"])
		if String(s.get("ability", "")) != "":
			out["abilities"].append(String(s["ability"]))
	out["sets"] = ArmourStats.set_counts(inventory.equipment)
	var from_sets := ArmourStats.set_bonus(db, out["sets"])
	for key: String in from_sets:
		out["bonus"][key] = float(out["bonus"].get(key, 0.0)) + float(from_sets[key])
	var bonus: Dictionary = out["bonus"]
	out["defense"] *= 1.0 + float(bonus.get("defense_pct", 0.0)) / 100.0
	out["block"] = minf(out["block"] + float(bonus.get("block", 0.0)), MAX_BLOCK)
	for e in ELEMENTS:
		out["resist"][e] = minf(out["resist"][e] + float(bonus.get(e, 0.0)), MAX_RESIST)
	return out


# Damage taken after armor (`worn` = result of totals()). `roll` is a random 0..1 (block if below the block chance). Returns 0 when blocked.
static func incoming(damage: float, element: String, worn: Dictionary, roll: float) -> float:
	if roll < float(worn["block"]):
		return 0.0
	var taken := damage * DEFENSE_SCALE / (DEFENSE_SCALE + float(worn["defense"]))
	if worn["resist"].has(element):
		taken *= 1.0 - float(worn["resist"][element])
	return taken
