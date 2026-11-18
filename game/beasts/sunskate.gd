# Purpose: region 1's SUNSKATE (sea step 8e, director: "a giant manta that leaps over the deck, knocking players
# flat"). A school of 2-3 glides round the ship its quarry is on, wing tips cutting the surface; now and then one
# LEAPS: a high arc from one side of her clean over the deck to the other, and every player within knock_m of its
# path where it crosses the deck is knocked flat (thrown along its flight and hurt). It glides on from where it
# came down, then leaps again. Shot in the air or in the water. HOST: start / step; EVERY MACHINE: pose (wings flap,
# a dive into the water). Numbers: data/sea/encounters.json beasts.sunskate.
# Dependencies: game/sea_beasts.gd (the manager `m`: players, ship_near, water, knock, set_mode, cfg_of, rng, now).
extends RefCounted


static func start(m: Node, b: Dictionary) -> void:
	var c: Dictionary = m.call("cfg_of", "sunskate")
	var r: RandomNumberGenerator = m.call("rng")
	b["a"] = r.randf() * TAU
	b["ring"] = r.randf_range(float(c["ring_m"][0]), float(c["ring_m"][1]))
	b["next"] = float(m.call("now")) + r.randf_range(2.0, float(c["leap_every"][1])) + float(b["nth"]) * 2.5
	m.call("set_mode", b, "swim")


static func step(m: Node, b: Dictionary, delta: float) -> void:
	var c: Dictionary = m.call("cfg_of", "sunskate")
	var e: Node3D = b["enemy"]
	var ship: Node3D = b["ship"] if is_instance_valid(b["ship"]) else m.call("ship_near", e.global_position, 220.0)
	b["ship"] = ship
	var centre := ship.global_position if ship != null else e.global_position
	if String(b["mode"]) == "leap":
		var u := clampf(float(b["t"]) / float(c["leap_s"]), 0.0, 1.0)
		var from: Vector3 = b["from"]
		var to: Vector3 = b["to"]
		var p := from.lerp(to, u)
		p.y = lerpf(from.y, to.y, u) + sin(u * PI) * float(b["apex"])
		var way := to - from
		e.global_position = p
		e.rotation = Vector3(-atan2(cos(u * PI) * float(b["apex"]) * PI, Vector2(way.x, way.z).length()) * 0.6, atan2(-way.x, -way.z), 0.0)
		if u >= 0.5 and not bool(b.get("struck", false)):  # over her deck: whoever stands under the arc is knocked flat
			b["struck"] = true
			for who: Dictionary in m.call("players"):
				var body: Node3D = who["body"]
				if Vector2(body.global_position.x - p.x, body.global_position.z - p.z).length() <= float(c["knock_m"]) and absf(body.global_position.y + 1.0 - p.y) < 4.5:
					var push := Vector3(way.x, 0.0, way.z).normalized() * float(c["knock_push"])
					m.call("knock", body, push, float(c["knock_damage"]) * float(b["mult"]))
		if u >= 1.0:
			b["a"] = atan2(to.z - centre.z, to.x - centre.x)
			b["next"] = float(m.call("now")) + (m.call("rng") as RandomNumberGenerator).randf_range(float(c["leap_every"][0]), float(c["leap_every"][1]))
			e.rotation.x = 0.0
			m.call("set_mode", b, "swim")
		return
	# gliding round her (or round where she was)
	b["a"] = float(b["a"]) + float(c["speed"]) / maxf(float(b["ring"]), 1.0) * delta * (1.0 if int(b["nth"]) % 2 == 0 else -1.0)
	var a := float(b["a"])
	var spot := centre + Vector3(cos(a), 0.0, sin(a)) * float(b["ring"])
	spot.y = float(m.call("water", spot)) - float(c["depth"])
	var step_v := spot - e.global_position
	e.global_position += step_v.limit_length(float(c["speed"]) * 1.6 * delta)
	if Vector2(step_v.x, step_v.z).length() > 0.05:
		e.rotation.y = lerp_angle(e.rotation.y, atan2(-step_v.x, -step_v.z), 0.15)
	if ship != null and float(m.call("now")) >= float(b["next"]):
		var from := e.global_position
		var across := ship.global_position - from
		across.y = 0.0
		var to := ship.global_position + across.normalized() * maxf(across.length(), 8.0)
		to.y = float(m.call("water", to)) - float(c["depth"])
		b["from"] = from
		b["to"] = to
		b["apex"] = float((ship.get("spec") as Dictionary)["deck"]) + float(c["leap_height"])
		b["struck"] = false
		m.call("count", "leaps")
		m.call("set_mode", b, "leap")


static func pose(_m: Node, b: Dictionary, _delta: float) -> void:
	var model: Node3D = (b["enemy"] as Node).get("_model")
	if model == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + float(b["id"]) * 1.7
	var leap := String(b["mode"]) == "leap"
	var flap := (0.55 + 0.25 * sin(t * 6.0)) if leap else sin(t * 1.8) * 0.28
	for wing: String in ["WingL", "WingR"]:
		var w := model.find_child(wing, true, false) as Node3D
		if w != null:
			w.rotation.z = flap if wing == "WingL" else -flap
	var tail := model.find_child("Tail", true, false) as Node3D
	if tail != null:
		tail.rotation.y = sin(t * 2.4) * 0.35
