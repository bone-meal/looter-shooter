# Purpose: (polish1 D4c) the treetop village's plain rules (data/treetops.json): the decks (rings round a giant tree's
# trunk at three heights, platforms on stilts) and the WAYS between them (ladders, lifts, rope bridges) bought like
# doors in any order, and (part 2) the OFFSHORE complex in the middle sea (rig decks on legs or on lower decks, free stairs
# and catwalk links between them) joined to the villages' top rings by bought CATWALKS. Works out where every deck and every way's ends are (world-plan metres, the islands' frame:
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
var climbs: Array = []  # (polish1 D4d) where climbing enemies go up / down: {"deck": index, "from": lower deck index or -1 (ground), "foot": Vector3 (where it starts, at the bottom), "top": Vector3 (where it steps off on the deck)}
var cut := {}  # (polish1 D4d) way index -> true while a rope-cutter has cut it (players mend it for free)
var buys: Array = []  # (part 3) {"kind": "wall" | "perk" | "reforge", "gun", "price", "perk", "deck": index, "at": Vector2, "y": float, "yaw": radians}
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
			if String(w["kind"]) == "catwalk":
				continue  # (added once the offshore decks exist)
			var way := {"id": String(w["id"]), "kind": String(w["kind"]), "price": int(w["price"]), "open": false,
				"from": -1 if String(w["from"]) == "ground" else int(_deck_index[String(w["from"])]), "to": int(_deck_index[String(w["to"])])}
			ways.append(way)
	_offshore(cfg.get("offshore", {}))
	for v: Dictionary in cfg["villages"]:  # the villages' catwalks to the offshore complex (its decks exist now)
		for w: Dictionary in v["ways"]:
			if String(w["kind"]) == "catwalk":
				ways.append({"id": String(w["id"]), "kind": "catwalk", "price": int(w["price"]), "open": false, "from": int(_deck_index[String(w["from"])]), "to": int(_deck_index[String(w["to"])])})
	for way: Dictionary in ways:  # bridges first: they fix where decks meet; ladders and lifts then take free sides
		if way["kind"] == "bridge" or way["kind"] == "catwalk":
			_place_bridge(way)
	for way: Dictionary in ways:
		if way["kind"] == "ladder" or way["kind"] == "lift":
			_place_climb(way, land)
		elif way["kind"] == "catwalk":
			way["pylons"] = _pylons(way, land)
	_place_climbs(land)
	for b: Dictionary in cfg.get("buys", []):  # (part 3) the best buys high
		var di := int(_deck_index[String(b["deck"])])
		var deck: Dictionary = decks[di]
		var at: Vector2 = deck["at"]
		var yaw := deg_to_rad(float(b.get("yaw", 0.0)))
		if b.has("at"):
			at = Vector2(float(b["at"][0]), float(b["at"][1]))
		elif not (deck["gaps"] as Array).is_empty():  # in the hut's middle, its front toward the deck's first opening
			var to: Vector2 = (deck["gaps"] as Array)[0] - at
			yaw = atan2(to.x, to.y)
		buys.append({"kind": String(b["kind"]), "gun": String(b.get("gun", "")), "price": int(b.get("price", 0)), "perk": String(b.get("perk", "")), "deck": di, "at": at, "y": float(deck["y"]), "yaw": yaw})


# A long catwalk's pylons, about every 15 m: in the sea, or on flat land clear of rocks and trees (nudged along the
# catwalk until they are; a beach slope is skipped).
func _pylons(way: Dictionary, land: RefCounted) -> Array:
	var a: Vector3 = way["a"]
	var b: Vector3 = way["b"]
	var flat := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(1, floori(flat / 15.0))
	var out: Array = []
	for k in range(1, n + 1):
		for nudge: float in [0.0, 2.5, -2.5, 5.0, -5.0]:
			var t := clampf((float(k) / float(n + 1)) + nudge / flat, 0.08, 0.92)
			var p := Vector2(lerpf(a.x, b.x, t), lerpf(a.z, b.z, t))
			var h := float(land.call("height_at", p.x, p.y))
			var in_sea := h < float(land.get("sea_level")) - 0.5
			if in_sea or (is_zero_approx(h) and not bool(land.call("blocked", p.x, p.y, 1.2, true))):
				out.append(p)
				break
	return out


# (polish1 D4c part 2) The offshore complex: decks on legs or on lower decks, free stairs and catwalk links between them.
func _offshore(o: Dictionary) -> void:
	for d: Dictionary in o.get("decks", []):
		var r: Array = d["rect"]
		var deck := {"id": String(d["id"]), "island": -1, "kind": "rig", "layer": 0, "y": float(d["y"]), "gaps": [], "busy": [], "hut": false,
			"at": Vector2((float(r[0]) + float(r[2])) * 0.5, (float(r[1]) + float(r[3])) * 0.5), "outer": Vector2(absf(float(r[2]) - float(r[0])), absf(float(r[3]) - float(r[1]))) * 0.5,
			"legs": bool(d.get("legs", false)), "on": int(_deck_index.get(String(d.get("on", "")), -1)), "name": String(d.get("name", ""))}
		_deck_index[deck["id"]] = decks.size()
		decks.append(deck)
	for st: Dictionary in o.get("stairs", []):
		var low: Dictionary = decks[int(_deck_index[String(st["from"])])]
		var high: Dictionary = decks[int(_deck_index[String(st["to"])])]
		var start := Vector2(float(st["start"][0]), float(st["start"][1]))
		var end := Vector2(float(st["end"][0]), float(st["end"][1]))
		var join := _nearest_on(high, end)  # where the landing at the top meets the upper deck's edge
		(high["gaps"] as Array).append(join)
		ways.append({"id": "stairs_%s_%s" % [low["id"], high["id"]], "kind": "stairs", "price": 0, "open": true, "free": true, "from": int(_deck_index[low["id"]]), "to": int(_deck_index[high["id"]]),
			"start": Vector3(start.x, float(low["y"]), start.y), "end": Vector3(end.x, float(high["y"]), end.y), "join": Vector3(join.x, float(high["y"]), join.y), "width": float(st.get("width", 2.0)), "ends": []})
	for l: Dictionary in o.get("links", []):
		var a: Dictionary = decks[int(_deck_index[String(l["from"])])]
		var b: Dictionary = decks[int(_deck_index[String(l["to"])])]
		var pa := Vector2(float(l["at"][0]), float(l["at"][1]))
		var pb := Vector2(float(l["to_at"][0]), float(l["to_at"][1]))
		(a["gaps"] as Array).append(pa)
		(b["gaps"] as Array).append(pb)
		ways.append({"id": "link_%s_%s" % [a["id"], b["id"]], "kind": "link", "price": 0, "open": true, "free": true, "from": int(_deck_index[a["id"]]), "to": int(_deck_index[b["id"]]),
			"a": Vector3(pa.x, float(a["y"]), pa.y), "b": Vector3(pb.x, float(b["y"]), pb.y), "ends": []})


# The point of a rectangular deck's edge nearest a plan point outside it (or the point itself when inside).
func _nearest_on(deck: Dictionary, p: Vector2) -> Vector2:
	var at: Vector2 = deck["at"]
	var half: Vector2 = deck["outer"]
	return Vector2(clampf(p.x, at.x - half.x, at.x + half.x), clampf(p.y, at.y - half.y, at.y + half.y))


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


# (polish1 D4d) Climbing spots: a ring is climbed from the ring below (the first from the ground) just outside its own
# edge, over the railing; a platform on stilts from the ground at the middle of its freest side. Offshore decks have
# none (climbers reach them by the catwalks).
func _place_climbs(land: RefCounted) -> void:
	for i in decks.size():
		var deck: Dictionary = decks[i]
		if deck["kind"] == "rig":
			continue
		var below := -1
		if deck["kind"] == "ring" and int(deck["layer"]) > 1:
			for j in decks.size():
				if decks[j]["kind"] == "ring" and int(decks[j]["island"]) == int(deck["island"]) and int(decks[j]["layer"]) == int(deck["layer"]) - 1:
					below = j
		var at: Vector2 = deck["at"]
		var best := Vector2.ZERO
		var best_score := -INF
		for k in 24:
			var dir := Vector2(cos(TAU * float(k) / 24.0), sin(TAU * float(k) / 24.0))
			if deck["kind"] == "stilts" and k % 6 != 0:
				continue
			var edge := edge_toward(deck, at + dir * 50.0)
			var score := 12.0
			for g: Vector2 in deck["gaps"] + deck["busy"]:
				score = minf(score, g.distance_to(edge))
			var foot2 := edge + dir * 0.6
			if below >= 0:
				for g: Vector2 in decks[below]["gaps"] + decks[below]["busy"]:
					score = minf(score, g.distance_to(foot2) + 0.5)
			elif float(land.call("height_at", foot2.x, foot2.y)) < -0.05 or bool(land.call("blocked", foot2.x, foot2.y, 0.5, true)):
				score -= 100.0
			if score > best_score:
				best_score = score
				best = edge
		var out := (best - at).normalized()
		var foot := best + out * 0.6
		var foot_y: float = float(decks[below]["y"]) if below >= 0 else float(land.call("height_at", foot.x, foot.y))
		var top := best - out * 0.9
		climbs.append({"deck": i, "from": below, "foot": Vector3(foot.x, foot_y, foot.y), "top": Vector3(top.x, float(deck["y"]), top.y)})
		(deck["busy"] as Array).append(best)


# (polish1 D4d) Where a climbing enemy at `from` should head for a prey at `to` (both in the islands' frame): {} = walk
# straight at it (the navigation mesh joins them: same deck, bridges, stairs, catwalks); {"goal": Vector3} = walk
# there first; with "climb": [start, end] = once there, climb from start to end (up or down). `node_of` decides where a
# spot is: a deck, the ground (-1) or nowhere useful (-2: on a bridge or stair: just keep going).
func route(from: Vector3, to: Vector3, ground_y: float) -> Dictionary:
	var a := _node_of(from, ground_y)
	var b := _node_of(to, ground_y)
	if a == b or a == -2 or b == -2:
		return {}
	var prev := {a: a}  # breadth first over decks (-1 = the ground)
	var how := {}  # node -> [climb index or -1 (a walk), from node]
	var queue := [a]
	while not queue.is_empty():
		var n: int = queue.pop_front()
		if n == b:
			break
		for step: Array in _steps_from(n):
			var m := int(step[0])
			if not prev.has(m):
				prev[m] = n
				how[m] = step[1]
				queue.append(m)
	if not prev.has(b):
		return {}  # no way up there (yet): go as near as it can
	var chain: Array = []
	var n2 := b
	while n2 != a:
		chain.push_front([n2, how[n2]])
		n2 = int(prev[n2])
	for link: Array in chain:  # the first climb on the way decides; walks before it are done by the navigation mesh
		var c := int(link[1])
		if c >= 0:
			var cl: Dictionary = climbs[c]
			var up := int(link[0]) == int(cl["deck"])
			var start: Vector3 = cl["foot"] if up else cl["top"]
			var end: Vector3 = cl["top"] if up else cl["foot"]
			return {"goal": start, "climb": [start, end]}
	return {}


func _node_of(p: Vector3, ground_y: float) -> int:
	var d := deck_at(p.x, p.y, p.z)
	if d >= 0:
		return d
	return -1 if p.y < ground_y + 1.6 else -2


# The decks one step from a node: climbs (both ways) and open / free walks between decks.
func _steps_from(n: int) -> Array:
	var out: Array = []
	for i in climbs.size():
		var cl: Dictionary = climbs[i]
		if int(cl["from"]) == n:
			out.append([int(cl["deck"]), i])
		elif int(cl["deck"]) == n:
			out.append([int(cl["from"]), i])
	for w: Dictionary in ways:
		if w["kind"] in ["ladder", "lift"] or not bool(w["open"]):
			continue  # (ladders and lifts are the players' ways)
		if int(w["from"]) == n:
			out.append([int(w["to"]), -1])
		elif int(w["to"]) == n:
			out.append([int(w["from"]), -1])
	return out


# (polish1 D4d) A rope-cutter's errand: the nearest bought rope bridge or rope ladder to `from` and the spot (on a deck)
# where it cuts it: {"way": index, "at": Vector3}, or {} when there is none.
func cut_target(from: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for i in ways.size():
		var w: Dictionary = ways[i]
		if not bool(w["open"]) or not (w["kind"] in ["bridge", "ladder"]):
			continue
		var at: Vector3 = w["ends"][0] if w["kind"] == "bridge" else w["ends"][1]
		var d := from.distance_to(at)
		if d < best_d:
			best_d = d
			best = {"way": i, "at": at}
	return best


# A rope-cutter cut this way: it falls (not bought any more) until a player mends it. True when it changed.
func cut_way(way: int) -> bool:
	if not is_open(way) or not (ways[way]["kind"] in ["bridge", "ladder"]):
		return false
	ways[way]["open"] = false
	cut[way] = true
	return true


# A player mended a cut way: open again, free.
func mend(way: int) -> bool:
	if not cut.has(way):
		return false
	cut.erase(way)
	ways[way]["open"] = true
	return true


func deck_of(id: String) -> int:
	return int(_deck_index.get(id, -1))


# The way whose end a spot (world-plan x / z, height y) is at, -1 = none. Ends of open ways count too (a lift is
# ridden from its ends).
func way_near(x: float, y: float, z: float) -> int:
	var reach := float(cfg["reach"])
	var best := -1
	var best_d := reach
	for i in ways.size():
		if bool(ways[i].get("free", false)):
			continue
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
	if way < 0 or way >= ways.size() or is_open(way) or bool(ways[way].get("free", false)):
		return false
	ways[way]["open"] = true
	return true


func close_all() -> void:
	cut.clear()
	for w: Dictionary in ways:
		w["open"] = bool(w.get("free", false))  # (the offshore complex's own stairs and links are always there)


func open_list() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in ways.size():
		if is_open(i) and not bool(ways[i].get("free", false)):
			out.append(i)
	return out


# True when a plan spot at height y is inside an open ladder's climb box.
func on_ladder(x: float, y: float, z: float) -> bool:
	for w: Dictionary in ways:
		if w["kind"] != "ladder" or not bool(w["open"]):
			continue
		var foot: Vector3 = w["foot"]
		var top: Vector3 = w["top"]
		if y < foot.y - 0.2 or y > top.y + 0.9:  # (bug update: 0.5 let gravity take the body back before its feet were over the lip)
			continue
		var face: Vector2 = w["face"]
		var off := Vector2(x - foot.x, z - foot.z)
		var along := off.dot(face)  # toward the deck: a little in front, a little behind
		var side := absf(off.dot(Vector2(-face.y, face.x)))
		if side < 0.55 and along > -0.75 and along < 0.55:
			return true
	return false


# (bug update) The top height of the open ladder at a plan spot (see on_ladder), INF when on none.
func ladder_top(x: float, y: float, z: float) -> float:
	for w: Dictionary in ways:
		if w["kind"] != "ladder" or not bool(w["open"]):
			continue
		var foot: Vector3 = w["foot"]
		var top: Vector3 = w["top"]
		if y < foot.y - 0.2 or y > top.y + 0.9:
			continue
		var face: Vector2 = w["face"]
		var off := Vector2(x - foot.x, z - foot.z)
		var along := off.dot(face)
		if absf(off.dot(Vector2(-face.y, face.x))) < 0.55 and along > -0.75 and along < 0.55:
			return top.y
	return INF


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
