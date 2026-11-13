# Purpose: developer check of the colosseum's rules (core/colosseum_rules.gd with data/colosseum.json, data/waves.json,
# data/gun_loot.json, data/items.json): tickets, tougher waves, the loot by wave, the last boss, the chest, armour
# drops and their variant with a holster, the modifiers. Log tools/colosseum_check.log (ends COLOSSEUM_CHECK_DONE problems=n).
# Dependencies: core/colosseum_rules.gd, core/wave_state.gd, core/item_db.gd, core/data_store.gd.
extends Node

const ColosseumRules = preload("res://core/colosseum_rules.gd")
const WaveState = preload("res://core/wave_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const CigaretteState = preload("res://core/cigarette_state.gd")
const DataStore = preload("res://core/data_store.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var rules := ColosseumRules.new(DataStore.load_json("res://data/colosseum.json"))
	var waves: Dictionary = DataStore.load_json("res://data/waves.json")
	var tiers: Array = []
	for tier: Dictionary in DataStore.load_json("res://data/gun_loot.json")["tiers"]:
		tiers.append(String(tier["id"]))
	var wrong := rules.problems((waves["waves"] as Array).size(), tiers)
	_say("the colosseum data is sound%s" % ("" if wrong.is_empty() else ": " + "; ".join(wrong)), wrong.is_empty())
	var ends_on_boss := true
	var told := PackedStringArray()
	for i in rules.ticket_count():
		var entry: Dictionary = rules.ticket(i)
		var last: Dictionary = (waves["waves"] as Array)[int(entry["waves"]) - 1]
		var boss := false
		for id: String in last:
			boss = boss or id.begins_with("boss")
		ends_on_boss = ends_on_boss and boss
		told.append("%d waves %d points" % [int(entry["waves"]), int(entry["price"])])
	_say("three tickets (%s), each ending on a boss wave" % ", ".join(told), rules.ticket_count() == 3 and ends_on_boss)
	var short := WaveState.new(waves, 4)
	_say("a 4-wave ticket is the first four waves of the twelve", short.wave_count() == 4 and WaveState.new(waves).wave_count() == 12)
	var base := {"max_hp": 100.0, "damage": 10.0, "speed": 4.0, "size": [1, 2, 1]}
	var late: Dictionary = rules.wave_stats(base, 12)
	_say("wave 1 is as written; wave 12: health x%.2f, damage x%.2f, speed x%.2f; the data is untouched" % [float(late["max_hp"]) / 100.0, float(late["damage"]) / 10.0, float(late["speed"]) / 4.0],
		rules.wave_stats(base, 1)["max_hp"] == 100.0 and float(late["max_hp"]) > 200.0 and float(late["damage"]) > 15.0 and float(late["speed"]) > 4.0 and float(base["max_hp"]) == 100.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_say("trash leaves green in waves 1-4, blue in 5-7, purple in 8-9, gold after", rules.band_tier(1) == "green" and rules.band_tier(4) == "green" and rules.band_tier(5) == "blue" and rules.band_tier(7) == "blue" and rules.band_tier(8) == "purple" and rules.band_tier(9) == "purple" and rules.band_tier(10) == "gold" and rules.band_tier(12) == "gold")
	var counts := {}
	var kills := 200000
	for _kill in kills:
		for tier: String in rules.kill_tiers(rng, 2, "trash"):
			counts[tier] = int(counts.get(tier, 0)) + 1
	var dropped := 0
	for tier: String in counts:
		dropped += int(counts[tier])
	_say("wave 2 trash: %.2f %% of kills leave a gun; %.1f %% of those are blue, the rest green, nothing else" % [100.0 * float(dropped) / float(kills), 100.0 * float(counts.get("blue", 0)) / float(maxi(dropped, 1))],
		absf(float(dropped) / float(kills) - 0.03) < 0.003 and counts.size() == 2 and absf(float(counts.get("blue", 0)) / float(dropped) - 0.01) < 0.008)
	_say("an elite always leaves one gun of its wave's tier or one better", rules.kill_tiers(rng, 6, "elite").size() == 1 and ["blue", "purple"].has(rules.kill_tiers(rng, 6, "elite")[0]))
	_say("a boss leaves one tier above its wave: blue in wave 4, purple in 6, gold in 8, orange in 10 and 11", rules.kill_tiers(rng, 4, "boss") == (["blue"] as Array[String]) and rules.kill_tiers(rng, 6, "boss") == (["purple"] as Array[String]) and rules.kill_tiers(rng, 8, "boss") == (["gold"] as Array[String]) and rules.kill_tiers(rng, 10, "boss") == (["orange"] as Array[String]) and rules.kill_tiers(rng, 11, "boss") == (["orange"] as Array[String]))
	var last_boss := {}
	var three := true
	for _run in 20000:
		var got := rules.kill_tiers(rng, 12, "boss")
		three = three and got.size() == 3
		for tier: String in got:
			last_boss[tier] = int(last_boss.get(tier, 0)) + 1
	_say("the wave-12 boss leaves three guns: orange %.0f %%, rainbow %.0f %%, pony %.0f %%" % [float(last_boss.get("orange", 0)) / 600.0, float(last_boss.get("rainbow", 0)) / 600.0, float(last_boss.get("pony", 0)) / 600.0],
		three and last_boss.size() == 3 and absf(float(last_boss["orange"]) / 60000.0 - 0.6) < 0.02 and absf(float(last_boss["pony"]) / 60000.0 - 0.1) < 0.01)
	var pony_elsewhere := false
	for wave in range(1, 13):
		for kind: String in ["trash", "elite", "boss"]:
			if wave == 12 and kind == "boss":
				continue
			for _roll in 2000:
				pony_elsewhere = pony_elsewhere or rules.kill_tiers(rng, wave, kind, 5.0).has("pony") or rules.kill_tiers(rng, wave, kind, 5.0).has("grey")
	_say("no pony from anything but that boss, and no grey anywhere, even with five times the luck", not pony_elsewhere)
	_say("the chest: two blue after 4 waves, two gold after 8, two orange after 12", rules.chest_tiers(4) == (["blue", "blue"] as Array[String]) and rules.chest_tiers(8) == (["gold", "gold"] as Array[String]) and rules.chest_tiers(12) == (["orange", "orange"] as Array[String]))
	var treasures := 0
	for _run in 20000:
		treasures += 1 if rules.treasure(rng, 12, "boss") != "" else 0
	_say("Phoon's Treasure: from the wave-12 boss %.1f %% of the time, from nothing else" % (float(treasures) / 200.0), absf(float(treasures) / 20000.0 - float(rules.cfg["loot"]["final_boss"]["treasure_chance"])) < 0.01 and rules.treasure(rng, 11, "boss", 100.0) == "" and rules.treasure(rng, 12, "trash", 100.0) == "" and rules.treasure(rng, 12, "boss", 100.0) == "phoons_treasure")

	var items := ItemDb.new(DataStore.load_json("res://data/items.json"))
	var pool := items.armour_drops()
	_say("%d armour pieces can drop; not the cigarette, not Phoon's Treasure, not a variant" % pool.size(), pool.size() >= 10 and not pool.has("cigarette") and not pool.has("phoons_treasure") and not pool.has("steel_chestplate+holster"))
	_say("a chestplate also exists with a holster (one more ready gun slot); boots do not", items.has_item("steel_chestplate+holster") and String(items.stats("steel_chestplate+holster")["ability"]) == "extra_holster" and items.equip_slot("steel_chestplate+holster") == "chestplate" and items.item_name("steel_chestplate+holster") != items.item_name("steel_chestplate") and items.stat_lines("steel_chestplate+holster").has("One more ready gun slot") and not items.has_item("work_boots+holster") and not items.has_item("cigarette+holster"))
	var armour := 0
	var with_slot := 0
	for _kill in 200000:
		if rules.armour_drops(rng, "trash"):
			armour += 1
			with_slot += 1 if rules.armour_has_slot(rng) else 0
	_say("armour from %.2f %% of ordinary kills; %.0f %% of it has the holster" % [float(armour) / 2000.0, 100.0 * float(with_slot) / float(maxi(armour, 1))], absf(float(armour) / 200000.0 - 0.01) < 0.002 and absf(float(with_slot) / float(armour) - 0.08) < 0.03)

	var mods: Array = rules.modifiers()
	var sound := mods.size() == 22
	var seen := {}
	var every := PackedStringArray()
	for mod: Dictionary in mods:
		sound = sound and not seen.has(mod["id"]) and String(mod["name"]) != "" and String(mod["desc"]) != "" and float(mod["loot"]) > 0.0 and not (mod["effects"] as Dictionary).is_empty()
		seen[mod["id"]] = true
		every.append(String(mod["id"]))
	_say("22 modifiers, each with a name, what it does, a loot share and an effect", sound)
	_say("no modifier: a plain run (loot x1, no effects); all 22: loot x%.2f" % rules.loot_mult(every), rules.loot_mult(PackedStringArray()) == 1.0 and rules.effects(PackedStringArray()).is_empty() and rules.loot_mult(every) > 4.0)
	var fx := rules.effects(PackedStringArray(["thick_hides", "heavy_hitters", "quick_feet", "twin_bosses", "packed_house"]))
	var hard: Dictionary = rules.wave_stats(base, 1, fx)
	_say("Thick Hides, Heavy Hitters, Quick Feet: wave 1 health x1.5, damage x1.5, speed x1.3", is_equal_approx(float(hard["max_hp"]), 150.0) and is_equal_approx(float(hard["damage"]), 15.0) and is_equal_approx(float(hard["speed"]), 5.2))
	var plain_run := rules.run_waves(waves["waves"], 4)
	var full_run := rules.run_waves(waves["waves"], 4, fx)
	_say("Twin Bosses and Packed House: wave 4 has %d bosses and %d chasers instead of %d and %d; wave 1 %d chasers instead of %d" % [int(full_run[3]["boss"]), int(full_run[3]["chaser"]), int(plain_run[3]["boss"]), int(plain_run[3]["chaser"]), int(full_run[0]["chaser"]), int(plain_run[0]["chaser"])],
		plain_run.size() == 4 and int(plain_run[3]["boss"]) == 1 and int(full_run[3]["boss"]) == 2 and int(full_run[3]["chaser"]) == 6 and int(full_run[0]["chaser"]) == 5 and int((waves["waves"] as Array)[0]["chaser"]) == 3)
	_say("the chest of a 12-wave run with every modifier holds %d guns" % rules.chest_tiers(12, every).size(), rules.chest_tiers(12, every).size() == 2 + floori(rules.loot_mult(every) - 1.0) and rules.chest_tiers(12).size() == 2)
	var all_fx := rules.effects(every)
	var keys_there := true
	for key: String in ["enemy_health", "enemy_damage", "enemy_speed", "death_blast_radius", "death_blast_damage", "all_elite", "player_health", "ammo_start", "fog", "hide_bars", "boss_count", "enemy_count", "no_heal", "wave_seconds", "late_pack", "boss_body_damage", "vampire", "wave_delay", "blackout", "ring_start", "ring_end", "ring_dps", "still_seconds", "still_element", "berserk_below", "berserk_mult", "blind", "reload_time", "jump_fatigue", "no_sprint"]:
		keys_there = keys_there and all_fx.has(key)
	_say("every effect the game reads is given by some modifier (%d keys)" % all_fx.size(), keys_there and all_fx.size() == 30)

	# --- the cigarette (core/cigarette_state.gd with data/cigarette.json) ---
	var smoke := CigaretteState.new()
	smoke.setup(DataStore.load_json("res://data/cigarette.json"))
	_say("a cigarette burns %d minutes; the burnt one is an item that exists, has no ability and stacks like cigarettes" % roundi(smoke.full() / 60.0), is_equal_approx(smoke.full(), 1800.0) and items.has_item("cigarette_butt") and not items.stats("cigarette_butt").has("ability") and items.stack_max("cigarette") > 1 and items.equip_slot("cigarette_butt") == "mouth")
	smoke.light()
	var burnt_early := smoke.tick(600.0, true)
	var idle_left := smoke.left
	smoke.tick(5000.0, false)
	_say("lit: full; 10 burning minutes leave 20; time off the gun side burns nothing", not burnt_early and is_equal_approx(idle_left, 1200.0) and is_equal_approx(smoke.left, 1200.0))
	smoke.light()
	_say("putting one back on goes on from where it was (no free refill)", is_equal_approx(smoke.left, 1200.0))
	var out := smoke.tick(1199.0, true) == false and smoke.warning() and smoke.tick(5.0, true)
	smoke.light()
	_say("it warns near the end, burns out once, and only then the next one starts full", out and is_equal_approx(smoke.left, 1800.0))
	_say("reward chests: one cigarette after 4 or 8 waves, two after 12", smoke.chest_count(4, 12) == 1 and smoke.chest_count(8, 12) == 1 and smoke.chest_count(12, 12) == 2)

	_lines.append("COLOSSEUM_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/colosseum_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
