# Purpose: a BIG island streamed in pieces (director 2026-11-16: the start island grows to ~1.6 km for the port town):
# its ground comes in chunks (data/sea/isles/<island>.json "chunks": size + reach; model nodes <model>_i_j and
# <model>_i_j_far from tools/blender/sea_isle_kit.py ground_chunks). Near chunks are drawn close by and far ones beyond
# (visibility ranges); a chunk is SOLID at full detail only near the player (else its coarse far shape, so ships still
# run aground everywhere); trees, rocks and set pieces stand for the whole island, small clutter (grass, ferns,
# flowers, shells, coral ...) and the props' colliders only in chunks near the player.
# Dependencies: game/sea_isle_props.gd (drawing props, colliders, set pieces), data/sea/islands.json "props".
# Made by game/sea_islands.gd, which runs setup()'s steps a few a frame (sea step 13g) and calls follow() with the
# players' island-local positions.
extends Node3D

const IsleProps = preload("res://game/sea_isle_props.gd")
const NEAR_SHOWN := 340.0  # a chunk's centre this close: its full-detail ground is drawn (beyond: the far one)
const SOLID_ON := 230.0  # a chunk's centre this close: full-detail collision and its props' colliders
const SOLID_OFF := 360.0
const SMALL_ON := 260.0  # a chunk's centre this close: its small clutter is drawn
const SMALL_OFF := 380.0
const SMALL_RANGE := 260.0  # props drawn no farther than this are "small clutter" (streamed per chunk)

var _big_drawn := 0
var _chunks := {}  # "i_j" -> {"centre": Vector2, "near", "far": MeshInstance3D, "near_body", "far_body": Node, "small": Node3D, "solid": Node}
var _cfg: Dictionary
var _graphics := ""
var _solid_list := {}


# model = the island's instantiated ground model (this node's child), list = its data/sea/isles json, sorted =
# bucket(list, cfg, graphics) (worked out off the main thread; {} = work it out here). Maps the chunks now and returns
# the rest of the setup as small steps (Callables) for game/sea_islands.gd to run a few at a time (sea step 13g).
func setup(model: Node3D, ground: Material, list: Dictionary, cfg: Dictionary, graphics: String, sorted: Dictionary = {}) -> Array:
	_cfg = cfg
	_graphics = graphics
	_solid_list = list.get("solid", {})
	var size := float(list["chunks"]["size"])
	var reach := float(list["chunks"]["reach"])
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		mesh.material_override = ground
		var parts := String(mesh.name).split("_")
		var far := parts[parts.size() - 1] == "far"
		var at := parts.size() - (3 if far else 2)
		if at < 0 or not parts[at].is_valid_int() or not parts[at + 1].is_valid_int():
			continue
		var key := "%s_%s" % [parts[at], parts[at + 1]]
		if not _chunks.has(key):
			_chunks[key] = {"centre": Vector2(-reach + (float(parts[at]) + 0.5) * size, -reach + (float(parts[at + 1]) + 0.5) * size), "small": null, "solid": null, "near_body": null, "far_body": null, "props": []}
		var chunk: Dictionary = _chunks[key]
		chunk["far" if far else "near"] = mesh
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		if far:
			mesh.visibility_range_begin = NEAR_SHOWN
			mesh.visibility_range_begin_margin = 20.0
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		else:
			mesh.visibility_range_end = NEAR_SHOWN
			mesh.visibility_range_end_margin = 20.0
	if sorted.is_empty():
		sorted = bucket(list, cfg, graphics)
	for key: String in sorted["small"]:
		if _chunks.has(key):
			_chunks[key]["props"] = sorted["small"][key]
	for key: String in sorted["solid_big"]:  # the big props' colliders go with their chunk
		if _chunks.has(key):
			_chunks[key]["solid_props"] = sorted["solid_big"][key]
	var steps: Array = []
	for g: Dictionary in sorted["big"]:
		steps.append(func() -> void: _big_drawn += IsleProps.add_group(self, g))
	for p: Array in list.get("places", []):
		steps.append(func() -> void:
			if IsleProps.place(self, p):
				_big_drawn += 1)
	for key: String in _chunks:  # every chunk starts solid in its coarse shape (unless a player stands on it by then)
		var chunk_f: Dictionary = _chunks[key]
		steps.append(func() -> void:
			if chunk_f["near_body"] == null:
				_far_solid(chunk_f, true))
	return steps


# The list's props sorted by chunk "i_j": plain data, safe off the main thread (sea step 13g). small = clutter drawn
# per chunk near the player, big = the rest as IsleProps.groups_of() patches, solid_big = the big props with colliders.
static func bucket(list: Dictionary, cfg: Dictionary, graphics: String) -> Dictionary:
	var size := float(list["chunks"]["size"])
	var reach := float(list["chunks"]["reach"])
	var ranges: Dictionary = cfg["range"]
	var solid: Dictionary = list.get("solid", {})
	var small := {}
	var solid_big := {}
	var big: Array = []
	for p: Array in list["props"]:
		var key := "%d_%d" % [floori((float(p[1]) + reach) / size), floori((float(p[3]) + reach) / size)]
		if float(ranges.get(String(p[0]), ranges["default"])) <= SMALL_RANGE:
			if not small.has(key):
				small[key] = []
			(small[key] as Array).append(p)
		else:
			big.append(p)
			if solid.has(String(p[0])):
				if not solid_big.has(key):
					solid_big[key] = []
				(solid_big[key] as Array).append(p)
	return {"small": small, "solid_big": solid_big, "big": IsleProps.groups_of(big, cfg, graphics)}


# Call every half second or so with island-local positions (x, z): points[0] is this machine's own player when own
# is true (small clutter follows only him); every point keeps the chunks round it solid at full detail (on the host
# that is every player at sea, director 2026-11-16 "1").
func follow(points: Array, own: bool = true) -> void:
	for key: String in _chunks:
		var chunk: Dictionary = _chunks[key]
		var centre: Vector2 = chunk["centre"]
		var solid_d := INF
		for point: Vector2 in points:
			solid_d = minf(solid_d, point.distance_to(centre))
		if solid_d < SOLID_ON and chunk["near_body"] == null:
			_near_solid(chunk, true)
		elif solid_d > SOLID_OFF and chunk["near_body"] != null:
			_near_solid(chunk, false)
		var d := (points[0] as Vector2).distance_to(centre) if own and not points.is_empty() else INF
		if d < SMALL_ON and chunk["small"] == null and not (chunk["props"] as Array).is_empty():
			var small := Node3D.new()
			add_child(small)
			chunk["small"] = small
			small.set_meta("count", IsleProps.draw(small, chunk["props"], _cfg, _graphics))
		elif d > SMALL_OFF and chunk["small"] != null:
			(chunk["small"] as Node3D).queue_free()
			chunk["small"] = null


func _near_solid(chunk: Dictionary, on: bool) -> void:
	if on:
		if chunk.get("near") != null:
			var before := (chunk["near"] as Node).get_child_count()
			(chunk["near"] as MeshInstance3D).create_trimesh_collision()
			if (chunk["near"] as Node).get_child_count() > before:
				chunk["near_body"] = (chunk["near"] as Node).get_child((chunk["near"] as Node).get_child_count() - 1)
		var props: Array = (chunk.get("solid_props", []) as Array).duplicate()
		props.append_array((chunk["props"] as Array).filter(func(p: Array) -> bool: return _solid_list.has(String(p[0]))))
		if not props.is_empty():
			chunk["solid"] = IsleProps.solids(self, props, _solid_list)
		_far_solid(chunk, false)
	else:
		if chunk["near_body"] != null:
			(chunk["near_body"] as Node).queue_free()
		chunk["near_body"] = null
		if chunk["solid"] != null:
			(chunk["solid"] as Node).queue_free()
		chunk["solid"] = null
		_far_solid(chunk, true)


func _far_solid(chunk: Dictionary, on: bool) -> void:
	if on and chunk["far_body"] == null and chunk.get("far") != null:
		var before := (chunk["far"] as Node).get_child_count()
		(chunk["far"] as MeshInstance3D).create_trimesh_collision()
		if (chunk["far"] as Node).get_child_count() > before:
			chunk["far_body"] = (chunk["far"] as Node).get_child((chunk["far"] as Node).get_child_count() - 1)
	elif not on and chunk["far_body"] != null:
		(chunk["far_body"] as Node).queue_free()
		chunk["far_body"] = null


# Taking the island down (game/sea_islands.gd, sea step 13g): lets go of up to n chunks' prop lists at a time, so the
# big lists are not all freed in one frame (~40 ms). Returns false once none are left.
func shed(n: int) -> bool:
	var keys := _chunks.keys()
	for i in mini(n, keys.size()):
		_chunks.erase(keys[i])
	return not _chunks.is_empty()


func drawn() -> int:  # copies of props standing now (checks)
	var n := _big_drawn
	for key: String in _chunks:
		if _chunks[key]["small"] != null:
			n += int((_chunks[key]["small"] as Node).get_meta("count", 0))
	return n


func chunk_counts() -> Vector3i:  # (chunks, solid at full detail, with clutter) for checks
	var solid := 0
	var small := 0
	for key: String in _chunks:
		if _chunks[key]["near_body"] != null:
			solid += 1
		if _chunks[key]["small"] != null:
			small += 1
	return Vector3i(_chunks.size(), solid, small)
