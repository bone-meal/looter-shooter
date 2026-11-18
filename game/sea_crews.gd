# Purpose: PIRATE CREWS (sea step 8b; director 2026-11-18: big pirate ships also board with a crew; loot drops on
# deck after a boarding fight). Every foe ship comes manned (data/sea/encounters.json kinds[..]["crew"]): real
# game/enemy.gd fighters standing on her deck as children of the ship (ship space, walking by core/sea/deck_walk.gd),
# made by the wave director (adopt: its shots, kill pay, grenades and skills reach them). Musketeers shoot at
# players within see_m; cutlass men and the captain fight whoever stands on their deck. A boarder closes on a player's
# ship and swings her boarders across one by one on a rope (an arc tween). Beating off the boarders leaves her deck
# loot as chests on the defended deck; clearing her own deck leaves it on hers and she strikes (no guns, no sail).
# HOST-AUTHORITATIVE: the host runs the crews and tells everyone (game/net_sea.gd crews: ship index + ship-space
# spot, 10 Hz); other machines show puppets that send their hits to the host; the host says who fell and whose
# blow it was. Kills pay through the wave director's `killed` (XP; no gun drops at sea: the plunder is on deck).
# Dependencies: core/sea/deck_walk.gd, data/enemies.json (pirate_*), data/sea/encounters.json "crews" and kinds,
# game/enemy.gd, game/wave_director.gd (adopt, forget; set by game/game_session.gd), the score card (blow), the fleet
# (game/sea_ships.gd: ships, rules, _net), game/sea_flotsam.gd (add_deck), the sea world (map, inside, notice).
extends Node3D

const DeckWalk = preload("res://core/sea/deck_walk.gd")

var cfg: Dictionary  # encounters.json "crews"
var director: Node  # game/wave_director.gd
var card: RefCounted  # core/score_card.gd: `blow` ("other" = this death pays nobody here)
var men := {}  # id -> {"enemy": Enemy, "home": the foe ship he came on, "kind": enemy id, "boarder": bool}
var boardings := {}  # foe ship -> {"target": ship, "queue": Array of ids, "next": float, "aboard": Array of ids, "done": bool}
var struck := {}  # foe ship -> true: her deck was cleared (host)
var swung := 0  # dev / checks: boarders that swung across here, boardings beaten off, foes struck, crewmen fallen
var repelled := 0
var strikes := 0
var fallen := 0
var _next_id := 1
var _retarget := 0.0
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _kinds: Dictionary  # encounters.json kinds
var _stats := {}  # data/enemies.json enemies
var _rng := RandomNumberGenerator.new()
var _hitter := 0  # host: the peer whose hit is being applied (0 = the host's own)
var _pending := {}  # client: id -> damage this frame, sent to the host as one hit
var _missing := {}  # client: id -> time it was first missing from the host's list
var _sent_empty := true
var _ropes: Array = []  # [rope mesh, foe ship, enemy, until]


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D, encounters: Dictionary) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	cfg = encounters["crews"]
	_kinds = encounters["kinds"]
	_stats = (JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")) as Dictionary)["enemies"]
	_rng.randomize()


func _net() -> Node:
	return _fleet.call("_net")


func _host() -> bool:
	var net := _net()
	return net == null or not bool(net.call("is_client"))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _region(ship: Node3D) -> String:
	var st: Dictionary = ship.get("state")
	return String((_sea.get("map") as RefCounted).call("region_id_at", float(st["x"]), float(st["z"])))


const ELBOW := 0.75  # m crewmen keep between each other (they would stand in one another round their prey)


# The walker of a crewman: a step on the deck of whatever ship he stands on now, edging off shipmates too close.
func _walk(from: Vector3, by: Vector3, enemy: Node3D) -> Vector3:
	var ship := enemy.get_parent()
	if ship == null or not ship.get("spec") is Dictionary:
		return from + by
	for other: Node in ship.get_children():
		if other != enemy and other.has_meta("sea") and other is Node3D:
			var away := from - (other as Node3D).position
			away.y = 0.0
			var d := away.length()
			if d < ELBOW and d > 0.001:
				by += away / d * (ELBOW - d) * 0.25
	return DeckWalk.step(ship.get("spec"), from, by)


# A crewman's numbers out here: tougher by region.
func _scaled(kind: String, region_n: int) -> Dictionary:
	var stats: Dictionary = (_stats[kind] as Dictionary).duplicate()
	stats["max_hp"] = float(stats["max_hp"]) * (1.0 + float(cfg["hp_per_region"]) * float(region_n - 1))
	stats["damage"] = float(stats["damage"]) * (1.0 + float(cfg["damage_per_region"]) * float(region_n - 1))
	return stats


func _make(id: int, kind: String, ship: Node3D, at: Vector3, stats: Dictionary, puppet: bool) -> Node3D:
	if director == null or not _stats.has(kind):
		return null
	var enemy: Node3D = director.call("adopt", kind, stats)
	enemy.set("space", ship)
	enemy.set("walker", _walk.bind(enemy))
	enemy.set("puppet", puppet)
	enemy.set("net_pos", at)
	enemy.set_meta("net_id", id)
	ship.add_child(enemy)
	enemy.position = at
	enemy.rotation.y = _rng.randf() * TAU
	enemy.died.connect(_on_died.bind(id))
	if puppet:
		enemy.set_meta("host_pays", true)
		enemy.connect("puppet_hit", func(damage: float) -> void: _pending[id] = float(_pending.get(id, 0.0)) + damage)
	else:
		enemy.connect("attacked", _on_attacked.bind(id))
	men[id] = {"enemy": enemy, "home": ship, "kind": kind, "boarder": false}
	return enemy


# Host / alone: a foe ship that just came in gets her crew (captain first, then the cutlass men, then the muskets).
func man(ship: Node3D) -> void:
	var k: Dictionary = _kinds.get(String(ship.get("state").get("foe", "")), {})
	var crew: Dictionary = k.get("crew", {})
	var total := 0
	for kind: String in crew:
		total += int(crew[kind])
	var region_n := maxi(int(_region(ship).trim_prefix("region_")), 1)
	var tier := int(cfg["tier_first"]) + int(cfg["tier_per_region"]) * (region_n - 1)
	var n := 0
	for kind: String in ["pirate_captain", "pirate_cutlass", "pirate_musket"]:
		for i in int(crew.get(kind, 0)):
			var at := DeckWalk.muster(ship.get("spec"), n, total, _rng.randf())
			var enemy := _make(_next_id, kind, ship, at, _scaled(kind, region_n), false)
			if enemy != null:
				enemy.set_meta("tier", tier)
			_next_id += 1
			n += 1


# Before a ship is freed: her men are taken off the director's list (they go with her).
func ship_gone(ship: Node3D) -> void:
	for id: int in men.keys():
		var enemy: Node3D = men[id]["enemy"]
		if not is_instance_valid(enemy) or enemy.get_parent() == ship:
			if is_instance_valid(enemy) and director != null:
				director.call("forget", enemy)
			men.erase(id)
	boardings.erase(ship)
	struck.erase(ship)


func _on_died(_enemy: Node, id: int) -> void:
	men.erase(id)
	fallen += 1
	var net := _net()
	if net != null and _host():
		net.call("tell_crew_died", id, _hitter)


# Host: a musketeer fired: everyone sees the shot (ship space, so it lines up on every machine).
func _on_attacked(origin: Vector3, aim: Vector3, id: int) -> void:
	var net := _net()
	var enemy: Node3D = men.get(id, {}).get("enemy")
	if net == null or not is_instance_valid(enemy):
		return
	var ship := enemy.get_parent() as Node3D
	net.call("tell_crew_fire", id, (_fleet.get("ships") as Array).find(ship), ship.global_transform.affine_inverse() * origin, ship.global_transform.basis.inverse() * aim)


# How many of a foe's men still stand on her own deck.
func on_deck(ship: Node3D) -> int:
	var n := 0
	for id: int in men:
		var enemy: Node3D = men[id]["enemy"]
		if is_instance_valid(enemy) and enemy.get_parent() == ship and not enemy.get("health").is_dead():
			n += 1
	return n


func is_struck(ship: Node3D) -> bool:
	return struck.has(ship)


# Her boarders are going across or fighting over there: she holds her guns (they would hit her own men).
func boarding(ship: Node3D) -> bool:
	return boardings.has(ship) and not bool(boardings[ship]["done"])


# The gap a foe keeps from her target: a boarder with boarders still to send closes in.
func keep_for(ship: Node3D) -> Array:
	var k: Dictionary = _kinds.get(String(ship.get("state").get("foe", "")), {})
	if int(k.get("boarders", 0)) <= 0 or bool(boardings.get(ship, {}).get("done", false)):
		return []
	if boardings.has(ship) and (boardings[ship]["queue"] as Array).is_empty():
		return []
	return cfg["board_keep_m"]


# Host: from a foe's plan this frame: close and abeam of a player's ship = her boarders go.
func consider(ship: Node3D, target_ship: Node3D, plan: Dictionary) -> void:
	var k: Dictionary = _kinds.get(String(ship.get("state").get("foe", "")), {})
	if int(k.get("boarders", 0)) <= 0 or boardings.has(ship) or target_ship == null or struck.has(ship):
		return
	if float(plan["d"]) > float(cfg["board_m"]) or absf(float(plan["ahead"])) > float(cfg["board_abeam"]):
		return
	board(ship, target_ship)


# Host / dev: her boarders (captain and cutlass men first) swing across to that ship one after another.
func board(ship: Node3D, target_ship: Node3D) -> void:
	if boardings.has(ship):
		return  # one boarding per foe
	var k: Dictionary = _kinds.get(String(ship.get("state").get("foe", "")), {})
	var queue: Array = []
	for kind: String in ["pirate_captain", "pirate_cutlass", "pirate_musket"]:
		for id: int in men:
			if queue.size() < int(k.get("boarders", 0)) and String(men[id]["kind"]) == kind and (men[id]["enemy"] as Node).get_parent() == ship:
				queue.append(id)
	boardings[ship] = {"target": target_ship, "queue": queue, "next": _now(), "aboard": [], "done": false}
	_sea.emit_signal("notice", String(cfg["board_notice"]) % String(k.get("name", "pirate")))


func _process(delta: float) -> void:
	if not bool(_sea.call("running")):
		return
	_ropes_follow()
	if not _host():
		_send_hits()
		return
	_retarget -= delta
	if _retarget <= 0.0 and not men.is_empty():
		_retarget = float(cfg["retarget_s"])
		_choose_targets()
	for ship: Node3D in boardings.keys():
		_go_on(ship)
	for ship: Node3D in _foes():
		if not struck.has(ship) and _manned_ever(ship) and on_deck(ship) == 0 and (not boardings.has(ship) or (boardings[ship]["queue"] as Array).is_empty()):
			_strike(ship)


func _foes() -> Array:
	var out: Array = []
	for ship: Node3D in _fleet.get("ships"):
		if (ship.get("state") as Dictionary).has("foe"):
			out.append(ship)
	return out


func _manned_ever(ship: Node3D) -> bool:
	return not (_kinds.get(String(ship.get("state").get("foe", "")), {}).get("crew", {}) as Dictionary).is_empty()


# Host: every crewman goes for the nearest player he can reach (his deck; a musket also within see_m), or stands.
func _choose_targets() -> void:
	var bodies: Array = []
	if bool(_sea.get("inside")) and not bool(_player.get("downed")):
		bodies.append(_player)
	var net := _net()
	if net != null and bool(net.call("active")):
		for body: Node3D in net.get("net").call("target_nodes"):
			if body.global_position.x < -10000.0:  # (sea_world SIDE_X: on the sea side of the scene)
				bodies.append(body)
	var ship_rules: RefCounted = _fleet.get("rules")
	for id: int in men:
		var enemy: Node3D = men[id]["enemy"]
		if not is_instance_valid(enemy) or bool(enemy.get("puppet")) or not enemy.is_physics_processing():
			continue
		var ship := enemy.get_parent() as Node3D
		var ranged := String(enemy.get("_stats").get("attack_type", "")) == "ranged"
		var best: Node3D = null
		var best_d := INF
		for body: Node3D in bodies:
			var d := enemy.global_position.distance_to(body.global_position)
			var same := bool(ship_rules.call("aboard", String(ship.get("state")["ship"]), ship.global_transform.affine_inverse() * body.global_position))
			if (same or (ranged and d <= float(cfg["see_m"]))) and d < best_d:
				best_d = d
				best = body
		enemy.call("set_target", best)


# Host: a boarding under way: the next boarder swings when his turn comes; all of them down = beaten off.
func _go_on(ship: Node3D) -> void:
	var b: Dictionary = boardings[ship]
	if bool(b["done"]):
		return
	var target: Node3D = b["target"]
	if not is_instance_valid(ship) or not is_instance_valid(target):
		b["done"] = true
		return
	var queue: Array = b["queue"]
	if not queue.is_empty() and _now() >= float(b["next"]):
		var id := int(queue.pop_front())
		var near := Vector2(float(ship.get("state")["x"]), float(ship.get("state")["z"])).distance_to(Vector2(float(target.get("state")["x"]), float(target.get("state")["z"])))
		if men.has(id) and is_instance_valid(men[id]["enemy"]) and near <= float(cfg["board_m"]) + 6.0:
			swing(id, target, (b["aboard"] as Array).size())
			(b["aboard"] as Array).append(id)
		b["next"] = _now() + float(cfg["swing_gap_s"])
	if queue.is_empty() and not (b["aboard"] as Array).is_empty():
		for id: int in b["aboard"]:
			if men.has(id):
				return
		b["done"] = true
		repelled += 1
		_deck_loot(ship, target)
		_sea.emit_signal("notice", String(cfg["repelled_notice"]))


# A crewman swings from his deck onto another ship (here: a rope from her mainmast top and an arc).
func swing(id: int, target: Node3D, nth: int, land: Vector3 = Vector3.INF) -> void:
	var enemy: Node3D = men[id]["enemy"]
	var from_ship := enemy.get_parent() as Node3D
	if land == Vector3.INF:
		land = DeckWalk.muster(target.get("spec"), nth % 4, 4, _rng.randf())
	enemy.set_physics_process(false)
	enemy.reparent(target)
	enemy.set("space", target)
	enemy.set("net_pos", land)
	men[id]["boarder"] = true
	var start := enemy.position
	var lift := float(cfg["swing_height"])
	var tween := enemy.create_tween()
	tween.tween_method(func(t: float) -> void: enemy.position = start.lerp(land, t) + Vector3(0.0, sin(t * PI) * lift, 0.0), 0.0, 1.0, float(cfg["swing_s"]))
	tween.tween_callback(enemy.set_physics_process.bind(true))
	_rope(from_ship, enemy, float(cfg["swing_s"]))
	swung += 1


func _rope(from_ship: Node3D, enemy: Node3D, seconds: float) -> void:
	var rope := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.025
	mesh.bottom_radius = 0.025
	mesh.height = 1.0
	mesh.radial_segments = 5
	mesh.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.33, 0.2)
	mesh.material = mat
	rope.mesh = mesh
	rope.top_level = true
	add_child(rope)
	_ropes.append([rope, from_ship, enemy, _now() + seconds + 0.2])


func _ropes_follow() -> void:
	for r: Array in _ropes.duplicate():
		var rope: MeshInstance3D = r[0]
		if _now() > float(r[3]) or not is_instance_valid(r[1]) or not is_instance_valid(r[2]):
			rope.queue_free()
			_ropes.erase(r)
			continue
		var ship: Node3D = r[1]
		var masts: Array = ship.get("spec")["masts"]
		var top: Vector3 = ship.call("deck_spot", [0.0, float(masts[masts.size() - 1][0])], float(masts[masts.size() - 1][1]) * 0.8)
		var hand := (r[2] as Node3D).global_position + Vector3(0.0, 1.9, 0.0)
		var span := hand - top
		if span.length() < 0.1:
			continue
		var up := span.normalized()
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		rope.global_transform = Transform3D(Basis(side, up * span.length(), side.cross(up)), (top + hand) * 0.5)


# Host: her deck is cleared: she strikes, and her plunder waits on her deck.
func _strike(ship: Node3D) -> void:
	struck[ship] = true
	strikes += 1
	var st: Dictionary = ship.get("state")
	st["stage"] = 0
	st["rudder"] = 0.0
	_deck_loot(ship, ship)
	_sea.emit_signal("notice", String(cfg["cleared_notice"]) % String(_kinds.get(String(st["foe"]), {}).get("name", "pirate")))


# Host: a foe's deck loot as chests on that deck (game/sea_flotsam.gd deck pieces).
func _deck_loot(foe: Node3D, on: Node3D) -> void:
	var k: Dictionary = _kinds.get(String(foe.get("state").get("foe", "")), {})
	var loot := String(k.get("deck_loot", ""))
	var flotsam: Node = get_parent().get("flotsam")
	if loot == "" or flotsam == null:
		return
	var n := int(flotsam.get("rules").call("pieces", loot, _rng))
	for i in n:
		var at := DeckWalk.muster(on.get("spec"), i + 1, n + 2, 0.5)
		flotsam.call("add_deck", on, at.x, at.z, loot, _region(foe))


# --- online (game/net_sea.gd) ---

# Host: [id, ship index, x, y, z (ship space), yaw, health 0..1, kind] for every crewman.
func to_net() -> Array:
	var out: Array = []
	var ships: Array = _fleet.get("ships")
	for id: int in men:
		var enemy: Node3D = men[id]["enemy"]
		if not is_instance_valid(enemy):
			continue
		var p := enemy.position
		var hp: RefCounted = enemy.get("health")
		out.append([id, ships.find(enemy.get_parent()), snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(enemy.rotation.y, 0.01), snappedf(float(hp.get("hp")) / maxf(float(hp.get("max_hp")), 1.0), 0.01), String(men[id]["kind"])])
	return out


# Host: send this tick? (the crews, and one empty list after the last is gone)
func should_send() -> bool:
	if not men.is_empty():
		_sent_empty = false
		return true
	if not _sent_empty:
		_sent_empty = true
		return true
	return false


# Client: the host's crews: new ones appear, moved ones swing across, missing ones go (after a moment: a death may still be on its way).
func from_net(list: Array) -> void:
	var ships: Array = _fleet.get("ships")
	var seen := {}
	for got: Variant in list:
		if not got is Array or (got as Array).size() < 8:
			continue
		var id := int(got[0])
		var index := int(got[1])
		var at := Vector3(float(got[2]), float(got[3]), float(got[4]))
		if index < 0 or index >= ships.size() or not at.is_finite() or not is_finite(float(got[5])):
			continue
		seen[id] = true
		var ship: Node3D = ships[index]
		var kind := String(got[7]).left(24)
		if not men.has(id) or not is_instance_valid(men[id]["enemy"]):
			if not kind.begins_with("pirate_"):
				continue
			_make(id, kind, ship, at, (_stats[kind] as Dictionary).duplicate(), true)
		var enemy: Node3D = men[id]["enemy"]
		if enemy.get_parent() != ship:
			swing(id, ship, 0, at)
		elif enemy.is_physics_processing():
			enemy.set("net_pos", at)
		enemy.set("net_yaw", float(got[5]))
		var hp: RefCounted = enemy.get("health")
		hp.set("hp", clampf(float(got[6]), 0.0, 1.0) * float(hp.get("max_hp")))
	for id: int in men.keys():
		if seen.has(id):
			_missing.erase(id)
		elif _now() - float(_missing.get(id, _now())) > 0.6:
			var enemy: Node3D = men[id]["enemy"]
			if is_instance_valid(enemy):
				director.call("forget", enemy)
				enemy.queue_free()
			men.erase(id)
			_missing.erase(id)
		elif not _missing.has(id):
			_missing[id] = _now()


# Client: what our shots did to the puppets this frame goes to the host as one hit each.
func _send_hits() -> void:
	if _pending.is_empty():
		return
	var net := _net()
	for id: int in _pending:
		if net != null:
			net.call("request_crew_hit", id, float(_pending[id]))
	_pending.clear()


# Host: a client's hit on a crewman (its claim capped); a killing blow is his kill, not ours.
func host_hit(id: int, damage: float, from: int) -> void:
	if not men.has(id) or not is_finite(damage) or damage <= 0.0:
		return
	var enemy: Node3D = men[id]["enemy"]
	if not is_instance_valid(enemy):
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null:
		card.set("blow", "other")
	_hitter = from
	enemy.call("on_hit", minf(damage, float(cfg["max_hit"])))
	_hitter = 0
	if card != null:
		card.set("blow", before)


# Client: a musketeer's shot, shown here (it can hit our player).
func show_fire(id: int, ship_index: int, origin: Vector3, aim: Vector3) -> void:
	var ships: Array = _fleet.get("ships")
	if not men.has(id) or ship_index < 0 or ship_index >= ships.size():
		return
	var ship: Node3D = ships[ship_index]
	(men[id]["enemy"] as Node).call("shoot_burst", ship.global_transform * origin, (ship.global_transform.basis * aim).normalized())


# Client: the host says a crewman fell (and whose blow it was: ours pays us).
func fell(id: int, killer: int, me: int) -> void:
	if not men.has(id):
		return
	var enemy: Node3D = men[id]["enemy"]
	men.erase(id)
	if not is_instance_valid(enemy):
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null and killer != me:
		card.set("blow", "other")
	enemy.call("die_now")
	if card != null:
		card.set("blow", before)


func status() -> String:
	var aboard := 0
	for id: int in men:
		if bool(men[id]["boarder"]):
			aboard += 1
	return "crews %d (boarders across %d), swung %d, repelled %d, struck %d, fallen %d, boardings %d" % [men.size(), aboard, swung, repelled, strikes, fallen, boardings.size()]
