# Purpose: (polish1 D4c) the treetop village's plain rules (data/treetops.json): the decks (rings round a giant tree's
# trunk at three heights, platforms on stilts) and the WAYS between them (ladders, lifts, rope bridges) bought like
# doors in any order. Works out where every deck and every way's ends are (world-plan metres, the islands' frame:
# x / z from game/island.gd CENTER, y up), which way end a spot is at, which ways are open, the ladders' climb boxes.
# Pure: no nodes, no drawing.
# Dependencies: core/tree_shape.gd; an Archipelago (core/archipelago.gd) for islands, trees and ground heights.
extends RefCounted

const TreeShape = preload("res://core/tree_shape.gd")

const RAIL_GAP := 1.0  # half the opening in a deck's railing where a way meets it
const LADDER_OUT := 0.35  # a ladder hangs this far outside the deck's edge
const STAND := 0.9  # where a player stands to use a way end: this far from it

var cfg: Dictionary
var decks: Array = []  # {"id", "island": int, "kind": "ring" | "stilts", "layer": 1-3, "y": deck top, "at": Vector2 (ring: the trunk's middle at that height), "outer": ring reach / stilts half size Vector2, "inner": ring hole, "hut": bool, "gaps": [Vector2: openings in the railing], "busy": [Vector2: spots taken by a lift or a ladder's foot, no opening]}
var ways: Array = []  # {"id", "kind", "from": deck index or -1 (ground), "to": deck index, "price", "ends": [Vector3, Vector3] (stand spots: low / from end first), "open": bool, + geometry: ladder "foot" / "top" Vector3 + "face" Vector2 (toward the deck); bridge "a" / "b" Vector3; lift "foot" / "top" Vector3 + "face"}
var _deck_index := {}


func _init(config: Dictionary, land: RefCounted) -> void:
	cfg = config
	var layers: Array = cfg["layers"]
	var rings: Array = cfg["rings"]
	for v: Dictionary in cfg["villages"]:
		var isle := int(land.call("index_of", String(v["island"])))
		var mid: Vector2 = (land.get("islands") as Array)[isle]["at"]
		var tree_at := mid + Vector2(float(v["tree"][0]), float(v["tree"][1]))
		var tree: Dictionary = _tree_block(land, tree_at)
		var ground := float(land.call("height_at", tree_at.x, tree_at.y))
		for d: Dictionary in v["decks"]:
			var layer := int(d["layer"])
			var deck := {"id": String(d["id"]), "island": isle, "layer": layer, "y": ground + float(layers[layer - 1]), "gaps": [], "busy": [], "hut": bool(d.get("hut", false))}
			if String(d["on"]) == "tree":
				var h := float(layers[layer - 1])
				deck["kind"] = "ring"
				deck["at"] = TreeShape.axis_at(tree_at, h, float(tree["height"]))
				deck["outer"] = float(rings[layer - 1])
				deck["inner"] = TreeShape.radius_at(h, float(tree["height"]), float(tree["girth"])) * 1.18 + 0.25
				deck["tree"] = tree_at
			else:
				var at := mid + Vector2(float(d["at"][0]), float(d["at"][1]))
				deck["kind"] = "stilts"
				deck["at"] = at
				deck["outer"] = Vector2(float(d["size"][0]), float(d["size"][1])) * 0.5
				deck["y"] = float(land.call("height_at", at.x, at.y)) + float(layers[layer - 1])
			_deck_index[deck["id"]] = decks.size()
			decks.append(deck)
		for w: Dictionary in v["ways"]:
			var way := {"id": String(w["id"]), "kind": String(w["kind"]), "price": int(w["price"]), "open": false,
				"from": -1 if String(w["from"]) == "ground" else int(_deck_index[String(w["from"])]), "to": int(_deck_index[String(w["to"])])}
			ways.append(way)
	for way: Dictionary in ways:  # bridges first: they fix where decks meet; ladders and lifts then take free sides
		if way["kind"] == "bridge":
			_place_bridge(way)
	for way: Dictionary in ways:
		if way["kind"] != "bridge":
			_place_climb(way, land)


func _tree_block(land: RefCounted, at: Vector2) -> Dictionary:
	for b: Dictionary in land.get("blocks"):
		if String(b["kind"]) == "tree" and (b["a"] as Vector2).distance_to(at) < 0.5:
			return b
	push_error("treetops: no giant tree at %s" % str(at))
	return {"height": 30.0, "girth": 1.8}


# Where a deck's edge is toward a plan point (and the way out of it there).
func edge_toward(deck: Dictionary, toward: Vector2) -> Vector2:
	var at: Vector2 = deck["at"]
	var dir := (toward - at).normalized()
	if deck["kind"] == "ring":
		return at + dir * float(deck["outer"])
	var half: Vector2 = deck["outer"]
	var t := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	return at + dir * t


func _place_bridge(way: Dictionary) -> void:
	var a: Dictionary = decks[int(way["from"])]
	var b: Dictionary = decks[int(way["to"])]
	var ea := edge_toward(a, b["at"])
	var eb := edge_toward(b, a["at"])
	way["a"] = Vector3(ea.x, float(a["y"]), ea.y)
	way["b"] = Vector3(eb.x, float(b["y"]), eb.y)
	(a["gaps"] as Array).append(ea)
	(b["gaps"] as Array).append(eb)
	var inward_a := ((a["at"] as Vector2) - ea).normalized() * STAND
	var inward_b := ((b["at"] as Vector2) - eb).normalized() * STAND
	way["ends"] = [Vector3(ea.x + inward_a.x, float(a["y"]), ea.y + inward_a.y), Vector3(eb.x + inward_b.x, float(b["y"]), eb.y + inward_b.y)]


# A ladder or lift goes up the side of its top deck that is farthest from the openings already used (and for a ring
# whose lower deck is a ring too, over that lower ring).
func _place_climb(way: Dictionary, land: RefCounted) -> void:
	var top: Dictionary = decks[int(way["to"])]
	var at: Vector2 = top["at"]
	var best := Vector2.ZERO
	var best_score := -INF
	for k in 24:
		var ang := TAU * float(k) / 24.0
		var dir := Vector2(cos(ang), sin(ang))
		var edge := edge_toward(top, at + dir * 50.0)
		if top["kind"] == "stilts":  # only the middles of the four sides
			var half: Vector2 = top["outer"]
			if k % 6 != 0:
				continue
			edge = at + dir * (half.x if absf(dir.x) > 0.5 else half.y)
		var score := 0.0
		var nearest := INF
		for g: Vector2 in top["gaps"] + top["busy"]:
			nearest = minf(nearest, g.distance_to(edge))
		score = minf(nearest, 12.0)
		if int(way["from"]) >= 0:
			var low: Dictionary = decks[int(way["from"])]
			for g: Vector2 in low["gaps"] + low["busy"]:
				score = minf(score, g.distance_to(edge) + 1.0)
		elif float(land.call("height_at", edge.x + dir.x, edge.y + dir.y)) < -0.05 or bool(land.call("blocked", edge.x + dir.x * 1.2, edge.y + dir.y * 1.2, 0.6, true)):
			score -= 100.0  # its foot would be in the water, on a slope or in a rock
		if score > best_score:
			best_score = score
			best = edge
	var out := (best - at).normalized()
	(top["busy"] if way["kind"] == "lift" else top["gaps"] as Array).append(best)  # a lift's rider is set down on the deck: no opening
	var hang := best + out * LADDER_OUT
	var foot_y: float = float(land.call("height_at", hang.x, hang.y)) if int(way["from"]) < 0 else float(decks[int(way["from"])]["y"])
	if int(way["from"]) >= 0:
		(decks[int(way["from"])]["busy"] as Array).append(hang)  # keeps the lower deck's next ways off it
	way["face"] = -out  # the climber faces the deck
	way["foot"] = Vector3(hang.x, foot_y, hang.y)
	way["top"] = Vector3(hang.x, float(top["y"]), hang.y)
	var below := hang + out * STAND  # on the ground: in front of the ladder
	var above := best - out * STAND
	if int(way["from"]) >= 0:
		below = hang + Vector2(-out.y, out.x) * STAND  # on the lower deck: beside its foot (the ring ends just past it)
	if way["kind"] == "lift":
		hang = best + out * 1.1  # the shaft stands clear of the deck's edge
		way["foot"] = Vector3(hang.x, foot_y, hang.y)
		way["top"] = Vector3(hang.x, float(top["y"]), hang.y)
		below = hang + out * 1.6
	way["ends"] = [Vector3(below.x, foot_y, below.y), Vector3(above.x, float(top["y"]), above.y)]


func deck_of(id: String) -> int:
	return int(_deck_index.get(id, -1))


# The way whose end a spot (world-plan x / z, height y) is at, -1 = none. Ends of open ways count too (a lift is
# ridden from its ends).
func way_near(x: float, y: float, z: float) -> int:
	var reach := float(cfg["reach"])
	var best := -1
	var best_d := reach
	for i in ways.size():
		for e: Vector3 in ways[i]["ends"]:
			if absf(e.y - y) > 1.6:
				continue
			var d := Vector2(e.x - x, e.z - z).length()
			if d < best_d:
				best_d = d
				best = i
	return best


# Which end of a way (0 = low / from, 1 = high / to) a spot is at.
func end_at(way: int, x: float, y: float, z: float) -> int:
	var e0: Vector3 = ways[way]["ends"][0]
	var e1: Vector3 = ways[way]["ends"][1]
	return 0 if Vector3(x, y, z).distance_to(e0) <= Vector3(x, y, z).distance_to(e1) else 1


func is_open(way: int) -> bool:
	return way >= 0 and way < ways.size() and bool(ways[way]["open"])


func price(way: int) -> int:
	return int(ways[way]["price"])


func open(way: int) -> bool:
	if way < 0 or way >= ways.size() or is_open(way):
		return false
	ways[way]["open"] = true
	return true


func close_all() -> void:
	for w: Dictionary in ways:
		w["open"] = false


func open_list() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in ways.size():
		if is_open(i):
			out.append(i)
	return out


# True when a plan spot at height y is inside an open ladder's climb box.
func on_ladder(x: float, y: float, z: float) -> bool:
	for w: Dictionary in ways:
		if w["kind"] != "ladder" or not bool(w["open"]):
			continue
		var foot: Vector3 = w["foot"]
		var top: Vector3 = w["top"]
		if y < foot.y - 0.2 or y > top.y + 0.5:
			continue
		var face: Vector2 = w["face"]
		var off := Vector2(x - foot.x, z - foot.z)
		var along := off.dot(face)  # toward the deck: a little in front, a little behind
		var side := absf(off.dot(Vector2(-face.y, face.x)))
		if side < 0.55 and along > -0.75 and along < 0.55:
			return true
	return false


# The deck a plan spot at height y stands on, -1 = none (the ground, the water, a bridge).
func deck_at(x: float, y: float, z: float) -> int:
	for i in decks.size():
		var d: Dictionary = decks[i]
		if absf(y - float(d["y"])) > 1.2:
			continue
		var off := Vector2(x, z) - (d["at"] as Vector2)
		if d["kind"] == "ring":
			if off.length() <= float(d["outer"]) + 0.1 and off.length() >= float(d["inner"]) - 0.3:
				return i
		elif absf(off.x) <= (d["outer"] as Vector2).x + 0.1 and absf(off.y) <= (d["outer"] as Vector2).y + 0.1:
			return i
	return -1
