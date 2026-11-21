# Purpose: the islands' land as pure rules: where the islands and the ways between them are, how high the ground is,
# which island a spot belongs to, where something that fell in the water washes up, where an enemy may come out of
# the sea, and which debris is cleared. (polish1 D4a) The lie of the land: hills raise the ground (smooth, walkable);
# ridges, ruins and boulders are solid things standing on it (`blocks`, built by game/island_terrain.gd).
# No nodes, no rendering.
# Dependencies: none. Data: data/archipelago.json, passed to the constructor. Positions are metres (x, z) from the
# middle of the spawn island (island 0); heights are relative to the islands' flat ground (0).
extends RefCounted

const FLAT_BEFORE_SHORE := 2.0  # the flat part of an island ends this far before the waterline
const TRIES := 12

var cfg: Dictionary
var sea_level: float
var islands: Array = []  # {"id", "name", "at": Vector2, "radius", "flat", "grass", "palms", "scatter", "hills": [[at, radius, height]]}
var blocks: Array = []  # every ridge / ruin / boulder / giant tree in world-plan metres: {"kind", "island", "a": Vector2, "b": Vector2, "half_width", "height"} (+ trees: "core", "girth")
var wall_buys: Array = []  # {"gun", "price": int, "island": int, "at": Vector2, "yaw": the way its board faces (toward its island's middle)} (+ "y" for the treetop / offshore ones, added by the session)
var shelters: Array = []  # {"island": int, "at": Vector2, "yaw": the way its door faces (toward its island's middle)}
# (polish1 D4b hold-out huts) what stands inside each hut: its wall buy joins `wall_buys` (on the back wall, facing in),
# its perk machine and its ammo crate are here: perk id -> {"at", "yaw"}; [{"at", "yaw", "price"}]
var hut_perks := {}
var ammo_crates: Array = []
const HUT_WALL_BUY := Vector2(0.0, -4.15)  # in the hut's frame (door at +z), matches core/shelter_rules.gd HALF
const HUT_PERK := Vector2(4.4, -3.0)
const HUT_AMMO := Vector2(-4.6, 2.6)
var keep_clear: Array[Vector2] = []  # more spots where things will stand (the session adds them before the islands are built): no tree or rock there
var bridges: Array = []  # {"from": int, "to": int, "price": int, "kind", "a": Vector2, "b": Vector2 (shore to shore), "mid": Vector2, "open": bool}

var _drop: float
var _middle := Vector2.ZERO
var _reach := 0.0


func _init(config: Dictionary) -> void:
	cfg = config
	sea_level = float(config["sea_level"])
	_drop = float(config["beach_drop"])
	for entry: Dictionary in config["islands"]:
		var radius := float(entry["radius"])
		var mid := Vector2(float(entry["at"][0]), float(entry["at"][1]))
		var hills: Array = []
		for f: Dictionary in entry.get("features", []):
			var kind := String(f["kind"])
			if kind == "hill":
				hills.append([mid + Vector2(float(f["at"][0]), float(f["at"][1])), float(f["radius"]), float(f["height"])])
			elif kind == "tree":  # (polish1 D4b) a giant tree: `half_width` = how far its roots reach, `core` = its flared foot
				var tc := mid + Vector2(float(f["at"][0]), float(f["at"][1]))
				var girth := float(f["girth"])
				blocks.append({"kind": kind, "island": islands.size(), "a": tc, "b": tc, "half_width": girth * 1.55 + 4.6, "core": girth * 1.55, "girth": girth, "height": float(f["height"])})
			elif kind == "boulder":
				var c := mid + Vector2(float(f["at"][0]), float(f["at"][1]))
				blocks.append({"kind": kind, "island": islands.size(), "a": c, "b": c, "half_width": float(f["size"]), "height": float(f["size"]) * 1.4})
			else:  # ridge / ruin
				blocks.append({"kind": kind, "island": islands.size(), "a": mid + Vector2(float(f["from"][0]), float(f["from"][1])), "b": mid + Vector2(float(f["to"][0]), float(f["to"][1])),
					"half_width": 1.6 if kind == "ridge" else 0.35, "height": float(f["height"])})
		islands.append({"id": String(entry["id"]), "name": String(entry["name"]), "at": mid,
			"radius": radius, "flat": radius - FLAT_BEFORE_SHORE, "grass": float(entry["grass"]), "palms": int(entry["palms"]), "scatter": float(entry.get("scatter", 1.0)), "hills": hills})
	for entry: Dictionary in config["bridges"]:
		var from := index_of(String(entry["from"]))
		var to := index_of(String(entry["to"]))
		var here: Vector2 = islands[from]["at"]
		var there: Vector2 = islands[to]["at"]
		var along := (there - here).normalized()
		var a := here + along * (float(islands[from]["radius"]) - 1.0)
		var b := there - along * (float(islands[to]["radius"]) - 1.0)
		bridges.append({"from": from, "to": to, "price": int(entry["price"]), "kind": String(entry["kind"]), "a": a, "b": b, "mid": (a + b) * 0.5, "open": false})
	for entry: Dictionary in config.get("wall_buys", []):
		var isle := index_of(String(entry["island"]))
		var off := Vector2(float(entry["at"][0]), float(entry["at"][1]))
		wall_buys.append({"gun": String(entry["gun"]), "price": int(entry["price"]), "island": isle, "at": (islands[isle]["at"] as Vector2) + off, "yaw": atan2(-off.x, -off.y)})
	for entry: Dictionary in config.get("shelters", []):
		var isle := index_of(String(entry["island"]))
		var off := Vector2(float(entry["at"][0]), float(entry["at"][1]))
		var hut_at := (islands[isle]["at"] as Vector2) + off
		var hy := atan2(-off.x, -off.y)
		shelters.append({"island": isle, "at": hut_at, "yaw": hy})
		if entry.has("wall_buy"):
			var wb: Dictionary = entry["wall_buy"]
			wall_buys.append({"gun": String(wb["gun"]), "price": int(wb["price"]), "island": isle, "at": hut_at + _hut_turn(HUT_WALL_BUY, hy), "yaw": hy})
		if entry.has("perk"):
			var f := _hut_turn(Vector2(-1.0, 0.0), hy)
			hut_perks[String(entry["perk"])] = {"at": hut_at + _hut_turn(HUT_PERK, hy), "yaw": atan2(f.x, f.y)}
		if entry.has("ammo"):
			var f2 := _hut_turn(Vector2(1.0, 0.0), hy)
			ammo_crates.append({"at": hut_at + _hut_turn(HUT_AMMO, hy), "yaw": atan2(f2.x, f2.y), "price": int(entry["ammo"])})
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for isle: Dictionary in islands:
		var at: Vector2 = isle["at"]
		var r := float(isle["radius"])
		low = Vector2(minf(low.x, at.x - r), minf(low.y, at.y - r))
		high = Vector2(maxf(high.x, at.x + r), maxf(high.y, at.y + r))
	_middle = (low + high) * 0.5
	_reach = (high - low).length() * 0.5 + float(config["sea_bed"]) + 12.0


# A hut-frame offset turned the hut's way (the same turn as core/shelter_rules.gd).
static func _hut_turn(local: Vector2, yaw: float) -> Vector2:
	return Vector2(local.x * cos(yaw) + local.y * sin(yaw), -local.x * sin(yaw) + local.y * cos(yaw))


func index_of(id: String) -> int:
	for i in islands.size():
		if String(islands[i]["id"]) == id:
			return i
	return -1


# A spot given as [x, z] from the middle of the island with this id.
func on_island(island_id: String, at: Array) -> Vector2:
	return (islands[index_of(island_id)]["at"] as Vector2) + Vector2(float(at[0]), float(at[1]))


# The middle of everything and how far from it still counts as being at the islands.
func middle() -> Vector2:
	return _middle


func reach() -> float:
	return _reach


func within(x: float, z: float) -> bool:
	return Vector2(x, z).distance_to(_middle) < _reach


# Ground height: every island is flat (0) to 2 m before its waterline and slopes into the sea from there, with its
# hills on top; between islands the higher sea bed counts. Bridges are not ground (see deck_at).
func height_at(x: float, z: float) -> float:
	var best := -INF
	for i in islands.size():
		best = maxf(best, island_height(i, x, z))
	return best


# One island's own ground (what its ground mesh is built from).
func island_height(island: int, x: float, z: float) -> float:
	var isle: Dictionary = islands[island]
	var beyond := maxf(Vector2(x, z).distance_to(isle["at"]) - float(isle["flat"]), 0.0)
	var dunes := sin(x * 1.3 + z * 0.7) * sin(z * 1.1 - x * 0.4) * 0.05
	var h := -_drop * pow(beyond, 1.5) + dunes * clampf(beyond / 1.5, 0.0, 1.0)
	for hill: Array in isle["hills"]:
		var d := Vector2(x, z).distance_to(hill[0]) / float(hill[1])
		if d < 1.0:
			var c := cos(d * PI) * 0.5 + 0.5  # a smooth dome: flat on top, easing out to nothing at its edge
			h += float(hill[2]) * c
	return h


# True when (x, z) is within `margin` metres of a ridge, ruin or boulder (or on a hill when hills count).
func blocked(x: float, z: float, margin: float, hills_count := false) -> bool:
	var p := Vector2(x, z)
	for b: Dictionary in blocks:
		var a: Vector2 = b["a"]
		var ab: Vector2 = (b["b"] as Vector2) - a
		var t := 0.0 if ab.length_squared() < 1e-6 else clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		if p.distance_to(a + ab * t) < float(b["half_width"]) + margin:
			return true
	if hills_count:
		for isle: Dictionary in islands:
			for hill: Array in isle["hills"]:
				if p.distance_to(hill[0]) < float(hill[1]) + margin:
					return true
	return false


# The island a spot belongs to: the one whose shore is nearest (a spot on an island = that island).
func island_near(x: float, z: float) -> int:
	var best := 0
	var best_d := INF
	for i in islands.size():
		var d := Vector2(x, z).distance_to(islands[i]["at"]) - float(islands[i]["radius"])
		if d < best_d:
			best_d = d
			best = i
	return best


# True on dry sand or grass (not in the water, not on a bridge).
func on_land(x: float, z: float) -> bool:
	return height_at(x, z) >= sea_level


# Where something lying at (x, z) ends up: where it is when that is dry land, else on the sand of `island` (-1 = the
# nearest), 1.5 m in from the waterline. Returns the spot with its ground height in y.
func wash_up(x: float, z: float, island: int = -1) -> Vector3:
	if island < 0 and on_land(x, z):
		return Vector3(x, height_at(x, z), z)
	var isle: Dictionary = islands[island if island >= 0 else island_near(x, z)]
	var at: Vector2 = isle["at"]
	var out := Vector2(x, z) - at
	var limit := float(isle["radius"]) - 1.5
	if out.length() > limit:
		out = out.normalized() * limit if out.length() > 0.001 else Vector2(limit, 0.0)
	var spot := at + out
	return Vector3(spot.x, height_at(spot.x, spot.y), spot.y)


# How far to either side of a prey's bearing (radians, seen from the island's middle) an enemy may come up on this
# island: data spawn_arc metres of shore, the whole way round on a small island.
func arc_of(island: int) -> float:
	return minf(float(cfg["spawn_arc"]) / float(islands[island]["radius"]), PI)


# True when two spots belong to different islands and lie more than far_respawn apart (an enemy left behind).
func left_behind(x: float, z: float, prey_x: float, prey_z: float) -> bool:
	return island_near(x, z) != island_near(prey_x, prey_z) and Vector2(x, z).distance_to(Vector2(prey_x, prey_z)) > float(cfg["far_respawn"])


# A spot in the sea round `island` where an enemy can come up: spawn_ring metres beyond the shore, under water, not
# beside a bridge and not on another island's beach. `bearing` (radians) = roughly from where (NAN = anywhere),
# within `spread` of it. Vector3(INF, 0, 0) when no such spot was found.
func sea_spot(island: int, rng: RandomNumberGenerator, bearing: float = NAN, spread: float = 0.6) -> Vector3:
	var isle: Dictionary = islands[island]
	var at: Vector2 = isle["at"]
	var ring: Array = cfg["spawn_ring"]
	for attempt in TRIES:
		var angle := rng.randf() * TAU if (is_nan(bearing) or attempt >= TRIES >> 1) else bearing + rng.randf_range(-spread, spread)
		var spot := at + Vector2(cos(angle), sin(angle)) * (float(isle["radius"]) + rng.randf_range(float(ring[0]), float(ring[1])))
		if island_near(spot.x, spot.y) != island or height_at(spot.x, spot.y) > sea_level - 0.6 or _bridge_within(spot, 4.0) >= 0:
			continue
		return Vector3(spot.x, height_at(spot.x, spot.y), spot.y)
	return Vector3(INF, 0.0, 0.0)


# What a refill of a wall gun's ammo pool costs.
func ammo_price(wall_buy: int) -> int:
	return roundi(float(wall_buys[wall_buy]["price"]) * float(cfg["ammo_share"]))


# The wall buy within `metres` of a spot, -1 = none.
func wall_buy_near(x: float, z: float, metres: float, y := 0.0) -> int:
	for i in wall_buys.size():
		if Vector2(x, z).distance_to(wall_buys[i]["at"]) <= metres and absf(y - float(wall_buys[i].get("y", 0.0))) < 1.6:  # (polish1 D4c: some stand up high)
			return i
	return -1


# --- the ways between the islands and their debris ---

func deck_width() -> float:
	return float(cfg["bridge_width"])


# Height of a bridge's walking surface above the islands' ground.
func deck_height(_bridge: int) -> float:
	return 0.35  # planks and sandbars alike (polish1 item 35: the sea's waves rolled over a sandbar at 0.2)


# The bridge whose deck (x, z) is on, -1 = none.
func deck_at(x: float, z: float) -> int:
	return _bridge_within(Vector2(x, z), deck_width() * 0.5)


func _bridge_within(spot: Vector2, margin: float) -> int:
	for i in bridges.size():
		var a: Vector2 = bridges[i]["a"]
		var b: Vector2 = bridges[i]["b"]
		var t := clampf((spot - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		if spot.distance_to(a + (b - a) * t) <= margin:
			return i
	return -1


func is_open(bridge: int) -> bool:
	return bool(bridges[bridge]["open"])


func price(bridge: int) -> int:
	return int(bridges[bridge]["price"])


# The debris is cleared; false when it already was (or there is no such bridge).
func open(bridge: int) -> bool:
	if bridge < 0 or bridge >= bridges.size() or is_open(bridge):
		return false
	bridges[bridge]["open"] = true
	return true


func close_all() -> void:
	for entry: Dictionary in bridges:
		entry["open"] = false


func open_list() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in bridges.size():
		if is_open(i):
			out.append(i)
	return out


# The closed debris within `debris_reach` metres of a spot, -1 = none.
func debris_near(x: float, z: float) -> int:
	for i in bridges.size():
		if not is_open(i) and Vector2(x, z).distance_to(bridges[i]["mid"]) <= float(cfg["debris_reach"]):
			return i
	return -1


# The name of the island a closed debris leads to, seen from a spot on one side of it.
func far_side(bridge: int, x: float, z: float) -> String:
	var entry: Dictionary = bridges[bridge]
	var from_a := Vector2(x, z).distance_to(entry["a"]) < Vector2(x, z).distance_to(entry["b"])
	return String(islands[int(entry["to"]) if from_a else int(entry["from"])]["name"])


# Which islands can be walked to from the spawn island over cleared bridges.
func reachable() -> Array[bool]:
	var seen: Array[bool] = []
	seen.resize(islands.size())
	seen.fill(false)
	seen[0] = true
	var changed := true
	while changed:
		changed = false
		for entry: Dictionary in bridges:
			if bool(entry["open"]) and seen[int(entry["from"])] != seen[int(entry["to"])]:
				seen[int(entry["from"])] = true
				seen[int(entry["to"])] = true
				changed = true
	return seen


# A thing of data "spots": its place (x, z) and the way it faces (radians about y; 0 = toward +z).
func place_of(id: String) -> Dictionary:
	var entry: Dictionary = cfg["spots"][id]
	var isle: Dictionary = islands[index_of(String(entry["island"]))]
	var at: Vector2 = isle["at"]
	if entry.has("at"):
		return {"at": at + Vector2(float(entry["at"][0]), float(entry["at"][1])), "yaw": float(entry.get("yaw", 0.0))}
	var toward: Vector2 = ((islands[index_of(String(entry["toward"]))]["at"] as Vector2) - at).normalized()  # stands `from_shore` metres inland of where the way from that island lands, facing it
	return {"at": at + toward * (float(isle["radius"]) - float(entry["from_shore"])), "yaw": atan2(toward.x, toward.y)}
