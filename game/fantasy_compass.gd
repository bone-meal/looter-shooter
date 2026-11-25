# Purpose: (polish1 item 98) the compass across the top of the screen in Aurelind, drawn as an unrolled scroll with
# 1400s manuscript lettering: the four winds in blackletter (north an illuminated red and gold capital), ticks, and
# margin-art marks for what lies that way: where the open quests send you (a red seal), people with a quest to give
# (a gold "!"), places by kind (the map's little signs) once found and a faint "?" for places not found yet, the
# named areas a quest is bound to, and nearby work stations (forge, cauldron, workbench, fire). The mark nearest the
# middle is named under the scroll with its distance. On spawn it points to Farmer Hale (his "!").
# Pure drawing over any CanvasItem; the list of marks is gathered twice a second from the world.
# Dependencies: game/fantasy_world.gd (quests, places, terrain, found, player_local, player_yaw),
# game/fantasy_style.gd (fonts, colours).
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")

const WIDTH := 640.0
const HEIGHT := 40.0
const HALF_VIEW := deg_to_rad(100.0)  # the scroll shows 200 degrees round you
const PLACE_REACH := 900.0  # places further away than this are left off
const PEOPLE_REACH := 450.0  # people with a quest to give
const STATION_REACH := 70.0
const INK := Color(0.2, 0.12, 0.06)
const RED := Color(0.62, 0.1, 0.07)
const PAPER := Color(0.9, 0.82, 0.62)
const PAPER_DARK := Color(0.74, 0.62, 0.42)

var marks: Array = []  # {"x", "z", "kind": quest | giver | place | unknown | area | station, "sign" (place kind / station kind), "name"}
var _since := 99.0


# Gathers what the compass shows (call every frame; works twice a second).
func update(world: Node3D, delta: float) -> void:
	_since += delta
	if _since < 0.5:
		return
	_since = 0.0
	marks = []
	var me: Vector3 = world.call("player_local")
	var quests: RefCounted = world.get("quests")
	var places: Node = world.get("places")
	var terrain: RefCounted = world.get("terrain")
	var found: Dictionary = world.get("found")
	var seen := {}
	for id: String in quests.get("active"):
		var step: Dictionary = quests.call("step", id)
		var q_name := String((quests.call("quest", id) as Dictionary).get("name", ""))
		match String(step.get("type", "")):
			"talk":
				var who: Dictionary = places.call("person", String(step["npc"]))
				if not who.is_empty():
					_add({"x": (who["at"] as Vector3).x, "z": (who["at"] as Vector3).z, "kind": "quest", "name": "%s (%s)" % [String(who["name"]), q_name]}, seen, "p:" + String(step["npc"]))
			"reach":
				var p: Dictionary = terrain.call("place", String(step["place"]))
				if not p.is_empty():
					_add({"x": float(p["pos"][0]), "z": float(p["pos"][1]), "kind": "quest", "name": "%s (%s)" % [String(p["name"]), q_name]}, seen, "pl:" + String(step["place"]))
			"kill":
				if step.has("area"):
					var a: Dictionary = terrain.call("area_by_id", String(step["area"]))
					if not a.is_empty():
						_add({"x": float(a["x"]), "z": float(a["z"]), "kind": "quest", "name": "%s (%s)" % [String(a["name"]), q_name]}, seen, "a:" + String(step["area"]))
				else:  # a boss: its arena
					for p: Dictionary in terrain.get("places"):
						if String(p.get("boss", "")) == String(step["enemy"]):
							_add({"x": float(p["pos"][0]), "z": float(p["pos"][1]), "kind": "quest", "name": "%s (%s)" % [String(p["name"]), q_name]}, seen, "pl:" + String(p["id"]))
			"make":  # the nearest station that makes it
				var kind := _station_for(world, String(step["item"]))
				var best: Dictionary = {}
				var best_d := INF
				for st: Dictionary in places.get("stations"):
					if String(st["kind"]) == kind:
						var d := Vector2((st["at"] as Vector3).x - me.x, (st["at"] as Vector3).z - me.z).length()
						if d < best_d:
							best_d = d
							best = st
				if not best.is_empty():
					_add({"x": (best["at"] as Vector3).x, "z": (best["at"] as Vector3).z, "kind": "quest", "name": "%s (%s)" % [kind.capitalize(), q_name]}, seen, "st:" + kind)
	for who: Dictionary in places.get("people"):
		if bool(who.get("folk", false)) or seen.has("p:" + String(who["id"])):
			continue
		var at: Vector3 = who["at"]
		if Vector2(at.x - me.x, at.z - me.z).length() < PEOPLE_REACH and not (quests.call("offers", String(who["id"])) as Array).is_empty():
			_add({"x": at.x, "z": at.z, "kind": "giver", "name": String(who["name"])}, seen, "p:" + String(who["id"]))
	for p: Dictionary in terrain.get("places"):
		if seen.has("pl:" + String(p["id"])):
			continue
		var d := Vector2(float(p["pos"][0]) - me.x, float(p["pos"][1]) - me.z).length()
		if d > PLACE_REACH or d < float(p.get("flat", 30.0)) or String(p["kind"]) == "landing":  # (polish1 F1a) level ground only, not a place
			continue
		if found.has(String(p["id"])):
			marks.append({"x": float(p["pos"][0]), "z": float(p["pos"][1]), "kind": "place", "sign": String(p["kind"]), "name": String(p["name"])})
		else:
			marks.append({"x": float(p["pos"][0]), "z": float(p["pos"][1]), "kind": "unknown", "name": "Not yet found"})
	for st: Dictionary in places.get("stations"):
		var at: Vector3 = st["at"]
		var kind := String(st["kind"])
		if kind in ["forge", "cauldron", "workbench", "fire"] and Vector2(at.x - me.x, at.z - me.z).length() < STATION_REACH and not seen.has("st:" + kind):
			seen["st:" + kind] = true
			marks.append({"x": at.x, "z": at.z, "kind": "station", "sign": kind, "name": kind.capitalize()})


func _add(mark: Dictionary, seen: Dictionary, key: String) -> void:
	if seen.has(key):
		return
	seen[key] = true
	marks.append(mark)


func _station_for(world: Node3D, item: String) -> String:
	for r: Dictionary in (world.get("skilling") as Dictionary).get("recipes", []):
		if (r.get("out", {}) as Dictionary).has(item):
			return String(r.get("station", ""))
	return ""


# North = 0, east = 90 degrees (x east, z south).
static func bearing(dx: float, dz: float) -> float:
	return atan2(dx, -dz)


# Draws the scroll centred at `top_middle` (its top edge).
func draw(canvas: CanvasItem, world: Node3D, top_middle: Vector2) -> void:
	var yaw := float(world.call("player_yaw"))
	var facing := bearing(-sin(yaw), -cos(yaw))
	var me: Vector3 = world.call("player_local")
	var strip := Rect2(top_middle - Vector2(WIDTH * 0.5, 0.0), Vector2(WIDTH, HEIGHT))
	_paper(canvas, strip)
	var mid := strip.get_center().x
	var font := Style.blackletter()
	# ticks every 15 degrees, longer every 45
	for k in 24:
		var x := _x_of(deg_to_rad(15.0 * k) - facing, strip)
		if x < 0.0:
			continue
		var fade := _edge_fade(x, strip)
		var long := k % 3 == 0
		canvas.draw_line(Vector2(x, strip.end.y - (11.0 if long else 6.0)), Vector2(x, strip.end.y - 3.0), Color(INK, 0.55 * fade), 1.4 if long else 1.0)
	# the winds
	var winds := [["N", 0.0], ["E", 90.0], ["S", 180.0], ["W", 270.0]]
	for w: Array in winds:
		var x := _x_of(deg_to_rad(float(w[1])) - facing, strip)
		if x < 0.0:
			continue
		var fade := _edge_fade(x, strip)
		if String(w[0]) == "N":  # an illuminated capital: gold square, red letter
			var box := Rect2(Vector2(x - 12.0, strip.position.y + 5.0), Vector2(24.0, 24.0))
			canvas.draw_rect(box, Color(0.82, 0.62, 0.22, 0.9 * fade))
			canvas.draw_rect(box, Color(INK, 0.7 * fade), false, 1.2)
			canvas.draw_string(font, Vector2(x - 12.0, strip.position.y + 26.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 24.0, 24, Color(RED, fade))
		else:
			canvas.draw_string(font, Vector2(x - 12.0, strip.position.y + 27.0), String(w[0]), HORIZONTAL_ALIGNMENT_CENTER, 24.0, 22, Color(INK, 0.85 * fade))
	for k in [45.0, 135.0, 225.0, 315.0]:  # between the winds: a little four-petal flower
		var x := _x_of(deg_to_rad(k) - facing, strip)
		if x >= 0.0:
			_flower(canvas, Vector2(x, strip.position.y + 17.0), 3.0, Color(RED, 0.55 * _edge_fade(x, strip)))
	# marks (quests on top), the one nearest the middle is named under the scroll
	var named: Dictionary = {}
	var named_off := 999.0
	var order := ["unknown", "station", "place", "area", "giver", "quest"]
	for kind: String in order:
		for m: Dictionary in marks:
			if String(m["kind"]) != kind:
				continue
			var dx := float(m["x"]) - me.x
			var dz := float(m["z"]) - me.z
			var x := _x_of(bearing(dx, dz) - facing, strip)
			if x < 0.0:
				continue
			var fade := _edge_fade(x, strip)
			_mark(canvas, m, Vector2(x, strip.position.y + 18.0), fade)
			var off := absf(x - mid)
			if off < 26.0 and (off < named_off or kind == "quest") and String(m["kind"]) != "unknown":
				if kind == "quest" or named.is_empty() or String(named["kind"]) != "quest":
					named = m
					named_off = off
					named["dist"] = Vector2(dx, dz).length()
	# the middle: a small red caret under the scroll
	canvas.draw_colored_polygon(PackedVector2Array([Vector2(mid, strip.end.y - 1.0), Vector2(mid - 6.0, strip.end.y + 7.0), Vector2(mid + 6.0, strip.end.y + 7.0)]), RED)
	if not named.is_empty():
		var label := "%s   %d m" % [String(named["name"]), roundi(float(named["dist"]))]
		var g := Style.gothic()
		canvas.draw_string_outline(g, Vector2(mid - 260.0, strip.end.y + 26.0), label, HORIZONTAL_ALIGNMENT_CENTER, 520.0, 17, 5, Color(0, 0, 0, 0.7))
		canvas.draw_string(g, Vector2(mid - 260.0, strip.end.y + 26.0), label, HORIZONTAL_ALIGNMENT_CENTER, 520.0, 17, PAPER if String(named["kind"]) != "quest" else Color(1.0, 0.82, 0.4))


func _x_of(angle: float, strip: Rect2) -> float:
	var a := wrapf(angle, -PI, PI)
	if absf(a) > HALF_VIEW:
		return -1.0
	return strip.get_center().x + a / HALF_VIEW * (strip.size.x * 0.5 - 26.0)


func _edge_fade(x: float, strip: Rect2) -> float:
	var off := absf(x - strip.get_center().x) / (strip.size.x * 0.5 - 26.0)
	return clampf((1.0 - off) / 0.22, 0.0, 1.0)


# The unrolled scroll: aged paper, a darker rim, ruled lines, and a roll at each end.
func _paper(c: CanvasItem, r: Rect2) -> void:
	c.draw_rect(r.grow(2.0), Color(0, 0, 0, 0.35))
	c.draw_rect(r, PAPER)
	for k in 6:  # darker toward the edges (aged)
		var t := float(k) / 6.0
		c.draw_rect(Rect2(r.position.x, r.position.y + t * 3.0, r.size.x, 1.5), Color(PAPER_DARK, 0.18))
		c.draw_rect(Rect2(r.position.x, r.end.y - 1.5 - t * 3.0, r.size.x, 1.5), Color(PAPER_DARK, 0.18))
	c.draw_line(r.position + Vector2(24, 4), Vector2(r.end.x - 24, r.position.y + 4), Color(RED, 0.35), 1.0)  # ruled in red ink, as a scribe would
	c.draw_line(Vector2(r.position.x + 24, r.end.y - 4), r.end - Vector2(24, 4), Color(RED, 0.35), 1.0)
	for side: float in [r.position.x, r.end.x]:  # the rolls: shaded cylinders past the paper's ends
		var roll := Rect2(Vector2(side - 9.0, r.position.y - 5.0), Vector2(18.0, r.size.y + 10.0))
		for k in 9:
			var t := float(k) / 8.0
			var shade := Color(0.56, 0.42, 0.24).lerp(Color(0.95, 0.86, 0.66), sin(t * PI))
			c.draw_rect(Rect2(roll.position.x + t * 16.0, roll.position.y, 2.2, roll.size.y), shade)
		c.draw_rect(roll, Color(INK, 0.6), false, 1.0)
		c.draw_rect(Rect2(roll.position.x + 5.0, roll.position.y - 4.0, 8.0, 4.0), Color(0.42, 0.26, 0.12))  # the rod's knobs
		c.draw_rect(Rect2(roll.position.x + 5.0, roll.end.y, 8.0, 4.0), Color(0.42, 0.26, 0.12))


func _flower(c: CanvasItem, at: Vector2, s: float, ink: Color) -> void:
	for k in 4:
		var d := Vector2.from_angle(PI * 0.5 * k + PI * 0.25)
		c.draw_circle(at + d * s, s * 0.7, ink)
	c.draw_circle(at, s * 0.45, Color(0.82, 0.62, 0.22, ink.a))


# One mark in the margin-art style.
func _mark(c: CanvasItem, m: Dictionary, at: Vector2, fade: float) -> void:
	match String(m["kind"]):
		"quest":  # a red wax seal with a gold star
			c.draw_circle(at, 9.0, Color(RED, fade))
			c.draw_arc(at, 9.0, 0.0, TAU, 20, Color(0.3, 0.04, 0.02, fade), 1.5, true)
			var star := PackedVector2Array()
			for k in 10:
				star.append(at + Vector2.from_angle(-PI * 0.5 + PI * k / 5.0) * (6.0 if k % 2 == 0 else 2.6))
			c.draw_colored_polygon(star, Color(0.98, 0.8, 0.3, fade))
		"giver":  # a gold "!" over a little scroll
			c.draw_rect(Rect2(at + Vector2(-7, 4), Vector2(14, 5)), Color(PAPER_DARK, fade))
			c.draw_string(Style.blackletter(), at + Vector2(-8, 6), "!", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 22, Color(0.86, 0.6, 0.12, fade))
			c.draw_string_outline(Style.blackletter(), at + Vector2(-8, 6), "!", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 22, 2, Color(INK, 0.6 * fade))
		"unknown":  # a faint question
			c.draw_string(Style.blackletter(), at + Vector2(-8, 7), "?", HORIZONTAL_ALIGNMENT_CENTER, 16.0, 18, Color(INK, 0.32 * fade))
		"station":
			_station(c, String(m["sign"]), at, Color(INK, 0.75 * fade))
		_:
			_place_sign(c, String(m.get("sign", "")), at, Color(INK, 0.85 * fade))


# The map's little signs, smaller.
func _place_sign(c: CanvasItem, kind: String, at: Vector2, ink: Color) -> void:
	if kind.begins_with("town"):
		c.draw_rect(Rect2(at + Vector2(-6, -2), Vector2(12, 8)), ink)
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(-8, -2), at + Vector2(0, -9), at + Vector2(8, -2)]), ink)
		c.draw_rect(Rect2(at + Vector2(-1.5, 1), Vector2(3, 5)), PAPER)
	elif kind in ["village", "farm"]:
		c.draw_rect(Rect2(at + Vector2(-4, -1), Vector2(8, 6)), ink)
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(-6, -1), at + Vector2(0, -6), at + Vector2(6, -1)]), ink)
	elif kind == "arena":
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -7), at + Vector2(6, 0), at + Vector2(0, 7), at + Vector2(-6, 0)]), Color(RED, ink.a))
	elif kind.begins_with("tribe") or kind == "camp":
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -7), at + Vector2(6, 5), at + Vector2(-6, 5)]), ink)
	elif kind == "course":
		c.draw_line(at + Vector2(-3, 6), at + Vector2(-3, -7), ink, 1.5)
		c.draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -7), at + Vector2(6, -4), at + Vector2(-3, -1)]), Color(0.75, 0.25, 0.15, ink.a))
	elif kind == "battlefield":
		c.draw_line(at + Vector2(-5, -5), at + Vector2(5, 5), ink, 2.0)
		c.draw_line(at + Vector2(5, -5), at + Vector2(-5, 5), ink, 2.0)
	else:
		for o: Vector2 in [Vector2(-4, 3), Vector2(0, -3), Vector2(4, 3)]:
			c.draw_rect(Rect2(at + o - Vector2(1.6, 1.6), Vector2(3.2, 3.2)), ink)


func _station(c: CanvasItem, kind: String, at: Vector2, ink: Color) -> void:
	match kind:
		"forge":  # an anvil
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(-7, -3), at + Vector2(7, -3), at + Vector2(4, 0), at + Vector2(2, 0), at + Vector2(3, 4), at + Vector2(-3, 4), at + Vector2(-2, 0), at + Vector2(-5, 0)]), ink)
		"cauldron":  # a pot on legs
			c.draw_circle(at + Vector2(0, 1), 5.0, ink)
			c.draw_rect(Rect2(at + Vector2(-6, -4), Vector2(12, 2)), ink)
		"fire":  # a flame
			c.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -7), at + Vector2(4, 0), at + Vector2(2, 5), at + Vector2(-2, 5), at + Vector2(-4, 0)]), Color(0.8, 0.3, 0.08, ink.a))
		_:  # a workbench: a hammer
			c.draw_line(at + Vector2(-4, 5), at + Vector2(3, -2), ink, 2.0)
			c.draw_rect(Rect2(at + Vector2(0, -6), Vector2(7, 4)), ink)
