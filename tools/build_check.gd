# Purpose: developer check of the buildables' rules: core/build_state.gd with data/buildables.json (parts found,
# things built, the state as one number), core/shield_state.gd with data/shield.json (which side a shield covers on
# the back and in hand, how it wears and breaks), core/boat_rules.gd with data/boat.json on the real land (sailing, running aground, reaching Gull Rock, seats). Log tools/build_check.log (ends BUILD_CHECK_DONE problems=n).
# Dependencies: core/build_state.gd, core/shield_state.gd, core/boat_rules.gd, core/archipelago.gd, core/data_store.gd.
extends Node

const BuildState = preload("res://core/build_state.gd")
const ShieldState = preload("res://core/shield_state.gd")
const BoatRules = preload("res://core/boat_rules.gd")
const Archipelago = preload("res://core/archipelago.gd")
const DataStore = preload("res://core/data_store.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var cfg: Dictionary = DataStore.load_json("res://data/buildables.json")
	var land := Archipelago.new(DataStore.load_json("res://data/archipelago.json"))
	var placed := true
	var where := PackedStringArray()
	for thing: Dictionary in cfg["things"]:
		for place: Dictionary in (thing["parts"] as Array) + [thing["bench"]]:
			var spot := land.on_island(String(place["island"]), place["at"])
			var dry := land.index_of(String(place["island"])) >= 0 and land.on_land(spot.x, spot.y) and land.height_at(spot.x, spot.y) > -0.05
			placed = placed and dry
			if not dry:
				where.append("%s %s" % [thing["id"], place.get("name", "bench")])
	_say("every part and bench lies on dry flat ground of an island that exists%s" % ("" if placed else ": NOT " + ", ".join(where)), placed)

	var builds := BuildState.new(cfg)
	var shield := builds.index_of("shield")
	var boat := builds.index_of("boat")
	_say("the shield and the boat are in the data (%d and %d parts)" % [builds.part_count(shield), builds.part_count(boat)], shield >= 0 and boat >= 0 and builds.part_count(shield) >= 1 and builds.part_count(boat) >= 1)
	_say("nothing is built from nothing", not builds.build(shield) and not builds.built(shield))
	_say("a part is found once", builds.take(shield, 0) and not builds.take(shield, 0) and builds.found_count(shield) == 1 and not builds.take(shield, 99) and not builds.take(7, 0))
	for part in builds.part_count(shield):
		builds.take(shield, part)
	_say("with every part found it is built, once", builds.all_found(shield) and builds.build(shield) and builds.built(shield) and not builds.build(shield) and not builds.built(boat))
	_say("a code names a part or a bench and comes apart again", BuildState.thing_of(BuildState.code_of(1, 3)) == 1 and BuildState.part_of(BuildState.code_of(1, 3)) == 3 and BuildState.part_of(BuildState.code_of(0, BuildState.BENCH)) == BuildState.BENCH and BuildState.thing_of(-1) == -1)
	_say("apply() does what a code asks", builds.apply(BuildState.code_of(boat, 1)) and not builds.apply(BuildState.code_of(boat, 1)) and not builds.apply(BuildState.code_of(boat, BuildState.BENCH)))
	var copy := BuildState.new(cfg)
	copy.set_bits(builds.to_bits())
	_say("the state travels as one number (%d)" % builds.to_bits(), copy.built(shield) and copy.found_count(boat) == 1 and copy.found(boat)[1] and not copy.built(boat) and copy.to_bits() == builds.to_bits())
	builds.reset()
	_say("game over: nothing found, nothing built", builds.to_bits() == 0 and not builds.built(shield))

	var worn := ShieldState.new()
	worn.setup(DataStore.load_json("res://data/shield.json"))
	_say("no shield stops nothing", not worn.stops(PI, false) and not worn.stops(0.0, true))
	_say("a shield is given once and is whole (%d hits)" % worn.max_hits(), worn.give() and not worn.give() and worn.hits_left == worn.max_hits() and worn.max_hits() > 0)
	var half := deg_to_rad(float(worn.cfg["arc_deg"])) * 0.5
	_say("on the back it stops what comes from behind, not from ahead or the side", worn.stops(PI, false) and worn.stops(PI - half + 0.01, false) and not worn.stops(0.0, false) and not worn.stops(PI - half - 0.05, false))
	_say("in hand it stops what comes from ahead, not from behind", worn.stops(0.0, true) and worn.stops(half - 0.01, true) and not worn.stops(PI, true) and not worn.stops(half + 0.05, true))
	var blows := 0
	while worn.owned and blows < 1000:
		blows += 1
		if worn.wear(1):
			break
	_say("it breaks on hit %d and is gone" % blows, blows == worn.max_hits() and not worn.owned and not worn.stops(PI, false))
	worn.give()
	var boss_blows := 0
	while worn.owned and boss_blows < 1000:
		boss_blows += 1
		worn.wear(int(worn.cfg["boss_cost"]))
	_say("a boss's blows break it in %d" % boss_blows, boss_blows == ceili(float(worn.max_hits()) / float(worn.cfg["boss_cost"])))

	# --- the boat (core/boat_rules.gd with data/boat.json) on the real land ---
	var boat_cfg: Dictionary = DataStore.load_json("res://data/boat.json")
	var skiff := BoatRules.new(boat_cfg)
	var depth := func(at_x: float, at_z: float) -> float:
		return 0.0 if (not land.within(at_x, at_z) or land.deck_at(at_x, at_z) >= 0) else land.sea_level - land.height_at(at_x, at_z)
	var start := land.on_island(String(boat_cfg["start"]["island"]), boat_cfg["start"]["at"])
	var isle: Vector2 = land.islands[land.island_near(start.x, start.y)]["at"]
	var out := start - isle
	skiff.place(start, atan2(-out.x, -out.y))
	_say("it starts afloat (%.2f m of water for a draught of %.2f), bow out to sea, a few steps off %s" % [float(depth.call(start.x, start.y)), float(boat_cfg["draught"]), String(land.islands[land.island_near(start.x, start.y)]["name"])],
		float(depth.call(start.x, start.y)) > float(boat_cfg["draught"]) and skiff.forward().dot(out.normalized()) > 0.99 and out.length() - float(land.islands[land.island_near(start.x, start.y)]["radius"]) < float(boat_cfg["board_reach"]) + 2.0)
	_say("left alone it stays where it is", _sail(skiff, 0.0, 0.0, 3.0, depth) < 0.001)
	_sail(skiff, 1.0, 0.0, 6.0, depth)
	_say("full ahead for 6 s: top speed %.1f m/s, never more" % skiff.speed, absf(skiff.speed - float(boat_cfg["max_speed"])) < 0.01)
	var heading := skiff.yaw
	_sail(skiff, 1.0, 1.0, 1.0, depth)
	_say("rudder to the right turns it right (%.0f degrees in a second)" % rad_to_deg(angle_difference(skiff.yaw, heading)), angle_difference(skiff.yaw, heading) > 0.5)
	_sail(skiff, 1.0, -1.0, 1.0, depth)
	skiff.place(start, atan2(-out.x, -out.y))
	_say("standing still the rudder does nothing", _turn(skiff, 0.0, 1.0, 2.0, depth) < 0.001)
	_say("keys let go: it drifts to a stop", _coast(skiff, depth))
	skiff.place(start, atan2(-out.x, -out.y) + PI)  # bow toward the island
	_sail(skiff, 1.0, 0.0, 6.0, depth)
	var beached := Vector2(skiff.x, skiff.z)
	_say("driven at the island it runs aground in the shallows and stops (%.1f m from the waterline)" % (beached.distance_to(isle) - float(land.islands[land.island_near(start.x, start.y)]["radius"])), skiff.aground and skiff.speed == 0.0 and land.height_at(skiff.x, skiff.z) < land.sea_level)
	_sail(skiff, -1.0, 0.0, 3.0, depth)
	_say("and backs off again (astern at %.1f m/s)" % -skiff.speed, Vector2(skiff.x, skiff.z).distance_to(isle) > beached.distance_to(isle) + 2.0 and not skiff.aground)
	for bearing: Vector2 in [Vector2(1, 0), Vector2(-1, 0)]:  # toward the club and toward the colosseum (director's bug: it got stuck for good at the edge)
		skiff.place(start, atan2(-bearing.x, -bearing.y))
		_sail(skiff, 1.0, 0.0, 120.0, depth)
		var stopped := Vector2(skiff.x, skiff.z)
		var held := skiff.aground and land.within(skiff.x, skiff.z)
		_sail(skiff, -1.0, 0.0, 4.0, depth)
		var backed := Vector2(skiff.x, skiff.z).distance_to(stopped)
		skiff.place(Vector2(skiff.x, skiff.z), skiff.yaw + PI * 0.5)
		var away := _sail(skiff, 1.0, 0.0, 3.0, depth)
		_say("sailed %s it stops at the edge of the islands' waters, backs off (%.1f m) and sails on along it (%.1f m)" % ["east" if bearing.x > 0.0 else "west", backed, away], held and backed > 3.0 and away > 5.0)
	var gull := land.index_of("gull")
	skiff.place(start, atan2(-out.x, -out.y))
	var best := INF
	for _second in 40:
		var to: Vector2 = (land.islands[gull]["at"] as Vector2) - Vector2(skiff.x, skiff.z)
		var off := angle_difference(atan2(-to.x, -to.y), skiff.yaw)  # above 0 = the island lies to the right
		_sail(skiff, 1.0, clampf(off * 3.0, -1.0, 1.0), 1.0, depth)
		best = minf(best, to.length() - float(land.islands[gull]["radius"]))
		if skiff.aground:
			break
	var landing := land.wash_up(skiff.x, skiff.z)
	_say("steered at Gull Rock it gets there and beaches; the sand is %.1f m from the boat (within reach to get off)" % Vector2(landing.x - skiff.x, landing.z - skiff.z).length(),
		gull >= 0 and skiff.aground and land.island_near(skiff.x, skiff.z) == gull and Vector2(landing.x - skiff.x, landing.z - skiff.z).length() <= float(boat_cfg["land_reach"]))
	_say("the first aboard takes the tiller, the next a seat; a seventh finds it full", skiff.sit(11) == 0 and skiff.sit(12) == 1 and skiff.sit(11) == 0 and skiff.sit(13) == 2 and skiff.sit(14) == 3 and skiff.sit(15) == 4 and skiff.sit(16) == 5 and skiff.sit(17) == -1 and skiff.aboard() == 6)
	_say("when the helmsman gets off, the next one moves to the tiller", skiff.leave(11) and skiff.helm() == 12 and skiff.seat_of(12) == 0 and skiff.seat_of(11) == -1 and not skiff.leave(11) and skiff.aboard() == 5)
	var place := skiff.seat_place(0)
	_say("the helm seat is in the boat, behind its middle", Vector2(place.x - skiff.x, place.z - skiff.z).dot(skiff.forward()) < 0.0 and Vector2(place.x - skiff.x, place.z - skiff.z).length() < float(boat_cfg["half_length"]))
	skiff.empty()
	_say("game over: nobody aboard", skiff.aboard() == 0 and skiff.helm() == 0)

	_lines.append("BUILD_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/build_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


# Sails for `seconds` in 1/60 s steps. Returns how far it got.
func _sail(skiff: BoatRules, throttle: float, rudder: float, seconds: float, depth: Callable) -> float:
	var from := Vector2(skiff.x, skiff.z)
	for _step in int(seconds * 60.0):
		skiff.step(throttle, rudder, 1.0 / 60.0, depth)
	return from.distance_to(Vector2(skiff.x, skiff.z))


func _turn(skiff: BoatRules, throttle: float, rudder: float, seconds: float, depth: Callable) -> float:
	var before := skiff.yaw
	_sail(skiff, throttle, rudder, seconds, depth)
	return absf(angle_difference(before, skiff.yaw))


func _coast(skiff: BoatRules, depth: Callable) -> bool:
	_sail(skiff, 1.0, 0.0, 4.0, depth)
	var fast := skiff.speed
	_sail(skiff, 0.0, 0.0, 12.0, depth)
	return fast > 5.0 and skiff.speed == 0.0


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
