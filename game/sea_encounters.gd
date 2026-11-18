# Purpose: SEA ENCOUNTERS (sea step 8; director 2026-11-18: random encounters while sailing, weighted by region,
# weather and night; pirate ships both by size: small ones fire broadsides from range, big ones also board (8b);
# loot: floating debris + deck drops): the HOST rolls core/sea/encounter_rules.gd every check_seconds for a player at
# sea outside the home port's safe waters, and a foe ship comes in ahead of him: a ship of the fleet with
# state["foe"] = kind (not saved with the world's fleet, nobody takes her helm), dark sails and a black flag. Her
# sailing is core/sea/pirate_rules.gd (approach, lay the target abeam, veer off when too near, flee when holed); her
# guns fire through game/sea_cannons.gd (the host's real balls, told to everyone). A foe sunk leaves flotsam
# (game/sea_flotsam.gd); a foe nobody is near any more sails off the map (removed). Her crew (8b) is
# game/sea_crews.gd: a boarder closes to board_keep_m and swings her boarders across; a foe whose deck is cleared
# strikes (drifts, no guns). Sea step 8d: GHOST SHIPS (kinds "ghost": true, night only) phase in and out
# (game/sea_ghosts.gd: she fires only once solid) and THE DROWNED rise round a ship at night (game/sea_drowned.gd).
# Dependencies: core/sea/encounter_rules.gd, core/sea/pirate_rules.gd, game/sea_flotsam.gd, game/sea_crews.gd, data/sea/encounters.json;
# the fleet (game/sea_ships.gd: spawn, remove, cannons, rules), the sea world (clock, weather, local_of, others).
extends Node3D

const EncounterRules = preload("res://core/sea/encounter_rules.gd")
const PirateRules = preload("res://core/sea/pirate_rules.gd")
const SeaFlotsam = preload("res://game/sea_flotsam.gd")
const SeaCrews = preload("res://game/sea_crews.gd")
const SeaSharks = preload("res://game/sea_sharks.gd")
const SeaSerpent = preload("res://game/sea_serpent.gd")
const SeaGhosts = preload("res://game/sea_ghosts.gd")
const SeaDrowned = preload("res://game/sea_drowned.gd")
const SeaBeasts = preload("res://game/sea_beasts.gd")
const SeaUboat = preload("res://game/sea_uboat.gd")

var rules: EncounterRules
var pirate: PirateRules
var flotsam := SeaFlotsam.new()
var crews := SeaCrews.new()
var sharks := SeaSharks.new()  # sea step 8c
var serpent := SeaSerpent.new()
var ghosts := SeaGhosts.new()  # sea step 8d
var drowned := SeaDrowned.new()
var beasts := SeaBeasts.new()  # sea step 8e: each region's own creature
var uboat := SeaUboat.new()  # sea step 8e-4: the G U-boat sightings
var paused := false  # dev: no rolls (tests spawn their own)
var rolled := 0  # dev / checks: checks rolled, foes that came, foes sunk, volleys fired
var came := 0
var sunk := 0
var volleys := 0
var last := ""  # dev: the last foe's plan
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _check := 0.0
var _rng := RandomNumberGenerator.new()
var _next_gun := {}  # foe ship -> time her next gun may fire (volley gap)


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	rules = EncounterRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/encounters.json")))
	pirate = PirateRules.new(rules.cfg["pirate"])
	_check = float(rules.cfg["check_seconds"])
	_rng.randomize()
	flotsam.name = "Flotsam"
	add_child(flotsam)
	flotsam.setup(fleet, sea, player, rules)
	crews.name = "Crews"
	add_child(crews)
	crews.setup(fleet, sea, player, rules.cfg)
	sharks.name = "Sharks"
	add_child(sharks)
	sharks.setup(fleet, sea, player, rules.cfg)
	serpent.name = "Serpent"
	add_child(serpent)
	serpent.setup(fleet, sea, player, rules.cfg)
	ghosts.name = "Ghosts"
	add_child(ghosts)
	ghosts.setup(fleet, sea, self, rules.cfg)
	drowned.name = "Drowned"
	add_child(drowned)
	drowned.setup(fleet, sea, player, crews, sharks, rules.cfg)
	crews.drowned_part = drowned
	beasts.name = "Beasts"
	add_child(beasts)
	beasts.setup(fleet, sea, player, rules.cfg)
	uboat.name = "Uboat"
	add_child(uboat)
	uboat.setup(fleet, sea, self, rules.cfg)


# Set by game/game_session.gd: the wave director that makes the crews and creatures, and the score card (kill pay).
func set_game(director: Node, card: RefCounted) -> void:
	for part: Node in [crews, sharks, serpent, beasts]:
		part.set("director", director)
		part.set("card", card)


func _host() -> bool:
	var net: Node = _fleet.call("_net")
	return net == null or not bool(net.call("is_client"))


func foes() -> Array:
	var out: Array = []
	for ship: Node3D in _fleet.get("ships"):
		if (ship.get("state") as Dictionary).has("foe"):
			out.append(ship)
	return out


func _process(delta: float) -> void:
	if not bool(_sea.call("running")) or not _host() or delta <= 0.0:
		return
	_check -= delta
	if _check <= 0.0:
		_check = float(rules.cfg["check_seconds"])
		if not paused:
			_roll()


# Everyone at sea, in sea coordinates: [{"at": Vector2, "ship": the ship he is on or null}].
func players() -> Array:
	var out: Array = []
	var spots: Array = []
	if bool(_sea.get("inside")):
		spots.append(_player.global_position)
	var others: Callable = _sea.get("others")
	if others.is_valid():
		for at: Vector3 in others.call():
			if at.x < -10000.0:  # (sea_world SIDE_X: the sea side of the scene)
				spots.append(at)
	for at: Vector3 in spots:
		var here: Vector3 = _sea.call("local_of", at)
		var on: Node3D = null
		for ship: Node3D in _fleet.get("ships"):
			var st: Dictionary = ship.get("state")
			if not st.has("foe") and bool(_fleet.get("rules").call("aboard", String(st["ship"]), ship.global_transform.affine_inverse() * at)):
				on = ship
				break
		out.append({"at": Vector2(here.x, here.z), "ship": on})
	return out


func _night() -> bool:
	var clock: RefCounted = (_sea.get("look") as RefCounted).get("clock")
	return clock != null and float(clock.call("daylight", clock.call("day_part", float(_sea.call("seconds"))))) < 0.25


# One check: a foe may come for one of the players out at sea.
func _roll() -> void:
	var list := players()
	if list.is_empty() or foes().size() >= int(rules.cfg["max_foes"]):
		return
	var who: Dictionary = list[_rng.randi() % list.size()]
	var at: Vector2 = who["at"]
	if rules.in_safe_waters(at.x, at.y):
		return
	rolled += 1
	var map: RefCounted = _sea.get("map")
	var region := String(map.call("region_id_at", at.x, at.y))
	var weather: Dictionary = _sea.call("weather_at", Vector3(at.x, 0.0, at.y))
	var on: Node3D = who["ship"]
	var anchored := on == null or bool(on.get("state")["anchored"])
	var night := _night()
	if _rng.randf() >= rules.chance(region, String(weather.get("kind", "calm")), night, anchored):
		return
	var kind := rules.pick(region, night, _rng.randf(), String(weather.get("kind", "calm")))
	if kind == "":
		return
	if String(rules.cfg["kinds"][kind].get("creature", "")) == "serpent":  # the Tide Wyrm (sea step 8c): out of the deep, not over the horizon
		var a := _rng.randf() * TAU
		var from := at + Vector2(cos(a), sin(a)) * 120.0
		if serpent.wyrm == null and sharks.clear_of_land(from.x, from.y, 60.0):
			serpent.spawn(from.x, from.y)
		return
	if String(rules.cfg["kinds"][kind].get("creature", "")) == "beast":  # a region's own creature (sea step 8e)
		if beasts.beasts.is_empty():
			var a2 := _rng.randf() * TAU
			var from2 := at + Vector2(cos(a2), sin(a2)) * 60.0
			beasts.spawn(String(rules.cfg["kinds"][kind]["beast"]), from2.x, from2.y, EncounterRules.region_number(region))
		return
	if String(rules.cfg["kinds"][kind].get("creature", "")) == "drowned":  # the drowned rise round him (sea step 8d)
		if not drowned.rising():
			drowned.begin(on, at, EncounterRules.region_number(region))
		return
	var heading := float(on.get("state")["yaw"]) if on != null else _rng.randf() * TAU
	var spot := rules.spawn_point(at.x, at.y, heading, _rng.randf(), _rng.randf())
	if float(map.call("inside_by", spot.x, spot.y)) < 50.0:
		return
	spawn_foe(kind, spot.x, spot.y, rad_to_deg(EncounterRules.yaw_towards(spot.x, spot.y, at.x, at.y)))


# Host / alone (and dev): a foe ship comes in.
func spawn_foe(kind: String, x: float, z: float, yaw_deg: float) -> Node3D:
	var k: Dictionary = rules.cfg["kinds"].get(kind, {})
	if k.is_empty():
		return null
	var ship: Node3D = _fleet.call("spawn", String(k["ship"]), x, z, yaw_deg)
	var st: Dictionary = ship.get("state")
	st["foe"] = kind
	st["hull_max"] = float(st["hull_max"]) * float(k.get("hull_mult", 1.0))
	st["hull"] = float(st["hull_max"])
	st["anchored"] = false
	st["stage"] = 4
	dress(ship)
	if bool(k.get("ghost", false)):
		ghosts.begin(ship)
	crews.man(ship)
	came += 1
	_sea.emit_signal("notice", String(k.get("notice", rules.cfg["pirate"]["notice"])) % String(k.get("name", kind)))
	return ship


# The look of a foe (here and on every machine that sees her come in).
func dress(ship: Node3D) -> void:
	var k: Dictionary = rules.cfg["kinds"].get(String(ship.get("state").get("foe", "")), {})
	var c: Array = k.get("sails", [0.15, 0.12, 0.12])
	ship.call("dress_foe", Color(float(c[0]), float(c[1]), float(c[2])))


# Host: one frame of a foe's sailing and gunnery (called by the fleet before her step).
func drive(ship: Node3D, _delta: float) -> void:
	var st: Dictionary = ship.get("state")
	if bool(st.get("sinking", false)):
		return
	var here := Vector2(float(st["x"]), float(st["z"]))
	var struck := crews.is_struck(ship)  # her deck cleared: she drifts, guns silent (till nobody is near)
	var best: Dictionary = {}
	var best_d := INF
	for who: Dictionary in players():
		var d := here.distance_to(who["at"])
		if d < best_d:
			best_d = d
			best = who
	if best.is_empty() or best_d > float(rules.cfg["lose_m"]):
		_fleet.call("remove_ship", ship)  # nobody near: she sails away
		return
	var target_ship: Node3D = best["ship"]
	var target: Vector2 = best["at"]
	var vel := Vector2.ZERO
	if target_ship != null:
		var ts: Dictionary = target_ship.get("state")
		target = Vector2(float(ts["x"]), float(ts["z"]))
		vel = Vector2(-sin(float(ts["yaw"])), -cos(float(ts["yaw"]))) * float(ts["speed"])
	if struck:
		st["rudder"] = 0.0
		st["stage"] = 0
		return
	var plan := pirate.plan(st, target, vel, crews.keep_for(ship))
	crews.consider(ship, target_ship, plan)
	st["rudder"] = float(plan["rudder"])
	st["stage"] = _best_stage(ship, float(plan["want"]), String(plan["mode"]))
	if crews.picking_up(ship) and String(plan["mode"]) != "flee":
		st["stage"] = 1  # heave to for a man overboard (sails furled)
	last = "%s d %.0f m, side %s, rudder %.2f, stage %d, speed %.1f" % [plan["mode"], float(plan["d"]), "starboard" if float(plan["side"]) > 0.0 else "port", float(plan["rudder"]), int(st["stage"]), float(st["speed"])]
	if String(plan["mode"]) != "flee" and float(plan["d"]) <= float(rules.cfg["pirate"]["fire_range_m"]) and not crews.boarding(ship) \
		and (not SeaGhosts.is_ghost(ship, rules.cfg["kinds"]) or ghosts.ready_to_fire(ship)):  # a ghost turns solid first
		var aim_at: Vector3 = target_ship.call("deck_spot", [0.0, 0.0], -0.6) if target_ship != null else _sea.call("world_of", Vector3(target.x, 0.0, target.y))
		var flight := float(plan["d"]) / 85.0
		aim_at += Vector3(vel.x, 0.0, vel.y) * flight  # lead her
		_fire(ship, float(plan["side"]), aim_at)


# The fastest of oars and the sails for the heading she wants (half sail while laying alongside to keep station).
func _best_stage(ship: Node3D, want: float, mode: String) -> int:
	var st: Dictionary = ship.get("state")
	var w: Dictionary = ship.get_meta("weather", {})
	var ship_rules: RefCounted = _fleet.get("rules")
	var best := 2
	var best_v := -1.0
	for stage: int in ([2, 3] if mode == "engage" else [2, 4]):
		var trial := st.duplicate()
		trial["yaw"] = want
		trial["stage"] = stage
		var v := float(ship_rules.call("target_speed", trial, float(w.get("wind", 0.3)), float(w.get("wind_dir", 0.0)), 1.0))
		if v > best_v:
			best_v = v
			best = stage
	return best


# Fires the loaded guns on the side she shows the target, one after another (volley_gap apart), with her aim error.
func _fire(ship: Node3D, side: float, point: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < float(_next_gun.get(ship, 0.0)):
		return
	var cannons: Node = _fleet.get("cannons")
	var k: Dictionary = rules.cfg["kinds"].get(String(ship.get("state")["foe"]), {})
	var err := deg_to_rad(float(k.get("aim_error_deg", 4.0)))
	for gun: Dictionary in cannons.call("guns_of", ship):
		if float(gun["side"]) != side or not bool(cannons.call("loaded", ship, int(gun["index"]))):
			continue
		var aim: Vector2 = cannons.call("aim_at", ship, int(gun["index"]), point)
		if is_nan(aim.x):
			continue
		var yaw := aim.x + _rng.randf_range(-err, err)
		var pitch := aim.y + _rng.randf_range(-err, err) * 0.5
		if bool(cannons.call("fire", ship, int(gun["index"]), yaw, pitch, true)):
			volleys += 1
			var net: Node = _fleet.call("_net")
			if net != null:
				net.call("tell_fire", (_fleet.get("ships") as Array).find(ship), int(gun["index"]), yaw, pitch)
			_next_gun[ship] = now + float(rules.cfg["pirate"]["volley_gap"])
			return


# Host: a foe went down: her cargo floats where she sank.
func went_down(ship: Node3D) -> void:
	var st: Dictionary = ship.get("state")
	var k: Dictionary = rules.cfg["kinds"].get(String(st.get("foe", "")), {})
	var region := String((_sea.get("map") as RefCounted).call("region_id_at", float(st["x"]), float(st["z"])))
	flotsam.spill(float(st["x"]), float(st["z"]), String(k.get("loot", "pirate_small")), region)
	sunk += 1
	_next_gun.erase(ship)
	_sea.emit_signal("notice", "The %s went down: her cargo is afloat" % String(k.get("name", "pirate")))


func status() -> String:
	var parts := PackedStringArray()
	for ship: Node3D in foes():
		var st: Dictionary = ship.get("state")
		parts.append("%s hull %.0f/%.0f at (%.0f, %.0f)%s" % [String(st["foe"]), float(st["hull"]), float(st["hull_max"]), float(st["x"]), float(st["z"]), " STRUCK" if bool(st.get("struck", false)) else ""])
	return "foes [%s], rolled %d, came %d, sunk %d, volleys %d, last '%s'; %s; %s; %s; %s; %s; %s" % [", ".join(parts), rolled, came, sunk, volleys, last, flotsam.status(), crews.status(), sharks.status(), serpent.status(), ghosts.status(), drowned.status() + "; " + beasts.status() + "; " + uboat.status()]
