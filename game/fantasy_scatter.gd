# Purpose: dresses each loaded chunk of the fantasy world with what core/fantasy_layout.gd says grows there: trees (one
# draw call per kind and chunk), blades of grass or wheat, tree trunks' colliders, and the things to gather (trees to
# chop, ore, crops, herbs, fishing spots on the water), which it hands to game/gather_nodes.gd. Detail drops with
# distance: far chunks keep only their ground.
# Dependencies: core/fantasy_terrain.gd, core/fantasy_layout.gd, game/fantasy_land.gd (chunk signals),
# game/fantasy_models.gd, game/gather_nodes.gd.
extends Node3D

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const FantasyLayout = preload("res://core/fantasy_layout.gd")
const FantasyGround = preload("res://game/fantasy_ground.gd")

const BLADES := 9  # thin blades in one tuft (one triangle each)
# Blades are lit like the ground they stand on from both sides (a two-sided blade would otherwise go black from behind)
# and lean with a slow wind, more the higher up the blade.
const BLADE_CODE := """shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform float wind = 1.0;
void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = wind * (sin(TIME * 1.6 + at.x * 0.31 + at.z * 0.23) + 0.5 * sin(TIME * 2.9 + at.x * 0.7));
	VERTEX.x += sway * 0.05 * VERTEX.y;
	VERTEX.z += sway * 0.03 * VERTEX.y;
}
void fragment() {
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
"""

var terrain: FantasyTerrain
var layout: FantasyLayout  # says where the trees and the things to gather stand
var gather: Node3D  # game/gather_nodes.gd
var tree_radius := 3  # chunks around the player that get trees and tufts
var tuft_radius := 2
var tuft_scale := 1.0  # graphics tier: share of the blades that are placed

var _land: Node3D
var _dressed := {}  # Vector2i -> Node3D holding that chunk's scatter
var _node_data: Dictionary
var _meshes := {}
var _tuft_mesh: ArrayMesh
var _wind := true
var _center := Vector2i(9999, 9999)


func setup(land_terrain: FantasyTerrain, world_layout: FantasyLayout, land: Node3D, gather_nodes: Node3D, skilling: Dictionary) -> void:
	terrain = land_terrain
	layout = world_layout
	_land = land
	gather = gather_nodes
	_node_data = skilling["nodes"]
	land.chunk_unloaded.connect(_undress)
	_tuft_mesh = _make_tuft()
	set_wind(_wind)


# Call with the player's chunk: dresses chunks that came into range and strips those that left it.
func follow(center: Vector2i) -> void:
	if center == _center:
		return
	_center = center
	for key: Vector2i in _dressed.keys():
		if maxi(absi(key.x - center.x), absi(key.y - center.y)) > tree_radius:
			_undress(key)
	refresh()


# Dresses loaded chunks in range that are still bare (also called while chunks arrive).
func refresh() -> void:
	for dz in range(-tree_radius, tree_radius + 1):
		for dx in range(-tree_radius, tree_radius + 1):
			var key := Vector2i(_center.x + dx, _center.y + dz)
			if not _dressed.has(key) and _land.loaded(key):
				_dress(key, maxi(absi(dx), absi(dz)) <= tuft_radius)


func _undress(key: Vector2i) -> void:
	if _dressed.has(key):
		(_dressed[key] as Node3D).queue_free()
		_dressed.erase(key)
		gather.drop_chunk(key)


func _mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		_meshes[id] = FantasyModels.mesh(id)
	return _meshes[id]


func _dress(key: Vector2i, with_tufts: bool) -> void:
	var size: float = _land.chunk_size()
	var holder := Node3D.new()
	add_child(holder)
	_dressed[key] = holder
	var by_model := {}  # model id -> Array[Transform3D]
	var trunks := StaticBody3D.new()
	holder.add_child(trunks)
	for tree: Array in layout.trees(key):  # scenery: [model, x, z, grow, turn]
		_place(by_model, String(tree[0]), float(tree[1]), terrain.height(float(tree[1]), float(tree[2])), float(tree[2]), float(tree[3]), float(tree[4]))
		_trunk(trunks, float(tree[1]), float(tree[2]), 0.3 * float(tree[3]))
	for node: Array in layout.nodes(key):  # things to work on: [slot, node id, x, y, z, turn]
		var def: Dictionary = _node_data[String(node[1])]
		var index := _place(by_model, String(def["model"]), float(node[2]), float(node[3]), float(node[4]), 1.0, float(node[5]))
		gather.add_node(key, int(node[0]), String(node[1]), Vector3(float(node[2]), float(node[3]), float(node[4])), String(def["model"]), index)
		if String(def["skill"]) in ["woodcutting", "mining"]:
			_trunk(trunks, float(node[2]), float(node[4]), 0.35)
	for id: String in by_model:
		var list: Array = by_model[id]
		var mesh := _mesh(id)
		if mesh == null or list.is_empty():
			continue
		var many := MultiMesh.new()
		many.transform_format = MultiMesh.TRANSFORM_3D
		many.mesh = mesh
		many.instance_count = list.size()
		for i in list.size():
			many.set_instance_transform(i, list[i])
		var drawn := MultiMeshInstance3D.new()
		drawn.multimesh = many
		holder.add_child(drawn)
		gather.bind_drawn(key, id, many)
	if with_tufts:
		_add_tufts(holder, key, float(key.x) * size, float(key.y) * size, size)


func _place(by_model: Dictionary, id: String, x: float, y: float, z: float, grow: float, turn: float) -> int:
	if not by_model.has(id):
		by_model[id] = []
	(by_model[id] as Array).append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * grow), Vector3(x, y - 0.05, z)))
	return (by_model[id] as Array).size() - 1


func _trunk(body: StaticBody3D, x: float, z: float, radius: float) -> void:
	var shape := CollisionShape3D.new()
	var post := CylinderShape3D.new()
	post.radius = radius
	post.height = 3.0
	shape.shape = post
	shape.position = Vector3(x, terrain.height(x, z) + 1.5, z)
	body.add_child(shape)


func _add_tufts(holder: Node3D, key: Vector2i, x0: float, z0: float, size: float) -> void:
	var region := terrain.region_at(x0 + size / 2.0, z0 + size / 2.0)
	var tuft: Dictionary = region["tuft"]
	var count := int(float(tuft["count"]) * tuft_scale)
	if count <= 0:
		return
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.use_colors = true
	many.mesh = _tuft_mesh
	many.instance_count = count
	var base := Color(tuft["color"][0], tuft["color"][1], tuft["color"][2])
	var tip := Color(tuft["tip"][0], tuft["tip"][1], tuft["tip"][2])
	var tall := float(tuft["height"])
	var shown := 0
	for i in count:
		var x := x0 + FantasyTerrain.hash01(key.x, key.y, 1000 + i * 2) * size
		var z := z0 + FantasyTerrain.hash01(key.x, key.y, 1001 + i * 2) * size
		var h := terrain.height(x, z)
		if h < terrain.sea + 0.5 or not _clear_of_yards(x, z):
			continue
		var vary := FantasyTerrain.hash01(key.x, key.y, 5000 + i)
		many.set_instance_transform(shown, Transform3D(Basis(Vector3.UP, vary * TAU).scaled(Vector3(1.0, tall * (0.7 + 0.6 * vary), 1.0)), Vector3(x, h - 0.03, z)))
		many.set_instance_color(shown, FantasyGround.toned(base.lerp(tip, vary)))
		shown += 1
	many.visible_instance_count = shown
	var drawn := MultiMeshInstance3D.new()
	drawn.multimesh = many
	drawn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(drawn)


func _clear_of_yards(x: float, z: float) -> bool:
	return terrain.trodden(x, z) < 0.3 and terrain.water_at(x, z) == ""


# One tuft: a few thin blades fanning out, darker at the root (the instance colour tints the whole tuft).
# Graphics tier: grass sways in the wind or stands still.
func set_wind(on: bool) -> void:
	_wind = on
	if _tuft_mesh != null:
		(_tuft_mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("wind", 1.0 if on else 0.0)


func _make_tuft() -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in BLADES:
		var a := float(i) * TAU / float(BLADES) + float(i % 3) * 0.4
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := Vector3(-out.z, 0.0, out.x) * 0.022
		var reach := 0.1 + 0.07 * float(i % 4)  # how far the blade stands from the middle
		var tall := 0.55 + 0.15 * float((i * 7) % 4)  # blades of one tuft differ in height
		verts.append_array(PackedVector3Array([out * reach * 0.45 - side, out * reach * 0.45 + side, out * (reach + 0.12 * tall) + Vector3(0, tall, 0)]))
		normals.append_array(PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]))
		colors.append_array(PackedColorArray([Color(0.6, 0.6, 0.6), Color(0.6, 0.6, 0.6), Color.WHITE]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var shader := Shader.new()
	shader.code = BLADE_CODE
	var blade := ShaderMaterial.new()
	blade.shader = shader
	mesh.surface_set_material(0, blade)
	return mesh
