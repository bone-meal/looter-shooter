# Purpose: the friendly / odd SEA EVENTS (sea step 13d; plan diary/DESIGN_REGION1.md 13d), rolled by the HOST like the
# encounters but for nicer things, for a player at sea outside the home port's waters:
#   MERCHANT RAFT  a trader's raft comes alongside (keep_m off the nearest player) and stays a while: [F] near her opens
#                  her goods (game/merchant_window.gd); each player pays his own doubloons, a few of each per player.
#   CASTAWAY       a man on a broken spar: [F] from a ship within haul_m (or swim to him) and the host puts him on
#                  that ship's deck (he SITS on a sea chest there; in the water he WAVES both arms while a player is
#                  within wave_m); sail him within deliver_m of the home port and he moves into the town (game/
#                  sea_town.gd castaways, game/town_people.gd shows him there), everyone aboard gets a reward. A ship
#                  that sinks under him puts him back on the water.
#   BOTTLE         a message in a bottle afloat ahead (game/sea_flotsam.gd piece, loot "bottle"): whoever takes it
#                  reads the next riddle of the region he has not read (read_bottle, on his own machine): its cache, a
#                  hidden salvage spot, is pinned on his chart and starts bubbling for him (game/sea_salvage.gd).
#   (sea step 13 R2e) each region has its own raft goods and castaways: region 2's sail to LANTERNWICK and live
#   there; MARSH LIGHTS (region 2, at night or in fog: game/sea_marsh_lights.gd) lead a ship to a cache or a Fogmaw.
#   WHALE POD      3-4 whales pass close by along a line: round them the sea calms on every machine (sea_world.calm),
#                  diving near them brings up finds quicker for a while (sea_salvage.wake_until), and the host leaves
#                  their wake's flotsam where they passed closest.
# SOLID (director): the raft, the castaway's spar and each whale carry an AnimatableBody3D on the world layer
# (group "sea_soft": a ship's bow probe stops her against one without hull damage, game/sea_ships.gd); a whale is
# solid only while near the surface.
# Online: the host sends the events at 10 Hz with the fleet (game/net_sea.gd _events_down), its notices as events
# (tell_sea_event, shown near them), a client's haul asks the host (request_sea_event).
# Dependencies: core/sea/event_rules.gd, data/sea/events.json, data/sea/writing/events_r1.txt + events_r2.txt,
# game/sea_marsh_lights.gd, game/merchant_window.gd,
# game/bottle_note.gd, game/npc_body.gd, game/body_motion.gd, game/fantasy_models.gd, game/fx_kit.gd, core/gun_gen.gd,
# core/gun_stats.gd, core/item_level.gd, core/sea/threat_rules.gd; the sea world (ships + foes: players, flotsam,
# rules; town, salvage, chart, port, map, weather, world_of, local_of, water_height, notice).
extends Node3D

const EventRules = preload("res://core/sea/event_rules.gd")
const NpcBody = preload("res://game/npc_body.gd")
const BodyMotion = preload("res://game/body_motion.gd")
const DancePoses = preload("res://game/dance_poses.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const FxKit = preload("res://game/fx_kit.gd")
const GunGen = preload("res://core/gun_gen.gd")
const GunStats = preload("res://core/gun_stats.gd")
const ItemLevel = preload("res://core/item_level.gd")
const Threat = preload("res://core/sea/threat_rules.gd")
const MerchantWindow = preload("res://game/merchant_window.gd")
const BottleNote = preload("res://game/bottle_note.gd")
const MarshLights = preload("res://game/sea_marsh_lights.gd")
const MODELS := "res://assets/models/sea/"

var rules: EventRules
var events := {}  # id -> {"kind", "x", "z", "yaw", "t", ...} (host's; a client's copy from the host)
var paused := false  # dev: no rolls of its own
var calm := 1.0  # this machine: the swell's share near whales (sea_world eases toward it)
var counts := {}  # dev / checks: kind -> how many came; "bought", "hauled", "home", "read", "faded", "wake"
var last := ""
var window := MerchantWindow.new()
var note := BottleNote.new()
var lights := MarshLights.new()  # (sea step 13 R2e) the marsh lights' wisps, steps and drawing
var _sea: Node3D
var _player: CharacterBody3D
var _rng := RandomNumberGenerator.new()
var _check := 0.0
var _last_event := -1e9
var _next_id := 1
var _nodes := {}  # id -> {"root": Node3D, "body": Node3D (merchant / castaway), "whales": [[Node3D, CPUParticles3D]]}
var _seen := {}  # id -> true: its notice was shown here
var _waked := {}  # id -> true: the wake notice was shown here
var _bought := {}  # "event id:stock index" -> count, this player's buys from that raft
var _asked := {}  # event id -> time (a client's haul ask, once a second)
var _clock := 0.0
var _sent_empty := true


func setup(sea_world: Node3D, player: CharacterBody3D, layer: CanvasLayer) -> void:
	_sea = sea_world
	_player = player
	var writing := FileAccess.get_file_as_string("res://data/sea/writing/events_r1.txt") + "\n" + FileAccess.get_file_as_string("res://data/sea/writing/events_r2.txt")
	rules = EventRules.new(JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/events.json")), writing)
	lights.events = self
	add_child(lights)
	_rng.randomize()
	_check = float(rules.cfg["check_s"])
	window.events = self
	layer.add_child(window)
	note.events = self
	layer.add_child(note)


func _fleet() -> Node3D:
	return _sea.get("ships")


func _foes() -> Node:
	return _fleet().get("foes")


func _net() -> Node:
	return _fleet().call("_net")


func _host() -> bool:
	var net := _net()
	return net == null or not bool(net.call("is_client"))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func session() -> Node:
	return get_tree().get_first_node_in_group("game_session")


# --- every frame ---

func _process(delta: float) -> void:
	if not bool(_sea.call("running")) or delta <= 0.0:
		return
	_clock += delta
	if _host():
		_host_step(delta)
	_draw(delta)
	_near(delta)


func _host_step(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = float(rules.cfg["check_s"])
		if not paused and events.size() < int(rules.cfg["max_active"]) and _now() - _last_event > float(rules.cfg["min_gap_s"]) and _rng.randf() < float(rules.cfg["chance"]):
			roll("")
	for id: int in events.keys():
		var e: Dictionary = events[id]
		e["t"] = float(e["t"]) + delta
		match String(e["kind"]):
			"merchant":
				_merchant_step(id, e, delta)
			"castaway":
				_castaway_step(id, e, delta)
			"whales":
				_whales_step(id, e, delta)
			"marsh_lights":
				lights.host_step(id, e, delta)


# Host / dev: an event for a random player at sea (kind "" = rolled). Returns what came ("" = nothing).
func roll(kind: String) -> String:
	var list: Array = _foes().call("players")
	if list.is_empty():
		return ""
	var who: Dictionary = list[_rng.randi() % list.size()]
	var at: Vector2 = who["at"]
	if kind == "" and bool((_foes().get("rules") as RefCounted).call("in_safe_waters", at.x, at.y)):
		return ""
	var region := String((_sea.get("map") as RefCounted).call("region_id_at", at.x, at.y))
	var weather: Dictionary = _sea.call("weather_at", Vector3(at.x, 0.0, at.y))
	if kind == "":
		kind = rules.pick(region, String(weather.get("kind", "calm")), _castaway_free(region) != "", _rng.randf(), _dark(weather))
	for e: Dictionary in events.values():
		if String(e["kind"]) == kind:
			return ""  # (one of each at a time)
	var way := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
	var on: Node3D = who["ship"]
	if on != null:
		var st: Dictionary = on.get("state")
		way = Vector2(-sin(float(st["yaw"])), -cos(float(st["yaw"])))
	var ahead := way.rotated(_rng.randf_range(-0.45, 0.45))
	match kind:
		"merchant":
			var c: Dictionary = rules.cfg["merchant"]
			var p := at + ahead * _rng.randf_range(float(c["spawn_m"][0]), float(c["spawn_m"][1]))
			var names: Array = c["names"]
			var key := rules.stock_key(region)
			_add({"kind": "merchant", "x": p.x, "z": p.y, "yaw": 0.0, "t": 0.0, "mode": "come", "name": String(names[_rng.randi() % names.size()]), "offers": rules.offers(_rng, key), "stock": key})
		"castaway":
			var who_id := _castaway_free(region)
			if who_id == "":
				return ""
			var c2: Dictionary = rules.cfg["castaway"]
			var p2 := at + ahead * _rng.randf_range(float(c2["spawn_m"][0]), float(c2["spawn_m"][1]))
			_add({"kind": "castaway", "x": p2.x, "z": p2.y, "yaw": _rng.randf() * TAU, "t": 0.0, "who": who_id, "ship": -1, "port": rules.castaway_port(who_id)})
		"bottle":
			var c3: Dictionary = rules.cfg["bottle"]
			var p3 := at + ahead * _rng.randf_range(float(c3["ahead_m"][0]), float(c3["ahead_m"][1]))
			(_foes().get("flotsam") as Node).call("add_one", p3.x, p3.y, "flotsam_bottle", "bottle", region)
			tell("bottle_seen", p3.x, p3.y, "", -1)
		"whales":
			var c4: Dictionary = rules.cfg["whales"]
			var pass_way := Vector2(-ahead.y, ahead.x) if _rng.randf() < 0.5 else Vector2(ahead.y, -ahead.x)  # (they cross his bow)
			var side := _rng.randf_range(float(c4["pass_m"][0]), float(c4["pass_m"][1]))
			var line: Array = rules.pod_line(at + ahead * 60.0, pass_way, side * (1.0 if _rng.randf() < 0.5 else -1.0))
			var start: Vector2 = line[0]
			_add({"kind": "whales", "x": start.x, "z": start.y, "yaw": atan2(-pass_way.x, -pass_way.y), "t": 0.0, "n": _rng.randi_range(int(c4["count"][0]), int(c4["count"][1])), "spilled": false, "region": region})
		"marsh_lights":
			var ml: Dictionary = lights.make(at, ahead, region, _rng)
			_add(ml)
			tell("marsh_lights_come", float(ml["x"]), float(ml["z"]), "", -1)
		_:
			return ""
	counts[kind] = int(counts.get(kind, 0)) + 1
	_last_event = _now()
	last = "%s for a player at (%.0f, %.0f)" % [kind, at.x, at.y]
	return kind


func _add(e: Dictionary) -> void:
	events[_next_id] = e
	_next_id += 1


func _castaway_free(region := "") -> String:
	var out_now: Array = []
	for e: Dictionary in events.values():
		if String(e["kind"]) == "castaway":
			out_now.append(String(e["who"]))
	var town: Node = _sea.get("town")
	return rules.next_castaway(town.get("castaways") if town != null else [], out_now, region)


# Night or fog (the marsh lights come only then).
func _dark(weather: Dictionary) -> bool:
	if String(weather.get("kind", "")) in ["fog", "mist"]:
		return true
	var clock: RefCounted = (_sea.get("look") as RefCounted).get("clock")
	return clock != null and float(clock.call("daylight", clock.call("day_part", float(_sea.call("seconds"))))) < 0.25


func _nearest(at: Vector2) -> Array:  # [distance, player at] of the nearest player at sea
	var best := INF
	var where := at
	for who: Dictionary in _foes().call("players"):
		var d := (who["at"] as Vector2).distance_to(at)
		if d < best:
			best = d
			where = who["at"]
	return [best, where]


func _merchant_step(id: int, e: Dictionary, delta: float) -> void:
	var c: Dictionary = rules.cfg["merchant"]
	var here := Vector2(float(e["x"]), float(e["z"]))
	var near: Array = _nearest(here)
	var d := float(near[0])
	var to: Vector2 = (near[1] as Vector2) - here
	if String(e["mode"]) != "go" and (float(e["t"]) > float(c["stay_s"]) or d > float(c["leave_m"])):
		e["mode"] = "go"
		e["go"] = 0.0
		tell("merchant_goes", here.x, here.y, String(e["name"]), -1)
	if String(e["mode"]) == "go":
		e["go"] = float(e["go"]) + delta
		var off := -to.normalized() if to.length() > 0.1 else Vector2(1.0, 0.0)
		_move(e, off, float(c["speed"]) * delta)
		if float(e["go"]) > float(c["go_s"]):
			events.erase(id)
		return
	if d > float(c["keep_m"]) and d < INF:
		_move(e, to.normalized(), minf(float(c["speed"]) * delta, d - float(c["keep_m"])))
		e["mode"] = "come"
	else:
		e["mode"] = "wait"
		if to.length() > 0.1:
			e["yaw"] = lerp_angle(float(e["yaw"]), atan2(-to.x, -to.y), delta * 0.5)  # her front (the counter) to the player


func _move(e: Dictionary, way: Vector2, step: float) -> void:
	if step <= 0.0 or way.length() < 0.5:
		return
	e["x"] = float(e["x"]) + way.x * step
	e["z"] = float(e["z"]) + way.y * step
	e["yaw"] = lerp_angle(float(e["yaw"]), atan2(-way.x, -way.y), 0.05)


func _castaway_step(id: int, e: Dictionary, delta: float) -> void:
	var c: Dictionary = rules.cfg["castaway"]
	var ship: Node3D = e.get("ship_node", null)
	if ship != null:
		if not is_instance_valid(ship) or bool((ship.get("state") as Dictionary).get("sinking", false)):  # she went down: he is back in the water
			e.erase("ship_node")
			e["ship"] = -1
			e["t"] = 0.0
			tell("castaway_lost", float(e["x"]), float(e["z"]), "", -1)
			return
		var st: Dictionary = ship.get("state")
		e["x"] = float(st["x"])
		e["z"] = float(st["z"])
		e["ship"] = (_fleet().get("ships") as Array).find(ship)
		var dock: Array = _dock_of(String(e.get("port", "home")))
		if Vector2(float(st["x"]), float(st["z"])).distance_to(Vector2(float(dock[0]), float(dock[1]))) < float(c["deliver_m"]):
			var town: Node = _sea.get("town")
			if town != null:
				town.call("add_castaway", String(e["who"]))
			counts["home"] = int(counts.get("home", 0)) + 1
			tell("castaway_home", float(e["x"]), float(e["z"]), String(e["who"]), int(e["ship"]))
			events.erase(id)
		return
	var wind_dir := float((_sea.call("weather_at", Vector3(float(e["x"]), 0.0, float(e["z"]))) as Dictionary).get("wind_dir", 0.0))
	e["x"] = float(e["x"]) - sin(wind_dir) * float(c["drift_mps"]) * delta
	e["z"] = float(e["z"]) - cos(wind_dir) * float(c["drift_mps"]) * delta
	if float(e["t"]) > float(c["lost_s"]) and float(_nearest(Vector2(float(e["x"]), float(e["z"])))[0]) > 600.0:
		events.erase(id)  # (nobody came: he drifts out of sight; he is still out there for another day)


# The dock a castaway sails to (data/sea/port.json port by id; the home port if unknown).
func _dock_of(port_id: String) -> Array:
	var ports: Array = (_sea.get("port") as Node).get("rules").cfg["ports"]
	for p: Dictionary in ports:
		if String(p["id"]) == port_id:
			return p["dock"]
	return ports[0]["dock"]


func _whales_step(id: int, e: Dictionary, delta: float) -> void:
	var c: Dictionary = rules.cfg["whales"]
	var yaw := float(e["yaw"])
	var way := Vector2(-sin(yaw), -cos(yaw))
	e["x"] = float(e["x"]) + way.x * float(c["speed"]) * delta
	e["z"] = float(e["z"]) + way.y * float(c["speed"]) * delta
	if not bool(e["spilled"]) and float(e["t"]) > float(c["start_back_m"]) / float(c["speed"]):
		e["spilled"] = true  # where they pass closest, their wake stirs things up
		var back := Vector2(float(e["x"]), float(e["z"])) - way * float(c["spacing_m"])
		(_foes().get("flotsam") as Node).call("spill", back.x, back.y, String(c["wake_loot"]), String(e["region"]))
	if float(e["t"]) > float(c["life_s"]):
		events.erase(id)


# --- acts: a castaway hauled aboard (the host decides; a client asks) ---

# The host: `peer` (1 = the host's own player) at sea point `at` asks to haul castaway `id` onto ship index `ship_i`.
func host_haul(id: int, ship_i: int, at: Vector2) -> bool:
	var e: Dictionary = events.get(id, {})
	var ships: Array = _fleet().get("ships")
	if e.is_empty() or String(e["kind"]) != "castaway" or e.has("ship_node") or ship_i < 0 or ship_i >= ships.size():
		return false
	var ship: Node3D = ships[ship_i]
	var st: Dictionary = ship.get("state")
	var here := Vector2(float(e["x"]), float(e["z"]))
	if st.has("foe") or bool(st.get("sinking", false)) or at.distance_to(here) > float(rules.cfg["castaway"]["haul_m"]) + 4.0 or Vector2(float(st["x"]), float(st["z"])).distance_to(here) > 60.0:
		return false
	e["ship_node"] = ship
	e["ship"] = ship_i
	counts["hauled"] = int(counts.get("hauled", 0)) + 1
	tell("castaway_aboard", here.x, here.y, String(e["who"]), ship_i)
	return true


# --- notices (and for a castaway's homecoming, the reward) on every machine ---

func tell(key: String, x: float, z: float, arg: String, ship_i: int) -> void:
	var net := _net()
	if net != null:
		net.call("tell_sea_event", key, x, z, arg, ship_i)
	heard(key, x, z, arg, ship_i)


func heard(key: String, x: float, z: float, arg: String, ship_i: int) -> void:
	var me: Vector3 = _sea.call("local_of", _player.global_position)
	var near := Vector2(me.x, me.z).distance_to(Vector2(x, z)) <= float(rules.cfg["notice_m"])
	if key == "castaway_home":
		var ships: Array = _fleet().get("ships")
		var mine: Node3D = _fleet().get("helm_ship") if _fleet().get("helm_ship") != null else _fleet().call("ship_aboard")
		var aboard: bool = mine != null and ship_i >= 0 and ship_i < ships.size() and ships[ship_i] == mine
		_notice(rules.notice_at(key, rules.castaway_port(arg)) % rules.name_of("castaways", arg))
		if aboard or near:
			var pay := int(rules.cfg["castaway"]["reward_doubloons"])
			var s := session()
			if s != null and s.has_method("doubloons"):
				(s.call("doubloons") as RefCounted).call("add", pay)
			_notice("%s: \"%s\" (+%d doubloons)" % [rules.name_of("castaways", arg), rules.line_of("castaways", arg, 2), pay])
		return
	if not near:
		return
	if key == "castaway_aboard":
		_notice("%s: \"%s\"" % [rules.name_of("castaways", arg), rules.line_of("castaways", arg, 1)])
		_notice(rules.notice_at(key, rules.castaway_port(arg)))
		return
	elif key == "merchant_goes":
		_notice("%s: \"%s\"" % [rules.name_of("merchants", arg), rules.line_of("merchants", arg, 2)])
		if window.visible and window.event_id >= 0 and not events.has(window.event_id):
			close_window()
	_notice(rules.notice(key))


func _notice(text: String) -> void:
	if bool(_sea.get("inside")) and text != "":
		_sea.emit_signal("notice", text)


# --- this player near an event: notices once, the calm round whales, their wake ---

func _near(_delta: float) -> void:
	var me: Vector3 = _sea.call("local_of", _player.global_position)
	var here := Vector2(me.x, me.z)
	var want := 1.0
	var c: Dictionary = rules.cfg["whales"]
	for id: int in events:
		var e: Dictionary = events[id]
		var at := Vector2(float(e["x"]), float(e["z"]))
		var d := at.distance_to(here)
		if not _seen.has(id) and d <= float(rules.cfg["notice_m"]):
			_seen[id] = true
			match String(e["kind"]):
				"merchant":
					_notice(rules.notice("merchant_comes"))
				"castaway":
					if int(e["ship"]) < 0:
						_notice(rules.notice("castaway_seen"))
				"whales":
					_notice(rules.notice("whales_come"))
		if String(e["kind"]) != "whales":
			continue
		var nearest := INF
		for k in int(e["n"]):
			nearest = minf(nearest, _whale_at(e, k).distance_to(here))
		if nearest < float(c["calm_m"]):
			want = minf(want, lerpf(float(c["calm_swell"]), 1.0, clampf((nearest - float(c["calm_m"]) * 0.5) / (float(c["calm_m"]) * 0.5), 0.0, 1.0)))
		if nearest < float(c["wake_m"]):
			var salvage: Node = _sea.get("salvage")
			salvage.set("wake_until", _now() + float(c["wake_s"]))
			if not _waked.has(id):
				_waked[id] = true
				counts["wake"] = int(counts.get("wake", 0)) + 1
				_notice(rules.notice("whales_wake"))
	calm = want


# Whale k of a pod (sea x, z): in a line behind the leader, a little to the side.
func _whale_at(e: Dictionary, k: int) -> Vector2:
	var yaw := float(e["yaw"])
	var way := Vector2(-sin(yaw), -cos(yaw))
	var across := Vector2(-way.y, way.x)
	var sp := float(rules.cfg["whales"]["spacing_m"])
	return Vector2(float(e["x"]), float(e["z"])) - way * sp * float(k) + across * (sin(float(k) * 2.3) * 7.0)


# --- the interact key ---

func _my_ship() -> Node3D:
	return _fleet().get("helm_ship") if _fleet().get("helm_ship") != null else _fleet().call("ship_aboard")


# What the player can do here: [kind, event id] or [] (the nearest when several are in reach).
func spot_here() -> Array:
	if window.visible or note.visible:
		return []
	var me: Vector3 = _sea.call("local_of", _player.global_position)
	var here := Vector2(me.x, me.z)
	var swimming := bool(_player.get("swimming"))
	var best: Array = []
	var best_d := INF
	for id: int in events:
		var e: Dictionary = events[id]
		var at := Vector2(float(e["x"]), float(e["z"]))
		match String(e["kind"]):
			"merchant":
				var body: Node3D = (_nodes.get(id, {}) as Dictionary).get("body", null)
				var spot := body.global_position if body != null else (_sea.call("world_of", Vector3(at.x, 0.0, at.y)) as Vector3)
				var reach := float(rules.cfg["merchant"]["swim_talk_m"] if swimming else rules.cfg["merchant"]["talk_m"])
				var d := Vector2(spot.x, spot.z).distance_to(Vector2(_player.global_position.x, _player.global_position.z))
				if d <= reach and d < best_d:
					best = ["trade", id]
					best_d = d
			"castaway":
				if int(e["ship"]) >= 0:
					continue
				var d2 := at.distance_to(here)
				if ((swimming and d2 <= float(rules.cfg["castaway"]["swim_m"])) or (not swimming and _my_ship() != null and d2 <= float(rules.cfg["castaway"]["haul_m"]))) and d2 < best_d:
					best = ["haul", id]
					best_d = d2
	return best


func prompt(key: String) -> String:
	var spot := spot_here()
	if spot.is_empty():
		return ""
	var e: Dictionary = events[int(spot[1])]
	if spot[0] == "trade":
		return "[%s] Trade with %s (merchant raft)" % [key, rules.name_of("merchants", String(e["name"]))]
	return "[%s] %s" % [key, "Help the castaway to a ship" if bool(_player.get("swimming")) else "Throw the castaway a line"]


func interact() -> bool:
	var spot := spot_here()
	if spot.is_empty():
		return false
	var id := int(spot[1])
	if spot[0] == "trade":
		open_window(id)
		return true
	haul(id)
	return true


# This player hauls castaway `id` aboard his ship (swimming: the nearest of ours within 60 m).
func haul(id: int) -> void:
	var ship := _my_ship()
	var me: Vector3 = _sea.call("local_of", _player.global_position)
	if ship == null:
		var best := 60.0
		for s: Node3D in _fleet().get("ships"):
			var st: Dictionary = s.get("state")
			var d := Vector2(float(st["x"]), float(st["z"])).distance_to(Vector2(me.x, me.z))
			if not st.has("foe") and d < best:
				best = d
				ship = s
	if ship == null:
		_notice("No ship near to haul the castaway onto")
		return
	var ship_i := (_fleet().get("ships") as Array).find(ship)
	if _host():
		if not host_haul(id, ship_i, Vector2(me.x, me.z)):
			_notice("Too far: bring the ship closer")
		return
	if _now() - float(_asked.get(id, -10.0)) > 1.0:
		_asked[id] = _now()
		_net().call("request_sea_event", "haul", id, ship_i)


# --- the merchant's window (all of it the player's own money) ---

func open_window(id: int) -> void:
	window.open_for(id)
	_player.set("controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var e: Dictionary = events[id]
	window.said = "%s: \"%s\"" % [rules.name_of("merchants", String(e["name"])), rules.line_of("merchants", String(e["name"]), 1)]


func close_window() -> void:
	window.close()
	note.close()
	_player.set("controls_enabled", true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# The goods of raft `id`: [[stock index, entry, label, price, left for this player]].
func goods(id: int) -> Array:
	var e: Dictionary = events.get(id, {})
	var out: Array = []
	if e.is_empty():
		return out
	for idx: Variant in e["offers"]:
		var entry: Dictionary = rules.stock_entry(int(idx), _stock_of(e))
		if entry.is_empty():
			continue
		var label := ""
		if entry.has("gun"):
			var tier: Dictionary = (_player.get("gun_db") as RefCounted).call("tier", String(entry["gun"]))
			label = "Rolled gun of these waters: %s" % String(tier.get("name", entry["gun"]))
		else:
			label = String((_sea.get("port") as Node).call("item_name", String(entry["item"])))
			if int(entry.get("count", 1)) > 1:
				label += "  x%d" % int(entry["count"])
		var left := int(entry.get("limit", 1)) - int(_bought.get("%d:%d" % [id, int(idx)], 0))
		out.append([int(idx), entry, label, int(entry["doubloons"]), left])
	return out


# A raft's stock list: the host's own, a client's from where the raft is (its region).
func _stock_of(e: Dictionary) -> String:
	if e.has("stock"):
		return String(e["stock"])
	e["stock"] = rules.stock_key(String((_sea.get("map") as RefCounted).call("region_id_at", float(e["x"]), float(e["z"]))))
	return String(e["stock"])


func buy(id: int, idx: int) -> String:
	var e: Dictionary = events.get(id, {})
	if e.is_empty() or not (e["offers"] as Array).has(idx) and not (e["offers"] as Array).has(float(idx)):
		return "She has gone"
	var entry := rules.stock_entry(idx, _stock_of(e))
	var key := "%d:%d" % [id, idx]
	if int(_bought.get(key, 0)) >= int(entry.get("limit", 1)):
		return "\"That's all I have of that, dear\""
	var said := ""
	if entry.has("gun"):
		var s := session()
		var purse: RefCounted = s.call("doubloons") if s != null else null
		if purse == null or not bool(purse.call("spend", int(entry["doubloons"]))):
			return "Not enough doubloons"
		var db: RefCounted = _player.get("gun_db")
		var region := String((_sea.get("map") as RefCounted).call("region_id_at", float(e["x"]), float(e["z"])))
		var band := ItemLevel.region_band(EventRules.region_number(region))
		var gun := GunGen.generate(db, _rng, Threat.ng_luck(), "", String(entry["gun"]), "", Threat.loot_level(ItemLevel.roll(_rng, band.x, band.y)))
		if not bool((_player.get("inventory") as RefCounted).call("add_gun", gun)):
			purse.call("add", int(entry["doubloons"]))
			return "No room in the backpack"
		_player.call("refresh_held")
		said = "Bought %s" % GunStats.display_name(db, gun)
	else:
		said = String((_sea.get("port") as Node).call("buy", entry))
		if not said.begins_with("Bought"):
			return said
	_bought[key] = int(_bought.get(key, 0)) + 1
	counts["bought"] = int(counts.get("bought", 0)) + 1
	var s2 := session()
	if s2 != null and s2.has_method("save_profile"):
		s2.call("save_profile")
	return said


# --- a message in a bottle, read on the taker's machine (game/sea_flotsam.gd grant, loot "bottle") ---

func read_bottle(region: String) -> void:
	var salvage: Node = _sea.get("salvage")
	var book: RefCounted = salvage.get("book")
	var found: Dictionary = book.get("found")
	var r := rules.next_riddle(region, func(id: String) -> bool: return found.has("riddle:" + id))
	if r.is_empty():
		var pay := int(rules.cfg["bottle"]["faded_doubloons"])
		var s := session()
		if s != null and s.has_method("doubloons"):
			(s.call("doubloons") as RefCounted).call("add", pay)
		counts["faded"] = int(counts.get("faded", 0)) + 1
		note.show_note("A message in a bottle", rules.notice("bottle_faded"), "+%d doubloons" % pay)
		_open_note()
		return
	found["riddle:" + String(r["id"])] = true
	counts["read"] = int(counts.get("read", 0)) + 1
	var spot: Dictionary = salvage.call("spot_of_hoard", String(r["hoard"]))
	if not spot.is_empty():
		var at := Vector2(float(spot["at"][0]), float(spot["at"][1]))
		var chart: RefCounted = _sea.get("chart")
		var pinned := false
		for pin: Vector2 in chart.get("pins"):
			pinned = pinned or pin.distance_to(at) < 30.0
		if not pinned:
			chart.call("toggle_pin", at)
	salvage.call("refresh_found")
	note.show_note("A message in a bottle", rules.riddle_text(String(r["id"])), rules.notice("riddle_pinned"))
	_open_note()
	last = "read riddle %s" % String(r["id"])
	var s2 := session()
	if s2 != null and s2.has_method("save_profile"):
		s2.call("save_profile")  # (the logbook keeps what was read)


func _open_note() -> void:
	_player.set("controls_enabled", false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- drawing (every machine) ---

func _draw(delta: float) -> void:
	for id: int in _nodes.keys():
		if not events.has(id):
			(_nodes[id]["root"] as Node).queue_free()
			_nodes.erase(id)
	for id: int in events:
		var e: Dictionary = events[id]
		if not _nodes.has(id):
			_nodes[id] = _build(e)
		var n: Dictionary = _nodes[id]
		match String(e["kind"]):
			"merchant":
				_place_raft(n, e, delta)
			"castaway":
				_place_castaway(n, e, delta)
			"whales":
				_place_whales(n, e, delta)
			"marsh_lights":
				lights.place(n, e, delta, _clock)


func _model(name_id: String) -> Node3D:
	var path := MODELS + name_id + ".gltf"
	var made: Node3D
	if ResourceLoader.exists(path):
		made = (load(path) as PackedScene).instantiate() as Node3D
		for found in made.find_children("*", "MeshInstance3D", true, false):
			FantasyModels.dress((found as MeshInstance3D).mesh)
	else:
		made = MeshInstance3D.new()
		(made as MeshInstance3D).mesh = BoxMesh.new()
	return made


func _person(look: Array) -> Node3D:
	var body := NpcBody.build({"gender": String(look[1]), "height": 1.0, "weight": 1.0, "bust": 0.3, "glutes": 0.3, "skin": _rng.randi_range(0, 5), "hair": String(look[2]),
		"hair_color": ["#2b1d14", "#553322", "#8a5a2b", "#c9a26b", "#1a1a1a"][_rng.randi_range(0, 4)], "face": "gentle_smile", "outfit": String(look[0])})
	return body


func _plate(body: Node3D, words: String) -> void:
	var plate := Label3D.new()
	plate.text = words
	plate.font_size = 30
	plate.pixel_size = 0.005
	plate.outline_size = 8
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.position.y = 2.05
	body.add_child(plate)


# A solid body of boxes / a capsule (model space x, y, f; the game's -z is f) that players stand on and ships stop at.
func _solid(parent: Node3D, shapes: Array) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.sync_to_physics = false
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("sea_soft")
	for s: Array in shapes:
		var col := CollisionShape3D.new()
		if String(s[0]) == "box":
			var box := BoxShape3D.new()
			box.size = Vector3(float(s[1][0]), float(s[1][1]), float(s[1][2]))
			col.shape = box
		else:  # ["capsule", radius, length]: lying along f
			var cap := CapsuleShape3D.new()
			cap.radius = float(s[1])
			cap.height = float(s[2])
			col.shape = cap
			col.rotation.x = PI * 0.5
		col.position = Vector3(float(s[-1][0]), float(s[-1][1]), -float(s[-1][2]))
		body.add_child(col)
	parent.add_child(body)
	return body


func _build(e: Dictionary) -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var out := {"root": root}
	match String(e["kind"]):
		"marsh_lights":
			lights.build(root, e, out)
		"merchant":
			var raft := _model("merchant_raft")
			root.add_child(raft)
			_solid(root, [["box", [4.4, 0.55, 6.3], [0.0, 0.02, 0.0]], ["box", [3.0, 0.9, 0.75], [0.0, 0.75, 1.35]], ["box", [0.3, 4.6, 0.3], [0.0, 2.6, -1.2]]])  # logs and deck, the counter, the mast
			var looks: Dictionary = rules.cfg["merchant"]["looks"]
			var body := _person(looks.get(String(e["name"]), ["sailor", "female", "bun"]))
			raft.add_child(body)
			var stand := raft.find_child("Stand", true, false) as Node3D
			body.position = stand.position if stand != null else Vector3(0.0, 0.3, -0.55)
			body.rotation.y = PI  # (bodies face -z; the counter is at the raft's front, -z in the game)
			_plate(body, "%s\nmerchant" % rules.name_of("merchants", String(e["name"])))
			out["body"] = body
		"castaway":
			var spar := _model("castaway_spar")
			root.add_child(spar)
			out["spar_body"] = _solid(root, [["capsule", 0.26, 6.6, [0.0, 0.05, -0.1]], ["box", [0.25, 0.25, 3.0], [-1.15, 0.1, 0.1]]])  # the mast, the yard stump
			var body2 := _person(rules.castaway_look(String(e["who"])))
			root.add_child(body2)
			_plate(body2, rules.name_of("castaways", String(e["who"])))
			out["spar"] = spar
			out["body"] = body2
		"whales":
			var list: Array = []
			for k in int(e["n"]):
				var own: Array[StandardMaterial3D] = []
				var whale: Node3D = FantasyModels.creature("sea_whale", Color(0.1, 0.1, 0.1), own) if FantasyModels.has_creature("sea_whale") else _model("missing")
				whale.scale = Vector3.ONE * (1.0 - 0.12 * float(k % 3))
				root.add_child(whale)
				_solid(whale, [["capsule", 1.15, 9.6, [0.0, 1.1, 0.9]], ["box", [3.6, 0.5, 1.6], [0.0, 0.9, -5.9]]])  # the body, the flukes
				var spout := FxKit.particles(Color(0.95, 0.98, 1.0, 0.85), 40, 1.4, 0.6, 7.0, 25.0, -3.0, false, false)
				spout.emitting = false
				root.add_child(spout)
				list.append([whale, spout, k * 0.31])
			out["whales"] = list
	return out


func _water(at: Vector2) -> float:
	var w: Vector3 = _sea.call("world_of", Vector3(at.x, 0.0, at.y))
	return float(_sea.call("water_height", w)) - float((_sea.call("world_of", Vector3.ZERO) as Vector3).y)


func _place_raft(n: Dictionary, e: Dictionary, delta: float) -> void:
	var root: Node3D = n["root"]
	var at := Vector2(float(e["x"]), float(e["z"]))
	var goal := Vector3(at.x, _water(at) - 0.08, at.y)
	root.position = goal if root.position.distance_to(goal) > 20.0 else root.position.lerp(goal, minf(1.0, delta * 6.0))
	root.rotation = Vector3(sin(_clock * 0.8) * 0.03, lerp_angle(root.rotation.y, float(e["yaw"]), minf(1.0, delta * 3.0)), cos(_clock * 0.7) * 0.03)
	BodyMotion.animate(n["body"], 0.0, 0.0, _clock, false)


func _place_castaway(n: Dictionary, e: Dictionary, delta: float) -> void:
	var root: Node3D = n["root"]
	var spar: Node3D = n["spar"]
	var body: Node3D = n["body"]
	var ships: Array = _fleet().get("ships")
	var ship_i := int(e["ship"])
	var spar_body: AnimatableBody3D = n["spar_body"]
	spar_body.collision_layer = 0 if ship_i >= 0 else 1  # (aboard: the spar is left behind, not solid)
	if ship_i >= 0 and ship_i < ships.size():  # aboard: he sits on a sea chest on her deck toward the stern
		spar.visible = false
		var ship: Node3D = ships[ship_i]
		var half := absf(float((ship.get("spec")["outline"] as Array)[0][0]))
		var spot: Array = rules.cfg["castaway"]["deck_spot"]
		if String(n.get("pose", "")) != "sit":
			n["pose"] = "sit"
			DancePoses.reset(body)
			if body.has_method("hold"):
				body.call("hold", "Sitting_Idle", 0.4)
			_seat(n).visible = true
		body.global_position = ship.call("deck_spot", [float(spot[0]), half * float(spot[1])])
		body.global_rotation = Vector3(0.0, ship.global_rotation.y + PI * 0.5, 0.0)  # (sideways on the deck, looking out over the rail)
		return
	if String(n.get("pose", "")) == "sit":
		n["pose"] = ""
		_seat(n).visible = false
	spar.visible = true
	var at := Vector2(float(e["x"]), float(e["z"]))
	var goal := Vector3(at.x, _water(at) - 0.05, at.y)
	root.position = goal if root.position.distance_to(goal) > 20.0 else root.position.lerp(goal, minf(1.0, delta * 4.0))
	root.rotation = Vector3(sin(_clock * 1.1) * 0.05, float(e["yaw"]), cos(_clock * 0.9) * 0.04)
	var cling := spar.find_child("Cling", true, false) as Node3D
	var near := float(_nearest(at)[0]) < float(rules.cfg["castaway"].get("wave_m", 150.0))
	if near:  # somebody is in sight: both arms up, waving
		DancePoses.apply(body, "wave_arms", _clock * 0.7)
		n["pose"] = "wave"
	else:
		if String(n.get("pose", "")) == "wave":
			DancePoses.reset(body)
			n["pose"] = ""
		BodyMotion.animate(body, 0.0, 0.0, _clock * 1.6, false)
	body.position = (cling.position if cling != null else Vector3(0.6, 0.0, 0.45)) + Vector3(0.0, -1.05, 0.0)  # in the water to his chest
	body.rotation = Vector3.ZERO


# The sea chest the castaway sits on aboard (made once, a child of his body).
func _seat(n: Dictionary) -> MeshInstance3D:
	if n.has("seat"):
		return n["seat"]
	var seat := MeshInstance3D.new()
	var box := BoxMesh.new()
	var c: Dictionary = rules.cfg["castaway"]
	var size: Array = c.get("seat_size", [0.55, 0.46, 0.42])
	box.size = Vector3(float(size[0]), float(size[1]), float(size[2]))
	seat.mesh = box
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.4, 0.27, 0.16)
	seat.material_override = wood
	var at: Array = c.get("seat_at", [0.0, 0.23, 0.12])
	seat.position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	(n["body"] as Node3D).add_child(seat)
	n["seat"] = seat
	return seat


func _place_whales(n: Dictionary, e: Dictionary, delta: float) -> void:
	var c: Dictionary = rules.cfg["whales"]
	var period := float(c["surface_every_s"])
	var share := float(c["surface_share"])
	var yaw := float(e["yaw"])
	for k in (n["whales"] as Array).size():
		var pair: Array = n["whales"][k]
		var whale: Node3D = pair[0]
		var spout: CPUParticles3D = pair[1]
		var at := _whale_at(e, k)
		var u := fposmod(_clock / period + float(pair[2]), 1.0)
		var lift := -6.0
		var pitch := 0.0
		if u < share:  # surfacing: the back rolls up out of the water and down again
			var s := u / share
			lift = lerpf(-2.6, -1.25, sin(s * PI))
			pitch = lerpf(0.12, -0.2, s)
		var goal := Vector3(at.x, _water(at) + lift, at.y)
		whale.position = goal if whale.position.distance_to(goal) > 30.0 else whale.position.lerp(goal, minf(1.0, delta * 2.0))
		whale.rotation = Vector3(pitch, yaw, 0.0)
		whale.visible = lift > -5.0 or u > 0.92
		var solid_w := whale.get_child(whale.get_child_count() - 1) as AnimatableBody3D
		if solid_w != null:
			solid_w.collision_layer = 1 if lift > -4.0 else 0  # (solid near the surface only)
		var tail := whale.find_child("Tail", true, false) as Node3D
		if tail != null:
			tail.rotation.x = sin(_clock * 1.3 + float(k)) * 0.18 + (0.6 * smoothstep(0.75, 1.0, u / share) if u < share else 0.0)
		spout.emitting = u < share * 0.35 and u > share * 0.05
		spout.global_position = whale.global_position + whale.global_basis * Vector3(0.0, 2.3, -4.6)


# --- online ---

func to_net() -> Array:
	var out: Array = []
	for id: int in events:
		var e: Dictionary = events[id]
		var a := ""
		var b := ""
		match String(e["kind"]):
			"merchant":
				a = String(e["name"])
				b = ",".join(PackedStringArray((e["offers"] as Array).map(func(v: Variant) -> String: return str(int(v)))))
			"castaway":
				a = String(e["who"])
				b = str(int(e["ship"]))
			"whales":
				a = str(int(e["n"]))
			"marsh_lights":
				a = str(int(e["n"]))
				b = String(e.get("mode", "lead"))
		out.append([id, String(e["kind"]), snappedf(float(e["x"]), 0.1), snappedf(float(e["z"]), 0.1), snappedf(float(e["yaw"]), 0.01), a, b])
	return out


func should_send() -> bool:
	if not events.is_empty():
		_sent_empty = false
		return true
	if not _sent_empty:
		_sent_empty = true
		return true
	return false


func from_net(list: Array) -> void:
	var seen := {}
	for got: Variant in list:
		if not got is Array or (got as Array).size() < 7:
			continue
		var g: Array = got
		var id := int(g[0])
		var kind := String(g[1]).left(12)
		if not ["merchant", "castaway", "whales", "marsh_lights"].has(kind) or not is_finite(float(g[2])) or not is_finite(float(g[3])):
			continue
		seen[id] = true
		var e: Dictionary = events.get(id, {"kind": kind, "t": 0.0})
		e["x"] = float(g[2])
		e["z"] = float(g[3])
		e["yaw"] = float(g[4])
		match kind:
			"merchant":
				e["name"] = String(g[5]).left(16)
				var offers: Array = []
				for part: String in String(g[6]).left(64).split(",", false):
					offers.append(int(part))
				e["offers"] = offers
			"castaway":
				e["who"] = String(g[5]).left(16)
				e["ship"] = int(g[6])
			"whales":
				e["n"] = clampi(int(g[5]), 1, 6)
			"marsh_lights":
				e["n"] = clampi(int(g[5]), 1, 8)
				e["mode"] = String(g[6]).left(8)
		events[id] = e
	for id: int in events.keys():
		if not seen.has(id):
			events.erase(id)


# The old host left (sea step 12): merchants paddle off, whales swim on out of sight; a castaway on a deck stays
# with that ship (the new host carries him on), one in the water is lost to the current.
func adopt_as_host() -> void:
	for id: int in events.keys():
		var e: Dictionary = events[id]
		if String(e["kind"]) == "castaway" and int(e["ship"]) >= 0 and int(e["ship"]) < (_fleet().get("ships") as Array).size():
			e["ship_node"] = _fleet().get("ships")[int(e["ship"])]
			continue
		events.erase(id)
	_last_event = _now()


func status() -> String:
	var parts: PackedStringArray = []
	var me: Vector3 = _sea.call("local_of", _player.global_position)
	for id: int in events:
		var e: Dictionary = events[id]
		parts.append("%d %s %.0f m%s" % [id, String(e["kind"]), Vector2(float(e["x"]), float(e["z"])).distance_to(Vector2(me.x, me.z)), (" " + String(e.get("mode", ""))) if e.has("mode") else (" ship %d" % int(e["ship"]) if e.has("ship") else "")])
	return "events [%s], calm %.2f, counts %s, last '%s'" % [", ".join(parts), calm, str(counts), last]
