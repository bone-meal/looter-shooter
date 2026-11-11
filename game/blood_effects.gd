# Purpose: pooled bursts of small bits flying out and falling when enemies are hit or die: red blood by default, or
# chips in a colour the caller names (bark, stone, sand, snow ... for the fantasy creatures).
# Dependencies: none. Fixed pool of emitters, reused round-robin, so nothing is allocated during play.
extends Node3D

const POOL_SIZE := 12
const BASE_SPEED := 6.0

var _emitters: Array[CPUParticles3D] = []
var _next := 0
var _cube := BoxMesh.new()  # blood: flat red
var _chip := BoxMesh.new()  # debris: lit, takes the colour of each burst


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.04, 0.04)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cube.size = Vector3(0.07, 0.07, 0.07)
	_cube.material = mat
	var chip_mat := StandardMaterial3D.new()
	chip_mat.vertex_color_use_as_albedo = true
	chip_mat.roughness = 0.9
	_chip.size = Vector3(0.09, 0.06, 0.08)
	_chip.material = chip_mat
	for i in POOL_SIZE:
		var p := CPUParticles3D.new()
		p.emitting = false
		p.one_shot = true
		p.amount = 16
		p.lifetime = 0.7
		p.explosiveness = 1.0
		p.mesh = _cube
		p.spread = 55.0
		p.gravity = Vector3(0, -12, 0)
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = BASE_SPEED
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.3
		add_child(p)
		_emitters.append(p)


# `big` adds a second, stronger burst (used on death). `chips` with alpha above 0 throws bits of that colour instead of blood.
func burst(point: Vector3, normal: Vector3, big: bool = false, chips: Color = Color(0, 0, 0, 0)) -> void:
	_fire(point, normal, 1.0, chips)
	if big:
		_fire(point + Vector3(0, 0.3, 0), Vector3.UP, 1.6, chips)


func _fire(point: Vector3, normal: Vector3, speed_scale: float, chips: Color) -> void:
	var p := _emitters[_next]
	p.mesh = _chip if chips.a > 0.0 else _cube
	p.color = chips if chips.a > 0.0 else Color.WHITE
	_next = (_next + 1) % POOL_SIZE
	p.global_position = point
	p.reset_physics_interpolation()
	p.direction = normal
	p.initial_velocity_max = BASE_SPEED * speed_scale
	p.restart()
