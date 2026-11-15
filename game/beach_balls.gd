# Purpose: the BEACH BALL BOMBARDIER's balls (diary/DESIGN_UNIQUES.md, region 1 chase gun): a small pool of light,
# floaty beach balls stepped on the physics tick. A ball bounces off enemies' heads (every bounce hits), off the
# ground and walls, and pops (a blast) when its bounces or time run out, when someone SHOOTS it (any gun:
# shot_through) or after it was kicked about: walking into a ball KICKS it where you look, and every kick
# (a volley) makes its pop bigger. Numbers come from the gun's data "cfg" (data/gun_uniques.json beach_ball_bombardier).
# Dependencies: game/explosives.gd (blast, its enemy source, damage numbers, score, sounds),
# assets/models/weapons/uniques/beach_ball.gltf (falls back to a plain sphere).
extends Node3D

const POOL_SIZE := 8
const MODEL := "res://assets/models/weapons/uniques/beach_ball.gltf"
const HEAD_REACH := 0.45  # metres round an enemy's head that count as touching it

var explosives: Node3D  # game/explosives.gd: blast(), source (enemy_list), numbers, score, sounds
var kicker: Node3D  # the local player: walking into a ball kicks it (aim_flat(), look pitch from its camera)

var _balls: Array[Node3D] = []
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _bounces := PackedInt32Array()
var _ground := PackedInt32Array()
var _volleys := PackedInt32Array()
var _damage := PackedFloat32Array()  # one head bounce's damage
var _pop := PackedFloat32Array()  # the pop's damage before volleys
var _radius := PackedFloat32Array()  # the pop's blast radius
var _kick_ready := PackedFloat32Array()  # time from which this ball may be kicked again
var _hit_ready := PackedFloat32Array()  # time from which this ball may hit a head again
var _cfg: Dictionary = {}
var _query := PhysicsRayQueryParameters3D.new()
var _clock := 0.0


func _ready() -> void:
	add_to_group("beach_balls")
	var scene: PackedScene = load(MODEL) if ResourceLoader.exists(MODEL) else null
	for i in POOL_SIZE:
		var ball: Node3D
		if scene != null:
			ball = scene.instantiate() as Node3D
		else:
			var plain := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.0
			sphere.height = 2.0
			plain.mesh = sphere
			ball = plain
		ball.visible = false
		add_child(ball)
		_balls.append(ball)
	_vel.resize(POOL_SIZE)  # (packed arrays are values: each is resized by name)
	_life.resize(POOL_SIZE)
	_bounces.resize(POOL_SIZE)
	_ground.resize(POOL_SIZE)
	_volleys.resize(POOL_SIZE)
	_damage.resize(POOL_SIZE)
	_pop.resize(POOL_SIZE)
	_radius.resize(POOL_SIZE)
	_kick_ready.resize(POOL_SIZE)
	_hit_ready.resize(POOL_SIZE)


# A new ball from `origin` along `dir` (the gun's cfg: speed, size, damage shares). Reuses the oldest when all are out.
func launch(origin: Vector3, dir: Vector3, cfg: Dictionary, gun_damage: float, blast_radius: float) -> void:
	_cfg = cfg
	var i := _free_slot()
	var size := float(cfg.get("ball_radius", 0.22))
	_balls[i].scale = Vector3.ONE * size
	_balls[i].position = origin
	_balls[i].rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
	_balls[i].visible = true
	_vel[i] = dir * float(cfg.get("speed", 16.0))
	_life[i] = float(cfg.get("life", 7.0))
	_bounces[i] = 0
	_ground[i] = 0
	_volleys[i] = 0
	_damage[i] = gun_damage * float(cfg.get("bounce_damage", 0.5))
	_pop[i] = gun_damage * float(cfg.get("pop_damage", 1.2))
	_radius[i] = blast_radius
	_kick_ready[i] = _clock + 0.35  # not kicked by the shooter the moment it leaves the gun
	_hit_ready[i] = 0.0


func active_count() -> int:
	var n := 0
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			n += 1
	return n


# A shot along `dir` from `from` (any gun, anyone's on this machine): pops the first ball on its line. True if one popped.
func shot_through(from: Vector3, dir: Vector3, reach: float) -> bool:
	var best := -1
	var best_t := reach
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		var to_ball := _balls[i].position - from
		var t := to_ball.dot(dir)
		if t < 0.0 or t > best_t:
			continue
		var size := _balls[i].scale.x * 1.15  # a little generous: they are meant to be hit
		if (to_ball - dir * t).length_squared() <= size * size:
			best = i
			best_t = t
	if best < 0:
		return false
	_pop_ball(best)
	return true


func _physics_process(delta: float) -> void:
	_clock += delta
	if active_count() == 0:
		return
	var space := get_world_3d().direct_space_state
	_query.exclude = [kicker.get_rid()] if kicker is CollisionObject3D else []
	var enemies: Array = explosives.source.enemy_list() if explosives != null and explosives.source != null else []
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		var ball := _balls[i]
		var size := ball.scale.x
		_vel[i].y -= float(_cfg.get("gravity", 7.0)) * delta
		_vel[i] *= maxf(0.0, 1.0 - float(_cfg.get("drag", 0.25)) * delta)
		_kick(i)
		if _head_bounce(i, enemies):
			continue
		var from := ball.position
		var to := from + _vel[i] * delta
		_query.from = from
		_query.to = to + _vel[i].normalized() * size
		var hit := space.intersect_ray(_query)
		if not hit.is_empty() and not (hit.collider as Object).has_method("on_hit"):
			var n: Vector3 = hit.normal
			_vel[i] = _vel[i].bounce(n) * float(_cfg.get("restitution", 0.65))
			ball.position = (hit.position as Vector3) + n * (size + 0.01)
			if n.y > 0.6:
				_ground[i] += 1
				if _ground[i] >= int(_cfg.get("ground_bounces", 3)) or _vel[i].length() < 1.5:
					_pop_ball(i)
					continue
		else:
			ball.position = to
		ball.rotate_x(_vel[i].length() * delta / maxf(size, 0.05))  # it spins as it flies
		_life[i] -= delta
		if _life[i] <= 0.0:
			_pop_ball(i)


# Touching an enemy's head: it hits and the ball springs up off it. True when this tick was a bounce.
func _head_bounce(i: int, enemies: Array) -> bool:
	if _clock < _hit_ready[i]:
		return false
	var ball := _balls[i]
	for enemy: Node3D in enemies:
		if not is_instance_valid(enemy) or enemy.health.is_dead():
			continue
		var head: Vector3 = enemy.global_position + Vector3(0, enemy.head_height(), 0)
		var reach := ball.scale.x + HEAD_REACH
		if ball.position.distance_squared_to(head) > reach * reach:
			continue
		enemy.on_hit(_damage[i], head, Vector3.UP)
		if explosives.numbers != null:
			explosives.numbers.spawn(head, _damage[i])
		if explosives.score != null and not enemy.health.is_dead() and not enemy.has_meta("host_pays"):
			explosives.score.hit()
		var away := ball.position - head
		away.y = 0.0
		_vel[i] = away.normalized() * maxf(Vector2(_vel[i].x, _vel[i].z).length() * 0.6, 2.0) + Vector3.UP * float(_cfg.get("head_bounce", 7.5))
		ball.position = head + Vector3.UP * reach
		_hit_ready[i] = _clock + 0.2
		_bounces[i] += 1
		if _bounces[i] >= int(_cfg.get("max_bounces", 6)):
			_pop_ball(i)
		return true
	return false


# The local player walking into a ball kicks it where they look; each kick is a volley (a bigger pop).
func _kick(i: int) -> void:
	if kicker == null or _clock < _kick_ready[i]:
		return
	var reach := _balls[i].scale.x + float(_cfg.get("kick_reach", 0.9))
	var body := kicker.global_position + Vector3(0, 1.0, 0)
	if _balls[i].position.distance_squared_to(body) > reach * reach:
		return
	var flat: Vector3 = kicker.call("aim_flat")
	_vel[i] = (flat + Vector3.UP * 0.9).normalized() * float(_cfg.get("kick_speed", 10.0))
	_volleys[i] += 1
	_life[i] = maxf(_life[i], 3.0)  # a kicked ball stays up a while longer
	_ground[i] = 0
	_kick_ready[i] = _clock + 0.4


func _pop_ball(i: int) -> void:
	var at := _balls[i].position
	_life[i] = 0.0
	_balls[i].visible = false
	if explosives != null:
		var damage := _pop[i] * (1.0 + float(_volleys[i]) * float(_cfg.get("volley_bonus", 0.25)))
		explosives.blast(at, _radius[i], damage)
		if explosives.sounds != null:
			explosives.sounds.call("play", "explosion", at)


func _free_slot() -> int:
	var oldest := 0
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			return i
		if _life[i] < _life[oldest]:
			oldest = i
	_balls[oldest].visible = false
	return oldest
