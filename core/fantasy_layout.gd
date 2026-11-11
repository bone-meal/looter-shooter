# Purpose: where everything stands in the fantasy world, worked out from data and repeatable numbers only (no
# rendering): the buildings and belongings of each place, the small sites scattered through the country, the trees, the
# things to gather and the fishing spots on real water. Every machine gets the same answer, so the game can draw it
# (game/fantasy_places.gd, game/fantasy_scatter.gd), build colliders from it, and creatures can walk around it
# (`walk`) without any physics.
# Dependencies: core/fantasy_terrain.gd, data/fantasy/layouts.json (the rules), data/fantasy/props.json (sizes),
# data/fantasy/skilling.json (gather nodes). All positions are the world's own map metres (x east, z south).
extends RefCounted

const FantasyTerrain = preload("res://core/fantasy_terrain.gd")

const TREE_SLOTS := 10
const NODE_SLOTS := 8
const GRID := 12.0  # metres: side of one square of the obstacle grid
const WADE := 0.5  # creatures do not go into water deeper than this

var terrain: FantasyTerrain
var rules: Dictionary
var props: Dictionary
var node_data: Dictionary
var interiors: RefCounted  # core/fantasy_interiors.gd, set by whoever builds the world (optional)

var _places := {}  # place id -> Array of items
var _sites := {}  # Vector2i cell -> site ({} = nothing there)
var _trees := {}  # chunk key -> Array of [model, x, z, grow, turn]
var _grid := {}  # Vector2i square -> Array of [x, z, half width, half depth, cos, sin]
var _chunk: float


func _init(land: FantasyTerrain, layout_rules: Dictionary, prop_sizes: Dictionary, gather_nodes: Dictionary) -> void:
	terrain = land
	rules = layout_rules
	props = prop_sizes
	node_data = gather_nodes
	_chunk = float(terrain.data["chunk"])


# --- places ---

# Everything standing in a place: [{"model", "x", "z", "turn", "solid", "station"}]. `keep` = spots to leave free
# (where people stand).
func place_items(place: Dictionary, keep: Array = []) -> Array:
	var id := String(place["id"])
	if not _places.has(id):
		var scheme := String(terrain.region_by_id(String(place["region"])).get("scheme", "amber"))
		var cx := float(place["pos"][0])
		var cz := float(place["pos"][1])
		_places[id] = _lay(rules["kinds"].get(String(place["kind"]), []), cx, cz, float(place["flat"]), scheme, int(cx), int(cz), keep, false)
		_remember(_places[id])
		if interiors != null:  # the furniture of the main story's walk-in houses stands in the open world
			for item: Dictionary in (_places[id] as Array).duplicate():
				(_places[id] as Array).append_array(interiors.call("furnish", item))
	return _places[id]


# --- sites: small spots between the places ---

func site_cell(x: float, z: float) -> Vector2i:
	var cell := float(rules["site_cell"])
	return Vector2i(floori(x / cell), floori(z / cell))


# The site of a grid cell: {"id", "x", "z", "kind", "items"} or {} when the cell is empty.
func site(cell: Vector2i) -> Dictionary:
	if _sites.has(cell):
		return _sites[cell]
	var found := {}
	var side := float(rules["site_cell"])
	if FantasyTerrain.hash01(cell.x, cell.y, 901) < float(rules["site_chance"]):
		var x := (float(cell.x) + 0.15 + 0.7 * FantasyTerrain.hash01(cell.x, cell.y, 902)) * side
		var z := (float(cell.y) + 0.15 + 0.7 * FantasyTerrain.hash01(cell.x, cell.y, 903)) * side
		if _open_country(x, z, 24.0):
			var region := terrain.region_at(x, z)
			var kind := _pick(rules["region_sites"].get(String(region["id"]), {}), FantasyTerrain.hash01(cell.x, cell.y, 904))
			if kind != "":
				found = {"id": "site:%d:%d" % [cell.x, cell.y], "x": x, "z": z, "kind": kind,
					"items": _lay(rules["sites"][kind], x, z, 16.0, String(region.get("scheme", "amber")), cell.x * 31 + 7, cell.y * 17 + 3, [], true)}
				_remember(found["items"])
	_sites[cell] = found
	return found


# Level, dry ground away from every place, lake and path.
func _open_country(x: float, z: float, room: float) -> bool:
	if terrain.height(x, z) < terrain.sea + 1.0 or terrain.normal(x, z).y < 0.965:
		return false
	for k in 4:
		var a := float(k) * TAU / 4.0
		if absf(terrain.height(x + cos(a) * room * 0.6, z + sin(a) * room * 0.6) - terrain.height(x, z)) > 1.6:
			return false
	for p: Dictionary in terrain.places:
		if Vector2(x - float(p["pos"][0]), z - float(p["pos"][1])).length() < float(p["flat"]) * 1.3 + room:
			return false
	for lake: Dictionary in terrain.lakes:
		if Vector2(x - float(lake["x"]), z - float(lake["z"])).length() < float(lake["r"]) + room:
			return false
	return terrain.trodden(x, z) < 0.05


func _pick(weights: Dictionary, roll: float) -> String:
	var total := 0.0
	for key: String in weights:
		total += float(weights[key])
	var left := roll * total
	for key: String in weights:
		left -= float(weights[key])
		if left <= 0.0:
			return key
	return ""


# --- the rule engine ---

func _size(model: String) -> Dictionary:
	return props.get(model, {"w": 1.0, "d": 1.0, "h": 1.0, "x": 0.0, "z": 0.0, "solid": false})


func _lay(list: Array, cx: float, cz: float, flat: float, scheme: String, seed_x: int, seed_z: int, keep: Array, slopes: bool) -> Array:
	var out: Array = []
	var taken: Array = []  # [x, z, radius] of what already stands
	for spot: Vector2 in keep:
		taken.append([spot.x, spot.y, 1.7])
	var salt := 0
	for rule: Dictionary in list:
		salt += 97
		if rule.has("wall"):
			_wall(out, taken, rule, cx, cz, flat)
		elif rule.has("model"):
			var at := Vector2(cx, cz)
			if rule.has("at_m"):
				at += Vector2(float(rule["at_m"][0]), float(rule["at_m"][1]))
			else:
				at += Vector2(float(rule["at"][0]), float(rule["at"][1])) * flat
			var turn := deg_to_rad(float(rule.get("turn", 0.0)))
			if String(rule.get("face", "")) == "in":
				turn = atan2(at.x - cx, at.y - cz)
			_put(out, taken, String(rule["model"]).replace("$", scheme), at.x, at.y, turn, String(rule.get("station", "")), true, slopes)
		else:
			var models: Array = rules["extras"].get(scheme, []) if rule.has("extras") else rule["models"]
			var count := int(rule.get("extras", rule.get("count", 0)))
			var metres := rule.has("ring_m")
			var ring: Variant = rule.get("ring_m", rule.get("ring", 0.5))
			var r0 := float(ring[0]) if ring is Array else float(ring)
			var r1 := float(ring[1]) if ring is Array else float(ring)
			if not metres:
				r0 *= flat
				r1 *= flat
			var even := bool(rule.get("even", false))
			if models.is_empty():
				continue
			for i in count:
				for attempt in 5:
					var h1 := FantasyTerrain.hash01(seed_x, seed_z, salt + i * 13 + attempt * 5)
					var h2 := FantasyTerrain.hash01(seed_x, seed_z, salt + i * 13 + attempt * 5 + 1)
					var h3 := FantasyTerrain.hash01(seed_x, seed_z, salt + i * 13 + attempt * 5 + 2)
					var a := (float(i) + (0.5 + (h1 - 0.5) * 0.3 if attempt == 0 else h1)) * TAU / float(count) if even else h1 * TAU
					var r := lerpf(r0, r1, sqrt(h2))
					var x := cx + cos(a) * r
					var z := cz + sin(a) * r
					var model := String(models[i % models.size()] if even else models[int(h3 * 997.0 + float(i)) % models.size()]).replace("$", scheme)
					var turn := h3 * TAU
					match String(rule.get("face", "any")):
						"in":
							turn = atan2(cos(a), sin(a))
						"out":
							turn = atan2(-cos(a), -sin(a))
					if _put(out, taken, model, x, z, turn, "", false, slopes):
						break
	return out


# Adds one thing if it fits (does not overlap what stands, not in water; on a slope only when `slopes` allows a
# little). `forced` things (named with "at") are always added.
func _put(out: Array, taken: Array, model: String, x: float, z: float, turn: float, station: String, forced: bool, slopes: bool) -> bool:
	var size := _size(model)
	var solid := bool(size["solid"])
	var radius := maxf(float(size["w"]), float(size["d"])) * 0.45
	if not forced:
		if terrain.water_at(x, z) != "":
			return false
		if slopes and radius > 1.5 and terrain.normal(x, z).y < 0.95:
			return false
		for other: Array in taken:
			var reach := float(other[2]) + radius + 0.35 if solid else float(other[2]) * 0.8
			if absf(x - float(other[0])) < reach and absf(z - float(other[1])) < reach and Vector2(x - float(other[0]), z - float(other[1])).length() < reach:
				return false
	if solid or radius > 1.2:
		taken.append([x, z, radius])
	out.append({"model": model, "x": x, "z": z, "turn": turn, "solid": solid, "station": station})
	return true


# A wall around a place, in stretches as long as the wall model, with gaps where the gates stand.
func _wall(out: Array, taken: Array, rule: Dictionary, cx: float, cz: float, flat: float) -> void:
	var model := String(rule["wall"])
	var radius := float(rule["ring"]) * flat
	var length := maxf(float(_size(model)["w"]), 1.0)
	var count := int(TAU * radius / length)
	var gates := int(rule.get("gates", 0))
	var gap := (float(_size(String(rule.get("gate", model)))["w"]) * 0.5 + length * 0.6) / radius
	for k in gates:
		var a := PI / 2.0 + float(k) * TAU / float(gates)  # the first gate faces south
		_put(out, taken, String(rule["gate"]), cx + cos(a) * radius, cz + sin(a) * radius, atan2(-cos(a), -sin(a)), "", true, false)
	for i in count:
		var a := float(i) * TAU / float(count)
		var open := false
		for k in gates:
			if absf(angle_difference(a, PI / 2.0 + float(k) * TAU / float(gates))) < gap:
				open = true
		if not open:
			var x := cx + cos(a) * radius
			var z := cz + sin(a) * radius
			if terrain.water_at(x, z) == "":
				out.append({"model": model, "x": x, "z": z, "turn": -a - PI / 2.0, "solid": true, "station": ""})


# --- trees, things to gather, fishing spots (per piece of land) ---

func _free_ground(x: float, z: float) -> bool:
	if terrain.height(x, z) < terrain.sea + 0.6 or terrain.normal(x, z).y < 0.8 or terrain.water_at(x, z) != "":
		return false
	if terrain.trodden(x, z) > 0.2:
		return false
	for p: Dictionary in terrain.places:
		if Vector2(x - float(p["pos"][0]), z - float(p["pos"][1])).length() < float(p.get("flat", 0.0)) * 1.15:
			return false
	var here := site(site_cell(x, z))
	return here.is_empty() or Vector2(x - float(here["x"]), z - float(here["z"])).length() > 22.0


# The trees of one piece of land: [model, x, z, grow, turn].
func trees(key: Vector2i) -> Array:
	if _trees.has(key):
		return _trees[key]
	var out: Array = []
	for slot in TREE_SLOTS:
		var x := (float(key.x) + FantasyTerrain.hash01(key.x, key.y, slot * 3 + 1)) * _chunk
		var z := (float(key.y) + FantasyTerrain.hash01(key.x, key.y, slot * 3 + 2)) * _chunk
		var kinds: Dictionary = terrain.region_at(x, z)["trees"]
		var total := 0.0
		for id: String in kinds:
			total += float(kinds[id])
		var pick := FantasyTerrain.hash01(key.x, key.y, slot * 3 + 3) * float(TREE_SLOTS)
		if pick >= total or not _free_ground(x, z):
			continue
		for id: String in kinds:
			pick -= float(kinds[id])
			if pick <= 0.0:
				out.append([id, x, z, 0.8 + 0.5 * FantasyTerrain.hash01(key.x, key.y, slot * 3 + 40), FantasyTerrain.hash01(key.x, key.y, slot + 70) * TAU])
				break
	_trees[key] = out
	return out


# The things to gather on one piece of land: [slot, node id, x, y, z, turn]. Fishing spots sit ON the water of a lake,
# a pond or the sea, a rod's cast from the bank, and give that region's fresh or salt water fish.
func nodes(key: Vector2i) -> Array:
	var out: Array = []
	for slot in NODE_SLOTS:
		var x := (float(key.x) + FantasyTerrain.hash01(key.x, key.y, slot * 3 + 101)) * _chunk
		var z := (float(key.y) + FantasyTerrain.hash01(key.x, key.y, slot * 3 + 102)) * _chunk
		var kinds: Dictionary = terrain.region_at(x, z)["nodes"]
		var total := 0.0
		for id: String in kinds:
			total += float(kinds[id])
		var pick := FantasyTerrain.hash01(key.x, key.y, slot * 3 + 103) * maxf(float(NODE_SLOTS), total)
		if pick >= total or not _free_ground(x, z):
			continue
		for id: String in kinds:
			pick -= float(kinds[id])
			if pick <= 0.0:
				out.append([slot, id, x, terrain.height(x, z), z, FantasyTerrain.hash01(key.x, key.y, slot + 170) * TAU])
				break
	var slot := NODE_SLOTS
	for lake: Dictionary in terrain.lakes:  # spots around each lake, three metres in from the bank
		var spots := maxi(int(float(lake["r"]) / 5.0), 3)
		for k in spots:
			var a := float(k) * TAU / float(spots) + 0.4
			var x := float(lake["x"]) + cos(a) * (float(lake["r"]) - 3.0)
			var z := float(lake["z"]) + sin(a) * (float(lake["r"]) - 3.0)
			if floori(x / _chunk) == key.x and floori(z / _chunk) == key.y:
				var id := String(terrain.region_at(x, z)["fish"]["fresh"])
				out.append([slot, id, x, float(lake["level"]) + 0.02, z, 0.0])
				slot += 1
	for k in 3:  # and along the sea shore: where the water starts
		var x := (float(key.x) + FantasyTerrain.hash01(key.x, key.y, 300 + k)) * _chunk
		var z := (float(key.y) + FantasyTerrain.hash01(key.x, key.y, 310 + k)) * _chunk
		var h := terrain.height(x, z)
		if h < terrain.sea - 0.25 and h > terrain.sea - 1.6 and terrain.water_near(x, z, 6.0) != "" and _shore_near(x, z):
			out.append([slot, String(terrain.region_at(x, z)["fish"]["salt"]), x, terrain.sea + 0.02, z, 0.0])
			slot += 1
	return out


func _shore_near(x: float, z: float) -> bool:
	for k in 8:
		var a := float(k) * TAU / 8.0
		if terrain.height(x + cos(a) * 4.5, z + sin(a) * 4.5) > terrain.sea + 0.1:
			return true
	return false


# --- walking around things ---

func _remember(items: Array) -> void:
	for item: Dictionary in items:
		if not bool(item["solid"]):
			continue
		var size := _size(String(item["model"]))
		var turn := float(item["turn"])
		var ox := float(size["x"]) * cos(turn) + float(size["z"]) * sin(turn)
		var oz := -float(size["x"]) * sin(turn) + float(size["z"]) * cos(turn)
		var entry := [float(item["x"]) + ox, float(item["z"]) + oz, float(size["w"]) * 0.5, float(size["d"]) * 0.5, cos(turn), sin(turn)]
		var reach := maxf(entry[2], entry[3]) + 1.0
		for gz in range(floori((entry[1] - reach) / GRID), floori((entry[1] + reach) / GRID) + 1):
			for gx in range(floori((entry[0] - reach) / GRID), floori((entry[0] + reach) / GRID) + 1):
				var square := Vector2i(gx, gz)
				if not _grid.has(square):
					_grid[square] = []
				(_grid[square] as Array).append(entry)


# Makes sure the places and sites around a point are laid out (call for wherever creatures are about to walk).
func prepare(x: float, z: float, reach: float = 160.0) -> void:
	for p: Dictionary in terrain.places:
		if Vector2(x - float(p["pos"][0]), z - float(p["pos"][1])).length() < float(p["flat"]) * 1.3 + reach:
			place_items(p)
	var cell := site_cell(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			site(cell + Vector2i(dx, dz))


# A point pushed out of whatever solid thing it is inside (`pad` = the walker's own radius).
func push_out(x: float, z: float, pad: float) -> Vector2:
	var at := Vector2(x, z)
	var square := Vector2i(floori(x / GRID), floori(z / GRID))
	if _grid.has(square):
		for entry: Array in _grid[square]:
			var rel := at - Vector2(entry[0], entry[1])
			var local := Vector2(rel.x * float(entry[4]) - rel.y * float(entry[5]), rel.x * float(entry[5]) + rel.y * float(entry[4]))  # into the thing's own axes
			var hw := float(entry[2]) + pad
			var hd := float(entry[3]) + pad
			if absf(local.x) < hw and absf(local.y) < hd:
				if hw - absf(local.x) < hd - absf(local.y):
					local.x = hw * signf(local.x if local.x != 0.0 else 1.0)
				else:
					local.y = hd * signf(local.y if local.y != 0.0 else 1.0)
				rel = Vector2(local.x * float(entry[4]) + local.y * float(entry[5]), -local.x * float(entry[5]) + local.y * float(entry[4]))
				at = Vector2(entry[0], entry[1]) + rel
	for tree: Array in trees(Vector2i(floori(at.x / _chunk), floori(at.y / _chunk))):
		var away := at - Vector2(tree[1], tree[2])
		var reach := 0.35 * float(tree[3]) + pad
		if away.length() < reach:
			at = Vector2(tree[1], tree[2]) + (away.normalized() if away.length() > 0.01 else Vector2.RIGHT) * reach
	return at


func blocked(x: float, z: float, pad: float) -> bool:
	return push_out(x, z, pad).distance_to(Vector2(x, z)) > 0.01 or terrain.water_at(x, z) != ""


# One step of a creature that walks on the land: from (x, z) by (step_x, step_z). It slides along walls and trees and
# stops at deep water (unless it `swims`). Returns the new x, z.
func walk(x: float, z: float, step_x: float, step_z: float, pad: float, swims: bool) -> Vector2:
	var to := push_out(x + step_x, z + step_z, pad)
	if not swims and _deep(to.x, to.y):
		to = push_out(x + step_x, z, pad)  # try along one side, then the other, else stay
		if _deep(to.x, to.y):
			to = push_out(x, z + step_z, pad)
			if _deep(to.x, to.y):
				return Vector2(x, z)
	return to


func _deep(x: float, z: float) -> bool:
	if terrain.height(x, z) < terrain.sea - WADE:
		return true
	for lake: Dictionary in terrain.lakes:
		if Vector2(x - float(lake["x"]), z - float(lake["z"])).length() < float(lake["r"]) - 1.5:
			return true
	return false
