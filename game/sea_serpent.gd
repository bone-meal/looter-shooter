# Purpose: the SEA SERPENT, our own TIDE WYRM (sea step 8c; director: a roaming monster - a rare random encounter in
# deep water, more in storms; it surfaces beside the ship, bites the hull, lunges at players on deck, dives and
# resurfaces; fought with cannons and guns; trophy, scales, loot afloat). The HOST runs it as a cycle round the ship a
# player is on (or the player himself in the water): APPROACH under water -> SURFACE abeam of her (head up, its long
# body arching out of the sea), bite her hull every bite_every, LUNGE at a player on deck (rears up for windup s with
# the jaw open - the moment to step away - then strikes: everyone within lunge_radius of the spot is hurt) -> DIVE and
# come up on her other side. The wyrm is a game/enemy.gd body made by the wave director (kill XP, grenades, skills
# reach it) whose head is the enemy itself (hits there count as head hits); each body segment carries a hit box that
# passes segment_share of a hit on (game/hit_proxy.gd). Cannon balls hurt it (game/sea_cannons.gd). Slain = its
# hoard floats where it died (game/sea_flotsam.gd, loot "serpent": doubloons, scales, its fang, a good gun chance).
# Online: the host sends where it is and how its body lies (game/net_sea.gd serpent); clients show a puppet, its hits
# go to the host.
# Dependencies: data/sea/encounters.json "serpent" + kinds sea_serpent, data/enemies.json sea_serpent, game/enemy.gd,
# game/hit_proxy.gd, game/wave_director.gd, the fleet (game/sea_ships.gd: ships, hull_part, ship_aboard, rules, _net),
# game/sea_flotsam.gd, the sea world (water_height, local_of / world_of, map, notice), the player.
extends Node3D

const HitProxy = preload("res://game/hit_proxy.gd")
const SEGMENTS := 10
const SEG_LEN := 1.8

var cfg: Dictionary
var director: Node
var card: RefCounted
var wyrm: Node3D = null  # the enemy (head); null = none about
var mode := ""  # approach | surface | dive | (puppet: from the host)
var rise := 0.0  # how far its body arches out of the water (0 under .. 1 up)
var phase := 0.0  # the wave running down its body
var jaw := 0.0  # 0 shut .. 1 wide
var came := 0  # dev / checks
var slain := 0
var hull_bites := 0
var lunges := 0
var last := ""
var _side := 1.0  # which side of her it surfaces on
var _t := 0.0  # time left in this mode
var _bite_t := 0.0
var _lunge_t := 0.0
var _windup := 0.0  # > 0: rearing up before a strike
var _strike_at := Vector3.ZERO
var _target_ship: Node3D = null
var _fleet: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _stats := {}
var _rng := RandomNumberGenerator.new()
var _pending := 0.0
var _hitter := 0
var _was_here := false


func setup(fleet: Node3D, sea: Node3D, player: CharacterBody3D, encounters: Dictionary) -> void:
	_fleet = fleet
	_sea = sea
	_player = player
	cfg = encounters["serpent"]
	_stats = (JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")) as Dictionary)["enemies"]["sea_serpent"]
	_rng.randomize()


func _net() -> Node:
	return _fleet.call("_net")


func _host() -> bool:
	var net := _net()
	return net == null or not bool(net.call("is_client"))


func _water(at: Vector3) -> float:
	return float(_sea.call("water_height", Vector3(at.x, 0.0, at.z)))


# Lays the body of a wyrm model along its swimming curve (head at the model's origin, the body trailing behind along
# +z): `rise` lifts the arches out of the water, `phase` runs the wave down it, `sway` bends it side to side.
static func lay_body(model: Node3D, ph: float, up: float, sway: float) -> void:
	var curve := func(s: float) -> Vector3:
		var fade := clampf(s / 5.0, 0.0, 1.0)
		var y := up * 1.6 * sin(s * 0.42 - ph) * fade - (1.0 - up) * 2.5 * fade - s * 0.04
		var x := sway * 1.8 * sin(s * 0.33 - ph * 0.7) * fade
		return Vector3(x, y, s)
	for i in SEGMENTS + 1:
		var node := model.find_child("Seg%d" % (i + 1) if i < SEGMENTS else "Tail", true, false) as Node3D
		if node == null:
			continue
		var s := 0.6 + (float(i) + 0.5) * SEG_LEN + (0.6 if i == SEGMENTS else 0.0)
		var p: Vector3 = curve.call(s)
		var tangent: Vector3 = (curve.call(s + 0.2) as Vector3) - (curve.call(s - 0.2) as Vector3)
		node.transform = Transform3D(Basis.looking_at(-tangent.normalized(), Vector3.UP), p)


# Host / alone (and dev): it comes up out of the deep near that sea spot.
func spawn(x: float, z: float) -> void:
	if wyrm != null or director == null:
		return
	var region := String((_sea.get("map") as RefCounted).call("region_id_at", x, z))
	var n := maxi(int(region.trim_prefix("region_")), 1)
	var stats := _stats.duplicate()
	stats["max_hp"] = float(stats["max_hp"]) * (1.0 + float(cfg["hp_per_region"]) * float(n - 1))
	_make(stats, false)
	var at: Vector3 = _sea.call("world_of", Vector3(x, 0.0, z))
	wyrm.global_position = Vector3(at.x, _water(at) - 5.0, at.z)
	wyrm.set_meta("tier", 8 + 4 * (n - 1))
	wyrm.set_meta("dmg", 1.0 + float(cfg["damage_per_region"]) * float(n - 1))
	wyrm.set_meta("region", region)
	mode = "approach"
	_t = 40.0
	came += 1
	_sea.emit_signal("notice", String(cfg["notice"]))


func _make(stats: Dictionary, puppet: bool) -> void:
	wyrm = director.call("adopt", "sea_serpent", stats)
	wyrm.set("puppet", puppet)
	wyrm.set_meta("serpent", true)
	_fleet.add_child(wyrm)
	wyrm.set_physics_process(puppet)
	var model: Node3D = wyrm.get("_model")
	if model != null:
		model.scale = Vector3.ONE * float(cfg.get("scale", 1.0))  # (modelled at a man's scale; the enemy would scale it to its head box)
		for i in SEGMENTS + 1:  # a hit box on every segment, passing part of a hit on to the wyrm
			var seg := model.find_child("Seg%d" % (i + 1) if i < SEGMENTS else "Tail", true, false) as Node3D
			if seg != null:
				var proxy := HitProxy.new()
				proxy.target = wyrm
				proxy.share = float(cfg["segment_share"])
				proxy.radius = 0.75 - 0.03 * float(i)
				seg.add_child(proxy)
				_player.add_collision_exception_with(proxy)  # its body never shoves us (a lunge would push us overboard)
	_player.add_collision_exception_with(wyrm)
	wyrm.died.connect(_on_died)
	if puppet:
		wyrm.set_meta("host_pays", true)
		wyrm.connect("puppet_hit", func(damage: float) -> void: _pending += damage)
	if model != null:
		lay_body(model, phase, rise, 0.0)


func _remove() -> void:
	if is_instance_valid(wyrm):
		director.call("forget", wyrm)
		wyrm.queue_free()
	wyrm = null
	mode = ""


# --- the host's wyrm ---

func _process(delta: float) -> void:
	if not bool(_sea.call("running")) or delta <= 0.0:
		return
	if wyrm != null and not is_instance_valid(wyrm):
		wyrm = null
	if wyrm == null:
		return
	phase += delta * (2.4 if mode == "surface" else 3.2)
	var model: Node3D = wyrm.get("_model")
	if model != null:
		lay_body(model, phase, rise, 0.4 if mode != "surface" else 0.25)
		var jaw_node := model.find_child("Jaw", true, false) as Node3D
		if jaw_node != null:
			jaw_node.rotation.x = jaw * 0.7
	if not _host():
		if _pending > 0.0 and _net() != null:
			_net().call("request_serpent_hit", _pending)
		_pending = 0.0
		return
	if bool(wyrm.get("health").is_dead()):
		return
	_drive(delta)


# Who it goes for: the ship the nearest player at sea is on (or that player in the water); null = nobody near.
func _quarry() -> Array:
	var best: Array = []
	var best_d := INF
	for who: Dictionary in get_parent().call("players"):
		var at: Vector3 = _sea.call("world_of", Vector3((who["at"] as Vector2).x, 0.0, (who["at"] as Vector2).y))
		var d := Vector2(at.x - wyrm.global_position.x, at.z - wyrm.global_position.z).length()
		if d < best_d:
			best_d = d
			best = [who["ship"], at]
	return best if best_d <= float(cfg["lose_m"]) else []


func _drive(delta: float) -> void:
	var q := _quarry()
	if q.is_empty():
		last = "lost everyone: back to the deep"
		_remove()
		return
	_target_ship = q[0]
	var mark: Vector3 = q[1]  # where its quarry is
	var side_spot := mark
	if _target_ship != null:
		var st: Dictionary = _target_ship.get("state")
		var right := Vector3(cos(float(st["yaw"])), 0.0, -sin(float(st["yaw"])))
		side_spot = _target_ship.global_position + right * _side * float(cfg["ring_m"])
	var here := wyrm.global_position
	var flat := Vector3(side_spot.x - here.x, 0.0, side_spot.z - here.z)
	var dmg := float(wyrm.get_meta("dmg", 1.0))
	var y_goal := _water(here) - 5.0
	var speed := float(cfg["speed"])
	_t -= delta
	match mode:
		"approach", "dive":
			rise = move_toward(rise, 0.0, delta * 0.8)
			jaw = move_toward(jaw, 0.0, delta * 2.0)
			speed = float(cfg["dive_speed"])
			if mode == "dive" and _t > 0.0:
				flat = flat.rotated(Vector3.UP, 0.6 * _side)  # swinging round under her keel
			if (mode == "approach" and flat.length() < 6.0) or (mode == "dive" and _t <= 0.0 and flat.length() < 10.0) or _t < -20.0:
				mode = "surface"
				_t = _rng.randf_range(float(cfg["surface_s"][0]), float(cfg["surface_s"][1]))
				_bite_t = float(cfg["bite_every"]) * 0.5
				_lunge_t = float(cfg["lunge_every"]) * 0.7
		"surface":
			y_goal = _water(here) + 1.1
			rise = move_toward(rise, 1.0, delta * 0.7)
			speed = float(cfg["speed"]) * (0.6 if flat.length() < 3.0 else 1.0)
			_bite_t -= delta
			_lunge_t -= delta
			if _windup > 0.0:  # rearing up: head high, jaw wide, still
				_windup -= delta
				jaw = move_toward(jaw, 1.0, delta * 3.0)
				y_goal = _water(here) + 3.2
				speed = 0.0
				if _windup <= 0.0:
					_strike(dmg)
			elif _lunge_t <= 0.0 and _pick_lunge():
				_windup = float(cfg["lunge_windup"])
				lunges += 1
			elif _bite_t <= 0.0 and _target_ship != null and flat.length() < 6.0:
				_bite_hull(dmg)
			else:
				jaw = move_toward(jaw, 0.15, delta * 2.0)
			if _t <= 0.0 and _windup <= 0.0:
				mode = "dive"
				_side = -_side
				_t = _rng.randf_range(float(cfg["dive_s"][0]), float(cfg["dive_s"][1]))
	var step := flat.normalized() * minf(speed * delta, flat.length())
	here += step
	here.y = move_toward(here.y, y_goal, 2.5 * delta)
	wyrm.global_position = here
	var face := (mark - here) if mode == "surface" else step
	face.y = 0.0
	if face.length() > 0.01:
		wyrm.rotation.y = lerp_angle(wyrm.rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-3.0 * delta))
	if mode != "surface":
		last = "%s, %.0f m to her side" % [mode, flat.length()]


func _bite_hull(dmg: float) -> void:
	_bite_t = float(cfg["bite_every"])
	jaw = 1.0
	hull_bites += 1
	var ship := _target_ship
	var local := ship.global_transform.affine_inverse() * wyrm.global_position
	var hull_hit := Vector3(clampf(local.x, -2.0, 2.0), 0.0, clampf(local.z, -6.0, 6.0))
	_fleet.get("hull_part").call("damage", ship, hull_hit, float(cfg["bite_hull"]) * dmg)
	last = "bit her hull"
	if _fleet.call("ship_aboard") == ship:
		_sea.emit_signal("notice", "The wyrm is biting the hull!")


# A player on her deck (or the one in the water) it can reach: where it will strike. False = none.
func _pick_lunge() -> bool:
	var bodies: Array = []
	if bool(_sea.get("inside")):
		bodies.append(_player)
	var net := _net()
	if net != null and bool(net.call("active")):
		for body: Node3D in (net.get("net") as Node).call("target_nodes"):
			if body.global_position.x < -10000.0:
				bodies.append(body)
	var best: Node3D = null
	var best_d := float(cfg["lunge_reach"])
	for body: Node3D in bodies:
		var d := body.global_position.distance_to(wyrm.global_position)
		if d < best_d:
			best_d = d
			best = body
	if best == null:
		_lunge_t = 1.0
		return false
	_strike_at = best.global_position
	last = "rearing up to strike"
	return true


func _strike(dmg: float) -> void:
	_lunge_t = float(cfg["lunge_every"])
	jaw = 0.3
	var head := wyrm.global_position
	var tween := wyrm.create_tween()  # the head darts at the spot and back
	tween.tween_property(wyrm, "global_position", _strike_at + Vector3(0.0, 0.6, 0.0), 0.18)
	tween.tween_property(wyrm, "global_position", head, 0.5)
	var hurt := 0
	var bodies: Array = [_player] if bool(_sea.get("inside")) else []
	var net := _net()
	if net != null and bool(net.call("active")):
		bodies.append_array((net.get("net") as Node).call("target_nodes"))
	for body: Node3D in bodies:
		if is_instance_valid(body) and body.global_position.distance_to(_strike_at) <= float(cfg["lunge_radius"]):
			body.call("take_damage", float(cfg["lunge_damage"]) * dmg, "physical")
			hurt += 1
	last = "struck (%d hurt)" % hurt


func _on_died(_enemy: Node) -> void:
	var at: Vector3 = _sea.call("local_of", wyrm.global_position) if is_instance_valid(wyrm) else Vector3.ZERO
	slain += 1
	last = "slain"
	if _host():
		var flotsam: Node = get_parent().get("flotsam")
		var region := String(wyrm.get_meta("region", "region_1")) if is_instance_valid(wyrm) else "region_1"
		flotsam.call("spill", at.x, at.z, String(cfg["loot"]), region)
		flotsam.call("add_piece", int(flotsam.get("_next_id")), at.x, at.z, 2, "serpent_trophy", region)  # its fang: the trophy, in the chest where it went down
		flotsam.set("_next_id", int(flotsam.get("_next_id")) + 1)
		var net := _net()
		if net != null:
			net.call("tell_serpent_died", _hitter)
	_sea.emit_signal("notice", String(cfg["slain_notice"]))
	var dead := wyrm
	wyrm = null
	mode = ""
	if is_instance_valid(dead):
		dead.get_tree().create_timer(6.0).timeout.connect(func() -> void:
			if is_instance_valid(dead):
				director.call("forget", dead)
				dead.queue_free())


# --- online ---

func to_net() -> Array:
	if wyrm == null or not is_instance_valid(wyrm):
		return []
	var p: Vector3 = _sea.call("local_of", wyrm.global_position)
	var hp: RefCounted = wyrm.get("health")
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(wyrm.rotation.y, 0.01), snappedf(float(hp.get("hp")) / maxf(float(hp.get("max_hp")), 1.0), 0.01), snappedf(rise, 0.01), snappedf(jaw, 0.01), mode]


func should_send() -> bool:
	var here := wyrm != null
	if here or _was_here:
		_was_here = here
		return true
	return false


func from_net(got: Array) -> void:
	if got.size() < 8:
		if wyrm != null and is_instance_valid(wyrm) and bool(wyrm.get("puppet")):
			_remove()
		return
	var at := Vector3(float(got[0]), float(got[1]), float(got[2]))
	if not at.is_finite():
		return
	if wyrm == null:
		_make(_stats.duplicate(), true)
		wyrm.global_position = _sea.call("world_of", at)
		_sea.emit_signal("notice", String(cfg["notice"]))
	wyrm.set("net_pos", (_fleet as Node3D).to_local(_sea.call("world_of", at)))
	wyrm.set("net_yaw", float(got[3]))
	var hp: RefCounted = wyrm.get("health")
	hp.set("hp", clampf(float(got[4]), 0.0, 1.0) * float(hp.get("max_hp")))
	rise = clampf(float(got[5]), 0.0, 1.0)
	jaw = clampf(float(got[6]), 0.0, 1.0)
	mode = String(got[7]).left(12)


func host_hit(damage: float, from: int) -> void:
	if wyrm == null or not is_finite(damage) or damage <= 0.0:
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null:
		card.set("blow", "other")
	_hitter = from
	wyrm.call("on_hit", minf(damage, 5000.0))
	_hitter = 0
	if card != null:
		card.set("blow", before)


func fell(killer: int, me: int) -> void:
	if wyrm == null or not is_instance_valid(wyrm):
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null and killer != me:
		card.set("blow", "other")
	wyrm.call("die_now")
	if card != null:
		card.set("blow", before)


func status() -> String:
	if wyrm == null:
		return "wyrm none (came %d, slain %d)" % [came, slain]
	var hp: RefCounted = wyrm.get("health")
	return "wyrm %s hp %.0f/%.0f rise %.2f, hull bites %d, lunges %d, last '%s' (came %d, slain %d)" % [mode, float(hp.get("hp")), float(hp.get("max_hp")), rise, hull_bites, lunges, last, came, slain]
