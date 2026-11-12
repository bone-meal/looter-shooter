# Purpose: developer check of round 6's gun rules: ammo pools (core/ammo_pools.gd) and reloading from them
# (core/weapon_state.gd), the holsters of the inventory (core/inventory_state.gd: only guns, rounds handed back,
# saving, old saves, the host's join check), carrying speed shifted by parts (core/gun_stats.gd), the knives
# (core/knife_db.gd: 13 types, the roll) and knife attack timing (core/melee_state.gd).
# Log tools/gun_check.log (ends GUN_CHECK_DONE problems=n).
# Dependencies: the files above, core/gun_db.gd, core/gun_gen.gd, core/item_db.gd, core/join_check.gd, core/data_store.gd.
extends Node

const AmmoPools = preload("res://core/ammo_pools.gd")
const WeaponState = preload("res://core/weapon_state.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const JoinCheck = preload("res://core/join_check.gd")
const KnifeDb = preload("res://core/knife_db.gd")
const MeleeState = preload("res://core/melee_state.gd")
const DataStore = preload("res://core/data_store.gd")
const BankState = preload("res://core/bank_state.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var weapons: Dictionary = DataStore.load_json("res://data/weapons.json")["weapons"]
	var items := ItemDb.new(DataStore.load_json("res://data/items.json"))
	var gun_db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"), DataStore.load_json("res://data/gun_uniques.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 6

	# --- pools ---
	var sized := true
	var sizes := PackedStringArray()
	for body: String in weapons:
		sized = sized and int(weapons[body].get("ammo_pool", 0)) >= int(weapons[body]["mag_size"])
		sizes.append("%s %d" % [body, int(weapons[body].get("ammo_pool", 0))])
	_say("every gun body has a pool of at least one magazine: %s" % ", ".join(sizes), sized and weapons.size() == 8)
	var pools := AmmoPools.new(weapons)
	_say("a new character's pools are full", pools.left("pistol_basic") == pools.size_of("pistol_basic") and pools.is_full("m60"))
	_say("taking 30 from the AK's pool leaves the M16's alone (separate pools)", pools.take("ak47", 30) == 30 and pools.left("ak47") == pools.size_of("ak47") - 30 and pools.is_full("m16"))
	_say("rockets and grenades are separate too", pools.take("rocket_launcher", 3) == 3 and pools.is_full("grenade_launcher"))
	pools.take("pistol_basic", 90)
	_say("you cannot take more than is there: asked 20, got %d" % pools.take("pistol_basic", 20), pools.left("pistol_basic") == 0)
	_say("found ammo stops at the pool's size", pools.give("ak47", 500) == 30 and pools.is_full("ak47"))
	_say("rounds out of your own gun are never thrown away", pools.give("ak47", 7, true) == 7 and pools.left("ak47") == pools.size_of("ak47") + 7)
	var again := AmmoPools.new(weapons)
	again.from_dict(JSON.parse_string(JSON.stringify(pools.to_dict())))
	_say("saved and loaded: pistol %d, rockets %d" % [again.left("pistol_basic"), again.left("rocket_launcher")], again.left("pistol_basic") == 0 and again.left("rocket_launcher") == pools.left("rocket_launcher") and again.left("ak47") == pools.left("ak47"))
	again.from_dict({"pistol_basic": -4, "ak47": 1e9, "m16": "many"})
	_say("a save with nonsense in it: never below 0, never more than twice the pool, a broken entry = full", again.left("pistol_basic") == 0 and again.left("ak47") == again.size_of("ak47") * 2 and again.is_full("m16"))
	again.bonus_pct = 50.0
	again.fill_all()
	_say("a 50 %% bigger pool (for a later perk): pistol %d" % again.left("pistol_basic"), again.left("pistol_basic") == roundi(int(weapons["pistol_basic"]["ammo_pool"]) * 1.5))
	pools.fill_all()

	# --- reloading from a pool ---
	var pistol := WeaponState.new("pistol_basic", weapons["pistol_basic"])
	pistol.pool = pools
	pools.take("pistol_basic", pools.left("pistol_basic") - 5)  # 5 spare rounds left
	pistol.ammo = 2
	pistol.start_reload(0.0)
	pistol.update(10.0)
	_say("a reload takes what the pool has: 2 + 5 = %d in the gun, %d spare" % [pistol.ammo, pistol.spare()], pistol.ammo == 7 and pistol.spare() == 0)
	pistol.start_reload(11.0)
	_say("with nothing spare a reload does not even start", not pistol.is_reloading())
	pools.fill("pistol_basic")
	pistol.start_reload(12.0)
	pistol.cancel_reload()
	pistol.update(30.0)
	_say("putting the gun away stops the reload: still %d" % pistol.ammo, pistol.ammo == 7 and pools.is_full("pistol_basic"))
	var free := WeaponState.new("pistol_basic", weapons["pistol_basic"])
	free.ammo = 0
	free.start_reload(0.0)
	free.update(10.0)
	_say("without a pool (test scenes) a reload still fills the gun", free.ammo == free.mag_size)

	# --- holsters ---
	var bag := InventoryState.new(items)
	bag.set_gun_db(gun_db)
	bag.add("pistol_basic", 1)
	_say("the starting pistol goes into holster 1 and is fresh (it loads itself from the pool)", bag.holster_body(0) == "pistol_basic" and bag.loaded[0] == InventoryState.FRESH and bag.item_id(0) == "")
	var ak := GunGen.generate(gun_db, rng, 0.0, "ak47", "blue")
	var m60 := GunGen.generate(gun_db, rng, 0.0, "m60", "green")
	bag.add_gun(ak)
	bag.add_gun(m60)
	_say("the next gun takes holster 2, the third goes to the backpack", bag.holster_body(1) == "ak47" and bag.holster_body(2) == "" and not bag.gun_at(0).is_empty())
	bag.add("worm", 3)
	bag.click_slot(1)  # worms on the mouse
	bag.click_holster(0)
	_say("only guns go into a holster (a worm stays on the mouse)", bag.holster_body(0) == "pistol_basic" and String(bag.cursor.get("id", "")) == "worm")
	bag.click_slot(1)
	bag.loaded[1] = 21
	bag.click_slot(0)  # the M60 on the mouse
	bag.click_holster(1)  # swap with the AK
	var back := bag.take_returned()
	_say("swapping by hand: the M60 is in, empty; the AK's 21 rounds go back to its pool", bag.holster_body(1) == "m60" and bag.loaded[1] == 0 and int(back.get("ak47", 0)) == 21 and bag.body_of(bag.cursor) == "ak47")
	bag.return_cursor()
	_say("closing the window puts the gun on the mouse in the backpack, not back in a holster", bag.cursor.is_empty() and bag.holster_body(1) == "m60" and not bag.gun_at(0).is_empty())
	_say("a closed holster cannot be clicked", bag.holsters[2].is_empty() and _try_holster(bag, 2))
	bag.holster_count = 3
	bag.click_slot(0)
	bag.click_holster(2)
	bag.loaded[2] = 9
	var homeless := bag.set_holster_count(2)
	_say("a holster that closes sends its gun to the backpack and its rounds to the pool", homeless.is_empty() and bag.holster_body(2) == "" and not bag.gun_at(0).is_empty() and int(bag.take_returned().get("ak47", 0)) == 9)
	bag.loaded[0] = 4
	var saved: Dictionary = JSON.parse_string(JSON.stringify(bag.to_dict()))
	var loaded_bag := InventoryState.new(items)
	loaded_bag.set_gun_db(gun_db)
	loaded_bag.from_dict(saved)
	_say("saved and loaded: holsters %s / %s with %d and %d rounds, AK in the backpack" % [loaded_bag.holster_body(0), loaded_bag.holster_body(1), loaded_bag.loaded[0], loaded_bag.loaded[1]], loaded_bag.holster_body(0) == "pistol_basic" and loaded_bag.holster_body(1) == "m60" and loaded_bag.loaded[0] == 4 and loaded_bag.loaded[1] == 0 and String(loaded_bag.gun_at(0).get("body", "")) == "ak47" and loaded_bag.count_of("worm") == 3)
	var old_save := {"version": 3, "slots": [["worm", 2], ["sniper_basic", 1], ["gun", 1, ak], ["pistol_basic", 1], [], [], [], [], [], ["gun", 1, m60]], "equipment": {}}
	var old_bag := InventoryState.new(items)
	old_bag.set_gun_db(gun_db)
	old_bag.from_dict(JSON.parse_string(JSON.stringify(old_save)))
	_say("a save from before: the first two guns of the old hotbar are ready (%s, %s), the rest stays in the backpack" % [old_bag.holster_body(0), old_bag.holster_body(1)], old_bag.holster_body(0) == "sniper_basic" and old_bag.holster_body(1) == "ak47" and old_bag.item_id(3) == "pistol_basic" and old_bag.item_id(0) == "worm" and old_bag.item_id(1) == "" and not old_bag.gun_at(9).is_empty() and old_bag.loaded[0] == InventoryState.FRESH)
	var shown := InventoryState.new(items)  # what a joiner shows the host: no rolled guns in it
	shown.from_dict(saved)
	var profile := {"name": "Tester", "inv": shown.to_dict()}
	_say("the host accepts a profile with holsters: \"%s\"" % JoinCheck.check(profile, items), JoinCheck.check(profile, items) == "")
	var cheat: Dictionary = shown.to_dict()
	(cheat["holsters"] as Array)[1] = ["worm", 1]
	_say("... and refuses something that is no gun in a holster: \"%s\"" % JoinCheck.check({"name": "Tester", "inv": cheat}, items), JoinCheck.check({"name": "Tester", "inv": cheat}, items) != "")
	cheat = shown.to_dict()
	cheat.erase("holsters")
	_say("... and a profile without holsters (another game version)", JoinCheck.check({"name": "Tester", "inv": cheat}, items) != "")

	# --- everything carried, taken and given back (the backpack left where you go down) ---
	var carried_guns := 0
	for i in InventoryState.HOLSTERS:
		carried_guns += 1 if loaded_bag.holster_body(i) != "" else 0
	loaded_bag.loaded[0] = 7
	var bundle: Dictionary = loaded_bag.take_all()
	var gone := loaded_bag.holster_body(0) == "" and loaded_bag.holster_body(1) == "" and loaded_bag.count_of("worm") == 0 and loaded_bag.gun_at(0).is_empty()
	_say("going down: %d things leave in one bundle, nothing is left in hand or bag, the pistol's 7 rounds go back to the pool" % InventoryState.bundle_size(bundle), gone and InventoryState.bundle_size(bundle) == 4 and int(loaded_bag.take_returned().get("pistol_basic", 0)) == 7)
	loaded_bag.add("pistol_basic", 1)  # the pistol you get back
	var rest: Dictionary = loaded_bag.put_all(JSON.parse_string(JSON.stringify(bundle)))
	_say("back at the backpack: everything returns (the fresh pistol keeps holster 1, the first gun of the bundle takes holster 2, the rest goes to the bag)", InventoryState.bundle_size(rest) == 0 and loaded_bag.holster_body(0) == "pistol_basic" and loaded_bag.holster_body(1) == "pistol_basic" and String(loaded_bag.gun_at(0).get("body", "")) == "m60" and String(loaded_bag.gun_at(1).get("body", "")) == "ak47" and loaded_bag.count_of("worm") == 3)
	var full := InventoryState.new(items)
	full.set_gun_db(gun_db)
	full.add("pistol_basic", 1)
	full.add("ak47", 1)
	for i in InventoryState.SIZE:
		full.add_gun(GunGen.generate(gun_db, rng, 0.0, "m16", "green"))
	var no_room: Dictionary = full.put_all({"things": [["gun", 1, ak], ["worm", 2]]})
	_say("a full bag takes nothing: both things stay in the backpack", InventoryState.bundle_size(no_room) == 2)
	_say("nonsense instead of a bundle does nothing", InventoryState.bundle_size(full.put_all("junk")) == 0 and InventoryState.bundle_size(full.put_all({"things": [["laser", 1], 5]})) == 0)

	# --- the bank ---
	var bank_cfg: Dictionary = DataStore.load_json("res://data/bank.json")
	var bank := BankState.new(bank_cfg)
	var costs := PackedStringArray()
	var probe := BankState.new(bank_cfg)
	while not probe.next_upgrade().is_empty():
		var cost: Dictionary = probe.next_upgrade()
		costs.append("%d %s" % [int(cost.values()[0]), String(cost.keys()[0])])
		probe.upgrade()
	_say("the bank starts with %d slots and grows to %d: %s" % [bank.capacity(), probe.capacity(), ", ".join(costs)], bank.capacity() == 10 and probe.capacity() == 60 and probe.capacity() == bank.most_slots() and costs.size() == 5 and costs[0] == "25000 points" and costs[2] == "5000 coins")
	var owner_bag := InventoryState.new(items)
	owner_bag.set_gun_db(gun_db)
	owner_bag.add("pistol_basic", 1)
	owner_bag.add("ak47", 1)
	owner_bag.add_gun(m60)
	owner_bag.add("worm", 5)
	owner_bag.click_slot(0)  # the M60 on the mouse
	bank.click(3, owner_bag)
	owner_bag.click_slot(1)  # the worms
	bank.click(0, owner_bag)
	_say("a gun and a stack of worms put into the bank leave the bag", bank.used() == 2 and owner_bag.cursor.is_empty() and owner_bag.gun_at(0).is_empty() and owner_bag.count_of("worm") == 0 and String(bank.stack(3)["gun"]["body"]) == "m60")
	owner_bag.take_all()
	_say("going down takes nothing out of the bank", bank.used() == 2)
	bank.click(9 + 1, owner_bag)
	_say("a slot the bank does not have yet cannot be used", bank.used() == 2)
	bank.upgrade()
	var kept := BankState.new(bank_cfg)
	kept.from_dict(JSON.parse_string(JSON.stringify(bank.to_dict(owner_bag))), owner_bag)
	_say("saved and loaded: %d slots, the M60 and 5 worms still there" % kept.capacity(), kept.capacity() == 20 and kept.used() == 2 and int(kept.stack(0)["count"]) == 5 and String(kept.stack(3)["gun"]["body"]) == "m60")
	kept.from_dict({"level": 99, "slots": [["laser", 3], "x", ["worm", 2]]}, owner_bag)
	_say("a save with nonsense in it: no more upgrades than exist, unknown things left out", kept.capacity() == 60 and kept.used() == 1 and String(kept.stack(2)["id"]) == "worm")
	kept.click(2, owner_bag)
	_say("taking it out puts it on the mouse", String(owner_bag.cursor.get("id", "")) == "worm" and kept.used() == 0)

	# --- parts shift the carrying speed ---
	var parts: Dictionary = DataStore.load_json("res://data/gun_parts.json")["parts"]
	var slowest := 0.0
	var fastest := 0.0
	for slot: String in parts:
		var low := 0.0
		var high := 0.0
		for kind: String in parts[slot]:
			var shift := float(parts[slot][kind]["mods"].get("move_speed", 0.0))
			low = minf(low, shift)
			high = maxf(high, shift)
		slowest += low
		fastest += high
	_say("parts change speed slightly: the heaviest build %.1f %%, the lightest +%.1f %%" % [slowest * 100.0, fastest * 100.0], slowest < 0.0 and slowest >= -0.15 and fastest > 0.0 and fastest <= 0.08)
	var heavy := GunGen.generate(gun_db, rng, 0.0, "ak47", "blue")
	(heavy["parts"] as Dictionary)["barrel"] = {"kind": "heavy", "maker": heavy["maker"]}  # (a rolled gun need not have every part)
	(heavy["parts"] as Dictionary)["mag"] = {"kind": "drum", "maker": heavy["maker"]}
	var heavy_speed := float(GunStats.final_stats(gun_db, heavy)["move_speed"])
	var plain_speed := float(weapons["ak47"]["move_speed"])
	_say("an AK with a heavy barrel and a drum: %.0f u/s instead of %.0f" % [heavy_speed, plain_speed], heavy_speed < plain_speed and heavy_speed >= plain_speed * 0.85)

	# --- knives ---
	var knives := KnifeDb.new(DataStore.load_json("res://data/knives.json"))
	var total := 0.0
	var rarest := ""
	var commonest := ""
	for id: String in knives.ids():
		total += knives.chance_pct(id)
		if rarest == "" or knives.chance_pct(id) < knives.chance_pct(rarest):
			rarest = id
		if commonest == "" or knives.chance_pct(id) > knives.chance_pct(commonest):
			commonest = id
	_say("13 knife types whose chances add up to 100 %%; rarest %s (%.1f %%), commonest %s (%.0f %%)" % [knives.name_of(rarest), knives.chance_pct(rarest), knives.name_of(commonest), knives.chance_pct(commonest)], knives.ids().size() == 13 and absf(total - 100.0) < 0.001 and rarest == "butterfly" and commonest == "combat")
	var counts := {}
	for _i in 200000:
		var got := knives.roll(rng)
		counts[got] = int(counts.get(got, 0)) + 1
	var worst := 0.0
	for id: String in knives.ids():
		worst = maxf(worst, absf(float(counts.get(id, 0)) / 2000.0 - knives.chance_pct(id)))
	_say("200 000 rolls: every type within %.2f points of its chance; butterfly knives %d (expected 400)" % [worst, int(counts.get("butterfly", 0))], worst < 0.3 and int(counts.get("butterfly", 0)) > 300 and int(counts.get("butterfly", 0)) < 500)
	_say("an unknown knife id becomes the plain combat knife", knives.known("laser_sword") == "combat" and knives.known(7) == "combat" and knives.known("karambit") == "karambit")
	var shapes_fine := true
	for id: String in knives.ids():
		shapes_fine = shapes_fine and not knives.parts(id).is_empty()
		for part: Dictionary in knives.parts(id):
			shapes_fine = shapes_fine and knives.material_ids().has(String(part["mat"])) and ["blade", "grip", "box", "ring"].has(String(part["kind"]))
	_say("every knife is built from known parts and materials", shapes_fine)
	var slash: Dictionary = knives.attack("slash")
	var stab: Dictionary = knives.attack("stab")
	_say("slash %d damage every %.2f s, stab %d every %.2f s" % [int(slash["damage"]), float(slash["interval"]), int(stab["damage"]), float(stab["interval"])], float(stab["damage"]) > float(slash["damage"]) and float(stab["interval"]) > float(slash["interval"]) and float(slash["hit_at"]) < float(slash["interval"]))
	var melee := MeleeState.new()
	_say("a slash starts, and a second one has to wait", melee.try_start("slash", slash, 1.0) and not melee.try_start("slash", slash, 1.0 + float(slash["interval"]) * 0.5))
	_say("its blow lands once, %.2f s after the click" % float(slash["hit_at"]), not melee.lands(1.0 + float(slash["hit_at"]) * 0.5) and melee.lands(1.0 + float(slash["hit_at"]) + 0.01) and not melee.lands(1.3))
	_say("after the interval the next one starts", melee.try_start("stab", stab, 1.0 + float(slash["interval"]) + 0.01) and melee.kind == "stab")
	melee.cancel()
	_say("putting the knife away mid-stab: the blow never lands", not melee.lands(99.0))

	_lines.append("GUN_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/gun_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


# Clicks a holster with an empty mouse and reports whether nothing happened.
func _try_holster(bag: InventoryState, index: int) -> bool:
	var before := bag.cursor.duplicate()
	bag.click_holster(index)
	return bag.cursor == before


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
