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
		var size := Vector3(float(p["size"][0]), thick, float(p["size"][1]))
		var middle := Vector3(float(p["at"][0]), -thick * 0.5, float(p["at"][1]))
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
			label.position = Vector3(float(p["at"][0]), 3.4, float(p["at"][1]))
			root.add_child(label)
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
