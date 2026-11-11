# Purpose: pure shape of the fantasy world: for any point, which regions it belongs to (they blend into each other),
# the ground height, the ground colour, the mood (fog, sky, light) and the enemy level. Every machine computes the same
# land from the same data, so the host and the clients agree where the ground is. No nodes.
# Dependencies: none (uses the engine's FastNoiseLite). Data: data/fantasy/world.json.
extends RefCounted

const RULES_VERSION := 2  # raise when these rules change the shape or colour of the land: saved charts are then painted afresh
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
var _place_level := PackedFloat32Array()  # ground level of each place (same order as `places`)
var _ready_places := false
var _calm_at := PackedVector3Array()  # places and lakes: (x, z, radius inside which the land is calm)
var _calm_out := PackedFloat32Array()  # ... and the radius from which it is fully wild again
var _flat_at := PackedVector3Array()  # every place, same order as `places`: (x, z, flat radius)
var _trod_in := PackedFloat32Array()  # every place: the radius of its fully trodden middle
var _lake_at := PackedVector3Array()  # every lake, same order as `lakes`: (x, z, radius)
var _lake_level := PackedFloat32Array()
var _lake_depth := PackedFloat32Array()
var _seg_a := PackedVector2Array()  # every stretch of path: its two ends ...
var _seg_b := PackedVector2Array()
var _seg_cells := {}  # ... and which stretches pass near each SEG_CELL square: Vector2i -> PackedInt32Array
var _no_segments := PackedInt32Array()
var _cones: Array = []  # volcano cones: {"x", "z", "crater", "rim", "radius", "height", "open" (bearing of the way in)}

const ROAD_WIDTH := 2.3  # half width of a path, metres
const SEG_CELL := 80.0  # paths are looked up through a grid of squares this wide
const CALM_NEAR := 7.0  # this close to a path the land has none of its wild landforms ...
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
	var last: Dictionary = regions[regions.size() - 1]
	_ring_center = Vector2(float(last["center"][0]), float(last["center"][1]))
	_ring_radius = float(last["radius"]) + 30.0
	for p: Dictionary in places:
		_place_level.append(maxf(_raw_height(float(p["pos"][0]), float(p["pos"][1])), sea + 1.2))
		var flat := float(p.get("flat", 0.0))
		_flat_at.append(Vector3(float(p["pos"][0]), float(p["pos"][1]), flat))
		_trod_in.append(flat * (0.72 if String(p["kind"]).begins_with("town") or String(p["kind"]) == "arena" else 0.4))
		if flat > 0.0:
			_calm_at.append(Vector3(float(p["pos"][0]), float(p["pos"][1]), float(p["flat"]) * 1.1))
			_calm_out.append(float(p["flat"]) * 3.0)
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
		roads.append(PackedVector2Array([from, (from + to) * 0.5 + bend, to]))
	for lake: Dictionary in lakes:
		_lake_at.append(Vector3(float(lake["x"]), float(lake["z"]), float(lake["r"])))
		_lake_level.append(float(lake["level"]))
		_lake_depth.append(float(lake["depth"]))
	for road: PackedVector2Array in roads:
		for i in road.size() - 1:
			var index := _seg_a.size()
			_seg_a.append(road[i])
			_seg_b.append(road[i + 1])
			var reach := CALM_FAR + 6.0
			for cz in range(floori((minf(road[i].y, road[i + 1].y) - reach) / SEG_CELL), floori((maxf(road[i].y, road[i + 1].y) + reach) / SEG_CELL) + 1):
				for cx in range(floori((minf(road[i].x, road[i + 1].x) - reach) / SEG_CELL), floori((maxf(road[i].x, road[i + 1].x) + reach) / SEG_CELL) + 1):
					var cell := Vector2i(cx, cz)
					var list: PackedInt32Array = _seg_cells.get(cell, PackedInt32Array())
					list.append(index)
					_seg_cells[cell] = list


# One weight per region (same order as `regions`), adding up to 1: high for the region the point is in, shared
# smoothly near a border.
func weights(x: float, z: float) -> PackedFloat32Array:
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


# The land with its places levelled (towns, farms and boss arenas sit on flat ground), before lakes are cut.
func _placed_height(x: float, z: float) -> float:
	var h := _raw_height(x, z, wildness(x, z))
	for i in _flat_at.size():
		var spot := _flat_at[i]
		var reach := spot.z * 1.5
		var dx := x - spot.x
		var dz := z - spot.y
		if absf(dx) < reach and absf(dz) < reach:
			h = lerpf(_place_level[i], h, smoothstep(spot.z * 0.75, reach, sqrt(dx * dx + dz * dz)))
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
	c = c.lerp(cliff, smoothstep(0.32, 0.62, slope))
	c = c.lerp(BEACH, 1.0 - smoothstep(sea + 0.4, sea + 2.2, h))
	var worn := trodden(x, z)
	if worn > 0.0:
		var here := place_at(x, z)
		c = c.lerp(PAVED if String(here.get("yard", "")) == "g_cobble" else DIRT, worn * 0.85)
	c.a = 1.0
	return c


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
