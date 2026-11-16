# Purpose: developer check of sea step 5a's sailing rules (core/sea/ship_rules.gd: wind share by heading, sail stages
# and oars, anchor, turning to the side of the rudder, the lean, the deck outline, the helmsman's level gate) and, when
# the model is imported, that a ship (game/sea_ship.gd) finds its moving parts and stands where its state says.
# Writes tools/ship_check.log ("SHIP_CHECK problems=n").
# Dependencies: core/sea/ship_rules.gd, game/sea_ship.gd, core/sea/sea_waves.gd, data/sea/ships.json, data/sea/world.json.
extends Node3D

const ShipRules = preload("res://core/sea/ship_rules.gd")
const SeaShip = preload("res://game/sea_ship.gd")
const SeaWaves = preload("res://core/sea/sea_waves.gd")
const HullRules = preload("res://core/sea/hull_rules.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/ships.json"))
	var rules := ShipRules.new(cfg)
	_hull_checks(rules)
	_swift_checks(rules)
	_check(rules.wind_share(45.0) > rules.wind_share(90.0) and rules.wind_share(90.0) > rules.wind_share(135.0), "broad reach > beam reach > close hauled")
	_check(rules.wind_share(175.0) == 0.0, "no way forward straight into the wind")
	var s := rules.new_state("sloop", 0.0, 0.0, 0.0)  # bow to the north (-z)
	var to_south := PI * 0.5  # Vector2.from_angle: (0, 1) = +z = south
	_check(is_equal_approx(ShipRules.off_wind(0.0, to_south), 180.0), "bow north, wind blowing south = straight into it")
	_check(is_equal_approx(ShipRules.off_wind(0.0, -PI * 0.5), 0.0), "bow north, wind blowing north = running")
	_check(rules.target_speed(s, 1.0, -PI * 0.5, 0.0) == 0.0, "anchored: no speed")
	s["anchored"] = false
	s["stage"] = 4
	var full := rules.target_speed(s, 1.0, -PI * 0.5, 0.0)
	s["stage"] = 3
	var half := rules.target_speed(s, 1.0, -PI * 0.5, 0.0)
	_check(full > half and half > 0.0, "full sail beats half sail (%.1f vs %.1f)" % [full, half])
	_check(rules.target_speed(s, 1.0, -PI * 0.5, 0.1) > half, "the Sailing perk adds speed")
	_check(rules.target_speed(s, 0.0, -PI * 0.5, 0.0) < half, "less wind, less speed")
	s["stage"] = 2
	_check(rules.target_speed(s, 0.0, to_south, 0.0) > 0.0, "oars go ahead even into the wind")
	s["stage"] = 0
	_check(rules.target_speed(s, 0.5, -PI * 0.5, 0.0) < 0.0, "oars back go astern")
	rules.step_stage(s, false)
	_check(int(s["stage"]) == 0, "the stages stop at the ends")
	s = rules.new_state("sloop", 0.0, 0.0, 0.0)
	s["anchored"] = false
	s["stage"] = 4
	var moved := 0.0
	for i in 600:
		moved += rules.step(s, 0.8, -PI * 0.25, 0.0, 1.0 / 60.0)
	_check(float(s["speed"]) > 1.0 and float(s["z"]) < 0.0, "under sail she gathers way and goes ahead (%.1f m/s, %.0f m)" % [s["speed"], moved])
	s["rudder"] = 1.0
	var yaw_before := float(s["yaw"])
	for i in 60:
		rules.step(s, 0.8, -PI * 0.25, 0.0, 1.0 / 60.0)
	var bow := Vector2(-sin(float(s["yaw"])), -cos(float(s["yaw"])))
	_check(bow.x > 0.0 and float(s["yaw"]) < yaw_before, "starboard rudder turns her to starboard (east from north)")
	s["anchored"] = true
	for i in 300:
		rules.step(s, 0.8, -PI * 0.25, 0.0, 1.0 / 60.0)
	_check(absf(float(s["speed"])) < 0.01, "the anchor stops her")
	var lean := rules.heel({"ship": "sloop", "yaw": 0.0, "stage": 4}, 1.0, 0.0)  # wind blowing east = to starboard
	_check(lean > 0.0, "a wind blowing to starboard leans her to starboard (%.1f deg)" % lean)
	_check(rules.half_width("sloop", 0.0) > 2.0 and rules.half_width("sloop", -7.2) < 0.1 and rules.half_width("sloop", 20.0) == 0.0, "the deck outline")
	_check(rules.aboard("sloop", Vector3(0.5, 1.4, 1.0)) and not rules.aboard("sloop", Vector3(4.0, 1.4, 1.0)) and not rules.aboard("sloop", Vector3(0.0, -1.0, 0.0)), "aboard or not")
	_check(rules.can_steer("sloop", 1) and not rules.can_steer("sloop", 0), "the helmsman's level gate")
	# the ship in the world
	var ship := SeaShip.new()
	add_child(ship)
	ship.setup(rules, rules.new_state("sloop", 100.0, -50.0, 90.0))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/world.json"))
	ship.pose(SeaWaves.new(world["waves"]), 10.0, 1.0, 0.5, 0.0, 0.0)
	_check(ship.position.distance_to(Vector3(100.0, ship.position.y, -50.0)) < 0.01 and absf(ship.position.y) <= 1.0, "she stands where her state says, riding the waves")
	var spot := ship.deck_spot([0.0, 0.0])
	_check(absf(spot.y - ship.position.y - 1.3) < 0.4, "deck spot at deck height")
	var shapes := ship.find_children("*", "CollisionShape3D", true, false).size()
	_check(shapes >= 10, "hull, bulwarks, transom and mast are solid (%d shapes)" % shapes)
	if ResourceLoader.exists(String(cfg["ships"]["sloop"]["model"])):
		var found: Dictionary = ship.get("_parts")
		_check(found.size() == 8, "the model's moving parts are found (%s)" % str(found.keys()))
	else:
		_lines.append("note the sloop model is not imported here (stand-in box)")
	for ship_id: String in cfg["ships"]:  # every ship: its numbers hang together and its model (once imported) has a yard + sail per mast
		var sp: Dictionary = cfg["ships"][ship_id]
		var other := SeaShip.new()
		add_child(other)
		other.setup(rules, rules.new_state(ship_id, 0.0, 0.0, 0.0))
		var masts := (sp["masts"] as Array).size()
		var shown := "model not imported"
		if ResourceLoader.exists(String(sp["model"])):
			shown = "%d yards, %d sails" % [(other.get("_yards") as Array).size(), (other.get("_sails") as Array).size()]
			_check((other.get("_yards") as Array).size() == masts and (other.get("_sails") as Array).size() == masts, "%s: a yard and a sail on each of %d masts" % [ship_id, masts])
		_check(rules.half_width(ship_id, float(sp["helm"][1])) > absf(float(sp["helm"][0])) and rules.half_width(ship_id, float(sp["anchor"][1])) > 0.2, "%s: helm and anchor on the deck (%s)" % [ship_id, shown])
		for place: Array in sp["cannons"] + sp["rigging"]:
			_check(rules.half_width(ship_id, float(place[1])) >= absf(float(place[0])), "%s: station %s on the deck" % [ship_id, str(place)])
	_lines.append("SHIP_CHECK problems=%d" % _problems)
	var f := FileAccess.open("res://tools/ship_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	get_tree().quit()


func _check(ok: bool, what: String) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_problems += 1


# Sea step 5d: hull, leaks, flooding, sinking, planks, aground damage (core/sea/hull_rules.gd, data/sea/hull.json).
func _hull_checks(rules: ShipRules) -> void:
	var hull := HullRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/hull.json")))
	for id: String in rules.cfg["ships"]:
		_check((hull.cfg["hull"] as Dictionary).has(id), "%s has a hull size" % id)
		_check(HullRules.zones(rules.spec(id)).size() == 3, "%s has three leak zones" % id)
	var s := rules.new_state("sloop", 0.0, 0.0, 0.0)
	hull.fill(s)
	var spec: Dictionary = rules.spec("sloop")
	var most := hull.max_hull("sloop")
	_check(hull.hit(s, spec, 0.0, -5.0, most * 0.02) == -1 and hull.holes(s) == 0.0, "a light blow holes nothing")
	_check(hull.hit(s, spec, 0.0, -5.0, most * 0.1) == 0, "a hard blow near the bow holes the bow zone")
	_check(hull.hit(s, spec, 0.0, 6.0, most * 0.1) == 2, "a hard blow at the stern holes the stern zone")
	var dry := hull.speed_mult(s)
	for i in 100:
		hull.step(s, 0.5)
	_check(float(s["water"]) > 0.0 and hull.speed_mult(s) < dry, "holes flood the hold and slow her (water %.2f)" % float(s["water"]))
	_check(hull.use_plank(s, 0) == "patched" and float(s["leaks"][0]) == 0.0, "a plank patches the bow")
	_check(hull.use_plank(s, 0) == "", "nothing to mend while the stern is still holed")
	hull.use_plank(s, 2)
	var water := float(s["water"])
	hull.step(s, 10.0)
	_check(float(s["water"]) < water, "the pumps drain a sound hull")
	var h := float(s["hull"])
	_check(hull.use_plank(s, 1) == "mended" and float(s["hull"]) > h, "with no holes a plank mends hull")
	s["leaks"] = [1.0, 1.0, 1.0]
	var founder := false
	for i in 400:
		if hull.step(s, 0.5):
			founder = true
			break
	_check(founder, "three open holes founder her")
	hull.refloat(s)
	_check(not hull.sunk(s) and not hull.seaworthy(s), "refloated: afloat but not seaworthy")
	hull.use_plank(s, 0)
	hull.use_plank(s, 0)
	_check(hull.seaworthy(s), "two planks make her seaworthy")
	_check(hull.aground_damage(1.5) == 0.0 and hull.aground_damage(6.0) > hull.aground_damage(4.0), "aground: harmless slow, worse faster")
	_check(hull.hit(s, spec, 0.0, 0.0, NAN) == -1, "a bad number does nothing")


# Sea step 5e: the swift sail (the last stage, gated by Sailing level; the wind always from astern).
func _swift_checks(rules: ShipRules) -> void:
	var top := rules.stage_count() - 1
	_check(bool((rules.cfg["stages"][top] as Dictionary).get("swift", false)), "the last stage is the swift sail")
	_check(rules.top_stage(1) == top - 1 and rules.top_stage(70) == top, "the swift sail needs its Sailing level (top %d at 1, %d at 70)" % [rules.top_stage(1), rules.top_stage(70)])
	var s := rules.new_state("sloop", 0.0, 0.0, 0.0)
	s["anchored"] = false
	s["stage"] = top - 1
	var into := PI * 0.5  # bow north, the wind blowing south = straight into it
	_check(rules.target_speed(s, 0.6, into, 0.0) == 0.0, "full sail goes nowhere into the wind")
	s["stage"] = top
	var swift_into := rules.target_speed(s, 0.6, into, 0.0)
	s["stage"] = top - 1
	var full_best := rules.target_speed(s, 0.6, -PI * 0.5 + deg_to_rad(45.0), 0.0)
	s["stage"] = top
	_check(swift_into > full_best, "the swift sail into the wind beats full sail at its best (%.1f vs %.1f)" % [swift_into, full_best])
	_check(rules.target_speed(s, 0.0, into, 0.0) > 0.0, "the swift sail moves even in a calm")
