# Purpose: the card vending machine of "You got me Lobster?" in the casino: a tall lit cabinet with a glass front, three
# shelves of packs (single packs, bundles, a box) in the game's colours, the logo on a glowing header, and a small odds
# board beside it. F in front of it opens game/tcg/vendor_screen.gd. Primitive meshes, shared materials, one light.
# Dependencies: assets/tcg/logo.png.
extends Node3D

const REACH := 2.2

static var _mats: Dictionary = {}


func _ready() -> void:
	_box(Vector3(1.4, 2.3, 0.8), Vector3(0, 1.15, 0), _mat("body", Color(0.32, 0.03, 0.09), 0.4, 0.3))
	_box(Vector3(1.5, 0.12, 0.9), Vector3(0, 2.36, 0), _mat("gold", Color(1.0, 0.75, 0.3), 0.25, 1.0))
	_box(Vector3(1.5, 0.1, 0.9), Vector3(0, 0.05, 0), _mat("gold", Color(1.0, 0.75, 0.3), 0.25, 1.0))
	_box(Vector3(1.1, 1.35, 0.04), Vector3(0, 1.25, 0.41), _mat("back", Color(0.06, 0.02, 0.05), 0.6, 0.0, Color(0.25, 0.05, 0.12), 0.6))
	var colors := [Color(0.2, 0.55, 1.0), Color(0.9, 0.2, 0.6), Color(1.0, 0.75, 0.25)]
	for row in 3:  # shelves with standing packs: singles, bundles, the box
		var y := 0.72 + float(row) * 0.42
		_box(Vector3(1.1, 0.03, 0.3), Vector3(0, y - 0.02, 0.32), _mat("gold", Color(1.0, 0.75, 0.3), 0.25, 1.0))
		var n := 6 if row == 0 else (4 if row == 1 else 2)
		for i in n:
			var w := 0.12 if row < 2 else 0.4
			_box(Vector3(w, 0.26, 0.05), Vector3(-0.45 + (float(i) + 0.5) * (0.9 / float(n)), y + 0.13, 0.33), _mat("pack%d" % row, colors[row], 0.3, 0.2, colors[row], 0.4))
	_box(Vector3(1.12, 1.38, 0.02), Vector3(0, 1.25, 0.44), _mat("glass", Color(0.8, 0.9, 1.0, 0.18), 0.05, 0.0))
	_box(Vector3(0.5, 0.12, 0.06), Vector3(0, 0.38, 0.42), _mat("slot", Color(0.05, 0.05, 0.05), 0.5, 0.0))
	var header := Sprite3D.new()
	if ResourceLoader.exists("res://assets/tcg/logo.png"):
		header.texture = load("res://assets/tcg/logo.png")
	header.pixel_size = 0.0006
	header.position = Vector3(0, 2.75, 0.3)
	add_child(header)
	var title := Label3D.new()
	title.text = "You got me Lobster?\nCARDS"
	title.font_size = 64
	title.pixel_size = 0.004
	title.outline_size = 12
	title.modulate = Color(1.0, 0.85, 0.35)
	title.position = Vector3(0, 2.2, 0.47)
	add_child(title)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.45, 0.7)
	glow.light_energy = 1.2
	glow.omni_range = 3.0
	glow.position = Vector3(0, 1.4, 0.9)
	glow.shadow_enabled = false
	add_child(glow)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(1.4, 2.3, 0.8)
	shape.shape = b
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
