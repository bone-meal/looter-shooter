# Purpose: (polish1 D4a, director: "Navmesh") the islands' navigation mesh: baked at load from every static collider
# of the archipelago (ground with its hills, ridges, ruins, boulders, huts, machines, bridges, debris ...) on its own
# navigation map, so island enemies walk round obstacles and up hills to their prey (game/enemy.gd `nav_map`).
# Cleared debris re-bakes it (in the background; the old mesh is used meanwhile). Only the machine that runs the
# island's enemies needs it (alone or hosting); it is cheap to keep everywhere.
# Dependencies: core/archipelago.gd (the area), game/island.gd (CENTER). Parsing runs on the main thread, baking on a worker.
extends Node3D

signal baked(seconds: float)

var map := RID()
var _region: NavigationRegion3D
var _mesh: NavigationMesh
var _source := NavigationMeshSourceGeometryData3D.new()
var _baking := false
var _again := false
var _root: Node
var _started := 0
var _area: Rect2  # the archipelago seen from above (world x, z)


func setup(root: Node, land: RefCounted, centre: Vector3) -> void:
	_root = root
	map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, 0.3)
	NavigationServer3D.map_set_cell_height(map, 0.2)
	NavigationServer3D.map_set_active(map, true)
	_mesh = NavigationMesh.new()
	_mesh.cell_size = 0.3
	_mesh.cell_height = 0.2
	_mesh.agent_radius = 0.5
	_mesh.agent_height = 1.7
	_mesh.agent_max_climb = 0.45
	_mesh.agent_max_slope = 42.0
	_mesh.region_min_size = 4.0
	_mesh.edge_max_error = 1.5
	_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	_mesh.geometry_source_group_name = &"island_nav"
	var mid: Vector2 = land.call("middle")
	var reach := float(land.call("reach"))
	_area = Rect2(centre.x + mid.x - reach, centre.z + mid.y - reach, reach * 2.0, reach * 2.0)
	_mesh.filter_baking_aabb = AABB(Vector3(centre.x + mid.x - reach, centre.y - 25.0, centre.z + mid.y - reach), Vector3(reach * 2.0, 60.0, reach * 2.0))
	_region = NavigationRegion3D.new()
	_region.navigation_mesh = _mesh
	add_child(_region)
	_region.set_navigation_map(map)


# (Re)bakes from what stands there now. Called once the islands and their things are built, and after debris clears.
func rebuild() -> void:
	if _baking:
		_again = true
		return
	_baking = true
	_started = Time.get_ticks_msec()
	_source.clear()
	_tag(_root)  # every static body at the islands goes into the group the parser reads
	NavigationServer3D.parse_source_geometry_data(_mesh, _source, _root)
	var fresh := NavigationMesh.new()
	for prop: Dictionary in _mesh.get_property_list():
		if (prop["usage"] as int) & PROPERTY_USAGE_STORAGE and String(prop["name"]) not in ["vertices", "polygons"]:
			fresh.set(String(prop["name"]), _mesh.get(String(prop["name"])))
	NavigationServer3D.bake_from_source_geometry_data_async(fresh, _source, _done.bind(fresh))


func _tag(node: Node) -> void:
	for child in node.get_children():
		if child is StaticBody3D:
			var p := (child as Node3D).global_position
			if _area.has_point(Vector2(p.x, p.z)) and not child.is_in_group(&"island_nav") and not child.is_in_group(&"nav_skip"):  # (doors: open / shut)
				child.add_to_group(&"island_nav")
		elif child.get_child_count() > 0 and not (child is CharacterBody3D) and not (child is Control):
			_tag(child)


func _done(fresh: NavigationMesh) -> void:
	_apply.call_deferred(fresh)  # (the bake finishes on a worker thread)


func _apply(fresh: NavigationMesh) -> void:
	_mesh = fresh
	_region.navigation_mesh = fresh
	_baking = false
	var secs := float(Time.get_ticks_msec() - _started) / 1000.0
	print("[island nav] baked in %.2f s: %d polygons" % [secs, fresh.get_polygon_count()])
	baked.emit(secs)
	if _again:
		_again = false
		rebuild()


func ready_to_use() -> bool:
	return map.is_valid() and _region != null and _region.navigation_mesh != null and _region.navigation_mesh.get_polygon_count() > 0
