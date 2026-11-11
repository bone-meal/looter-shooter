# Purpose: the enemy character models: skeleton swordsman, skeleton archer, the clockwork bear boss and the Omaha
# wasteland enemies come from assets/models/creatures/ (modelled in Blender by tools/blender/creatures.py and
# wasteland.py); when a skeleton or bear file is missing, and for the old blocky player, they are built here from boxes.
# Dependencies: none. Limbs are pivots named LegL, LegR, ArmL, ArmR (bear also "Key") so game scripts can animate them.
# Models face -Z, feet at y=0, 1.8 m tall.
extends RefCounted

const MODELS := "res://assets/models/creatures/"

static var _materials := {}
static var _styled_materials := {}  # "use + colour" -> Material


static func player() -> Node3D:
	var root := Node3D.new()
	var suit := _material(Color(0.2, 0.5, 0.9))
	var dark := _material(Color(0.12, 0.2, 0.4))
	var skin := _material(Color(0.9, 0.72, 0.6))
	_box(root, Vector3(0.38, 0.52, 0.22), Vector3(0, 1.14, 0), suit)
	_box(root, Vector3(0.24, 0.24, 0.24), Vector3(0, 1.6, 0), skin)
	_box(root, Vector3(0.26, 0.1, 0.26), Vector3(0, 1.76, 0), dark)  # cap
	_limb(root, "LegL", Vector3(-0.1, 0.88, 0), Vector3(0.14, 0.88, 0.16), dark)
	_limb(root, "LegR", Vector3(0.1, 0.88, 0), Vector3(0.14, 0.88, 0.16), dark)
	var arm_l := _limb(root, "ArmL", Vector3(-0.26, 1.38, 0), Vector3(0.11, 0.55, 0.11), suit)
	var arm_r := _limb(root, "ArmR", Vector3(0.26, 1.38, 0), Vector3(0.11, 0.55, 0.11), suit)
	arm_l.rotation_degrees.x = 35.0
	arm_r.rotation_degrees.x = 80.0  # reaches forward to hold the weapon
	return root


# kind is "sword" or "archer". `bone` is the enemy's own material so the whole skeleton can flash when hit.
static func skeleton(kind: String, bone: Material, accent: Color) -> Node3D:
	var modelled := _modelled("skeleton_sword" if kind == "sword" else "skeleton_bow", {"bone": bone}, accent, accent.lerp(Color(0.2, 0.16, 0.12), 0.82))  # worn cloth with a hint of the accent
	if modelled != null:  # same start poses as the code-built skeleton below
		(modelled.get_node("ArmR") as Node3D).rotation_degrees.x = 50.0 if kind == "sword" else 60.0
		if kind != "sword":
			(modelled.get_node("ArmL") as Node3D).rotation_degrees.x = 85.0
		return modelled
	var root := Node3D.new()
	var eye := StandardMaterial3D.new()
	eye.albedo_color = accent
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var cloth := _material(accent.darkened(0.35))
	_box(root, Vector3(0.3, 0.12, 0.16), Vector3(0, 0.92, 0), bone)  # pelvis
	_box(root, Vector3(0.32, 0.22, 0.19), Vector3(0, 0.82, 0), cloth)  # loincloth
	_box(root, Vector3(0.06, 0.42, 0.06), Vector3(0, 1.15, 0.02), bone)  # spine
	for i in 3:
		_box(root, Vector3(0.3 - i * 0.03, 0.04, 0.18), Vector3(0, 1.25 + i * 0.1, 0), bone)  # ribs
	_box(root, Vector3(0.44, 0.05, 0.09), Vector3(0, 1.52, 0), bone)  # shoulders
	_box(root, Vector3(0.2, 0.22, 0.22), Vector3(0, 1.68, 0), bone)  # skull
	_box(root, Vector3(0.13, 0.05, 0.16), Vector3(0, 1.54, -0.02), bone)  # jaw
	_box(root, Vector3(0.045, 0.05, 0.02), Vector3(-0.05, 1.69, -0.115), eye)
	_box(root, Vector3(0.045, 0.05, 0.02), Vector3(0.05, 1.69, -0.115), eye)
	for side in [-1.0, 1.0]:
		var leg := _limb(root, "LegL" if side < 0.0 else "LegR", Vector3(side * 0.09, 0.9, 0), Vector3(0.06, 0.86, 0.06), bone)
		_box(leg, Vector3(0.09, 0.04, 0.17), Vector3(0, -0.86, -0.04), bone)  # foot
	var arm_l := _limb(root, "ArmL", Vector3(-0.23, 1.5, 0), Vector3(0.05, 0.6, 0.05), bone)
	var arm_r := _limb(root, "ArmR", Vector3(0.23, 1.5, 0), Vector3(0.05, 0.6, 0.05), bone)
	if kind == "sword":
		arm_r.rotation_degrees.x = 50.0
		var steel := _material(Color(0.75, 0.78, 0.82))
		_box(arm_r, Vector3(0.04, 0.12, 0.04), Vector3(0, -0.62, 0), _material(Color(0.35, 0.22, 0.12)))  # hilt
		_box(arm_r, Vector3(0.18, 0.03, 0.05), Vector3(0, -0.7, 0), steel)  # crossguard
		_box(arm_r, Vector3(0.05, 0.75, 0.014), Vector3(0, -1.08, 0), steel)  # blade
	else:
		arm_l.rotation_degrees.x = 85.0
		arm_r.rotation_degrees.x = 60.0
		var bow := Node3D.new()
		bow.position = Vector3(-0.23, 1.45, -0.6)
		root.add_child(bow)
		var wood := _material(Color(0.45, 0.3, 0.15))
		_box(bow, Vector3(0.04, 0.14, 0.04), Vector3.ZERO, wood)  # grip
		_box(bow, Vector3(0.03, 0.42, 0.03), Vector3(0, 0.27, 0.04), wood, 18.0)  # upper limb
		_box(bow, Vector3(0.03, 0.42, 0.03), Vector3(0, -0.27, 0.04), wood, -18.0)  # lower limb
		_box(bow, Vector3(0.008, 0.78, 0.008), Vector3(0, 0, 0.13), _material(Color(0.9, 0.9, 0.85)))  # string
	return root


# The Omaha wasteland people and beasts (tools/blender/wasteland.py): `file` is the enemy's "model" id. `body` is the
# enemy's own material and covers the clothes ("body" surfaces) or the skin of bare creatures ("hide"); their "gear"
# and "metal" surfaces are coloured per part by the model itself. Pivots LegL, LegR, ArmL, ArmR.
static func has_wastelander(file: String) -> bool:
	return file != "" and ResourceLoader.exists(MODELS + file + ".gltf")


static func wastelander(file: String, body: Material, accent: Color) -> Node3D:
	return _modelled(file, {"body": body, "hide": body}, accent, accent.lerp(Color(0.22, 0.18, 0.14), 0.7))


# Original boss: a brass wind-up bear. Pivots LegL, LegR, ArmL, ArmR; "Key" is the wind-up key on its back (spun by game/enemy.gd).
static func clockwork_bear(brass_material: Material, glow: Color) -> Node3D:
	var modelled := _modelled("clockwork_bear", {"brass": brass_material}, glow, Color.WHITE)
	if modelled != null:
		return modelled
	var root := Node3D.new()
	var iron := _material(Color(0.22, 0.2, 0.22))
	var plate := _material(Color(0.85, 0.7, 0.35))
	var eye := StandardMaterial3D.new()
	eye.albedo_color = glow
	eye.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box(root, Vector3(0.82, 0.8, 0.55), Vector3(0, 1.15, 0), brass_material)  # torso
	_box(root, Vector3(0.6, 0.55, 0.06), Vector3(0, 1.12, -0.29), plate)  # belly plate
	_box(root, Vector3(0.86, 0.08, 0.58), Vector3(0, 0.78, 0), iron)  # waist band
	_box(root, Vector3(0.86, 0.08, 0.58), Vector3(0, 1.5, 0), iron)  # shoulder band
	for sx in [-0.28, 0.28]:
		for sy in [1.0, 1.25]:
			_box(root, Vector3(0.05, 0.05, 0.03), Vector3(sx, sy, -0.325), iron)  # rivets
	_sphere(root, 0.3, Vector3(0, 1.72, 0), brass_material, Vector3.ONE)  # head
	_sphere(root, 0.11, Vector3(-0.22, 1.94, 0), brass_material, Vector3(1, 1, 0.5))  # ears
	_sphere(root, 0.11, Vector3(0.22, 1.94, 0), brass_material, Vector3(1, 1, 0.5))
	_sphere(root, 0.06, Vector3(-0.22, 1.94, -0.04), iron, Vector3(1, 1, 0.5))
	_sphere(root, 0.06, Vector3(0.22, 1.94, -0.04), iron, Vector3(1, 1, 0.5))
	_box(root, Vector3(0.2, 0.14, 0.18), Vector3(0, 1.64, -0.3), plate)  # snout
	_box(root, Vector3(0.07, 0.05, 0.03), Vector3(0, 1.69, -0.4), iron)  # nose
	_box(root, Vector3(0.14, 0.02, 0.02), Vector3(0, 1.6, -0.395), iron)  # mouth
	_box(root, Vector3(0.07, 0.07, 0.03), Vector3(-0.12, 1.78, -0.27), eye)  # glowing eyes
	_box(root, Vector3(0.07, 0.07, 0.03), Vector3(0.12, 1.78, -0.27), eye)
	var key := Node3D.new()  # wind-up key
	key.name = "Key"
	key.position = Vector3(0, 1.25, 0.3)
	root.add_child(key)
	_box(key, Vector3(0.05, 0.05, 0.18), Vector3(0, 0, 0.09), iron)
	_box(key, Vector3(0.32, 0.06, 0.04), Vector3(0, 0, 0.2), plate)
	for limb in [["LegL", -0.22], ["LegR", 0.22]]:
		_limb(root, limb[0], Vector3(limb[1], 0.8, 0), Vector3(0.3, 0.8, 0.34), brass_material)
	_limb(root, "ArmL", Vector3(-0.56, 1.5, 0), Vector3(0.24, 0.8, 0.26), brass_material)
	_limb(root, "ArmR", Vector3(0.56, 1.5, 0), Vector3(0.24, 0.8, 0.26), brass_material)
	for foot in ["LegL", "LegR"]:
		_box(root.get_node(foot), Vector3(0.34, 0.08, 0.44), Vector3(0, -0.8, -0.05), iron)
	return root


# Glowing add-ons that show a skeleton's element: flames (fire), crystals (ice) or orbiting droplets (toxic).
# Returns a node named "Decor" for the skeleton model (1.8 m tall space); game/enemy.gd animates it.
static func element_decor(element: String, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "Decor"
	var glow := StandardMaterial3D.new()
	glow.albedo_color = tint
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	match element:
		"fire":
			for flame in [Vector3(0, 1.88, 0), Vector3(-0.22, 1.62, 0), Vector3(0.22, 1.62, 0), Vector3(0, 1.2, 0.12)]:
				_cone(root, 0.07, 0.3, flame, glow)
		"ice":
			for crystal in [[Vector3(-0.26, 1.62, 0), 25.0], [Vector3(0.26, 1.62, 0), -25.0], [Vector3(0, 1.88, 0), 0.0]]:
				var n := _cone(root, 0.06, 0.32, crystal[0], glow)
				n.rotation_degrees.z = crystal[1]
		"toxic":
			for k in 4:
				var a := TAU * k / 4.0
				_sphere(root, 0.055, Vector3(cos(a) * 0.38, 1.5 + 0.12 * (k % 2), sin(a) * 0.38), glow, Vector3.ONE)
	return root


static func _cone(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 6
	mesh.rings = 1
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos + Vector3(0, height * 0.5, 0)
	parent.add_child(node)
	return node


static func _sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, scale: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.scale = scale
	parent.add_child(node)


# A creature modelled in Blender (tools/blender/creatures.py), or null when its file is missing (the callers then build
# the old boxes). Surfaces named in `own` get the game's own material (the one enemies tint and flash), which takes over
# the model's textures; "eye" surfaces glow in the accent colour; "cloth" surfaces are tinted.
static func _modelled(file: String, own: Dictionary, glow: Color, cloth: Color) -> Node3D:
	var path := MODELS + file + ".gltf"
	if not ResourceLoader.exists(path):
		return null
	var model := (load(path) as PackedScene).instantiate() as Node3D
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var piece := found as MeshInstance3D
		for surface in piece.mesh.get_surface_count():
			var made := piece.mesh.surface_get_material(surface) as BaseMaterial3D
			if made == null:
				continue
			var id := String(made.resource_name)
			if own.has(id):
				_dress(own[id] as StandardMaterial3D, made)
				piece.set_surface_override_material(surface, own[id])
			elif id == "eye":
				piece.set_surface_override_material(surface, _styled("glow", glow, null))
			elif id == "cloth":
				piece.set_surface_override_material(surface, _styled("cloth", cloth, made))
	return model


# Gives a plain game material the textures of a modelled one, keeping its colour (so tints and hit flashes still show).
static func _dress(target: StandardMaterial3D, made: BaseMaterial3D) -> void:
	if target == null or target.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or target.albedo_texture != null:
		return
	target.albedo_texture = made.albedo_texture
	target.normal_enabled = made.normal_enabled
	target.normal_texture = made.normal_texture
	target.roughness = made.roughness
	target.roughness_texture = made.roughness_texture
	target.roughness_texture_channel = made.roughness_texture_channel
	target.metallic = made.metallic
	target.metallic_texture = made.metallic_texture
	target.metallic_texture_channel = made.metallic_texture_channel


# One shared material per use and colour: "glow" = unshaded eye colour, otherwise a tinted copy of `made`.
static func _styled(use: String, color: Color, made: BaseMaterial3D) -> Material:
	var key := use + color.to_html()
	if not _styled_materials.has(key):
		var material: BaseMaterial3D = StandardMaterial3D.new() if made == null else (made.duplicate() as BaseMaterial3D)
		material.albedo_color = color
		if made == null:
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_styled_materials[key] = material
	return _styled_materials[key]


static func _limb(root: Node3D, limb_name: String, pivot: Vector3, size: Vector3, mat: Material) -> Node3D:
	var node := Node3D.new()
	node.name = limb_name
	node.position = pivot
	root.add_child(node)
	_box(node, size, Vector3(0, -size.y * 0.5, 0), mat)
	return node


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, tilt_x_deg: float = 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	node.rotation_degrees.x = tilt_x_deg
	parent.add_child(node)


static func _material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		_materials[color] = mat
	return _materials[color]
