# Purpose: fixed pool of enemy projectiles (arrows), moved on the physics tick; nothing is allocated while playing.
# Dependencies: none. Projectiles hit the world and the player (physics layer 1), never other enemies.
extends Node3D

const POOL_SIZE := 48
const LIFETIME := 4.0

var _meshes: Array[MeshInstance3D] = []
var _velocity := PackedVector3Array()
var _damage := PackedFloat32Array()
var _life := PackedFloat32Array()
var _element: Array[String] = []  # "physical", "fire", "ice" or "toxic" per projectile
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	var arrow := BoxMesh.new()
	arrow.size = Vector3(0.05, 0.05, 0.55)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.75, 0.5)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_velocity.resize(POOL_SIZE)
	_damage.resize(POOL_SIZE)
	_life.resize(POOL_SIZE)
	_element.resize(POOL_SIZE)
	for i in POOL_SIZE:
		var m := MeshInstance3D.new()
		m.mesh = arrow
		m.material_override = mat
		m.visible = false
		add_child(m)
		_meshes.append(m)
	_query.collision_mask = 1


# Drops the shot silently if the pool is full (keeps the projectile cap).
func fire(origin: Vector3, direction: Vector3, speed: float, damage: float, element: String = "physical") -> void:
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD
			_meshes[i].look_at_from_position(origin, origin + direction, up)
			_meshes[i].reset_physics_interpolation()
			_meshes[i].visible = true
			_velocity[i] = direction * speed
			_damage[i] = damage
			_element[i] = element
			_life[i] = LIFETIME
			return


func active_count() -> int:
	var n := 0
	for i in POOL_SIZE:
		if _life[i] > 0.0:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue
		var from := _meshes[i].position
		var to := from + _velocity[i] * delta
		_query.from = from
		_query.to = to
		var hit := space.intersect_ray(_query)
		if not hit.is_empty():
			var target: Object = hit.collider
			if target.has_method("take_damage"):
				target.take_damage(_damage[i], _element[i])
			_deactivate(i)
			continue
		_meshes[i].position = to
		_life[i] -= delta
		if _life[i] <= 0.0:
			_deactivate(i)


func _deactivate(i: int) -> void:
	_life[i] = 0.0
	_meshes[i].visible = false
