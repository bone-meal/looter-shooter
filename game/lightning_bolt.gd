# Purpose: a lightning bolt drawn for a moment between two points (Weathervane's strike, Kite Flyer's catch and dive):
# a jagged line of thin glowing boxes with a short flash of light, gone after 0.25 s. Only a picture: whoever calls it
# deals any damage.
# Dependencies: none.
extends Node3D

const LIFE := 0.25
const SEGMENTS := 8

static var _mesh: BoxMesh
static var _mat: StandardMaterial3D

var _age := 0.0
var _light: OmniLight3D


# A bolt from `from` to `to` in `world` (null world = nothing).
static func strike(world: Node, from: Vector3, to: Vector3) -> void:
	if world == null or not world.is_inside_tree():
		return
	var bolt := (load("res://game/lightning_bolt.gd") as GDScript).new() as Node3D
	world.add_child(bolt)
	bolt.call("_build", from, to)


func _build(from: Vector3, to: Vector3) -> void:
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3(0.06, 0.06, 1.0)
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.albedo_color = Color(0.85, 0.92, 1.0)
	var points: Array[Vector3] = [from]
	var side := (to - from).cross(Vector3.UP if absf((to - from).normalized().y) < 0.9 else Vector3.RIGHT).normalized()
	var other := (to - from).cross(side).normalized()
	var jag := from.distance_to(to) * 0.06
	for k in range(1, SEGMENTS):
		var t := float(k) / SEGMENTS
		points.append(from.lerp(to, t) + side * randf_range(-jag, jag) + other * randf_range(-jag, jag))
	points.append(to)
	for k in SEGMENTS:
		var a := points[k]
		var b := points[k + 1]
		var piece := MeshInstance3D.new()
		piece.mesh = _mesh
		piece.material_override = _mat
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		piece.global_position = (a + b) * 0.5
		if a.distance_to(b) > 0.01:
			piece.look_at(b, Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.RIGHT)
		piece.scale = Vector3(1.0, 1.0, a.distance_to(b))
	_light = OmniLight3D.new()
	_light.light_color = Color(0.75, 0.85, 1.0)
	_light.light_energy = 3.0
	_light.omni_range = 14.0
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = to + Vector3(0, 1.0, 0)


func _process(delta: float) -> void:
	_age += delta
	if _light != null:
		_light.light_energy = 3.0 * maxf(0.0, 1.0 - _age / LIFE)
	if _age >= LIFE:
		queue_free()
