# Purpose: (polish1 D4c) the treetop village as things in the world (core/treetop_rules.gd): plank ring decks round
# the giant trees' trunks and platforms on stilts (with an open thatched hut), railings with openings where a way
# meets a deck, and the WAYS: rope ladders (rolled up until bought), rope bridges (only their ropes until bought),
# lifts (a basket in a frame of posts, ridden up / down once bought). The fixed parts of every village are merged
# into one mesh per material; each way has its own small "bought" / "not bought" meshes. Colliders are plain boxes,
# cylinders and convex deck pieces (nothing to wedge in); a rope across an opening stops falls until its way is bought.
# Dependencies: core/treetop_rules.gd, game/surface_library.gd (painting_post wood, fx_thatch).
extends Node3D

const TreetopRules = preload("res://core/treetop_rules.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")

const SEGMENTS := 16  # a ring deck's pieces
const THICK := 0.25  # deck planks
const RAIL_H := 1.05
const SEEN := 170.0  # a way's own meshes are drawn this near

var rules: TreetopRules
var _wood: Material
var _rope: StandardMaterial3D
var _thatch: Material
var _body: StaticBody3D
var _looks: Array = []  # per way: [bought Node3D, not bought Node3D, barrier CollisionShape3D or null, walk shapes (bridge) Array]
var _baskets: Array = []  # per way: the lift's basket (Node3D) or null


func setup(config: Dictionary, land: RefCounted) -> void:
	rules = TreetopRules.new(config, land)
	_wood = SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
	_thatch = SurfaceLibrary.material("fx_thatch", Color(0.72, 0.62, 0.36))
	_rope = StandardMaterial3D.new()
	_rope.albedo_color = Color(0.62, 0.52, 0.34)
	_rope.roughness = 0.95
	_body = StaticBody3D.new()
	_body.name = "TreetopBody"
	add_child(_body)
	var wood_st := SurfaceTool.new()
	wood_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var roof_st := SurfaceTool.new()
	roof_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for deck: Dictionary in rules.decks:
		if deck["kind"] == "ring":
			_ring_deck(wood_st, deck)
		else:
			_stilt_deck(wood_st, roof_st, deck, land)
	for pair: Array in [[wood_st, _wood], [roof_st, _thatch]]:
		var mi := MeshInstance3D.new()
		mi.mesh = (pair[0] as SurfaceTool).commit()
		mi.material_override = pair[1]
		add_child(mi)
	for i in rules.ways.size():
		_build_way(i)
		show_way(i)


# --- decks ---

func _ring_deck(st: SurfaceTool, deck: Dictionary) -> void:
	var at: Vector2 = deck["at"]
	var y := float(deck["y"])
	var r_in := float(deck["inner"])
	var r_out := float(deck["outer"])
	for k in SEGMENTS:
		var a0 := TAU * float(k) / float(SEGMENTS)
		var a1 := TAU * float(k + 1) / float(SEGMENTS)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var pts := PackedVector3Array()
		for r: float in [r_in, r_out]:
			for d: Vector2 in [d0, d1]:
				for h: float in [y, y - THICK]:
					pts.append(Vector3(at.x + d.x * r, h, at.y + d.y * r))
		_hull_mesh(st, pts)
		_shape(ConvexPolygonShape3D.new(), Transform3D.IDENTITY, pts)
		# the railing on the outer edge, left open where a way meets the deck
		var p0 := at + d0 * (r_out - 0.06)
		var p1 := at + d1 * (r_out - 0.06)
		if not _near_gap(deck, (p0 + p1) * 0.5, 1.4):
			_rail(st, p0, p1, y)
		else:
			_post(st, p0, y)
	for k in 8:  # brackets under the deck from the trunk (looks only)
		var a := TAU * (float(k) + 0.5) / 8.0
		var d := Vector2(cos(a), sin(a))
		var from := Vector3(at.x + d.x * r_in * 0.9, y - 1.8, at.y + d.y * r_in * 0.9)
		var to := Vector3(at.x + d.x * (r_out - 0.4), y - THICK, at.y + d.y * (r_out - 0.4))
		_beam(st, from, to, 0.16)


func _stilt_deck(st: SurfaceTool, roof: SurfaceTool, deck: Dictionary, land: RefCounted) -> void:
	var at: Vector2 = deck["at"]
	var half: Vector2 = deck["outer"]
	var y := float(deck["y"])
	var c := Vector3(at.x, y - THICK * 0.5, at.y)
	_box(st, c, Vector3(half.x * 2.0, THICK, half.y * 2.0), Basis.IDENTITY)
	var shape := BoxShape3D.new()
	shape.size = Vector3(half.x * 2.0, THICK, half.y * 2.0)
	_shape(shape, Transform3D(Basis.IDENTITY, c))
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:  # stilts
		var p := at + corner * (half - Vector2(0.45, 0.45))
		var ground := float(land.call("height_at", p.x, p.y)) - 0.3
		_pole(st, Vector3(p.x, ground, p.y), y - THICK, 0.24, true)
	for side in 4:  # cross braces between the stilts (looks only, high enough to walk under)
		var c0 := at + _corner(side) * (half - Vector2(0.45, 0.45))
		var c1 := at + _corner(side + 1) * (half - Vector2(0.45, 0.45))
		_beam(st, Vector3(c0.x, y - 3.2, c0.y), Vector3(c1.x, y - 0.6, c1.y), 0.1)
	for side in 4:  # railings in 1 m pieces, open where a way meets the deck
		var c0 := at + _corner(side) * (half - Vector2(0.06, 0.06))
		var c1 := at + _corner(side + 1) * (half - Vector2(0.06, 0.06))
		var n := maxi(1, roundi(c0.distance_to(c1)))
		for k in n:
			var p0 := c0.lerp(c1, float(k) / float(n))
			var p1 := c0.lerp(c1, float(k + 1) / float(n))
			if not _near_gap(deck, (p0 + p1) * 0.5, TreetopRules.RAIL_GAP + 0.1):
				_rail(st, p0, p1, y)
	if bool(deck["hut"]):  # an open hut: four corner posts and a thatched roof (room for a buy later)
		var hh := half - Vector2(1.3, 1.3)
		for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			var p := at + corner * hh
			_pole(st, Vector3(p.x, y, p.y), y + 2.5, 0.13, true)
		var apex := Vector3(at.x, y + 3.9, at.y)
		var eaves: Array[Vector3] = []
		for side in 4:
			var p := at + _corner(side) * (hh + Vector2(0.7, 0.7))
			eaves.append(Vector3(p.x, y + 2.35, p.y))
		for side in 4:
			_tri_out(roof, eaves[side], eaves[(side + 1) % 4], apex, Vector3(at.x, y, at.y))
			_tri_out(roof, eaves[(side + 1) % 4], eaves[side], apex, Vector3(at.x, y + 10.0, at.y))  # its underside


func _corner(side: int) -> Vector2:
	return [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)][side % 4]


func _near_gap(deck: Dictionary, p: Vector2, within: float) -> bool:
	for g: Vector2 in deck["gaps"]:
		if g.distance_to(p) < within:
			return true
	return false


# --- ways ---

func _build_way(i: int) -> void:
	var w: Dictionary = rules.ways[i]
	var bought := Node3D.new()
	var shut := Node3D.new()
	add_child(bought)
	add_child(shut)
	var barrier: CollisionShape3D = null
	var walk: Array = []
	_baskets.append(null)
	match String(w["kind"]):
		"ladder":
			_ladder(bought, shut, w)
			barrier = _barrier_at(Vector2((w["top"] as Vector3).x, (w["top"] as Vector3).z) + (w["face"] as Vector2) * TreetopRules.LADDER_OUT, w["face"], float((w["top"] as Vector3).y))
		"bridge":
			walk = _bridge(bought, shut, w)
			var a: Vector3 = w["a"]
			var b: Vector3 = w["b"]
			var dir := Vector2(b.x - a.x, b.z - a.z).normalized()
			barrier = _barrier_at(Vector2(a.x, a.z), -dir, a.y)
			var barrier2 := _barrier_at(Vector2(b.x, b.z), dir, b.y)
			walk.append(barrier2)  # (a second barrier: toggled with the first, see show_way)
		"lift":
			_lift(bought, shut, w, i)  # (no opening in the railing: the rider is set down on the deck)
	_looks.append([bought, shut, barrier, walk])


# Draws a way bought or not, and turns its walking surfaces / barriers on or off to match.
func show_way(i: int) -> void:
	var open := rules.is_open(i)
	var look: Array = _looks[i]
	(look[0] as Node3D).visible = open
	(look[1] as Node3D).visible = not open
	if look[2] != null:
		(look[2] as CollisionShape3D).set_deferred("disabled", open)
	for s: Variant in look[3]:
		var shape := s as CollisionShape3D
		var is_barrier := shape.has_meta("barrier")
		shape.set_deferred("disabled", open if is_barrier else not open)


# A rope across a deck's opening (stops a fall until the way is bought): `face` points from the opening into the deck.
func _barrier_at(p: Vector2, face: Vector2, y: float) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = Vector3(TreetopRules.RAIL_GAP * 2.2, RAIL_H, 0.12)
	var turn := Basis(Vector3.UP, atan2(face.x, face.y))
	var cs := _shape(box, Transform3D(turn, Vector3(p.x, y + RAIL_H * 0.5, p.y) + Vector3(face.x, 0, face.y) * 0.1))
	cs.set_meta("barrier", true)
	return cs


func _ladder(bought: Node3D, shut: Node3D, w: Dictionary) -> void:
	var foot: Vector3 = w["foot"]
	var top: Vector3 = w["top"]
	var face: Vector2 = w["face"]
	var across := Vector3(-face.y, 0, face.x)
	var st := _begin()
	for s: float in [-0.3, 0.3]:
		_beam(st, foot + across * s + Vector3(0, 0.05, 0), top + across * s + Vector3(0, 0.9, 0), 0.035)
	var y := foot.y + 0.3
	while y < top.y + 0.6:
		_beam(st, Vector3(foot.x, y, foot.z) - across * 0.32, Vector3(foot.x, y, foot.z) + across * 0.32, 0.04)
		y += 0.33
	_end(st, _wood, bought)
	var rolled := _begin()  # rolled up under the deck's edge, a short end hanging, a sign
	_beam(rolled, top - across * 0.4 + Vector3(0, 0.3, 0), top + across * 0.4 + Vector3(0, 0.3, 0), 0.22)
	for s: float in [-0.3, 0.3]:
		_beam(rolled, top + across * s + Vector3(0, 0.3, 0), top + across * s - Vector3(0, 1.4, 0), 0.03)
	_end(rolled, _rope, shut)
	_sign(shut, w, foot, face)


# A rope bridge from a to b: planks and rope rails, sagging a little. Returns its walk / rail shapes (on when bought).
func _bridge(bought: Node3D, shut: Node3D, w: Dictionary) -> Array:
	var a: Vector3 = w["a"]
	var b: Vector3 = w["b"]
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var length := flat.length()
	var dir := Vector3(flat.x, 0, flat.y) / length
	var across := Vector3(-dir.z, 0, dir.x)
	var sag := length * 0.03
	var n := maxi(2, ceili(length / 1.2))
	var at := func(t: float) -> Vector3: return a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
	var planks := _begin()
	var ropes := _begin()
	var shapes: Array = []
	for k in n:
		var p0: Vector3 = at.call(float(k) / float(n))
		var p1: Vector3 = at.call(float(k + 1) / float(n))
		var mid := (p0 + p1) * 0.5
		var seg := p1 - p0
		var turn := Basis.looking_at(seg.normalized(), Vector3.UP)
		_box(planks, mid - Vector3(0, 0.05, 0), Vector3(1.5, 0.08, seg.length() * 0.92), turn)
		var walk := BoxShape3D.new()
		walk.size = Vector3(1.6, 0.2, seg.length() + 0.08)
		shapes.append(_shape(walk, Transform3D(turn, mid - Vector3(0, 0.1, 0))))
		for s: float in [-0.8, 0.8]:
			var rail := BoxShape3D.new()
			rail.size = Vector3(0.1, RAIL_H, seg.length() + 0.05)
			shapes.append(_shape(rail, Transform3D(turn, mid + across * s + Vector3(0, RAIL_H * 0.5, 0))))
			_beam(ropes, p0 + across * s + Vector3(0, 1.0, 0), p1 + across * s + Vector3(0, 1.0, 0), 0.035)
			if k % 2 == 0:
				_beam(ropes, p0 + across * s, p0 + across * s + Vector3(0, 1.0, 0), 0.03)
	_end(planks, _wood, bought)
	_end(ropes, _rope, bought)
	var loose := _begin()  # not bought: two ropes across, slack
	for s: float in [-0.8, 0.8]:
		for k in n:
			var p0: Vector3 = at.call(float(k) / float(n)) - Vector3(0, sag * 2.0 * sin(PI * float(k) / float(n)), 0)
			var p1: Vector3 = at.call(float(k + 1) / float(n)) - Vector3(0, sag * 2.0 * sin(PI * float(k + 1) / float(n)), 0)
			_beam(loose, p0 + across * s + Vector3(0, 0.9, 0), p1 + across * s + Vector3(0, 0.9, 0), 0.03)
	_end(loose, _rope, shut)
	_sign(shut, w, Vector3((w["ends"][0] as Vector3).x, a.y, (w["ends"][0] as Vector3).z), Vector2(dir.x, dir.z))
	return shapes


func _lift(bought: Node3D, shut: Node3D, w: Dictionary, i: int) -> void:
	var foot: Vector3 = w["foot"]
	var top: Vector3 = w["top"]
	var face: Vector2 = w["face"]
	var frame := _begin()
	var across := Vector3(-face.y, 0, face.x)
	var fwd := Vector3(face.x, 0, face.y)
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var p := foot + across * corner.x * 0.85 + fwd * corner.y * 0.85
		_pole(frame, Vector3(p.x, foot.y - 0.3, p.z), top.y + 2.4, 0.11, true)
	_beam(frame, top + across * 1.0 + Vector3(0, 2.4, 0), top - across * 1.0 + Vector3(0, 2.4, 0), 0.14)  # the head beam ...
	_beam(frame, top + fwd * 1.2 + Vector3(0, 2.4, 0), top + Vector3(0, 2.4, 0), 0.12)  # ... tied back to the deck
	_beam(frame, top + fwd * 0.55 + Vector3(0, -0.02, 0), top + fwd * 0.55 + Vector3(0, -THICK, 0), 0.55)  # a landing plank to the deck (looks)
	var mi := _end(frame, _wood, self)
	mi.visibility_range_end = SEEN
	var basket := Node3D.new()
	basket.position = foot
	add_child(basket)
	var bst := _begin()
	_box(bst, Vector3(0, 0.05, 0), Vector3(1.3, 0.1, 1.3), Basis.IDENTITY)
	for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		_beam(bst, Vector3(corner.x * 0.62, 0.0, corner.y * 0.62), Vector3(corner.x * 0.62, 1.0, corner.y * 0.62), 0.04)
	for side in 4:
		var c0 := _corner(side) * 0.62
		var c1 := _corner(side + 1) * 0.62
		_beam(bst, Vector3(c0.x, 1.0, c0.y), Vector3(c1.x, 1.0, c1.y), 0.04)
	_end(bst, _wood, basket)
	var cable := _begin()
	_beam(cable, Vector3(0, 1.0, 0), Vector3(0, top.y - foot.y + 2.4, 0), 0.03)
	_end(cable, _rope, bought).position = foot
	_baskets[i] = basket
	_sign(shut, w, Vector3((w["ends"][0] as Vector3).x, foot.y, (w["ends"][0] as Vector3).z), face)


# A small board with the price, standing at the way's low end (the session shows the real prompt).
func _sign(parent: Node3D, w: Dictionary, at: Vector3, face: Vector2) -> void:
	var st := _begin()
	var side := Vector3(-face.y, 0, face.x)
	var p := at + side * 0.9
	_pole(st, Vector3(p.x, at.y, p.z), at.y + 1.3, 0.05, false)
	_end(st, _wood, parent)
	var label := Label3D.new()
	label.text = "%s\n%d" % [{"ladder": "ROPE LADDER", "bridge": "ROPE BRIDGE", "lift": "LIFT"}[String(w["kind"])], int(w["price"])]
	label.font_size = 48
	label.pixel_size = 0.005
	label.modulate = Color(1.0, 0.93, 0.75)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = Vector3(p.x, at.y + 1.5, p.z)
	label.visibility_range_end = 40.0
	parent.add_child(label)


# Moves a lift's basket (and nothing else: the session carries the rider) to share t of the way up (0 = foot).
func set_basket(way: int, t: float) -> void:
	var basket := _baskets[way] as Node3D
	if basket == null:
		return
	var foot: Vector3 = rules.ways[way]["foot"]
	var top: Vector3 = rules.ways[way]["top"]
	basket.position = foot.lerp(top + Vector3(0, -THICK, 0), clampf(t, 0.0, 1.0))


# --- building blocks ---

func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _end(st: SurfaceTool, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.visibility_range_end = SEEN
	parent.add_child(mi)
	return mi


func _shape(shape: Shape3D, xf: Transform3D, points := PackedVector3Array()) -> CollisionShape3D:
	if shape is ConvexPolygonShape3D:
		(shape as ConvexPolygonShape3D).points = points
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	_body.add_child(cs)
	return cs


func _rail(st: SurfaceTool, p0: Vector2, p1: Vector2, y: float) -> void:
	_post(st, p0, y)
	_beam(st, Vector3(p0.x, y + RAIL_H, p0.y), Vector3(p1.x, y + RAIL_H, p1.y), 0.06)
	_beam(st, Vector3(p0.x, y + RAIL_H * 0.5, p0.y), Vector3(p1.x, y + RAIL_H * 0.5, p1.y), 0.04)
	var box := BoxShape3D.new()
	var length := p0.distance_to(p1)
	box.size = Vector3(0.12, RAIL_H, length + 0.04)
	var mid := (p0 + p1) * 0.5
	var turn := Basis(Vector3.UP, atan2(p1.x - p0.x, p1.y - p0.y))
	_shape(box, Transform3D(turn, Vector3(mid.x, y + RAIL_H * 0.5, mid.y)))


func _post(st: SurfaceTool, p: Vector2, y: float) -> void:
	_beam(st, Vector3(p.x, y, p.y), Vector3(p.x, y + RAIL_H + 0.05, p.y), 0.06)


# A round pole (8 sides) from `base` up to height `to_y`; `solid` adds its cylinder collider.
func _pole(st: SurfaceTool, base: Vector3, to_y: float, r: float, solid: bool) -> void:
	_beam(st, base, Vector3(base.x, to_y, base.z), r)
	if solid:
		var cyl := CylinderShape3D.new()
		cyl.radius = r
		cyl.height = to_y - base.y
		_shape(cyl, Transform3D(Basis.IDENTITY, Vector3(base.x, (base.y + to_y) * 0.5, base.z)))


# A thin square beam from a to b (looks only).
func _beam(st: SurfaceTool, a: Vector3, b: Vector3, r: float) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var turn := Basis.looking_at(d.normalized(), up)
	_box(st, (a + b) * 0.5, Vector3(r * 2.0, r * 2.0, d.length()), turn)


func _box(st: SurfaceTool, c: Vector3, size: Vector3, turn: Basis) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for z: float in [-h.z, h.z]:
		for y: float in [-h.y, h.y]:
			for x: float in [-h.x, h.x]:
				corners.append(c + turn * Vector3(x, y, z))
	for f: Array in [[0, 1, 3, 2], [5, 4, 6, 7], [4, 0, 2, 6], [1, 5, 7, 3], [2, 3, 7, 6], [4, 5, 1, 0]]:
		_tri_out(st, corners[f[0]], corners[f[1]], corners[f[2]], c)
		_tri_out(st, corners[f[0]], corners[f[2]], corners[f[3]], c)


func _hull_mesh(st: SurfaceTool, pts: PackedVector3Array) -> void:
	# a ring piece: pts = [in-d0-top, in-d0-bot, in-d1-top, in-d1-bot, out-d0-top, out-d0-bot, out-d1-top, out-d1-bot]
	var c := Vector3.ZERO
	for p: Vector3 in pts:
		c += p
	c /= float(pts.size())
	for f: Array in [[0, 2, 6, 4], [1, 5, 7, 3], [4, 6, 7, 5], [0, 1, 3, 2], [0, 4, 5, 1], [2, 3, 7, 6]]:
		_tri_out(st, pts[f[0]], pts[f[1]], pts[f[2]], c)
		_tri_out(st, pts[f[0]], pts[f[2]], pts[f[3]], c)


# One triangle facing away from `inside` (Godot's front faces are clockwise seen from the front).
func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var out := n.dot((a + b + c) / 3.0 - inside) >= 0.0
	if not out:
		n = -n
	for p: Vector3 in ([a, c, b] if out else [a, b, c]):
		st.set_normal(n)
		st.add_vertex(p)
