# Purpose: region 2's FOGMAW (sea step 8e, director: "an eel that shows only a glowing lure in fog and snatches a
# player off the rail"; it comes only in fog). It LURKS beside the ship its quarry is on, under water with just its
# lure glowing at the surface; when a player stands near the rail on its side it RISES (rise_s: the head comes up
# over the rail, jaw open) and if he is still within snatch_reach it SNATCHES him into the sea throw_m off her side
# (his own machine) and SINKS, to lurk again elsewhere along her (every s). With nobody at the rail it bites her hull
# now and then; a player swimming near it gets bitten. Shot at the lure or the head. HOST: start / step; EVERY
# MACHINE: pose (lure bob, jaw, the five body segments trailing in a sinuous line, deeper behind). Numbers:
# data/sea/encounters.json beasts.fogmaw.
# Dependencies: game/sea_beasts.gd (the manager `m`), core/sea/deck_walk.gd.
extends RefCounted

const DeckWalk = preload("res://core/sea/deck_walk.gd")


static func start(m: Node, b: Dictionary) -> void:
	b["side"] = 1.0 if (m.call("rng") as RandomNumberGenerator).randf() < 0.5 else -1.0
	b["lz"] = 0.0
	b["next"] = float(m.call("now")) + 4.0
	b["next_bite"] = float(m.call("now")) + float(m.call("cfg_of", "fogmaw")["hull_every"])
	m.call("set_mode", b, "lurk")


static func step(m: Node, b: Dictionary, delta: float) -> void:
	var c: Dictionary = m.call("cfg_of", "fogmaw")
	var e: Node3D = b["enemy"]
	var ship: Node3D = b["ship"] if is_instance_valid(b["ship"]) else m.call("ship_near", e.global_position, 260.0)
	b["ship"] = ship
	var now := float(m.call("now"))
	if ship == null:
		e.global_position.y = move_toward(e.global_position.y, float(m.call("water", e.global_position)) - 3.0, delta)
		return
	var side := float(b["side"])
	var mode := String(b["mode"])
	var lurk_at: Vector3 = m.call("beside", ship, side, float(c["lurk_m"]), float(b["lz"]), -float(c["lurk_depth"]))
	var face := atan2(side * ship.global_transform.basis.x.x, side * ship.global_transform.basis.x.z)  # facing her side
	if mode == "lurk":
		e.global_position = e.global_position.lerp(lurk_at, minf(delta * 1.5, 1.0))
		e.rotation.y = lerp_angle(e.rotation.y, face, 0.1)
		_bite_swimmers(m, b, c, now)
		if now < float(b["next"]):
			return
		var target := _at_rail(m, ship, side, float(b["lz"]), c)
		if target != null:
			b["target"] = target
			m.call("set_mode", b, "rise")
		elif now >= float(b["next_bite"]):  # nobody to take: it gnaws her hull
			b["next_bite"] = now + float(c["hull_every"])
			m.call("hull_bite", ship, m.call("beside", ship, side, 0.0, float(b["lz"]), -0.3), float(c["hull_bite"]) * float(b["hull_mult"]))
			_move_along(m, b, ship)
	elif mode == "rise":
		var up: Vector3 = m.call("beside", ship, side, 0.6, float(b["lz"]), float((ship.get("spec") as Dictionary)["deck"]) + 0.3)
		var u := clampf(float(b["t"]) / float(c["rise_s"]), 0.0, 1.0)
		e.global_position = lurk_at.lerp(up, u * u)
		e.rotation.y = face
		if u >= 1.0:
			var target: Node3D = b.get("target")
			if is_instance_valid(target) and target.global_position.distance_to(e.global_position) <= float(c["snatch_reach"]):
				var throw_at: Vector3 = m.call("beside", ship, side, float(c["throw_m"]), float(b["lz"]), 0.0)
				m.call("snatch", target, (m.get("_sea") as Node).call("local_of", throw_at), float(c["snatch_damage"]) * float(b["mult"]))
			m.call("set_mode", b, "sink")
	elif mode == "sink":
		e.global_position = e.global_position.lerp(lurk_at, minf(delta * 2.0, 1.0))
		if float(b["t"]) >= float(c["sink_s"]):
			_move_along(m, b, ship)
			b["next"] = now + (m.call("rng") as RandomNumberGenerator).randf_range(float(c["every"][0]), float(c["every"][1]))
			m.call("set_mode", b, "lurk")


# A player standing at the rail on this side, near enough along her to reach.
static func _at_rail(m: Node, ship: Node3D, side: float, lz: float, c: Dictionary) -> Node3D:
	var spec: Dictionary = ship.get("spec")
	for who: Dictionary in m.call("players"):
		if who["ship"] != ship:
			continue
		var local := ship.global_transform.affine_inverse() * (who["body"] as Node3D).global_position
		if local.x * side >= DeckWalk.half_width(spec, local.z) - float(c["rail_m"]) and absf(local.z - lz) <= float(c["along_m"]):
			return who["body"]
	for who: Dictionary in m.call("players"):  # nobody here: shift along her toward one at this rail
		if who["ship"] == ship:
			var local2 := ship.global_transform.affine_inverse() * (who["body"] as Node3D).global_position
			if local2.x * side >= DeckWalk.half_width(spec, local2.z) - float(c["rail_m"]):
				return null
	return null


static func _move_along(m: Node, b: Dictionary, ship: Node3D) -> void:
	var r: RandomNumberGenerator = m.call("rng")
	var spec: Dictionary = ship.get("spec")
	var ends: Vector2 = m.call("ship_length", ship)
	var best_z := r.randf_range(ends.y + 2.0, ends.x - 2.0)
	var best_side := 1.0 if r.randf() < 0.5 else -1.0
	for who: Dictionary in m.call("players"):  # go where a player is near a rail
		if who["ship"] == ship:
			var local := ship.global_transform.affine_inverse() * (who["body"] as Node3D).global_position
			if absf(local.x) >= DeckWalk.half_width(spec, local.z) - 2.0:
				best_z = clampf(local.z, ends.y + 1.5, ends.x - 1.5)
				best_side = signf(local.x)
	b["lz"] = best_z
	b["side"] = best_side


static func _bite_swimmers(m: Node, b: Dictionary, c: Dictionary, now: float) -> void:
	if now < float(b.get("next_swim_bite", 0.0)):
		return
	var e: Node3D = b["enemy"]
	for who: Dictionary in m.call("players"):
		if bool(who["swimming"]) and (who["body"] as Node3D).global_position.distance_to(e.global_position) <= float(c["swim_bite_m"]):
			(who["body"] as Node).call("take_damage", float(c["swim_bite"]) * float(b["mult"]), "physical")
			b["next_swim_bite"] = now + 2.0
			m.call("count", "bites")
			return


static func pose(_m: Node, b: Dictionary, _delta: float) -> void:
	var model: Node3D = (b["enemy"] as Node).get("_model")
	if model == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + float(b["id"])
	var mode := String(b["mode"])
	var jaw := model.find_child("Jaw", true, false) as Node3D
	if jaw != null:
		jaw.rotation.x = lerpf(jaw.rotation.x, 0.65 if mode == "rise" else 0.05 + 0.04 * sin(t * 2.0), 0.15)
	var lure := model.find_child("Lure", true, false) as Node3D
	if lure != null:
		lure.rotation.x = sin(t * 1.3) * 0.15
		lure.visible = mode != "rise"  # it rises with the lure dark (the light goes out before it strikes)
	var head := model.find_child("Head", true, false) as Node3D
	if head != null:
		head.rotation.x = -0.9 if mode == "rise" else 0.0  # reared up over the rail
	for i in 5:
		var seg := model.find_child("Seg%d" % (i + 1), true, false) as Node3D
		if seg != null:  # each a little deeper and swaying behind the one before
			seg.rotation.y = sin(t * 1.6 - float(i) * 0.8) * 0.25
			seg.rotation.x = (0.35 if mode == "rise" else 0.08) * float(i + 1) * 0.3
