# Purpose: (polish1 item 71) one pool table in the games room: a 9 ft table (green cloth, cushions, leather pockets,
# wooden frame with pearl sights, legs, a lamp over it), its 16 numbered balls (one MultiMesh: a picture atlas drawn
# once, each ball rolls round its own axis), the cue stick, the aiming guide (line, ghost ball, the object ball's and
# the cue ball's paths, played ahead on a copy of the table), a ring on the called pocket and a ring where a ball in hand would go. Draws only:
# core/pool_sim.gd moves the balls. Sim coordinates (x along, y across) are this node's local x / z on the cloth.
# Dependencies: core/pool_sim.gd (sizes, pockets, positions).
extends Node3D

const CLOTH_Y := 0.79  # height of the playing surface
const LAMP_LAYER := 1 << 9  # render layer 10: the lamp, which the over-the-table view leaves out
const TILE := Vector2i(256, 128)

static var _atlas: Texture2D = null
static var _waiting: Array[ShaderMaterial] = []

var sim: RefCounted
var _balls: MultiMesh
var _basis: Array[Basis] = []
var _cue: Node3D
var _guide_line: MeshInstance3D
var _ghost: MeshInstance3D
var _obj_line: MeshInstance3D
var _cue_line: MeshInstance3D
var _called: MeshInstance3D
var _place_ring: MeshInstance3D
var _paths: MeshInstance3D  # (bug update) where the cue ball and the ball it hits really go: the shot played ahead
var _paths_mesh: ImmediateMesh
var _path_key := Vector4(INF, 0, 0, 0)  # angle, power, spin x, spin y of the drawn preview
var _path_at := 0.0
var _path_hit := -1


func setup(pool_sim: RefCounted) -> void:
	sim = pool_sim
	_frame()
	_build_balls()
	_build_cue()
	_build_guides()
	_lamp()


func to_world(p: Vector2, lift := 0.0) -> Vector3:
	return to_global(Vector3(p.x, CLOTH_Y + float(sim.get("r")) + lift, p.y))


func dir_world(angle: float) -> Vector3:
	return global_basis * Vector3(cos(angle), 0.0, sin(angle))


# A world point on the cloth back to sim coordinates.
func to_sim(world: Vector3) -> Vector2:
	var l := to_local(world)
	return Vector2(l.x, l.z)


func centre_top() -> Vector3:
	return to_global(Vector3(0, CLOTH_Y, 0))


# ------------------------------------------------------------------ building

func _mat(c: Color, rough := 0.8, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(size: Vector3, pos: Vector3, m: Material, solid := false) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	var n := MeshInstance3D.new()
	n.mesh = b
	n.material_override = m
	n.position = pos
	add_child(n)
	if solid:
		var body := StaticBody3D.new()
		body.position = pos
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)
	return n


func _frame() -> void:
	var L := float(sim.get("length"))
	var W := float(sim.get("width"))
	var cloth := _mat(Color(0.05, 0.38, 0.2), 0.95)
	var wood := _mat(Color(0.3, 0.13, 0.05), 0.45)
	var rail_w := 0.16
	_box(Vector3(L + 0.1, 0.06, W + 0.1), Vector3(0, CLOTH_Y - 0.03, 0), cloth)  # bed
	_box(Vector3(L + 2.0 * rail_w + 0.1, 0.62, W + 2.0 * rail_w + 0.1), Vector3(0, CLOTH_Y - 0.37, 0), wood, true)  # body (a collider)
	var h := 0.045  # cushion height above the cloth
	for seg: Array in sim.get("rails"):  # green cushions along the rail segments, wood behind them
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var mid := (a + b) * 0.5
		var along := absf(b.x - a.x) > 0.01
		var out := Vector2(0, signf(mid.y)) if along else Vector2(signf(mid.x), 0)
		var seg_len := a.distance_to(b)
		var cush := Vector3(seg_len, h, 0.05) if along else Vector3(0.05, h, seg_len)
		_box(cush, Vector3(mid.x + out.x * 0.025, CLOTH_Y + h * 0.5, mid.y + out.y * 0.025), cloth)
		var top := Vector3(seg_len + 0.04, 0.05, rail_w) if along else Vector3(rail_w, 0.05, seg_len + 0.04)
		_box(top, Vector3(mid.x + out.x * (0.05 + rail_w * 0.5), CLOTH_Y + h + 0.0, mid.y + out.y * (0.05 + rail_w * 0.5)), wood)
	# pockets: leather cups (one MultiMesh) where the rails stop
	var cup := CylinderMesh.new()
	cup.top_radius = 0.075
	cup.bottom_radius = 0.06
	cup.height = 0.08
	cup.radial_segments = 14
	cup.rings = 1
	cup.material = _mat(Color(0.03, 0.03, 0.03), 0.9)
	var cups := MultiMesh.new()
	cups.transform_format = MultiMesh.TRANSFORM_3D
	cups.mesh = cup
	var pockets: Array = sim.get("pockets")
	cups.instance_count = pockets.size()
	for k in pockets.size():
		var p: Vector2 = pockets[k]
		cups.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(p.x, CLOTH_Y + 0.005, p.y)))
	var cn := MultiMeshInstance3D.new()
	cn.multimesh = cups
	add_child(cn)
	# (polish1 item 166) a pale brass liner round each pocket's mouth, faintly lit, so the pockets read in the dark room
	var ring := TorusMesh.new()
	ring.inner_radius = 0.07
	ring.outer_radius = 0.088
	ring.rings = 18
	ring.ring_segments = 6
	var brass := _mat(Color(0.85, 0.66, 0.3), 0.35)
	brass.metallic = 0.6
	brass.emission_enabled = true
	brass.emission = Color(0.55, 0.42, 0.18)
	brass.emission_energy_multiplier = 0.6
	ring.material = brass
	var rings := MultiMesh.new()
	rings.transform_format = MultiMesh.TRANSFORM_3D
	rings.mesh = ring
	rings.instance_count = pockets.size()
	for k in pockets.size():
		var p2: Vector2 = pockets[k]
		rings.set_instance_transform(k, Transform3D(Basis.IDENTITY, Vector3(p2.x, CLOTH_Y + 0.012, p2.y)))
	var rn := MultiMeshInstance3D.new()
	rn.multimesh = rings
	add_child(rn)
	# pearl sights on the rail tops
	var dot := SphereMesh.new()
	dot.radius = 0.008
	dot.height = 0.008
	dot.radial_segments = 6
	dot.rings = 3
	dot.material = _mat(Color(0.95, 0.93, 0.85), 0.3)
	var dots := MultiMesh.new()
	dots.transform_format = MultiMesh.TRANSFORM_3D
	dots.mesh = dot
	var spots: Array[Vector3] = []
	for i in range(1, 8):
		if i == 4:
			continue
		var x := -L * 0.5 + L * float(i) / 8.0
		spots.append(Vector3(x, CLOTH_Y + h + 0.026, -W * 0.5 - 0.05 - rail_w * 0.5))
		spots.append(Vector3(x, CLOTH_Y + h + 0.026, W * 0.5 + 0.05 + rail_w * 0.5))
	for i in range(1, 4):
		var z := -W * 0.5 + W * float(i) / 4.0
		spots.append(Vector3(-L * 0.5 - 0.05 - rail_w * 0.5, CLOTH_Y + h + 0.026, z))
		spots.append(Vector3(L * 0.5 + 0.05 + rail_w * 0.5, CLOTH_Y + h + 0.026, z))
	dots.instance_count = spots.size()
	for i in spots.size():
		dots.set_instance_transform(i, Transform3D(Basis.IDENTITY, spots[i]))
	var dn := MultiMeshInstance3D.new()
	dn.multimesh = dots
	add_child(dn)
	for sx: float in [-1.0, 1.0]:  # legs
		for sz: float in [-1.0, 1.0]:
			_box(Vector3(0.14, 0.5, 0.14), Vector3(sx * (L * 0.5 - 0.1), 0.25, sz * (W * 0.5 - 0.05)), wood)


func _lamp() -> void:
	var L := float(sim.get("length"))
	var parts: Array[MeshInstance3D] = []
	parts.append(_box(Vector3(L * 0.75, 0.12, 0.34), Vector3(0, CLOTH_Y + 1.15, 0), _mat(Color(0.06, 0.25, 0.12), 0.5)))  # shade
	parts.append(_box(Vector3(L * 0.72, 0.012, 0.3), Vector3(0, CLOTH_Y + 1.088, 0), _mat(Color(1.0, 0.95, 0.8), 0.5, true)))  # its glowing underside
	for sx: float in [-0.3, 0.3]:
		parts.append(_box(Vector3(0.012, 1.2, 0.012), Vector3(sx * L, CLOTH_Y + 1.8, 0), _mat(Color(0.1, 0.1, 0.1))))
	for p in parts:
		p.layers = LAMP_LAYER
	var spot := SpotLight3D.new()  # one small real light on the cloth (no shadows): the balls need it to read
	add_child(spot)
	spot.position = Vector3(0, CLOTH_Y + 1.05, 0)
	spot.rotation_degrees.x = -90.0
	spot.light_color = Color(1.0, 0.95, 0.85)
	spot.light_energy = 1.6
	spot.spot_range = 1.6
	spot.spot_angle = 62.0
	spot.shadow_enabled = false


# ------------------------------------------------------------------ balls

const BALL_SHADER := """
shader_type spatial;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
void vertex() {
	UV = UV * vec2(0.25, 0.25) + INSTANCE_CUSTOM.xy;
}
void fragment() {
	ALBEDO = texture(atlas, UV).rgb;
	ROUGHNESS = 0.18;
	SPECULAR = 0.7;
}
"""


func _build_balls() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = float(sim.get("r"))
	sphere.height = sphere.radius * 2.0
	sphere.radial_segments = 20
	sphere.rings = 10
	var sh := Shader.new()
	sh.code = BALL_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	sphere.material = m
	_balls = MultiMesh.new()
	_balls.transform_format = MultiMesh.TRANSFORM_3D
	_balls.use_custom_data = true
	_balls.mesh = sphere
	_balls.instance_count = 16
	for i in 16:
		_balls.set_instance_custom_data(i, Color(float(i % 4) * 0.25, float(i >> 2) * 0.25, 0, 0))
		_basis.append(Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, randf_range(-0.6, 0.6)))
	var n := MultiMeshInstance3D.new()
	n.multimesh = _balls
	add_child(n)
	if _atlas != null:
		m.set_shader_parameter("atlas", _atlas)
	else:
		_waiting.append(m)
		if _waiting.size() == 1:
			_draw_atlas.call_deferred()
	update_balls(0.0)


# Every frame while balls move: positions, and each ball turned the way it rolls.
func update_balls(delta: float) -> void:
	var pos: PackedVector2Array = sim.get("pos")
	var vel: PackedVector2Array = sim.get("vel")
	var on: PackedByteArray = sim.get("on_table")
	var r := float(sim.get("r"))
	for i in 16:
		if on[i] == 0:
			_balls.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.001), Vector3(0, -1.0, 0)))
			continue
		var v := vel[i]
		var sp := v.length()
		if sp > 0.0001 and delta > 0.0:
			var axis := Vector3(v.y, 0.0, -v.x) / sp  # rolling forward along v turns about up x v
			_basis[i] = Basis(axis, sp * delta / r) * _basis[i]
			_basis[i] = _basis[i].orthonormalized()
		_balls.set_instance_transform(i, Transform3D(_basis[i], Vector3(pos[i].x, CLOTH_Y + r, pos[i].y)))


func _draw_atlas() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(TILE.x * 4, TILE.y * 4)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var art := BallArt.new()
	art.size = Vector2(vp.size)
	vp.add_child(art)
	add_child(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	img.generate_mipmaps()
	_atlas = ImageTexture.create_from_image(img)
	for m in _waiting:
		m.set_shader_parameter("atlas", _atlas)
	_waiting.clear()
	vp.queue_free()


# The 16 balls' pictures (equirectangular): solids in their colour, stripes white with a band, number discs.
class BallArt:
	extends Control
	const COLOURS := [Color(1, 1, 1), Color(0.98, 0.78, 0.05), Color(0.1, 0.25, 0.85), Color(0.85, 0.1, 0.1), Color(0.4, 0.12, 0.6),
		Color(1.0, 0.45, 0.05), Color(0.05, 0.5, 0.2), Color(0.5, 0.12, 0.08), Color(0.05, 0.05, 0.05)]

	func _draw() -> void:
		var tw := size.x / 4.0
		var th := size.y / 4.0
		var font := ThemeDB.fallback_font
		for i in 16:
			var o := Vector2(float(i % 4) * tw, float(i >> 2) * th)
			var base: Color = COLOURS[i if i <= 8 else i - 8]
			var stripe := i >= 9
			draw_rect(Rect2(o, Vector2(tw, th)), Color(0.97, 0.96, 0.92) if stripe or i == 0 else base)
			if stripe:
				draw_rect(Rect2(o + Vector2(0, th * 0.27), Vector2(tw, th * 0.46)), base)
			if i == 0:
				for u: float in [0.25, 0.75]:  # the cue ball's two red spots (to see it spin)
					draw_circle(o + Vector2(tw * u, th * 0.5), th * 0.05, Color(0.8, 0.1, 0.1))
				continue
			for u: float in [0.25, 0.75]:
				var c := o + Vector2(tw * u, th * 0.5)
				draw_set_transform(c, 0.0, Vector2(0.55, 1.0))  # the disc is squeezed so it reads round on the sphere
				draw_circle(Vector2.ZERO, th * 0.2, Color(0.98, 0.98, 0.95))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				var text := str(i)
				var fs := int(th * 0.22)
				var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_set_transform(c, 0.0, Vector2(0.6, 1.0))
				draw_string(font, Vector2(-ts.x * 0.5, ts.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.05, 0.05, 0.05))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ------------------------------------------------------------------ cue and guides

func _build_cue() -> void:
	_cue = Node3D.new()
	add_child(_cue)
	var shaft := CylinderMesh.new()  # along the node's +z: the tip at z 0, the butt at +1.47
	shaft.top_radius = 0.0065
	shaft.bottom_radius = 0.0145
	shaft.height = 1.47
	shaft.radial_segments = 10
	shaft.rings = 1
	var n := MeshInstance3D.new()
	n.mesh = shaft
	n.material_override = _mat(Color(0.82, 0.68, 0.45), 0.4)
	n.rotation_degrees.x = -90.0
	n.position = Vector3(0, 0, 0.735)
	_cue.add_child(n)
	var butt := CylinderMesh.new()
	butt.top_radius = 0.0125
	butt.bottom_radius = 0.0148
	butt.height = 0.45
	butt.radial_segments = 10
	butt.rings = 1
	var bn := MeshInstance3D.new()
	bn.mesh = butt
	bn.material_override = _mat(Color(0.12, 0.05, 0.03), 0.35)
	bn.rotation_degrees.x = -90.0
	bn.position = Vector3(0, 0, 1.25)
	_cue.add_child(bn)
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0062
	tip.bottom_radius = 0.0062
	tip.height = 0.012
	tip.radial_segments = 8
	tip.rings = 1
	var tn := MeshInstance3D.new()
	tn.mesh = tip
	tn.material_override = _mat(Color(0.2, 0.35, 0.75), 0.9)
	tn.rotation_degrees.x = -90.0
	tn.position = Vector3(0, 0, 0.006)
	_cue.add_child(tn)
	_cue.visible = false


# The cue behind the cue ball, aimed along `angle`, drawn back by `pull` metres, its tip offset for spin, tilted up.
func show_cue(on: bool, angle := 0.0, pull := 0.0, spin := Vector2.ZERO) -> void:
	_cue.visible = on
	if not on:
		return
	var r := float(sim.get("r"))
	var p: Vector2 = (sim.get("pos") as PackedVector2Array)[0]
	var d := Vector2(cos(angle), sin(angle))
	var side := Vector2(-d.y, d.x)
	var tip := Vector3(p.x, CLOTH_Y + r, p.y) - Vector3(d.x, 0, d.y) * (r + 0.008 + pull) + Vector3(side.x, 0, side.y) * spin.x * r * 0.5 + Vector3(0, spin.y * r * 0.5, 0)
	_cue.position = tip
	var forward := Vector3(d.x, -0.1, d.y).normalized()  # the butt a little higher than the tip
	_cue.basis = Basis.looking_at(forward, Vector3.UP)


func _build_guides() -> void:
	var white := _mat(Color(1, 1, 1, 0.85), 0.5, true)
	white.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_guide_line = _bar(white)
	_obj_line = _bar(white)
	var dim := _mat(Color(0.7, 0.85, 1.0, 0.6), 0.5, true)
	dim.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_cue_line = _bar(dim)
	var ring := TorusMesh.new()
	ring.inner_radius = float(sim.get("r")) * 0.9
	ring.outer_radius = float(sim.get("r")) * 1.05
	ring.rings = 24
	ring.ring_segments = 4
	_ghost = MeshInstance3D.new()
	_ghost.mesh = ring
	_ghost.material_override = white
	add_child(_ghost)
	var big := TorusMesh.new()
	big.inner_radius = 0.07
	big.outer_radius = 0.085
	big.rings = 24
	big.ring_segments = 4
	_called = MeshInstance3D.new()
	_called.mesh = big
	_called.material_override = _mat(Color(1.0, 0.8, 0.25), 0.5, true)
	add_child(_called)
	_place_ring = MeshInstance3D.new()
	_place_ring.mesh = ring
	_place_ring.material_override = _mat(Color(0.4, 1.0, 0.5), 0.5, true)
	add_child(_place_ring)
	_paths_mesh = ImmediateMesh.new()
	_paths = MeshInstance3D.new()
	_paths.mesh = _paths_mesh
	_paths.material_override = _mat(Color(1, 1, 1), 0.5, true)
	(_paths.material_override as StandardMaterial3D).vertex_color_use_as_albedo = true
	(_paths.material_override as StandardMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
	_paths.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_paths)
	hide_guides()
	show_called(-1)
	show_place(false)


func _bar(m: Material) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(1, 1, 1)
	var n := MeshInstance3D.new()
	n.mesh = b
	n.material_override = m
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(n)
	return n


func _place_bar(n: MeshInstance3D, a: Vector2, b: Vector2, thick := 0.004) -> void:
	var y := CLOTH_Y + 0.002
	var mid := (a + b) * 0.5
	var l := a.distance_to(b)
	n.visible = l > 0.001
	if not n.visible:
		return
	n.transform = Transform3D(Basis(Vector3.UP, -(b - a).angle()).scaled(Vector3(l, 0.002, thick)), Vector3(mid.x, y, mid.y))


func hide_guides() -> void:
	_paths.visible = false
	_path_key = Vector4(INF, 0, 0, 0)
	_guide_line.visible = false
	_obj_line.visible = false
	_cue_line.visible = false
	_ghost.visible = false


# The aiming guide for a shot along `angle` with the power and spin set now (bug update: the lines are the shot played
# ahead on a copy of the table with only the cue ball and the ball it meets: the cue ball's path from the ball to past
# the contact, follow / draw / english included, and the object ball's path toward its pocket; with no power set yet a
# medium shot is shown). Returns the ball it would hit first (-1 none).
func show_guides(angle: float, power := 0.0, spin := Vector2.ZERO) -> int:
	var hit := _straight_guides(angle)
	_guide_line.visible = false  # the preview path replaces the straight line and the short stubs
	_obj_line.visible = false
	_cue_line.visible = false
	var key := Vector4(angle, maxf(power, 0.45), spin.x, spin.y)
	var now := Time.get_ticks_msec() / 1000.0
	if (key - _path_key).length() > 0.002 and now - _path_at > 0.06:
		_path_key = key
		_path_at = now
		_path_hit = hit
		_draw_paths(angle, key.y, spin, hit)
	_paths.visible = true
	return hit


func _draw_paths(angle: float, power: float, spin: Vector2, hit: int) -> void:
	var p: RefCounted = sim.call("copy_still")
	var on: PackedByteArray = p.get("on_table")
	for j in on.size():
		if j != 0 and j != hit:
			on[j] = 0
	p.set("on_table", on)
	p.call("shoot", angle, power, spin)
	var cue := PackedVector3Array([_cloth(p, 0)])
	var obj := PackedVector3Array()
	var cue_after := 0.0
	var obj_run := 0.0
	var t := 0.0
	while t < 4.0:
		p.call("tick_once")
		t += 1.0 / 240.0
		var on_now: PackedByteArray = p.get("on_table")
		var touched := int(p.get("first_hit")) >= 0
		if on_now[0] == 1 and cue_after < 0.55:
			var c := _cloth(p, 0)
			if c.distance_to(cue[cue.size() - 1]) > 0.02:
				if touched:
					cue_after += c.distance_to(cue[cue.size() - 1])
				cue.append(c)
		if hit >= 0 and touched and on_now[hit] == 1 and obj_run < 1.1:
			var o := _cloth(p, hit)
			if obj.is_empty() or o.distance_to(obj[obj.size() - 1]) > 0.02:
				if not obj.is_empty():
					obj_run += o.distance_to(obj[obj.size() - 1])
				obj.append(o)
		var still := (p.get("vel") as PackedVector2Array)[0] == Vector2.ZERO
		if (cue_after >= 0.55 or on_now[0] == 0 or still) and (hit < 0 or obj_run >= 1.1 or on_now[hit] == 0 or (touched and (p.get("vel") as PackedVector2Array)[hit] == Vector2.ZERO)):
			break
		if not touched and hit >= 0 and t > 3.0:
			break
	_paths_mesh.clear_surfaces()
	_paths_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_strip(cue, Color(1, 1, 1, 1), 0.007)
	_strip(obj, Color(1.0, 0.85, 0.3, 1), 0.007)
	_paths_mesh.surface_end()


func _cloth(p: RefCounted, ball: int) -> Vector3:
	var at: Vector2 = (p.get("pos") as PackedVector2Array)[ball]
	return Vector3(at.x, CLOTH_Y + 0.003, at.y)


# A flat ribbon along the points, `w` wide, on the cloth.
func _strip(pts: PackedVector3Array, color: Color, w: float) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var side := (b - a).cross(Vector3.UP).normalized() * w * 0.5
		for v: Vector3 in [a - side, a + side, b + side, a - side, b + side, b - side]:
			_paths_mesh.surface_set_color(color)
			_paths_mesh.surface_add_vertex(v)


func _straight_guides(angle: float) -> int:
	var pos: PackedVector2Array = sim.get("pos")
	var on: PackedByteArray = sim.get("on_table")
	var r := float(sim.get("r"))
	var from := pos[0]
	var d := Vector2(cos(angle), sin(angle))
	var best_t := 4.0
	var hit := -1
	for j in range(1, 16):
		if on[j] == 0:
			continue
		var f := from - pos[j]
		var b := f.dot(d)
		var c := f.length_squared() - 4.0 * r * r
		var disc := b * b - c
		if disc < 0.0:
			continue
		var t := -b - sqrt(disc)
		if t > 0.0 and t < best_t:
			best_t = t
			hit = j
	var hx := float(sim.get("length")) * 0.5 - r
	var hy := float(sim.get("width")) * 0.5 - r
	for axis in 2:  # the cushion it would reach first
		var dc := d.x if axis == 0 else d.y
		if absf(dc) < 1e-6:
			continue
		var lim := hx if axis == 0 else hy
		var cur := from.x if axis == 0 else from.y
		var t2 := ((lim if dc > 0.0 else -lim) - cur) / dc
		if t2 > 0.0 and t2 < best_t:
			best_t = t2
			hit = -1
	var ghost := from + d * best_t
	_place_bar(_guide_line, from, ghost)
	_ghost.visible = true
	_ghost.position = Vector3(ghost.x, CLOTH_Y + r, ghost.y)
	_ghost.rotation = Vector3.ZERO
	if hit >= 0:
		var n := (pos[hit] - ghost).normalized()
		_place_bar(_obj_line, pos[hit], pos[hit] + n * 0.3)
		var tangent := d - n * d.dot(n)
		_place_bar(_cue_line, ghost, ghost + tangent.normalized() * 0.18 * tangent.length())
	else:
		_obj_line.visible = false
		_cue_line.visible = false
	return hit


func show_called(pocket: int) -> void:
	_called.visible = pocket >= 0
	if pocket >= 0:
		var p: Vector2 = (sim.get("pockets") as Array)[pocket]
		_called.position = Vector3(p.x, CLOTH_Y + 0.05, p.y)


func show_place(on: bool, at := Vector2.ZERO, ok := true) -> void:
	_place_ring.visible = on
	if on:
		_place_ring.position = Vector3(at.x, CLOTH_Y + 0.003, at.y)
		(_place_ring.material_override as StandardMaterial3D).albedo_color = Color(0.4, 1.0, 0.5) if ok else Color(1.0, 0.35, 0.3)
