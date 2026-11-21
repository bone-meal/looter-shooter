# Purpose: (polish1 D4b) the GIANT TREES on the islands (core/archipelago.gd blocks of kind "tree", from the islands'
# `features` in data/archipelago.json): a trunk with a flared foot, low roots spreading over the sand, five or six
# great limbs and a crown of leaf clumps. Made in code (faceted, vertex-coloured) and merged into two meshes for all
# the trees (bark, leaves: two draw calls). Colliders are smooth on purpose (director: no getting stuck): the trunk
# is a stack of convex shells (the flare is a steep cone: a wall, nothing to wedge in), each root a low convex hump
# you walk over; limbs and leaves have none (out of reach). The navigation mesh sees the same colliders.
# Dependencies: game/surface_library.gd (fx_bark, fx_leaf: grain surfaces coloured by the mesh), core/tree_shape.gd.
extends RefCounted

const SurfaceLibrary = preload("res://game/surface_library.gd")
const TreeShape = preload("res://core/tree_shape.gd")

const SEGS := 14  # round the trunk
const ROOTS := 7
const SECTIONS := [-0.6, 0.6, 1.8, 4.2, 9.0, 16.0, 24.0]  # the trunk's convex collider pieces (heights from the ground; short at the
# flared foot so each shell hugs the curve instead of bulging out past it)


static func build(parent: Node3D, land: RefCounted, centre: Vector3) -> void:
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	body.name = "GiantTrees"
	body.position = centre
	parent.add_child(body)
	var any := false
	for b: Dictionary in land.get("blocks"):
		if String(b["kind"]) != "tree":
			continue
		any = true
		var at: Vector2 = b["a"]
		_tree(bark, leaves, body, at, float(land.call("height_at", at.x, at.y)), float(b["height"]), float(b["girth"]), TreeShape.seed_of(at))
	if not any:
		return
	for pair: Array in [[bark, "fx_bark"], [leaves, "fx_leaf"]]:
		var n := MeshInstance3D.new()
		n.mesh = (pair[0] as SurfaceTool).commit()
		n.position = centre
		var m := SurfaceLibrary.material(String(pair[1]), Color.WHITE)
		m.vertex_color_use_as_albedo = true
		n.material_override = m
		parent.add_child(n)


# How wide the trunk is at height y (from the ground) for a tree of this height and girth (radius).
static func radius_at(y: float, height: float, girth: float) -> float:
	return TreeShape.radius_at(y, height, girth)


static func _tree(bark: SurfaceTool, leaves: SurfaceTool, body: StaticBody3D, at: Vector2, ground: float, height: float, girth: float, seed_n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var noise := FastNoiseLite.new()
	noise.seed = seed_n
	noise.frequency = 0.35
	var top := height * TreeShape.TOP_SHARE
	# the trunk: rings up to the crown, bulged by noise, leaning a little
	var rings: Array = []
	var heights: Array[float] = []
	var y := float(SECTIONS[0])
	while y < top:
		heights.append(y)
		y += 0.6 if y < 3.0 else 1.6
	heights.append(top)
	var lean := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized() * rng.randf_range(0.4, 1.2)
	for h: float in heights:
		var axis := at + lean * pow(maxf(h, 0.0) / top, 2.0)
		var r := radius_at(h, height, girth)
		var ring: Array[Vector3] = []
		for j in SEGS:
			var a := TAU * float(j) / float(SEGS)
			var d := Vector2(cos(a), sin(a))
			var bump := 1.0 + 0.1 * noise.get_noise_3d(d.x * 3.0, h * 0.5, d.y * 3.0) + (0.12 * exp(-maxf(h, 0.0) / 1.2) if j % 2 == 0 else 0.0)  # buttress ribs low down
			ring.append(Vector3(axis.x + d.x * r * bump, ground + h, axis.y + d.y * r * bump))
		rings.append(ring)
	var axis_at := func(p: Vector3) -> Vector3:
		var t := clampf((p.y - ground) / top, 0.0, 1.0)
		var ax := at + lean * t * t
		return Vector3(ax.x, p.y, ax.y)
	for i in rings.size() - 1:
		for j in SEGS:
			var j2 := (j + 1) % SEGS
			_quad(bark, rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j], axis_at, _bark_tone)
	# trunk colliders: one convex shell per section (each a frustum: smooth sides, no lip)
	for s in SECTIONS.size() - 1:
		var lo := float(SECTIONS[s])
		var hi := minf(float(SECTIONS[s + 1]), top)
		if lo >= top:
			break
		var hull := PackedVector3Array()
		for i in rings.size():
			var inside_band := heights[i] >= lo - 0.01 and heights[i] <= hi + 0.01
			var first_above := heights[i] > hi + 0.01 and i > 0 and heights[i - 1] <= hi + 0.01
			if inside_band or first_above:
				for p: Vector3 in rings[i]:
					hull.append(p)
		_shell(body, hull)
	# roots: low humps from the flare out over the ground, each a convex collider you walk over
	var core := radius_at(0.0, height, girth)
	for k in ROOTS:
		var a := TAU * (float(k) + rng.randf_range(-0.25, 0.25)) / float(ROOTS)
		var d := Vector2(cos(a), sin(a))
		var side := Vector2(-d.y, d.x)
		var reach := rng.randf_range(3.2, 4.6)
		var bend := rng.randf_range(-0.35, 0.35)
		var pts: Array[Vector2] = []
		for n in 4:
			var t := float(n) / 3.0
			pts.append(at + d * (core * 0.7 + reach * t) + side * bend * t * t * reach)
		for n in 3:
			var w0 := lerpf(0.75, 0.3, float(n) / 3.0)
			var w1 := lerpf(0.75, 0.3, float(n + 1) / 3.0)
			var h0 := lerpf(0.5, 0.14, float(n) / 3.0)
			var h1 := lerpf(0.5, 0.14, float(n + 1) / 3.0)
			if n == 0:
				h0 = 0.9  # it rises into the flare
			_root_piece(bark, body, pts[n], pts[n + 1], w0, w1, h0, h1, ground)
	# limbs and the crown: long limbs spread wide like a great rain-forest tree (room for platforms later), each with a
	# fork; leaf clumps along them and at the tips, a few on top
	var limb_n := rng.randi_range(6, 7)
	var trunk_top := Vector3(at.x + lean.x, ground + top, at.y + lean.y)
	for k in limb_n:
		var a := TAU * (float(k) + rng.randf_range(-0.2, 0.2)) / float(limb_n)
		var start_y := height * rng.randf_range(0.45, 0.68)
		var t0 := start_y / top
		var base := Vector3(at.x + lean.x * t0 * t0, ground + start_y, at.y + lean.y * t0 * t0)
		var pitch := rng.randf_range(0.22, 0.55)
		var length := rng.randf_range(10.0, 15.0)
		var dir := Vector3(cos(a) * cos(pitch), sin(pitch), sin(a) * cos(pitch))
		var tip := base + dir * length
		_limb(bark, base, tip, girth * 0.5, girth * 0.15)
		var fork_at := base.lerp(tip, 0.6) + Vector3(0, 0.36, 0)
		var fa := a + (0.65 if rng.randf() < 0.5 else -0.65)
		var fork_tip := fork_at + Vector3(cos(fa), rng.randf_range(0.3, 0.6), sin(fa)) * rng.randf_range(5.0, 7.0)
		_limb(bark, fork_at, fork_tip, girth * 0.22, girth * 0.1)
		_clump(leaves, base.lerp(tip, 0.55) + Vector3(0, 1.8, 0), rng.randf_range(3.4, 4.4), rng)
		_clump(leaves, fork_tip + Vector3(0, 0.8, 0), rng.randf_range(3.6, 4.8), rng)
		for c in rng.randi_range(2, 3):
			var off := Vector3(rng.randf_range(-2.2, 2.2), rng.randf_range(0.2, 1.6), rng.randf_range(-2.2, 2.2))
			_clump(leaves, tip + off, rng.randf_range(4.0, 5.6), rng)
	for c in 3:
		var off := Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(1.5, 3.5), rng.randf_range(-3.0, 3.0))
		_clump(leaves, trunk_top + off, rng.randf_range(5.0, 6.4), rng)


# One root piece from a to b (plan), a hump with a ridge of height h and a foot of half width w at each end.
static func _root_piece(st: SurfaceTool, body: StaticBody3D, a: Vector2, b: Vector2, w0: float, w1: float, h0: float, h1: float, ground: float) -> void:
	var d := (b - a).normalized()
	var s := Vector2(-d.y, d.x)
	var foot := -0.15
	var pa := [Vector3(a.x + s.x * w0, ground + foot, a.y + s.y * w0), Vector3(a.x, ground + h0, a.y), Vector3(a.x - s.x * w0, ground + foot, a.y - s.y * w0)]
	var pb := [Vector3(b.x + s.x * w1, ground + foot, b.y + s.y * w1), Vector3(b.x, ground + h1, b.y), Vector3(b.x - s.x * w1, ground + foot, b.y - s.y * w1)]
	var inside := func(p: Vector3) -> Vector3:
		var t := clampf((Vector2(p.x, p.z) - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		var q := a.lerp(b, t)
		return Vector3(q.x, ground - 0.5, q.y)
	_quad(st, pa[0], pb[0], pb[1], pa[1], inside, _bark_tone)
	_quad(st, pa[1], pb[1], pb[2], pa[2], inside, _bark_tone)
	_tri(st, pb[0], pb[1], pb[2], inside, _bark_tone)  # the far end (the near end is inside the flare)
	var hull := PackedVector3Array()
	for p: Vector3 in pa + pb:
		hull.append(p)
	_shell(body, hull)


# A tapering limb (6-sided) from base to tip.
static func _limb(st: SurfaceTool, base: Vector3, tip: Vector3, r0: float, r1: float) -> void:
	var axis := (tip - base).normalized()
	var u := axis.cross(Vector3.UP).normalized()
	if u.length_squared() < 0.01:
		u = Vector3.RIGHT
	var v := axis.cross(u).normalized()
	var steps := 4
	var rings: Array = []
	for i in steps + 1:
		var t := float(i) / float(steps)
		var c := base.lerp(tip, t) + Vector3(0, sin(t * PI) * 0.6, 0)  # a little arch
		var r := lerpf(r0, r1, t)
		var ring: Array[Vector3] = []
		for j in 6:
			var a := TAU * float(j) / 6.0
			ring.append(c + (u * cos(a) + v * sin(a)) * r)
		rings.append(ring)
	var inside := func(p: Vector3) -> Vector3:
		var t := clampf((p - base).dot(tip - base) / (tip - base).length_squared(), 0.0, 1.0)
		return base.lerp(tip, t) + Vector3(0, sin(t * PI) * 0.6, 0)
	for i in steps:
		for j in 6:
			var j2 := (j + 1) % 6
			_quad(st, rings[i][j], rings[i][j2], rings[i + 1][j2], rings[i + 1][j], inside, _bark_tone)


# A leaf clump: a squashed, lumpy icosahedron (subdivided once), darker underneath.
static func _clump(st: SurfaceTool, c: Vector3, r: float, rng: RandomNumberGenerator) -> void:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var faces := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	var squash := rng.randf_range(0.55, 0.7)
	var shade := rng.randf_range(0.85, 1.1)
	var place := func(p: Vector3) -> Vector3:
		var n := p.normalized()
		var lump := 1.0 + rng.randf_range(-0.14, 0.14)
		return c + Vector3(n.x * r * lump, n.y * r * squash * lump, n.z * r * lump)
	var tone := func(p: Vector3) -> Color:
		var under := clampf(0.62 + 0.5 * (p.y - c.y + r * 0.3) / (r * squash), 0.6, 1.08)
		return Color(0.2, 0.4, 0.15) * under * shade
	var cache := {}
	for f: Array in faces:
		var a: Vector3 = v[f[0]]
		var b: Vector3 = v[f[1]]
		var d: Vector3 = v[f[2]]
		var ab := (a + b) * 0.5
		var bd := (b + d) * 0.5
		var da := (d + a) * 0.5
		var pts: Array[Vector3] = []
		for p: Vector3 in [a, b, d, ab, bd, da]:
			var key := p.normalized().snapped(Vector3(0.001, 0.001, 0.001))
			if not cache.has(key):
				cache[key] = place.call(p)
			pts.append(cache[key])
		for tri: Array in [[0, 3, 5], [3, 1, 4], [5, 4, 2], [3, 4, 5]]:
			_tri(st, pts[tri[0]], pts[tri[1]], pts[tri[2]], c, tone)


static func _shell(body: StaticBody3D, points: PackedVector3Array) -> void:
	if points.size() < 4:
		return
	var convex := ConvexPolygonShape3D.new()
	convex.points = points
	var shape := CollisionShape3D.new()
	shape.shape = convex
	body.add_child(shape)


static func _bark_tone(p: Vector3) -> Color:
	var streak := 0.9 + 0.1 * sin(p.x * 3.1 + p.z * 2.3 + p.y * 0.7)
	var moss := clampf(1.0 - p.y * 0.6, 0.0, 1.0) * 0.25  # greener at the ground
	return Color(0.4 * streak * (1.0 - moss * 0.5), 0.31 * streak * (1.0 + moss * 0.6), 0.23 * streak * (1.0 - moss * 0.3))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, centre: Variant, tone: Callable) -> void:
	_tri(st, a, b, c, centre, tone)
	_tri(st, a, c, d, centre, tone)


# One faceted triangle, its front facing away from `centre` (a point, or a Callable giving the inside point).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, centre: Variant, tone: Callable) -> void:
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
		st.set_color(tone.call(p))
		st.set_normal(n)
		st.add_vertex(p)
