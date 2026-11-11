# Purpose: what staff spells do in the world once cast: the four forms (jet, bolt, eruption, wave), the long secret
# spells (storm, meteors, tsunami, quake, nova, barrage, lance), their lingering pools and clouds, the damage and
# effects on enemies (through the same interface guns use: on_hit, push, apply_slow / burn / freeze / vulnerable), and
# the pooled shapes that show them. Each spell also throws the small bits of its own substance (game/spell_motes.gd:
# drops, flames, rocks, shards, sparks, leaves ...) and everything grows with the number of elements, so a spell is
# told apart by colour, shape and size. Wet enemies take more from lightning and freeze at once.
# Dependencies: game/spell_motes.gd, an enemy list (`source.enemy_list()`, game/wave_director.gd), the caster's body for healing, optional
# game/damage_numbers.gd. The spell dictionaries come from core/spell_book.gd `resolve`.
extends Node3D

const SpellMotes = preload("res://game/spell_motes.gd")

const MAX_PUFFS := 180
const BALL := 0
const POST := 1
const RING := 2
const SPIKE := 3
const TICK := 0.5  # seconds between hits of anything that lingers
const BOSS_HOLD := 0.25  # bosses are held for this share of a freeze or stagger and cannot be thrown

signal healed(amount: float)  # the caster healed (the world tops up health)
signal landed(local_kind: String, at: Vector3, spell: Dictionary)  # a spell reached the ground (fires get lit there)

var source: Node  # has enemy_list()
var numbers: Node  # game/damage_numbers.gd, optional
var caster: Node3D  # the local player
var motes := SpellMotes.new()

var _meshes: Array[Mesh] = []
var _puffs: Array = []  # {"node", "mat", "left", "life", "from", "to", "pos", "move", "color"}
var _jobs: Array = []  # running spells, see _run
var _wet := {}  # enemy instance id -> engine time it dries
var _hit_once := {}  # scratch: enemy instance id -> true


func _ready() -> void:
	top_level = true  # shapes are placed in world space wherever this node hangs
	global_transform = Transform3D.IDENTITY
	add_child(motes)
	var ball := SphereMesh.new()
	ball.radius = 0.5
	ball.height = 1.0
	ball.radial_segments = 10
	ball.rings = 5
	var post := CylinderMesh.new()
	post.top_radius = 0.5
	post.bottom_radius = 0.5
	post.height = 1.0
	post.radial_segments = 8
	var ring := TorusMesh.new()
	ring.inner_radius = 0.82
	ring.outer_radius = 1.0
	ring.rings = 20
	ring.ring_segments = 5
	var spike := CylinderMesh.new()
	spike.top_radius = 0.0
	spike.bottom_radius = 0.5
	spike.height = 1.0
	spike.radial_segments = 6
	_meshes = [ball, post, ring, spike]


# Casts a resolved spell. `damage` and `heal` are already scaled by the caster's strength.
# `show_only`: another player's spell, drawn here without doing anything (their machine and the host decide the hits).
func cast(spell: Dictionary, origin: Vector3, aim: Vector3, tip: Vector3, damage: float, heal: float, show_only := false) -> void:
	var c: Array = spell["color"]
	var color := Color(c[0], c[1], c[2])
	var job := {"spell": spell, "kind": String(spell["kind"]), "color": color, "damage": damage, "heal": heal, "origin": origin,
		"aim": aim, "tip": tip, "t": 0.0, "next": 0.0, "effects": spell["effects"], "count": int(spell["count"]), "show": show_only}
	_give_look(job)
	if heal > 0.0 and not show_only:
		healed.emit(heal)
		_shape(BALL, caster.global_position + Vector3(0, 1, 0), Vector3.ONE * 0.5, Vector3.ONE * 4.0, Color(color, 0.5), 0.6)
	match job["kind"]:
		"jet":
			job["left"] = float(spell["seconds"])
		"bolt":
			job["pos"] = tip
			job["left"] = float(spell["range"]) / maxf(float(spell["speed"]), 1.0)
		"ground":
			job["at"] = _aim_point(origin, aim, float(spell["range"]))
			_erupt(job)
			return
		"wave":
			_wave(job)
			return
		"storm":
			job["at"] = _aim_point(origin, aim, 45.0)
			job["left"] = float(spell["seconds"])
		"meteors":
			job["at"] = _aim_point(origin, aim, 60.0)
			job["left"] = float(spell["seconds"])
			job["drops"] = int(spell["count"])
		"tsunami":
			job["pos"] = origin - Vector3(0.0, 1.6, 0.0)
			job["dir"] = Vector3(aim.x, 0.0, aim.z).normalized()
			job["left"] = float(spell["range"]) / 18.0
			job["seen"] = {}
		"quake":
			job["at"] = origin - Vector3(0.0, 1.6, 0.0)
			job["left"] = float(spell["seconds"])
			job["rings"] = 3
		"nova":
			_nova(job)
			return
		"barrage":
			job["at"] = _aim_point(origin, aim, 60.0)
			job["left"] = 0.12 * float(spell["count"]) + 0.2
			job["drops"] = int(spell["count"])
		"lance":
			_lance(job)
			return
	_jobs.append(job)


# What this spell's flying bits look like and how large everything is drawn (larger with every element).
func _give_look(job: Dictionary) -> void:
	var look: Dictionary = (job["spell"] as Dictionary).get("look", {})
	job["look"] = look
	job["scale"] = 0.7 + 0.16 * float(job["count"])
	if look.has("also"):  # a secret spell mixes two shapes
		var second := look.duplicate()
		second["shape"] = look["also"]
		job["look2"] = second


# One flying bit of the spell's own look.
func _mote(job: Dictionary, at: Vector3, velocity: Vector3, life: float, size: float) -> void:
	var look: Dictionary = job["look"]
	if job.has("look2") and randf() < 0.4:
		look = job["look2"]
	motes.emit(look, at, velocity, life, size * float(job["scale"]), job["color"])


func clear() -> void:
	motes.clear()
	_jobs.clear()
	for puff: Dictionary in _puffs:
		puff["left"] = 0.0
		(puff["node"] as Node3D).visible = false


func _process(delta: float) -> void:
	for i in range(_jobs.size() - 1, -1, -1):
		var job: Dictionary = _jobs[i]
		job["t"] = float(job["t"]) + delta
		job["left"] = float(job["left"]) - delta
		_run(job, delta)
		if float(job["left"]) <= 0.0:
			_jobs.remove_at(i)
	for puff: Dictionary in _puffs:
		var left := float(puff["left"])
		if left <= 0.0:
			continue
		left -= delta
		puff["left"] = left
		var node: MeshInstance3D = puff["node"]
		if left <= 0.0:
			node.visible = false
			continue
		var k := 1.0 - left / float(puff["life"])
		puff["pos"] = (puff["pos"] as Vector3) + (puff["move"] as Vector3) * delta
		node.position = puff["pos"]
		node.scale = (puff["from"] as Vector3).lerp(puff["to"], k)
		var color: Color = puff["color"]
		(puff["mat"] as StandardMaterial3D).albedo_color = Color(color.r, color.g, color.b, color.a * (1.0 - k * k))


func _run(job: Dictionary, delta: float) -> void:
	if not job.has("look"):  # pools, clouds and meteor impacts are started by other spells
		_give_look(job)
	var color: Color = job["color"]
	var spell: Dictionary = job["spell"]
	match String(job["kind"]):
		"jet":
			# follows the caster's aim while it lasts
			var origin: Vector3 = job["origin"] if bool(job["show"]) else caster.call("view_origin")
			var aim: Vector3 = job["aim"] if bool(job["show"]) else caster.call("view_forward")
			var reach := float(spell["range"])
			var end := _ray_end(origin, aim, reach)
			var from: Vector3 = origin + aim * 0.8 + Vector3(0.0, -0.25, 0.0)
			var width := float(spell["width"]) * (0.6 + 0.2 * float(job["count"]))
			_shape(BALL, from, Vector3.ONE * width * 0.3, Vector3.ONE * width * 0.5, Color(color, 0.3), from.distance_to(end) / 45.0 + 0.03, (end - from).normalized() * 45.0)
			# the stream itself is made of the substance's own bits: so many a second, more and larger with every element
			var along := (end - from).normalized()
			job["emit"] = float(job.get("emit", 0.0)) + delta * (80.0 + 25.0 * float(job["count"]))
			while float(job["emit"]) >= 1.0:
				job["emit"] = float(job["emit"]) - 1.0
				var fly := (along + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.045) * randf_range(24.0, 34.0)
				_mote(job, from + along * randf() * 1.2, fly, from.distance_to(end) / 29.0 + 0.04, 0.42)
			if float(job["t"]) >= float(job["next"]):
				job["next"] = float(job["t"]) + 0.15
				var ticks := maxf(float(spell["seconds"]) / 0.15, 1.0)
				_hit_line(origin, end, width, float(job["damage"]) / ticks, job, aim)
		"bolt":
			var pos: Vector3 = job["pos"]
			var step: Vector3 = (job["aim"] as Vector3) * float(spell["speed"]) * delta
			var burst := float(job["left"]) <= 0.0
			var hit := _ray(pos, pos + step)
			if not hit.is_empty():
				pos = hit["position"]
				burst = true
			else:
				pos += step
				for enemy in _enemies():
					if _center(enemy).distance_to(pos) < 1.2:
						burst = true
			job["pos"] = pos
			var size := 0.35 + 0.1 * float(job["count"])
			_shape(BALL, pos, Vector3.ONE * size, Vector3.ONE * size * 0.3, Color(color, 0.9), 0.18)
			job["emit"] = float(job.get("emit", 0.0)) + delta * (55.0 + 15.0 * float(job["count"]))
			while float(job["emit"]) >= 1.0:  # a tail of the substance's bits behind the head
				job["emit"] = float(job["emit"]) - 1.0
				_mote(job, pos + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * size * 0.6, Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 1.0), randf_range(-1.0, 1.0)) * 1.8 + (job["aim"] as Vector3) * 5.0, 0.5, 0.4)
			if burst:
				job["left"] = 0.0
				_burst(pos, float(spell["radius"]), float(job["damage"]), job, Vector3.ZERO)
				landed.emit("bolt", pos, spell)
		"zone":
			if float(job["t"]) >= float(job["next"]):
				job["next"] = float(job["t"]) + TICK
				var at: Vector3 = job["at"]
				_shape(RING, at + Vector3(0, 0.15, 0), Vector3(1, 0.3, 1) * float(job["radius"]), Vector3(1, 0.3, 1) * float(job["radius"]), Color(color, 0.35), TICK + 0.1)
				for n in 6:
					var za := randf() * TAU
					_mote(job, at + Vector3(cos(za), 0.1, sin(za)) * randf() * float(job["radius"]), Vector3(0.0, randf_range(1.0, 3.0), 0.0), 0.7, 0.36)
				_burst(at, float(job["radius"]), float(job["damage"]), job, Vector3.ZERO, false)
		"storm":
			var at: Vector3 = job["at"]
			var radius := float(spell["radius"])
			for n in 2:  # the turning wall of the storm
				var a := float(job["t"]) * 2.4 + float(n) * PI + randf() * 0.6
				var r := radius * randf_range(0.35, 1.0)
				var p := at + Vector3(cos(a) * r, randf_range(0.5, 14.0), sin(a) * r)
				_shape(BALL, p, Vector3.ONE * 2.5, Vector3.ONE * 5.0, Color(color, 0.32), 0.9, Vector3(-sin(a), 0.4, cos(a)) * r * 1.6)
				_mote(job, p, Vector3(-sin(a), 0.2, cos(a)) * r * 1.6, 0.9, 0.45)
				_mote(job, p + Vector3(0.0, 4.0, 0.0), Vector3(-sin(a) * 4.0, -14.0, cos(a) * 4.0), 0.9, 0.3)
			if float(job["t"]) >= float(job["next"]):
				job["next"] = float(job["t"]) + TICK
				_shape(RING, at + Vector3(0, 0.2, 0), Vector3(1, 0.2, 1) * radius, Vector3(1, 0.2, 1) * radius, Color(color, 0.4), TICK + 0.1)
				_burst(at, radius, float(job["damage"]), job, Vector3.ZERO, false)
				var strikes := int((job["effects"] as Dictionary).get("chain", 0))
				var crowd := _within(at, radius)
				for n in mini(strikes, crowd.size()):
					var struck: Node3D = crowd[randi() % crowd.size()]
					_bolt_from_sky(_center(struck), Color(1.0, 1.0, 0.75))
					_hurt(struck, float(job["damage"]), job, Vector3.ZERO)
				if float(job["heal"]) > 0.0 and not bool(job["show"]) and caster.global_position.distance_to(at) < radius:
					healed.emit(float(job["heal"]))
		"meteors":
			var total := maxi(int(spell["count"]), 1)
			var due := int(float(job["t"]) / float(spell["seconds"]) * float(total)) + 1
			while int(job["drops"]) > total - mini(due, total):
				job["drops"] = int(job["drops"]) - 1
				var a := randf() * TAU
				var r := sqrt(randf()) * float(spell["radius"])
				var target: Vector3 = (job["at"] as Vector3) + Vector3(cos(a) * r, 0.0, sin(a) * r)
				_shape(BALL, target + Vector3(6, 40, 0), Vector3.ONE * 2.2, Vector3.ONE * 2.2, Color(color, 0.95), 0.5, Vector3(-12, -80, 0))
				for n in 5:
					_mote(job, target + Vector3(6, 40, 0) + Vector3(randf(), randf(), randf()), Vector3(-12, -80, 0) * randf_range(0.8, 1.0), 0.5, 0.6)
				_jobs.append({"kind": "impact", "spell": spell, "color": color, "damage": job["damage"], "effects": job["effects"], "count": job["count"], "heal": 0.0, "at": target, "t": 0.0, "next": 0.0, "left": 0.5, "show": job["show"]})
		"impact":
			if float(job["left"]) <= 0.0:
				_burst(job["at"], 5.0, float(job["damage"]), job, Vector3.ZERO)
		"tsunami":
			var dir: Vector3 = job["dir"]
			var pos: Vector3 = (job["pos"] as Vector3) + dir * 18.0 * delta
			job["pos"] = pos
			var half := float(spell["radius"])
			var side := Vector3(-dir.z, 0.0, dir.x)
			for n in 3:
				var off := randf_range(-half, half)
				_shape(BALL, pos + side * off + Vector3(0, randf_range(0.5, 4.0), 0), Vector3(2.5, 3.5, 2.5), Vector3(3.5, 1.0, 3.5), Color(color, 0.55), 0.5, dir * 14.0)
				_mote(job, pos + side * off + Vector3(0, 4.0, 0), dir * 16.0 + Vector3(0.0, randf_range(2.0, 7.0), 0.0), 0.8, 0.4)
			for enemy in _enemies():
				var rel := _center(enemy) - pos
				if absf(rel.dot(dir)) < 2.5 and absf(rel.dot(side)) < half and not (job["seen"] as Dictionary).has(enemy.get_instance_id()):
					job["seen"][enemy.get_instance_id()] = true
					_hurt(enemy, float(job["damage"]), job, dir)
		"quake":
			var every := float(spell["seconds"]) / 3.0
			if int(job["rings"]) > 0 and float(job["t"]) >= float(job["next"]):
				job["next"] = float(job["t"]) + every
				job["rings"] = int(job["rings"]) - 1
				var at: Vector3 = job["at"]
				var radius := float(spell["radius"])
				_shape(RING, at + Vector3(0, 0.2, 0), Vector3(1, 0.5, 1), Vector3(radius, 0.5, radius), Color(color, 0.8), every)
				for n in 14:
					var a := randf() * TAU
					var r := randf() * radius
					_shape(SPIKE, at + Vector3(cos(a) * r, 0.0, sin(a) * r), Vector3(0.8, 0.1, 0.8), Vector3(1.2, randf_range(1.5, 4.0), 1.2), Color(color, 0.95), every * 0.9, Vector3(0, 1.2, 0))
				motes.burst(job["look"], at, 26, radius * 1.2, 1.0, 0.45 * float(job["scale"]), color, 1.4)
				_burst(at, radius, float(job["damage"]) / 3.0, job, Vector3.ZERO, false)
		"barrage":
			var total := maxi(int(spell["count"]), 1)
			var due := mini(int(float(job["t"]) / 0.12) + 1, total)
			while int(job["drops"]) > total - due:
				job["drops"] = int(job["drops"]) - 1
				var crowd := _within(job["at"], float(spell["radius"]))
				if crowd.is_empty():
					var a := randf() * TAU
					_bolt_from_sky((job["at"] as Vector3) + Vector3(cos(a), 0.0, sin(a)) * randf() * 8.0, color)
				else:
					var struck: Node3D = crowd[randi() % crowd.size()]
					_bolt_from_sky(_center(struck), color)
					_hurt(struck, float(job["damage"]), job, Vector3.ZERO)


# --- the instant forms ---

func _erupt(job: Dictionary) -> void:
	var spell: Dictionary = job["spell"]
	var at: Vector3 = job["at"]
	var radius := float(spell["radius"])
	var color: Color = job["color"]
	var solid := String((job["look"] as Dictionary).get("shape", "")) in ["rock", "shard"]  # stone and ice stand up as spikes; the rest only as their own bits
	for n in (5 + int(job["count"]) if solid else 0):
		var a := randf() * TAU
		var r := randf() * radius * 0.8
		_shape(SPIKE, at + Vector3(cos(a) * r, 0.0, sin(a) * r), Vector3(0.5, 0.1, 0.5), Vector3(0.9, randf_range(1.2, 2.6) * (1.0 + 0.1 * float(job["count"])), 0.9), Color(color, 0.95), 0.9, Vector3(0, 1.0, 0))
	_shape(RING, at + Vector3(0, 0.15, 0), Vector3(0.5, 0.4, 0.5), Vector3(radius, 0.4, radius), Color(color, 0.7), 0.4)
	motes.burst(job["look"], at, 18 + 6 * int(job["count"]), 7.0 + radius, 1.0, 0.5 * float(job["scale"]), color, 1.3)
	_burst(at, radius, float(job["damage"]), job, Vector3.ZERO, false)
	landed.emit("ground", at, spell)
	var linger := float(spell["seconds"])
	if linger > 0.0:
		_zone(at, radius, linger, float(job["damage"]) * 0.2, job)


func _wave(job: Dictionary) -> void:
	var spell: Dictionary = job["spell"]
	var aim: Vector3 = job["aim"]
	var flat := Vector3(aim.x, 0.0, aim.z).normalized()
	var from: Vector3 = (job["origin"] as Vector3) - Vector3(0, 0.6, 0)
	var radius := float(spell["radius"])
	var half := deg_to_rad(float(spell["angle"])) * 0.5
	var color: Color = job["color"]
	for n in 9:
		var a := lerpf(-half, half, float(n) / 8.0)
		var dir := flat.rotated(Vector3.UP, a)
		_shape(BALL, from + dir, Vector3(0.6, 0.6, 0.6), Vector3(2.2, 1.6, 2.2), Color(color, 0.6), 0.35, dir * radius / 0.35)
		for k in 4 + int(job["count"]):
			_mote(job, from + dir * randf_range(0.6, 1.6) + Vector3(0.0, randf_range(-0.3, 1.1), 0.0), dir * radius / randf_range(0.32, 0.6), 0.45, 0.5)
	for enemy in _enemies():
		var rel := _center(enemy) - from
		rel.y = 0.0
		if rel.length() < radius and (rel.length() < 1.5 or absf(flat.signed_angle_to(rel.normalized(), Vector3.UP)) < half):
			_hurt(enemy, float(job["damage"]), job, rel.normalized())


func _nova(job: Dictionary) -> void:
	var spell: Dictionary = job["spell"]
	var at: Vector3 = (job["origin"] as Vector3) - Vector3(0, 0.6, 0)
	var radius := float(spell["radius"])
	var color: Color = job["color"]
	_shape(BALL, at, Vector3.ONE, Vector3.ONE * radius * 2.0, Color(color, 0.55), 0.7)
	_shape(RING, at - Vector3(0, 0.8, 0), Vector3(1, 0.5, 1), Vector3(radius, 0.5, radius), Color(color, 0.9), 0.7)
	for n in 40:
		var na := TAU * float(n) / 40.0
		_mote(job, at + Vector3(cos(na), 0.0, sin(na)), Vector3(cos(na), randf_range(0.0, 0.5), sin(na)) * radius / 0.6, 0.6, 0.5)
	_burst(at, radius, float(job["damage"]), job, Vector3.ZERO, false)


func _lance(job: Dictionary) -> void:
	var spell: Dictionary = job["spell"]
	var origin: Vector3 = job["origin"]
	var aim: Vector3 = job["aim"]
	var reach := float(spell["range"])
	var width := float(spell["radius"])
	var mid := origin + aim * reach * 0.5
	var across := Basis(Quaternion(Vector3.UP, aim))
	_shape(POST, mid, Vector3(width, reach, width), Vector3(width * 0.1, reach, width * 0.1), Color(job["color"], 0.9), 0.8, Vector3.ZERO, across)
	_shape(POST, mid, Vector3(width * 0.4, reach, width * 0.4), Vector3(0.05, reach, 0.05), Color(1, 1, 1, 0.95), 0.6, Vector3.ZERO, across)
	for n in 40:
		_mote(job, origin + aim * reach * randf(), aim * 6.0 + Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 2.0, 0.9, 0.4)
	_hit_line(origin, origin + aim * reach, width, float(job["damage"]), job, aim)


# --- hitting things ---

func _enemies() -> Array:
	return source.call("enemy_list") if source != null else []


func _center(enemy: Node3D) -> Vector3:
	return enemy.global_position + Vector3(0.0, float(enemy.call("head_height")) * 0.55, 0.0)


func _within(at: Vector3, radius: float) -> Array:
	var out: Array = []
	for enemy in _enemies():
		if is_instance_valid(enemy) and Vector2(enemy.global_position.x - at.x, enemy.global_position.z - at.z).length() < radius:
			out.append(enemy)
	return out


# Everything within `radius` of a point takes the hit (pushed away from the middle when the spell pushes).
func _burst(at: Vector3, radius: float, damage: float, job: Dictionary, _dir: Vector3, show := true) -> void:
	if show:
		_shape(BALL, at, Vector3.ONE * 0.6, Vector3.ONE * radius * 2.0, Color(job["color"], 0.6), 0.35)
		if job.has("look"):
			motes.burst(job["look"], at, 14 + 5 * int(job["count"]), 5.0 + radius * 2.0, 0.7, 0.42 * float(job["scale"]), job["color"])
	for enemy in _within(at, radius + 0.6):
		var away: Vector3 = enemy.global_position - at
		away.y = 0.0
		_hurt(enemy, damage, job, away.normalized())


# Everything within `width` of a line takes the hit.
func _hit_line(from: Vector3, to: Vector3, width: float, damage: float, job: Dictionary, dir: Vector3) -> void:
	var along := to - from
	var length := along.length()
	if length < 0.01:
		return
	along /= length
	for enemy in _enemies():
		var rel := _center(enemy) - from
		var d := clampf(rel.dot(along), 0.0, length)
		if (rel - along * d).length() < width + 0.7:
			_hurt(enemy, damage, job, dir)


func _hurt(enemy: Node3D, damage: float, job: Dictionary, dir: Vector3) -> void:
	if bool(job.get("show", false)) or not is_instance_valid(enemy):
		return
	var effects: Dictionary = job["effects"]
	var now := Time.get_ticks_msec() / 1000.0
	var id := enemy.get_instance_id()
	var wet := float(_wet.get(id, 0.0)) > now
	var boss := enemy.has_meta("fantasy_boss")
	var hold := BOSS_HOLD if boss else 1.0
	if wet and (effects.has("chain") or effects.has("shock")):
		damage *= 1.5  # water carries lightning
	if damage > 0.0:
		var at := _center(enemy)
		enemy.call("on_hit", damage, at, Vector3.UP)
		if numbers != null:
			numbers.call("spawn", at, damage)
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		_wet.erase(id)
		return
	if effects.has("wet"):
		_wet[id] = now + float(effects["wet"])
		enemy.call("apply_slow", 0.15, float(effects["wet"]))
	if effects.has("burn"):
		enemy.call("apply_burn", maxf(damage, 1.0) * 0.25, float(effects["burn"]))
	if effects.has("slow"):
		enemy.call("apply_slow", float(effects["slow"]), 4.0)
	if effects.has("weaken"):
		enemy.call("apply_vulnerable", float(effects["weaken"]), 6.0)
	for key: String in ["stagger", "shock", "freeze"]:
		if effects.has(key):
			enemy.call("apply_freeze", float(effects[key]) * hold)
	if effects.has("freeze_at") and (wet or int(job["count"]) >= int(effects["freeze_at"])):
		enemy.call("apply_freeze", 2.5 * hold)
	if not boss:
		if effects.has("push") and dir != Vector3.ZERO:
			enemy.call("push", dir * float(effects["push"]))
		if effects.has("launch") and dir != Vector3.ZERO:
			enemy.call("push", dir * float(effects["launch"]))
			enemy.call("apply_freeze", 0.6)
		if effects.has("pull") and job.has("at"):
			var inward: Vector3 = (job["at"] as Vector3) - enemy.global_position
			inward.y = 0.0
			enemy.call("push", inward.normalized() * float(effects["pull"]))
	if effects.has("leech"):
		healed.emit(damage * float(effects["leech"]))
	if job.get("kind") in ["jet", "bolt", "wave"]:  # the lingering forms make their own pools
		if effects.has("pool"):
			_zone(enemy.global_position, 2.5, float(effects["pool"]), damage * 0.25, job)
		if effects.has("cloud"):
			_zone(enemy.global_position, 3.0, float(effects["cloud"]), damage * 0.25, job)
		if effects.has("chain") and not job.has("chained"):
			var jumps := int(effects["chain"])
			var chained := job.duplicate()
			chained["chained"] = true
			for other in _within(enemy.global_position, 9.0):
				if other != enemy and jumps > 0:
					jumps -= 1
					_link(_center(enemy), _center(other), Color(1.0, 1.0, 0.7))
					_hurt(other, damage * 0.6, chained, Vector3.ZERO)
	if effects.has("regen") and float(job["heal"]) > 0.0:
		healed.emit(float(job["heal"]) * 0.1)


# A patch that keeps hurting what stands in it.
func _zone(at: Vector3, radius: float, seconds: float, damage: float, job: Dictionary) -> void:
	var effects := (job["effects"] as Dictionary).duplicate()
	for key: String in ["pool", "cloud", "chain", "push", "launch"]:
		effects.erase(key)
	_jobs.append({"kind": "zone", "spell": job["spell"], "color": job["color"], "damage": damage, "heal": 0.0, "effects": effects, "count": job["count"],
		"at": at, "radius": radius, "t": 0.0, "next": 0.0, "left": seconds, "show": job.get("show", false)})


# --- aiming ---

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_ray(query)


func _ray_end(origin: Vector3, aim: Vector3, reach: float) -> Vector3:
	var hit := _ray(origin, origin + aim * reach)
	return hit["position"] if not hit.is_empty() else origin + aim * reach


# Where the caster points on the ground: the first thing the look hits, else the ground below the far end.
func _aim_point(origin: Vector3, aim: Vector3, reach: float) -> Vector3:
	var hit := _ray(origin, origin + aim * reach)
	if not hit.is_empty():
		return hit["position"]
	var far := origin + aim * reach
	var down := _ray(far + Vector3(0, 60, 0), far - Vector3(0, 200, 0))
	return down["position"] if not down.is_empty() else far


# --- shapes ---

func _bolt_from_sky(at: Vector3, color: Color) -> void:
	_shape(POST, at + Vector3(0, 15, 0), Vector3(0.5, 30, 0.5), Vector3(0.05, 30, 0.05), Color(color, 0.95), 0.25)
	_shape(BALL, at, Vector3.ONE * 0.8, Vector3.ONE * 3.0, Color(color, 0.7), 0.25)


func _link(from: Vector3, to: Vector3, color: Color) -> void:
	var along := to - from
	if along.length() < 0.05:
		return
	_shape(POST, (from + to) * 0.5, Vector3(0.18, along.length(), 0.18), Vector3(0.02, along.length(), 0.02), Color(color, 0.95), 0.2, Vector3.ZERO, Basis(Quaternion(Vector3.UP, along.normalized())))


func _shape(kind: int, at: Vector3, from: Vector3, to: Vector3, color: Color, life: float, move := Vector3.ZERO, turn := Basis()) -> void:
	var puff := {}
	for candidate: Dictionary in _puffs:
		if float(candidate["left"]) <= 0.0:
			puff = candidate
			break
	if puff.is_empty():
		if _puffs.size() >= MAX_PUFFS:
			return
		var node := MeshInstance3D.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		node.material_override = mat
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		puff = {"node": node, "mat": mat}
		_puffs.append(puff)
	var shown: MeshInstance3D = puff["node"]
	shown.mesh = _meshes[kind]
	shown.basis = turn
	shown.position = at
	shown.scale = from
	shown.visible = true
	(puff["mat"] as StandardMaterial3D).albedo_color = color
	puff["left"] = life
	puff["life"] = life
	puff["from"] = from
	puff["to"] = to
	puff["pos"] = at
	puff["move"] = move
	puff["color"] = color
