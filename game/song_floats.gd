# Purpose: the hidden songs' glass fishing floats lying on the islands: a green glass ball in a rope net, half in
# the sand. Each is a game/hidden_target.gd; a shot one goes dark until its song has been found. Draws and reports
# hits only: core/song_book.gd decides.
# Dependencies: game/hidden_target.gd. `setup(spots, on_shot)`: spots[secret][thing] = world position.
extends Node3D

const HiddenTarget = preload("res://game/hidden_target.gd")
const RADIUS := 0.2

var _floats: Array = []  # [secret][thing] -> MeshInstance3D
var _glass := StandardMaterial3D.new()
var _dark := StandardMaterial3D.new()


func setup(spots: Array, on_shot: Callable) -> void:
	_glass.albedo_color = Color(0.35, 0.75, 0.55, 0.75)
	_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_glass.roughness = 0.1
	_glass.metallic_specular = 0.9
	_glass.emission_enabled = true
	_glass.emission = Color(0.1, 0.35, 0.25)
	_dark.albedo_color = Color(0.15, 0.2, 0.18)
	var ball := SphereMesh.new()
	ball.radius = RADIUS
	ball.height = RADIUS * 2.0
	ball.radial_segments = 12
	ball.rings = 6
	var net := TorusMesh.new()
	net.inner_radius = RADIUS * 0.95
	net.outer_radius = RADIUS * 1.08
	var rope := StandardMaterial3D.new()
	rope.albedo_color = Color(0.45, 0.36, 0.22)
	for secret in spots.size():
		var row: Array = []
		for thing in (spots[secret] as Array).size():
			var body := HiddenTarget.new()
			body.position = spots[secret][thing]
			body.rotation = Vector3(0.4, float(secret * 3 + thing), 0.2)
			body.hit_by = on_shot.bind(secret, thing)
			var shape := CollisionShape3D.new()
			var round_shape := SphereShape3D.new()
			round_shape.radius = RADIUS * 1.3  # a little easier to hit than it looks
			shape.shape = round_shape
			body.add_child(shape)
			var glass := MeshInstance3D.new()
			glass.mesh = ball
			glass.material_override = _glass
			glass.visibility_range_end = 45.0
			body.add_child(glass)
			var ring := MeshInstance3D.new()
			ring.mesh = net
			ring.material_override = rope
			ring.visibility_range_end = 30.0
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(ring)
			add_child(body)
			row.append(glass)
		_floats.append(row)


# A float shot (dark) or whole again.
func show_shot(secret: int, thing: int, shot: bool) -> void:
	(_floats[secret][thing] as MeshInstance3D).material_override = _dark if shot else _glass


func show_secret(secret: int, shot: bool) -> void:
	for thing in (_floats[secret] as Array).size():
		show_shot(secret, thing, shot)
