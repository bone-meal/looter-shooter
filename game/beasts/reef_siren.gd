# Purpose: region 6's REEF SIRENS (sea step 8e, director: "sing from rocks and drag your rudder off course until shot").
# 2-3 sirens come up on reef rocks round the ship their quarry is on, ahead of her bow, and SING: while any sings
# within sing_m, her heading is dragged toward the nearest singer (pull_deg a second, stronger nearer, whatever the
# helmsman does): left alone she runs onto the rocks (they are solid: running aground holes her). Each siren dies to
# shots (her rock sinks with her). HOST: start / step; EVERY MACHINE: pose (her rock, singing arms, notes rising).
# Numbers: data/sea/encounters.json beasts.reef_siren.
# Dependencies: game/sea_beasts.gd (the manager `m`), game/fantasy_models.gd (the rock), game/fx_kit.gd.
extends RefCounted

const FantasyModels = preload("res://game/fantasy_models.gd")
const FxKit = preload("res://game/fx_kit.gd")


static func start(m: Node, b: Dictionary) -> void:
	var c: Dictionary = m.call("cfg_of", "reef_siren")
	var e: Node3D = b["enemy"]
	var ship: Node3D = m.call("ship_near", e.global_position, 400.0)
	b["ship"] = ship
	if ship != null:  # her rock: ahead of the bow, spread across it
		var r: RandomNumberGenerator = m.call("rng")
		var fwd := -ship.global_transform.basis.z
		fwd.y = 0.0
		var right := ship.global_transform.basis.x
		var spread := (float(b["nth"]) - 1.0) * float(c["spread_m"]) + r.randf_range(-5.0, 5.0)
		var at := ship.global_position + fwd.normalized() * r.randf_range(float(c["ahead_m"][0]), float(c["ahead_m"][1])) + right.normalized() * spread
		e.global_position = Vector3(at.x, float(m.call("water", at)) + float(c["seat_y"]), at.z)
	b["side_i"] = 0
	m.call("set_mode", b, "sing")


static func step(m: Node, b: Dictionary, delta: float) -> void:
	var c: Dictionary = m.call("cfg_of", "reef_siren")
	var e: Node3D = b["enemy"]
	var ship: Node3D = b["ship"] if is_instance_valid(b["ship"]) else m.call("ship_near", e.global_position, 400.0)
	b["ship"] = ship
	e.global_position.y = float(m.call("water", e.global_position)) + float(c["seat_y"])
	if ship == null:
		return
	var to := e.global_position - ship.global_position
	to.y = 0.0
	if to.length() > float(c["sing_m"]):
		return
	e.rotation.y = atan2(to.x, to.z)  # she faces the ship
	if not _nearest(m, b, ship):
		return  # the nearest singer drags her; the others only sing
	var st: Dictionary = ship.get("state")
	var want := atan2(-to.x, -to.z)  # her yaw that would point her bow at this siren
	var turn := wrapf(want - float(st["yaw"]), -PI, PI)
	var pull := deg_to_rad(float(c["pull_deg"])) * clampf(float(c["sing_m"]) / maxf(to.length(), 8.0), 1.0, 3.0) * 0.5
	st["yaw"] = float(st["yaw"]) + clampf(turn, -pull * delta, pull * delta)
	m.call("count", "pulling")


static func _nearest(m: Node, b: Dictionary, ship: Node3D) -> bool:
	var mine := (b["enemy"] as Node3D).global_position.distance_to(ship.global_position)
	for other: Dictionary in (m.get("beasts") as Dictionary).values():
		if other != b and String(other["kind"]) == "reef_siren" and is_instance_valid(other["enemy"]) and (other["enemy"] as Node3D).global_position.distance_to(ship.global_position) < mine:
			return false
	return true


static func pose(m: Node, b: Dictionary, _delta: float) -> void:
	var e: Node3D = b["enemy"]
	if not b.has("extra"):  # her rock (every machine; solid, so a ship runs aground on it)
		var c: Dictionary = m.call("cfg_of", "reef_siren")
		var own: Array[StandardMaterial3D] = []
		var rock := StaticBody3D.new()
		rock.collision_layer = 1
		rock.collision_mask = 0
		var model := FantasyModels.creature("sea_siren_rock", Color(1, 1, 1), own)
		if model != null:
			rock.add_child(model)
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 2.0
		cyl.height = 4.0
		shape.shape = cyl
		shape.position.y = -0.5
		rock.add_child(shape)
		(m as Node).add_child(rock)
		rock.global_position = e.global_position - Vector3(0.0, float(c["seat_y"]) + 0.0, 0.0) + Vector3(0.0, float(c["rock_up"]), 0.0)
		var notes := FxKit.particles(Color(0.55, 1.0, 0.9), 8, 2.2, 0.12, 1.2, 30.0, -0.3, false)
		e.add_child(notes)
		notes.position.y = 1.7
		b["extra"] = rock
	var rock_node: Node3D = b["extra"]
	if is_instance_valid(rock_node):
		var c2: Dictionary = m.call("cfg_of", "reef_siren")
		rock_node.global_position = e.global_position - Vector3(0.0, float(c2["seat_y"]) - float(c2["rock_up"]), 0.0)
	var model2: Node3D = e.get("_model")
	if model2 == null:
		return
	var t := Time.get_ticks_msec() / 1000.0 + float(b["id"])
	for arm: String in ["ArmL", "ArmR"]:
		var a := model2.find_child(arm, true, false) as Node3D
		if a != null:  # arms raised and swaying as she sings
			a.rotation = Vector3(-1.2 + sin(t * 1.4) * 0.25, 0.0, (0.5 if arm == "ArmL" else -0.5) + sin(t * 0.9) * 0.15)
