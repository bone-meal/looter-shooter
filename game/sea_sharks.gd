# Purpose: SHARKS (sea step 8c; director: they go for anyone swimming or diving, a wounded swimmer - player or pirate
# - draws more, and Hunting can harpoon them for hides, teeth and meat). The HOST keeps sharks in deep water round
# whoever is in it: each swimmer brings sharks_per_swimmer, a bleeding one (bitten, or a pirate hit) blood_extra more;
# a player at sea on a deck in deep water sees a fin or two circling his ship. A hunting shark circles its swimmer
# closer and closer, then LUNGES and bites (the swimmer's own machine takes the damage: game/net_rounds.gd forwards a
# ghost's blow), swings off and circles again. Sharks are game/enemy.gd bodies made by the wave director (shots, kill
# XP, grenades and skills reach them) under the fleet (sea coordinates), driven here (no physics). A shark killed
# within harvest.window_s of a HARPOON of ours (the harpoon gun: game/shot_bolts.gd marks what it hits) gives our
# Hunting its xp and hides / teeth / meat into the bag (every harpooner's own machine); other kills only the kill.
# A harpooned shark is pinned and hauled toward the shooter. Online: the host sends them (game/net_sea.gd sharks),
# clients show puppets whose hits go to the host.
# Dependencies: data/sea/encounters.json "sharks", data/enemies.json "sea_shark", game/enemy.gd, game/wave_director.gd
# (adopt / forget), the fleet (game/sea_ships.gd: _net), game/sea_crews.gd (pirates in the water), the sea world
# (map, water_height, skills, notice), the player.
extends Node3D

const Threat = preload("res://core/sea/threat_rules.gd")

var cfg: Dictionary
var _threat: Dictionary  # encounters.json "threat" (sea step 8f)
var director: Node
var card: RefCounted
var sharks := {}  # id -> {"enemy", "mode": roam|circle|lunge|off, "target": key, "t", "angle", "radius", "bit": time}
var blood := {}  # swimmer key -> time it bleeds until
var bites := 0  # dev / checks
var spawned := 0
var harvested := 0
var last_harvest := ""
var paused := false  # dev: no spawning of its own
var _next_id := 1
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _stats := {}
var _rng := RandomNumberGenerator.new()
var _pending := {}  # client: id -> damage this frame
var _missing := {}
var _sent_empty := true
var _hitter := 0
var _think := 0.0
var _islands: Array = []


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D, encounters: Dictionary) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	cfg = encounters["sharks"]
	_threat = encounters["threat"]
	_stats = (JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")) as Dictionary)["enemies"]["sea_shark"]
	_rng.randomize()


func _net() -> Node:
	return _fleet.call("_net")


func _host() -> bool:
	var net := _net()
	return net == null or not bool(net.call("is_client"))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _crews() -> Node:
	return get_parent().get("crews")


# Everyone in the water, by key: "me", "g<peer>" (other players), "c<id>" (pirates overboard) -> [body, scene position].
func swimmers() -> Dictionary:
	var out := {}
	if bool(_sea.get("inside")) and bool(_player.get("swimming")):
		out["me"] = _player
	var net := _net()
	if net != null and bool(net.call("active")):
		var ns: Node = net.get("net")
		for id: int in ns.get("roster"):
			var body: Node3D = ns.call("player_node", id)
			if body != null and body != _player and bool(body.get("_swimming")) and body.global_position.x < -10000.0:
				out["g%d" % id] = body
	var crews := _crews()
	if crews != null:
		for id: int in crews.get("men"):
			var m: Dictionary = crews.get("men")[id]
			if m.has("swim") and is_instance_valid(m["enemy"]):
				out["c%d" % id] = m["enemy"]
	return out


# Open water: deep_m clear of every island's reach (data/sea/islands.json pos + radius).
func _deep(at: Vector3) -> bool:
	var here: Vector3 = _sea.call("local_of", at)
	return clear_of_land(here.x, here.z, float(cfg["deep_m"]))


func clear_of_land(x: float, z: float, by: float) -> bool:
	if _islands.is_empty():
		_islands = (JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/islands.json")) as Dictionary)["islands"]
	for isle: Dictionary in _islands:
		if Vector2(x, z).distance_to(Vector2(float(isle["pos"][0]), float(isle["pos"][1]))) < float(isle["radius"]) + by:
			return false
	return float((_sea.get("map") as RefCounted).call("inside_by", x, z)) > 0.0


func _water(at: Vector3) -> float:
	return float(_sea.call("water_height", Vector3(at.x, 0.0, at.z)))


# --- the host's sharks ---

func _process(delta: float) -> void:
	if not bool(_sea.call("running")) or delta <= 0.0:
		return
	_animate(delta)
	if not _host():
		_send_hits()
		return
	_think -= delta
	var swimmers_now := swimmers()
	if _think <= 0.0:
		_think = 0.5
		_spawn_and_assign(swimmers_now)
	for id: int in sharks.keys():
		if sharks.has(id):
			_drive(id, delta, swimmers_now)


func _spawn_and_assign(swimmers_now: Dictionary) -> void:
	var now := _now()
	var want := 0
	var anchors: Array = []  # [key, body]
	for key: String in swimmers_now:
		var body: Node3D = swimmers_now[key]
		if not _deep(body.global_position):
			continue
		want += int(cfg["per_swimmer"]) + (int(cfg["blood_extra"]) if float(blood.get(key, 0.0)) > now else 0)
		anchors.append([key, body])
	if anchors.is_empty() and bool(_sea.get("inside")) and _fleet.call("ship_aboard") != null and _deep(_player.global_position):
		want = int(cfg["roaming"])  # fins round the ship
		anchors.append(["ship", _fleet.call("ship_aboard")])
	want = mini(want, int(cfg["max"]))
	if not paused and sharks.size() < want and not anchors.is_empty():
		var pick: Array = anchors[_rng.randi() % anchors.size()]
		_spawn_near(pick[1])
	for id: int in sharks.keys():  # every shark: a swimmer to hunt (the nearest, bleeding ones first), else roam
		var s: Dictionary = sharks[id]
		var e: Node3D = s["enemy"]
		if not is_instance_valid(e):
			sharks.erase(id)
			continue
		var best := ""
		var best_d := INF
		for pair: Array in anchors:
			if String(pair[0]) == "ship":
				continue
			var d := e.global_position.distance_to((pair[1] as Node3D).global_position) * (0.5 if float(blood.get(pair[0], 0.0)) > now else 1.0)
			if d < best_d and d <= float(cfg["notice_m"]):
				best_d = d
				best = String(pair[0])
		if String(s["mode"]) == "off":
			continue
		if best != "" and String(s["mode"]) == "roam":
			s["mode"] = "circle"
			s["t"] = _rng.randf_range(float(cfg["circle_s"][0]), float(cfg["circle_s"][1]))
		s["target"] = best
		var far := true
		for pair: Array in anchors:
			if e.global_position.distance_to((pair[1] as Node3D).global_position) < float(cfg["leave_m"]):
				far = false
		if far or anchors.is_empty() and s["mode"] != "off":
			_remove(id)


func _spawn_near(anchor: Node3D) -> void:
	if director == null:
		return
	var at := anchor.global_position
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(float(cfg["spawn_m"][0]), float(cfg["spawn_m"][1]))
	var spot := at + Vector3(cos(a) * r, 0.0, sin(a) * r)
	if not _deep(spot):
		return
	var region := String((_sea.get("map") as RefCounted).call("region_id_at", _sea.call("local_of", spot).x, _sea.call("local_of", spot).z))
	var n := maxi(int(region.trim_prefix("region_")), 1)
	var stats := _stats.duplicate()
	stats["max_hp"] = float(stats["max_hp"]) * Threat.player_mult(_threat, n)  # (sea step 8f)
	var e := _make(_next_id, stats, false)
	e.global_position = Vector3(spot.x, _water(spot) - float(cfg["fin_depth"]), spot.z)
	e.set_meta("tier", 4 + 4 * (n - 1))
	e.set_meta("bite", float(cfg["bite"]) * Threat.player_mult(_threat, n))
	sharks[_next_id] = {"enemy": e, "mode": "roam", "target": "", "t": 0.0, "angle": a, "radius": _rng.randf_range(float(cfg["circle_m"][0]), float(cfg["circle_m"][1])) * 2.0, "bit": 0.0, "anchor": anchor}
	_next_id += 1
	spawned += 1


func _make(id: int, stats: Dictionary, puppet: bool) -> Node3D:
	var e: Node3D = director.call("adopt", "sea_shark", stats)
	e.set("puppet", puppet)
	e.set_meta("net_id", id)
	e.set_meta("shark", true)
	_fleet.add_child(e)
	e.set_physics_process(puppet)  # the host drives it here; a puppet glides after the host's word
	e.died.connect(_on_died.bind(id))
	if puppet:
		e.set_meta("host_pays", true)
		e.connect("puppet_hit", func(damage: float) -> void: _pending[id] = float(_pending.get(id, 0.0)) + damage)
	return e


func _remove(id: int) -> void:
	var e: Node3D = sharks[id]["enemy"]
	if is_instance_valid(e):
		director.call("forget", e)
		e.queue_free()
	sharks.erase(id)


# Host: one shark's frame. Roam = a slow ring round its anchor at the fin's depth; circle = round its swimmer, the
# ring closing; lunge = straight at him at speed, a bite within bite_m, then off to circle again.
func _drive(id: int, delta: float, swimmers_now: Dictionary) -> void:
	var s: Dictionary = sharks[id]
	var e: Node3D = s["enemy"]
	if not is_instance_valid(e) or bool(e.get("health").is_dead()):
		sharks.erase(id)
		return
	if String(s["mode"]) == "off":  # (dev: held where it is)
		return
	var now := _now()
	var target: Node3D = swimmers_now.get(String(s["target"]))
	var speed := float(cfg["speed"])
	var goal: Vector3
	var goal_y := NAN  # NAN = at the fin's depth
	if target == null:
		s["mode"] = "roam"
		var anchor: Node3D = s.get("anchor") if is_instance_valid(s.get("anchor")) else _player
		s["angle"] = float(s["angle"]) + delta * speed / maxf(float(s["radius"]), 1.0)
		goal = anchor.global_position + Vector3(cos(float(s["angle"])), 0.0, sin(float(s["angle"]))) * float(s["radius"])
	else:
		var t_at := target.global_position
		if String(s["mode"]) == "circle":
			s["t"] = float(s["t"]) - delta
			s["radius"] = move_toward(float(s["radius"]), float(cfg["circle_m"][0]), delta * 1.2)
			s["angle"] = float(s["angle"]) + delta * speed / maxf(float(s["radius"]), 1.0)
			goal = t_at + Vector3(cos(float(s["angle"])), 0.0, sin(float(s["angle"]))) * float(s["radius"])
			if float(s["t"]) <= 0.0:
				s["mode"] = "lunge"
		else:  # lunge
			speed = float(cfg["lunge_speed"])
			goal = t_at
			goal_y = minf(t_at.y - 0.2, _water(t_at) - 0.6)  # its body level with him (down after a diver)
			var head := e.global_position + e.global_transform.basis.z * -1.4 + Vector3(0.0, 0.45, 0.0)
			if head.distance_to(t_at + Vector3(0.0, 0.5, 0.0)) <= float(cfg["bite_m"]) and now - float(s["bit"]) > float(cfg["bite_every"]):
				s["bit"] = now
				_bite(String(s["target"]), target, float(e.get_meta("bite", cfg["bite"])))
				s["mode"] = "circle"
				s["t"] = _rng.randf_range(float(cfg["circle_s"][0]), float(cfg["circle_s"][1])) * 0.6
				s["radius"] = float(cfg["circle_m"][1])
				s["angle"] = atan2(e.global_position.z - t_at.z, e.global_position.x - t_at.x)
	# pinned by a harpoon: slowed and hauled toward the shooter (its push)
	var slow := float(e.get("_slow_amount")) if now < float(e.get("_slow_until")) else 0.0
	var push: Vector3 = e.get("_push")
	e.set("_push", push.move_toward(Vector3.ZERO, 6.0 * delta))
	var flat := Vector3(goal.x - e.global_position.x, 0.0, goal.z - e.global_position.z)
	if String(s["mode"]) == "lunge":  # aim the head, not the middle, at him
		flat += Vector3(-sin(e.rotation.y), 0.0, -cos(e.rotation.y)) * -1.2
	var step := flat.normalized() * minf(speed * (1.0 - slow) * delta, flat.length()) + push * delta
	var at := e.global_position + step
	at.y = move_toward(e.global_position.y, _water(at) - float(cfg["fin_depth"]) if is_nan(goal_y) else goal_y, 3.0 * delta)
	e.global_position = at
	if step.length() > 0.001:
		e.rotation.y = lerp_angle(e.rotation.y, atan2(-step.x, -step.z), 1.0 - exp(-6.0 * delta))
	e.set_meta("swim_speed", step.length() / maxf(delta, 0.001))


func _bite(key: String, target: Node3D, damage: float) -> void:
	bites += 1
	blood[key] = _now() + float(cfg["blood_s"])  # it bleeds: more come
	if target.has_method("take_damage"):  # our own body, another player's (his machine takes it), a pirate overboard
		target.call("take_damage", damage, "physical")
	if key == "me":
		_sea.emit_signal("notice", "A shark bit you!")


# Swimming tail and the jaw (every machine).
func _animate(delta: float) -> void:
	var t := _now()
	for id: int in sharks:
		var e: Node3D = sharks[id]["enemy"]
		if not is_instance_valid(e):
			continue
		var model: Node3D = e.get("_model")
		if model == null:
			continue
		var tail := model.find_child("Tail", true, false) as Node3D
		var jaw := model.find_child("Jaw", true, false) as Node3D
		var pace := clampf(float(e.get_meta("swim_speed", 2.0)) / 4.0, 0.3, 1.6)
		if tail != null:
			tail.rotation.y = sin(t * 5.0 * pace + float(id)) * 0.45
		if jaw != null:
			var lunging: bool = String(sharks[id].get("mode", "")) == "lunge" or bool(e.get_meta("lunge", false))
			jaw.rotation.x = lerpf(jaw.rotation.x, 0.55 if lunging else 0.05, 1.0 - exp(-8.0 * delta))


# --- deaths, harvest ---

func _on_died(_enemy: Node, id: int) -> void:
	var e: Node3D = sharks.get(id, {}).get("enemy")
	sharks.erase(id)
	if is_instance_valid(e) and e.has_meta("harpooned_at") and _now() - float(e.get_meta("harpooned_at")) <= float(cfg["harvest"]["window_s"]):
		_harvest()
	var net := _net()
	if net != null and _host():
		net.call("tell_shark_died", id, _hitter)


# Our harpoon was in it: Hunting xp and the shark's parts into our bag.
func _harvest() -> void:
	var skills: Variant = _sea.get("skills")
	if skills == null:
		return
	var h: Dictionary = cfg["harvest"]
	var got := PackedStringArray()
	var double := float((skills as Node).call("perk", "hunting", "double"))
	for item: String in h["items"]:
		var n := _rng.randi_range(int(h["items"][item][0]), int(h["items"][item][1])) + (1 if _rng.randf() < double else 0)
		if n > 0:
			(skills as Node).call("give", item, n)
			got.append("%d %s" % [n, String((skills as Node).get("bag").call("item_name", item))])
	(skills as Node).call("gain_xp", "hunting", int(h["xp"]))
	harvested += 1
	last_harvest = ", ".join(got)
	_sea.emit_signal("notice", "Harpooned shark: %s" % last_harvest)


# --- online (game/net_sea.gd) ---

func to_net() -> Array:
	var out: Array = []
	for id: int in sharks:
		var e: Node3D = sharks[id]["enemy"]
		if not is_instance_valid(e):
			continue
		var p: Vector3 = _sea.call("local_of", e.global_position)
		var hp: RefCounted = e.get("health")
		out.append([id, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(e.rotation.y, 0.01), snappedf(float(hp.get("hp")) / maxf(float(hp.get("max_hp")), 1.0), 0.01), String(sharks[id]["mode"]) == "lunge"])
	return out


func should_send() -> bool:
	if not sharks.is_empty():
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
		var id := int(got[0])
		var at := Vector3(float(got[1]), float(got[2]), float(got[3]))
		if not at.is_finite():
			continue
		seen[id] = true
		if not sharks.has(id) or not is_instance_valid(sharks[id]["enemy"]):
			var e := _make(id, _stats.duplicate(), true)
			sharks[id] = {"enemy": e, "mode": "roam"}
			e.global_position = _sea.call("world_of", at)
		var en: Node3D = sharks[id]["enemy"]
		en.set("net_pos", (_fleet as Node3D).to_local(_sea.call("world_of", at)))
		en.set("net_yaw", float(got[4]))
		en.set_meta("lunge", bool(got[6]))
		var hp: RefCounted = en.get("health")
		hp.set("hp", clampf(float(got[5]), 0.0, 1.0) * float(hp.get("max_hp")))
	for id: int in sharks.keys():
		if seen.has(id):
			_missing.erase(id)
		elif _now() - float(_missing.get(id, _now())) > 0.6:
			_remove(id)
			_missing.erase(id)
		elif not _missing.has(id):
			_missing[id] = _now()


# The old host left (sea step 12): the sharks it showed slip away (new ones come for swimmers as ever).
func adopt_as_host() -> int:
	var n := sharks.size()
	for id: int in sharks.keys():
		_remove(id)
	_pending.clear()
	_missing.clear()
	return n


func _send_hits() -> void:
	if _pending.is_empty():
		return
	var net := _net()
	for id: int in _pending:
		if net != null:
			net.call("request_shark_hit", id, float(_pending[id]))
	_pending.clear()


func host_hit(id: int, damage: float, from: int) -> void:
	if not sharks.has(id) or not is_finite(damage) or damage <= 0.0:
		return
	var e: Node3D = sharks[id]["enemy"]
	if not is_instance_valid(e):
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null:
		card.set("blow", "other")
	_hitter = from
	e.call("on_hit", minf(damage, 2500.0))
	_hitter = 0
	if card != null:
		card.set("blow", before)


func fell(id: int, killer: int, me: int) -> void:
	if not sharks.has(id):
		return
	var e: Node3D = sharks[id]["enemy"]
	if not is_instance_valid(e):
		sharks.erase(id)
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null and killer != me:
		card.set("blow", "other")
	e.call("die_now")
	if card != null:
		card.set("blow", before)


func status() -> String:
	var modes := PackedStringArray()
	for id: int in sharks:
		modes.append(String(sharks[id]["mode"]))
	return "sharks %d [%s], spawned %d, bites %d, harvested %d '%s', swimmers %d" % [sharks.size(), ",".join(modes), spawned, bites, harvested, last_harvest, swimmers().size()]
