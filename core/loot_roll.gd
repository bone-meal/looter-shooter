# Purpose: pure loot rolling: turns a loot table (list of entries) into drops. The host will run this later; clients never do.
# Dependencies: none. Tables come from data/loot_tables.json.
extends RefCounted


# Entry: {"chance": 0..1, "min": int, "max": int} plus either "item": id, or "pick_one": [{"item": id, "weight": n}, ...].
# Returns [{"id": String, "count": int}, ...].
static func roll(table: Array, rng: RandomNumberGenerator) -> Array:
	var drops: Array = []
	for entry in table:
		if rng.randf() > float(entry["chance"]):
			continue
		var id := String(entry["item"]) if entry.has("item") else _pick(entry["pick_one"], rng)
		drops.append({"id": id, "count": rng.randi_range(int(entry["min"]), int(entry["max"]))})
	return drops


static func _pick(options: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for o in options:
		total += float(o["weight"])
	var pick := rng.randf() * total
	for o in options:
		pick -= float(o["weight"])
		if pick <= 0.0:
			return String(o["item"])
	return String(options[options.size() - 1]["item"])
