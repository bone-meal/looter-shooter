# Purpose: region 4's RIME ORCA POD (sea step 8e, director: "a pack that tips ice and snatches swimmers"). A pod of 3-4
# circles the ship its quarry is on, fins up. A player in the water is hunted: one orca rushes him and, within
# grab_m, SNATCHES him: dragged drag_m further out and under (his own machine) and hurt. Every tip_every s one orca
# dives and heaves up under her side: she TIPS hard to the other side for tip_s (every machine draws it), players on
# her deck slide toward the low rail and anyone already at that rail goes over into the sea; the blow also strains
# her hull. Shot at the surface. HOST: start / step; EVERY MACHINE: pose (flukes beat, a breach arc, the tip).
# Numbers: data/sea/encounters.json beasts.rime_orca.
# Dependencies: game/sea_beasts.gd (the manager `m`), core/sea/deck_walk.gd.
extends RefCounted

const DeckWalk = preload("res://core/sea/deck_walk.gd")


static func start(m: Node, b: Dictionary) -> void:
	var c: Dictionary = m.call("cfg_of", "rime_orca")
	var r: RandomNumberGenerator = m.call("rng")
	b["a"] = r.randf() * TAU
	b["ring"] = r.randf_range(float(c["ring_m"][0]), float(c["ring_m"][1]))
	b["next_tip"] = float(m.call("now")) + float(c["first_tip_s"]) + float(b["nth"]) * float(c["tip_every"][0])
	m.call("set_mode", b, "circle")


static func step(m: Node, b: Dictionary, delta: float) -> void:
	var c: Dictionary = m.call("cfg_of", "rime_orca")
	var e: Node3D = b["enemy"]
	var ship: Node3D = b["ship"] if is_instance_valid(b["ship"]) else m.call("ship_near", e.global_position, 260.0)
	b["ship"] = ship
	if ship == null:
		return
	var now := float(m.call("now"))
	var mode := String(b["mode"])
	var surface := float(m.call("water", e.global_position)) - float(c["depth"])
	if mode == "circle":
		b["a"] = float(b["a"]) + float(c["speed"]) / float(b["ring"]) * delta
		var spot := ship.global_position + Vector3(cos(float(b["a"])), 0.0, sin(float(b["a"]))) * float(b["ring"])
		_swim(e, spot, float(c["speed"]) * 1.4, surface, delta)
		var prey := _swimmer(m, e, float(c["hunt_m"]))
		if prey != null and now >= float(b.get("next_grab", 0.0)):
			b["prey"] = prey
			m.call("set_mode", b, "hunt")
		elif now >= float(b["next_tip"]):
			var local := ship.global_transform.affine_inverse() * e.global_position
			b["side_i"] = 1 if local.x >= 0.0 else -1
			m.call("set_mode", b, "dive")
	elif mode == "hunt":
		var prey2: Node3D = b.get("prey")
		if not is_instance_valid(prey2) or not _still_swimming(m, prey2) or float(b["t"]) > 15.0:
			m.call("set_mode", b, "circle")
			return
		_swim(e, prey2.global_position, float(c["rush_speed"]), surface, delta)
		if Vector2(e.global_position.x - prey2.global_position.x, e.global_position.z - prey2.global_position.z).length() <= float(c["grab_m"]):
			var away := prey2.global_position - ship.global_position
			away.y = 0.0
			var to := prey2.global_position + away.normalized() * float(c["drag_m"])
			m.call("snatch", prey2, (m.get("_sea") as Node).call("local_of", to), float(c["grab_damage"]) * float(b["mult"]))
			b["next_grab"] = now + float(c["grab_every"])
			m.call("set_mode", b, "circle")
	elif mode == "dive":  # under her side, then the heave
		var lz := 0.0
		var under: Vector3 = m.call("beside", ship, float(b["side_i"]), -0.5, lz, -3.0)
		_swim(e, under, float(c["rush_speed"]), under.y, delta)
		if e.global_position.distance_to(under) < 1.5 or float(b["t"]) > 6.0:
			_heave(m, b, c, ship)
			m.call("set_mode", b, "tip")
	elif mode == "tip":
		var out: Vector3 = m.call("beside", ship, float(b["side_i"]), 6.0, 0.0, 0.0)
		_swim(e, out, float(c["speed"]), surface + sin(clampf(float(b["t"]) / float(c["tip_s"]), 0.0, 1.0) * PI) * 1.5, delta)
		if float(b["t"]) >= float(c["tip_s"]):
			b["next_tip"] = now + (m.call("rng") as RandomNumberGenerator).randf_range(float(c["tip_every"][0]), float(c["tip_every"][1]))
			m.call("set_mode", b, "circle")


# The heave: her hull strained, her deck tips to the far side: everyone slides that way, those at that rail go over.
static func _heave(m: Node, b: Dictionary, c: Dictionary, ship: Node3D) -> void:
	m.call("count", "tips")
	var side := float(b["side_i"])
	m.call("hull_bite", ship, m.call("beside", ship, side, 0.0, 0.0, -0.6), float(c["tip_hull"]) * float(b["hull_mult"]))
	var spec: Dictionary = ship.get("spec")
	var low := -side  # the orca lifts this side: she rolls down to the other
	var push: Vector3 = ship.global_transform.basis.x.normalized() * low * float(c["slide_speed"])
	for who: Dictionary in m.call("players"):
		if who["ship"] != ship:
			continue
		var body: Node3D = who["body"]
		var local := ship.global_transform.affine_inverse() * body.global_position
		if local.x * low >= DeckWalk.half_width(spec, local.z) - float(c["rail_m"]):  # at the low rail: over she goes
			var over: Vector3 = m.call("beside", ship, low, 2.5, local.z, 0.0)
			m.call("snatch", body, (m.get("_sea") as Node).call("local_of", over), float(c["over_damage"]))
			m.call("count", "overboard")
		else:
			m.call("slide", body, push)


static func _swimmer(m: Node, e: Node3D, within: float) -> Node3D:
	for who: Dictionary in m.call("players"):
		if bool(who["swimming"]) and (who["body"] as Node3D).global_position.distance_to(e.global_position) <= within:
			return who["body"]
	return null


static func _still_swimming(m: Node, body: Node3D) -> bool:
	for who: Dictionary in m.call("players"):
		if who["body"] == body:
			return bool(who["swimming"])
	return false


static func _swim(e: Node3D, spot: Vector3, speed: float, y: float, delta: float) -> void:
	var way := spot - e.global_position
	way.y = 0.0
	e.global_position += way.limit_length(speed * delta)
	e.global_position.y = move_toward(e.global_position.y, y, 3.0 * delta)
	if way.length() > 0.05:
		e.rotation.y = lerp_angle(e.rotation.y, atan2(-way.x, -way.z), minf(delta * 3.0, 1.0))


static func pose(m: Node, b: Dictionary, _delta: float) -> void:
	var model: Node3D = (b["enemy"] as Node).get("_model")
	if model == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + float(b["id"]) * 0.9
	var fast := String(b["mode"]) in ["hunt", "dive"]
	var tail := model.find_child("Tail", true, false) as Node3D
	if tail != null:
		tail.rotation.x = sin(t * (5.0 if fast else 2.2)) * 0.35
	var jaw := model.find_child("Jaw", true, false) as Node3D
	if jaw != null:
		jaw.rotation.x = 0.4 if String(b["mode"]) == "hunt" else 0.0
	if String(b["mode"]) == "tip" and is_instance_valid(b["ship"]):  # her deck heaved over (every machine)
		var c: Dictionary = m.call("cfg_of", "rime_orca")
		var u := clampf(float(b["t"]) / float(c["tip_s"]), 0.0, 1.0)
		var ship: Node3D = b["ship"]
		ship.set("tip_deg", -float(b.get("side_i", 1)) * -1.0 * float(c["tip_deg"]) * sin(u * PI))
		ship.set_meta("tipping", true)
