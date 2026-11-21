# Purpose: (polish1 D4c part 2) the OFFSHORE COMPLEX in the middle sea as things in the world (data/treetops.json
# `offshore`, worked out by core/treetop_rules.gd): steel decks on legs to the sea bed or on columns over a lower deck,
# yellow railings with openings, free stairs and catwalk links, the props that fill it (containers, tanks, pipe racks,
# pumps, a derrick, cranes, the quarters block, lifeboats, the helipad, a flare boom with its flame, lamps), and the
# bought CATWALKS on pylons from the villages' top rings (only end stubs and the pylons until bought, a rope barrier
# across both openings). Every fixed part is one vertex-coloured mesh (one draw call) plus a few glowing ones.
# Colliders: boxes and cylinders only, stairs a smooth ramp (nothing to wedge in).
# Dependencies: core/treetop_rules.gd (given), game/surface_library.gd (fx_metal grain surface).
extends Node3D

const SurfaceLibrary = preload("res://game/surface_library.gd")

const STEEL := Color(0.46, 0.49, 0.52)
const DARK := Color(0.28, 0.3, 0.32)
const YELLOW := Color(0.92, 0.72, 0.12)
const WHITE := Color(0.92, 0.92, 0.9)
const ORANGE := Color(0.95, 0.45, 0.1)
const RAIL_H := 1.05
const RAIL_GAP := 1.0
const PLATE := 0.4  # deck plate thickness

var rules: RefCounted
var _body: StaticBody3D
var _metal: Material
var _glow: Dictionary = {}  # name -> StandardMaterial3D (emissive)
var _looks: Dictionary = {}  # way index -> [bought Node3D, not bought Node3D, shapes Array (walk + rails), barriers Array]
var _flames: Array[Node3D] = []
var _clock := 0.0


func setup(tops: RefCounted, land: RefCounted) -> void:
	rules = tops
	var m := SurfaceLibrary.material("fx_metal", Color.WHITE)
	m.vertex_color_use_as_albedo = true
	_metal = m
	for pair: Array in [["window", Color(1.0, 0.85, 0.55), 1.6], ["lamp", Color(1.0, 0.96, 0.85), 2.5], ["beacon", Color(1.0, 0.15, 0.1), 3.0], ["flame", Color(1.0, 0.55, 0.15), 4.0]]:
		var g := StandardMaterial3D.new()
		g.albedo_color = pair[1]
		g.emission_enabled = true
		g.emission = pair[1]
		g.emission_energy_multiplier = float(pair[2])
		g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow[pair[0]] = g
	_body = StaticBody3D.new()
	_body.name = "OffshoreBody"
	add_child(_body)
	var st := _begin()
	var glows: Dictionary = {}
	for k: String in _glow:
		glows[k] = _begin()
	for deck: Dictionary in rules.get("decks"):
		if deck["kind"] == "rig":
			_deck(st, deck, land)
	for w: Dictionary in rules.get("ways"):
		if w["kind"] == "stairs":
			_stairs(st, w)
		elif w["kind"] == "link":
			_walkway(st, w["a"], w["b"], [], true)
	var off: Dictionary = rules.get("cfg").get("offshore", {})
	for p: Dictionary in off.get("props", []):
		_prop(st, glows, p)
	_end(st, _metal, self)
	for k: String in glows:
		_end(glows[k], _glow[k], self)
	var ways: Array = rules.get("ways")
	for i in ways.size():
		if ways[i]["kind"] == "catwalk":
			_catwalk(i, ways[i], land)
			show_way(i)


func handles(way: int) -> bool:
	return _looks.has(way)


func show_way(way: int) -> void:
	if not _looks.has(way):
		return
	var open := bool(rules.call("is_open", way))
	var look: Array = _looks[way]
	(look[0] as Node3D).visible = open
	(look[1] as Node3D).visible = not open
	for s: Variant in look[2]:
		(s as CollisionShape3D).set_deferred("disabled", not open)
	for s: Variant in look[3]:
		(s as CollisionShape3D).set_deferred("disabled", open)


func _process(delta: float) -> void:
	_clock += delta
	for i in _flames.size():  # the flare's flame licks and sways
		var f := _flames[i]
		var lick := 1.0 + 0.18 * sin(_clock * 9.0 + float(i)) + 0.1 * sin(_clock * 23.0)
		f.scale = Vector3(1.0 + 0.1 * sin(_clock * 13.0), lick, 1.0 + 0.1 * cos(_clock * 11.0))


# --- decks ---

func _deck(st: SurfaceTool, deck: Dictionary, land: RefCounted) -> void:
	var at: Vector2 = deck["at"]
	var half: Vector2 = deck["outer"]
	var y := float(deck["y"])
	var c := Vector3(at.x, y - PLATE * 0.5, at.y)
	_box(st, c, Vector3(half.x * 2.0, PLATE, half.y * 2.0), Basis.IDENTITY, DARK)
	_solid_box(c, Vector3(half.x * 2.0, PLATE, half.y * 2.0), Basis.IDENTITY)
	for side in 4:  # a steel edge beam round the plate (looks)
		var c0 := at + _corner(side) * half
		var c1 := at + _corner(side + 1) * half
		_beam(st, Vector3(c0.x, y - PLATE - 0.35, c0.y), Vector3(c1.x, y - PLATE - 0.35, c1.y), 0.3, STEEL)
	for side in 4:  # railings in 1.5 m pieces, open where a stair, link or catwalk meets the deck
		var c0 := at + _corner(side) * (half - Vector2(0.08, 0.08))
		var c1 := at + _corner(side + 1) * (half - Vector2(0.08, 0.08))
		var n := maxi(1, roundi(c0.distance_to(c1) / 1.5))
		for k in n:
			var p0 := c0.lerp(c1, float(k) / float(n))
			var p1 := c0.lerp(c1, float(k + 1) / float(n))
			if not _near_gap(deck, (p0 + p1) * 0.5, RAIL_GAP + 0.6):
				_rail(st, p0, p1, y)
	var supports: Array[Vector2] = []
	var inset := 1.2 if bool(deck["legs"]) else 0.5
	var nx := maxi(1, ceili(half.x * 2.0 / 14.0))
	var nz := maxi(1, ceili(half.y * 2.0 / 14.0))
	for ix in nx + 1:
		for iz in nz + 1:
			if ix == 0 or ix == nx or iz == 0 or iz == nz:
				supports.append(at - half + Vector2(inset, inset) + Vector2((half.x * 2.0 - inset * 2.0) * float(ix) / float(nx), (half.y * 2.0 - inset * 2.0) * float(iz) / float(nz)))
	if bool(deck["legs"]):  # big legs to the sea bed with cross braces
		var bed := -12.0
		for s: Vector2 in supports:
			bed = minf(bed, float(land.call("height_at", s.x, s.y)) - 1.0)
		for s: Vector2 in supports:
			_cylinder(st, Vector3(s.x, bed, s.y), y - PLATE - bed, 0.8, 12, STEEL)
			_solid_cylinder(Vector3(s.x, bed, s.y), y - PLATE - bed, 0.8)
		for i in supports.size():
			for j in range(i + 1, supports.size()):
				var a2: Vector2 = supports[i]
				var b2: Vector2 = supports[j]
				if a2.distance_to(b2) > 15.0 or (absf(a2.x - b2.x) > 0.1 and absf(a2.y - b2.y) > 0.1):
					continue  # neighbours along a side only
				for h: float in [-1.0, 4.0]:
					_beam(st, Vector3(a2.x, h, a2.y), Vector3(b2.x, h + 4.0, b2.y), 0.16, STEEL)
					_beam(st, Vector3(b2.x, h, b2.y), Vector3(a2.x, h + 4.0, a2.y), 0.16, STEEL)
	elif int(deck["on"]) >= 0:  # columns down to the deck below
		var low: Dictionary = (rules.get("decks") as Array)[int(deck["on"])]
		for s: Vector2 in supports:
			_cylinder(st, Vector3(s.x, float(low["y"]), s.y), y - PLATE - float(low["y"]), 0.3, 10, STEEL)
			_solid_cylinder(Vector3(s.x, float(low["y"]), s.y), y - PLATE - float(low["y"]), 0.3)


func _near_gap(deck: Dictionary, p: Vector2, within: float) -> bool:
	for g: Vector2 in deck["gaps"]:
		if g.distance_to(p) < within:
			return true
	return false


func _corner(side: int) -> Vector2:
	return [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)][side % 4]


# A free stair flight: a smooth ramp (the collider) with steps drawn on it, rails both sides, a landing to the upper deck.
func _stairs(st: SurfaceTool, w: Dictionary) -> void:
	var s0: Vector3 = w["start"]
	var s1: Vector3 = w["end"]
	var join: Vector3 = w["join"]
	var width := float(w["width"])
	var flat := Vector2(s1.x - s0.x, s1.z - s0.z)
	var dir := Vector3(flat.x, 0, flat.y).normalized()
	var across := Vector3(-dir.z, 0, dir.x)
	var slope := (s1 - s0)
	var turn := Basis.looking_at(slope.normalized(), Vector3.UP)
	var normal := turn.y
	var length := slope.length()
	var thick := 0.3
	var mid := (s0 + s1) * 0.5 - normal * thick * 0.5
	var ramp := BoxShape3D.new()
	ramp.size = Vector3(width, thick, length + 0.6)
	_shape(ramp, Transform3D(turn, mid - slope.normalized() * 0.3))  # (lengthened only at the foot: under the deck, no lip on top)
	_box(st, mid, Vector3(width, thick, length), turn, STEEL)
	var steps := maxi(2, ceili((s1.y - s0.y) / 0.3))
	for k in steps:  # the treads (looks)
		var t := (float(k) + 0.5) / float(steps)
		var p := s0.lerp(s1, t)
		_box(st, p + Vector3(0, 0.04, 0), Vector3(width, 0.08, 0.32), Basis(Vector3.UP, atan2(dir.x, dir.z)), DARK)
	for side: float in [-1.0, 1.0]:
		var e := across * (width * 0.5 + 0.05) * side
		_beam(st, s0 + e + Vector3(0, RAIL_H, 0), s1 + e + Vector3(0, RAIL_H, 0), 0.05, YELLOW)
		_beam(st, s0 + e, s0 + e + Vector3(0, RAIL_H, 0), 0.05, YELLOW)
		var rail := BoxShape3D.new()
		rail.size = Vector3(0.12, RAIL_H, length)
		_shape(rail, Transform3D(turn, (s0 + s1) * 0.5 + e + normal * RAIL_H * 0.5))
	# the landing from the top of the flight to the upper deck's edge
	var a := Vector2(s1.x, s1.z)
	var b := Vector2(join.x, join.z)
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(width * 0.5, width * 0.5)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(width * 0.5, width * 0.5)
	var lc := Vector3((lo.x + hi.x) * 0.5, s1.y - PLATE * 0.5, (lo.y + hi.y) * 0.5)
	var ls := Vector3(hi.x - lo.x, PLATE, hi.y - lo.y)
	_box(st, lc, ls, Basis.IDENTITY, DARK)
	_solid_box(lc, ls, Basis.IDENTITY)


# A level steel walkway from a to b with rails both sides; `shapes` collects its colliders (for a bought catwalk).
func _walkway(st: SurfaceTool, a: Vector3, b: Vector3, shapes: Array, fixed: bool) -> void:
	var flat := Vector2(b.x - a.x, b.z - a.z)
	var length := flat.length()
	var dir := Vector3(flat.x, 0, flat.y) / length
	var across := Vector3(-dir.z, 0, dir.x)
	var turn := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var mid := (a + b) * 0.5 + Vector3(0, -PLATE * 0.5, 0)
	_box(st, mid, Vector3(1.8, PLATE * 0.6, length + 0.4), turn, DARK)
	var walk := BoxShape3D.new()
	walk.size = Vector3(1.8, PLATE, length + 0.4)
	var ws := _shape(walk, Transform3D(turn, mid))
	if not fixed:
		shapes.append(ws)
	for side: float in [-1.0, 1.0]:
		var e := across * 0.95 * side
		_beam(st, a + e + Vector3(0, RAIL_H, 0), b + e + Vector3(0, RAIL_H, 0), 0.05, YELLOW)
		_beam(st, a + e + Vector3(0, RAIL_H * 0.5, 0), b + e + Vector3(0, RAIL_H * 0.5, 0), 0.035, YELLOW)
		var n := maxi(1, ceili(length / 2.0))
		for k in n + 1:
			var p := a.lerp(b, float(k) / float(n)) + e
			_beam(st, p, p + Vector3(0, RAIL_H, 0), 0.04, YELLOW)
		var rail := BoxShape3D.new()
		rail.size = Vector3(0.12, RAIL_H, length)
		var rs := _shape(rail, Transform3D(turn, (a + b) * 0.5 + e + Vector3(0, RAIL_H * 0.5, 0)))
		if not fixed:
			shapes.append(rs)


# A bought catwalk from a village's top ring to the complex: its pylons always stand; the walkway when bought.
func _catwalk(i: int, w: Dictionary, land: RefCounted) -> void:
	var bought := Node3D.new()
	var shut := Node3D.new()
	add_child(bought)
	add_child(shut)
	var a: Vector3 = w["a"]
	var b: Vector3 = w["b"]
	var shapes: Array = []
	var st := _begin()
	_walkway(st, a, b, shapes, false)
	_end(st, _metal, bought)
	var stubs := _begin()  # not bought: a short stub at each end
	var dir := (Vector3(b.x, a.y, b.z) - a).normalized()
	_box(stubs, a + dir * 1.0 + Vector3(0, -PLATE * 0.3, 0), Vector3(1.8, PLATE * 0.6, 2.0), Basis(Vector3.UP, atan2(dir.x, dir.z)), DARK)
	_box(stubs, b - dir * 1.0 + Vector3(0, -PLATE * 0.3, 0), Vector3(1.8, PLATE * 0.6, 2.0), Basis(Vector3.UP, atan2(dir.x, dir.z)), DARK)
	_end(stubs, _metal, shut)
	var label := Label3D.new()
	label.text = "CATWALK TO THE PLATFORM\n%d" % int(w["price"])
	label.font_size = 48
	label.pixel_size = 0.005
	label.modulate = Color(1.0, 0.93, 0.75)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.position = a + Vector3(0, 2.0, 0) - dir * 1.0
	label.visibility_range_end = 40.0
	shut.add_child(label)
	var pst := _begin()  # pylons: a lattice tower each, from the sea bed (or the ground) to under the walkway
	for p: Vector2 in w["pylons"]:
		var ground := float(land.call("height_at", p.x, p.y))
		var foot := minf(ground, float(land.get("sea_level")) - 1.0) - 2.0 if ground < float(land.get("sea_level")) else ground - 0.2
		var t := Vector2(p.x - a.x, p.y - a.z).length() / Vector2(b.x - a.x, b.z - a.z).length()
		var top := lerpf(a.y, b.y, t) - PLATE
		for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_beam(pst, Vector3(p.x + corner.x * 0.9, foot, p.y + corner.y * 0.9), Vector3(p.x + corner.x * 0.6, top, p.y + corner.y * 0.6), 0.12, STEEL)
		var h := foot
		while h < top - 2.0:
			for side in 4:
				var c0 := _corner(side) * 0.8
				var c1 := _corner(side + 1) * 0.8
				_beam(pst, Vector3(p.x + c0.x, h, p.y + c0.y), Vector3(p.x + c1.x, h + 2.5, p.y + c1.y), 0.06, STEEL)
			h += 2.5
		_box(pst, Vector3(p.x, top - 0.15, p.y), Vector3(2.4, 0.3, 2.4), Basis.IDENTITY, STEEL)
		_solid_cylinder(Vector3(p.x, foot, p.y), top - foot, 1.0)
	_end(pst, _metal, self)
	var barriers: Array = []
	for end: Vector3 in [a, b]:
		var face := (Vector3(b.x, 0, b.z) - Vector3(a.x, 0, a.z)).normalized() * (1.0 if end == a else -1.0)
		var box := BoxShape3D.new()
		box.size = Vector3(RAIL_GAP * 2.2, RAIL_H, 0.12)
		barriers.append(_shape(box, Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), end - face * 0.1 + Vector3(0, RAIL_H * 0.5, 0))))
	_looks[i] = [bought, shut, shapes, barriers]


# --- props ---

func _prop(st: SurfaceTool, glows: Dictionary, p: Dictionary) -> void:
	var deck: Dictionary = (rules.get("decks") as Array)[int(rules.call("deck_of", String(p["deck"])))]
	var y := float(deck["y"])
	var at := Vector3(float(p["at"][0]), y, float(p["at"][1]))
	var size := Vector3(1, 1, 1)
	if p.has("size"):
		size = Vector3(float(p["size"][0]), float(p["size"][1]), float(p["size"][2]))
	var turn := Basis(Vector3.UP, deg_to_rad(float(p.get("yaw", 0.0))))
	var col := Color(float(p["color"][0]), float(p["color"][1]), float(p["color"][2])) if p.has("color") else STEEL
	match String(p["kind"]):
		"container":
			var c := at + Vector3(0, size.y * 0.5, 0)
			_box(st, c, size, turn, col)
			var long_x := size.x >= size.z
			var n := int((size.x if long_x else size.z) / 0.5)
			for k in n + 1:  # corrugation ribs
				var t := float(k) / float(n) - 0.5
				var off := Vector3(t * size.x, 0, 0) if long_x else Vector3(0, 0, t * size.z)
				for s: float in [-1.0, 1.0]:
					var side := Vector3(0, 0, size.z * 0.5 * s + 0.03 * s) if long_x else Vector3(size.x * 0.5 * s + 0.03 * s, 0, 0)
					_box(st, at + turn * (off + side) + Vector3(0, size.y * 0.5, 0), Vector3(0.08, size.y * 0.96, 0.06) if long_x else Vector3(0.06, size.y * 0.96, 0.08), turn, col * 0.82)
			_solid_box(c, size, turn)
		"tank":
			var r := size.x * 0.5
			_cylinder(st, at, size.y, r, 16, WHITE * 0.85)
			_cylinder(st, at + Vector3(0, size.y, 0), 0.5, r * 0.75, 16, WHITE * 0.8)
			for h: float in [size.y * 0.33, size.y * 0.66]:
				_cylinder(st, at + Vector3(0, h, 0), 0.12, r + 0.05, 16, DARK)
			_solid_cylinder(at, size.y + 0.5, r)
		"pipes":
			for k in 3:
				var off := turn * Vector3(0, 0.3 + float(k) * 0.3, (float(k) - 1.0) * size.z * 0.3)
				_beam(st, at + off - turn * Vector3(size.x * 0.5, 0, 0), at + off + turn * Vector3(size.x * 0.5, 0, 0), 0.14, [STEEL, YELLOW, Color(0.6, 0.25, 0.2)][k])
			for e: float in [-0.45, 0.45]:
				_box(st, at + turn * Vector3(size.x * e, size.y * 0.5, 0), Vector3(0.2, size.y, size.z), turn, DARK)
			_solid_box(at + Vector3(0, size.y * 0.5, 0), size, turn)
		"pump":
			_box(st, at + Vector3(0, 0.3, 0), Vector3(size.x, 0.6, size.z), turn, DARK)
			_box(st, at + Vector3(0, 0.6 + (size.y - 0.6) * 0.5, 0), Vector3(size.x * 0.55, size.y - 0.6, size.z * 0.8), turn, Color(0.25, 0.45, 0.6))
			_beam(st, at + turn * Vector3(size.x * 0.25, size.y * 0.6, 0), at + turn * Vector3(size.x * 0.5, size.y * 0.6, 0), 0.25, STEEL)
			_solid_box(at + Vector3(0, size.y * 0.5, 0), size, turn)
		"drums":
			for k in 4:
				var off := turn * Vector3((float(k % 2) - 0.5) * size.x * 0.5, 0, (float(floori(float(k) / 2.0)) - 0.5) * size.z * 0.5)
				_cylinder(st, at + off, 0.9, 0.3, 10, [Color(0.15, 0.35, 0.65), Color(0.75, 0.2, 0.15)][k % 2])
			_solid_box(at + Vector3(0, 0.45, 0), Vector3(size.x, 0.9, size.z), turn)
		"derrick":
			var base := size.x * 0.5
			var top := base * 0.22
			for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				_beam(st, at + Vector3(corner.x * base, 0, corner.y * base), at + Vector3(corner.x * top, size.y, corner.y * top), 0.13, Color(0.8, 0.3, 0.2))
				_solid_cylinder(at + Vector3(corner.x * (base - 0.1), 0, corner.y * (base - 0.1)), 2.4, 0.18)
			var h := 0.0
			while h < size.y - 1.0:
				var w0 := lerpf(base, top, h / size.y)
				var w1 := lerpf(base, top, (h + 2.5) / size.y)
				for side in 4:
					var c0 := _corner(side)
					var c1 := _corner(side + 1)
					_beam(st, at + Vector3(c0.x * w0, h, c0.y * w0), at + Vector3(c1.x * w1, h + 2.5, c1.y * w1), 0.06, Color(0.8, 0.3, 0.2))
					_beam(st, at + Vector3(c0.x * w1, h + 2.5, c0.y * w1), at + Vector3(c1.x * w1, h + 2.5, c1.y * w1), 0.05, Color(0.8, 0.3, 0.2))
				h += 2.5
			_box(st, at + Vector3(0, size.y + 0.4, 0), Vector3(top * 2.6, 0.8, top * 2.6), Basis.IDENTITY, YELLOW)  # crown block
			_box(glows["beacon"], at + Vector3(0, size.y + 1.0, 0), Vector3(0.3, 0.3, 0.3), Basis.IDENTITY, WHITE)
		"crane":
			_cylinder(st, at, 2.6, 0.8, 12, YELLOW)
			_box(st, at + Vector3(0, 3.6, 0), Vector3(2.2, 2.0, 2.6), turn, YELLOW)
			_box(glows["window"], at + turn * Vector3(0, 3.8, -1.32), Vector3(1.6, 0.7, 0.04), turn, WHITE)
			var root := at + turn * Vector3(0, 3.2, -0.8)
			var tip := root + turn * Vector3(0, size.z * sin(deg_to_rad(32.0)), -size.z * cos(deg_to_rad(32.0)))
			for s: float in [-0.45, 0.45]:
				for h2: float in [0.0, 0.7]:
					_beam(st, root + turn * Vector3(s, h2, 0), tip + turn * Vector3(s * 0.4, h2 * 0.4, 0), 0.07, YELLOW)
			_beam(st, tip, tip - Vector3(0, 5.0, 0), 0.03, DARK)
			_box(st, tip - Vector3(0, 5.3, 0), Vector3(0.5, 0.6, 0.5), Basis.IDENTITY, DARK)
			_solid_cylinder(at, 2.6, 0.85)
			_solid_box(at + Vector3(0, 3.6, 0), Vector3(2.2, 2.0, 2.6), turn)
		"cabin":
			var c := at + Vector3(0, size.y * 0.5, 0)
			_box(st, c, size, turn, WHITE * 0.9)
			_box(glows["window"], at + turn * Vector3(0, size.y * 0.62, -size.z * 0.5 - 0.02), Vector3(size.x * 0.8, size.y * 0.3, 0.04), turn, WHITE)
			_box(st, at + turn * Vector3(size.x * 0.3, 1.0, size.z * 0.5 + 0.02), Vector3(0.9, 2.0, 0.05), turn, DARK)
			_solid_box(c, size, turn)
		"block":
			var c := at + Vector3(0, size.y * 0.5, 0)
			_box(st, c, size, turn, WHITE * 0.88)
			for floor_n in 2:
				for face in 4:
					var fdir := turn * Vector3(sin(float(face) * PI * 0.5), 0, cos(float(face) * PI * 0.5))
					var fside := fdir.cross(Vector3.UP)
					var span := size.x if face % 2 == 1 else size.z
					for k in 3:
						var off := fside * ((float(k) - 1.0) * span * 0.28)
						_box(glows["window"], at + fdir * (size.x * 0.5 + 0.02) + off + Vector3(0, 1.3 + float(floor_n) * 2.6, 0), Vector3(1.1, 0.9, 0.04), Basis(Vector3.UP, atan2(fdir.x, fdir.z)), WHITE)
			_box(st, at + turn * Vector3(0, 1.05, size.z * 0.5 + 0.03), Vector3(1.0, 2.1, 0.05), turn, DARK)  # a door (shut)
			_solid_box(c, size, turn)
		"lifeboat":
			_box(st, at + Vector3(0, 1.6, 0), size, turn, ORANGE)
			_box(st, at + Vector3(0, 1.6 + size.y * 0.5 + 0.1, 0), size * Vector3(0.8, 0.2, 0.8), turn, WHITE)
			for e: float in [-0.35, 0.35]:
				var long := turn * (Vector3(0, 0, size.z * e) if size.z > size.x else Vector3(size.x * e, 0, 0))
				_beam(st, at + long, at + long + Vector3(0, 2.8, 0), 0.08, STEEL)
			_solid_box(at + Vector3(0, 1.4, 0), size + Vector3(0, 2.8, 0) * Vector3(0, 1, 0), turn)
		"antenna":
			_cylinder(st, at, size.y, 0.12, 8, WHITE)
			for h3: float in [size.y * 0.5, size.y * 0.8]:
				_beam(st, at + Vector3(-0.8, h3, 0), at + Vector3(0.8, h3, 0), 0.04, WHITE)
			_box(glows["beacon"], at + Vector3(0, size.y + 0.15, 0), Vector3(0.3, 0.3, 0.3), Basis.IDENTITY, WHITE)
			_solid_cylinder(at, size.y, 0.15)
		"helipad":
			for k in 24:
				var a0 := TAU * float(k) / 24.0
				var a1 := TAU * float(k + 1) / 24.0
				var r := size.x * 0.4
				_beam(st, at + Vector3(cos(a0) * r, 0.03, sin(a0) * r), at + Vector3(cos(a1) * r, 0.03, sin(a1) * r), 0.2, YELLOW)
			var hh := size.x * 0.18
			_box(st, at + Vector3(-hh, 0.03, 0), Vector3(0.5, 0.05, hh * 2.4), Basis.IDENTITY, WHITE)
			_box(st, at + Vector3(hh, 0.03, 0), Vector3(0.5, 0.05, hh * 2.4), Basis.IDENTITY, WHITE)
			_box(st, at + Vector3(0, 0.03, 0), Vector3(hh * 2.0, 0.05, 0.5), Basis.IDENTITY, WHITE)
		"flare_boom":
			var dir := turn * Vector3(0, 0, -1)
			var root := at + Vector3(0, 0.5, 0)
			var tip := root + (dir * cos(deg_to_rad(40.0)) + Vector3(0, sin(deg_to_rad(40.0)), 0)) * size.y
			for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				var side := dir.cross(Vector3.UP).normalized()
				var off := side * corner.x * 0.5 + Vector3(0, corner.y * 0.5, 0)
				_beam(st, root + off * 1.4, tip + off * 0.5, 0.08, Color(0.8, 0.3, 0.2))
			_box(st, at + Vector3(0, 0.5, 0), Vector3(size.x, 1.0, size.z), turn, DARK)
			_solid_box(at + Vector3(0, 0.5, 0), Vector3(size.x, 1.0, size.z), turn)
			var flame := Node3D.new()
			flame.position = tip
			add_child(flame)
			var fst := _begin()
			_box(fst, Vector3(0, 1.2, 0), Vector3(1.0, 2.4, 1.0), Basis(Vector3.UP, 0.4), WHITE)
			_box(fst, Vector3(0, 2.3, 0), Vector3(0.6, 1.4, 0.6), Basis(Vector3.UP, 1.1), WHITE)
			_end(fst, _glow["flame"], flame).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_flames.append(flame)
		"lamp":
			_cylinder(st, at, 3.0, 0.07, 6, YELLOW)
			_beam(st, at + Vector3(0, 3.0, 0), at + Vector3(0.6, 3.0, 0), 0.05, YELLOW)
			_box(glows["lamp"], at + Vector3(0.6, 2.9, 0), Vector3(0.35, 0.18, 0.25), Basis.IDENTITY, WHITE)
			_solid_cylinder(at, 3.0, 0.1)


# --- building blocks ---

func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _end(st: SurfaceTool, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _shape(shape: Shape3D, xf: Transform3D) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xf
	_body.add_child(cs)
	return cs


func _solid_box(c: Vector3, size: Vector3, turn: Basis) -> void:
	var box := BoxShape3D.new()
	box.size = size
	_shape(box, Transform3D(turn, c))


func _solid_cylinder(base: Vector3, height: float, r: float) -> void:
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = height
	_shape(cyl, Transform3D(Basis.IDENTITY, base + Vector3(0, height * 0.5, 0)))


func _rail(st: SurfaceTool, p0: Vector2, p1: Vector2, y: float) -> void:
	_beam(st, Vector3(p0.x, y, p0.y), Vector3(p0.x, y + RAIL_H, p0.y), 0.045, YELLOW)
	_beam(st, Vector3(p0.x, y + RAIL_H, p0.y), Vector3(p1.x, y + RAIL_H, p1.y), 0.045, YELLOW)
	_beam(st, Vector3(p0.x, y + RAIL_H * 0.5, p0.y), Vector3(p1.x, y + RAIL_H * 0.5, p1.y), 0.03, YELLOW)
	var box := BoxShape3D.new()
	box.size = Vector3(0.12, RAIL_H, p0.distance_to(p1) + 0.04)
	var mid := (p0 + p1) * 0.5
	_shape(box, Transform3D(Basis(Vector3.UP, atan2(p1.x - p0.x, p1.y - p0.y)), Vector3(mid.x, y + RAIL_H * 0.5, mid.y)))


func _cylinder(st: SurfaceTool, base: Vector3, height: float, r: float, sides: int, col: Color) -> void:
	var top := base + Vector3(0, height, 0)
	var centre := base + Vector3(0, height * 0.5, 0)
	for k in sides:
		var a0 := TAU * float(k) / float(sides)
		var a1 := TAU * float(k + 1) / float(sides)
		var d0 := Vector3(cos(a0), 0, sin(a0)) * r
		var d1 := Vector3(cos(a1), 0, sin(a1)) * r
		_tri_out(st, base + d0, base + d1, top + d1, Vector3(base.x, base.y + height * 0.5, base.z) - Vector3(0, 0, 0), col, true)
		_tri_out(st, base + d0, top + d1, top + d0, centre, col, true)
		_tri_out(st, top, top + d0, top + d1, centre, col, false)


func _beam(st: SurfaceTool, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	_box(st, (a + b) * 0.5, Vector3(r * 2.0, r * 2.0, d.length()), Basis.looking_at(d.normalized(), up), col)


func _box(st: SurfaceTool, c: Vector3, size: Vector3, turn: Basis, col: Color) -> void:
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for z: float in [-h.z, h.z]:
		for y: float in [-h.y, h.y]:
			for x: float in [-h.x, h.x]:
				corners.append(c + turn * Vector3(x, y, z))
	for f: Array in [[0, 1, 3, 2], [5, 4, 6, 7], [4, 0, 2, 6], [1, 5, 7, 3], [2, 3, 7, 6], [4, 5, 1, 0]]:
		_tri_out(st, corners[f[0]], corners[f[1]], corners[f[2]], c, col, false)
		_tri_out(st, corners[f[0]], corners[f[2]], corners[f[3]], c, col, false)


# One triangle facing away from `inside` (clockwise = front in Godot); `radial` = for a round side, light it as if
# smooth round its axis (normal straight out from the axis).
func _tri_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3, col: Color, radial: bool) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()
	var out := n.dot((a + b + c) / 3.0 - inside) >= 0.0
	if not out:
		n = -n
	for p: Vector3 in ([a, c, b] if out else [a, b, c]):
		st.set_color(col)
		st.set_normal(Vector3(p.x - inside.x, 0, p.z - inside.z).normalized() if radial else n)
		st.add_vertex(p)
