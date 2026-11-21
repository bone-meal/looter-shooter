# Purpose: carries out the carried skinned knife's POWER (polish1 D5b part 2): core/knife_fx.gd decides, this node does
# it in the world: burns, blasts, freezes and weakens enemies (enemy methods, which a joiner's puppets pass to the host),
# casts gun skills for the powers built on them (chain lightning, decoy, drones), Shockwave-style slams, molten pools,
# the ghost-shark bite down a line, Christmas Bells' snowman (a snowman over the frozen enemy with a big red nose: it
# takes x2.5 damage), Club Lights' marks over enemies, confetti, heals and refills. What needs the session (loot, chips,
# luck, revives, party ammo, power-ups) goes out through `wants`. Child of game/player.gd ("KnifePowers").
# Dependencies: core/knife_fx.gd, game/skill_effects.gd (player.skill_fx), game/player.gd.
extends Node3D

const KnifeFx = preload("res://core/knife_fx.gd")

signal wants(action: Dictionary)  # for the session: pull_loot, chips, party_ammo, revive_near, slot 777, marks to the party

var fx: KnifeFx
var player: Node3D
var _rng := RandomNumberGenerator.new()
var _delayed: Array = []  # [time, point, radius, damage]
var _pools: Array = []  # [until, a, b]
var _venom := {}  # enemy instance id -> stacks
var _snowmen: Array = []  # [until, node, enemy]
var _marks: Array = []  # [until, node, enemy]
var _pool_tick := 0.0


func setup(rules: RefCounted, owner_player: Node3D) -> void:
	fx = KnifeFx.new(rules)
	player = owner_player
	_rng.randomize()


func carry(item: Dictionary) -> void:
	fx.carry(item)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# What the player reads (see core/knife_fx.gd).
func speed_mult() -> float:
	return fx.speed_mult(_now()) if fx != null else 1.0


func rate_mult() -> float:
	return fx.rate_mult(_now()) if fx != null else 1.0


func incoming(amount: float) -> float:
	return fx.incoming(amount, _now(), _rng.randf()) if fx != null else amount


func would_down() -> bool:
	return fx != null and fx.would_down(_now())


func luck_pct() -> float:
	return fx.luck_pct(_now()) if fx != null else 0.0


# Last Laugh went off: everything near is thrown back, confetti, a laugh on screen.
func last_laugh() -> void:
	var r := float(fx.p.get("radius", 8.0))
	for e in _near(player.global_position, r):
		var away: Vector3 = (e.global_position - player.global_position) * Vector3(1, 0, 1)
		e.push(away.normalized() * float(fx.p.get("push", 12.0)))
		e.apply_freeze(0.8)
	_confetti(player.global_position)
	wants.emit({"do": "notice", "text": "HA HA HA!  LAST LAUGH"})


func _sfx() -> Node:
	return player.get("skill_fx") if player != null else null


# A knife blow landed on `target` at `point` for `dealt` damage.
func on_hit(kind: String, target: Node, point: Vector3, dealt: float) -> void:
	if fx == null or fx.power == "":
		return
	var eid := str(target.get("enemy_id")) if target != null else ""
	var elite := str(target.get("elite")) not in ["", "<null>"] if target != null else false
	for a: Dictionary in fx.on_hit(kind, elite, eid.begins_with("boss"), _now()):
		_do(a, target, point, dealt)


# A paid kill with the knife at `where`.
func on_kill(where: Vector3) -> void:
	if fx == null or fx.power == "":
		return
	for a: Dictionary in fx.on_kill(_now(), _rng):
		_do(a, null, where, _knife_damage())


func _knife_damage() -> float:
	return float(player.call("knife_damage")) if player != null and player.has_method("knife_damage") else 60.0


func _do(a: Dictionary, target: Node, point: Vector3, dealt: float) -> void:
	var sfx := _sfx()
	match String(a["do"]):
		"heal":
			var hp: RefCounted = player.get("health")
			hp.call("heal", float(hp.get("max_hp")) * float(a["share"]))
		"refill_mag":
			var w: RefCounted = player.call("held_weapon")
			if w != null:
				w.set("ammo", mini(int(w.get("ammo")) + ceili(float(w.get("mag_size")) * float(a["share"])), int(w.get("mag_size"))))
		"burn_area":
			for e in _near(point, float(a["radius"])):
				e.apply_burn(dealt * float(a["dps"]), float(a["seconds"]))
			if sfx != null:
				sfx.ring(point, float(a["radius"]), Color(1.0, 0.55, 0.15))
		"delayed_blast":
			_delayed.append([_now() + float(a["delay"]), target.global_position if target is Node3D else point, float(a["radius"]), dealt * float(a["damage"])])
			if target != null and target.has_method("apply_vulnerable"):
				target.apply_vulnerable(1.0, float(a["delay"]))
		"slam":
			for e in _near(player.global_position, float(a["radius"])):
				var away: Vector3 = (e.global_position - player.global_position) * Vector3(1, 0, 1)
				e.on_hit(dealt, e.global_position + Vector3.UP, Vector3.UP)
				e.apply_freeze(float(a["stun"]))
				e.push(away.normalized() * float(a["push"]))
			if sfx != null:
				sfx.ring(player.global_position, float(a["radius"]), Color(1.0, 0.75, 0.3))
		"pool":
			var fwd := -(player.global_basis.z * Vector3(1, 0, 1)).normalized()
			var at: Vector3 = Vector3(point.x, player.global_position.y, point.z)
			_pools.append([_now() + float(a["seconds"]), at - fwd * float(a["length"]) * 0.5, at + fwd * float(a["length"]) * 0.5])
			if sfx != null:
				sfx.zones.burn_line(player.get("gun_db"), {"id": "fire_trail_dash", "q": clampf(fx.scale, 0.0, 1.0)}, dealt * 0.3, at - fwd * float(a["length"]) * 0.5, at + fwd * float(a["length"]) * 0.5)
		"ignite_next":
			var in_pool := false
			for pl: Array in _pools:
				if _now() < float(pl[0]) and _seg_dist(point, pl[1], pl[2]) < 1.5:
					in_pool = true
			if in_pool and sfx != null:
				var next = sfx.nearest(point, float(a["reach"]), [])
				if next != null:
					next.apply_burn(dealt * 0.4, 4.0)
					sfx.bolt(point + Vector3.UP, next.global_position + Vector3.UP, Color(1.0, 0.4, 0.05))
		"vulnerable":
			if target != null and target.has_method("apply_vulnerable"):
				target.apply_vulnerable(float(a["mult"]), float(a["seconds"]))
		"freeze":
			if target != null and target.has_method("apply_freeze"):
				target.apply_freeze(float(a["seconds"]))
		"bite":
			var dir := -(player.global_basis.z * Vector3(1, 0, 1)).normalized()
			var from: Vector3 = player.global_position + Vector3.UP
			var hit_ids := {}
			for k in 6:  # a ghost shark rushes down the line: everything on it is bitten
				var c := from + dir * (1.0 + float(k) * float(a["length"]) / 6.0)
				if sfx != null:
					sfx.ring(c - Vector3.UP, 1.4, Color(0.5, 0.9, 1.0))
				for e in _near(c, 1.8):
					if not hit_ids.has(e.get_instance_id()):
						hit_ids[e.get_instance_id()] = true
						e.on_hit(dealt * float(a["damage"]), e.global_position + Vector3.UP, Vector3.UP)
			if sfx != null:
				sfx.bolt(from, from + dir * float(a["length"]), Color(0.6, 0.95, 1.0))
		"venom":
			if target != null and target.has_method("apply_burn"):
				var id := target.get_instance_id()
				_venom[id] = mini(int(_venom.get(id, 0)) + 1, int(a["stacks"]))
				target.apply_burn(dealt * float(a["dps"]) * float(_venom[id]), float(a["seconds"]))
		"cast":
			if sfx != null:
				var eye: Vector3 = player.call("eye_position") if player.has_method("eye_position") else player.global_position + Vector3.UP * 1.6
				var fwd2 := -player.global_basis.z
				sfx.cast(player.get("gun_db"), {"id": String(a["skill"]), "q": clampf(fx.scale, 0.0, 1.0)}, dealt, player.global_position, eye, fwd2, point)
		"reset_dodge":
			if player.has_method("reset_dodge"):
				player.call("reset_dodge")
		"blind":
			for e in _near(point, float(a["radius"])):
				e.apply_freeze(float(a["seconds"]))
			_confetti(point)
		"snowman":
			if target is Node3D and target.has_method("apply_freeze"):
				target.apply_freeze(float(a["freeze"]))
				target.apply_vulnerable(float(a["mult"]), float(a["nose"]))
				_snowmen.append([_now() + float(a["nose"]), _snowman(target), target])
		"marks", "pull_loot", "chips", "party_ammo", "revive_near", "slot", "notice":
			if String(a["do"]) == "marks":
				show_marks(point, float(a["radius"]), float(a["seconds"]))
			wants.emit(a)


func _near(point: Vector3, radius: float) -> Array:
	var sfx := _sfx()
	return sfx.near(point, radius) if sfx != null else []


func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := (b - a) * Vector3(1, 0, 1)
	var t := clampf(((p - a) * Vector3(1, 0, 1)).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return ((a + ab * t) - p).length()


# Club Lights: a bright marker over every enemy within `radius`, seen through walls (also a teammate's, from the party).
func show_marks(point: Vector3, radius: float, seconds: float) -> void:
	for e in _near(point, radius):
		var m := Label3D.new()
		m.text = "V"
		m.font_size = 96
		m.outline_size = 18
		m.modulate = Color(1.0, 0.25, 0.75)
		m.outline_modulate = Color(0.1, 0.0, 0.1)
		m.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		m.no_depth_test = true
		m.fixed_size = true
		m.pixel_size = 0.0022
		e.add_child(m)
		m.position = Vector3(0, float(e.call("head_height")) + 0.6 if e.has_method("head_height") else 2.4, 0)
		_marks.append([_now() + seconds, m, e])


func _confetti(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 90
	p.lifetime = 1.2
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -5, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.07)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 0.3, 0.7), Color(0.3, 0.9, 1), Color(1, 0.9, 0.2), Color(0.5, 1, 0.4)])
	g.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	p.color_initial_ramp = g
	get_tree().current_scene.add_child(p)
	p.global_position = at + Vector3.UP
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


# A snowman over a frozen enemy: three snowballs, coal eyes, and a big red nose that swells (the weak spot).
func _snowman(target: Node3D) -> Node3D:
	var root := Node3D.new()
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color(0.96, 0.97, 1.0)
	snow.roughness = 0.8
	var h := maxf(float(target.call("head_height")) if target.has_method("head_height") else 1.8, 1.6)  # (small foes are swallowed by a full-size snowman)
	var sizes := [0.5, 0.36, 0.26]
	var y := 0.0
	for i in 3:
		var s := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = sizes[i] * h / 1.8
		sm.height = sm.radius * 2.0
		sm.radial_segments = 16
		sm.rings = 8
		s.mesh = sm
		s.material_override = snow
		y += sm.radius * (1.0 if i == 0 else 1.6)
		s.position = Vector3(0, y, 0)
		root.add_child(s)
	var top: MeshInstance3D = root.get_child(2)
	var nose := MeshInstance3D.new()
	var nm := SphereMesh.new()
	nm.radius = 0.09 * h / 1.8
	nm.height = nm.radius * 2.0
	nose.mesh = nm
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.95, 0.08, 0.1)
	red.emission_enabled = true
	red.emission = Color(1.0, 0.1, 0.1)
	red.emission_energy_multiplier = 0.8
	nose.material_override = red
	nose.name = "Nose"
	nose.position = top.position + Vector3(0, 0, -(top.mesh as SphereMesh).radius * 0.95)
	root.add_child(nose)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.025 * h / 1.8
		em.height = em.radius * 2.0
		eye.mesh = em
		var coal := StandardMaterial3D.new()
		coal.albedo_color = Color(0.05, 0.05, 0.06)
		eye.material_override = coal
		eye.position = top.position + Vector3(side * 0.08 * h / 1.8, 0.07 * h / 1.8, -(top.mesh as SphereMesh).radius * 0.85)
		root.add_child(eye)
	target.add_child(root)
	var tw := root.create_tween()  # the nose swells
	tw.tween_property(nose, "scale", Vector3.ONE * 2.6, 1.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	return root


func _process(delta: float) -> void:
	if fx == null:
		return
	var now := _now()
	var i := 0
	while i < _delayed.size():
		var d: Array = _delayed[i]
		if now >= float(d[0]):
			var sfx := _sfx()
			if sfx != null:
				sfx.burst(d[1], float(d[2]), float(d[3]), Color(1.0, 0.4, 0.05))
			_delayed.remove_at(i)
		else:
			i += 1
	for list: Array in [_snowmen, _marks]:
		var j := 0
		while j < list.size():
			var s: Array = list[j]
			if now >= float(s[0]) or not is_instance_valid(s[2]) or (s[2] as Node).get("health") != null and (s[2] as Node).health.is_dead():
				if is_instance_valid(s[1]):
					(s[1] as Node).queue_free()
				list.remove_at(j)
			else:
				j += 1
	_pool_tick -= delta
	if _pool_tick <= 0.0 and not _pools.is_empty():
		_pool_tick = 0.5
		var k := 0
		while k < _pools.size():
			if now >= float(_pools[k][0]):
				_pools.remove_at(k)
			else:
				k += 1
	var regen := fx.regen_share(now)
	if regen > 0.0 and player != null:
		var hp: RefCounted = player.get("health")
		hp.call("heal", float(hp.get("max_hp")) * regen * delta)
