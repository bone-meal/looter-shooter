# Purpose: region 5's SQUALLBEAKS (sea step 8e, director: "storm seabirds that dive-bomb the deck from sea stacks"; they
# come mostly in storms). A flock of 4-6 big seabirds wheels high over the ship its quarry is on; each in turn picks a
# player on her deck and DIVES on him (dive_s): within peck_m at the bottom it pecks (hurt + a small shove) and climbs
# back to the flock (climb_s). Shot out of the air. HOST: start / step; EVERY MACHINE: pose (wings beat, folded in the
# dive). Numbers: data/sea/encounters.json beasts.squallbeak.
# Dependencies: game/sea_beasts.gd (the manager `m`).
extends RefCounted


static func start(m: Node, b: Dictionary) -> void:
	var c: Dictionary = m.call("cfg_of", "squallbeak")
	var r: RandomNumberGenerator = m.call("rng")
	b["a"] = r.randf() * TAU
	b["ring"] = r.randf_range(float(c["ring_m"][0]), float(c["ring_m"][1]))
	b["height"] = r.randf_range(float(c["height_m"][0]), float(c["height_m"][1]))
	b["next"] = float(m.call("now")) + float(c["first_dive_s"]) + float(b["nth"]) * 1.7
	var e: Node3D = b["enemy"]
	e.global_position.y = float(m.call("water", e.global_position)) + float(b["height"])
	m.call("set_mode", b, "wheel")


static func step(m: Node, b: Dictionary, delta: float) -> void:
	var c: Dictionary = m.call("cfg_of", "squallbeak")
	var e: Node3D = b["enemy"]
	var ship: Node3D = b["ship"] if is_instance_valid(b["ship"]) else m.call("ship_near", e.global_position, 300.0)
	b["ship"] = ship
	var centre := ship.global_position if ship != null else e.global_position
	var now := float(m.call("now"))
	var mode := String(b["mode"])
	if mode == "wheel":
		b["a"] = float(b["a"]) + float(c["speed"]) / float(b["ring"]) * delta
		var spot := centre + Vector3(cos(float(b["a"])), 0.0, sin(float(b["a"]))) * float(b["ring"])
		spot.y = float(m.call("water", centre)) + float(b["height"])
		_fly(e, spot, float(c["speed"]) * 1.5, delta)
		if ship != null and now >= float(b["next"]):
			var prey := _on_deck(m, ship)
			if prey != null:
				b["prey"] = prey
				b["from"] = e.global_position
				m.call("set_mode", b, "dive")
			else:
				b["next"] = now + 3.0
	elif mode == "dive":
		var prey2: Node3D = b.get("prey")
		var u := clampf(float(b["t"]) / float(c["dive_s"]), 0.0, 1.0)
		var goal: Vector3 = prey2.global_position + Vector3(0.0, 1.5, 0.0) if is_instance_valid(prey2) else centre
		var p: Vector3 = (b["from"] as Vector3).lerp(goal, u * u)
		var way := p - e.global_position
		e.global_position = p
		if way.length() > 0.01:
			e.look_at(e.global_position + way, Vector3.UP)
		if u >= 1.0:
			if is_instance_valid(prey2) and prey2.global_position.distance_to(e.global_position - Vector3(0.0, 1.5, 0.0)) <= float(c["peck_m"]):
				var push := Vector3(way.x, 0.0, way.z).normalized() * float(c["peck_push"])
				m.call("knock", prey2, push, float(c["peck_damage"]) * float(b["mult"]))
				m.call("count", "pecks")
			b["from"] = e.global_position
			m.call("set_mode", b, "climb")
	elif mode == "climb":
		var u2 := clampf(float(b["t"]) / float(c["climb_s"]), 0.0, 1.0)
		var top := centre + Vector3(cos(float(b["a"])), 0.0, sin(float(b["a"]))) * float(b["ring"])
		top.y = float(m.call("water", centre)) + float(b["height"])
		e.global_position = (b["from"] as Vector3).lerp(top, u2)
		e.rotation.x = 0.0
		e.rotation.z = 0.0
		if u2 >= 1.0:
			b["next"] = now + (m.call("rng") as RandomNumberGenerator).randf_range(float(c["dive_every"][0]), float(c["dive_every"][1]))
			m.call("set_mode", b, "wheel")


static func _on_deck(m: Node, ship: Node3D) -> Node3D:
	var on: Array = []
	for who: Dictionary in m.call("players"):
		if who["ship"] == ship:
			on.append(who["body"])
	if on.is_empty():
		return null
	return on[(m.call("rng") as RandomNumberGenerator).randi() % on.size()]


static func _fly(e: Node3D, spot: Vector3, speed: float, delta: float) -> void:
	var way := spot - e.global_position
	e.global_position += way.limit_length(speed * delta)
	if Vector2(way.x, way.z).length() > 0.05:
		e.rotation = Vector3(0.0, lerp_angle(e.rotation.y, atan2(-way.x, -way.z), minf(delta * 3.0, 1.0)), sin(Time.get_ticks_msec() / 900.0) * 0.25)


static func pose(_m: Node, b: Dictionary, _delta: float) -> void:
	var model: Node3D = (b["enemy"] as Node).get("_model")
	if model == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + float(b["id"]) * 0.7
	var mode := String(b["mode"])
	var beat := 0.65 if mode == "dive" else (sin(t * 7.0) * 0.55 if mode == "climb" else sin(t * 2.5) * 0.18)  # folded back in the dive, hard beats climbing, gliding on the wind
	for wing: String in ["WingL", "WingR"]:
		var w := model.find_child(wing, true, false) as Node3D
		if w != null:
			w.rotation.z = beat if wing == "WingL" else -beat
			w.rotation.y = (0.6 if wing == "WingL" else -0.6) if mode == "dive" else 0.0
