# Purpose: dresses each loaded chunk of the fantasy world with what core/fantasy_layout.gd says grows there: trees (one
# draw call per kind and chunk), blades of grass or wheat, tree trunks' colliders, and the things to gather (trees to
# chop, ore, crops, herbs, fishing spots on the water), which it hands to game/gather_nodes.gd. Detail drops with
# distance: far chunks keep only their ground.
# Dependencies: core/fantasy_terrain.gd, core/fantasy_layout.gd, game/fantasy_land.gd (chunk signals),
# game/fantasy_models.gd, game/gather_nodes.gd.
extends Node3D

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")
const NodeLooks = preload("res://game/node_looks.gd")
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
var _clutter := {}  # model id -> {"many": MultiMesh, "at": Array of Transform3D, "of": Array of chunk keys}
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
	_dress_some(9, 1)  # what is right around the player at once; the rest one chunk a frame (_process)


# Dresses every loaded chunk in range that is still bare, at once (after a change of graphics settings).
func refresh() -> void:
	for dz in range(-tree_radius, tree_radius + 1):
		for dx in range(-tree_radius, tree_radius + 1):
			var key := Vector2i(_center.x + dx, _center.y + dz)
			if not _dressed.has(key) and _land.loaded(key):
				_dress(key, maxi(absi(dx), absi(dz)) <= tuft_radius)


# One more bare chunk each frame, nearest first: dressing them all in the frame they arrive made the game stutter.
func _process(_delta: float) -> void:
	_dress_some(1, tree_radius)


func _dress_some(limit: int, reach: int) -> void:
	var left := limit
	for ring in range(0, reach + 1):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var key := Vector2i(_center.x + dx, _center.y + dz)
				if not _dressed.has(key) and _land.loaded(key):
					_dress(key, ring <= tuft_radius)
					left -= 1
					if left <= 0:
						return


func _undress(key: Vector2i) -> void:
	if _dressed.has(key):
		(_dressed[key] as Node3D).queue_free()
		_dressed.erase(key)
		gather.drop_chunk(key)
		_clutter_drop(key)


# (polish1 item 97) A piece standing on the ground as it is DRAWN (the chunk's own mesh, not the smooth height it was
# made from), sunk to the lowest point under its foot and tilted with the slope, so nothing floats or juts out of a hill.
func _on_ground(x: float, z: float, turn: float, grow: float, radius: float, lean: float = 1.0, sink: float = 0.0) -> Transform3D:
	var h := _ground_y(x, z)
	var reach := clampf(radius * 0.6, 0.2, 2.0)
	var e := _ground_y(x + reach, z)
	var w := _ground_y(x - reach, z)
	var s := _ground_y(x, z + reach)
	var n := _ground_y(x, z - reach)
	var up := Vector3.UP.lerp(Vector3(w - e, 2.0 * reach, n - s).normalized(), lean).normalized()  # (polish1 F1a) `lean`: how far it leans with the slope
	var tilt := Basis(Quaternion(Vector3.UP, up)) if up.dot(Vector3.UP) < 0.9999 else Basis()
	var low := minf(h, minf(minf(e, w), minf(s, n)))
	if lean < 0.5:  # (polish1 F1a) an upright piece on a steep slope (a crag) stands between its middle and the lowest ground: the lowest buried it
		low = lerpf(h, low, 0.5)
	return Transform3D((tilt * Basis(Vector3.UP, turn)).scaled(Vector3.ONE * grow), Vector3(x, low - 0.05 - sink, z))


# (polish1 item 155) An upright thing's foot (trees, work nodes): the lowest drawn ground under a ring of that radius, a
# little lower, so no side of it hangs over a slope. Trees and nodes went by the smooth height, up to half a metre off the drawn ground.
func _foot_y(x: float, z: float, radius: float) -> float:
	var low := _ground_y(x, z)
	for k in 4:
		var a := TAU * float(k) / 4.0 + 0.785
		low = minf(low, _ground_y(x + cos(a) * radius, z + sin(a) * radius))
	return low - 0.08


# (2026-11-23) True where the DRAWN ground (the chunk mesh) slopes more than about 40 degrees round a point.
func _drawn_steep(x: float, z: float) -> bool:
	var e := 0.8
	var n := Vector3(_ground_y(x - e, z) - _ground_y(x + e, z), 2.0 * e, _ground_y(x, z - e) - _ground_y(x, z + e)).normalized()
	return n.y < 0.76


func _ground_y(x: float, z: float) -> float:
	var here: Vector2 = _land.call("ground", x, z)
	return terrain.height(x, z) if is_nan(here.x) else here.x


# Clutter is drawn by ONE MultiMesh per model for the whole dressed land (a draw call per kind of boulder, however
# many chunks are in range); a chunk adds its pieces when it is dressed and takes them out when it is stripped.
func _clutter_add(key: Vector2i, id: String, where: Transform3D) -> void:
	if not _clutter.has(id):
		var mesh := _mesh(id)
		if mesh == null:
			return
		var fresh := MultiMesh.new()
		fresh.transform_format = MultiMesh.TRANSFORM_3D
		fresh.mesh = mesh
		fresh.instance_count = 64
		fresh.visible_instance_count = 0
		var drawn := MultiMeshInstance3D.new()
		drawn.multimesh = fresh
		drawn.custom_aabb = AABB(Vector3(-1.0e5, -2000.0, -1.0e5), Vector3(2.0e5, 4000.0, 2.0e5))  # pieces come and go: never culled as a whole (polish1 item 112: the old +-1100 m box was smaller than the 6 km world, so far pieces vanished from some angles while their colliders stayed)
		add_child(drawn)
		_clutter[id] = {"many": fresh, "at": [], "of": []}
	var pool: Dictionary = _clutter[id]
	var many: MultiMesh = pool["many"]
	var at: Array = pool["at"]
	if at.size() >= many.instance_count:  # full: twice the room (a MultiMesh forgets its instances when resized)
		many.instance_count = at.size() * 2
		for i in at.size():
			many.set_instance_transform(i, at[i])
	many.set_instance_transform(at.size(), where)
	at.append(where)
	(pool["of"] as Array).append(key)
	many.visible_instance_count = at.size()


func _clutter_drop(key: Vector2i) -> void:
	for id: String in _clutter:
		var pool: Dictionary = _clutter[id]
		var many: MultiMesh = pool["many"]
		var at: Array = pool["at"]
		var of: Array = pool["of"]
		for i in range(at.size() - 1, -1, -1):
			if of[i] == key:  # the last piece takes the place of the one that goes
				var last := at.size() - 1
				if i != last:
					at[i] = at[last]
					of[i] = of[last]
					many.set_instance_transform(i, at[i])
				at.pop_back()
				of.pop_back()
		many.visible_instance_count = at.size()


func _mesh(id: String) -> Mesh:
	if not _meshes.has(id):
		if id.contains("#"):  # (polish1 items 106 / 109) "model#node": the node's model with its look (data nodes "look")
			var parts := id.split("#")
			_meshes[id] = NodeLooks.compose(_mesh(parts[0]), (_node_data.get(parts[1], {}) as Dictionary).get("look", {}))
		else:
			_meshes[id] = FantasyModels.mesh(id)
		if _meshes[id] != null:
			(_meshes[id] as Mesh).resource_name = id  # named for checks (!f1a ground)
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
		_place(by_model, String(tree[0]), float(tree[1]), _foot_y(float(tree[1]), float(tree[2]), 0.5 * float(tree[3])), float(tree[2]), float(tree[3]), float(tree[4]))  # (polish1 item 155) on the drawn ground
		_trunk(trunks, float(tree[1]), float(tree[2]), 0.3 * float(tree[3]))
	for thing: Array in layout.clutter(key):  # boulders, logs, bushes: [model, x, z, grow, turn, radius, (tilt, sink: a country's rock)]
		_clutter_add(key, String(thing[0]), _on_ground(float(thing[1]), float(thing[2]), float(thing[4]), float(thing[3]), float(thing[5]) if thing.size() > 5 else 0.6,
			float(thing[6]) if thing.size() > 6 else 1.0, float(thing[7]) if thing.size() > 7 else 0.0))
		if not layout.walked_over(String(thing[0])):  # bushes and stumps are walked through; boulders, spires and logs stay solid
			_trunk(trunks, float(thing[1]), float(thing[2]), float(thing[5]))
	for node: Array in layout.nodes(key):  # things to work on: [slot, node id, x, y, z, turn]
		var def: Dictionary = _node_data[String(node[1])]
		var node_y := float(node[3])
		if absf(node_y - terrain.height(float(node[2]), float(node[4]))) < 0.05:  # (polish1 item 155) a node on land (not a fishing spot on the water): on the drawn ground
			if _drawn_steep(float(node[2]), float(node[4])):
				continue  # (2026-11-23) the drawn land is a steep face here (a terrace edge the smooth height calls flat): wheat stood buried in such faces
			var tree := String(def["skill"]) == "woodcutting"
			node_y = _foot_y(float(node[2]), float(node[4]), 0.5 if tree else 0.2) + (0.0 if tree else 0.04)  # crops, herbs, ore: by their middle, only a little sunk
		var model_id := String(def["model"]) + ("#" + String(node[1]) if def.has("look") else "")  # a node with a look has its own mesh, apart from the scenery
		var index := _place(by_model, model_id, float(node[2]), node_y, float(node[4]), float((def.get("look", {}) as Dictionary).get("scale", 1.0)), float(node[5]))
		gather.add_node(key, int(node[0]), String(node[1]), Vector3(float(node[2]), node_y, float(node[4])), model_id, index)
		if String(def["skill"]) == "woodcutting":
			_trunk(trunks, float(node[2]), float(node[4]), 0.35)
		elif String(def["skill"]) == "mining" and not layout.walked_over(String(def["model"])):  # a rock is as wide as its model (the low ore rocks are walked over)
			var rock: Dictionary = layout.props.get(String(def["model"]), {})
			_trunk(trunks, float(node[2]), float(node[4]), maxf(maxf(float(rock.get("w", 0.9)), float(rock.get("d", 0.9))) * 0.4, 0.35))
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
	var lake_near := false  # only chunks by a lake need the (slow) water rule per tuft
	for lake: Dictionary in terrain.lakes:
		if Vector2(x0 + size * 0.5 - float(lake["x"]), z0 + size * 0.5 - float(lake["z"])).length() < float(lake["r"]) + size:
			lake_near = true
	for i in count:
		var x := x0 + FantasyTerrain.hash01(key.x, key.y, 1000 + i * 2) * size
		var z := z0 + FantasyTerrain.hash01(key.x, key.y, 1001 + i * 2) * size
		var here: Vector2 = _land.call("ground", x, z)  # height and trodden-ness from the chunk's own mesh
		var h := here.x
		if is_nan(h):
			h = terrain.height(x, z)
			here.y = terrain.trodden(x, z)
		if h < terrain.sea + 0.5 or here.y >= 0.3 or (lake_near and terrain.water_at(x, z) != ""):
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
