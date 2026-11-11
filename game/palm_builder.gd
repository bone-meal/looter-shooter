# Purpose: builds one palm tree mesh in code for the realistic look: a curved, tapering trunk (surface 0) and a crown
# of arching fronds made of separate leaflets (surface 1). About 2k triangles, so it is cheap on every tier.
# Dependencies: none. The caller supplies the bark material; leaf_material() is the frond material.
extends RefCounted

const HEIGHT := 5.2
const LEAN := 0.9           # how far the top leans sideways (local +X)
const TRUNK_RINGS := 10
const TRUNK_SIDES := 8
const FRONDS := 16
const STATIONS := 20        # leaflet pairs along one frond

static var _mesh: ArrayMesh
static var _leaves: StandardMaterial3D


static func leaf_material() -> StandardMaterial3D:
	if _leaves == null:
		_leaves = StandardMaterial3D.new()
		_leaves.albedo_color = Color(0.24, 0.36, 0.13)
		_leaves.vertex_color_use_as_albedo = true
		_leaves.cull_mode = BaseMaterial3D.CULL_DISABLED
		_leaves.roughness = 0.55
		_leaves.backlight_enabled = true
		_leaves.backlight = Color(0.16, 0.24, 0.05)
	return _leaves


static func mesh(bark: Material) -> ArrayMesh:
	if _mesh == null:
		_mesh = ArrayMesh.new()
		_trunk().commit(_mesh)
		_crown().commit(_mesh)
		_mesh.surface_set_material(1, leaf_material())
	_mesh.surface_set_material(0, bark)
	return _mesh


# Point on the trunk centre line, t from 0 (ground) to 1 (top).
static func _spine(t: float) -> Vector3:
	return Vector3(LEAN * t * t, HEIGHT * t, 0.0)


static func _trunk() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in TRUNK_RINGS:
		for side in TRUNK_SIDES:
			var quad: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for corner: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var t := float(ring + corner.y) / TRUNK_RINGS
				var angle := TAU * float(side + corner.x) / TRUNK_SIDES
				var radius := lerpf(0.3, 0.15, t) + 0.08 * maxf(0.0, 1.0 - t * 6.0)
				var out := Vector3(cos(angle), 0.0, sin(angle))
				quad.append(_spine(t) + out * radius)
				normals.append(out)
			_quad(st, quad, normals, Color.WHITE)
	return st


static func _crown() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var top := _spine(1.0)
	for i in FRONDS:
		var yaw := TAU * float(i) / FRONDS + rng.randf_range(-0.2, 0.2)
		var lift := deg_to_rad(rng.randf_range(-5.0, 70.0))     # start angle above the horizon
		var length := rng.randf_range(2.4, 3.3)
		var droop := deg_to_rad(rng.randf_range(70.0, 110.0))   # how far the tip bends down
		var shade := rng.randf_range(0.75, 1.1)
		var side_dir := Vector3(-sin(yaw), 0.0, cos(yaw))        # horizontal, across the frond
		var prev := top
		var prev_dir := Vector3.UP
		for s in STATIONS + 1:
			var f := float(s) / STATIONS
			var pitch := lift - droop * pow(f, 1.4)
			var dir := Vector3(cos(yaw) * cos(pitch), sin(pitch), sin(yaw) * cos(pitch))
			var here := prev + dir * (length / STATIONS) if s > 0 else top
			var color := Color(shade, shade, shade * 0.9).lerp(Color(1.0, 0.95, 0.6), f * f * 0.35)
			if s > 0:
				var stem_up := prev_dir.cross(side_dir).normalized()
				var half := side_dir * lerpf(0.035, 0.008, f)
				_quad(st, [prev - half, prev + half, here + half, here - half], [stem_up, stem_up, stem_up, stem_up], color)
				if f > 0.1:
					var leaf_len := 0.75 * sin(PI * (0.12 + 0.88 * f)) + 0.1
					for sign_side: float in [-1.0, 1.0]:
						var along := (side_dir * sign_side + dir * 0.45 + Vector3.DOWN * 0.4).normalized()
						var tip := here + along * leaf_len
						var base_half := dir * 0.05
						var n := along.cross(dir).normalized() * sign_side
						_tri(st, here - base_half, here + base_half, tip, n, color)
			prev = here
			prev_dir = dir
	return st


static func _quad(st: SurfaceTool, p: Array, n: Array, color: Color) -> void:
	var face: Vector3 = ((n[0] as Vector3) + (n[1] as Vector3) + (n[2] as Vector3) + (n[3] as Vector3)).normalized()
	for idx: Array in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = p[idx[0]]
		var b: Vector3 = p[idx[1]]
		var c: Vector3 = p[idx[2]]
		var order := [idx[0], idx[1], idx[2]]
		if (b - a).cross(c - a).dot(face) > 0.0:
			order = [idx[0], idx[2], idx[1]]  # Godot front faces are clockwise
		for k: int in order:
			st.set_color(color)
			st.set_normal(n[k])
			st.add_vertex(p[k])


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
	var pts := [a, b, c]
	if (b - a).cross(c - a).dot(n) > 0.0:
		pts = [a, c, b]
	for p: Vector3 in pts:
		st.set_color(color)
		st.set_normal(n)
		st.add_vertex(p)
