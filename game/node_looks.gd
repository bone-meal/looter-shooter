# Purpose: (polish1 items 106 / 109) what makes a thing you can gather in Aurelind look different from the same kind
# of scenery: a gather node's model plus its "look" from data/fantasy/skilling.json nodes: a coloured forester's band
# round the trunk (one colour per woodcutting tier), a fresh axe notch and wood chips at the foot (a tree marked for
# felling); a golden tint, heavy grain heads and a twine tie (ripe wheat). Built once per node kind into one mesh, so
# the nodes still draw as one MultiMesh per kind.
# Dependencies: game/fantasy_models.gd (surface materials).
extends RefCounted

const FantasyModels = preload("res://game/fantasy_models.gd")


# The node model with its look added. look keys (all optional): "tint" [r, g, b] multiplies the model's colours,
# "band" [r, g, b] + "band_h" m, "notch" true, "chips" true, "heads" [r, g, b] + "heads_h" m.
static func compose(base: Mesh, look: Dictionary) -> Mesh:
	if base == null or look.is_empty():
		return base
	var out := ArrayMesh.new()
	var bark: PackedVector3Array = PackedVector3Array()
	for s in base.get_surface_count():
		var arrays := base.surface_get_arrays(s)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat: Material = base.surface_get_material(s)
		if look.has("tint") and mat is StandardMaterial3D:
			var m := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			var t: Array = look["tint"]
			m.albedo_color = Color(m.albedo_color.r * float(t[0]), m.albedo_color.g * float(t[1]), m.albedo_color.b * float(t[2]))
			mat = m
		out.surface_set_material(out.get_surface_count() - 1, mat)
		if s == 0:
			bark = arrays[Mesh.ARRAY_VERTEX]
	if look.has("band"):
		var h := float(look.get("band_h", 1.3))
		var ring := _trunk_at(bark, h)
		_add(out, _tube(ring, h, 0.24, 0.03), _color("cloth", look["band"]))
		var tail := SurfaceTool.new()  # a tail of the band hanging down one side
		tail.begin(Mesh.PRIMITIVE_TRIANGLES)
		var c: Vector3 = ring[0]
		var r := float(ring[1]) + 0.035
		_box(tail, Vector3(c.x + r, h - 0.22, c.z), Vector3(0.03, 0.34, 0.11), 0.15)
		_add(out, tail.commit(), _color("cloth", look["band"]))
	if bool(look.get("notch", false)):
		var ring2 := _trunk_at(bark, 0.55)
		var c2: Vector3 = ring2[0]
		var r2 := float(ring2[1])
		var cut := SurfaceTool.new()  # fresh pale wood where an axe bit in, facing the other way from the band's tail
		cut.begin(Mesh.PRIMITIVE_TRIANGLES)
		_box(cut, Vector3(c2.x - r2 * 0.92, 0.55, c2.z), Vector3(0.05, 0.2, minf(r2 * 1.3, 0.4)), 0.0)
		_add(out, cut.commit(), _color("wood", [1.6, 1.4, 1.0]))
	if bool(look.get("chips", false)):
		var ring3 := _trunk_at(bark, 0.3)
		var c3: Vector3 = ring3[0]
		var chips := SurfaceTool.new()
		chips.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 9:
			var a := float(k) * 2.4 + 0.3
			var d := float(ring3[1]) + 0.2 + fmod(float(k) * 0.37, 0.5)
			_box(chips, Vector3(c3.x + cos(a) * d, 0.03, c3.z + sin(a) * d), Vector3(0.13, 0.025, 0.07), a)
		_add(out, chips.commit(), _color("wood", [1.45, 1.3, 0.95]))
	if look.has("heads"):  # heavy grain heads standing out of the top of a sheaf
		var h4 := float(look.get("heads_h", 1.0))
		var heads := SurfaceTool.new()
		heads.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in 9:
			var a := TAU * float(k) / 9.0
			var rr := 0.07 + 0.06 * float(k % 3)
			var at := Vector3(cos(a) * rr, h4 + 0.04 * float(k % 2), sin(a) * rr)
			_ear(heads, at, Vector3(cos(a) * 0.35, 1.0, sin(a) * 0.35).normalized(), 0.2, 0.035)
		_add(out, heads.commit(), _color("cloth", look["heads"]))
	if look.has("tie"):
		var h5 := float(look.get("tie_h", 0.45))
		var ring5 := _trunk_at(bark, h5)
		_add(out, _tube([ring5[0], maxf(float(ring5[1]), 0.08)], h5, 0.06, 0.012), _color("leather", look["tie"]))
	return out


# The trunk's middle and radius at height h (from the first surface's vertices near that height).
static func _trunk_at(verts: PackedVector3Array, h: float) -> Array:
	var pts: Array = []
	for v: Vector3 in verts:
		if absf(v.y - h) < 0.2 and Vector2(v.x, v.z).length() < 1.2:
			pts.append(v)
	if pts.size() < 3:
		return [Vector3(0, h, 0), 0.25]
	var mid := Vector3.ZERO
	for p: Vector3 in pts:
		mid += p
	mid /= float(pts.size())
	var ds: Array = []
	for p: Vector3 in pts:
		ds.append(Vector2(p.x - mid.x, p.z - mid.z).length())
	ds.sort()
	return [Vector3(mid.x, h, mid.z), clampf(float(ds[int(float(ds.size()) * 0.6)]), 0.06, 0.6)]


static func _tube(ring: Array, h: float, tall: float, out_by: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Vector3 = ring[0]
	var r := float(ring[1]) + out_by
	var n := 14
	for k in n:
		var a0 := TAU * float(k) / float(n)
		var a1 := TAU * float(k + 1) / float(n)
		var p0 := Vector3(c.x + cos(a0) * r, h - tall * 0.5, c.z + sin(a0) * r)
		var p1 := Vector3(c.x + cos(a1) * r, h - tall * 0.5, c.z + sin(a1) * r)
		var n0 := Vector3(cos(a0), 0, sin(a0))
		var n1 := Vector3(cos(a1), 0, sin(a1))
		st.set_normal(n0); st.add_vertex(p0)
		st.set_normal(n0); st.add_vertex(p0 + Vector3(0, tall, 0))
		st.set_normal(n1); st.add_vertex(p1)
		st.set_normal(n1); st.add_vertex(p1)
		st.set_normal(n0); st.add_vertex(p0 + Vector3(0, tall, 0))
		st.set_normal(n1); st.add_vertex(p1 + Vector3(0, tall, 0))
	return st.commit()


static func _box(st: SurfaceTool, center: Vector3, size: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var h := size * 0.5
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD], [Vector3.UP, Vector3.BACK, Vector3.RIGHT],
		[Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT], [Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]
	for f: Array in faces:
		var nrm: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var o := nrm * h
		var du := u * h
		var dv := v * h
		var q := [o - du - dv, o + du - dv, o + du + dv, o - du + dv]
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(b * nrm)
			st.add_vertex(center + b * (q[i] as Vector3))


static func _ear(st: SurfaceTool, at: Vector3, up: Vector3, length: float, radius: float) -> void:
	var side := up.cross(Vector3.FORWARD).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var fwd := side.cross(up).normalized()
	var rings := 5
	var seg := 6
	for i in rings:
		for k in seg:
			var t0 := float(i) / float(rings)
			var t1 := float(i + 1) / float(rings)
			var r0 := radius * sin(PI * clampf(t0, 0.05, 0.95))
			var r1 := radius * sin(PI * clampf(t1, 0.05, 0.95))
			var a0 := TAU * float(k) / float(seg)
			var a1 := TAU * float(k + 1) / float(seg)
			var d0 := side * cos(a0) + fwd * sin(a0)
			var d1 := side * cos(a1) + fwd * sin(a1)
			var q := [at + up * length * t0 + d0 * r0, at + up * length * t0 + d1 * r0, at + up * length * t1 + d1 * r1, at + up * length * t1 + d0 * r1]
			var nn := [d0, d1, d1, d0]
			for j: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nn[j])
				st.add_vertex(q[j])


static func _add(out: ArrayMesh, part: Mesh, mat: Material) -> void:
	if part == null or part.get_surface_count() == 0:
		return
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part.surface_get_arrays(0))
	out.surface_set_material(out.get_surface_count() - 1, mat)


# One of the fantasy look's own surfaces (game/fantasy_models.gd: lit like the rest of the world), tinted.
static func _color(kind: String, c: Array) -> StandardMaterial3D:
	return FantasyModels.tinted(kind, Color(float(c[0]), float(c[1]), float(c[2])))
