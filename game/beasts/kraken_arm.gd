# Purpose: one ARM of the Whorl Kraken (sea step 8e; its body is game/beasts/whorl_kraken.gd). It rises out of the
# water at her side, curls up over the rail onto her deck and HOLDS (while any arm holds she cannot move); every
# slam_every s it rears up (windup_s) and SMASHES down on the deck by it: players within slam_m are knocked flat and
# hurt, her hull takes a blow. Shot enough it is cut off and sinks (the body grows another). HOST: start / step;
# EVERY MACHINE: pose (each of its six chained segments turned a little: the curl over the rail, the rear, the slam,
# a writhe). Numbers: data/sea/encounters.json beasts.kraken_arm.
# Dependencies: game/sea_beasts.gd (the manager `m`), core/sea/deck_walk.gd.
extends RefCounted

const DeckWalk = preload("res://core/sea/deck_walk.gd")


static func start(m: Node, b: Dictionary) -> void:
	var c: Dictionary = m.call("cfg_of", "kraken_arm")
	b["next"] = float(m.call("now")) + float(c["rise_s"]) + (m.call("rng") as RandomNumberGenerator).randf_range(float(c["slam_every"][0]), float(c["slam_every"][1]))
	m.call("count", "grabs")
	m.call("set_mode", b, "rise")


static func step(m: Node, b: Dictionary, _delta: float) -> void:
	var c: Dictionary = m.call("cfg_of", "kraken_arm")
	var e: Node3D = b["enemy"]
	var ship: Node3D = b["ship"]
	if not is_instance_valid(ship):
		return
	var side := float(b["side"])
	var root: Vector3 = m.call("beside", ship, side, float(c["out_m"]), float(b["lz"]), -0.6)
	var mode := String(b["mode"])
	var now := float(m.call("now"))
	if mode == "rise":
		var u := clampf(float(b["t"]) / float(c["rise_s"]), 0.0, 1.0)
		e.global_position = root - Vector3(0.0, (1.0 - u) * 6.0, 0.0)
		if u >= 1.0:
			m.call("set_mode", b, "hold")
	else:
		e.global_position = root
	var bx := ship.global_transform.basis.x
	e.rotation.y = atan2(side * bx.x, side * bx.z)  # its front (the suckers) toward her
	if mode == "hold" and now >= float(b["next"]):
		m.call("set_mode", b, "raise")
	elif mode == "raise" and float(b["t"]) >= float(c["windup_s"]):
		m.call("set_mode", b, "slam")
	elif mode == "slam" and float(b["t"]) >= float(c["slam_s"]):
		_smash(m, b, c, ship)
		b["next"] = now + (m.call("rng") as RandomNumberGenerator).randf_range(float(c["slam_every"][0]), float(c["slam_every"][1]))
		m.call("set_mode", b, "hold")


# The blow on her deck beside it: players near are knocked flat, her hull takes it.
static func _smash(m: Node, b: Dictionary, c: Dictionary, ship: Node3D) -> void:
	m.call("count", "slams")
	var spec: Dictionary = ship.get("spec")
	var side := float(b["side"])
	var lz := float(b["lz"])
	var x := side * maxf(DeckWalk.half_width(spec, lz) - float(c["reach_in"]), 0.3)
	var spot: Vector3 = ship.global_transform * Vector3(x, float(spec["deck"]), lz)
	for who: Dictionary in m.call("players"):
		var body: Node3D = who["body"]
		if who["ship"] == ship and Vector2(body.global_position.x - spot.x, body.global_position.z - spot.z).length() <= float(c["slam_m"]):
			var away := body.global_position - spot
			away.y = 0.0
			m.call("knock", body, (away.normalized() if away.length() > 0.1 else ship.global_transform.basis.x * -side) * float(c["slam_push"]), float(c["slam_damage"]) * float(b["mult"]))
	m.call("hull_bite", ship, m.call("beside", ship, side, 0.0, lz, 0.6), float(c["slam_hull"]) * float(b["mult"]))


static func pose(_m: Node, b: Dictionary, delta: float) -> void:
	var model: Node3D = (b["enemy"] as Node).get("_model")
	if model == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + float(b["id"]) * 0.6
	var mode := String(b["mode"])
	var want := -0.52  # curled over the rail onto her deck
	var speed := 3.0
	if mode == "rise":
		want = -0.2
	elif mode == "raise":
		want = -0.08  # reared up high
		speed = 2.5
	elif mode == "slam":
		want = -0.62
		speed = 14.0
	var curl := move_toward(float(b.get("curl", -0.1)), want, speed * delta)
	b["curl"] = curl
	for i in 6:
		var seg := model.find_child("Seg%d" % (i + 1), true, false) as Node3D
		if seg != null:
			var writhe := sin(t * 2.0 - float(i) * 0.7) * (0.05 if mode == "hold" else 0.02)
			seg.rotation = Vector3((curl * (0.4 if i == 0 else 1.0)) + writhe, 0.0, sin(t * 1.3 - float(i)) * 0.06)
