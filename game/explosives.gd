# Purpose: player rockets and grenades: a fixed projectile pool stepped on the physics tick, explosion damage in a radius, and a pooled explosion flash.
# Dependencies: game/damage_numbers.gd (optional `numbers`), core/score_card.gd (optional `score`). `source` must have enemy_list() (game/wave_director.gd). Stats come from the "projectile" block in data/weapons.json.
extends Node3D

const POOL_SIZE := 12
const EXPLOSION_POOL := 6
const LIFETIME := 5.0
const FLASH_TIME := 0.35
const MIN_DAMAGE_FRACTION := 0.35  # damage at the very edge of the blast

var source  # has enemy_list()
var sounds: Node  # the game's sound player, set by game/game_session.gd
var numbers  # DamageNumbers or null
var score: RefCounted  # core/score_card.gd or null: a blast pays one hit for every enemy it hurts without killing
var cripple := {}  # data/island_rounds.json "cripple": a blast that takes `share` of an island enemy's health without killing it leaves it crawling
var ignore: RID  # the player's body, so shots don't hit their owner

var _meshes: Array[MeshInstance3D] = []
var _velocity := PackedVector3Array()
var _life := PackedFloat32Array()
var _gravity := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _damage := PackedFloat32Array()
var _rocket_mesh := BoxMesh.new()
var _grenade_mesh := SphereMesh.new()
var _flashes: Array[MeshInstance3D] = []
var _flash_age := PackedFloat32Array()
var _flash_radius := PackedFloat32Array()
var _query := PhysicsRayQueryParameters3D.new()
var _next_flash := 0


func _ready() -> void:
	_rocket_mesh.size = Vector3(0.14, 0.14, 0.6)
	_grenade_mesh.radius = 0.12
	_grenade_mesh.height = 0.24
	var rocket_mat := StandardMaterial3D.new()
	rocket_mat.albedo_color = Color(0.9, 0.45, 0.15)
	_velocity.resize(POOL_SIZE)
	_life.resize(POOL_SIZE)
	_gravity.resize(POOL_SIZE)
	_radius.resize(POOL_SIZE)
	_damage.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var m := MeshInstance3D.new()
		m.material_override = rocket_mat
		m.visible = false
		add_child(m)
		_meshes.append(m)
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 12
	ball.rings = 6
	for i in EXPLOSION_POOL:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.6, 0.15, 0.7)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var f := MeshInstance3D.new()
		f.mesh = ball
		f.material_override = mat
		f.visible = false
		f.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(f)
		_flashes.append(f)
		_flash_age.append(FLASH_TIME)
		_flash_radius.append(1.0)
	_query.collision_mask = 3  # world + enemies


# `stats` is the weapon's "projectile" block: kind ("rocket" or "grenade"), speed, gravity, splash_radius, splash_damage.
# Silently drops the shot when the pool is full.
func fire(origin: Vector3, direction: Vector3, stats: Dictionary) -> void:
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			var is_rocket: bool = stats["kind"] == "rocket"
			if is_rocket:
				_meshes[i].mesh = _rocket_mesh
			else:
				_meshes[i].mesh = _grenade_mesh
			var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
			_meshes[i].look_at_from_position(origin, origin + direction, up)
			_meshes[i].reset_physics_interpolation()
			_meshes[i].visible = true
			_velocity[i] = direction * float(stats["speed"])
			_gravity[i] = float(stats["gravity"])
			_radius[i] = float(stats["splash_radius"])
			_damage[i] = float(stats["splash_damage"])
			_life[i] = LIFETIME
			return


func active_count() -> int:
	var n := 0
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	_query.exclude = [ignore]
	var space := get_world_3d().direct_space_state
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		_velocity[i].y -= _gravity[i] * delta
		var from := _meshes[i].position
		var to := from + _velocity[i] * delta
		_query.from = from
		_query.to = to
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			_explode(i, hit.position)
			continue
		_meshes[i].position = to
		_life[i] -= delta
		if _life[i] <= 0.0:
			_explode(i, to)


func _process(delta: float) -> void:
	for i in EXPLOSION_POOL:
		if _flash_age[i] >= FLASH_TIME:
			continue
		_flash_age[i] += delta
		if _flash_age[i] >= FLASH_TIME:
			_flashes[i].visible = false
			continue
		var t := _flash_age[i] / FLASH_TIME
		_flashes[i].scale = Vector3.ONE * lerpf(0.3, _flash_radius[i], sqrt(t))
		(_flashes[i].material_override as StandardMaterial3D).albedo_color.a = 0.7 * (1.0 - t)


func _explode(i: int, point: Vector3) -> void:
	if sounds != null:
		sounds.call("play", "explosion", point)
	var radius := _radius[i]
	var damage := _damage[i]
	_life[i] = 0.0
	_meshes[i].visible = false
	_show_flash(point, radius)
	if source == null:
		return
	for enemy in source.enemy_list().duplicate():
		if not is_instance_valid(enemy):
			continue
		var center: Vector3 = enemy.global_position + Vector3(0, enemy.head_height() * 0.5, 0)
		var distance := center.distance_to(point)
		if distance > radius:
			continue
		var dealt: float = damage * lerpf(1.0, MIN_DAMAGE_FRACTION, distance / radius)
		enemy.on_hit(dealt, center, Vector3.UP)
		if score != null and not enemy.health.is_dead() and not enemy.has_meta("host_pays"):
			score.hit()
		if not cripple.is_empty() and enemy.has_meta("island") and not enemy.health.is_dead() and dealt >= float(enemy.health.max_hp) * float(cripple["share"]):
			enemy.cripple(float(cripple["speed"]))
		if numbers != null:
			numbers.spawn(center, dealt)


# Instant blast at `point` (gun buffs): damages enemies in range like a splash, optionally with the flash.
func blast(point: Vector3, radius: float, damage: float, flash: bool = true) -> void:
	if flash:
		_show_flash(point, radius)
	if source == null:
		return
	for enemy in source.enemy_list().duplicate():
		if not is_instance_valid(enemy):
			continue
		var center: Vector3 = enemy.global_position + Vector3(0, enemy.head_height() * 0.5, 0)
		var distance := center.distance_to(point)
		if distance > radius:
			continue
		var dealt: float = damage * lerpf(1.0, MIN_DAMAGE_FRACTION, distance / radius)
		enemy.on_hit(dealt, center, Vector3.UP)
		if score != null and not enemy.health.is_dead() and not enemy.has_meta("host_pays"):
			score.hit()
		if not cripple.is_empty() and enemy.has_meta("island") and not enemy.health.is_dead() and dealt >= float(enemy.health.max_hp) * float(cripple["share"]):
			enemy.cripple(float(cripple["speed"]))
		if numbers != null:
			numbers.spawn(center, dealt)


func _show_flash(point: Vector3, radius: float) -> void:
	var f := _flashes[_next_flash]
	f.position = point
	f.scale = Vector3.ONE * 0.3
	f.visible = true
	_flash_age[_next_flash] = 0.0
	_flash_radius[_next_flash] = radius
	_next_flash = (_next_flash + 1) % EXPLOSION_POOL
