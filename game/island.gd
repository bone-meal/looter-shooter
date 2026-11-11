# Purpose: builds the starting island: sand that slopes into the sea, a grass patch, the ocean, palm trees, shore rocks
# and plants, and the paintings on posts. The middle (FLAT_RADIUS) is exactly flat at height 0, so everything that
# stands on the island keeps y = 0.
# Dependencies: game/painting_art.gd, game/surface_library.gd, game/ground_blend.gd, game/water_surface.gd,
# game/palm_builder.gd, game/model_library.gd, game/look_props.gd. Static and batched (MultiMeshes, shared materials).
extends RefCounted

const PaintingArt = preload("res://game/painting_art.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")
const GroundBlend = preload("res://game/ground_blend.gd")
const WaterSurface = preload("res://game/water_surface.gd")
const PalmBuilder = preload("res://game/palm_builder.gd")
const ModelLibrary = preload("res://game/model_library.gd")
const LookProps = preload("res://game/look_props.gd")

const CENTER := Vector3(500, 0, 0)
const RADIUS := 14.0          # where the sand meets the sea
const FLAT_RADIUS := 12.0     # flat ground inside this radius
const GROUND_RADIUS := 30.0   # the sea bed ends here
const SEA_LEVEL := -0.4
const BEACH_DROP := 0.1414    # sea bed depth = BEACH_DROP * (metres beyond FLAT_RADIUS) ^ 1.5
const GRASS_RADIUS := 9.0
const TREE_COUNT := 9
const CROW_POS := CENTER + Vector3(-7, 0, 3)

const SAND := Color(0.9, 0.8, 0.55)
const SECTORS := 96
const PAINTING := Vector3(0, 0, -8)
const PAINTING_FANTASY := Vector3(-9, 0, -6)


# Returns {"spawn": Vector3, "painting": Vector3, "painting_fantasy": Vector3} (world positions).
static func build(parent: Node3D) -> Dictionary:
	_ocean(parent)
	_ground(parent)
	_palms(parent)
	_rocks(parent)
	_plants(parent)
	var painting := CENTER + PAINTING
	build_painting(parent, painting, PaintingArt.texture())
	var painting_fantasy := CENTER + PAINTING_FANTASY
	build_painting(parent, painting_fantasy, PaintingArt.wheat_texture())
	return {"spawn": CENTER + Vector3(0, 0.1, 4), "painting": painting, "painting_fantasy": painting_fantasy}


# Ground height at a point given relative to CENTER.
static func height_at(x: float, z: float) -> float:
	var beyond := maxf(sqrt(x * x + z * z) - FLAT_RADIUS, 0.0)
	var dunes := sin(x * 1.3 + z * 0.7) * sin(z * 1.1 - x * 0.4) * 0.05
	return -BEACH_DROP * pow(beyond, 1.5) + dunes * clampf(beyond / 1.5, 0.0, 1.0)


static func _flat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


static func _place(parent: Node3D, mesh: Mesh, surface: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = surface
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _ocean(parent: Node3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	var water := _place(parent, plane, WaterSurface.material(Color(0.1, 0.45, 0.7)), CENTER + Vector3(0, SEA_LEVEL, 0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shallows := CylinderMesh.new()
	shallows.top_radius = RADIUS + 6.0
	shallows.bottom_radius = RADIUS + 6.0
	shallows.height = 0.1
	LookProps.add(_place(parent, shallows, _flat(Color(0.3, 0.75, 0.8)), CENTER + Vector3(0, -0.3, 0)), false)


static func _ground(parent: Node3D) -> void:
	var radii: Array[float] = [0.0]
	while radii[-1] < GROUND_RADIUS - 0.01:
		radii.append(minf(radii[-1] + (2.0 if radii[-1] < FLAT_RADIUS - 0.01 else 0.6), GROUND_RADIUS))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in radii.size() - 1:
		for sector in SECTORS:
			var a0 := TAU * float(sector) / SECTORS
			var a1 := TAU * float(sector + 1) / SECTORS
			var p00 := _ground_point(radii[ring], a0)
			var p01 := _ground_point(radii[ring], a1)
			var p10 := _ground_point(radii[ring + 1], a0)
			var p11 := _ground_point(radii[ring + 1], a1)
			_ground_tri(st, p00, p10, p11)
			if ring > 0:
				_ground_tri(st, p00, p11, p01)
	var ground := st.commit()
	var blend := GroundBlend.material(SAND, Vector2(CENTER.x, CENTER.z), GRASS_RADIUS, SEA_LEVEL)
	_place(parent, ground, blend, CENTER)
	var grass := CylinderMesh.new()
	grass.top_radius = GRASS_RADIUS
	grass.bottom_radius = GRASS_RADIUS
	grass.height = 0.04
	LookProps.add(_place(parent, grass, _flat(Color(0.35, 0.65, 0.3)), CENTER + Vector3(0, 0.02, 0)), false)

	var body := StaticBody3D.new()
	body.position = CENTER
	var shape := CollisionShape3D.new()
	shape.shape = ground.create_trimesh_shape()
	body.add_child(shape)
	parent.add_child(body)


static func _ground_point(radius: float, angle: float) -> Vector3:
	var x := cos(angle) * radius
	var z := sin(angle) * radius
	return Vector3(x, height_at(x, z), z)


static func _ground_normal(p: Vector3) -> Vector3:
	var e := 0.1
	return Vector3(height_at(p.x - e, p.z) - height_at(p.x + e, p.z), 2.0 * e, height_at(p.x, p.z - e) - height_at(p.x, p.z + e)).normalized()


static func _ground_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var pts := [a, b, c]
	if (b - a).cross(c - a).y > 0.0:
		pts = [a, c, b]  # Godot front faces are clockwise
	for p: Vector3 in pts:
		st.set_normal(_ground_normal(p))
		st.add_vertex(p)


# Where the palms stand (relative to CENTER): a ring around the grass, kept clear of the first painting.
static func _palm_spots() -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for i in TREE_COUNT:
		var angle := TAU * float(i) / TREE_COUNT + 0.3
		var r := 9.0 + float(i % 3) * 1.2
		var spot := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		if spot.distance_to(PAINTING) < 4.0:
			spot += Vector3(0, 0, 5)
		spots.append(spot)
	return spots


static func _palms(parent: Node3D) -> void:
	# Flat look: a pole and a ball.
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.18
	trunk_mesh.bottom_radius = 0.28
	trunk_mesh.height = 5.0
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 1.8
	crown_mesh.height = 1.2
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var palms: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for spot: Vector3 in _palm_spots():
		trunks.append(Transform3D(Basis(), CENTER + spot + Vector3(0, 2.5, 0)))
		crowns.append(Transform3D(Basis(), CENTER + spot + Vector3(0, 5.1, 0)))
		var tall := rng.randf_range(0.85, 1.25)
		var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(tall, tall, tall))
		palms.append(Transform3D(turn, CENTER + spot))
	LookProps.add(_field(parent, trunk_mesh, trunks, _flat(Color(0.5, 0.35, 0.2))), false)
	LookProps.add(_field(parent, crown_mesh, crowns, _flat(Color(0.2, 0.55, 0.25))), false)
	# Textured look: curved trunks with frond crowns.
	var bark := SurfaceLibrary.material("palm_bark", Color(0.5, 0.35, 0.2))
	LookProps.add(_field(parent, PalmBuilder.mesh(bark), palms, null), true)


# Boulders at the waterline (textured look only), each with a simple round collider.
static func _rocks(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var body := StaticBody3D.new()
	body.position = CENTER
	parent.add_child(body)
	LookProps.add(body, true)
	# [model, node, how many, smallest size, largest size, real radius of the model in metres]
	for kind: Array in [["namaqualand_boulder_04", "boulder_04", 3, 0.45, 0.9, 1.25], ["rock_09", "rock_09_LOD0", 8, 5.0, 16.0, 0.07]]:
		var rock := ModelLibrary.mesh(String(kind[0]), String(kind[1]))
		if rock == null:
			continue
		var reach := float(kind[5])
		var xforms: Array[Transform3D] = []
		for i in int(kind[2]):
			var angle := rng.randf_range(0.0, TAU)
			var r := rng.randf_range(RADIUS - 1.6, RADIUS + 2.2)
			var big := rng.randf_range(float(kind[3]), float(kind[4]))
			var spot := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
			if spot.distance_to(PAINTING) < 5.0 or spot.distance_to(PAINTING_FANTASY) < 5.0:
				continue
			spot.y = height_at(spot.x, spot.z) - 0.25 * big * reach  # sunk into the sand a little
			var turn := Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, TAU), rng.randf_range(-0.2, 0.2)))
			xforms.append(Transform3D(turn * Basis.from_scale(Vector3(big, big, big)), spot))
			var ball := SphereShape3D.new()
			ball.radius = big * reach * 0.8
			var shape := CollisionShape3D.new()
			shape.shape = ball
			shape.position = spot + Vector3(0, ball.radius * 0.5, 0)
			body.add_child(shape)
		_field(body, rock, xforms, null)


# Ferns and broad-leaf plants around the grass edge and the palm feet (textured look only).
static func _plants(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var feet := _palm_spots()
	# [model, plants of each variant, smallest size, largest size]
	for kind: Array in [["fern_02", 9, 0.9, 1.6], ["calathea_orbifolia_01", 4, 1.0, 1.8], ["anthurium_botany_01", 2, 0.9, 1.4]]:
		for entry: Array in ModelLibrary.meshes(String(kind[0])):
			var xforms: Array[Transform3D] = []
			for i in int(kind[1]):
				var spot := Vector3.ZERO
				if rng.randf() < 0.5:
					var away := rng.randf_range(0.5, 1.6)
					var around := rng.randf_range(0.0, TAU)
					spot = feet[rng.randi() % feet.size()] + Vector3(cos(around) * away, 0.0, sin(around) * away)
				else:
					var angle := rng.randf_range(0.0, TAU)
					var r := rng.randf_range(GRASS_RADIUS - 2.5, GRASS_RADIUS + 1.5)
					spot = Vector3(cos(angle) * r, 0.0, sin(angle) * r)
				if spot.distance_to(PAINTING) < 3.5 or spot.distance_to(PAINTING_FANTASY) < 3.5 or spot.length() > FLAT_RADIUS:
					continue
				var big := rng.randf_range(float(kind[2]), float(kind[3]))
				var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(big, big, big))
				xforms.append(Transform3D(turn, CENTER + spot))
			var field := _field(parent, entry[1] as Mesh, xforms, null)
			field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			LookProps.add_scatter(field)


# One MultiMesh for many copies of a mesh. surface = null keeps the mesh's own materials.
static func _field(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], surface: Material) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.material_override = surface
	parent.add_child(inst)
	return inst


# A framed painting on two posts at `at` (also used for the way home inside a painting's world).
static func build_painting(parent: Node3D, at: Vector3, texture: Texture2D) -> void:
	var post_wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
	for side: float in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(0.25, 3.6, 0.25)
		_place(parent, post, post_wood, at + Vector3(side * 2.4, 1.8, 0))
	var frame := BoxMesh.new()
	frame.size = Vector3(5.0, 3.6, 0.2)
	_place(parent, frame, SurfaceLibrary.material("painting_frame", Color(0.55, 0.4, 0.15)), at + Vector3(0, 2.3, 0))
	var canvas := QuadMesh.new()
	canvas.size = Vector2(4.6, 3.2)
	var art := StandardMaterial3D.new()
	art.albedo_texture = texture
	art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	art.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_place(parent, canvas, art, at + Vector3(0, 2.3, 0.11))

	var body := StaticBody3D.new()
	body.position = at + Vector3(0, 1.8, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.6, 0.4)
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
