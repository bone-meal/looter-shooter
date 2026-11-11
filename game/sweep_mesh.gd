# Purpose: builds a mesh by sweeping a 2D profile (offset outward, height) once around an ellipse, or around a point
# for round things like pillars. Curved along the sweep, sharp at every profile corner, UVs in metres so a tiling
# stone texture keeps its real size. Dependencies: none.
# Profile rule: walking along the profile, the visible side is on the left (a wall seen from the centre runs upward;
# a pillar seen from outside runs downward).
extends RefCounted


# profile: points Vector2(offset, height). half_x / half_z: the ellipse at offset 0 (both 0 = a lathe around the Y axis).
# tile: texture repeat in metres (the sweep direction is stretched slightly so the pattern closes without a seam).
static func build(profile: PackedVector2Array, half_x: float, half_z: float, segments: int, tile: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := 0.0
	for j in profile.size() - 1:
		var p0 := profile[j]
		var p1 := profile[j + 1]
		var edge := p1 - p0
		var edge_len := edge.length()
		if edge_len < 0.0001:
			continue
		var n2 := Vector2(-edge.y, edge.x) / edge_len  # visible side, in (outward, up)
		var mid := (p0.x + p1.x) * 0.5
		var around := _circumference(half_x + mid, half_z + mid, segments)
		var u_fix := maxf(roundf(around / tile), 1.0) * tile / maxf(around, 0.0001)
		var u := 0.0
		for i in segments:
			var a0 := TAU * float(i) / segments
			var a1 := TAU * float(i + 1) / segments
			var step := _point(a0, mid, 0.0, half_x, half_z).distance_to(_point(a1, mid, 0.0, half_x, half_z)) * u_fix
			var n_a := _normal(a0, mid, n2, half_x, half_z)
			var n_b := _normal(a1, mid, n2, half_x, half_z)
			var corners := [
				[_point(a0, p0.x, p0.y, half_x, half_z), n_a, Vector2(u, v)],
				[_point(a1, p0.x, p0.y, half_x, half_z), n_b, Vector2(u + step, v)],
				[_point(a1, p1.x, p1.y, half_x, half_z), n_b, Vector2(u + step, v + edge_len)],
				[_point(a0, p1.x, p1.y, half_x, half_z), n_a, Vector2(u, v + edge_len)],
			]
			_quad(st, corners)
			u += step
		v += edge_len
	st.generate_tangents()
	return st.commit()


static func _point(angle: float, offset: float, height: float, half_x: float, half_z: float) -> Vector3:
	return Vector3((half_x + offset) * cos(angle), height, (half_z + offset) * sin(angle))


static func _normal(angle: float, offset: float, n2: Vector2, half_x: float, half_z: float) -> Vector3:
	var out := Vector3((half_z + offset) * cos(angle), 0.0, (half_x + offset) * sin(angle))
	if out.length_squared() < 0.000001:
		out = Vector3(cos(angle), 0.0, sin(angle))
	return (out.normalized() * n2.x + Vector3.UP * n2.y).normalized()


static func _circumference(rx: float, rz: float, segments: int) -> float:
	var total := 0.0
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		total += Vector3(rx * cos(a0), 0.0, rz * sin(a0)).distance_to(Vector3(rx * cos(a1), 0.0, rz * sin(a1)))
	return total


static func _quad(st: SurfaceTool, corners: Array) -> void:
	var face: Vector3 = ((corners[0][1] as Vector3) + (corners[1][1] as Vector3)).normalized()
	for tri: Array in [[0, 1, 2], [0, 2, 3]]:
		var a: Vector3 = corners[tri[0]][0]
		var b: Vector3 = corners[tri[1]][0]
		var c: Vector3 = corners[tri[2]][0]
		var order: Array = tri
		if (b - a).cross(c - a).dot(face) > 0.0:
			order = [tri[0], tri[2], tri[1]]  # Godot front faces are clockwise
		for k: int in order:
			st.set_normal(corners[k][1])
			st.set_uv(corners[k][2])
			st.add_vertex(corners[k][0])
