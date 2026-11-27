# Purpose: pure shape of the fantasy world: for any point, which regions it belongs to (they blend into each other),
# the ground height, the ground colour, the mood (fog, sky, light) and the enemy level. Every machine computes the same
# land from the same data, so the host and the clients agree where the ground is. No nodes.
# A COUNTRY (polish1 F1a: data/fantasy/countries/<id>.json, made into world data by core/country_world.gd) has a
# "shape" instead: its big land comes from core/country_shape.gd and its regions are the looks its zones wear.
# Dependencies: core/country_shape.gd (uses the engine's FastNoiseLite). Data: data/fantasy/world.json or a country.
extends RefCounted

const CountryShape = preload("res://core/country_shape.gd")

const RULES_VERSION := 13  # raise when these rules change the shape or colour of the land: saved charts are then painted afresh
const RING_HEIGHT := 34.0  # the mountain ring around the last region
const RING_WIDTH := 42.0
const PASS_ANGLE := 0.5  # radians: how wide the gap in the ring is (it faces south, towards the start)
const BEACH := Color(0.9, 0.84, 0.62)

var data: Dictionary
var regions: Array
var places: Array
var size: float
var sea: float

var _noise := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _blend: float
var _ring_center := Vector2.ZERO
var _ring_radius := 0.0
var lakes: Array = []  # {"id", "name", "x", "z", "r", "depth", "level", "water"}: level is worked out from the land around
var roads: Array = []  # PackedVector2Array per road: a bent line between two places
var road_ends: Array = []  # (polish1 item 123) per road (same order): [place id at its start, place id at its end]
var areas: Array = []  # (polish1 item 129) named areas: {"id", "name", "region", "x", "z" (where the map / compass name it), "cx", "cz" (a circle's centre), "radius", "inner", "road" (PackedVector2Array or empty), "width"}
var _place_level := PackedFloat32Array()  # ground level of each place (same order as `places`)
var _ready_places := false
var _calm_at := PackedVector3Array()  # places and lakes: (x, z, radius inside which the land is calm)
var _calm_out := PackedFloat32Array()  # ... and the radius from which it is fully wild again
var _flat_at := PackedVector3Array()  # every place, same order as `places`: (x, z, flat radius)
var _reach := PackedFloat32Array()  # every place: the radius where its level ground has eased back into the land
var _trod_in := PackedFloat32Array()  # every place: the radius of its fully trodden middle
var _lake_at := PackedVector3Array()  # every lake, same order as `lakes`: (x, z, radius)
var _lake_level := PackedFloat32Array()
var _lake_depth := PackedFloat32Array()
var _seg_a := PackedVector2Array()  # every stretch of path: its two ends ...
var _seg_b := PackedVector2Array()
var _seg_cells := {}  # ... and which stretches pass near each SEG_CELL square: Vector2i -> PackedInt32Array
var _no_segments := PackedInt32Array()
var _seg_road := PackedInt32Array()  # (polish1 F3) every stretch of path: which road it is part of ...
var _seg_from := PackedFloat32Array()  # ... and how many metres of that road lie before it
var _grade: Array = []  # (polish1 F3, countries) per road: the graded road bed's height every GRADE_STEP m (PackedFloat32Array)
var _grade_bridge: Array = []  # ... and where it is a bridge deck over water (PackedByteArray: 1 = bridge)
var _road_most := PackedFloat32Array()  # per road: the steepest it climbs (GRADE_MOST unless its data says otherwise)
var _graded := false  # true once the road beds are worked out (they are measured on the land without them)
var bridges: Array = []  # (polish1 F3) {"id", "x", "z", "y" (deck top), "spans": [[x, z, turn]]}: every bridge carrying a road over water
var _cones: Array = []  # volcano cones: {"x", "z", "crater", "rim", "radius", "height", "open" (bearing of the way in)}
var country_shape: RefCounted = null  # (polish1 F1a) a country's compiled shape (core/country_shape.gd), null for the old world
var _levels := Vector2(1, 50)  # a country's level band
var _snowline := INF  # a country's snowline (metres): above it the land is white
const SNOW := Color(0.93, 0.95, 0.98)
var _spawn := Vector2.ZERO
const RELIEF := 0.8  # a country: how much of a look's own hills and landforms stand on the big land
const RIVER_DEPTH := 1.4  # metres of water in the middle of a river
const PEAKS := 62.0  # a country's high ground: metres of sharp ridges and peaks the mountains carry over their big shape
const GULLIES := 9.0  # metres the rain has cut gullies into steep slopes
const SPURS := 18.0  # metres the rock spurs between the gullies stand out of a big mountain face
const ROLL := 6.0  # metres of rolling hills on the lowlands
const LEDGE := 7.0  # metres between the rock ledges on steep high ground
var _ridges := FastNoiseLite.new()  # (polish1 F1a) a country's ridgelines: ridged noise bent by a warp
var _gullies := FastNoiseLite.new()
var _roll := FastNoiseLite.new()

const ROAD_WIDTH := 2.3  # half width of a path, metres
const SEG_CELL := 80.0  # paths are looked up through a grid of squares this wide
const CALM_NEAR := 7.0  # this close to a path the land has none of its wild landforms ...
const GRADE_STEP := 4.0  # (polish1 F3) a graded road bed is measured every so many metres along its road
const GRADE_IN := 3.2  # this close to a road's middle the ground IS the road bed ...
const GRADE_OUT := 12.0  # ... and from here on the land is its own again (cuttings and banks between)
const GRADE_MOST := 0.26  # the steepest a road climbs unless its data says otherwise (rise per metre: about 15 degrees)
const BRIDGE_MOST := 32.0  # metres of water a road will bridge (wider = a lake or the sea: the road needs a bend in its data)
const BRIDGE_CLEAR := 1.1  # metres a bridge deck clears the water by
const CALM_FAR := 40.0  # ... and from here on all of them: a path through mountains runs in a pass
const DIRT := Color(0.46, 0.38, 0.27)
const PAVED := Color(0.5, 0.48, 0.45)


func _init(world_data: Dictionary) -> void:
	data = world_data
	regions = data["regions"]
	places = data["places"]
	size = float(data["size"])
	sea = float(data["sea_level"])
	_blend = float(data["blend"]) / 3.0
	_noise.seed = int(data["seed"])
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_octaves = 3
	_noise.frequency = 1.0
	_detail.seed = int(data["seed"]) + 11
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.fractal_octaves = 2
	_detail.frequency = 1.0 / 17.0
	_ridges.seed = int(data["seed"]) + 23
	_ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridges.fractal_octaves = 5
	_ridges.fractal_gain = 0.52
	_ridges.frequency = 1.0 / 420.0
	_ridges.domain_warp_enabled = true
	_ridges.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	_ridges.domain_warp_amplitude = 90.0
	_ridges.domain_warp_frequency = 1.0 / 700.0
	_gullies.seed = int(data["seed"]) + 29
	_gullies.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_gullies.fractal_octaves = 3
	_gullies.frequency = 1.0 / 70.0
	_roll.seed = int(data["seed"]) + 31
	_roll.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_roll.fractal_octaves = 3
	_roll.frequency = 1.0 / 260.0
	if data.has("shape"):
		country_shape = CountryShape.new(data, float(data.get("grid", 16.0)))
		var picked: Array = []  # the regions are the looks, in the shape's order
		for look: String in country_shape.looks:
			for template: Dictionary in data["regions"]:
				if String(template["id"]) == look:
					picked.append(template)
		regions = picked
		var band := String(data.get("levels", "1-50")).split("-")
		_levels = Vector2(float(band[0]), float(band[band.size() - 1]))
		var low: Array = data.get("low_at", data["spawn"])
		_spawn = Vector2(float(low[0]), float(low[1]))
		_snowline = float(data.get("snowline", INF))
	else:
		var last: Dictionary = regions[regions.size() - 1]
		_ring_center = Vector2(float(last["center"][0]), float(last["center"][1]))
		_ring_radius = float(last["radius"]) + 30.0
	for p: Dictionary in places:
		_place_level.append(maxf(_raw_height(float(p["pos"][0]), float(p["pos"][1])), sea + 1.2))
		var flat := float(p.get("flat", 0.0))
		_flat_at.append(Vector3(float(p["pos"][0]), float(p["pos"][1]), flat))
		_reach.append(float(p.get("reach", flat * 1.5)))
		_trod_in.append(flat * (0.72 if String(p["kind"]).begins_with("town") or String(p["kind"]) == "arena" else 0.4))
		if flat > 0.0:
			_calm_at.append(Vector3(float(p["pos"][0]), float(p["pos"][1]), float(p["flat"]) * 1.1))
			_calm_out.append(maxf(float(p["flat"]) * 3.0, _reach[_reach.size() - 1]))
	_ready_places = true
	for entry: Dictionary in data.get("lakes", []):
		_calm_at.append(Vector3(float(entry["pos"][0]), float(entry["pos"][1]), float(entry["radius"]) + 8.0))
		_calm_out.append(float(entry["radius"]) + 45.0)
	for region: Dictionary in regions:
		var cone: Dictionary = (region["height"] as Dictionary).get("cone", {})
		var heart := place(String(cone.get("place", "")))
		if not heart.is_empty():
			var door := place(String(cone.get("open_to", "")))
			var way := Vector2(float(door["pos"][0]) - float(heart["pos"][0]), float(door["pos"][1]) - float(heart["pos"][1])).angle() if not door.is_empty() else 0.0
			_cones.append({"x": float(heart["pos"][0]), "z": float(heart["pos"][1]), "crater": float(cone["crater"]), "rim": float(cone["rim"]), "radius": float(cone["radius"]), "height": float(cone["height"]), "open": way})
	for entry: Dictionary in data.get("lakes", []):
		var lx := float(entry["pos"][0])
		var lz := float(entry["pos"][1])
		lakes.append({"id": String(entry["id"]), "name": String(entry.get("name", "")), "x": lx, "z": lz, "r": float(entry["radius"]), "depth": float(entry["depth"]),
			"level": maxf(_placed_height(lx, lz) - 0.7, sea + 0.6), "water": String(entry.get("water", "fresh"))})
	for pair: Array in data.get("roads", []):
		var a := place(String(pair[0]))
		var b := place(String(pair[1]))
		if a.is_empty() or b.is_empty():
			continue
		var from := Vector2(float(a["pos"][0]), float(a["pos"][1]))
		var to := Vector2(float(b["pos"][0]), float(b["pos"][1]))
		var bend := (to - from).orthogonal().normalized() * (to - from).length() * 0.14 * (hash01(int(from.x), int(to.y), 5) - 0.5) * 2.0
		var middle := (from + to) * 0.5 + bend
		var most := GRADE_MOST
		for k in range(2, pair.size()):  # (polish1 F3) a road may name the point it bends through ([x, z]: round a lake, a hill) and how steep it may climb (a number)
			if pair[k] is Array:
				middle = Vector2(float(pair[k][0]), float(pair[k][1]))
			else:
				most = float(pair[k])
		_road_most.append(most)
		roads.append(PackedVector2Array([from, middle, to]))
		road_ends.append([String(pair[0]), String(pair[1])])
	for entry: Dictionary in data.get("areas", []):
		var area := {"id": String(entry["id"]), "name": String(entry.get("name", "")), "region": String(entry.get("region", "")), "radius": float(entry.get("radius", 0.0)),
			"inner": float(entry.get("inner", 0.0)), "road": PackedVector2Array(), "width": float(entry.get("width", 0.0))}
		if entry.has("road"):
			var ends: Array = entry["road"]
			for road: PackedVector2Array in roads:
				var a0 := place(String(ends[0]))
				var b0 := place(String(ends[1]))
				var pa := Vector2(float(a0.get("pos", [0, 0])[0]), float(a0.get("pos", [0, 0])[1]))
				var pb := Vector2(float(b0.get("pos", [0, 0])[0]), float(b0.get("pos", [0, 0])[1]))
				if (road[0].is_equal_approx(pa) and road[2].is_equal_approx(pb)) or (road[0].is_equal_approx(pb) and road[2].is_equal_approx(pa)):
					area["road"] = road
			var line: PackedVector2Array = area["road"]
			if not line.is_empty():
				area["x"] = line[1].x
				area["z"] = line[1].y
		else:
			area["x"] = float(entry["pos"][0])
			area["z"] = float(entry["pos"][1])
			area["cx"] = area["x"]  # the shape's centre (x / z may move to where the name is shown)
			area["cz"] = area["z"]
			if float(area["inner"]) > 0.0:  # a ring round a place: named on its north side
				area["z"] = float(entry["pos"][1]) - (float(area["radius"]) + float(area["inner"])) * 0.5
		if area.has("x"):
			areas.append(area)
	if country_shape != null:  # a country's lakes are cut into its big land already; listed for their water and names
		for lake: Dictionary in country_shape.lakes:
			var entry := lake.duplicate()
			entry["name"] = String((data.get("lake_names", {}) as Dictionary).get(String(lake["id"]), lake.get("name", "")))  # (polish1 F3) named in the places file
			lakes.append(entry)
	for lake: Dictionary in lakes if country_shape == null else []:
		_lake_at.append(Vector3(float(lake["x"]), float(lake["z"]), float(lake["r"])))
		_lake_level.append(float(lake["level"]))
		_lake_depth.append(float(lake["depth"]))
	for road: PackedVector2Array in roads:
		for i in road.size() - 1:
			var index := _seg_a.size()
			_seg_a.append(road[i])
			_seg_b.append(road[i + 1])
			_seg_road.append(roads.find(road))
			_seg_from.append(0.0 if i == 0 else road[0].distance_to(road[1]))
			var reach := CALM_FAR + 6.0
			for cz in range(floori((minf(road[i].y, road[i + 1].y) - reach) / SEG_CELL), floori((maxf(road[i].y, road[i + 1].y) + reach) / SEG_CELL) + 1):
				for cx in range(floori((minf(road[i].x, road[i + 1].x) - reach) / SEG_CELL), floori((maxf(road[i].x, road[i + 1].x) + reach) / SEG_CELL) + 1):
					var cell := Vector2i(cx, cz)
					var list: PackedInt32Array = _seg_cells.get(cell, PackedInt32Array())
					list.append(index)
					_seg_cells[cell] = list
	if country_shape != null:
		_grade_roads()


# (polish1 item 129) The ids of the named areas a point lies in.
func areas_at(x: float, z: float) -> Array:
	var out: Array = []
	for area: Dictionary in areas:
		if area_has(area, x, z):
			out.append(String(area["id"]))
	return out


func area_has(area: Dictionary, x: float, z: float) -> bool:
	var line: PackedVector2Array = area["road"]
	var p := Vector2(x, z)
	if not line.is_empty():
		for i in line.size() - 1:
			if Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1]).distance_to(p) <= float(area["width"]):
				return true
		return false
	var d := Vector2(x - float(area["cx"]), z - float(area["cz"])).length()
	return d <= float(area["radius"]) and d >= float(area["inner"])


func area_by_id(id: String) -> Dictionary:
	for entry: Dictionary in areas:
		if String(entry["id"]) == id:
			return entry
	return {}


# One weight per region (same order as `regions`), adding up to 1: high for the region the point is in, shared
# smoothly near a border.
func weights(x: float, z: float) -> PackedFloat32Array:
	if country_shape != null:
		return country_shape.weights(x, z)
	var scores := PackedFloat32Array()
	var best := INF
	for region: Dictionary in regions:
		var score := Vector2(x - float(region["center"][0]), z - float(region["center"][1])).length() - float(region["radius"])
		scores.append(score)
		best = minf(best, score)
	var total := 0.0
	for i in scores.size():
		scores[i] = exp(-(scores[i] - best) / _blend)
		total += scores[i]
	for i in scores.size():
		scores[i] /= total
	return scores


func region_index(x: float, z: float) -> int:
	var w := weights(x, z)
	var best := 0
	for i in w.size():
		if w[i] > w[best]:
			best = i
	return best


func region_at(x: float, z: float) -> Dictionary:
	return regions[region_index(x, z)]


func region_by_id(id: String) -> Dictionary:
	for region: Dictionary in regions:
		if String(region["id"]) == id:
			return region
	return {}


func place(id: String) -> Dictionary:
	for p: Dictionary in places:
		if String(p["id"]) == id:
			return p
	return {}


# Enemy level at a point: the low end of the region's band at its edge, the high end near its heart.
func level_at(x: float, z: float) -> int:
	if country_shape != null:  # a country: its low end where you come in at its heart, its high end at its far edges
		return roundi(lerpf(_levels.x, _levels.y, clampf(Vector2(x, z).distance_to(_spawn) / (size * 0.55), 0.0, 1.0)))
	var region := region_at(x, z)
	var d := Vector2(x - float(region["center"][0]), z - float(region["center"][1])).length()
	var t := clampf(1.0 - d / float(region["radius"]), 0.0, 1.0)
	return roundi(lerpf(float(region["level"][0]), float(region["level"][1]), t))


# How wild the land may be at a point: 0 at a place, along a path and round a lake (calm ground to build and walk
# on), 1 in open country (all of the region's landforms).
func wildness(x: float, z: float) -> float:
	var wild := 1.0
	for i in _calm_at.size():
		var spot := _calm_at[i]
		var far := _calm_out[i]
		var dx := x - spot.x
		var dz := z - spot.y
		if absf(dx) < far and absf(dz) < far:
			wild = minf(wild, smoothstep(spot.z, far, sqrt(dx * dx + dz * dz)))
	var here := Vector2(x, z)
	var near: PackedInt32Array = _seg_cells.get(Vector2i(floori(x / SEG_CELL), floori(z / SEG_CELL)), _no_segments)
	for s in near:
		var a := _seg_a[s]
		var b := _seg_b[s]
		var along := clampf((here - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		wild = minf(wild, smoothstep(CALM_NEAR, CALM_FAR, here.distance_to(a + (b - a) * along)))
	return wild


# What a region's landforms add to its plain hills at a point, in metres (it can be negative). Keys of a region's
# `height` in data/fantasy/world.json: ridge (sharp mountain ridges along winding lines), mesa (table land with
# cliff edges; small `rough` makes stone pillars), gorge (winding cuts that run out into open ground now and
# then, so there is a way out), dunes (long waves of sand), terrace (the whole slope in steps). `plain` = the
# region's height there without them.
func _landforms(shape: Dictionary, x: float, z: float, plain: float) -> float:
	var add := 0.0
	if shape.has("ridge"):
		var ridge: Dictionary = shape["ridge"]
		var s := float(ridge["rough"])
		var crest := maxf(1.0 - absf(_noise.get_noise_2d(x / s + 31.7, z / s - 12.3)) * 1.6, 0.0)
		add += float(ridge["amp"]) * pow(crest, float(ridge.get("sharp", 2.0)))
	if shape.has("mesa"):
		var mesa: Dictionary = shape["mesa"]
		var s := float(mesa["rough"])
		var level := float(mesa["level"])  # the higher, the less of the land is table land
		add += float(mesa["height"]) * smoothstep(level, level + float(mesa.get("edge", 0.05)), _noise.get_noise_2d(x / s - 53.9, z / s + 27.1))
	if shape.has("dunes"):
		var dunes: Dictionary = shape["dunes"]
		var length := float(dunes["length"])
		var bend := _noise.get_noise_2d(x / (length * 3.0) + 5.0, z / (length * 3.0) - 8.0) * 6.0
		add += float(dunes["amp"]) * pow(0.5 + 0.5 * sin((x * 0.8 + z * 0.6) / length * TAU + bend), 1.6)
	if shape.has("gorge"):
		var gorge: Dictionary = shape["gorge"]
		var s := float(gorge["rough"])
		var n := _noise.get_noise_2d(x / s + 91.3, z / s + 44.4) / float(gorge.get("width", 0.07))
		var runs := smoothstep(-0.25, 0.15, _noise.get_noise_2d(x / (s * 1.7) - 19.0, z / (s * 1.7) + 61.0))
		add -= float(gorge["depth"]) * runs * exp(-n * n)
	if shape.has("terrace"):
		var terrace: Dictionary = shape["terrace"]
		var step := float(terrace["step"])
		var soft := float(terrace.get("soft", 0.3))  # the share of a step that is its slope
		var level := (plain + add) / step
		add = (floorf(level) + smoothstep(0.5 - soft * 0.5, 0.5 + soft * 0.5, level - floorf(level))) * step - plain
	return add


# The land before places are levelled and lakes cut. `wild` (see `wildness`) scales the regions' landforms.
func _raw_height(x: float, z: float, wild: float = 0.0) -> float:
	if country_shape != null:
		return _country_height(x, z, wild)
	var w := weights(x, z)
	var h := 0.0
	for i in regions.size():
		if w[i] < 0.002:
			continue
		var shape: Dictionary = regions[i]["height"]
		var rough := float(shape["rough"])
		var plain := float(shape["base"]) + float(shape["amp"]) * _noise.get_noise_2d(x / rough, z / rough)
		if wild > 0.0:
			# nothing is cut below the sea inland: the sea stays at the coast
			plain = maxf(plain + wild * _landforms(shape, x, z, plain), minf(plain, sea + 1.5))
		h += w[i] * plain
	for cone: Dictionary in _cones:  # a volcano: up to the rim, down into the crater, open on one side
		var out := Vector2(x - float(cone["x"]), z - float(cone["z"]))
		if out.length() < float(cone["radius"]):
			var up := smoothstep(float(cone["crater"]), float(cone["rim"]), out.length()) * (1.0 - smoothstep(float(cone["rim"]), float(cone["radius"]), out.length()))
			h += float(cone["height"]) * up * smoothstep(0.16, 0.42, absf(angle_difference(out.angle(), float(cone["open"]))))
	h += 0.5 * _detail.get_noise_2d(x, z)
	# the ring of mountains around the last region, open to the south
	var from_ring := Vector2(x, z) - _ring_center
	var gap := absf(angle_difference(from_ring.angle(), PI / 2.0))  # +z = south
	var wall := exp(-pow((from_ring.length() - _ring_radius) / RING_WIDTH, 2.0)) * smoothstep(PASS_ANGLE * 0.5, PASS_ANGLE, gap)
	h += RING_HEIGHT * wall * (0.75 + 0.5 * absf(_noise.get_noise_2d(x / 60.0, z / 60.0)))
	# the land ends in the sea before the edge of the map
	var edge := maxf(absf(x), absf(z))
	var shore := smoothstep(size * 0.5 - 150.0, size * 0.5 - 30.0, edge)
	return lerpf(h, sea - 3.2, shore)


# (polish1 F1a) A country's land: its big shape, each look's own hills and landforms on top (less near the sea),
# the rivers' beds cut into it.
func _country_height(x: float, z: float, wild: float) -> float:
	var big: float = country_shape.height(x, z)
	# the land's character from its big shape: how mountainous, how steep (metres a metre)
	var slope_xz := Vector2(country_shape.height(x + 12.0, z) - country_shape.height(x - 12.0, z), country_shape.height(x, z + 12.0) - country_shape.height(x, z - 12.0))
	var steep := slope_xz.length() / 24.0
	var mount := smoothstep(18.0, 150.0, big)
	var inland := smoothstep(0.5, 8.0, big)
	var tame := 0.6 + 0.4 * maxf(wild, 0.0)  # places and paths keep a gentler ground
	# peaks: ridgelines that grow with the mountains (sharp crests, broad shoulders, valleys between)
	var crest := 0.5 + 0.5 * _ridges.get_noise_2d(x, z)
	big += (pow(crest, 1.7) - 0.3) * PEAKS * mount * inland * tame
	# gullies the rain has cut straight down the steeper slopes (the noise is stretched along the fall line)
	var fall := slope_xz.normalized()
	var along := x * fall.x + z * fall.y
	var across := -x * fall.y + z * fall.x
	big -= pow(1.0 - absf(_gullies.get_noise_2d(across, along * 0.22)), 3.0) * GULLIES * smoothstep(0.06, 0.35, steep) * inland * tame
	# spurs: a big face is ribbed with broad rock buttresses running down it, so it never reads as one smooth bank
	var rib := 1.0 - absf(_gullies.get_noise_2d(across * 0.25 + 600.0, along * 0.06))
	big += (rib * rib * (3.0 - 2.0 * rib) - 0.55) * SPURS * smoothstep(0.12, 0.45, steep) * mount * inland * tame  # rounded ribs, no sheer slots
	# the low ground: broad plains with hills standing out of them here and there
	big += pow(maxf(_roll.get_noise_2d(x, z), 0.0), 1.5) * ROLL * 2.2 * (1.0 - mount) * inland * tame
	# crags: steep faces are broken rock, not smooth banks
	if steep > 0.3:
		big += (0.5 + 0.5 * _ridges.get_noise_2d(x * 6.0 + 900.0, z * 6.0)) * 5.0 * smoothstep(0.3, 0.8, steep) * inland
	# rock ledges: steep high ground breaks into bands
	var ledgy := smoothstep(0.25, 0.6, steep) * mount * tame
	if ledgy > 0.0:
		var band := big / LEDGE
		var stepped := (floorf(band) + smoothstep(0.65, 1.0, band - floorf(band))) * LEDGE
		big = lerpf(big, stepped, ledgy * 0.35)
	var w := weights(x, z)
	var add := 0.0
	for i in regions.size():
		if w[i] < 0.002:
			continue
		var form: Dictionary = regions[i]["height"]
		var rough := float(form["rough"])
		var plain := float(form["amp"]) * _noise.get_noise_2d(x / rough, z / rough)
		if wild > 0.0:
			plain += wild * _landforms(form, x, z, big + plain)
		add += w[i] * plain
	var h := big + add * RELIEF * smoothstep(0.5, 6.0, big)
	h = maxf(h, minf(big, sea + 1.5)) if big > sea else h  # the relief never drowns land
	h += 0.5 * _detail.get_noise_2d(x, z)
	if country_shape.lake_at(x, z) >= 0:
		h = minf(h, country_shape.height(x, z))  # (polish1 F1b) a lake's bed stays under its water: the land's detail lifted it into islands
	var river: Vector3 = country_shape.river_near(x, z)
	var vale: float = river.y * 6.0 + 45.0  # a river runs in its own valley, wider where the river is
	if river.x < vale:
		var floor_h := river.z + 0.4 + river.x * 0.02
		h = lerpf(minf(h, floor_h + (h - floor_h) * 0.25), h, smoothstep(river.y * 2.0, vale, river.x))  # the valley floor
		var bank := maxf(h, river.z + 0.35)
		var bed := river.z - RIVER_DEPTH * (1.0 - pow(minf(river.x / maxf(river.y, 0.5), 1.0), 2.0)) - 0.1
		h = lerpf(bed, lerpf(bank, h, smoothstep(river.y * 1.6, river.y * 3.0 + 2.0, river.x)), smoothstep(river.y * 0.85, river.y * 1.3, river.x))
	var edge := maxf(absf(x), absf(z))
	return lerpf(h, minf(h, sea - 3.2), smoothstep(size * 0.5 - 60.0, size * 0.5 - 10.0, edge))


# The land with its places levelled (towns, farms and boss arenas sit on flat ground), before lakes are cut.
func _placed_height(x: float, z: float) -> float:
	var h := _raw_height(x, z, wildness(x, z))
	for i in _flat_at.size():
		var spot := _flat_at[i]
		var reach := _reach[i]
		var dx := x - spot.x
		var dz := z - spot.y
		if absf(dx) < reach and absf(dz) < reach:
			h = lerpf(_place_level[i], h, smoothstep(spot.z * 0.75, reach, sqrt(dx * dx + dz * dz)))
	if _graded:  # after the places: a road keeps its grade up to a place's level ground (rules 13; it was worked in before them)
		h = _on_road_bed(x, z, h)
	return h


# Whether a point lies on a place's level ground (where _placed_height is exactly the place's level).
func _in_flat(x: float, z: float) -> bool:
	for spot: Vector3 in _flat_at:
		if Vector2(x - spot.x, z - spot.y).length() <= spot.z * 0.75:
			return true
	return false


# (polish1 F3) GRADED ROADS of a country. A road no longer lies on whatever the land does under it: its bed is
# measured along the road, smoothed, and kept under GRADE_MOST steep by cutting through rises (never by filling,
# except up to a bridge). Where it crosses water up to BRIDGE_MOST wide the bed is a level BRIDGE deck from bank to
# bank (the land under it keeps its river; game/fantasy_places.gd stands the spans, `bridges`). Within GRADE_IN of
# the road's middle the ground is the bed, easing back into the land by GRADE_OUT.
# (rules 13) A place's level ground HOLDS the bed at the place's level, and like a bridge deck the road may be built
# up toward it: on a hillside a road now ramps up to a terrace instead of meeting its edge as a step.
func _grade_roads() -> void:
	for r in roads.size():
		var road: PackedVector2Array = roads[r]
		var rise := _road_most[r] * GRADE_STEP  # the most the bed climbs from one sample to the next
		var length := road[0].distance_to(road[1]) + road[1].distance_to(road[2])
		var count := maxi(ceili(length / GRADE_STEP) + 1, 2)
		var raw := PackedFloat32Array()
		var wet := PackedByteArray()
		var level := PackedFloat32Array()
		var held := PackedByteArray()  # 1 = the bed is fixed here (a place's level ground, a bridge deck)
		for i in count:
			var p := road_point(r, float(i) * GRADE_STEP)
			raw.append(_placed_height(p.x, p.y))
			held.append(1 if _in_flat(p.x, p.y) else 0)
			var water := water_at(p.x, p.y)
			wet.append(1 if water != "" else 0)
			var river: Vector3 = country_shape.river_near(p.x, p.y)
			level.append(river.z if water == "fresh" and river.x < river.y + 1.0 else (sea if water == "salt" else raw[i]))
		var bed := PackedFloat32Array()
		for i in count:  # the small ups and downs under the road are smoothed away (the mean of 28 m of it)
			var sum := 0.0
			var n := 0
			for k in range(maxi(i - 3, 0), mini(i + 4, count)):
				if wet[k] == 0:
					sum += raw[k]
					n += 1
			bed.append(raw[i] if held[i] == 1 else (sum / float(n) if n > 0 else raw[i]))
		var deck := PackedByteArray()
		deck.resize(count)
		var i0 := 0
		while i0 < count:  # every run of water becomes a bridge: one bank sample on each side, a level deck between
			if wet[i0] == 0:
				i0 += 1
				continue
			var i1 := i0
			while i1 + 1 < count and wet[i1 + 1] == 1:
				i1 += 1
			var a := maxi(i0 - 1, 0)
			var b := mini(i1 + 1, count - 1)
			if float(b - a) * GRADE_STEP <= BRIDGE_MOST and a > 0 and b < count - 1:
				var top := maxf(bed[a], bed[b])
				for k in range(a, b + 1):
					top = maxf(top, level[k] + BRIDGE_CLEAR)
				var spans: Array = []
				for k in range(a, b + 1):
					bed[k] = top
					deck[k] = 1
					held[k] = 1
					if k < b:
						var from := road_point(r, float(k) * GRADE_STEP)
						var to := road_point(r, float(k + 1) * GRADE_STEP)
						spans.append([(from.x + to.x) * 0.5, (from.y + to.y) * 0.5, atan2(-(to.x - from.x), -(to.y - from.y))])
				var mid := road_point(r, float(a + b) * 0.5 * GRADE_STEP)
				bridges.append({"id": "bridge:%d:%d" % [r, a], "x": mid.x, "z": mid.y, "y": top, "spans": spans, "half": float(b - a) * GRADE_STEP * 0.5, "road": r})
			i0 = i1 + 1
		var fill := PackedFloat32Array()  # banks rise to a bridge deck or a place's level ground: the only places a road is built up
		for i in count:
			fill.append(bed[i] if held[i] == 1 else -INF)
		for i in range(1, count):
			fill[i] = maxf(fill[i], fill[i - 1] - rise)
		for i in range(count - 2, -1, -1):
			fill[i] = maxf(fill[i], fill[i + 1] - rise)
		for i in count:
			bed[i] = maxf(bed[i], fill[i])
		for i in range(1, count):  # ... and everywhere else the road cuts through what is too steep to climb
			if held[i] == 0:
				bed[i] = minf(bed[i], bed[i - 1] + rise)
		for i in range(count - 2, -1, -1):
			if held[i] == 0:
				bed[i] = minf(bed[i], bed[i + 1] + rise)
		_grade.append(bed)
		_grade_bridge.append(deck)
	_graded = true


# The point `along` metres down a road (its bent line of three points).
func road_point(road_index: int, along: float) -> Vector2:
	var road: PackedVector2Array = roads[road_index]
	var first := road[0].distance_to(road[1])
	if along <= first:
		return road[0].lerp(road[1], along / maxf(first, 0.001))
	return road[1].lerp(road[2], minf((along - first) / maxf(road[1].distance_to(road[2]), 0.001), 1.0))


# The land's height `h` at a point, worked into the graded road beds near it (see _grade_roads).
func _on_road_bed(x: float, z: float, h: float) -> float:
	var near: PackedInt32Array = _seg_cells.get(Vector2i(floori(x / SEG_CELL), floori(z / SEG_CELL)), _no_segments)
	if near.is_empty():
		return h
	var here := Vector2(x, z)
	for s in near:
		var a := _seg_a[s]
		var b := _seg_b[s]
		var along := clampf((here - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		var d := here.distance_to(a + (b - a) * along)
		if d >= GRADE_OUT:
			continue
		var bed: PackedFloat32Array = _grade[_seg_road[s]]
		var deck: PackedByteArray = _grade_bridge[_seg_road[s]]
		var t := minf((_seg_from[s] + along * a.distance_to(b)) / GRADE_STEP, float(bed.size()) - 1.001)
		var i := int(t)
		var f := t - float(i)
		var open := 1.0 - lerpf(float(deck[i]), float(deck[i + 1]), f)  # under a bridge the land keeps its river
		h = lerpf(h, lerpf(bed[i], bed[i + 1], f), (1.0 - smoothstep(GRADE_IN, GRADE_OUT, d)) * open)
	return h


# (polish1 F3) The height to WALK at on a point: a bridge deck where one carries a road there, else the ground.
func walk_height(x: float, z: float) -> float:
	var h := height(x, z)
	for bridge: Dictionary in bridges:
		if absf(x - float(bridge["x"])) < float(bridge["half"]) + 3.0 and absf(z - float(bridge["z"])) < float(bridge["half"]) + 3.0:
			for span: Array in bridge["spans"]:
				if absf(x - float(span[0])) < 3.0 and absf(z - float(span[1])) < 3.0:
					return maxf(h, float(bridge["y"]))
	return h


# Ground height: the levelled land with ponds and lakes cut into it (a bowl below the water, a raised rim around it).
func height(x: float, z: float) -> float:
	var h := _placed_height(x, z)
	for i in _lake_at.size():
		var r := _lake_at[i].z
		var dx := x - _lake_at[i].x
		var dz := z - _lake_at[i].y
		if absf(dx) < r + 12.0 and absf(dz) < r + 12.0 and dx * dx + dz * dz < (r + 12.0) * (r + 12.0):
			var d := sqrt(dx * dx + dz * dz)
			var level := _lake_level[i]
			var bed := level - _lake_depth[i] * (1.0 - pow(minf(d / r, 1.0), 2.0)) - 0.15
			var shore := lerpf(maxf(h, level + 0.35), h, smoothstep(r + 4.0, r + 12.0, d))  # the bank never dips under the water
			h = lerpf(bed, shore, smoothstep(r - 1.5, r + 2.0, d))
	return h


# What water lies at a point: "" = dry land, "salt" = the sea, else a lake's kind ("fresh", "lava").
func water_at(x: float, z: float) -> String:
	if country_shape != null:
		var at: int = country_shape.lake_at(x, z)
		if at >= 0:
			return String(lakes[at].get("water", "fresh"))
		var river: Vector3 = country_shape.river_near(x, z)
		if river.x < river.y - 0.3:
			return "fresh"
		return "salt" if _placed_height(x, z) < sea - 0.3 else ""
	for lake: Dictionary in lakes:
		if Vector2(x - float(lake["x"]), z - float(lake["z"])).length() < float(lake["r"]) - 0.5:
			return String(lake["water"])
	return "salt" if _placed_height(x, z) < sea - 0.3 else ""


# The water within `reach` metres of a point, looking all around ("" = none): what an angler standing there can fish.
func water_near(x: float, z: float, reach: float) -> String:
	for k in 8:
		var a := float(k) * TAU / 8.0
		var found := water_at(x + cos(a) * reach, z + sin(a) * reach)
		if found != "":
			return found
	return ""


# How trodden the ground is at a point, 0..1: the middle of a place, or a path between places.
func trodden(x: float, z: float) -> float:
	var most := 0.0
	for i in _flat_at.size():
		var spot := _flat_at[i]
		var dx := x - spot.x
		var dz := z - spot.y
		if absf(dx) < spot.z and absf(dz) < spot.z and dx * dx + dz * dz < spot.z * spot.z:
			most = maxf(most, 1.0 - smoothstep(_trod_in[i], _trod_in[i] + 5.0, sqrt(dx * dx + dz * dz)))
	if most >= 1.0:
		return 1.0
	var here := Vector2(x, z)
	var near: PackedInt32Array = _seg_cells.get(Vector2i(floori(x / SEG_CELL), floori(z / SEG_CELL)), _no_segments)
	for s in near:
		var a := _seg_a[s]
		var b := _seg_b[s]
		var along := clampf((here - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		var d := here.distance_to(a + (b - a) * along)
		if d < ROAD_WIDTH + 2.4:
			most = maxf(most, 1.0 - smoothstep(ROAD_WIDTH, ROAD_WIDTH + 1.6, d + _detail.get_noise_2d(x * 2.0, z * 2.0) * 0.6))
	return most


# The place whose ground a point belongs to ({} when it is open country).
func place_at(x: float, z: float) -> Dictionary:
	for p: Dictionary in places:
		if Vector2(x - float(p["pos"][0]), z - float(p["pos"][1])).length() < float(p.get("flat", 0.0)):
			return p
	return {}


func normal(x: float, z: float) -> Vector3:
	var e := 1.5
	return Vector3(height(x - e, z) - height(x + e, z), 2.0 * e, height(x, z - e) - height(x, z + e)).normalized()


# Ground colour: the regions' colours mixed by weight, lighter on high ground, rock on steep ground, sand by the sea.
func color(x: float, z: float, h: float, slope: float) -> Color:
	var w := weights(x, z)
	var low := Color(0, 0, 0)
	var high := Color(0, 0, 0)
	var cliff := Color(0, 0, 0)
	for i in regions.size():
		if w[i] < 0.002:
			continue
		var g: Array = regions[i]["ground"]
		low += Color(g[0][0], g[0][1], g[0][2]) * w[i]
		high += Color(g[1][0], g[1][1], g[1][2]) * w[i]
		cliff += Color(g[2][0], g[2][1], g[2][2]) * w[i]
	var patch := 0.5 + 0.5 * _noise.get_noise_2d(x / 23.0, z / 23.0)
	var c := low.lerp(high, patch)
	if country_shape != null:
		c = _country_colour(c, low, cliff, x, z, h, slope)
	c = c.lerp(cliff, smoothstep(0.32, 0.62, slope))
	c = c.lerp(BEACH, 1.0 - smoothstep(sea + 0.4, sea + 2.2, h))
	var worn := trodden(x, z)
	if worn > 0.0:
		var here := place_at(x, z)
		c = c.lerp(PAVED if String(here.get("yard", "")) == "g_cobble" else DIRT, worn * 0.85)
	c.a = 1.0
	return c


# (polish1 F1a) A country's ground over its looks' own colours: big patches of lighter and darker land (meadow,
# heath, fields), greener valley floors along the rivers, bare stone below the snowline, snow above it.
func _country_colour(c: Color, low: Color, cliff: Color, x: float, z: float, h: float, slope: float) -> Color:
	var broad := _roll.get_noise_2d(x * 1.9 + 400.0, z * 1.9)
	c = c.lightened(broad * 0.12) if broad > 0.0 else c.darkened(-broad * 0.16)
	var river: Vector3 = country_shape.river_near(x, z)
	if river.x < river.y * 5.0 + 30.0:
		c = c.lerp(low.darkened(0.12).lerp(Color(0.32, 0.5, 0.22), 0.4), 0.45 * (1.0 - smoothstep(river.y * 1.5, river.y * 5.0 + 30.0, river.x)))
	var line := _snowline + 9.0 * _detail.get_noise_2d(x * 0.25, z * 0.25)
	c = c.lerp(cliff.lerp(Color(0.55, 0.53, 0.5), 0.4), 0.55 * smoothstep(line - 35.0, line - 5.0, h))  # bare stone toward the snow
	c = c.lerp(SNOW, snow_at(x, z, h) * (1.0 - smoothstep(0.5, 0.75, slope)))
	return c


# (polish1 F1a) How much snow lies at a point of a country (0 none .. 1): above its snowline, which wanders a little.
# The ground shader lays it on the level parts (ledges, tops), the steep faces stay rock. 0 in the old world.
func snow_at(x: float, z: float, h: float) -> float:
	if country_shape == null:
		return 0.0
	var line := _snowline + 9.0 * _detail.get_noise_2d(x * 0.25, z * 0.25)
	return smoothstep(line, line + 5.0, h)


# Fog, sky and light at a point: {"fog": Color, "density": float, "sky_top": Color, "sky_horizon": Color,
# "ambient": Color, "sun": Color}, mixed between regions.
func mood(x: float, z: float) -> Dictionary:
	var w := weights(x, z)
	var out := {"fog": Color(0, 0, 0), "density": 0.0, "sky_top": Color(0, 0, 0), "sky_horizon": Color(0, 0, 0), "ambient": Color(0, 0, 0), "sun": Color(0, 0, 0)}
	for i in regions.size():
		if w[i] < 0.002:
			continue
		var m: Dictionary = regions[i]["mood"]
		for key: String in ["fog", "sky_top", "sky_horizon", "ambient", "sun"]:
			var c: Array = m[key]
			out[key] = (out[key] as Color) + Color(c[0], c[1], c[2]) * w[i]
		out["density"] = float(out["density"]) + float(m["density"]) * w[i]
	for key: String in ["fog", "sky_top", "sky_horizon", "ambient", "sun"]:
		(out[key] as Color).a = 1.0
		out[key] = Color((out[key] as Color).r, (out[key] as Color).g, (out[key] as Color).b, 1.0)
	return out


# A repeatable number 0..1 for a grid cell and a salt: everything scattered over the land (trees, rocks, enemies'
# favourite spots) is placed with this, so every machine scatters alike.
static func hash01(cx: int, cz: int, salt: int) -> float:
	var n := (cx * 73856093) ^ (cz * 19349663) ^ (salt * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFFFF) / float(0xFFFFFF)
