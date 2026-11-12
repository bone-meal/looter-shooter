# Purpose: a wall buy: a tarred board on two posts with a gun's outline and its price in chalk. Draws only; the
# session sells the gun (or its ammo) to whoever presses interact at it.
# Dependencies: core/data_store.gd, game/surface_library.gd (wood). Data: data/chalk_guns.json + assets/ui/chalk_guns.png
# (the outlines, made by tools/make_chalk_guns.py). Set `gun` and `price` before add_child.
extends Node3D

const DataStore = preload("res://core/data_store.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")

const REACH := 2.8  # metres from which it can be bought at
const BOARD := Vector3(2.0, 1.3, 0.08)
const MID := 1.55  # height of the board's middle
const TAR := Color(0.11, 0.1, 0.09)
const CHALK := Color(0.96, 0.95, 0.9)

var gun := ""  # body id (data/weapons.json)
var price := 0

static var _sheet: Dictionary
static var _chalk: Texture2D


func _ready() -> void:
	if _sheet.is_empty():
		_sheet = DataStore.load_json("res://data/chalk_guns.json")
		_chalk = load("res://assets/ui/chalk_guns.png")
	var tools: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new()]
	for tool in tools:
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plank := BoxMesh.new()
	plank.size = BOARD
	tools[1].append_from(plank, 0, Transform3D(Basis(), Vector3(0, MID, 0)))
	var post := BoxMesh.new()
	post.size = Vector3(0.14, MID + BOARD.y * 0.5 + 0.1, 0.14)
	for side: float in [-1.0, 1.0]:
		tools[0].append_from(post, 0, Transform3D(Basis(), Vector3(side * (BOARD.x * 0.5 - 0.12), post.size.y * 0.5, -0.11)))
	var tar := StandardMaterial3D.new()
	tar.albedo_color = TAR
	tar.roughness = 0.95
	var mesh := ArrayMesh.new()
	tools[0].commit(mesh)
	tools[1].commit(mesh)
	mesh.surface_set_material(0, SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15)))
	mesh.surface_set_material(1, tar)
	var stand := MeshInstance3D.new()
	stand.mesh = mesh
	add_child(stand)
	# the outline: one cell of the sheet
	var columns := int(_sheet["columns"])
	var rows := int(_sheet["rows"])
	var cell := int((_sheet["cells"] as Dictionary).get(gun, 0))
	var chalk := StandardMaterial3D.new()
	chalk.albedo_texture = _chalk
	chalk.albedo_color = CHALK
	chalk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	chalk.uv1_scale = Vector3(1.0 / float(columns), 1.0 / float(rows), 1.0)
	chalk.uv1_offset = Vector3(float(cell % columns) / float(columns), float(floori(float(cell) / float(columns))) / float(rows), 0.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 0.9)
	var outline := MeshInstance3D.new()
	outline.mesh = quad
	outline.material_override = chalk
	outline.position = Vector3(0, MID + 0.14, BOARD.z * 0.5 + 0.005)
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outline)
	var tag := Label3D.new()
	tag.text = str(price)
	tag.font = load("res://assets/fonts/Chewy-Regular.ttf")
	tag.font_size = 64
	tag.pixel_size = 0.0042
	tag.modulate = Color(CHALK.r, CHALK.g, CHALK.b, 0.9)
	tag.outline_size = 0
	tag.position = Vector3(0, MID - 0.47, BOARD.z * 0.5 + 0.006)
	add_child(tag)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BOARD.x, MID + BOARD.y * 0.5, 0.3)
	shape.shape = box
	shape.position = Vector3(0, box.size.y * 0.5, -0.05)
	body.add_child(shape)
	add_child(body)
