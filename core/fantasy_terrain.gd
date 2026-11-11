# Purpose: pure shape of the fantasy world: for any point, which regions it belongs to (they blend into each other),
# the ground height, the ground colour, the mood (fog, sky, light) and the enemy level. Every machine computes the same
# land from the same data, so the host and the clients agree where the ground is. No nodes.
# Dependencies: none (uses the engine's FastNoiseLite). Data: data/fantasy/world.json.
extends RefCounted

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

const ROAD_WIDTH := 2.3  # half width of a path, metres
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
	_ready_places = true
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


func _raw_height(x: float, z: float) -> float:
	var w := weights(x, z)
	var h := 0.0
	for i in regions.size():
		if w[i] < 0.002:
			continue
		var shape: Dictionary = regions[i]["height"]
		var rough := float(shape["rough"])
		h += w[i] * (float(shape["base"]) + float(shape["amp"]) * _noise.get_noise_2d(x / rough, z / rough))
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
	var h := _raw_height(x, z)
	for i in places.size():
		var p: Dictionary = places[i]
		var flat := float(p.get("flat", 0.0))
		var d := Vector2(x - float(p["pos"][0]), z - float(p["pos"][1])).length()
		if flat > 0.0 and d < flat * 1.5:
			var level := _place_level[i] if _ready_places else maxf(_raw_height(float(p["pos"][0]), float(p["pos"][1])), sea + 1.2)
			h = lerpf(level, h, smoothstep(flat * 0.75, flat * 1.5, d))
	return h


# Ground height: the levelled land with ponds and lakes cut into it (a bowl below the water, a raised rim around it).
func height(x: float, z: float) -> float:
	var h := _placed_height(x, z)
	for lake: Dictionary in lakes:
		var r: float = lake["r"]
		var d := Vector2(x - float(lake["x"]), z - float(lake["z"])).length()
		if d < r + 12.0:
			var level: float = lake["level"]
			var bed := level - float(lake["depth"]) * (1.0 - pow(minf(d / r, 1.0), 2.0)) - 0.15
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
	for p: Dictionary in places:
		var flat := float(p.get("flat", 0.0))
		var d := Vector2(x - float(p["pos"][0]), z - float(p["pos"][1])).length()
		if d < flat:
			var inner := flat * (0.72 if String(p["kind"]).begins_with("town") or String(p["kind"]) == "arena" else 0.4)
			most = maxf(most, 1.0 - smoothstep(inner, inner + 5.0, d))
	if most >= 1.0:
		return 1.0
	var here := Vector2(x, z)
	for road: PackedVector2Array in roads:
		for i in road.size() - 1:
			var a := road[i]
			var b := road[i + 1]
			if absf(x - (a.x + b.x) * 0.5) > absf(a.x - b.x) * 0.5 + 6.0 or absf(z - (a.y + b.y) * 0.5) > absf(a.y - b.y) * 0.5 + 6.0:
				continue
			var along := clampf((here - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			var d := here.distance_to(a + (b - a) * along) + (_detail.get_noise_2d(x * 2.0, z * 2.0) * 0.6)
			most = maxf(most, 1.0 - smoothstep(ROAD_WIDTH, ROAD_WIDTH + 1.6, d))
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
