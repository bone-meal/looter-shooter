# Purpose: the held-weapon models by weapon ID: modelled glTF files from assets/models/weapons/ (made in Blender by
# tools/blender/weapons.py) or, when a file is missing, the old flat-colour boxes and cylinders built here.
# Dependencies: none. Models point down -Z; game/player.gd parents them to the head. Node names the game looks for:
# "Slide" (moves back when the pistol fires), "Sight" (height the eye lines up with when aiming), "Support" (left-hand point on long guns).
extends RefCounted

const SLIDE := Color(0.62, 0.64, 0.68)
const DARK := Color(0.14, 0.14, 0.16)
const FRAME := Color(0.3, 0.3, 0.33)
const OLIVE := Color(0.24, 0.28, 0.23)
const STEEL := Color(0.2, 0.21, 0.23)
const LENS := Color(0.25, 0.5, 0.9)
const WOOD := Color(0.45, 0.27, 0.12)
const BLACK := Color(0.09, 0.09, 0.1)
const WARHEAD := Color(0.85, 0.4, 0.12)

const MODELS := "res://assets/models/weapons/"

static var _materials := {}


static func build(weapon_id: String) -> Node3D:
	var coded := _coded(weapon_id)
	var path := MODELS + weapon_id + ".gltf"
	if not ResourceLoader.exists(path):
		return coded
	var model := (load(path) as PackedScene).instantiate() as Node3D
	model.position = coded.position  # same hold position and size as the code-built gun it replaces
	model.scale = coded.scale
	coded.free()
	return model


static func _coded(weapon_id: String) -> Node3D:
	match weapon_id:
		"pistol_basic":
			return _deagle()
		"sniper_basic":
			return _sniper()
		"ak47":
			return _ak47()
		"m16":
			return _m16()
		"m60":
			return _m60()
		"shotgun_double":
			return _shotgun()
		"rocket_launcher":
			return _rocket_launcher()
		"grenade_launcher":
			return _grenade_launcher()
	return Node3D.new()


# Chunky Desert-Eagle-style pistol: long slide, heavy frame, angled grip.
static func _deagle() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.22, -0.2, -0.45)
	var slide := Node3D.new()  # moves back when firing (see game/player.gd)
	slide.name = "Slide"
	root.add_child(slide)
	_box(slide, Vector3(0.045, 0.06, 0.28), Vector3(0, 0.02, -0.14), SLIDE)
	_box(slide, Vector3(0.02, 0.03, 0.05), Vector3(0, 0.018, -0.3), DARK)  # muzzle
	_box(slide, Vector3(0.012, 0.008, 0.24), Vector3(0, 0.054, -0.14), DARK)  # slide rib
	_box(slide, Vector3(0.016, 0.014, 0.01), Vector3(0, 0.06, -0.005), DARK)  # rear sight
	_box(slide, Vector3(0.012, 0.014, 0.01), Vector3(0, 0.06, -0.27), DARK)  # front sight
	_box(root, Vector3(0.042, 0.04, 0.2), Vector3(0, -0.028, -0.11), FRAME)  # frame
	_box(root, Vector3(0.036, 0.012, 0.075), Vector3(0, -0.055, -0.1), DARK)  # trigger guard
	_box(root, Vector3(0.012, 0.03, 0.012), Vector3(0, -0.04, -0.09), DARK)  # trigger
	_box(root, Vector3(0.044, 0.125, 0.065), Vector3(0, -0.095, -0.015), DARK, -15.0)  # grip
	return root


# Bolt-action sniper: long barrel, scope, stock, magazine, bolt handle.
static func _sniper() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.2, -0.18, -0.4)
	root.scale = Vector3(0.5, 0.5, 0.5)
	_box(root, Vector3(0.05, 0.08, 0.5), Vector3(0, 0, -0.05), OLIVE)  # receiver
	_cyl(root, 0.016, 0.75, Vector3(0, 0.01, -0.67), STEEL)  # barrel
	_cyl(root, 0.025, 0.08, Vector3(0, 0.01, -1.08), DARK)  # muzzle brake
	_box(root, Vector3(0.045, 0.11, 0.3), Vector3(0, -0.02, 0.35), OLIVE)  # stock
	_box(root, Vector3(0.04, 0.03, 0.2), Vector3(0, 0.06, 0.32), OLIVE)  # cheek rest
	_box(root, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.09, 0.14), DARK, -12.0)  # grip
	_box(root, Vector3(0.04, 0.1, 0.07), Vector3(0, -0.08, -0.04), DARK)  # magazine
	_box(root, Vector3(0.02, 0.04, 0.03), Vector3(0, 0.06, -0.12), DARK)  # scope mount front
	_box(root, Vector3(0.02, 0.04, 0.03), Vector3(0, 0.06, 0.08), DARK)  # scope mount rear
	_cyl(root, 0.028, 0.34, Vector3(0, 0.11, -0.02), STEEL)  # scope tube
	_cyl(root, 0.04, 0.09, Vector3(0, 0.11, -0.22), STEEL)  # scope front bell
	_cyl(root, 0.034, 0.06, Vector3(0, 0.11, 0.16), STEEL)  # scope eyepiece
	_cyl(root, 0.036, 0.006, Vector3(0, 0.11, -0.268), LENS)  # lens
	_cyl(root, 0.008, 0.06, Vector3(0.05, 0.025, 0.04), DARK, true)  # bolt handle
	_cyl(root, 0.014, 0.014, Vector3(0.082, 0.025, 0.04), DARK, true)  # bolt knob
	return root


# AK-47: wooden stock and handguard, gas tube, curved magazine.
static func _ak47() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.2, -0.2, -0.4)
	root.scale = Vector3.ONE * 0.55
	_box(root, Vector3(0.06, 0.09, 0.4), Vector3(0, 0, 0), STEEL)  # receiver
	_box(root, Vector3(0.05, 0.03, 0.38), Vector3(0, 0.06, 0), FRAME)  # dust cover
	_cyl(root, 0.014, 0.5, Vector3(0, 0.0, -0.45), STEEL)  # barrel
	_cyl(root, 0.016, 0.4, Vector3(0, 0.045, -0.42), STEEL)  # gas tube
	_box(root, Vector3(0.055, 0.07, 0.28), Vector3(0, -0.005, -0.33), WOOD)  # handguard
	_box(root, Vector3(0.01, 0.04, 0.01), Vector3(0, 0.06, -0.68), DARK)  # front sight
	_box(root, Vector3(0.05, 0.1, 0.32), Vector3(0, -0.02, 0.34), WOOD)  # stock
	_box(root, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.09, 0.12), WOOD, -15.0)  # grip
	_box(root, Vector3(0.04, 0.2, 0.07), Vector3(0, -0.15, -0.08), DARK, 14.0)  # curved magazine
	_sight(root, 0.08)
	return root


# M16: black polymer rifle, carry handle, straight magazine, flash hider.
static func _m16() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.2, -0.2, -0.4)
	root.scale = Vector3.ONE * 0.55
	_box(root, Vector3(0.055, 0.1, 0.38), Vector3(0, 0, 0), BLACK)  # receiver
	_box(root, Vector3(0.03, 0.05, 0.2), Vector3(0, 0.1, 0.02), BLACK)  # carry handle
	_box(root, Vector3(0.012, 0.03, 0.012), Vector3(0, 0.13, -0.12), DARK)  # sight
	_cyl(root, 0.013, 0.55, Vector3(0, 0.0, -0.47), STEEL)  # barrel
	_cyl(root, 0.03, 0.3, Vector3(0, 0.0, -0.33), BLACK)  # handguard
	_cyl(root, 0.02, 0.08, Vector3(0, 0.0, -0.78), DARK)  # flash hider
	_box(root, Vector3(0.05, 0.1, 0.28), Vector3(0, -0.02, 0.32), BLACK)  # stock
	_box(root, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.09, 0.12), BLACK, -15.0)  # grip
	_box(root, Vector3(0.04, 0.16, 0.07), Vector3(0, -0.13, -0.06), DARK)  # magazine
	_sight(root, 0.14)
	return root


# M60: heavy machine gun with a bipod, shrouded barrel, belt box and carry handle.
static func _m60() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.22, -0.22, -0.4)
	root.scale = Vector3.ONE * 0.5
	_box(root, Vector3(0.08, 0.12, 0.5), Vector3(0, 0, 0), STEEL)  # receiver
	_cyl(root, 0.02, 0.6, Vector3(0, 0.0, -0.55), DARK)  # barrel
	_cyl(root, 0.032, 0.35, Vector3(0, 0.0, -0.42), FRAME)  # barrel shroud
	_box(root, Vector3(0.02, 0.04, 0.3), Vector3(0, 0.1, -0.15), DARK)  # carry handle
	_box(root, Vector3(0.14, 0.14, 0.12), Vector3(-0.1, -0.14, 0.0), OLIVE)  # ammo box
	_box(root, Vector3(0.02, 0.1, 0.1), Vector3(-0.04, -0.05, -0.02), SLIDE)  # belt
	_box(root, Vector3(0.012, 0.14, 0.012), Vector3(-0.04, -0.1, -0.7), DARK, 20.0)  # bipod leg
	_box(root, Vector3(0.012, 0.14, 0.012), Vector3(0.04, -0.1, -0.7), DARK, 20.0)
	_box(root, Vector3(0.06, 0.12, 0.3), Vector3(0, -0.02, 0.4), WOOD)  # stock
	_box(root, Vector3(0.045, 0.11, 0.05), Vector3(0, -0.09, 0.14), DARK, -15.0)  # grip
	_sight(root, 0.12)
	return root


# Double-barrel shotgun: side-by-side barrels, wooden fore-end and stock.
static func _shotgun() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.2, -0.2, -0.4)
	root.scale = Vector3.ONE * 0.6
	_cyl(root, 0.017, 0.65, Vector3(-0.019, 0.01, -0.4), STEEL)  # left barrel
	_cyl(root, 0.017, 0.65, Vector3(0.019, 0.01, -0.4), STEEL)  # right barrel
	_box(root, Vector3(0.012, 0.012, 0.65), Vector3(0, 0.035, -0.4), DARK)  # rib
	_box(root, Vector3(0.075, 0.1, 0.14), Vector3(0, 0, 0), FRAME)  # breech
	_box(root, Vector3(0.02, 0.012, 0.05), Vector3(0, 0.056, 0.03), SLIDE)  # top lever
	_box(root, Vector3(0.07, 0.05, 0.2), Vector3(0, -0.035, -0.28), WOOD)  # fore-end
	_box(root, Vector3(0.05, 0.12, 0.32), Vector3(0, -0.035, 0.25), WOOD, 8.0)  # stock
	_sight(root, 0.045)
	return root


# Rocket launcher: big shoulder tube with flared ends and a visible warhead.
static func _rocket_launcher() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.24, -0.22, -0.4)
	root.scale = Vector3.ONE * 0.45
	_cyl(root, 0.07, 1.0, Vector3(0, 0.02, -0.1), OLIVE)  # tube
	_cyl(root, 0.09, 0.08, Vector3(0, 0.02, -0.62), STEEL)  # front flare
	_cyl(root, 0.085, 0.08, Vector3(0, 0.02, 0.42), STEEL)  # rear flare
	_cyl(root, 0.05, 0.1, Vector3(0, 0.02, -0.68), WARHEAD)  # warhead
	_box(root, Vector3(0.04, 0.12, 0.05), Vector3(0, -0.1, 0.05), DARK, -15.0)  # grip
	_box(root, Vector3(0.03, 0.06, 0.03), Vector3(0, 0.11, -0.1), DARK)  # sight
	_sight(root, 0.14)
	return root


# Grenade launcher: stubby barrel over a chunky revolving drum, with a stock.
static func _grenade_launcher() -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(0.22, -0.2, -0.4)
	root.scale = Vector3.ONE * 0.65
	_cyl(root, 0.06, 0.15, Vector3(0, 0, -0.05), STEEL)  # drum
	_cyl(root, 0.032, 0.35, Vector3(0, 0.0, -0.3), DARK)  # barrel
	_box(root, Vector3(0.06, 0.05, 0.14), Vector3(0, -0.06, -0.28), WOOD)  # handguard
	_box(root, Vector3(0.05, 0.1, 0.25), Vector3(0, -0.02, 0.25), WOOD)  # stock
	_box(root, Vector3(0.04, 0.11, 0.05), Vector3(0, -0.09, 0.1), DARK, -15.0)  # grip
	_box(root, Vector3(0.012, 0.04, 0.012), Vector3(0, 0.07, -0.42), DARK)  # sight
	_sight(root, 0.09)
	return root


# Marks where the sights are (root-local). game/player.gd moves the gun so this point sits on the crosshair when aiming.
static func _sight(root: Node3D, height: float) -> void:
	var marker := Node3D.new()
	marker.name = "Sight"
	marker.position = Vector3(0, height, 0)
	root.add_child(marker)


static func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color, tilt_x_deg: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	node.rotation_degrees.x = tilt_x_deg
	root.add_child(node)


# Cylinder along Z (or along X when sideways is true).
static func _cyl(root: Node3D, radius: float, length: float, pos: Vector3, color: Color, sideways: bool = false) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 10
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	node.position = pos
	if sideways:
		node.rotation_degrees.z = 90.0
	else:
		node.rotation_degrees.x = 90.0
	root.add_child(node)


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_materials[color] = mat
	return _materials[color]
