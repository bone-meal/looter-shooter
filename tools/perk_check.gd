# Purpose: developer check of the perks and the power switch: data/perks.json is whole (15 perks, each with a machine
# on flat ground clear of everything else, the dearer ones on the farther islands), the limit, the boss's free perk,
# losing them, their numbers; the power's parts and switch. Log tools/perk_check.log (ends PERK_CHECK_DONE problems=n).
# Dependencies: core/perk_state.gd, core/power_state.gd, core/archipelago.gd, core/data_store.gd.
extends Node

const PerkState = preload("res://core/perk_state.gd")
const PowerState = preload("res://core/power_state.gd")
const Archipelago = preload("res://core/archipelago.gd")
const DataStore = preload("res://core/data_store.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var land := Archipelago.new(DataStore.load_json("res://data/archipelago.json"))
	var cfg: Dictionary = DataStore.load_json("res://data/perks.json")
	var perks := PerkState.new(cfg)
	var spots: Array[Vector2] = []
	var data_fine := perks.ids().size() == 15 and perks.limit() == 6
	var dearest_by_island := {}
	for id: String in perks.ids():
		var entry: Dictionary = cfg["perks"][id]
		var spot := land.on_island(String(entry["island"]), entry["at"])
		data_fine = data_fine and perks.price(id) > 0 and perks.name_of(id) != "" and perks.desc(id) != "" and is_zero_approx(land.height_at(spot.x, spot.y))
		for other: Vector2 in spots:
			data_fine = data_fine and spot.distance_to(other) > 4.0
		for board: Dictionary in land.wall_buys:
			data_fine = data_fine and spot.distance_to(board["at"]) > 4.0
		for hut: Dictionary in land.shelters:
			data_fine = data_fine and spot.distance_to(hut["at"]) > 7.0
		spots.append(spot)
		var isle := land.index_of(String(entry["island"]))
		dearest_by_island[isle] = maxi(int(dearest_by_island.get(isle, 0)), perks.price(id))
	var rising := true
	for isle in range(1, land.islands.size()):
		rising = rising and int(dearest_by_island.get(isle, 0)) >= int(dearest_by_island.get(isle - 1, 0))
	_say("15 perks, limit 6, every machine on flat ground clear of the others, boards and huts; the farther the island the dearer its perks", data_fine and rising)

	_say("nothing carried: numbers fall back", is_equal_approx(perks.num("max_health", 100.0), 100.0) and perks.refusal("iron_gut") == "")
	perks.add("iron_gut")
	perks.add("quickhands")
	_say("Iron Gut and Quickhands carried: health %d, reload x%.2f; the same one is not sold twice" % [int(perks.num("max_health", 100.0)), perks.num("reload_time_mult", 1.0)],
		is_equal_approx(perks.num("max_health", 100.0), 250.0) and is_equal_approx(perks.num("reload_time_mult", 1.0), 0.5) and perks.refusal("iron_gut") == "owned" and not perks.add("iron_gut"))
	for id: String in ["hair_trigger", "trade_winds", "steady_hand", "deep_pockets"]:
		perks.add(id)
	var stamp := perks.stamp
	_say("six carried: the seventh is refused", perks.owned.size() == 6 and perks.refusal("cold_blood") == "limit" and not perks.add("cold_blood") and perks.stamp == stamp)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var free := perks.give_random(rng)
	_say("the boss's power-up gives a seventh that was not carried (%s)" % free, perks.owned.size() == 7 and perks.known(free) and perks.stamp == stamp + 1)
	for _n in 20:
		perks.give_random(rng)
	_say("... until all fifteen are carried, then nothing more", perks.owned.size() == 15 and perks.give_random(rng) == "")
	perks.clear()
	_say("going down: all gone", perks.owned.is_empty() and is_equal_approx(perks.num("max_health", 100.0), 100.0))

	var power_cfg: Dictionary = DataStore.load_json("res://data/power.json")
	var power := PowerState.new(power_cfg)
	var parts_fine := (power_cfg["parts"] as Array).size() == 3
	for part: Dictionary in power_cfg["parts"]:
		var spot := land.on_island(String(part["island"]), part["at"])
		parts_fine = parts_fine and is_zero_approx(land.height_at(spot.x, spot.y)) and land.island_near(spot.x, spot.y) == 0
	var bench := land.on_island(String(power_cfg["bench"]["island"]), power_cfg["bench"]["at"])
	_say("three parts on the spawn island, the workbench on the second island", parts_fine and land.island_near(bench.x, bench.y) == 1 and is_zero_approx(land.height_at(bench.x, bench.y)))
	_say("no part, no power", not power.switch_on() and not power.on and power.found_count() == 0)
	power.take(0)
	power.take(2)
	_say("two of three found: still no power; a part is not found twice", not power.switch_on() and not power.take(2) and power.found_count() == 2)
	power.take(1)
	_say("all three: the switch goes on, once", power.switch_on() and power.on and not power.switch_on())
	var bits := power.to_bits()
	var copy := PowerState.new(power_cfg)
	copy.set_bits(bits)
	_say("the state travels as one number (%d)" % bits, copy.on and copy.all_found() and bits == 15)
	power.reset()
	_say("game over: dark, the parts lie there again", not power.on and power.found_count() == 0 and power.to_bits() == 0)

	_lines.append("PERK_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/perk_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
