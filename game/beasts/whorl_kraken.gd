# Purpose: region 7's WHORL KRAKEN, the body (sea step 8e, director: "tentacles that grab the hull, hold the ship still
# and smash the deck until cut off"). It surfaces body_m off the side of the ship its quarry is on - a huge mantle with
# glowing whorls and great eyes, mostly under water - and sends ARMS (game/beasts/kraken_arm.gd, separate beasts:
# each one shot off on its own) up her sides. While any arm holds her she cannot move (her place kept). Cut arms grow
# back (one every regrow_s, up to arms). Killing the body (guns, cannons) ends it: its arms sink, its hoard floats.
# HOST: start / step; EVERY MACHINE: pose (the mantle breathes, the whorls turn). Numbers: data/sea/encounters.json
# beasts.whorl_kraken.
# Dependencies: game/sea_beasts.gd (the manager `m`: spawn_one, hold_ship, beside, ship_near).
extends RefCounted


static func start(m: Node, b: Dictionary) -> void:
	var c: Dictionary = m.call("cfg_of", "whorl_kraken")
	var e: Node3D = b["enemy"]
	var ship: Node3D = m.call("ship_near", e.global_position, 500.0)
	b["ship"] = ship
	b["side"] = 1.0 if (m.call("rng") as RandomNumberGenerator).randf() < 0.5 else -1.0
	b["side_i"] = int(b["side"])
	b["next_regrow"] = 0.0
	b["sent"] = 0
	if ship != null:
		e.global_position = m.call("beside", ship, float(b["side"]), float(c["body_m"]), 0.0, -float(c["depth"]))
		var ends: Vector2 = m.call("ship_length", ship)
		for i in int(c["arms"]):
			_arm(m, b, ship, ends, i)
	m.call("set_mode", b, "hold")


static func _arm(m: Node, b: Dictionary, ship: Node3D, ends: Vector2, i: int) -> void:
	var c: Dictionary = m.call("cfg_of", "whorl_kraken")
	var side := float(b["side"]) if i % 2 == 0 else -float(b["side"])  # (round both sides: it wraps her)
	var spread := float(c["arm_spread"])
	var lz := clampf(lerpf(ends.y + 2.0, ends.x - 2.0, (float(i % 4) + 0.5) / 4.0) + (m.call("rng") as RandomNumberGenerator).randf_range(-spread, spread), ends.y + 1.5, ends.x - 1.5)
	var root: Vector3 = m.call("beside", ship, side, 1.0, lz, -0.6)
	m.call("spawn_one", "kraken_arm", root - Vector3(0.0, 6.0, 0.0), int(b.get("region", 7)), {"body": int(b["id"]), "side": side, "side_i": int(side), "lz": lz, "ship": ship})
	b["sent"] = int(b["sent"]) + 1


static func step(m: Node, b: Dictionary, _delta: float) -> void:
	var c: Dictionary = m.call("cfg_of", "whorl_kraken")
	var e: Node3D = b["enemy"]
	var ship: Node3D = b["ship"] if is_instance_valid(b["ship"]) else m.call("ship_near", e.global_position, 500.0)
	b["ship"] = ship
	if ship == null:
		return
	var target: Vector3 = m.call("beside", ship, float(b["side"]), float(c["body_m"]), 0.0, -float(c["depth"]))
	e.global_position = e.global_position.lerp(target, 0.05)
	var to := ship.global_position - e.global_position
	e.rotation.y = atan2(-to.x, -to.z)
	var arms := 0
	for other: Dictionary in (m.get("beasts") as Dictionary).values():
		if int(other.get("body", -1)) == int(b["id"]):
			arms += 1
	var now := float(m.call("now"))
	if arms > 0:  # held fast
		if not b.has("held"):
			b["held"] = Vector2(float(ship.get("state")["x"]), float(ship.get("state")["z"]))
			(m.get("_sea") as Node).emit_signal("notice", String(c["hold_notice"]))
		m.call("hold_ship", ship, b["held"])
	else:
		b.erase("held")
	if arms < int(c["arms"]) and now >= float(b["next_regrow"]):
		if float(b["next_regrow"]) > 0.0:
			_arm(m, b, ship, m.call("ship_length", ship), int(b["sent"]))
		b["next_regrow"] = now + float(c["regrow_s"])


static func pose(_m: Node, b: Dictionary, _delta: float) -> void:
	var model: Node3D = (b["enemy"] as Node).get("_model")
	if model == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	if not model.has_meta("base_scale"):
		model.set_meta("base_scale", model.scale.y)
	var breath := 1.0 + 0.03 * sin(t * 1.1)
	model.scale = Vector3(breath, 1.0 / breath, breath) * float(model.get_meta("base_scale"))
