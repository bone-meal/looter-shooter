# Purpose: developer check of rolled armour (sea step 1f; core/armour_gen.gd, core/armour_stats.gd, core/armor_math.gd,
# data/items.json armour_loot): pieces roll by tier, the host refuses made-up ones, defense grows with item level and
# tier, rolls and set steps add to the totals, pieces keep their roll through the bag, gear, saves, trades and the join
# check. Log tools/armour_check.log (ARMOUR_CHECK_DONE problems=n).
# Dependencies: core/armour_gen.gd, core/armour_stats.gd, core/armor_math.gd, core/item_db.gd, core/inventory_state.gd,
# core/join_check.gd, core/trade_desk.gd, core/gun_gen.gd, core/gun_db.gd, the item and gun data files.
extends Node

const ArmourGen = preload("res://core/armour_gen.gd")
const ArmourStats = preload("res://core/armour_stats.gd")
const ArmorMath = preload("res://core/armor_math.gd")
const ItemDb = preload("res://core/item_db.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const JoinCheck = preload("res://core/join_check.gd")
const TradeDesk = preload("res://core/trade_desk.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunDb = preload("res://core/gun_db.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var items := ItemDb.new(_json("items"))
	var gun_db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var cfg: Dictionary = items.armour
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# --- rolling
	var all_ok := true
	for tier: String in cfg["tiers"]:
		for i in 40:
			var p := ArmourGen.generate(items, rng, tier, rng.randi_range(1, 70))
			var arm: Dictionary = p["arm"]
			if ArmourGen.validate(items, String(p["id"]), arm) != "" or (arm["rolls"] as Dictionary).size() != int(cfg["tiers"][tier]["rolls"]):
				all_ok = false
	_say("320 rolled pieces over every tier are legal with the tier's number of rolls", all_ok)
	_say("every gun tier has an armour tier", gun_db.tiers.all(func(t: Dictionary) -> bool: return (cfg["tiers"] as Dictionary).has(String(t["id"]))))
	var sets_seen := {}
	for i in 400:
		var p := ArmourGen.generate(items, rng, "pony", 15)
		sets_seen[String(p["arm"]["set"])] = true
	_say("item level 15 rolls the region-2 set (Bogwalker) or none", sets_seen.keys().all(func(s: String) -> bool: return s == "" or s == "bogwalker") and sets_seen.has("bogwalker"))
	_say("levels 61-70 give the Maelstrom set", ArmourGen.set_for_level(cfg, 64) == "maelstrom" and ArmourGen.set_for_level(cfg, 1) == "tidecaller")
	var plain := ArmourGen.generate(items, rng, "purple", 21, "iron_helm", "")
	_say("a chosen item, no set", String(plain["id"]) == "iron_helm" and String(plain["arm"]["set"]) == "")
	_say("the holster variant rolls too", items.rollable("iron_breastplate+holster") or items.rollable(_first_variant(items)))
	_say("cigarettes and the treasure never roll", not items.rollable("cigarette") and not items.rollable("phoons_treasure"))
	# --- refusing made-up pieces
	var good: Dictionary = (ArmourGen.generate(items, rng, "orange", 30, "iron_helm", "auto")["arm"] as Dictionary)
	var cases := {"a roll above the tier's best": func(a: Dictionary) -> void: a["rolls"][a["rolls"].keys()[0]] = 1.5,
		"an unknown roll": func(a: Dictionary) -> void: a["rolls"] = {"godmode": 0.9, "might": 0.8, "focus": 0.8},
		"one roll too many": func(a: Dictionary) -> void: a["rolls"][_missing_roll(a)] = 0.9,
		"level 99": func(a: Dictionary) -> void: a["lvl"] = 99,
		"level 12.5": func(a: Dictionary) -> void: a["lvl"] = 12.5,
		"an extra field": func(a: Dictionary) -> void: a["owner"] = "me",
		"an unknown set": func(a: Dictionary) -> void: a["set"] = "gold_plated",
		"an unknown tier": func(a: Dictionary) -> void: a["tier"] = "mega"}
	for what: String in cases:
		var bad := good.duplicate(true)
		(cases[what] as Callable).call(bad)
		_say("refused: %s (%s)" % [what, ArmourGen.validate(items, "iron_helm", bad)], ArmourGen.validate(items, "iron_helm", bad) != "")
	_say("refused: a roll on a cigarette", ArmourGen.validate(items, "cigarette", good) != "")
	var as_json: Variant = JSON.parse_string(JSON.stringify(good))
	_say("a piece read back from JSON (numbers as floats) is still legal", ArmourGen.validate(items, "iron_helm", as_json) == "")
	# --- numbers
	var base_def := float(items.stats("iron_helm")["defense"])
	var grey1 := ArmourStats.piece(items, {"id": "iron_helm", "count": 1, "arm": {"v": 1, "tier": "grey", "lvl": 1, "rolls": {}, "set": ""}})
	var p21 := ArmourStats.piece(items, plain)
	var want := base_def * pow(float(cfg["defense_growth"]), 20.0) * float(cfg["tiers"]["purple"]["defense"])
	_say("grey level 1 = the item's own defense (%.1f)" % float(grey1["defense"]), absf(float(grey1["defense"]) - base_def) < 0.001)
	_say("purple level 21 defense = base x growth^20 x 1.25 (%.1f)" % float(p21["defense"]), absf(float(p21["defense"]) - want) < 0.01)
	var lines := ArmourStats.lines(items, plain)
	_say("card lines: %s" % " | ".join(lines), lines.size() == 1 + 2 and lines[0].begins_with("Defense "))
	_say("name: %s" % ArmourStats.display_name(items, {"id": "iron_helm", "count": 1, "arm": good}, "Mythic"), ArmourStats.display_name(items, {"id": "iron_helm", "count": 1, "arm": good}, "Mythic").begins_with("Mythic "))
	# --- totals: rolls, set steps, caps
	var inv := InventoryState.new(items)
	var slots := ["hat", "head", "earrings", "necklace"]
	var bases := _bases_for(items, slots)
	for i in slots.size():
		var piece := ArmourGen.generate(items, rng, "rainbow", 5, bases[i], "tidecaller")
		piece["arm"]["rolls"] = {"might": 1.0, "vitality": 1.0, "deflect": 1.0}
		inv.equipment[slots[i]] = piece
	var worn := ArmorMath.totals(inv, items)
	var bonus: Dictionary = worn["bonus"]
	_say("4 Tidecaller pieces: set counted 4 (%s)" % str(worn["sets"]), int((worn["sets"] as Dictionary).get("tidecaller", 0)) == 4)
	_say("might x4 = +48 %% damage (%.0f)" % float(bonus.get("damage_pct", 0)), absf(float(bonus.get("damage_pct", 0)) - 48.0) < 0.01)
	_say("vitality x4 + set 4 = 60 + 10 %% health (%.0f)" % float(bonus.get("health_pct", 0)), absf(float(bonus.get("health_pct", 0)) - 70.0) < 0.01)
	_say("set 2 speed + set 4 reload (%.0f / %.0f)" % [float(bonus.get("speed_pct", 0)), float(bonus.get("reload_pct", 0))], absf(float(bonus.get("speed_pct", 0)) - 8.0) < 0.01 and absf(float(bonus.get("reload_pct", 0)) - 15.0) < 0.01)
	_say("block from 4 deflect rolls is 0.16 plus the items' own, under the cap (%.2f)" % float(worn["block"]), float(worn["block"]) >= 0.16 - 0.001 and float(worn["block"]) <= ArmorMath.MAX_BLOCK)
	inv.equipment["necklace"] = {}
	inv.equipment["earrings"] = {}
	var two := ArmorMath.totals(inv, items)
	_say("2 pieces: only the 2-piece step (reload %.0f, speed %.0f)" % [float(two["bonus"].get("reload_pct", 0)), float(two["bonus"].get("speed_pct", 0))], float(two["bonus"].get("reload_pct", 0)) == 0.0 and float(two["bonus"].get("speed_pct", 0)) == 8.0)
	# --- the bag, gear, saves
	var bag := InventoryState.new(items)
	var helm := ArmourGen.generate(items, rng, "gold", 12, "iron_helm", "")
	_say("add_armour puts it in the backpack with its roll", bag.add_armour(helm) and bag.arm_at(0) == helm["arm"])
	bag.right_click_slot(0)
	_say("right click picks the whole piece up (roll kept)", bag.cursor.get("arm", {}) == helm["arm"] and bag.item_id(0) == "")
	bag.click_equipment("head")
	_say("worn: the head slot keeps the roll", (bag.equipment["head"] as Dictionary).get("arm", {}) == helm["arm"] and bag.cursor.is_empty())
	var second := ArmourGen.generate(items, rng, "blue", 3, "iron_helm", "")
	bag.add_armour(second)
	bag.click_slot(0)
	bag.click_equipment("head")
	_say("swapping: the new one is worn, the old one on the cursor, both with their rolls", (bag.equipment["head"] as Dictionary).get("arm", {}) == second["arm"] and bag.cursor.get("arm", {}) == helm["arm"])
	bag.return_cursor()
	_say("return_cursor puts the old one back with its roll", bag.cursor.is_empty() and bag.arm_at(0) == helm["arm"])
	bag.add("iron_helm", 1)  # a plain one of the same item: must not merge with the rolled one
	_say("a plain piece of the same item stays separate", bag.item_id(1) == "iron_helm" and bag.arm_at(1).is_empty())
	var saved: Variant = JSON.parse_string(JSON.stringify(bag.to_dict()))
	var back := InventoryState.new(items)
	back.from_dict(saved)
	_say("a JSON save brings back the bag piece and the worn piece with their rolls", ArmourGen.validate(items, "iron_helm", back.arm_at(0)) == "" and int(back.arm_at(0)["lvl"]) == 12 and int(((back.equipment["head"] as Dictionary).get("arm", {}) as Dictionary).get("lvl", 0)) == 3)
	var forged: Dictionary = saved
	(forged["slots"][0][2] as Dictionary)["rolls"] = {"might": 9.0, "vitality": 1.0}
	var cheat := InventoryState.new(items)
	cheat.from_dict(forged)
	_say("a forged roll in a save is dropped on load", cheat.item_id(0) == "")
	# --- join check (also guns and rings, which it refused before)
	var join_inv := InventoryState.new(items)
	join_inv.set_gun_db(gun_db)
	join_inv.add_gun(GunGen.generate(gun_db, rng, 0.0, "ak47", "purple", "", 5))
	join_inv.add_gun(GunGen.generate(gun_db, rng, 0.0, "m16", "blue", "", 5))
	join_inv.add_gun(GunGen.generate(gun_db, rng, 0.0, "m16", "blue", "", 5))  # backpack
	join_inv.add_armour(ArmourGen.generate(items, rng, "orange", 20))
	join_inv.equipment["head"] = ArmourGen.generate(items, rng, "purple", 8, "iron_helm")
	var ring := _bases_for(items, ["ring"])[0]
	if ring != "":
		join_inv.equipment["ring_1"] = {"id": ring, "count": 1}
	var profile := {"name": "Tester", "inv": JSON.parse_string(JSON.stringify(join_inv.to_dict()))}
	_ints(profile["inv"])
	_say("join check passes rolled guns, rolled armour (bag + worn) and a ring (%s)" % JoinCheck.check(profile, items), JoinCheck.check(profile, items) == "")
	((profile["inv"]["equipment"] as Dictionary)["head"][2] as Dictionary)["lvl"] = 500
	_say("join check refuses a worn piece of level 500", JoinCheck.check(profile, items) != "")
	# --- trade
	var desk := TradeDesk.new()
	var cleaned: Dictionary = desk.call("_clean", {"ref": 3, "id": "iron_helm", "arm": helm["arm"], "extra": 1})
	_say("a traded piece keeps its roll and nothing else rides along", cleaned.get("arm", {}) == helm["arm"] and not cleaned.has("extra"))
	_finish()


func _missing_roll(a: Dictionary) -> String:
	for id: String in ["might", "focus", "vitality", "deflect"]:
		if not (a["rolls"] as Dictionary).has(id):
			return id
	return "nimble"


func _first_variant(items: RefCounted) -> String:
	for id: String in items.ids_of_kind("armor"):
		if id.contains("+"):
			return id
	return ""


func _bases_for(items: RefCounted, slots: Array) -> Array[String]:
	var out: Array[String] = []
	for slot: String in slots:
		var found := ""
		for id: String in items.armour_drops():
			if String(items.equip_slot(id)) == slot:
				found = id
				break
		out.append(found)
	return out


# What travels over the network keeps whole numbers as ints (the join check wants int counts).
func _ints(inv: Dictionary) -> void:
	for key: String in ["slots", "holsters"]:
		for entry: Variant in inv[key]:
			if entry is Array and entry.size() >= 2:
				entry[1] = int(entry[1])
	inv["version"] = int(inv["version"])


func _json(file: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % file))


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("ARMOUR_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/armour_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
