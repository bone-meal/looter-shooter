# Purpose: builds the hop course in the sky (data/course.json): every platform in ONE mesh (coloured by kind: start
# green, pads sandstone, checkpoints blue, finish gold) on ONE static body with a box per platform, signs over the
# start, the checkpoints and the finish; and the stone arch on the islands that takes you there.
# Dependencies: data/course.json (the dictionary is handed in), core/course_rules.gd (pads, stage names).
extends RefCounted

const COLORS := {"start": Color(0.35, 0.62, 0.3), "pad": Color(0.78, 0.68, 0.5), "checkpoint": Color(0.3, 0.5, 0.85), "finish": Color(0.95, 0.75, 0.25)}


# The course under `parent`, its middle at the course's `center`. Returns the Node3D holding it.
static func build(parent: Node, rules: RefCounted) -> Node3D:
	var cfg: Dictionary = rules.get("cfg")
	var root := Node3D.new()
	root.name = "HopCourse"
	var c: Array = cfg["center"]
	root.position = Vector3(float(c[0]), float(c[1]), float(c[2]))
	parent.add_child(root)
	var thick := float(cfg.get("thickness", 1.0))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := StaticBody3D.new()
	root.add_child(body)
	var pads: Array = rules.get("pads")
	var checkpoint_number := 0
	for i in pads.size():
		var p: Dictionary = pads[i]
		var kind := String(p.get("kind", "pad"))
		var tall := float(p.get("thick", thick))  # (polish1 C7) a KZ tower reaches down to the step below
		var size := Vector3(float(p["size"][0]), tall, float(p["size"][1]))
		var middle := Vector3(float(p["at"][0]), float(p.get("y", 0.0)) - tall * 0.5, float(p["at"][1]))
		_box(tool, middle, size, COLORS.get(kind, COLORS["pad"]) * (0.92 + 0.08 * float(i % 2)))
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = middle
		body.add_child(shape)
		var sign_text := ""
		if kind == "start":
			sign_text = "START"
		elif kind == "finish":
			sign_text = "FINISH"
		elif kind == "checkpoint":
			checkpoint_number += 1
			sign_text = "CHECKPOINT %d\n%s" % [checkpoint_number, String(rules.call("stage_name", mini(i + 1, pads.size() - 1)))]
		if sign_text != "":
			var label := Label3D.new()
			label.text = sign_text
			label.font_size = 40
			label.pixel_size = 0.01
			label.outline_size = 10
			label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			label.modulate = COLORS.get(kind, Color.WHITE).lightened(0.4)
			label.position = Vector3(float(p["at"][0]), float(p.get("y", 0.0)) + 3.4, float(p["at"][1]))
			root.add_child(label)
	var ladders: Array = []  # (polish1 C7) [AABB in the course's space] the session climbs in
	for part: Dictionary in cfg.get("parts", []):
		var at := Vector3(float(part["at"][0]), float(part["at"][1]), float(part["at"][2]))
		var psize := Vector3(float(part["size"][0]), float(part["size"][1]), float(part["size"][2]))
		var xf := Transform3D(Basis.from_euler(Vector3(deg_to_rad(float(part.get("pitch", 0.0))), deg_to_rad(float(part.get("yaw", 0.0))), deg_to_rad(float(part.get("roll", 0.0))))), at)
		match String(part["kind"]):
			"ramp":  # a surf face: slick blue, solid
				_box_xf(tool, xf, psize, Color(0.35, 0.62, 0.85))
				var shape_r := CollisionShape3D.new()
				var box_r := BoxShape3D.new()
				box_r.size = psize
				shape_r.shape = box_r
				shape_r.transform = xf
				body.add_child(shape_r)
			"ladder":  # two rails and a rung every 30 cm on a tower's face; climbed, not stood on
				var rails := Color(0.55, 0.55, 0.6)
				for side: float in [-0.45, 0.45]:
					_box_xf(tool, xf * Transform3D(Basis(), Vector3(side * psize.x, 0, 0)), Vector3(0.07, psize.y, 0.07), rails)
				var rung := -psize.y * 0.5 + 0.25
				while rung < psize.y * 0.5:
					_box_xf(tool, xf * Transform3D(Basis(), Vector3(0, rung, 0)), Vector3(psize.x * 0.9, 0.05, 0.05), Color(0.75, 0.62, 0.35))
					rung += 0.3
				ladders.append(xf * AABB(-psize * 0.5 - Vector3(0.45, 0.0, 0.6), psize + Vector3(0.9, 0.6, 1.2)))
	root.set_meta("ladders", ladders)
	tool.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = tool.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	mesh.material_override = mat
	root.add_child(mesh)
	return root


# The way there: a stone arch with a sign, standing at `at` facing `yaw`. Returns it (interact range is the session's).
static func build_door(parent: Node, at: Vector3, yaw: float) -> Node3D:
	var arch := Node3D.new()
	arch.name = "HopCourseDoor"
	arch.position = at
	arch.rotation.y = yaw
	parent.add_child(arch)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.62, 0.58, 0.52)
	stone.roughness = 0.9
	for part: Array in [[Vector3(-1.3, 1.4, 0), Vector3(0.45, 2.8, 0.45)], [Vector3(1.3, 1.4, 0), Vector3(0.45, 2.8, 0.45)], [Vector3(0, 3.0, 0), Vector3(3.2, 0.45, 0.55)]]:
		var piece := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = part[1]
		piece.mesh = box
		piece.material_override = stone
		piece.position = part[0]
		arch.add_child(piece)
	var glow := MeshInstance3D.new()
	var sheet := QuadMesh.new()
	sheet.size = Vector2(2.15, 2.75)
	glow.mesh = sheet
	var light := StandardMaterial3D.new()
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.albedo_color = Color(0.45, 0.75, 1.0, 0.45)
	light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	light.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow.material_override = light
	glow.position = Vector3(0, 1.4, 0)
	arch.add_child(glow)
	var label := Label3D.new()
	label.text = "HOP COURSE"
	label.font_size = 72
	label.pixel_size = 0.01
	label.outline_size = 14
	label.position = Vector3(0, 3.55, 0)
	arch.add_child(label)
	return arch


# A turned box (surf faces, ladder parts) into the shared mesh.
static func _box_xf(tool: SurfaceTool, xf: Transform3D, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var corners := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[3, 2, 6, 7], [4, 5, 1, 0], [7, 6, 5, 4], [0, 1, 2, 3], [3, 7, 4, 0], [6, 2, 1, 5]]
	for face: Array in faces:
		var shade := color if face == faces[0] else color.darkened(0.25)
		var pts: Array[Vector3] = []
		for k: int in face:
			pts.append(xf * (corners[k] as Vector3))
		for v: Vector3 in [pts[0], pts[1], pts[2], pts[0], pts[2], pts[3]]:
			tool.set_color(shade)
			tool.add_vertex(v)


# A box's six faces into the shared mesh, in one colour.
static func _box(tool: SurfaceTool, middle: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var corners := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var faces := [[3, 2, 6, 7], [4, 5, 1, 0], [7, 6, 5, 4], [0, 1, 2, 3], [3, 7, 4, 0], [6, 2, 1, 5]]  # top, bottom, +z, -z, -x, +x
	for face: Array in faces:
		var shade := color if face == faces[0] else color.darkened(0.25)
		var a: Vector3 = middle + corners[face[0]]
		var b: Vector3 = middle + corners[face[1]]
		var c: Vector3 = middle + corners[face[2]]
		var d: Vector3 = middle + corners[face[3]]
		for v: Vector3 in [a, b, c, a, c, d]:
			tool.set_color(shade)
			tool.add_vertex(v)


# (polish1 item 26) The BHOP SERVER's hub: a floating round plaza; round its rim one gate per stage type (an arch in
# the type's colour with its name) with three portal pads (tier 1 bronze, 2 silver, 3 gold) that name their stage
# and your best time; walk onto one to go. In the middle the BEST TIMES board; at `exit` an arch back to the islands.
# Metas: "portals" [[stage index, Vector3 local]], "labels" {stage index: Label3D}, "board" (Label3D), "exit" (Vector3 local).
static func build_hub(parent: Node, server: Dictionary) -> Node3D:
	var hub: Dictionary = server["hub"]
	var root := Node3D.new()
	root.name = "BhopHub"
	root.position = Vector3(float(hub["at"][0]), float(hub["at"][1]), float(hub["at"][2]))
	parent.add_child(root)
	var radius := float(hub["radius"])
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = radius
	floor_mesh.bottom_radius = radius * 0.8
	floor_mesh.height = 1.2
	floor_mesh.radial_segments = 32
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.32, 0.34, 0.4)
	stone.roughness = 0.8
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = stone
	floor_node.position.y = -0.6
	root.add_child(floor_node)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = 1.2
	shape.shape = cyl
	shape.position.y = -0.6
	body.add_child(shape)
	root.add_child(body)
	var rim := MeshInstance3D.new()  # a glowing ring round the edge
	var ring := TorusMesh.new()
	ring.inner_radius = radius - 0.15
	ring.outer_radius = radius + 0.05
	ring.rings = 48
	rim.mesh = ring
	rim.material_override = _glow_mat(Color(0.4, 0.8, 1.0))
	root.add_child(rim)
	var types: Array = server["types"]
	var stages: Array = server["stages"]
	var portals: Array = []
	var labels := {}
	var tier_colors := [Color(0.8, 0.5, 0.25), Color(0.78, 0.8, 0.85), Color(1.0, 0.8, 0.3)]
	for t in types.size():
		var type: Dictionary = types[t]
		var colour := Color(String(type["color"]))
		var a := TAU * float(t) / float(types.size()) + PI / float(types.size())
		var out := Vector3(sin(a), 0, -cos(a))
		var gate := Node3D.new()
		gate.position = out * (radius - 4.0)
		gate.rotation.y = atan2(out.x, out.z)  # faces the middle
		root.add_child(gate)
		for side: float in [-3.4, 3.4]:  # the arch
			_part(gate, Vector3(side, 2.2, 1.2), Vector3(0.5, 4.4, 0.5), _glow_mat(colour.darkened(0.2)))
		_part(gate, Vector3(0, 4.6, 1.2), Vector3(7.4, 0.5, 0.6), _glow_mat(colour))
		var title := Label3D.new()
		title.text = String(type["name"])
		title.font_size = 64
		title.pixel_size = 0.012
		title.outline_size = 12
		title.modulate = colour.lightened(0.3)
		title.position = Vector3(0, 5.5, 1.2)
		title.rotation.y = PI
		gate.add_child(title)
		var tier := 0
		for i in stages.size():
			if String(stages[i]["type"]) != String(type["id"]):
				continue
			var spot := Vector3(-2.4 + 2.4 * float(tier), 0.0, -0.4)
			var disc := MeshInstance3D.new()
			var pad := CylinderMesh.new()
			pad.top_radius = 0.95
			pad.bottom_radius = 0.95
			pad.height = 0.08
			pad.radial_segments = 20
			disc.mesh = pad
			disc.material_override = _glow_mat(tier_colors[mini(tier, 2)])
			disc.position = spot + Vector3(0, 0.04, 0)
			gate.add_child(disc)
			var name_label := Label3D.new()
			name_label.font_size = 40
			name_label.pixel_size = 0.0075
			name_label.outline_size = 8
			name_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			name_label.position = spot + Vector3(0, 1.9, 0)
			gate.add_child(name_label)
			labels[i] = name_label
			portals.append([i, gate.transform * spot])
			tier += 1
	var board := Label3D.new()  # the BEST TIMES board in the middle, readable from all round
	board.font_size = 36
	board.pixel_size = 0.009
	board.outline_size = 8
	board.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	board.modulate = Color(1.0, 0.9, 0.6)
	board.position = Vector3(0, 4.2, 0)
	root.add_child(board)
	var exit_at := Vector3(float(hub["exit"][0]), 0.0, float(hub["exit"][1]))
	var door := build_door(root, exit_at, 0.0)
	(door.get_child(door.get_child_count() - 1) as Label3D).text = "BACK TO THE ISLANDS"
	root.set_meta("portals", portals)
	root.set_meta("labels", labels)
	root.set_meta("board", board)
	root.set_meta("exit", exit_at)
	return root


static func _part(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> void:
	var piece := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	piece.mesh = box
	piece.material_override = mat
	piece.position = at
	parent.add_child(piece)


static var _glows := {}
static func _glow_mat(colour: Color) -> StandardMaterial3D:
	var key := colour.to_html()
	if not _glows.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = colour
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glows[key] = m
	return _glows[key]
