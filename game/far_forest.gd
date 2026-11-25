# Purpose: (polish1 F1a) a country's FORESTS SEEN FROM AFAR: beyond the real trees round the player, every wooded
# stretch of the country (looks in WOODED) is drawn as simple standing trees (a stem and two cones of crown, 26
# triangles), so forested hills read as forest across the land. One MultiMesh per 400 m tile (culled by distance);
# a square round the player, where the real trees stand, is cut out in the shader. Spacing per graphics tier
# (data/graphics.json fantasy "far_trees" metres, 0 = none). Built once on a worker thread.
# Dependencies: core/fantasy_terrain.gd (height, weights, snow_at, water), game/fantasy_ground.gd (toned).
extends Node3D

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const FantasyGround = preload("res://game/fantasy_ground.gd")

const WOODED := {"greenwald": Color(0.2, 0.34, 0.17), "brinemouth": Color(0.16, 0.38, 0.18)}  # look -> crown colour
const TILE := 400.0  # metres a side of one drawn batch
const SHOW_M := 1700.0  # batches further than this are not drawn
const NEED := 0.5  # share of a wooded look a spot needs
const CODE := """shader_type spatial;
render_mode cull_back;
uniform vec4 hole = vec4(0.0, 0.0, -1.0, 0.0);
uniform vec3 origin = vec3(0.0);
varying vec3 spot;
void vertex() {
	spot = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz - origin;  // the tree's foot in the land's own metres
}
void fragment() {
	if (abs(spot.x - hole.x) < hole.z && abs(spot.z - hole.y) < hole.z) {
		discard;
	}
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * 0.3;  // a crown with the sun behind it stays green, not black
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}"""

var spacing := 20.0
var planted := false  # setup ran (once per country: a later change of graphics tier keeps these trees)
var _terrain: FantasyTerrain
var _material: ShaderMaterial
var _task := -1
var _built: Array = []  # [[tile centre (Vector3), Array of [Transform3D, Color]]] from the worker
var _count := 0


func setup(land_terrain: FantasyTerrain, metres: float) -> void:
	_terrain = land_terrain
	spacing = metres
	planted = true
	if _terrain.country_shape == null or spacing <= 0.0:
		return
	var shader := Shader.new()
	shader.code = CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_task = WorkerThreadPool.add_task(_plant)


# The square (centre and half width, local metres) where the real trees stand: the far trees there are not drawn.
func cut(center: Vector2, half: float) -> void:
	if _material != null:
		_material.set_shader_parameter("hole", Vector4(center.x, center.y, half, 0.0))


func count() -> int:
	return _count


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_show()


# Runs on a worker thread: the terrain rules are pure.
func _plant() -> void:
	var half := _terrain.size * 0.5
	var cells := int(_terrain.size / spacing)
	var tiles := {}
	var wooded := []
	for i in _terrain.regions.size():
		wooded.append(WOODED.get(String(_terrain.regions[i]["id"]), Color(0, 0, 0, 0)))
	for gz in cells:
		for gx in cells:
			var x := -half + (float(gx) + FantasyTerrain.hash01(gx, gz, 71)) * spacing
			var z := -half + (float(gz) + FantasyTerrain.hash01(gx, gz, 72)) * spacing
			var w := _terrain.weights(x, z)
			var share := 0.0
			var crown := Color(0, 0, 0)
			for i in w.size():
				if (wooded[i] as Color).a > 0.0:
					share += w[i]
					crown += (wooded[i] as Color) * w[i]
			if share < NEED:
				continue
			var h := _terrain.height(x, z)
			if h < _terrain.sea + 1.5 or _terrain.snow_at(x, z, h) > 0.3:
				continue
			var steep := Vector2(_terrain.height(x + 4.0, z) - _terrain.height(x - 4.0, z), _terrain.height(x, z + 4.0) - _terrain.height(x, z - 4.0)).length() / 8.0
			if steep > 0.65 or _terrain.water_at(x, z) != "":
				continue
			var vary := FantasyTerrain.hash01(gx, gz, 73)
			var grow := 0.8 + 0.55 * vary
			var key := Vector2i(floori((x + half) / TILE), floori((z + half) / TILE))
			if not tiles.has(key):
				tiles[key] = []
			var tint := (crown / share).lerp(Color(0.32, 0.42, 0.2), vary * 0.35)
			(tiles[key] as Array).append([Transform3D(Basis(Vector3.UP, vary * TAU).scaled(Vector3(grow, grow * (0.9 + 0.3 * FantasyTerrain.hash01(gx, gz, 74)), grow)), Vector3(x, h, z)), FantasyGround.toned(tint)])
	var out: Array = []
	for key: Vector2i in tiles:
		out.append([Vector3(-half + (float(key.x) + 0.5) * TILE, 0.0, -half + (float(key.y) + 0.5) * TILE), tiles[key]])
	_built = out


func _show() -> void:
	_material.set_shader_parameter("origin", global_position)
	var mesh := _tree_mesh()
	for tile: Array in _built:
		var list: Array = tile[1]
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.use_colors = true
		many.mesh = mesh
		many.instance_count = list.size()
		for i in list.size():
			many.set_instance_transform(i, list[i][0])
			many.set_instance_color(i, list[i][1])
		var drawn := MultiMeshInstance3D.new()
		drawn.multimesh = many
		drawn.material_override = _material
		drawn.visibility_range_end = SHOW_M
		drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(drawn)
		_count += list.size()
	_built = []


# A far tree: a stem reaching well down (the whole-land mesh lies a few metres under the real height) and two cones
# of crown. Vertex colours shade the stem and the crown's underside; the instance colour tints it.
func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 5
	_cone(st, sides, -6.0, 3.0, 0.35, 0.25, Color(0.45, 0.36, 0.3))
	_cone(st, sides, 2.2, 8.5, 2.6, 0.0, Color(0.85, 0.85, 0.85))
	_cone(st, sides, 6.0, 11.5, 1.9, 0.0, Color(1.0, 1.0, 1.0))
	st.generate_normals()
	return st.commit()


func _cone(st: SurfaceTool, sides: int, y0: float, y1: float, r0: float, r1: float, shade: Color) -> void:
	for k in sides:
		var a := TAU * float(k) / float(sides)
		var b := TAU * float(k + 1) / float(sides)
		var p0 := Vector3(cos(a) * r0, y0, sin(a) * r0)
		var p1 := Vector3(cos(b) * r0, y0, sin(b) * r0)
		var q0 := Vector3(cos(a) * r1, y1, sin(a) * r1)
		var q1 := Vector3(cos(b) * r1, y1, sin(b) * r1)
		for v: Vector3 in [p0, q0, p1, p1, q0, q1] if r1 > 0.0 else [p0, q0, p1]:
			st.set_color(shade.darkened(0.25) if v.y == y0 else shade)
			st.add_vertex(v)
