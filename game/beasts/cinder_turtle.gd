# Purpose: region 3's CINDER TURTLE (sea step 8e, director: "rams hulls and leaves burning patches on deck"). A huge
# turtle with magma vents in its basalt shell circles the ship its quarry is on, then CHARGES her side and RAMS:
# hull damage where it strikes (holes like a cannon hit) and its vents spit fire onto her deck: burning patches
# (fires_per_ram, fire_s each) that hurt whoever stands in them. It backs off and circles to ram again. Slow and
# very tough. HOST: start / step; EVERY MACHINE: pose (flippers paddle, vents pulse, head bobs). Numbers:
# data/sea/encounters.json beasts.cinder_turtle.
# Dependencies: game/sea_beasts.gd (the manager `m`), core/sea/deck_walk.gd.
extends RefCounted

const DeckWalk = preload("res://core/sea/deck_walk.gd")


static func start(m: Node, b: Dictionary) -> void:
	var c: Dictionary = m.call("cfg_of", "cinder_turtle")
	b["a"] = (m.call("rng") as RandomNumberGenerator).randf() * TAU
	b["next"] = float(m.call("now")) + float(c["first_ram_s"])
	m.call("set_mode", b, "circle")


static func step(m: Node, b: Dictionary, delta: float) -> void:
	var c: Dictionary = m.call("cfg_of", "cinder_turtle")
	var e: Node3D = b["enemy"]
	var ship: Node3D = b["ship"] if is_instance_valid(b["ship"]) else m.call("ship_near", e.global_position, 260.0)
	b["ship"] = ship
	if ship == null:
		return
	var mode := String(b["mode"])
	var now := float(m.call("now"))
	var float_y := float(m.call("water", e.global_position)) - float(c["depth"])
	if mode == "circle":
		b["a"] = float(b["a"]) + float(c["speed"]) / float(c["circle_m"]) * delta
		var spot := ship.global_position + Vector3(cos(float(b["a"])), 0.0, sin(float(b["a"]))) * float(c["circle_m"])
		_swim_to(e, spot, float(c["speed"]) * 1.4, float_y, delta)
		if now >= float(b["next"]):
			var spec: Dictionary = ship.get("spec")
			var local := ship.global_transform.affine_inverse() * e.global_position
			b["side"] = signf(local.x) if absf(local.x) > 0.1 else 1.0
			var ends: Vector2 = m.call("ship_length", ship)
			b["lz"] = clampf(local.z, ends.y + 2.0, ends.x - 2.0)
			b["hw"] = DeckWalk.half_width(spec, float(b["lz"]))
			m.call("set_mode", b, "charge")
	elif mode == "charge":
		var hit_at: Vector3 = m.call("beside", ship, float(b["side"]), 1.2 + float(c["reach"]), float(b["lz"]), 0.0)
		_swim_to(e, hit_at, float(c["ram_speed"]), float_y, delta)
		if Vector2(e.global_position.x - hit_at.x, e.global_position.z - hit_at.z).length() < 1.0 or float(b["t"]) > 12.0:
			_ram(m, b, c, ship)
			m.call("set_mode", b, "back")
	elif mode == "back":
		var away := e.global_position - ship.global_position
		away.y = 0.0
		_swim_to(e, e.global_position + away.normalized() * 4.0, float(c["speed"]), float_y, delta, true)
		if float(b["t"]) >= float(c["back_s"]):
			b["a"] = atan2(away.z, away.x)
			b["next"] = now + (m.call("rng") as RandomNumberGenerator).randf_range(float(c["ram_every"][0]), float(c["ram_every"][1]))
			m.call("set_mode", b, "circle")


static func _swim_to(e: Node3D, spot: Vector3, speed: float, y: float, delta: float, backwards := false) -> void:
	var way := spot - e.global_position
	way.y = 0.0
	e.global_position += way.limit_length(speed * delta)
	e.global_position.y = move_toward(e.global_position.y, y, delta)
	if way.length() > 0.05:
		var yaw := atan2(-way.x, -way.z) + (PI if backwards else 0.0)
		e.rotation.y = lerp_angle(e.rotation.y, yaw, minf(delta * 2.0, 1.0))


# The ram: her hull holed at the point it hit, and fire spat onto her deck on that side.
static func _ram(m: Node, b: Dictionary, c: Dictionary, ship: Node3D) -> void:
	var side := float(b["side"])
	var lz := float(b["lz"])
	m.call("count", "rams")
	m.call("hull_bite", ship, m.call("beside", ship, side, 0.0, lz, 0.4), float(c["ram_damage"]) * float(b["hull_mult"]))
	var r: RandomNumberGenerator = m.call("rng")
	var hw := float(b["hw"])
	for i in r.randi_range(int(c["fires_per_ram"][0]), int(c["fires_per_ram"][1])):
		var x := side * r.randf_range(0.3, maxf(hw - 0.7, 0.5))
		var z := lz + r.randf_range(-2.5, 2.5)
		m.call("add_fire", ship, x, z, float(c["fire_s"]))
	(m.get("_sea") as Node).emit_signal("notice", String(c["ram_notice"]))


static func pose(_m: Node, b: Dictionary, _delta: float) -> void:
	var model: Node3D = (b["enemy"] as Node).get("_model")
	if model == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + float(b["id"])
	var fast := 2.6 if String(b["mode"]) == "charge" else 1.2
	for name: String in ["FlipFL", "FlipFR", "FlipBL", "FlipBR"]:
		var f := model.find_child(name, true, false) as Node3D
		if f != null:
			var phase := t * fast + (0.0 if name.ends_with("L") else PI) + (0.0 if name.begins_with("FlipF") else 0.8)
			f.rotation.z = sin(phase) * (0.45 if name.begins_with("FlipF") else 0.25) * (1.0 if name.ends_with("L") else -1.0)
			f.rotation.y = cos(phase) * 0.25
	var vents := model.find_child("Vents", true, false) as Node3D
	if vents != null:
		var s := 1.0 + 0.04 * sin(t * (6.0 if String(b["mode"]) == "charge" else 2.5))
		vents.scale = Vector3(s, s, s)
	var head := model.find_child("Head", true, false) as Node3D
	if head != null:
		head.rotation.x = sin(t * 0.9) * 0.08 + (-0.15 if String(b["mode"]) == "charge" else 0.0)
