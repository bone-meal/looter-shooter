# Purpose: the mystery box as a thing in the world: a crate with a question mark under a beam; while it spins guns
# flicker over it, then the offered gun hangs there; a seagull carries the crate to its next spot.
# Draws only; core/mystery_box.gd decides and the session tells it what to show.
# Dependencies: game/weapon_models.gd (the gun on offer), game/surface_library.gd.
extends Node3D

const WeaponModels = preload("res://game/weapon_models.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")

const BODIES := ["pistol_basic", "ak47", "shotgun_double", "m16", "sniper_basic", "m60"]
const FLICKER := 0.14  # seconds each gun shows while the box spins
const LIFT := 9.0  # how high the seagull carries it

var _crate := Node3D.new()
var _show := Node3D.new()  # holds the gun shown over the crate
var _gull := Node3D.new()
var _mode := "idle"
var _t := 0.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _fly_time := 5.0
var _flick := 0


func _ready() -> void:
	add_child(_crate)
	var wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 0.7, 0.8)
	var body := MeshInstance3D.new()
	body.mesh = box
	body.material_override = wood
	body.position = Vector3(0, 0.35, 0)
	_crate.add_child(body)
	var mark := Label3D.new()
	mark.text = "?"
	mark.font_size = 120
	mark.pixel_size = 0.005
	mark.modulate = Color(1.0, 0.85, 0.3)
	mark.position = Vector3(0, 0.36, 0.41)
	_crate.add_child(mark)
	var solid := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = box.size
	shape.shape = hull
	shape.position = Vector3(0, 0.35, 0)
	solid.add_child(shape)
	_crate.add_child(solid)
	_show.position = Vector3(0, 1.35, 0)
	_crate.add_child(_show)
	# the seagull: a white body, grey wings, an orange beak
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.93)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.62, 0.65, 0.7)
	var ball := SphereMesh.new()
	ball.radius = 0.28
	ball.height = 0.9
	_part(_gull, ball, white, Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	var wing := BoxMesh.new()
	wing.size = Vector3(2.6, 0.05, 0.45)
	_part(_gull, wing, grey, Vector3(0, 0.08, 0), Vector3.ZERO)
	var beak := BoxMesh.new()
	beak.size = Vector3(0.08, 0.08, 0.3)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.95, 0.6, 0.15)
	_part(_gull, beak, orange, Vector3(0, 0, -0.55), Vector3.ZERO)
	_gull.visible = false
	add_child(_gull)


func _part(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, turn: Vector3) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = at
	piece.rotation = turn
	parent.add_child(piece)


# The box stands at `at` doing nothing.
func stand(at: Vector3) -> void:
	_mode = "idle"
	global_position = at
	_crate.position = Vector3.ZERO
	_gull.visible = false
	_clear()


func spin() -> void:
	_mode = "spinning"
	_t = 0.0
	_flick = -1


# The gun on offer hangs over the crate (body = its gun body id).
func offer(body: String) -> void:
	_mode = "offer"
	_put(body)


# The seagull lifts the crate and sets it down at `at`, `seconds` later.
func fly_to(at: Vector3, seconds: float) -> void:
	_mode = "moving"
	_clear()
	_from = global_position
	_to = at
	_fly_time = maxf(seconds, 0.5)
	_t = 0.0
	_gull.visible = true


func _clear() -> void:
	for child: Node in _show.get_children():
		child.queue_free()


func _put(body: String) -> void:
	_clear()
	var gun := WeaponModels.build(body)
	gun.position = Vector3.ZERO
	gun.scale *= 1.6
	_show.add_child(gun)


func _process(delta: float) -> void:
	_t += delta
	_show.rotation.y += delta * 1.6
	if _mode == "spinning":
		var now := floori(_t / FLICKER)
		if now != _flick:
			_flick = now
			_put(String(BODIES[now % BODIES.size()]))
	elif _mode == "moving":
		var k := clampf(_t / _fly_time, 0.0, 1.0)
		var flat := _from.lerp(_to, smoothstep(0.15, 0.85, k))
		global_position = flat + Vector3(0, LIFT * sin(k * PI), 0)
		_gull.position = Vector3(0, 1.3 + 0.15 * sin(_t * 9.0), 0)
		_gull.rotation.y = atan2(-(_to.x - _from.x), -(_to.z - _from.z))
		if k >= 1.0:
			stand(_to)
