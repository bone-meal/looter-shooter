# Purpose: PIRATE CREWS (sea step 8b; director 2026-11-18: big pirate ships also board with a crew; loot drops on
# deck after a boarding fight). Every foe ship comes manned (data/sea/encounters.json kinds[..]["crew"]): real
# game/enemy.gd fighters standing on her deck as children of the ship (ship space, walking by core/sea/deck_walk.gd),
# made by the wave director (adopt: its shots, kill pay, grenades and skills reach them). Musketeers shoot at
# players within see_m; cutlass men and the captain fight whoever stands on their deck. A boarder closes on a player's
# ship and swings her boarders across one by one on a rope (an arc tween). Beating off the boarders leaves her deck
# loot as chests on the defended deck; clearing her own deck leaves it on hers and she strikes (no guns, no sail, her
# flag comes down). Musketeers fire across at players on other ships (led for her speed). A crewman knocked hard over
# the rail, or on a sinking ship, swims to the nearest ship's ladder and climbs aboard (or drowns with none in reach).
# Poses: arms up on the rope and the ladder, a crawl stroke in the water. A brig keeps a few men BELOW in her hold
# (sea step 8b-2): they come up the companion stair one by one once the fight is near; a player who goes down meets them.
# HOST-AUTHORITATIVE: the host runs the crews and tells everyone (game/net_sea.gd crews: ship index + ship-space
# spot, 10 Hz); other machines show puppets that send their hits to the host; the host says who fell and whose
# blow it was. Kills pay through the wave director's `killed` (XP; no gun drops at sea: the plunder is on deck).
# Dependencies: core/sea/deck_walk.gd, data/enemies.json (pirate_*), data/sea/encounters.json "crews" and kinds,
# game/enemy.gd, game/wave_director.gd (adopt, forget; set by game/game_session.gd), the score card (blow), the fleet
# (game/sea_ships.gd: ships, rules, _net), game/sea_flotsam.gd (add_deck), the sea world (map, inside, notice).
extends Node3D

const Threat = preload("res://core/sea/threat_rules.gd")
const DeckWalk = preload("res://core/sea/deck_walk.gd")
const GhostLook = preload("res://game/ghost_look.gd")
const FxKit = preload("res://game/fx_kit.gd")
const ORDER := ["pirate_captain", "ghost_captain", "pirate_cutlass", "ghost_cutlass", "pirate_musket", "ghost_musket"]  # who goes first (mustering, boarding)
const KINDS_SENT := ["pirate_", "ghost_", "sea_drowned", "temple_"]  # crew kinds a client may make from the host's list

var cfg: Dictionary  # encounters.json "crews"
var _threat: Dictionary  # encounters.json "threat" (sea step 8f)
var director: Node  # game/wave_director.gd
var drowned_part: Node  # game/sea_drowned.gd (sea step 8d: undead swimmers chase and hold swimmers)
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
var overboard := 0  # dev / checks: crewmen that went into the sea, climbed back aboard, drowned
var climbed := 0
var drowned := 0
var shots := 0  # musket shots fired here (host)
var climbed_up := 0  # men come up from below
var last_overboard := ""  # dev: who went over last and why


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D, encounters: Dictionary) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	cfg = encounters["crews"]
	_threat = encounters["threat"]
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
	var to := DeckWalk.step(ship.get("spec"), from, by)
	var push: Vector3 = enemy.get("_push")
	if _host() and push.length() > float(cfg["overboard_push"]) and absf(from.x + by.x) > absf(to.x) + 0.2:
		_overboard.call_deferred(enemy, "thrown")  # thrown hard against the rail: over it
	return to


# --- foes in a dungeon's space (sea step 9c): the same host-run men (online list, hits, deaths, kill pay), standing in a
# dungeon instead of on a deck: they walk its map (floor, round pits, shut doors and things) and go for players in it ---

# Host: one foe in a dungeon space at a local point (its fights are run by game/sea_dungeons.gd). Returns his id.
func dungeon_spawn(kind: String, space: Node3D, at: Vector3, region_n: int) -> int:
	var id := _next_id
	_next_id += 1
	var enemy := _make(id, kind, space, at, _scaled(kind, region_n), false)
	if enemy == null:
		return -1
	enemy.set("walker", _dungeon_walk.bind(enemy, space))
	enemy.set_meta("tier", int(cfg["tier_first"]) + int(cfg["tier_per_region"]) * (region_n - 1))
	men[id]["dungeon"] = space
	FxKit.burst(space, enemy.global_position + Vector3(0.0, 0.6, 0.0), Color(0.6, 0.9, 0.85), 30, 0.8, 0.25, 3.0, -2.0)
	return id


# Host: a dungeon's foes taken away (everyone left while they fought: the fight starts again next time).
func dungeon_clear(ids: Array) -> void:
	for id: int in ids:
		if men.has(id):
			var enemy: Node3D = men[id]["enemy"]
			men.erase(id)
			if is_instance_valid(enemy):
				director.call("forget", enemy)
				enemy.queue_free()


func _dungeon_walk(from: Vector3, by: Vector3, enemy: Node3D, space: Node3D) -> Vector3:
	var rules: RefCounted = space.get("rules")
	var now := float(_sea.call("seconds"))
	for other: Node in space.get_children():
		if other != enemy and other.has_meta("net_id") and other is Node3D:
			var away := from - (other as Node3D).position
			away.y = 0.0
			var d := away.length()
			if d < ELBOW and d > 0.001:
				by += away / d * (ELBOW - d) * 0.25
	# (sea step 9c-2) they climb onto ledges: at a ledge's foot a foe goes up its face in place, then on; off a ledge
	# he drops to the floor
	var dt := get_physics_process_delta_time()
	var climb := float((space.get("cfg") as Dictionary).get("foe_climb_speed", 2.0))
	if Vector2(by.x, by.z).length() < 0.0005:
		return from  # standing still (winding up a blow, stunned): where he is, half way up a face or not
	for step: Vector3 in [by, Vector3(by.x, 0.0, 0.0), Vector3(0.0, 0.0, by.z)]:
		var to := from + step
		var c: Vector2i = rules.call("cell_of", to)
		var ahead: Vector2i = rules.call("cell_of", to + step.normalized() * 0.45)
		if bool(rules.call("body_can", c, now, true)) and bool(rules.call("body_can", ahead, now, true)):
			var want := maxf(float(rules.call("height_of", c)), float(rules.call("height_of", ahead)))
			if want > from.y + 0.15:
				return Vector3(from.x, move_toward(from.y, want, climb * dt), from.z)
			to.y = move_toward(from.y, want, 9.0 * dt)
			return to
	return Vector3(from.x, move_toward(from.y, float(rules.call("height_of", rules.call("cell_of", from))), 9.0 * dt), from.z)


# A crewman's numbers out here: tougher by region.
func _scaled(kind: String, region_n: int) -> Dictionary:
	var stats: Dictionary = (_stats[kind] as Dictionary).duplicate()
	var pm := Threat.player_mult(_threat, region_n)  # (sea step 8f: grows with the region's item level)
	stats["max_hp"] = float(stats["max_hp"]) * pm
	stats["damage"] = float(stats["damage"]) * pm
	return _sea_stats(stats)


# A musket at sea reaches across to the next ship (the land numbers are for 30 m fights).
func _sea_stats(stats: Dictionary) -> Dictionary:
	if String(stats.get("attack_type", "")) == "ranged":
		stats["attack_range"] = float(cfg["musket_range"])
		stats["projectile_speed"] = float(cfg["musket_speed"])
		stats["preferred_range"] = 0.0
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
		enemy.set("aim_fix", _lead)
	if kind.begins_with("ghost_"):
		GhostLook.body(enemy)  # (sea step 8d)
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
	for kind: String in ORDER:
		for i in int(crew.get(kind, 0)):
			var at := DeckWalk.muster(ship.get("spec"), n, total, _rng.randf())
			var enemy := _make(_next_id, kind, ship, at, _scaled(kind, region_n), false)
			if enemy != null:
				enemy.set_meta("tier", tier)
			_next_id += 1
			n += 1
	var below: Dictionary = k.get("below", {})
	if (ship.get("spec") as Dictionary).get("hold", {}).is_empty():
		below = {}
	var down := 0
	var down_total := 0
	for kind: String in below:
		down_total += int(below[kind])
	for kind: String in ORDER:
		for i in int(below.get(kind, 0)):
			var enemy := _make(_next_id, kind, ship, DeckWalk.hold_muster(ship.get("spec"), down, down_total), _scaled(kind, region_n), false)
			if enemy != null:
				enemy.set_meta("tier", tier)
			_next_id += 1
			down += 1


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


# Host (sea step 8d): one of the drowned comes up out of the water at sea (x, z), swimming for `ship` (or the
# nearest). Returns its id (-1 = none made).
func rise(kind: String, x: float, z: float, ship: Node3D, region_n: int) -> int:
	var water := float(_sea.call("water_height", _sea.call("world_of", Vector3(x, 0.0, z)))) - _fleet.global_position.y
	var enemy := _make(_next_id, kind, _fleet, Vector3(x, water - 1.6, z), _scaled(kind, region_n), false)
	if enemy == null:
		return -1
	enemy.set_meta("tier", int(cfg["tier_first"]) + int(cfg["tier_per_region"]) * (region_n - 1))
	enemy.set_physics_process(false)
	men[_next_id]["swim"] = {"t": 0.0, "undead": true, "goal_fixed": ship}
	_swim_pose(enemy, true)
	_next_id += 1
	return _next_id - 1


# Host: every man of these kinds is gone at once (a ghost crew at dawn): no kill, no pay.
func vanish(prefix: String) -> void:
	for id: int in men.keys():
		if String(men[id]["kind"]).begins_with(prefix):
			var enemy: Node3D = men[id]["enemy"]
			if is_instance_valid(enemy):
				if director != null:
					director.call("forget", enemy)
				FxKit.burst(self, enemy.global_position + Vector3(0.0, 1.0, 0.0), Color(0.45, 1.0, 0.85, 0.7), 16, 1.0, 0.4, 1.5, 0.5)
				enemy.queue_free()
			men.erase(id)


func _on_died(_enemy: Node, id: int) -> void:
	men.erase(id)
	fallen += 1
	var net := _net()
	if net != null and _host():
		net.call("tell_crew_died", id, _hitter)


# Host: a musketeer fired: everyone sees the shot (ship space, so it lines up on every machine).
func _on_attacked(origin: Vector3, aim: Vector3, id: int) -> void:
	shots += 1
	var net := _net()
	var enemy: Node3D = men.get(id, {}).get("enemy")
	if net == null or not is_instance_valid(enemy):
		return
	var ship := enemy.get_parent() as Node3D
	net.call("tell_crew_fire", id, (_fleet.get("ships") as Array).find(ship), ship.global_transform.affine_inverse() * origin, ship.global_transform.basis.inverse() * aim)


# Host: a musket's aim at a player on a moving ship: where he will be when the ball gets there, a little off.
func _lead(origin: Vector3, aim: Vector3, target: Node3D) -> Vector3:
	if not is_instance_valid(target):
		return aim
	var at := target.global_position + Vector3(0.0, 1.2, 0.0)
	var on := _ship_under(target.global_position)
	if on != null:
		var st: Dictionary = on.get("state")
		var vel := Vector3(-sin(float(st["yaw"])), 0.0, -cos(float(st["yaw"]))) * float(st["speed"])
		at += vel * origin.distance_to(at) / float(cfg["musket_speed"])
	var err := deg_to_rad(float(cfg["musket_error_deg"]))
	var way := (at - origin).normalized()
	var side := way.cross(Vector3.UP).normalized()
	return (way + side * _rng.randf_range(-err, err) + Vector3.UP * _rng.randf_range(-err, err) * 0.6).normalized()


# The ship whose deck is at this scene point (null = none).
func _ship_under(point: Vector3) -> Node3D:
	var ship_rules: RefCounted = _fleet.get("rules")
	for ship: Node3D in _fleet.get("ships"):
		if bool(ship_rules.call("aboard", String(ship.get("state")["ship"]), ship.global_transform.affine_inverse() * point)):
			return ship
	return null


# How many of a foe's men still stand on her own deck.
func on_deck(ship: Node3D) -> int:
	var n := 0
	for id: int in men:
		var enemy: Node3D = men[id]["enemy"]
		if is_instance_valid(enemy) and enemy.get_parent() == ship and not enemy.get("health").is_dead():
			n += 1
	return n


# A man of hers is in the water swimming for her: she heaves to (sails furled) till he is back aboard.
func picking_up(ship: Node3D) -> bool:
	for id: int in men:
		if men[id].has("swim") and men[id]["swim"].get("goal") == ship:
			return true
	return false


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
	for kind: String in ORDER:
		for id: int in men:
			if queue.size() < int(k.get("boarders", 0)) and String(men[id]["kind"]) == kind and (men[id]["enemy"] as Node).get_parent() == ship:
				queue.append(id)
	boardings[ship] = {"target": target_ship, "queue": queue, "next": _now(), "aboard": [], "done": false}
	_sea.emit_signal("notice", String(cfg["board_notice"]) % String(k.get("name", "pirate")))


func _process(delta: float) -> void:
	if not bool(_sea.call("running")):
		return
	_ropes_follow()
	_strokes()
	if not _host():
		_send_hits()
		return
	for id: int in men.keys():
		if men.has(id) and men[id].has("swim"):
			_swim_step(id, delta)
	for ship: Node3D in _fleet.get("ships"):
		if bool(ship.get("state").get("sinking", false)):
			for id: int in men.keys():
				var e: Node3D = men[id]["enemy"]
				if is_instance_valid(e) and e.get_parent() == ship and e.is_physics_processing():
					_overboard(e, "sinking")  # going down with her: into the sea
	_retarget -= delta
	if _retarget <= 0.0 and not men.is_empty():
		_retarget = float(cfg["retarget_s"])
		_choose_targets()
	for ship: Node3D in boardings.keys():
		_go_on(ship)
	_below_up()
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


# Host: men below in a foe's hold come up the companion stair one at a time once the fight is near.
var _below_next := {}  # foe ship -> time the next may climb


func _below_up() -> void:
	var now := _now()
	for ship: Node3D in _foes():
		var spec: Dictionary = ship.get("spec")
		if spec.get("hold", {}).is_empty() or now < float(_below_next.get(ship, 0.0)):
			continue
		var down: Array = []
		for id: int in men:
			var e: Node3D = men[id]["enemy"]
			if is_instance_valid(e) and e.get_parent() == ship and e.is_physics_processing() and DeckWalk.below(spec, e.position):
				down.append(id)
		if down.is_empty():
			continue
		var awake := boardings.has(ship)
		for who: Dictionary in get_parent().call("players"):
			if (who["at"] as Vector2).distance_to(Vector2(float(ship.get("state")["x"]), float(ship.get("state")["z"]))) <= float(cfg["below_wake_m"]):
				awake = true
		var anyone_below := false
		for id: int in down:  # a player down here: they fight him below instead
			var t: Variant = (men[id]["enemy"] as Node).get("_target")
			if is_instance_valid(t) and bool(_fleet.get("rules").call("in_hold", String(ship.get("state")["ship"]), ship.global_transform.affine_inverse() * (t as Node3D).global_position)):
				anyone_below = true
		if awake and not anyone_below:
			_below_next[ship] = now + float(cfg["below_up_s"])
			climb_up(int(down[0]), ship)


# Up the companion stair: to its foot, up it (arms on the rails), a step onto the deck beyond its head.
func climb_up(id: int, ship: Node3D) -> void:
	var enemy: Node3D = men[id]["enemy"]
	var spec: Dictionary = ship.get("spec")
	var st: Dictionary = spec["hold"]["stair"]
	var way := signf(float(st["high"]) - float(st["low"]))
	var foot := Vector3(float(st["x"]), float(spec["hold"]["floor"]), float(st["low"]) - way * 0.3)
	var head := Vector3(float(st["x"]) + float(climbed_up % 3 - 1) * 1.0, float(spec["deck"]), float(st["high"]) + way * (0.8 + 0.5 * float(climbed_up % 2)))  # (each a step apart: idle men do not walk off each other)
	var start := enemy.position
	enemy.set_physics_process(false)
	enemy.rotation.y = atan2(0.0, -way)
	var walk := maxf(start.distance_to(foot) / 3.0, 0.2)
	var tween := enemy.create_tween()
	tween.tween_method(func(t: float) -> void: enemy.position = start.lerp(foot, t), 0.0, 1.0, walk)
	tween.tween_callback(_pose.bind(enemy, "rope"))
	tween.tween_method(func(t: float) -> void: enemy.position = foot.lerp(head, t), 0.0, 1.0, float(cfg["climb_s"]))
	tween.tween_callback(_landed.bind(enemy))
	climbed_up += 1


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
	var dungeons: Node = _sea.get("dungeons")
	for id: int in men:
		var enemy: Node3D = men[id]["enemy"]
		if not is_instance_valid(enemy) or bool(enemy.get("puppet")) or not enemy.is_physics_processing():
			continue
		if men[id].has("dungeon"):  # in a dungeon: the nearest player in that same dungeon
			var space: Node3D = men[id]["dungeon"]
			var pick: Node3D = null
			var pick_d := INF
			for body: Node3D in bodies:
				var here: Vector3 = _sea.call("local_of", body.global_position)
				if String(dungeons.call("dungeon_at", here)) == String(space.get("rules").get("id")):
					var dd := enemy.global_position.distance_to(body.global_position)
					if dd < pick_d:
						pick_d = dd
						pick = body
			enemy.call("set_target", pick)
			continue
		var ship := enemy.get_parent() as Node3D
		var down := ship.get("spec") is Dictionary and DeckWalk.below(ship.get("spec"), enemy.position)  # below: only someone down there with him
		var ranged := String(enemy.get("_stats").get("attack_type", "")) == "ranged" and not down
		var best: Node3D = null
		var best_d := INF
		for body: Node3D in bodies:
			var d := enemy.global_position.distance_to(body.global_position)
			var local := ship.global_transform.affine_inverse() * body.global_position if ship.get("state") is Dictionary else Vector3.INF
			var same := local != Vector3.INF and bool(ship_rules.call("in_hold" if down else "aboard", String(ship.get("state")["ship"]), local))
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


# A crewman swings from his deck onto another ship (here: a rope from her mainmast top and an arc), or (from the
# water) climbs her side by the ladder: arms up the whole way.
func swing(id: int, target: Node3D, nth: int, land: Vector3 = Vector3.INF) -> void:
	var enemy: Node3D = men[id]["enemy"]
	var from_ship := enemy.get_parent() as Node3D
	var from_sea := not (from_ship != null and from_ship.get("spec") is Dictionary)  # (a swimmer: the fleet node)
	if land == Vector3.INF:
		land = DeckWalk.muster(target.get("spec"), nth % 4, 4, _rng.randf())
	enemy.set_physics_process(false)
	enemy.reparent(target)
	enemy.rotation = Vector3(0.0, enemy.rotation.y, 0.0)
	enemy.set("space", target)
	enemy.set("net_pos", land)
	men[id].erase("swim")
	if not from_sea:
		men[id]["boarder"] = true
	_pose(enemy, "rope")
	var start := enemy.position
	var lift := 0.4 if from_sea else float(cfg["swing_height"])
	var seconds := float(cfg["climb_s"]) if from_sea else float(cfg["swing_s"])
	var tween := enemy.create_tween()
	tween.tween_method(func(t: float) -> void: enemy.position = start.lerp(land, t) + Vector3(0.0, sin(t * PI) * lift, 0.0), 0.0, 1.0, seconds)
	tween.tween_callback(_landed.bind(enemy))
	if from_sea:
		climbed += 1
	else:
		_rope(from_ship, enemy, seconds)
		swung += 1


func _landed(enemy: Node3D) -> void:
	if is_instance_valid(enemy):
		_pose(enemy, "")
		enemy.set_physics_process(true)


# Arms up (the rope, the ladder), a crawl stroke (swimming), or back as the enemy holds them ("").
func _pose(enemy: Node3D, kind: String) -> void:
	if not enemy.has_meta("rest_pose"):
		var rest := {}
		for limb: String in ["ArmL", "ArmR", "LegL", "LegR"]:
			var n := enemy.find_child(limb, true, false) as Node3D
			if n != null:
				rest[limb] = n.rotation
		enemy.set_meta("rest_pose", rest)
	var rest_pose: Dictionary = enemy.get_meta("rest_pose")
	enemy.set_meta("pose", kind)
	for limb: String in rest_pose:
		var n := enemy.find_child(limb, true, false) as Node3D
		if n == null:
			continue
		if kind == "rope":
			n.rotation = Vector3(deg_to_rad(-165.0) if limb.begins_with("Arm") else 0.45, 0.0, 0.0)
		else:
			n.rotation = rest_pose[limb]


# Swimmers' arms and legs (every machine): a slow crawl stroke.
func _strokes() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id: int in men:
		var enemy: Node3D = men[id]["enemy"]
		if not is_instance_valid(enemy) or String(enemy.get_meta("pose", "")) != "swim":
			continue
		if bool(enemy.get("puppet")):  # (a client: glide to where the host says he swims)
			enemy.position = enemy.position.lerp(enemy.get("net_pos"), 0.15)
			enemy.rotation.y = lerp_angle(enemy.rotation.y, float(enemy.get("net_yaw")), 0.15)
		for limb: String in ["ArmL", "ArmR", "LegL", "LegR"]:
			var n := enemy.find_child(limb, true, false) as Node3D
			if n != null:
				var phase := t * 3.2 + (PI if limb.ends_with("R") else 0.0)
				n.rotation = Vector3((-PI * 0.5 + sin(phase) * 1.4) if limb.begins_with("Arm") else sin(phase * 2.0) * 0.35, 0.0, 0.0)


# Host: into the sea (thrown over, or his ship is going down).
func _overboard(enemy: Node3D, why: String = "") -> void:
	if not is_instance_valid(enemy) or enemy.get("health").is_dead() or not enemy.has_meta("net_id"):
		return
	var id := int(enemy.get_meta("net_id"))
	if not men.has(id) or men[id].has("swim"):
		return
	enemy.set_physics_process(false)
	enemy.reparent(_fleet)
	enemy.set("space", _fleet)
	last_overboard = "%s %s (push %.1f)" % [String(men[id]["kind"]), why, (enemy.get("_push") as Vector3).length()]
	enemy.set("_push", Vector3.ZERO)
	men[id]["swim"] = {"t": 0.0}
	_swim_pose(enemy, true)
	overboard += 1


func _swim_pose(enemy: Node3D, on: bool) -> void:
	enemy.rotation.x = -1.25 if on else 0.0  # laid face down in the water
	if on:
		_pose(enemy, "")
		enemy.set_meta("pose", "swim")
	else:
		_pose(enemy, "")


# Host: a swimmer floats up to the surface and swims to the nearest afloat ship's ladder (her own side), then climbs.
func _swim_step(id: int, delta: float) -> void:
	var enemy: Node3D = men[id]["enemy"]
	var sw: Dictionary = men[id]["swim"]
	if not is_instance_valid(enemy):
		men.erase(id)
		return
	sw["t"] = float(sw["t"]) + delta
	var world := enemy.global_position
	var water := float(_sea.call("water_height", Vector3(world.x, 0.0, world.z))) - (_fleet as Node3D).global_position.y
	var undead := bool(sw.get("undead", false))  # the drowned (sea step 8d): never drown, climb her hull anywhere
	enemy.position.y = move_toward(enemy.position.y, water - (0.5 if undead else 0.35), (2.0 if undead else 6.0) * delta)
	if undead and drowned_part != null and bool(drowned_part.call("swim", id, enemy, sw, delta)):
		return
	var best: Node3D = null
	var best_d := INF
	var foot := Vector3.ZERO
	var fixed: Variant = sw.get("goal_fixed")
	var fixed_ok := undead and is_instance_valid(fixed) and not bool((fixed as Node).get("state").get("sinking", false))
	for ship: Node3D in _fleet.get("ships"):
		if bool(ship.get("state").get("sinking", false)) or (fixed_ok and ship != fixed):
			continue
		var spec: Dictionary = ship.get("spec")
		var lz := float(spec.get("ladder_z", 0.0))
		if undead:  # straight up her side where it is nearest
			var outline: Array = spec["outline"]
			lz = clampf((ship.global_transform.affine_inverse() * world).z, float(outline[outline.size() - 1][0]) + 2.0, float(outline[0][0]) - 2.0)
		var local := ship.global_transform.affine_inverse() * world
		var side := 1.0 if local.x >= 0.0 else -1.0
		var at := ship.global_transform * Vector3(side * (DeckWalk.half_width(spec, lz) + 0.45), 0.0, lz)
		var d := Vector2(at.x - world.x, at.z - world.z).length()
		if d < best_d:
			best_d = d
			best = ship
			foot = at
	if best == null or (not undead and (best_d > 60.0 or float(sw["t"]) > float(cfg["drown_s"]))) or (undead and best_d > 400.0):
		drowned += 1  # nothing to climb: he goes under (nobody is paid)
		if director != null:
			director.call("forget", enemy)
		men.erase(id)
		enemy.queue_free()
		return
	sw["goal"] = best
	var way := Vector2(foot.x - world.x, foot.z - world.z)
	if way.length() <= 1.0:
		var spec_b: Dictionary = best.get("spec")
		var lz_b := float(spec_b.get("ladder_z", 0.0)) if not undead else (best.global_transform.affine_inverse() * foot).z
		var side_b := signf((best.global_transform.affine_inverse() * world).x)
		var x := side_b * maxf(DeckWalk.half_width(spec_b, lz_b) - 0.8, 0.3)
		swing(id, best, 0, Vector3(x, DeckWalk.height_at(spec_b, x, lz_b), lz_b))
		return
	var step := way.normalized() * minf(float(cfg["swim_speed"]) * (1.25 if undead else 1.0) * delta, way.length())
	enemy.position += Vector3(step.x, 0.0, step.y)
	enemy.rotation.y = atan2(-way.x, -way.y)


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
	st["struck"] = true
	ship.call("strike_colours")
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
		var where := -2 if men[id].has("dungeon") else ships.find(enemy.get_parent())
		out.append([id, where, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(enemy.rotation.y, 0.01), snappedf(float(hp.get("hp")) / maxf(float(hp.get("max_hp")), 1.0), 0.01), String(men[id]["kind"]), men[id].has("swim"),
			String((men[id]["dungeon"] as Node3D).get("rules").get("id")) if men[id].has("dungeon") else ""])
	return out


# The old host left and this machine hosts now (sea step 12): the crews it showed fight on as real men where they stand
# (a struck ship stays struck); men in dungeon fights go (those fights start again when a player comes near).
func adopt_as_host() -> void:
	for id: int in men.keys():
		var enemy: Node3D = men[id]["enemy"]
		if not is_instance_valid(enemy):
			men.erase(id)
			continue
		if men[id].has("dungeon"):
			director.call("forget", enemy)
			enemy.queue_free()
			men.erase(id)
			continue
		enemy.set("puppet", false)
		if enemy.has_meta("host_pays"):
			enemy.remove_meta("host_pays")
		if not enemy.is_connected("attacked", _on_attacked.bind(id)):
			enemy.connect("attacked", _on_attacked.bind(id))
		enemy.set("aim_fix", _lead)
		if not men[id].has("swim"):
			enemy.set_physics_process(true)
		_next_id = maxi(_next_id, id + 1)
	_pending.clear()
	_missing.clear()
	for ship: Node3D in _foes():
		if bool(ship.get("state").get("struck", false)):
			struck[ship] = true


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
		var swimming := (got as Array).size() >= 9 and bool(got[8])
		var space: Node3D = null
		if index == -2 and (got as Array).size() >= 10:  # in a dungeon's space (sea step 9c)
			space = (_sea.get("dungeons").get("spaces") as Dictionary).get(String(got[9]).left(32))
			if space == null:
				continue
		elif (not swimming and (index < 0 or index >= ships.size())) or not at.is_finite() or not is_finite(float(got[5])):
			continue
		seen[id] = true
		var ship: Node3D = space if space != null else (_fleet if swimming else ships[index])
		var kind := String(got[7]).left(24)
		if not men.has(id) or not is_instance_valid(men[id]["enemy"]):
			if not _stats.has(kind) or not KINDS_SENT.any(func(p: String) -> bool: return kind.begins_with(p)):
				continue
			_make(id, kind, ship, at, _sea_stats((_stats[kind] as Dictionary).duplicate()), true)
			if space != null:
				men[id]["dungeon"] = space
		var enemy: Node3D = men[id]["enemy"]
		if swimming and enemy.get_parent() != ship:  # over the side: he swims (the host moves him; _strokes glides him here)
			enemy.set_physics_process(false)
			enemy.reparent(_fleet)
			enemy.set("space", _fleet)
			enemy.set("net_pos", at)
			men[id]["swim"] = {"t": 0.0}
			_swim_pose(enemy, true)
		elif not swimming and enemy.get_parent() != ship:
			swing(id, ship, 0, at)
		elif enemy.is_physics_processing() or swimming:
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
	return "crews %d (boarders across %d), swung %d, repelled %d, struck %d, fallen %d, boardings %d, overboard %d, climbed %d, drowned %d, musket shots %d, came up %d, last over '%s'" % [men.size(), aboard, swung, repelled, strikes, fallen, boardings.size(), overboard, climbed, drowned, shots, climbed_up, last_overboard]
