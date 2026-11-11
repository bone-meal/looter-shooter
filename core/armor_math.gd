# Purpose: pure armor rules: adds up equipped items into totals, and turns an incoming hit into the damage actually taken.
# Dependencies: core/item_db.gd, core/inventory_state.gd (equipment dictionary). Numbers live in data/items.json.
extends RefCounted

const ELEMENTS := ["fire", "ice", "toxic"]
const MAX_BLOCK := 0.6
const MAX_RESIST := 0.75
const DEFENSE_SCALE := 100.0  # damage multiplier = scale / (scale + defense)


# Returns {"defense": float, "block": float, "resist": {element: float}, "abilities": Array[String]} for the equipped items.
static func totals(inventory: RefCounted, db: RefCounted) -> Dictionary:
	var out := {"defense": 0.0, "block": 0.0, "resist": {"fire": 0.0, "ice": 0.0, "toxic": 0.0}, "abilities": []}
	for slot in inventory.equipment:
		var stack: Dictionary = inventory.equipment[slot]
		if stack.is_empty():
			continue
		var s: Dictionary = db.stats(stack["id"])
		out["defense"] += float(s.get("defense", 0))
		out["block"] += float(s.get("block", 0))
		for e in ELEMENTS:
			out["resist"][e] += float(s.get("resist", {}).get(e, 0.0))
		if String(s.get("ability", "")) != "":
			out["abilities"].append(String(s["ability"]))
	out["block"] = minf(out["block"], MAX_BLOCK)
	for e in ELEMENTS:
		out["resist"][e] = minf(out["resist"][e], MAX_RESIST)
	return out


# Damage taken after armor (`worn` = result of totals()). `roll` is a random 0..1 (block if below the block chance). Returns 0 when blocked.
static func incoming(damage: float, element: String, worn: Dictionary, roll: float) -> float:
	if roll < float(worn["block"]):
		return 0.0
	var taken := damage * DEFENSE_SCALE / (DEFENSE_SCALE + float(worn["defense"]))
	if worn["resist"].has(element):
		taken *= 1.0 - float(worn["resist"][element])
	return taken
