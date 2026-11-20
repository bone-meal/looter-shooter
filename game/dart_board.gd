# Purpose: (polish1 item 71) one dartboard on the games-room wall: a standard board face (sectors, trebles, doubles,
# bulls, wires, numbers) drawn once into a texture, a cork-and-wood backboard with a lamp bar, the throw line (oche)
# on the floor 2.37 m out and a chalk scoreboard beside it. Gives the throw spots and turns board millimetres into
# world positions; makes and sticks the darts (one mesh each). Draws only: core/darts_rules.gd scores.
# Dependencies: core/darts_rules.gd (ring sizes, sector order), data/darts.json.
extends Node3D

const Rules = preload("res://core/darts_rules.gd")

const FACE_MM := 228.0  # the face texture covers the board out to this radius (numbers ring included)
const TEX := 1024

static var _face_tex: Texture2D = null  # shared by every board once drawn
static var _waiting: Array[StandardMaterial3D] = []

var distance := 2.37
var centre_height := 1.73  # the bull above the floor
var rules: RefCounted
var _face_mat: StandardMaterial3D
var _chalk: Label3D
var _stuck: Array[Node3D] = []


# The board's centre is this node's origin; local +z points into the room (toward the thrower), +x is the thrower's right.
func setup(darts_rules: RefCounted, throw_distance: float, height: float) -> void:
	rules = darts_rules
	distance = throw_distance
	centre_height = height
	_backboard()
	_face()
	_oche()
	_scoreboard()


func mm_to_world(p: Vector2, out := 0.0) -> Vector3:
	return to_global(Vector3(p.x / 1000.0, p.y / 1000.0, 0.012 + out))


func normal() -> Vector3:
	return global_basis.z.normalized()


func oche_position() -> Vector3:  # on the floor at the throw line, in the middle
	return to_global(Vector3(0, -centre_height, distance))


func eye_position() -> Vector3:
	return global_position + normal() * distance + Vector3(0, -0.04, 0)


func set_chalk(text: String) -> void:
	_chalk.text = text


# A dart that has landed at board point p (mm): stuck in the board, tail up and out a little.
func stick(p: Vector2, colour: Color, rng: RandomNumberGenerator) -> Node3D:
	var d := make_dart(colour)
	add_child(d)
	d.position = Vector3(p.x / 1000.0, p.y / 1000.0, 0.012 - 0.014)  # the point is in the sisal
	var tilt := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(0.04, 0.2), 1.0).normalized()  # tail up and out
	d.basis = Basis.looking_at(-tilt, Vector3.UP)
	_stuck.append(d)
	return d


func clear_darts() -> void:
	for d in _stuck:
		d.queue_free()
	_stuck.clear()


static var _dart_meshes := {}  # colour html -> ArrayMesh


# A dart along -z: steel point at the origin, tungsten barrel, coloured shaft and flights toward +z.
static func make_dart(colour: Color) -> MeshInstance3D:
	var key := colour.to_html()
	if not _dart_meshes.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tube(st, 0.0, 0.032, 0.0002, 0.0012, Color(0.78, 0.8, 0.84))  # point
		_tube(st, 0.032, 0.04, 0.0025, 0.0036, Color(0.45, 0.47, 0.5))
		_tube(st, 0.04, 0.078, 0.0036, 0.0036, Color(0.42, 0.44, 0.48))  # barrel
		_tube(st, 0.078, 0.084, 0.0036, 0.0019, Color(0.3, 0.3, 0.33))
		_tube(st, 0.084, 0.118, 0.0019, 0.0019, colour.darkened(0.3))  # shaft
		for k in 2:  # two flights, crossed
			var a := Vector3(1, 0, 0) if k == 0 else Vector3(0, 1, 0)
			var p0 := Vector3(0, 0, 0.092)
			var p1 := Vector3(0, 0, 0.13)
			for side: float in [-1.0, 1.0]:
				var w0 := a * side * 0.004
				var w1 := a * side * 0.016
				st.set_color(colour)
				st.add_vertex(p0 + w0)
				st.add_vertex(p1 + w1)
				st.add_vertex(p1)
				st.add_vertex(p0 + w0)
				st.add_vertex(p1)
				st.add_vertex(p0)
		st.generate_normals()
		var mesh := st.commit()
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.roughness = 0.45
		mesh.surface_set_material(0, m)
		_dart_meshes[key] = mesh
	var d := MeshInstance3D.new()
	d.mesh = _dart_meshes[key]
	d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return d


static func _tube(st: SurfaceTool, z0: float, z1: float, r0: float, r1: float, colour: Color) -> void:
	var sides := 8
	st.set_color(colour)
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var v00 := Vector3(cos(a0) * r0, sin(a0) * r0, z0)
		var v01 := Vector3(cos(a1) * r0, sin(a1) * r0, z0)
		var v10 := Vector3(cos(a0) * r1, sin(a0) * r1, z1)
		var v11 := Vector3(cos(a1) * r1, sin(a1) * r1, z1)
		st.add_vertex(v00)
		st.add_vertex(v10)
		st.add_vertex(v11)
		st.add_vertex(v00)
		st.add_vertex(v11)
		st.add_vertex(v01)


func _box(size: Vector3, pos: Vector3, colour: Color, glow := false) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var n := MeshInstance3D.new()
	n.mesh = b
	var m := StandardMaterial3D.new()
	m.albedo_color = colour
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	n.material_override = m
	n.position = pos
	add_child(n)
	return n


func _backboard() -> void:
	_box(Vector3(0.82, 0.82, 0.03), Vector3(0, 0, -0.015), Color(0.28, 0.15, 0.07))  # wooden cabinet back
	_box(Vector3(0.7, 0.7, 0.02), Vector3(0, 0, 0.0), Color(0.55, 0.42, 0.28))  # cork surround
	_box(Vector3(0.86, 0.05, 0.12), Vector3(0, 0.46, 0.05), Color(0.1, 0.1, 0.12))  # lamp bar
	_box(Vector3(0.8, 0.012, 0.08), Vector3(0, 0.432, 0.06), Color(1.0, 0.93, 0.78), true)  # its glowing strip


func _face() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(FACE_MM * 2.0 / 1000.0, FACE_MM * 2.0 / 1000.0)
	_face_mat = StandardMaterial3D.new()
	_face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # always readable in the dark room (lit by its lamp bar)
	_face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_face_mat.albedo_color = Color(0.92, 0.92, 0.92)
	var n := MeshInstance3D.new()
	n.mesh = quad
	n.material_override = _face_mat
	n.position = Vector3(0, 0, 0.012)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	if _face_tex != null:
		_face_mat.albedo_texture = _face_tex
		return
	_waiting.append(_face_mat)
	if _waiting.size() == 1:
		_draw_face.call_deferred()


# Draws the face once in a 2D viewport, keeps it as a mipmapped texture for every board, frees the viewport.
func _draw_face() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(TEX, TEX)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var face := BoardFace.new()
	face.rules = rules
	face.size = Vector2(TEX, TEX)
	vp.add_child(face)
	add_child(vp)
	for m in _waiting:
		m.albedo_texture = vp.get_texture()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.generate_mipmaps()
	_face_tex = ImageTexture.create_from_image(img)
	for m in _waiting:
		m.albedo_texture = _face_tex
	_waiting.clear()
	vp.queue_free()


func _oche() -> void:  # the throw line across the throw direction
	_box(Vector3(0.9, 0.02, 0.05), Vector3(0, -centre_height + 0.012, distance), Color(0.85, 0.75, 0.3), true)


func _scoreboard() -> void:
	_box(Vector3(0.6, 0.8, 0.03), Vector3(0.82, 0.0, -0.01), Color(0.12, 0.14, 0.13))  # slate
	_box(Vector3(0.64, 0.84, 0.02), Vector3(0.82, 0.0, -0.02), Color(0.35, 0.2, 0.1))  # frame
	_chalk = Label3D.new()
	_chalk.text = "DARTS\n\n501\nAround the\nClock"
	_chalk.font_size = 40
	_chalk.pixel_size = 0.0011
	_chalk.modulate = Color(0.95, 0.95, 0.9)
	_chalk.shaded = false
	_chalk.double_sided = false
	_chalk.position = Vector3(0.82, 0.0, 0.01)
	add_child(_chalk)


# The board face, drawn in board millimetres scaled to the texture.
class BoardFace:
	extends Control
	const R = preload("res://core/darts_rules.gd")
	var rules: RefCounted

	func _draw() -> void:
		var k := size.x * 0.5 / 228.0
		var c := size * 0.5
		var black := Color(0.08, 0.08, 0.08)
		var cream := Color(0.93, 0.86, 0.68)
		var red := Color(0.78, 0.1, 0.1)
		var green := Color(0.05, 0.5, 0.2)
		draw_circle(c, 228.0 * k, Color(0.05, 0.05, 0.05))
		var rr: Dictionary = {"b": float(rules.get("r_bull")), "ob": float(rules.get("r_outer_bull")), "ti": float(rules.get("r_treble_in")), "to": float(rules.get("r_treble_out")), "di": float(rules.get("r_double_in")), "do": float(rules.get("r_double_out"))}
		for i in 20:
			var even := i % 2 == 0
			_band(c, k, i, rr["ob"], rr["ti"], black if even else cream)
			_band(c, k, i, rr["ti"], rr["to"], red if even else green)
			_band(c, k, i, rr["to"], rr["di"], black if even else cream)
			_band(c, k, i, rr["di"], rr["do"], red if even else green)
		draw_circle(c, rr["ob"] * k, green)
		draw_circle(c, rr["b"] * k, red)
		var wire := Color(0.75, 0.76, 0.78)
		for r: float in [rr["ob"], rr["ti"], rr["to"], rr["di"], rr["do"]]:
			draw_arc(c, r * k, 0.0, TAU, 96, wire, 1.6, true)
		draw_arc(c, rr["b"] * k, 0.0, TAU, 32, wire, 1.4, true)
		for i in 20:
			var a := deg_to_rad(float(i) * 18.0 - 9.0)
			var dir := Vector2(sin(a), -cos(a))
			draw_line(c + dir * rr["ob"] * k, c + dir * rr["do"] * k, wire, 1.6, true)
		var font := ThemeDB.fallback_font
		var fs := int(26.0 * k)
		var order: Array = R.ORDER
		for i in 20:
			var a2 := deg_to_rad(float(i) * 18.0)
			var at := c + Vector2(sin(a2), -cos(a2)) * 199.0 * k
			var text := str(order[i])
			var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			draw_string(font, at + Vector2(-ts.x * 0.5, ts.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.95, 0.95, 0.95))

	func _band(c: Vector2, k: float, i: int, r0: float, r1: float, colour: Color) -> void:
		var pts := PackedVector2Array()
		var a0 := deg_to_rad(float(i) * 18.0 - 9.0)
		var steps := 6
		for s in steps + 1:
			var a := a0 + deg_to_rad(18.0) * float(s) / float(steps)
			pts.append(c + Vector2(sin(a), -cos(a)) * r1 * k)
		for s in range(steps, -1, -1):
			var a := a0 + deg_to_rad(18.0) * float(s) / float(steps)
			pts.append(c + Vector2(sin(a), -cos(a)) * r0 * k)
		draw_colored_polygon(pts, colour)
