# Purpose: a lightning bolt drawn for a moment between two points (Weathervane's strike, Kite Flyer's catch and dive):
# a jagged, forking ribbon turned to face the camera, a wide pale-blue glow round a thin white core (soft-edged
# texture across its width), with a short flash of light; gone after 0.25 s. Only a picture: whoever calls it deals
# any damage.
# Dependencies: game/fx_kit.gd (glow material).
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")
const LIFE := 0.25
const SEGMENTS := 9

static var _across: GradientTexture2D

var _age := 0.0
var _light: OmniLight3D
var _mesh: MeshInstance3D


# A bolt from `from` to `to` in `world` (null world = nothing).
static func strike(world: Node, from: Vector3, to: Vector3) -> void:
	if world == null or not world.is_inside_tree():
		return
	var bolt := (load("res://game/lightning_bolt.gd") as GDScript).new() as Node3D
	world.add_child(bolt)
	bolt.call("_build", from, to)


static func _soft_across() -> GradientTexture2D:
	if _across == null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		_across = GradientTexture2D.new()
		_across.gradient = grad
		_across.width = 32
		_across.height = 4
	return _across


func _jagged(from: Vector3, to: Vector3, steps: int, jag: float) -> Array[Vector3]:
	var pts: Array[Vector3] = [from]
	var along := to - from
	var side := along.cross(Vector3.UP if absf(along.normalized().y) < 0.9 else Vector3.RIGHT).normalized()
	var other := along.cross(side).normalized()
	for k in range(1, steps):
		var t := float(k) / steps
		pts.append(from.lerp(to, t) + side * randf_range(-jag, jag) + other * randf_range(-jag, jag))
	pts.append(to)
	return pts


func _build(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	var lines: Array = [_jagged(from, to, SEGMENTS, length * 0.06)]
	var main: Array[Vector3] = lines[0]
	for _f in 3:  # forks off the main path
		var at := main[randi_range(2, SEGMENTS - 2)]
		var off := Vector3(randf_range(-1, 1), randf_range(-0.6, -0.1), randf_range(-1, 1)).normalized() * length * randf_range(0.08, 0.18)
		lines.append(_jagged(at, at + off, 4, length * 0.02))
	var camera := get_viewport().get_camera_3d()
	var eye := camera.global_position if camera != null else from + Vector3(0, 0, 10)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for n in lines.size():
		var pts: Array[Vector3] = lines[n]
		for width: float in ([0.55, 0.12] if n == 0 else [0.25, 0.06]):  # glow, then core
			var tint := Color(0.55, 0.7, 1.0, 0.55) if width > 0.2 else Color(1, 1, 1, 1)
			for k in pts.size() - 1:
				var a := pts[k]
				var b := pts[k + 1]
				var across := (b - a).cross(eye - (a + b) * 0.5).normalized() * width * 0.5
				st.set_color(tint)
				st.set_uv(Vector2(0, 0)); st.add_vertex(a - across)
				st.set_uv(Vector2(1, 0)); st.add_vertex(a + across)
				st.set_uv(Vector2(1, 1)); st.add_vertex(b + across)
				st.set_uv(Vector2(0, 0)); st.add_vertex(a - across)
				st.set_uv(Vector2(1, 1)); st.add_vertex(b + across)
				st.set_uv(Vector2(0, 1)); st.add_vertex(b - across)
	_mesh = MeshInstance3D.new()
	_mesh.mesh = st.commit()
	var mat := FxKit.glow(Color.WHITE, true, _soft_across()).duplicate() as StandardMaterial3D
	mat.vertex_color_use_as_albedo = true
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.75, 0.85, 1.0)
	_light.light_energy = 3.0
	_light.omni_range = 14.0
	_light.shadow_enabled = false
	add_child(_light)
	_light.global_position = to + Vector3(0, 1.0, 0)


func _process(delta: float) -> void:
	_age += delta
	var left := maxf(0.0, 1.0 - _age / LIFE)
	if _light != null:
		_light.light_energy = 3.0 * left
	if _mesh != null:
		(_mesh.material_override as StandardMaterial3D).albedo_color = Color(1, 1, 1, left)
	if _age >= LIFE:
		queue_free()
