# Purpose: the special attacks of the fantasy bosses. Each boss's list is data (data/fantasy/enemies.json "moves"):
# every move has a kind, how often it comes, a warning time and its numbers. A move first paints its warning on the
# ground in its own colour (a circle or a lane that fills up), then strikes. The host decides who is hit; the other
# machines are told which move started where and draw the same thing (replay) without deciding anything.
# Kinds: slam (circle around the boss), charge (a lane, then the boss rushes down it), summon (helpers appear),
# zones (circles under the players that stay and burn), volley (a fan of shots), pull (drags everyone in, or blows
# them away), rain (many small circles falling one after another), beam (a lane that stays lit), blink (the boss
# vanishes and comes down where the player stood).
# Dependencies: game/fantasy_world.gd (terrain heights, walk_world, sound), game/enemy.gd (position, shoot, stats).
# Marks are pooled; nothing is allocated while a move runs.
extends Node3D

signal started(boss: Node3D, index: int, at: Vector3, roll: int)  # host: tell the HUD and the other machines
signal summoned(enemy_id: String, x: float, z: float)  # host: a helper should appear at this spot of the map

const MARKS := 24
const TICK := 0.4  # seconds between hits of something that stays (zones, beam)
const MARK_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float fill = 0.0;
uniform float strip = 0.0;
uniform float hot = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = mix(length(p), max(abs(p.x), abs(p.y)), strip);
	float edge = smoothstep(1.0, 0.94, d) * smoothstep(0.82, 0.94, d);
	float along = mix(d, UV.y, strip);
	float body = step(d, 1.0) * step(along, fill) * 0.3;
	float warn = max(edge * 0.95, body);
	float strike = step(d, 1.0) * (0.85 - 0.45 * d);
	ALBEDO = tint.rgb * (1.0 + hot * 1.5);
	ALPHA = mix(warn, strike, hot) * tint.a;
}"""

var bodies: Callable  # everyone a boss can hit (the spawner's list); used on the host only
var reach_m := 80.0  # a boss uses a special attack only on somebody this close (it reached across the whole map before)

var _world: Node3D
var _player: Node3D
var _marks: Array[MeshInstance3D] = []
var _mats: Array[ShaderMaterial] = []
var _mark_until: PackedFloat32Array = []  # engine time each mark is free again
var _watched: Array = []  # host: {"boss", "moves", "wait": PackedFloat32Array}
var _running: Array = []  # {"boss", "move", "t", "at", "from", "dir", "rng", "show", "stage", "marks", "spots", "next", "hit"}
var _beam: MeshInstance3D
var _beam_mat := StandardMaterial3D.new()


func setup(world: Node3D, player: Node3D) -> void:
	_world = world
	_player = player
	top_level = true  # marks are placed in world space
	var shader := Shader.new()
	shader.code = MARK_CODE
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	_mark_until.resize(MARKS)
	for i in MARKS:
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var mark := MeshInstance3D.new()
		mark.mesh = plane
		mark.material_override = mat
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.visible = false
		add_child(mark)
		_marks.append(mark)
		_mats.append(mat)
	_beam = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_beam.mesh = box
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam.material_override = _beam_mat
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)


# Host: this boss is awake, its moves start counting.
func watch(boss: Node3D, moves: Array) -> void:
	if moves.is_empty():
		return
	var wait := PackedFloat32Array()
	for i in moves.size():
		wait.append(float(moves[i]["every"]) * (0.45 + 0.25 * i))  # the first of each comes early, staggered
	_watched.append({"boss": boss, "moves": moves, "wait": wait})


# Another machine: draw this move (the host started it).
func replay(boss: Node3D, index: int, at: Vector3, roll: int) -> void:
	var moves: Array = boss.get("_stats").get("moves", [])
	if index >= 0 and index < moves.size():
		_begin(boss, moves[index], at, roll, true)


func clear() -> void:
	_watched.clear()
	_running.clear()
	_beam.visible = false
	for mark in _marks:
		mark.visible = false


func _alive(boss: Variant) -> bool:
	return is_instance_valid(boss) and not (boss as Node3D).health.is_dead()


func _busy(boss: Node3D) -> bool:
	for run: Dictionary in _running:
		if run["boss"] == boss:
			return true
	return false


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for i in MARKS:
		if _marks[i].visible and now >= _mark_until[i]:
			_marks[i].visible = false
	for i in range(_watched.size() - 1, -1, -1):
		var entry: Dictionary = _watched[i]
		if not _alive(entry["boss"]) or bool(entry["boss"].get("puppet")):
			_watched.remove_at(i)
			continue
		var wait: PackedFloat32Array = entry["wait"]
		var ready := -1
		for m in wait.size():
			wait[m] -= delta
			if wait[m] <= 0.0 and ready < 0:
				ready = m
		if ready >= 0 and not _busy(entry["boss"]) and bodies.is_valid():
			var boss: Node3D = entry["boss"]
			var all: Array = bodies.call()
			var target: Node3D = all[0]
			for body: Node3D in all:
				if body.global_position.distance_to(boss.global_position) < target.global_position.distance_to(boss.global_position):
					target = body
			if target.global_position.distance_to(boss.global_position) > reach_m:
				wait[ready] = 2.0  # nobody near: look again shortly
			else:
				wait[ready] = float(entry["moves"][ready]["every"])
				var roll := randi() & 0xFFFF
				_begin(boss, entry["moves"][ready], target.global_position, roll, false)
				started.emit(boss, ready, target.global_position, roll)
		entry["wait"] = wait
	for i in range(_running.size() - 1, -1, -1):
		var run: Dictionary = _running[i]
		if not _alive(run["boss"]):
			_end(run)
			_running.remove_at(i)
			continue
		run["t"] = float(run["t"]) + delta
		if _step(run, delta):
			_end(run)
			_running.remove_at(i)


# --- marks ---

func _ground(at: Vector3) -> Vector3:
	return Vector3(at.x, float(_world.call("ground_height", at.x, at.z)) + 0.15, at.z)


func _mark(at: Vector3, radius: float, color: Color, seconds: float) -> int:
	var now := Time.get_ticks_msec() / 1000.0
	for i in MARKS:
		if not _marks[i].visible:
			_marks[i].visible = true
			_marks[i].global_transform = Transform3D(Basis.IDENTITY.scaled(Vector3(radius, 1.0, radius)), _ground(at))
			_mats[i].set_shader_parameter("tint", color)
			_mats[i].set_shader_parameter("strip", 0.0)
			_mats[i].set_shader_parameter("fill", 0.0)
			_mats[i].set_shader_parameter("hot", 0.0)
			_mark_until[i] = now + seconds
			return i
	return -1


func _lane(from: Vector3, dir: Vector3, length: float, width: float, color: Color, seconds: float) -> int:
	var i := _mark(from + dir * length * 0.5, 1.0, color, seconds)
	if i >= 0:
		var basis := Basis(Vector3.UP, atan2(dir.x, dir.z)).scaled_local(Vector3(width * 0.5, 1.0, length * 0.5))
		_marks[i].global_transform = Transform3D(basis, _ground(from + dir * length * 0.5))
		_mats[i].set_shader_parameter("strip", 1.0)
	return i


func _fill(i: int, share: float) -> void:
	if i >= 0:
		_mats[i].set_shader_parameter("fill", clampf(share, 0.0, 1.0))


func _strike(i: int, seconds: float) -> void:
	if i >= 0:
		_mats[i].set_shader_parameter("hot", 1.0)
		_mark_until[i] = Time.get_ticks_msec() / 1000.0 + seconds


func _color(move: Dictionary) -> Color:
	var c: Array = move.get("color", [1.0, 0.4, 0.2])
	return Color(c[0], c[1], c[2], 1.0)


# --- hitting (host only) ---

func _damage(run: Dictionary) -> float:
	return float(run["boss"].get("_stats")["damage"]) * float(run["move"].get("damage", 1.0))


func _hit_circle(run: Dictionary, at: Vector3, radius: float, share: float = 1.0) -> void:
	if bool(run["show"]) or not bodies.is_valid():
		return
	for body: Node3D in bodies.call():
		if Vector2(body.global_position.x - at.x, body.global_position.z - at.z).length() < radius:
			body.set("struck_by", run["boss"])
			body.call("take_damage", _damage(run) * share, String(run["move"].get("element", "physical")))


func _hit_lane(run: Dictionary, from: Vector3, dir: Vector3, length: float, width: float, share: float = 1.0) -> void:
	if bool(run["show"]) or not bodies.is_valid():
		return
	for body: Node3D in bodies.call():
		var rel := body.global_position - from
		var along := rel.x * dir.x + rel.z * dir.z
		var side := absf(rel.x * dir.z - rel.z * dir.x)
		if along > -1.0 and along < length and side < width * 0.5:
			body.set("struck_by", run["boss"])
			body.call("take_damage", _damage(run) * share, String(run["move"].get("element", "physical")))


# --- running a move ---

func _begin(boss: Node3D, move: Dictionary, at: Vector3, roll: int, show_only: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = roll
	var from := boss.global_position
	var flat := Vector3(at.x - from.x, 0.0, at.z - from.z)
	var dir := flat.normalized() if flat.length() > 0.1 else Vector3.FORWARD
	var run := {"boss": boss, "move": move, "t": 0.0, "at": at, "from": from, "dir": dir, "rng": rng, "show": show_only, "stage": 0, "marks": PackedInt32Array(), "spots": PackedVector3Array(), "next": 0.0, "hit": {}}
	var color := _color(move)
	var windup := float(move["windup"])
	var marks := PackedInt32Array()
	var spots := PackedVector3Array()
	match String(move["kind"]):
		"slam":
			marks.append(_mark(from, float(move["radius"]), color, windup + 0.35))
		"charge":
			marks.append(_lane(from, dir, float(move["distance"]), float(move["width"]), color, windup + float(move["distance"]) / float(move["speed"]) + 0.2))
		"beam":
			run["dir"] = dir.rotated(Vector3.UP, -deg_to_rad(float(move.get("arc", 0.0))) * 0.5)  # it starts at one end of its sweep
			marks.append(_lane(from, run["dir"], float(move["range"]), float(move.get("width", 3.0)), color, windup + float(move["seconds"])))
		"summon":
			for i in int(move["count"]):
				var a := TAU * float(i) / float(move["count"]) + rng.randf()
				spots.append(from + Vector3(cos(a), 0.0, sin(a)) * (float(boss.get("_size").x) * 0.5 + 3.0))
				marks.append(_mark(spots[i], 1.2, color, windup + 0.3))
		"zones":
			var all: Array = bodies.call() if bodies.is_valid() else [_player]
			for i in int(move["count"]):
				var spot: Vector3 = (all[i] as Node3D).global_position if i < all.size() else at + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * float(move.get("spread", 12.0))
				if show_only and i == 0:
					spot = at
				spots.append(spot)
				marks.append(_mark(spot, float(move["radius"]), color, windup + float(move["linger"])))
		"rain":
			for i in int(move["count"]):
				var a := rng.randf() * TAU
				spots.append(at + Vector3(cos(a), 0.0, sin(a)) * sqrt(rng.randf()) * float(move.get("spread", 14.0)))
		"pull":
			marks.append(_mark(from, float(move["radius"]), color, windup + float(move.get("seconds", 2.5))))
		"blink":
			marks.append(_mark(at, float(move["radius"]), color, windup + 0.35))
		"volley":
			marks.append(_mark(from, float(boss.get("_size").x) * 0.5 + 1.0, color, windup))
	run["marks"] = marks
	run["spots"] = spots
	_running.append(run)
	_world.call("sound", "boss_warn", from)


# Advances one running move. Returns true when it is over.
func _step(run: Dictionary, delta: float) -> bool:
	var move: Dictionary = run["move"]
	var boss: Node3D = run["boss"]
	var t := float(run["t"])
	var windup := float(move["windup"])
	var marks: PackedInt32Array = run["marks"]
	var spots: PackedVector3Array = run["spots"]
	var from: Vector3 = run["from"]
	var dir: Vector3 = run["dir"]
	var kind := String(move["kind"])
	if int(run["stage"]) == 0 and kind != "rain":
		for i in marks:
			_fill(i, t / windup)
		if t < windup:
			return false
		run["stage"] = 1
		run["next"] = t
		_world.call("sound", "boss_hit", boss.global_position)
		match kind:
			"slam":
				_strike(marks[0], 0.3)
				_hit_circle(run, from, float(move["radius"]))
				return true
			"summon":
				if not bool(run["show"]):
					for spot in spots:
						var local: Vector3 = _world.call("local_of", spot)
						summoned.emit(String(move["enemy"]), local.x, local.z)
				return true
			"volley":
				var count := int(move["count"])
				var arc := deg_to_rad(float(move["arc"]))
				var origin := boss.global_position + Vector3(0.0, float(boss.get("_size").y) * 0.6, 0.0)
				for i in count:
					var turn := arc * (float(i) / float(maxi(count - 1, 1)) - 0.5) if arc < TAU - 0.1 else TAU * float(i) / float(count)
					boss.call("shoot", origin, dir.rotated(Vector3.UP, turn), float(move["speed"]), _damage(run))
				return true
			"blink":
				if not bool(run["show"]):
					var landing: Vector3 = run["at"]
					boss.global_position = _world.call("walk_world", Vector3(landing.x, 0.0, landing.z), Vector3.ZERO, float(boss.get("_size").x) * 0.5, 0, 0.0)
				_strike(marks[0], 0.3)
				_hit_circle(run, run["at"], float(move["radius"]))
				return true
			"zones":
				for i in marks:
					_strike(i, float(move["linger"]))
			"beam":
				_strike(marks[0], float(move["seconds"]))
	match kind:
		"charge":
			var travelled := (t - windup) * float(move["speed"])
			if not bool(run["show"]):
				boss.global_position = _world.call("walk_world", boss.global_position, dir * float(move["speed"]) * delta, float(boss.get("_size").x) * 0.5, 2 if float(boss.global_position.y) > float(_world.call("ground_height", boss.global_position.x, boss.global_position.z)) + 0.5 else 0, float(boss.get("_stats").get("hover", 1.4)) if String(boss.get("_stats").get("walks", "land")) == "fly" else 0.0)
				for body: Node3D in bodies.call():
					if not (run["hit"] as Dictionary).has(body) and Vector2(body.global_position.x - boss.global_position.x, body.global_position.z - boss.global_position.z).length() < float(move["width"]) * 0.5 + 0.6:
						(run["hit"] as Dictionary)[body] = true
						body.set("struck_by", run["boss"])
						body.call("take_damage", _damage(run), String(move.get("element", "physical")))
			return travelled >= float(move["distance"])
		"zones":
			if t >= float(run["next"]):
				run["next"] = float(run["next"]) + TICK
				for spot in spots:
					_hit_circle(run, spot, float(move["radius"]), TICK)
			return t >= windup + float(move["linger"])
		"beam":
			# the breath sweeps from one side to the other; the lane on the ground and the beam above it turn together
			var length := float(move["range"])
			var width := float(move.get("width", 3.0))
			var now_dir := dir.rotated(Vector3.UP, deg_to_rad(float(move.get("arc", 0.0))) * clampf((t - windup) / float(move["seconds"]), 0.0, 1.0))
			var turned := Basis(Vector3.UP, atan2(now_dir.x, now_dir.z))
			if marks[0] >= 0:
				_marks[marks[0]].global_transform = Transform3D(turned.scaled_local(Vector3(width * 0.5, 1.0, length * 0.5)), _ground(from + now_dir * length * 0.5))
			_beam.visible = true
			var c := _color(move)
			_beam_mat.albedo_color = Color(c.r, c.g, c.b, 0.55 + 0.25 * sin(t * 40.0))
			_beam.global_transform = Transform3D(turned.scaled_local(Vector3(width * 0.5, width * 0.5, length)), from + now_dir * length * 0.5 + Vector3(0.0, float(boss.get("_size").y) * 0.45, 0.0))
			if t >= float(run["next"]):
				run["next"] = float(run["next"]) + TICK
				_hit_lane(run, from, now_dir, length, width, TICK)
			return t >= windup + float(move["seconds"])
		"pull":
			var strength := float(move["pull"])
			var away := Vector3(_player.global_position.x - boss.global_position.x, 0.0, _player.global_position.z - boss.global_position.z)
			if away.length() < float(move["radius"]) and away.length() > 1.5:
				_player.call("shove", -away.normalized() * strength)  # every machine moves its own player
			if t >= windup + float(move.get("seconds", 2.5)):
				if float(move.get("slam", 0.0)) > 0.0:  # whoever was dragged all the way in is struck
					var m := _mark(boss.global_position, float(move["slam"]), _color(move), 0.3)
					_strike(m, 0.3)
					_hit_circle(run, boss.global_position, float(move["slam"]))
				return true
			return false
		"rain":
			# one circle after another: each warns for `windup`, then lands
			var gap := float(move.get("seconds", 0.3 * spots.size())) / float(maxi(spots.size(), 1))
			var linger := float(move.get("linger", 0.0))  # what landed keeps burning this long
			var radius := float(move["radius"])
			while int(run["stage"]) < spots.size() and t >= float(run["stage"]) * gap:
				marks.append(_mark(spots[int(run["stage"])], radius, _color(move), windup + 0.3))
				run["stage"] = int(run["stage"]) + 1
			run["marks"] = marks
			var done := 0
			for i in marks.size():
				var age := t - float(i) * gap
				if age < windup:
					_fill(marks[i], age / windup)
				elif not (run["hit"] as Dictionary).has(i):
					(run["hit"] as Dictionary)[i] = true
					_strike(marks[i], maxf(0.25, linger))
					_hit_circle(run, spots[i], radius)
					_world.call("sound", "boss_hit", spots[i])
				elif age < windup + linger and t >= float(run["next"]):
					_hit_circle(run, spots[i], radius, TICK * 0.5)
				if age >= windup + linger:
					done += 1
			if t >= float(run["next"]):
				run["next"] = t + TICK
			return done >= spots.size()
	return true


func _end(run: Dictionary) -> void:
	if String(run["move"]["kind"]) == "beam":
		_beam.visible = false
	var now := Time.get_ticks_msec() / 1000.0
	for i in (run["marks"] as PackedInt32Array):
		if i >= 0:
			_mark_until[i] = minf(_mark_until[i], now + 0.3)
