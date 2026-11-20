# Purpose: the card vending machine of "You got me Lobster?" in the casino (polish1 item 76: a real vending machine): a
# tall cabinet whose window is clear glass over a dark inside lit by a white strip, with the real goods on three
# shelves: single packs on coils at the top, 5- and 10-pack bundles in the middle, boxes of 50 at the bottom, each with
# its price on the rail; a side panel with a screen, keypad and chip slot, the pick-up flap below, the logo on top.
# F in front of it opens game/tcg/vendor_screen.gd. Primitive meshes and shared materials, no lights.
# Dependencies: assets/tcg/logo.png, pack.png, box.png, data/tcg/packs.json (prices).
extends Node3D

const REACH := 2.2

static var _mats: Dictionary = {}


func _ready() -> void:
	var gold := _mat("gold", Color(1.0, 0.75, 0.3), 0.25, 1.0)
	var body_m := _mat("body", Color(0.32, 0.03, 0.09), 0.4, 0.3)
	_box(Vector3(1.4, 2.3, 0.4), Vector3(0, 1.15, -0.2), body_m)  # the cabinet is a shell round the window recess
	_box(Vector3(0.06, 2.3, 0.42), Vector3(-0.67, 1.15, 0.21), body_m)
	_box(Vector3(0.3, 2.3, 0.42), Vector3(0.55, 1.15, 0.21), body_m)
	_box(Vector3(1.04, 0.55, 0.42), Vector3(-0.12, 0.275, 0.21), body_m)
	_box(Vector3(1.04, 0.25, 0.42), Vector3(-0.12, 2.175, 0.21), body_m)
	_box(Vector3(1.5, 0.12, 0.9), Vector3(0, 2.36, 0), gold)
	_box(Vector3(1.5, 0.1, 0.9), Vector3(0, 0.05, 0), gold)
	# (polish1 item 76) a real vending window: a dark inside lit white from the top, the goods on three shelves behind
	# clear glass: SINGLE PACKS on top, the 5- and 10-pack BUNDLES in the middle, BOXES at the bottom, each with its price
	_box(Vector3(1.04, 1.5, 0.02), Vector3(-0.12, 1.3, 0.05), _mat("inside", Color(0.07, 0.06, 0.08), 0.8, 0.0))
	_box(Vector3(0.02, 1.5, 0.36), Vector3(-0.64, 1.3, 0.23), _mat("inside", Color(0.07, 0.06, 0.08), 0.8, 0.0))
	_box(Vector3(0.02, 1.5, 0.36), Vector3(0.4, 1.3, 0.23), _mat("inside", Color(0.07, 0.06, 0.08), 0.8, 0.0))
	_box(Vector3(1.0, 0.04, 0.3), Vector3(-0.12, 2.03, 0.24), _mat("lamp", Color(1, 1, 1), 0.5, 0.0, Color(1.0, 0.97, 0.9), 2.5))  # the strip light
	var prices: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/packs.json"))["prices"]
	var pack := _textured("pack", "res://assets/tcg/pack.png")
	var carton := _textured("carton", "res://assets/tcg/box.png")
	var shelf_y := [1.68, 1.17, 0.66]  # top, middle, bottom
	for row in 3:
		var y: float = shelf_y[row]
		_box(Vector3(1.0, 0.025, 0.32), Vector3(-0.12, y - 0.015, 0.24), _mat("shelf", Color(0.8, 0.82, 0.85), 0.3, 0.8))
		_box(Vector3(1.0, 0.05, 0.01), Vector3(-0.12, y - 0.03, 0.405), _mat("rail", Color(0.92, 0.92, 0.95), 0.4, 0.0))  # the price rail
	for i in 5:  # top: single packs standing in a row, a coil under each
		var x := -0.52 + float(i) * 0.2
		_quad(pack, Vector2(0.15, 0.24), Vector3(x, shelf_y[0] + 0.12, 0.3))
		_coil(Vector3(x, shelf_y[0] + 0.02, 0.24))
		_tag(str(int(prices["single"])), Vector3(x, shelf_y[0] - 0.03, 0.415))
	for b in 2:  # middle: bundles, packs fanned behind a paper band with the count
		var cx := -0.38 + float(b) * 0.52
		var count := 5 if b == 0 else 10
		var fan := 5 if b == 0 else 7
		for k in fan:
			var off := float(k) - float(fan - 1) * 0.5
			_quad(pack, Vector2(0.15, 0.24), Vector3(cx + off * 0.035, shelf_y[1] + 0.12, 0.28 + float(k) * 0.006), off * 0.08)
		_box(Vector3(0.24, 0.05, 0.005), Vector3(cx, shelf_y[1] + 0.1, 0.33), _mat("band", Color(1.0, 0.85, 0.35), 0.4, 0.2))
		var band := Label3D.new()
		band.text = "%d PACKS" % count
		band.font_size = 32
		band.pixel_size = 0.0018
		band.modulate = Color(0.25, 0.05, 0.1)
		band.position = Vector3(cx, shelf_y[1] + 0.1, 0.336)
		add_child(band)
		_tag(str(int(prices["bundle_%d" % count])), Vector3(cx, shelf_y[1] - 0.03, 0.415))
	for b in 2:  # bottom: boxes of 50, the box picture on the front
		var cx := -0.38 + float(b) * 0.52
		_box(Vector3(0.36, 0.28, 0.24), Vector3(cx, shelf_y[2] + 0.14, 0.24), _mat("carton_side", Color(0.4, 0.06, 0.16), 0.6, 0.0))
		_quad(carton, Vector2(0.35, 0.28), Vector3(cx, shelf_y[2] + 0.14, 0.362))
		_tag(str(int(prices["box"])), Vector3(cx, shelf_y[2] - 0.03, 0.415))
	_box(Vector3(1.06, 1.52, 0.012), Vector3(-0.12, 1.3, 0.43), _mat("glass", Color(0.85, 0.92, 1.0, 0.07), 0.02, 0.0))
	for k in 2:  # light catching the glass
		var streak := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.05 + 0.04 * float(k), 1.4)
		streak.mesh = q
		streak.material_override = _mat("streak", Color(1, 1, 1, 0.1), 0.1, 0.0)
		streak.position = Vector3(-0.42 + float(k) * 0.12, 1.3, 0.437)
		streak.rotation.z = 0.35
		add_child(streak)
	# the side panel: a small screen, the keypad, the chip slot and the pick-up flap
	_box(Vector3(0.2, 0.12, 0.02), Vector3(0.53, 1.82, 0.43), _mat("screen", Color(0.05, 0.1, 0.08), 0.3, 0.0, Color(0.2, 1.0, 0.5), 0.8))
	for r in 3:
		for c in 3:
			_box(Vector3(0.045, 0.035, 0.02), Vector3(0.47 + float(c) * 0.06, 1.62 - float(r) * 0.05, 0.43), _mat("key", Color(0.85, 0.85, 0.88), 0.4, 0.3))
	_box(Vector3(0.12, 0.02, 0.02), Vector3(0.53, 1.4, 0.43), _mat("slot", Color(0.05, 0.05, 0.05), 0.5, 0.0))
	_box(Vector3(0.9, 0.16, 0.04), Vector3(-0.12, 0.3, 0.43), _mat("slot", Color(0.05, 0.05, 0.05), 0.5, 0.0))
	var header := Sprite3D.new()
	if ResourceLoader.exists("res://assets/tcg/logo.png"):
		header.texture = load("res://assets/tcg/logo.png")
	header.pixel_size = 0.0006
	header.position = Vector3(0, 2.75, 0.3)
	add_child(header)
	var title := Label3D.new()
	title.text = "You got me Lobster?  CARDS"
	title.font_size = 64
	title.pixel_size = 0.0032
	title.outline_size = 12
	title.modulate = Color(1.0, 0.85, 0.35)
	title.position = Vector3(0, 2.2, 0.47)
	add_child(title)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b2 := BoxShape3D.new()
	b2.size = Vector3(1.4, 2.3, 0.8)
	shape.shape = b2
	shape.position = Vector3(0, 1.15, 0)
	body.add_child(shape)
	add_child(body)


# Where a player stands to use it (in front of the glass).
func front() -> Vector3:
	return to_global(Vector3(0, 0, 1.1))


func near(pos: Vector3) -> bool:
	var f := front()
	return Vector2(pos.x - f.x, pos.z - f.z).length() < REACH


func _box(box_size: Vector3, pos: Vector3, m: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = box_size
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = m
	n.position = pos
	add_child(n)


static func _mat(key: String, color: Color, rough: float, metal: float, emit := Color.BLACK, strength := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = rough
		m.metallic = metal
		if color.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if strength > 0.0:
			m.emission_enabled = true
			m.emission = emit
			m.emission_energy_multiplier = strength
		_mats[key] = m
	return _mats[key]


# A flat picture (a pack, the box's front) facing out of the machine, tilted by `lean` about its depth axis.
func _quad(m: Material, quad_size: Vector2, pos: Vector3, lean: float = 0.0) -> void:
	var q := QuadMesh.new()
	q.size = quad_size
	var n := MeshInstance3D.new()
	n.mesh = q
	n.material_override = m
	n.position = pos
	n.rotation.z = lean
	add_child(n)


# The spiral that pushes a pack out: a few thin rings one behind the other.
func _coil(at: Vector3) -> void:
	for k in 4:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.045
		ring.outer_radius = 0.052
		ring.rings = 8
		ring.ring_segments = 4
		var n := MeshInstance3D.new()
		n.mesh = ring
		n.material_override = _mat("coil", Color(0.75, 0.76, 0.8), 0.3, 0.9)
		n.position = at + Vector3(0, 0.05, -0.12 + float(k) * 0.06)
		n.rotation.x = PI * 0.5
		add_child(n)


func _tag(text: String, pos: Vector3) -> void:
	var t := Label3D.new()
	t.text = text
	t.font_size = 32
	t.pixel_size = 0.0016
	t.modulate = Color(0.1, 0.1, 0.12)
	t.position = pos
	add_child(t)


static func _textured(key: String, path: String) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		if ResourceLoader.exists(path):
			m.albedo_texture = load(path)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.roughness = 0.5
		_mats[key] = m
	return _mats[key]
