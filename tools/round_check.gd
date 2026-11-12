# Purpose: developer check of the island's rounds (core/round_rules.gd with data/island_rounds.json): the data is
# sound, rounds grow as designed, boss and special rounds come when they should, enemies get tougher, and a played-
# through run (enemies killed a few seconds after they come ashore) keeps to the alive cap and the pacing.
# Log tools/round_check.log (ends ROUND_CHECK_DONE problems=n).
# Dependencies: core/round_rules.gd, core/data_store.gd, core/settings_state.gd (the graphics tiers).
extends Node

const RoundRules = preload("res://core/round_rules.gd")
const DataStore = preload("res://core/data_store.gd")
const SettingsState = preload("res://core/settings_state.gd")

var _lines := PackedStringArray()
var _problems := 0
var _events := PackedStringArray()


func _ready() -> void:
	var cfg: Dictionary = DataStore.load_json("res://data/island_rounds.json")
	var arena: Dictionary = DataStore.load_json("res://data/enemies.json")["enemies"]
	var own: Dictionary = cfg["enemies"]
	var known := true
	for entry: Dictionary in cfg["mix"]:
		for id: String in entry["enemies"]:
			known = known and own.has(id)
	known = known and own.has(String(cfg["special"]["enemy"]))
	for id: String in cfg["boss"]["order"]:
		known = known and arena.has(id)
	for id: String in own:
		for key: String in ["model", "max_hp", "speed", "attack_type", "damage", "attack_range", "attack_interval", "size", "color"]:
			known = known and (own[id] as Dictionary).has(key)
		known = known and String(own[id]["attack_type"]) == "melee"
	_say("every enemy of the mix, the special round and the boss list exists, and the island's own are all melee", known)
	var tiers := true
	for tier: String in SettingsState.GRAPHICS_IDS:
		tiers = tiers and int((cfg["alive_cap"] as Dictionary).get(tier, 0)) > 0
	_say("an alive cap for every graphics tier (ultimate %d, potato %d)" % [int(cfg["alive_cap"]["ultimate"]), int(cfg["alive_cap"]["potato"])], tiers and int(cfg["alive_cap"]["ultimate"]) == 24)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rules := RoundRules.new(cfg, rng)
	_say("round 1 holds %d enemies, round 10 holds %d, round 20 holds %d" % [rules.count(1, 1), rules.count(10, 1), rules.count(20, 1)], rules.count(1, 1) == 6 and rules.count(10, 1) == 24 and rules.count(20, 1) > rules.count(10, 1))
	_say("more with more players: round 5 alone %d, with four %d" % [rules.count(5, 1), rules.count(5, 4)], rules.count(5, 4) > rules.count(5, 1))
	var kinds := PackedStringArray()
	for n in range(1, 16):
		kinds.append("%d %s" % [n, rules.kind_of(n)])
	_say("kinds: %s" % ", ".join(kinds), rules.kind_of(5) == "boss" and rules.kind_of(10) == "boss" and rules.kind_of(7) == "special" and rules.kind_of(12) == "special" and rules.kind_of(1) == "normal" and rules.kind_of(2) == "normal")
	var order: Array = cfg["boss"]["order"]
	_say("bosses in turn: round 5 %s, round 10 %s, round %d %s again and tougher" % [rules.boss_of(5), rules.boss_of(10), 5 * (order.size() + 1), rules.boss_of(5 * (order.size() + 1))], rules.boss_of(5) == String(order[0]) and rules.boss_of(10) == String(order[1]) and rules.boss_of(5 * (order.size() + 1)) == String(order[0]) and rules.boss_cycle(5) == 0 and rules.boss_cycle(5 * (order.size() + 1)) == 1)
	var first_boss: Dictionary = rules.stats_for(arena[String(order[0])], 5, true)
	var later_boss: Dictionary = rules.stats_for(arena[String(order[0])], 5 * (order.size() + 1), true)
	_say("the first boss has its ordinary %d health, the second time round %d" % [int(first_boss["max_hp"]), int(later_boss["max_hp"])], is_equal_approx(float(first_boss["max_hp"]), float(arena[String(order[0])]["max_hp"])) and float(later_boss["max_hp"]) > float(first_boss["max_hp"]))
	var boss_round := rules.roster(5, 1)
	_say("a boss round: %d enemies, the boss fourth in line" % boss_round.size(), boss_round.count(String(order[0])) == 1 and boss_round.find(String(order[0])) == 3 and boss_round.size() < rules.count(5, 1) + 1)
	var special := rules.roster(7, 1)
	_say("a special round is nothing but %s (%d of them)" % [String(cfg["special"]["enemy"]), special.size()], special.count(String(cfg["special"]["enemy"])) == special.size() and special.size() >= rules.count(7, 1))
	var early := rules.roster(1, 1)
	var late := rules.roster(12 + 1, 1)
	_say("round 1 is only the drowned; runners come from round 10 on (round 13 has %d)" % late.count("drowned_runner"), early.count("drowned") == early.size() and late.count("drowned_runner") > 0 and rules.roster(9, 1).count("drowned_runner") == 0)
	var drowned: Dictionary = own["drowned"]
	var r1: Dictionary = rules.stats_for(drowned, 1, false)
	var r10: Dictionary = rules.stats_for(drowned, 10, false)
	var r20: Dictionary = rules.stats_for(drowned, 20, false)
	var r60: Dictionary = rules.stats_for(drowned, 60, false)
	_say("the drowned: round 1 %d health / %.1f m/s / %d damage, round 10 %d / %.1f / %d, round 20 %d / %.1f / %d" % [int(r1["max_hp"]), float(r1["speed"]), int(r1["damage"]), int(r10["max_hp"]), float(r10["speed"]), int(r10["damage"]), int(r20["max_hp"]), float(r20["speed"]), int(r20["damage"])], is_equal_approx(float(r1["max_hp"]), float(drowned["max_hp"])) and float(r10["max_hp"]) > float(r1["max_hp"]) * 2.0 and float(r20["max_hp"]) > float(r10["max_hp"]) * 2.0 and float(r10["speed"]) > float(r1["speed"]) and float(r10["damage"]) > float(r1["damage"]))
	_say("speed and damage stop growing (round 60: %.1f m/s, %d damage); health never does (%d)" % [float(r60["speed"]), int(r60["damage"]), int(r60["max_hp"])], is_equal_approx(float(r60["speed"]), float(drowned["speed"]) * float(cfg["speed"]["max"])) and is_equal_approx(float(r60["damage"]), float(drowned["damage"]) * float(cfg["damage"]["max"])) and float(r60["max_hp"]) > float(r20["max_hp"]) * 10.0)
	_say("enemies come faster in later rounds: every %.1f s in round 1, %.1f s in round 20, %.2f s in a special round" % [rules.spawn_gap(1, "normal"), rules.spawn_gap(20, "normal"), rules.spawn_gap(7, "special")], rules.spawn_gap(20, "normal") < rules.spawn_gap(1, "normal") and rules.spawn_gap(7, "special") < rules.spawn_gap(7, "normal"))

	# --- a run played through: every enemy dies 6 seconds after it came ashore ---
	rules.alive_cap = 8
	rules.round_started.connect(func(number: int, kind: String) -> void: _events.append("start %d %s" % [number, kind]))
	rules.round_ended.connect(func(number: int, kind: String) -> void: _events.append("end %d %s" % [number, kind]))
	_say("nothing happens before a run starts", rules.update(0.0, 0) == "" and not rules.running())
	rules.start(100.0)
	var deaths: Array[float] = []  # when each living enemy dies
	var most_alive := 0
	var sent := 0
	var first_spawn := -1.0
	var now := 100.0
	var round_3_at := -1.0
	while now < 100.0 + 600.0 and rules.number < 4:
		now += 0.05
		while not deaths.is_empty() and deaths[0] <= now:
			deaths.pop_front()
		var id := rules.update(now, deaths.size())
		if id != "":
			sent += 1
			deaths.append(now + 6.0)
			if first_spawn < 0.0:
				first_spawn = now
		most_alive = maxi(most_alive, deaths.size())
		if rules.number == 3 and round_3_at < 0.0:
			round_3_at = now
	_say("round 1 starts %.0f s after the run begins" % (first_spawn - 100.0), absf(first_spawn - 100.0 - float(cfg["start_delay"])) < 0.2)
	_say("three rounds played: %d enemies sent in (6 + 8 + 10), never more than %d alive (cap 8)" % [sent - (1 if rules.number == 4 else 0), most_alive], most_alive <= 8 and sent >= 24)
	_say("the rounds were announced in order: %s" % ", ".join(_events.slice(0, 6)), _events.size() >= 6 and _events[0] == "start 1 normal" and _events[1] == "end 1 normal" and _events[2] == "start 2 normal" and _events[5] == "end 3 normal")

	# --- leaving the island in the middle of a round ---
	rules.start(1000.0)
	now = 1000.0 + float(cfg["start_delay"]) + 0.1
	var got: Array = []
	for _i in 3:
		var id := rules.update(now, got.size())
		if id != "":
			got.append(id)
		now += 5.0
	var before := rules.left(got.size())
	rules.put_back(got)
	_say("everybody leaves with %d alive: they go back into the sea and the round still has %d to beat" % [got.size(), rules.left(0)], got.size() == 3 and rules.left(0) == before and rules.number == 1)
	rules.delay(500.0)
	_say("the clock stood still for the 500 s nobody was there: nothing comes at once", rules.update(now + 1.0, 0) == "")
	rules.stop()
	_say("game over: back to before round 1", rules.number == 0 and not rules.running() and rules.left(0) == 0)

	_lines.append("ROUND_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/round_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
