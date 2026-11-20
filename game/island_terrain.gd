# Purpose: (polish1 D4a) the solid lie of the land on the islands (core/archipelago.gd `blocks`): RIDGES (craggy rock
# walls, too steep to climb: cover and choke points), RUINS (broken stone walls with gaps and fallen blocks) and
# BOULDERS. Meshes are made in code from noise-displaced shapes and merged into one mesh per island and kind (a few
# draw calls an island); each has a simple collider (boxes / spheres), which is also what the navigation mesh sees.
# Dependencies: core/archipelago.gd, game/surface_library.gd (fx_rock, fx_stone).
extends RefCounted

const SurfaceLibrary = preload("res://game/surface_library.gd")


static func build(parent: Node3D, land: RefCounted, centre: Vector3) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.45
	var per: Dictionary = {}  # "<island>:<kind>" -> SurfaceTool
	var body := StaticBody3D.new()
	body.name = "IslandTerrain"
	body.position = centre
	parent.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for b: Dictionary in land.get("blocks"):
		var kind := String(b["kind"])
		var key := "%d:%s" % [int(b["island"]), "rock" if kind != "ruin" else "ruin"]
		if not per.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			per[key] = st
		var st2: SurfaceTool = per[key]
		var a: Vector2 = b["a"]
		var e: Vector2 = b["b"]
		var ground := float(land.call("height_at", (a.x + e.x) * 0.5, (a.y + e.y) * 0.5))
		colour = Color(0.62, 0.58, 0.52) if kind == "ruin" else (Color(0.48, 0.45, 0.41) if kind == "ridge" else Color(0.52, 0.5, 0.47))
		match kind:
			"ridge":
				_ridge(st2, body, a, e, float(b["height"]), ground, noise)
			"ruin":
				_ruin(st2, body, a, e, float(b["height"]), ground, rng)
			_:
				_boulder(st2, body, a, float(b["half_width"]), ground, noise, rng)
	for key: String in per:
		var st3: SurfaceTool = per[key]
		var mesh := st3.commit()
		var n := MeshInstance3D.new()
		n.mesh = mesh
		n.position = centre
		var m := SurfaceLibrary.material("fx_stone" if key.ends_with("ruin") else "fx_rock", Color.WHITE)
		m.vertex_color_use_as_albedo = true  # (the shared "grain" surfaces take their colour from the mesh, as the fantasy props do)
		n.material_override = m
		parent.add_child(n)


# A craggy wall: a box swept from a to b, wider at the foot, its faces pushed in and out by noise, the top jagged.
static func _ridge(st: SurfaceTool, body: StaticBody3D, a: Vector2, b: Vector2, h: float, ground: float, noise: FastNoiseLite) -> void:
	var along := (b - a)
	var length := along.length()
	var dir := along / length
	var side := Vector2(-dir.y, dir.x)
	var steps := maxi(4, ceili(length / 1.0))
	var rings: Array = []  # each: an outline of points (3D) round the wall at that step
	for i in steps + 1:
		var t := float(i) / float(steps)
		var end_taper := clampf(minf(t, 1.0 - t) * length / 2.5, 0.25, 1.0)  # the ends round off
		var c := a + along * t
		var top_h := h * end_taper * (0.85 + 0.3 * noise.get_noise_2d(c.x * 0.6, c.y * 0.6))
		var foot := 1.9 * end_taper
		var crest := 0.55 * end_taper
		var outline := [Vector2(-foot, -0.6), Vector2(-crest - 0.3, top_h * 0.7), Vector2(-crest * 0.5, top_h), Vector2(crest * 0.5, top_h * 0.96), Vector2(crest + 0.3, top_h * 0.68), Vector2(foot, -0.6)]
		var ring: Array[Vector3] = []
		for o: Vector2 in outline:
			var p2 := c + side * o.x
			var bump := noise.get_noise_3d(p2.x * 1.3, o.y * 1.3, p2.y * 1.3) * 0.45
			var p := Vector3(p2.x, ground + o.y, p2.y) + Vector3(side.x, 0, side.y) * bump * signf(o.x)
			ring.append(p)
		rings.append(ring)
	var axis := func(p: Vector3) -> Vector3:  # the point inside the wall next to p
		var t2 := clampf((Vector2(p.x, p.z) - a).dot(dir), 0.3, length - 0.3)
		var q := a + dir * t2
		return Vector3(q.x, ground + h * 0.3, q.y)
	for i in steps:
		var r0: Array = rings[i]
		var r1: Array = rings[i + 1]
		for k in r0.size() - 1:
			_quad(st, r0[k], r0[k + 1], r1[k + 1], r1[k], axis)
	for end: int in [0, steps]:  # end caps
		var ring2: Array = rings[end]
		for k in range(1, ring2.size() - 1):
			_tri(st, ring2[0], ring2[k], ring2[k + 1], axis)
	# (polish1 item 110 / director: no getting stuck) the collider follows the rock's real slopes (a convex shell of its
	# cross-sections, a little inside the bumps) so a body slides along the face instead of meeting an invisible box edge
	var hull := PackedVector3Array()
	for i2 in range(0, rings.size(), maxi(1, floori(rings.size() / 6.0))):
		for p3: Vector3 in rings[i2]:
			hull.append(p3)
	for p4: Vector3 in rings[rings.size() - 1]:
		hull.append(p4)
	var shape := CollisionShape3D.new()
	var convex := ConvexPolygonShape3D.new()
	convex.points = hull
	shape.shape = convex
	body.add_child(shape)


# A broken stone wall: blocks of uneven height with a gap or two, fallen stones at its foot.
static func _ruin(st: SurfaceTool, body: StaticBody3D, a: Vector2, b: Vector2, h: float, ground: float, rng: RandomNumberGenerator) -> void:
	var along := b - a
	var length := along.length()
	var dir := along / length
	var side := Vector2(-dir.y, dir.x)
	var yaw := atan2(dir.x, dir.y)
	var t := 0.0
	var gap_at := rng.randf_range(0.3, 0.7)
	while t < length - 0.2:
		var piece := minf(rng.randf_range(1.2, 2.4), length - t)
		var mid_t := (t + piece * 0.5) / length
		if absf(mid_t - gap_at) < 0.09:  # the gap people can slip through
			t += 1.4
			continue
		var ph := h * rng.randf_range(0.45, 1.05)
		var c := a + dir * (t + piece * 0.5)
		_box_mesh(st, Vector3(c.x, ground + ph * 0.5 - 0.2, c.y), Vector3(piece - 0.05, ph + 0.4, 0.7), yaw)
		_box_shape(body, c, Vector3(piece, ph + 0.4, 0.7), ground + ph * 0.5 - 0.2, yaw)
		t += piece
	for k in 3:  # fallen stones
		var f := a + along * rng.randf() + side * rng.randf_range(-1.6, 1.6)
		var s := rng.randf_range(0.35, 0.6)
		_box_mesh(st, Vector3(f.x, ground + s * 0.4, f.y), Vector3(s * 1.4, s, s), rng.randf() * TAU)


static func _boulder(st: SurfaceTool, body: StaticBody3D, at: Vector2, size: float, ground: float, noise: FastNoiseLite, rng: RandomNumberGenerator) -> void:
	var rings := 7
	var segs := 12
	var squash := rng.randf_range(0.65, 0.85)
	var pts: Array = []
	for i in rings + 1:
		var lat := PI * float(i) / float(rings) - PI * 0.5
		var row: Array[Vector3] = []
		for j in segs:
			var lon := TAU * float(j) / float(segs)
			var d := Vector3(cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon))
			var r := size * (1.0 + 0.28 * noise.get_noise_3d(d.x * 2.0 + at.x, d.y * 2.0, d.z * 2.0 + at.y))
			row.append(Vector3(at.x + d.x * r, ground + size * 0.35 + d.y * r * squash, at.y + d.z * r))
		pts.append(row)
	for i in rings:
		for j in segs:
			var j2 := (j + 1) % segs
			_quad(st, pts[i][j], pts[i][j2], pts[i + 1][j2], pts[i + 1][j], Vector3(at.x, ground + size * 0.35, at.y))
	var hull := PackedVector3Array()  # the rock's own shape (convex), not a ball taller than the squashed stone
	for row: Array in pts:
		for p3: Vector3 in row:
			hull.append(p3)
	var convex := ConvexPolygonShape3D.new()
	convex.points = hull
	var shape := CollisionShape3D.new()
	shape.shape = convex
	body.add_child(shape)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Variant) -> void:
	_tri(st, a, b, c, centre)
	_tri(st, a, c, d, centre)


# One faceted triangle lit from outside: its normal points away from `centre` (a point, or a Callable giving the
# inside point for a spot), and it is wound so its front faces out.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Variant) -> void:
	var mid := (a + b + c) / 3.0
	var inside: Vector3 = (centre as Callable).call(mid) if centre is Callable else centre
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-10:
		return
	n = n.normalized()
	var out := n.dot(mid - inside) >= 0.0
	if not out:
		n = -n
	var order := [a, c, b] if out else [a, b, c]  # Godot's front faces are clockwise seen from outside
	for p: Vector3 in order:
		st.set_color(_tone(p))
		st.set_normal(n)
		st.add_vertex(p)


static var colour := Color(0.5, 0.47, 0.42)  # set per kind while building


# The rock's colour at a point: a little darker low down and in streaks.
static func _tone(p: Vector3) -> Color:
	var streak := 0.92 + 0.08 * sin(p.x * 1.7 + p.z * 1.1) * sin(p.y * 2.3)
	var low := clampf(0.82 + p.y * 0.05, 0.82, 1.0)
	return Color(colour.r * streak * low, colour.g * streak * low, colour.b * streak * low)


static func _box_mesh(st: SurfaceTool, c: Vector3, size: Vector3, yaw: float) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var hx := size.x * 0.5
	var hy := size.y * 0.5
	var hz := size.z * 0.5
	# local: x across, z along (the yaw turns +z toward the wall's direction)
	var p := func(x: float, y: float, z: float) -> Vector3: return c + basis * Vector3(x, y, z)
	var v := [p.call(-hz, -hy, -hx), p.call(hz, -hy, -hx), p.call(hz, hy, -hx), p.call(-hz, hy, -hx),
		p.call(-hz, -hy, hx), p.call(hz, -hy, hx), p.call(hz, hy, hx), p.call(-hz, hy, hx)]
	for f: Array in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		_quad(st, v[f[0]], v[f[1]], v[f[2]], v[f[3]], c)


static func _box_shape(body: StaticBody3D, c: Vector2, size: Vector3, y: float, yaw: float) -> void:
	var box := BoxShape3D.new()
	box.size = Vector3(size.z, size.y, size.x)  # x across, z along
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.position = Vector3(c.x, y, c.y)
	shape.rotation.y = yaw
	body.add_child(shape)
