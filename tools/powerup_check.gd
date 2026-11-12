# Purpose: developer check of the islands' power-ups and of the pony rule: what dying enemies leave (chance, cap per
# round, bosses), the clocks of insta-kill and double points, what double points does to the points card, the pool of
# pickups (who takes one, when one's time is up, what a watching machine does), that no ordinary roll gives a pony
# gun any more, and how often trash leaves one. Log tools/powerup_check.log (ends POWERUP_CHECK_DONE problems=n).
# Dependencies: core/powerup_rules.gd, core/score_card.gd, core/drop_rules.gd, core/gun_gen.gd, core/gun_db.gd,
# core/data_store.gd, game/powerup_field.gd.
extends Node

const PowerupRules = preload("res://core/powerup_rules.gd")
const PowerupField = preload("res://game/powerup_field.gd")
const ScoreCard = preload("res://core/score_card.gd")
const DropRules = preload("res://core/drop_rules.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunDb = preload("res://core/gun_db.gd")
const DataStore = preload("res://core/data_store.gd")

var _lines := PackedStringArray()
var _problems := 0
var _touched: Array = []
var _expired: Array = []
var _near: Array = []


func _ready() -> void:
	var cfg: Dictionary = DataStore.load_json("res://data/powerups.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261112
	var rules := PowerupRules.new(cfg)
	var data_fine := float(cfg["drop_chance"]) > 0.0 and float(cfg["drop_chance"]) < 0.5 and int(cfg["max_per_round"]) > 0 and float(cfg["seconds_on_ground"]) > float(cfg["blink_seconds"]) and rules.has(String(cfg["special_round_end"]))
	for kind: String in ["max_ammo", "insta_kill", "double_points", "nuke"]:
		data_fine = data_fine and rules.has(kind) and float(cfg["kinds"][kind]["weight"]) > 0.0 and rules.name_of(kind) != ""
	_say("data/powerups.json: %s; chance %.0f %%, at most %d a round, %.0f s on the ground" % [", ".join(PackedStringArray(rules.kinds())), float(cfg["drop_chance"]) * 100.0, int(cfg["max_per_round"]), float(cfg["seconds_on_ground"])], data_fine)

	var left_in_round := 0
	for _n in 5000:
		if rules.roll_drop(rng, false) != "":
			left_in_round += 1
	_say("5000 kills in one round leave %d power-ups (the cap)" % left_in_round, left_in_round == int(cfg["max_per_round"]))
	_say("the cap holds until the next round", rules.roll_drop(rng, false) == "")
	var bosses := 0
	for _n in 50:
		if rules.has(rules.roll_drop(rng, true)):
			bosses += 1
	_say("a boss always leaves one, cap or not", bosses == 50)
	var chance_drops := 0
	for _n in 40000:
		rules.new_round()
		if rules.roll_drop(rng, false) != "":
			chance_drops += 1
	_say("40000 first kills of a round leave %d (about %d expected)" % [chance_drops, roundi(40000.0 * float(cfg["drop_chance"]))], absf(float(chance_drops) / 40000.0 - float(cfg["drop_chance"])) < 0.004)
	var seen := {}
	for _n in 20000:
		var kind := rules.pick(rng)
		seen[kind] = int(seen.get(kind, 0)) + 1
	var total := 0.0
	for kind: String in cfg["kinds"]:
		total += float(cfg["kinds"][kind]["weight"])
	var spread_fine := seen.size() == (cfg["kinds"] as Dictionary).size()
	for kind: String in seen:
		spread_fine = spread_fine and absf(float(seen[kind]) / 20000.0 - float(cfg["kinds"][kind]["weight"]) / total) < 0.015
	_say("kinds come by their weights: %s" % [seen], spread_fine)

	var lasts := rules.seconds_of("insta_kill")
	_say("nothing runs before anything is taken", not rules.is_on("insta_kill", 0.0) and rules.points_mult(0.0) == 1 and rules.timed().size() == 2)
	rules.start("insta_kill", 100.0)
	rules.start("max_ammo", 100.0)
	_say("insta-kill runs %.0f s; max ammo has no clock" % lasts, rules.is_on("insta_kill", 100.0 + lasts - 0.1) and not rules.is_on("insta_kill", 100.0 + lasts) and not rules.is_on("max_ammo", 100.5) and is_equal_approx(rules.left("insta_kill", 110.0), lasts - 10.0))
	rules.start("insta_kill", 120.0)
	_say("taking it again starts its clock from full", is_equal_approx(rules.left("insta_kill", 120.0), lasts))
	rules.start("double_points", 200.0)
	_say("double points: x%d while it runs, x1 after" % rules.points_mult(201.0), rules.points_mult(201.0) == int(cfg["kinds"]["double_points"]["mult"]) and rules.points_mult(200.0 + rules.seconds_of("double_points") + 0.1) == 1)
	rules.reset()
	_say("game over stops every clock", not rules.is_on("double_points", 201.0) and not rules.is_on("insta_kill", 121.0))

	var points: Dictionary = DataStore.load_json("res://data/points.json")
	var card := ScoreCard.new(points)
	card.mult = 2
	card.hit()
	card.kill()
	card.blow = "headshot"
	card.kill()
	card.blow = "melee"
	card.kill()
	card.blow = ""
	var doubled := 2 * (int(points["awards"]["hit"]) + int(points["awards"]["kill"]) + int(points["awards"]["headshot_kill"]) + int(points["awards"]["melee_kill"]))
	card.mult = 1
	card.hit()
	_say("with double points a hit and three kills pay %d, then a hit pays %d again" % [doubled, int(points["awards"]["hit"])], card.points == doubled + int(points["awards"]["hit"]) and card.kills == 3)

	# the pickups
	var field := PowerupField.new()
	field.setup(cfg)
	field.bodies = func() -> Array: return _near
	field.touched.connect(func(id: int, kind: String) -> void: _touched.append([id, kind]))
	field.expired.connect(func(id: int) -> void: _expired.append(id))
	add_child(field)
	var walker := Node3D.new()
	add_child(walker)
	walker.global_position = Vector3(50, 0, 0)
	_near = [walker]
	field.drop(1, "max_ammo", Vector3(0, 0, 0))
	field.drop(2, "nuke", Vector3(10, 0, 0))
	field.drop(3, "no_such_thing", Vector3(20, 0, 0))
	_say("two lie there (an unknown kind is not dropped)", field.count() == 2)
	field.call("_process", 0.2)
	_say("nobody near: nothing is taken", _touched.is_empty() and field.count() == 2)
	walker.global_position = Vector3(10.0 + float(cfg["reach"]) - 0.1, 0, 0)
	field.call("_process", 0.2)
	_say("walking into one takes it: %s" % [_touched], _touched == [[2, "nuke"]] and field.count() == 1)
	field.call("_process", float(cfg["seconds_on_ground"]))
	_say("the other one's time runs out: %s" % [_expired], _expired == [1] and field.count() == 0)
	field.deciding = false
	field.drop(4, "insta_kill", walker.global_position)
	field.call("_process", 0.2)
	field.call("_process", float(cfg["seconds_on_ground"]) + 1.0)
	_say("a machine that only watches takes nothing and ends nothing by itself", _touched.size() == 1 and _expired.size() == 1 and field.count() == 1)
	field.remove(4)
	_say("... it removes one when the host says so", field.count() == 0)
	field.deciding = true
	_near = []
	for n in PowerupField.SIZE + 2:
		field.drop(10 + n, "double_points", Vector3(float(n) * 3.0, 0, 30))
		field.call("_process", 0.01)
	_say("more than %d at once: the oldest give way" % PowerupField.SIZE, field.count() == PowerupField.SIZE and field.spot_of(10) == Vector3.ZERO and field.spot_of(11) == Vector3.ZERO and field.spot_of(12) != Vector3.ZERO)
	field.clear()
	_say("game over clears the field", field.count() == 0)

	# the pony rule
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"), DataStore.load_json("res://data/gun_uniques.json"))
	var drops: Dictionary = DataStore.load_json("res://data/drops.json")
	var one_in := int(drops["pony_trash_one_in"])
	var rolls := one_in * 30
	var ponies := 0
	for _n in rolls:
		if DropRules.pony_roll(drops, rng):
			ponies += 1
	_say("%d trash kills leave %d pony guns (1 in %d: about 30 expected)" % [rolls, ponies, one_in], one_in == 100000 and ponies >= 14 and ponies <= 50)
	_say("pony_trash_one_in 0 = never, 1 = always", not DropRules.pony_roll({"pony_trash_one_in": 0}, rng) and not DropRules.pony_roll({}, rng) and DropRules.pony_roll({"pony_trash_one_in": 1}, rng))
	var rolled_pony := 0
	var best := 0
	for n in 200000:
		var tier := GunGen.pick_tier(db, rng, float(n % 5), "" if n % 2 == 0 else "orange")
		best = maxi(best, db.tier_index(tier))
		if tier == "pony":
			rolled_pony += 1
	_say("200000 ordinary tier rolls with luck up to 4: %d pony, best tier %s" % [rolled_pony, String(db.tiers[best]["id"])], rolled_pony == 0 and String(db.tiers[best]["id"]) == "rainbow")
	var crate_pony := 0
	var crates: Array = DataStore.load_json("res://data/gun_loot.json")["vendor"]
	for crate: Dictionary in crates:
		for _n in 4000:
			if String(GunGen.generate(db, rng, float(crate["luck"]) * 3.0, "", "", String(crate["min_tier"]))["tier"]) == "pony":
				crate_pony += 1
	_say("%d casino crates opened 4000 times each at triple luck: %d pony" % [crates.size(), crate_pony], crate_pony == 0)
	var made := GunGen.generate(db, rng, 0.0, "", "pony")
	_say("the trash roll's own gun is pony tier and passes the gun check", String(made["tier"]) == "pony" and GunGen.validate(db, made) == "")

	_lines.append("POWERUP_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/powerup_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
