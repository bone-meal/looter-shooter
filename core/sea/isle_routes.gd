# Purpose: pure rules for an island's generated paths (director: "check proper paths to each poi are generated on each
# island, and the path can actually be used"): the path network of data/sea/isles/<island>.json ("start", "pois",
# "paths", "walk_into"; made by tools/blender/sea_isle_kit.py route) as a graph, whether every place joins the start,
# and the way along the paths from one place to another (for the walk check, tools/isle_walker.gd).
# Island-local metres, x east, z south.
# Dependencies: none.
extends RefCounted

const JOIN := 3.0  # path points this close count as one junction
const AT_PATH := 12.0  # a place must lie this close to a path point

var start := ""
var pois := {}  # name -> Vector2
var walk_into := {}  # name -> Vector2 (beyond the doorstep: inside / on top)
var points: Array[Vector2] = []
var _links: Array = []  # per point: Array of point indexes


func _init(island: Dictionary) -> void:
	start = String(island.get("start", ""))
	for name: String in island.get("pois", {}):
		pois[name] = _v(island["pois"][name])
	for name: String in island.get("walk_into", {}):
		walk_into[name] = _v(island["walk_into"][name])
	for line: Array in island.get("paths", []):
		var first := points.size()
		for p: Array in line:
			points.append(_v(p))
			_links.append([])
		for i in range(first, points.size() - 1):
			_link(i, i + 1)
	var cell := {}  # grid buckets so joining is not every point against every point
	for i in points.size():
		var key := Vector2i(floori(points[i].x / JOIN), floori(points[i].y / JOIN))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j: int in cell.get(key + Vector2i(dx, dz), []):
					if points[i].distance_to(points[j]) < JOIN:
						_link(i, j)
		if not cell.has(key):
			cell[key] = []
		(cell[key] as Array).append(i)


static func _v(p: Variant) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


func _link(i: int, j: int) -> void:
	if not (_links[i] as Array).has(j):
		(_links[i] as Array).append(j)
		(_links[j] as Array).append(i)


func nearest(at: Vector2) -> int:
	var best := -1
	var gap := INF
	for i in points.size():
		var d := points[i].distance_to(at)
		if d < gap:
			gap = d
			best = i
	return best


# The problems of the network ([] = every place joins the start by paths).
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if points.is_empty() or not pois.has(start):
		out.append("no paths or no start place")
		return out
	var reached := _reach(nearest(pois[start]))
	for name: String in pois:
		var i := nearest(pois[name])
		if points[i].distance_to(pois[name]) > AT_PATH:
			out.append("%s: %.0f m from the nearest path" % [name, points[i].distance_to(pois[name])])
		elif not reached.has(i):
			out.append("%s: its path does not join %s" % [name, start])
	return out


func _reach(from: int) -> Dictionary:
	var seen := {from: true}
	var todo: Array[int] = [from]
	while not todo.is_empty():
		var cur: int = todo.pop_back()
		for nb: int in _links[cur]:
			if not seen.has(nb):
				seen[nb] = true
				todo.append(nb)
	return seen


# The way along the paths between two places (path points, island-local), ending exactly at `to`; [] = none.
func way(from: Vector2, to: Vector2) -> Array[Vector2]:
	var a := nearest(from)
	var b := nearest(to)
	var out: Array[Vector2] = []
	if a < 0 or b < 0:
		return out
	var dist := {a: 0.0}
	var came := {}
	var open := {a: true}
	while not open.is_empty():
		var cur := -1
		var low := INF
		for i: int in open:
			if float(dist[i]) < low:
				low = dist[i]
				cur = i
		open.erase(cur)
		if cur == b:
			break
		for nb: int in _links[cur]:
			var d := float(dist[cur]) + points[cur].distance_to(points[nb])
			if d < float(dist.get(nb, INF)):
				dist[nb] = d
				came[nb] = cur
				open[nb] = true
	if not dist.has(b):
		return out
	var at := b
	while at != a:
		out.push_front(points[at])
		at = came[at]
	out.push_front(points[a])
	out.append(to)
	return out
