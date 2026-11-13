# Purpose: builds the islands of data/archipelago.json: for each one sand that slopes into the sea and a grass patch;
# the ocean, palm trees, shore rocks and plants; the ways between the islands (plank bridges and sandbars) with the
# debris across each; and the paintings on posts. The flat part of every island is exactly height 0, so everything
# that stands on an island keeps y = 0.
# Dependencies: core/archipelago.gd (where everything is; the session passes its own so both agree), core/data_store.gd,
# game/debris_pile.gd, game/painting_art.gd, game/surface_library.gd, game/ground_blend.gd, game/water_surface.gd,
# game/palm_builder.gd, game/model_library.gd, game/look_props.gd. Static and batched (MultiMeshes, shared materials).
extends RefCounted

const Archipelago = preload("res://core/archipelago.gd")
const DataStore = preload("res://core/data_store.gd")
const DebrisPile = preload("res://game/debris_pile.gd")
const PaintingArt = preload("res://game/painting_art.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")
const GroundBlend = preload("res://game/ground_blend.gd")
const WaterSurface = preload("res://game/water_surface.gd")
const PalmBuilder = preload("res://game/palm_builder.gd")
const ModelLibrary = preload("res://game/model_library.gd")
const LookProps = preload("res://game/look_props.gd")

const CENTER := Vector3(500, 0, 0)  # the middle of the spawn island in the world
const CROW_POS := CENTER + Vector3(-7, 0, 3)
const SAND := Color(0.9, 0.8, 0.55)
const SECTORS := 96
const KEEP_CLEAR := 5.0  # no palm, rock or plant this near a painting, the spawn or the end of a bridge
const POST_GAP := 4.0  # metres between the posts of a plank bridge


# Returns {"spawn", "painting", "painting_fantasy": world positions, "debris": one game/debris_pile.gd per bridge}.
static func build(parent: Node3D, land: Archipelago = null) -> Dictionary:
	if land == null:
		land = Archipelago.new(DataStore.load_json("res://data/archipelago.json"))
	var arena: Dictionary = land.place_of("painting_arena")
	var fantasy: Dictionary = land.place_of("painting_fantasy")
	var spawn: Vector2 = land.place_of("spawn")["at"]
	var clear: Array[Vector2] = [arena["at"], fantasy["at"], spawn]
	for board: Dictionary in land.wall_buys:
		clear.append(board["at"])
	clear.append_array(land.keep_clear)
	for hut: Dictionary in land.shelters:
		for corner: Vector2 in [Vector2.ZERO, Vector2(3, 2.4), Vector2(-3, 2.4), Vector2(3, -2.4), Vector2(-3, -2.4), Vector2(0, 5)]:
			clear.append((hut["at"] as Vector2) + corner.rotated(-float(hut["yaw"])))
	for bridge: Dictionary in land.bridges:
		clear.append(bridge["a"])
		clear.append(bridge["b"])
	_ocean(parent, land)
	var patches := PackedVector3Array()
	for isle: Dictionary in land.islands:
		patches.append(Vector3(CENTER.x + (isle["at"] as Vector2).x, CENTER.z + (isle["at"] as Vector2).y, float(isle["grass"])))
	var blend := GroundBlend.material(SAND, patches, land.sea_level)
	for i in land.islands.size():
		_ground(parent, land, i, blend)
	_palms(parent, land, clear)
	_rocks(parent, land, clear)
	_plants(parent, land, clear)
	var debris: Array = []
	for i in land.bridges.size():
		debris.append(_bridge(parent, land, i, blend))
	var painting := _world(arena["at"])
	build_painting(parent, painting, PaintingArt.texture(), float(arena["yaw"]))
	var painting_fantasy := _world(fantasy["at"])
	build_painting(parent, painting_fantasy, PaintingArt.wheat_texture(), float(fantasy["yaw"]))
	return {"spawn": _world(spawn) + Vector3(0, 0.1, 0), "painting": painting, "painting_fantasy": painting_fantasy, "debris": debris}


# A land spot (x, z from the spawn island's middle) as a world position on flat ground.
static func _world(at: Vector2) -> Vector3:
	return CENTER + Vector3(at.x, 0.0, at.y)


static func _near_any(spot: Vector2, clear: Array[Vector2], within: float) -> bool:
	for other: Vector2 in clear:
		if spot.distance_to(other) < within:
			return true
	return false


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


static func _ocean(parent: Node3D, land: Archipelago) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(700, 700)
	var water := _place(parent, plane, WaterSurface.material(Color(0.1, 0.45, 0.7)), _world(land.middle()) + Vector3(0, land.sea_level, 0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for isle: Dictionary in land.islands:
		var shallows := CylinderMesh.new()
		shallows.top_radius = float(isle["radius"]) + 6.0
		shallows.bottom_radius = shallows.top_radius
		shallows.height = 0.1
		LookProps.add(_place(parent, shallows, _flat(Color(0.3, 0.75, 0.8)), _world(isle["at"]) + Vector3(0, -0.3, 0)), false)


# One island's sand: rings of triangles out to where its sea bed ends, with a collider.
static func _ground(parent: Node3D, land: Archipelago, index: int, blend: Material) -> void:
	var isle: Dictionary = land.islands[index]
	var at: Vector2 = isle["at"]
	var flat := float(isle["flat"])
	var edge := flat + float(land.cfg["sea_bed"])
	var radii: Array[float] = [0.0]
	while radii[-1] < edge - 0.01:
		radii.append(minf(radii[-1] + (minf(4.0, flat - radii[-1]) if radii[-1] < flat - 0.01 else 0.6), edge))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in radii.size() - 1:
		for sector in SECTORS:
			var a0 := TAU * float(sector) / SECTORS
			var a1 := TAU * float(sector + 1) / SECTORS
			var p00 := _ground_point(land, index, at, radii[ring], a0)
			var p01 := _ground_point(land, index, at, radii[ring], a1)
			var p10 := _ground_point(land, index, at, radii[ring + 1], a0)
			var p11 := _ground_point(land, index, at, radii[ring + 1], a1)
			_ground_tri(st, land, index, at, p00, p10, p11)
			if ring > 0:
				_ground_tri(st, land, index, at, p00, p11, p01)
	var ground := st.commit()
	_place(parent, ground, blend, _world(at))
	var grass := CylinderMesh.new()
	grass.top_radius = float(isle["grass"])
	grass.bottom_radius = grass.top_radius
	grass.height = 0.04
	LookProps.add(_place(parent, grass, _flat(Color(0.35, 0.65, 0.3)), _world(at) + Vector3(0, 0.02, 0)), false)
	var body := StaticBody3D.new()
	body.position = _world(at)
	var shape := CollisionShape3D.new()
	shape.shape = ground.create_trimesh_shape()
	body.add_child(shape)
	parent.add_child(body)


# A point of an island's ground, relative to that island's middle.
static func _ground_point(land: Archipelago, index: int, at: Vector2, radius: float, angle: float) -> Vector3:
	var x := cos(angle) * radius
	var z := sin(angle) * radius
	return Vector3(x, land.island_height(index, at.x + x, at.y + z), z)


static func _ground_normal(land: Archipelago, index: int, at: Vector2, p: Vector3) -> Vector3:
	var e := 0.1
	var x := at.x + p.x
	var z := at.y + p.z
	return Vector3(land.island_height(index, x - e, z) - land.island_height(index, x + e, z), 2.0 * e, land.island_height(index, x, z - e) - land.island_height(index, x, z + e)).normalized()


static func _ground_tri(st: SurfaceTool, land: Archipelago, index: int, at: Vector2, a: Vector3, b: Vector3, c: Vector3) -> void:
	var pts := [a, b, c]
	if (b - a).cross(c - a).y > 0.0:
		pts = [a, c, b]  # Godot front faces are clockwise
	for p: Vector3 in pts:
		st.set_normal(_ground_normal(land, index, at, p))
		st.add_vertex(p)


# Where the palms stand ([x, z] from the spawn island's middle): scattered between each island's grass edge and its beach.
static func _palm_spots(land: Archipelago, clear: Array[Vector2]) -> Array[Vector2]:
	var spots: Array[Vector2] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for isle: Dictionary in land.islands:
		var count := int(isle["palms"])
		for i in count:
			var angle := TAU * float(i) / float(count) + rng.randf_range(-0.2, 0.2)
			var r := rng.randf_range(float(isle["grass"]) * 0.7, float(isle["flat"]) - 2.5)
			var spot: Vector2 = (isle["at"] as Vector2) + Vector2(cos(angle), sin(angle)) * r
			if not _near_any(spot, clear, KEEP_CLEAR):
				spots.append(spot)
	return spots


static func _palms(parent: Node3D, land: Archipelago, clear: Array[Vector2]) -> void:
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
	for at: Vector2 in _palm_spots(land, clear):
		var spot := _world(at)
		trunks.append(Transform3D(Basis(), spot + Vector3(0, 2.5, 0)))
		crowns.append(Transform3D(Basis(), spot + Vector3(0, 5.1, 0)))
		var tall := rng.randf_range(0.85, 1.25)
		var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(tall, tall, tall))
		palms.append(Transform3D(turn, spot))
	LookProps.add(_field(parent, trunk_mesh, trunks, _flat(Color(0.5, 0.35, 0.2))), false)
	LookProps.add(_field(parent, crown_mesh, crowns, _flat(Color(0.2, 0.55, 0.25))), false)
	# Textured look: curved trunks with frond crowns.
	var bark := SurfaceLibrary.material("palm_bark", Color(0.5, 0.35, 0.2))
	LookProps.add(_field(parent, PalmBuilder.mesh(bark), palms, null), true)


# Boulders at every island's waterline (textured look only), each with a simple round collider. One set of
# MultiMeshes per island, drawn only near it.
static func _rocks(parent: Node3D, land: Archipelago, clear: Array[Vector2]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var body := StaticBody3D.new()
	body.position = CENTER
	parent.add_child(body)
	LookProps.add(body, true)
	# [model, node, how many at scatter 1, smallest size, largest size, real radius of the model in metres]
	for kind: Array in [["namaqualand_boulder_04", "boulder_04", 3, 0.45, 0.9, 1.25], ["rock_09", "rock_09_LOD0", 8, 5.0, 16.0, 0.07]]:
		var rock := ModelLibrary.mesh(String(kind[0]), String(kind[1]))
		if rock == null:
			continue
		var reach := float(kind[5])
		for index in land.islands.size():
			var isle: Dictionary = land.islands[index]
			var radius := float(isle["radius"])
			var xforms: Array[Transform3D] = []
			for i in roundi(float(kind[2]) * float(isle["scatter"])):
				var angle := rng.randf_range(0.0, TAU)
				var r := rng.randf_range(radius - 1.6, radius + 2.2)
				var big := rng.randf_range(float(kind[3]), float(kind[4]))
				var at: Vector2 = (isle["at"] as Vector2) + Vector2(cos(angle), sin(angle)) * r
				if _near_any(at, clear, KEEP_CLEAR + 1.0):
					continue
				var spot := Vector3(at.x, land.island_height(index, at.x, at.y) - 0.25 * big * reach, at.y)  # sunk into the sand a little
				var turn := Basis.from_euler(Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, TAU), rng.randf_range(-0.2, 0.2)))
				xforms.append(Transform3D(turn * Basis.from_scale(Vector3(big, big, big)), spot))
				var ball := SphereShape3D.new()
				ball.radius = big * reach * 0.8
				var shape := CollisionShape3D.new()
				shape.shape = ball
				shape.position = spot + Vector3(0, ball.radius * 0.5, 0)
				body.add_child(shape)
			_near_only(_field(body, rock, xforms, null), land, index)


# Ferns and broad-leaf plants around the grass edges and the palm feet (textured look only), per island.
static func _plants(parent: Node3D, land: Archipelago, clear: Array[Vector2]) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 37
	var feet := _palm_spots(land, clear)
	# [model, plants of each variant at scatter 1, smallest size, largest size]
	for kind: Array in [["fern_02", 9, 0.9, 1.6], ["calathea_orbifolia_01", 4, 1.0, 1.8], ["anthurium_botany_01", 2, 0.9, 1.4]]:
		for entry: Array in ModelLibrary.meshes(String(kind[0])):
			for index in land.islands.size():
				var isle: Dictionary = land.islands[index]
				var mid: Vector2 = isle["at"]
				var xforms: Array[Transform3D] = []
				for i in roundi(float(kind[1]) * float(isle["scatter"])):
					var angle := rng.randf_range(0.0, TAU)
					var at := mid + Vector2(cos(angle), sin(angle)) * rng.randf_range(float(isle["grass"]) - 2.5, float(isle["grass"]) + 1.5)
					if rng.randf() < 0.5 and not feet.is_empty():
						var foot: Vector2 = feet[rng.randi() % feet.size()]
						if foot.distance_to(mid) < float(isle["radius"]):  # at the foot of one of this island's palms
							at = foot + Vector2(cos(angle), sin(angle)) * rng.randf_range(0.5, 1.6)
					if _near_any(at, clear, KEEP_CLEAR - 1.5) or land.height_at(at.x, at.y) < -0.01:
						continue
					var big := rng.randf_range(float(kind[2]), float(kind[3]))
					var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis.from_scale(Vector3(big, big, big))
					xforms.append(Transform3D(turn, _world(at)))
				if xforms.is_empty():
					continue
				var field := _field(parent, entry[1] as Mesh, xforms, null)
				field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_near_only(field, land, index)
				LookProps.add_scatter(field)


# Small things of one island are drawn only within data scatter_range metres of its shore (the range is measured to
# the middle of what the MultiMesh holds, which is the island's middle).
static func _near_only(field: MultiMeshInstance3D, land: Archipelago, index: int) -> void:
	field.visibility_range_end = float(land.islands[index]["radius"]) + float(land.cfg["scatter_range"])
	field.visibility_range_end_margin = 8.0


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


# One way between two islands, shore to shore, with its debris in the middle. Planks = a deck on posts; sandbar = a
# ridge of sand just above the water. Both are solid. Returns the debris (game/debris_pile.gd).
static func _bridge(parent: Node3D, land: Archipelago, index: int, sand: Material) -> Node3D:
	var entry: Dictionary = land.bridges[index]
	var a: Vector2 = entry["a"]
	var b: Vector2 = entry["b"]
	var length := a.distance_to(b)
	var width := land.deck_width()
	var top := land.deck_height(index)
	var way := Node3D.new()  # its -z runs from a to b
	way.position = _world(entry["mid"])
	way.rotation.y = atan2(-(b.x - a.x), -(b.y - a.y))
	parent.add_child(way)
	var body := StaticBody3D.new()
	way.add_child(body)
	var shape := CollisionShape3D.new()
	body.add_child(shape)
	if String(entry["kind"]) == "planks":
		var wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
		var deck := BoxMesh.new()
		deck.size = Vector3(width, 0.5, length)
		_place(way, deck, wood, Vector3(0, top - 0.25, 0))
		var box := BoxShape3D.new()
		box.size = deck.size
		shape.shape = box
		shape.position = Vector3(0, top - 0.25, 0)
		var post := CylinderMesh.new()
		post.top_radius = 0.16
		post.bottom_radius = 0.2
		post.height = 7.0
		post.radial_segments = 8
		var posts: Array[Transform3D] = []
		var rails: Array[Transform3D] = []
		for n in floori(length / POST_GAP) + 1:
			var along := -length * 0.5 + float(n) * length / float(floori(length / POST_GAP))
			for side: float in [-1.0, 1.0]:
				posts.append(Transform3D(Basis(), Vector3(side * (width * 0.5 + 0.1), top + 0.9 - post.height * 0.5, along)))
		var rail := BoxMesh.new()
		rail.size = Vector3(0.1, 0.1, length)
		for side: float in [-1.0, 1.0]:
			rails.append(Transform3D(Basis(), Vector3(side * (width * 0.5 + 0.1), top + 0.75, 0)))
		_field(way, post, posts, wood)
		_field(way, rail, rails, wood)
	else:
		var foot := -6.0  # the ridge stands on the sea bed
		var spread := (top - foot) * 1.25  # how far each side runs out on its way down
		var corners: Array[Vector3] = []
		for end: float in [-1.0, 1.0]:
			corners.append(Vector3(-width * 0.5, top, end * length * 0.5))
			corners.append(Vector3(width * 0.5, top, end * length * 0.5))
			corners.append(Vector3(-width * 0.5 - spread, foot, end * length * 0.5))
			corners.append(Vector3(width * 0.5 + spread, foot, end * length * 0.5))
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for quad: Array in [[0, 1, 5, 4], [2, 0, 4, 6], [1, 3, 7, 5]]:  # top, left side, right side
			var normal := ((corners[quad[1]] - corners[quad[0]]).cross(corners[quad[3]] - corners[quad[0]])).normalized()
			if normal.y < 0.0:
				normal = -normal
			for corner: int in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
				st.set_normal(normal)
				st.add_vertex(corners[corner])
		var ridge := _place(way, st.commit(), sand, Vector3.ZERO)
		ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var hull := ConvexPolygonShape3D.new()
		hull.points = PackedVector3Array(corners)
		shape.shape = hull
	var pile: Node3D = DebrisPile.new()
	pile.set("width", width)
	pile.position = Vector3(0, top, 0)
	way.add_child(pile)
	return pile


# A framed painting on two posts at `at`, its picture facing `yaw` (0 = +z). Also used for the way home inside a
# painting's world.
static func build_painting(parent: Node3D, at: Vector3, texture: Texture2D, yaw: float = 0.0) -> void:
	var stand := Node3D.new()
	stand.position = at
	stand.rotation.y = yaw
	parent.add_child(stand)
	var post_wood := SurfaceLibrary.material("painting_post", Color(0.4, 0.28, 0.15))
	for side: float in [-1.0, 1.0]:
		var post := BoxMesh.new()
		post.size = Vector3(0.25, 3.6, 0.25)
		_place(stand, post, post_wood, Vector3(side * 2.4, 1.8, 0))
	var frame := BoxMesh.new()
	frame.size = Vector3(5.0, 3.6, 0.2)
	_place(stand, frame, SurfaceLibrary.material("painting_frame", Color(0.55, 0.4, 0.15)), Vector3(0, 2.3, 0))
	var canvas := QuadMesh.new()
	canvas.size = Vector2(4.6, 3.2)
	var art := StandardMaterial3D.new()
	art.albedo_texture = texture
	art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	art.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_place(stand, canvas, art, Vector3(0, 2.3, 0.11))
	var body := StaticBody3D.new()
	body.position = Vector3(0, 1.8, 0)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.0, 3.6, 0.4)
	shape.shape = box
	body.add_child(shape)
	stand.add_child(body)
