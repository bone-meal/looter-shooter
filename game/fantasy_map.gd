# Purpose: the world map of the fantasy world (key M): the whole country drawn like an inked chart on parchment, with
# the sea, lakes, hills, roads, every place the player has found by name (others are unnamed dots), region names with
# their levels, quest marks, the player's arrow and the rest of the party. Walking stays possible while it is open.
# The chart itself is painted ONCE EVER from the terrain rules, on a background thread after the land around the
# player has arrived, and kept as a picture in the user folder (named by a hash of the world data and the terrain
# rules' version): later sessions just load it. (Painting it at every start cost about 6 s of a worker thread at
# the very moment the land needed those threads.)
# (polish1 F1a) In a country the chart is that country; its border crossings are always marked, and beside the chart
# hangs the ATLAS: the whole continent (assets/ui/atlas.jpg, names placed by data/fantasy/atlas.json), the countries
# been to named, the others "?", this one ringed.
# Dependencies: game/fantasy_world.gd (terrain, found places, countries_seen, map_marks, player_local),
# game/fantasy_spawner.gd (bodies), game/fantasy_style.gd, game/input_setup.gd.
extends Control

const Style = preload("res://game/fantasy_style.gd")
const ChartPainter = preload("res://game/chart_painter.gd")
const InputSetup = preload("res://game/input_setup.gd")

const PIXELS := 512  # the chart is this many dots a side
const PAPER := Color(0.87, 0.8, 0.64)
const INKED := Color(0.2, 0.15, 0.1)
const SEA := Color(0.56, 0.66, 0.68)

var world: Node3D
var settings: RefCounted

var _chart: ImageTexture
var _atlas: Texture2D = null
var _atlas_names := {}  # country id -> {"x", "y" (shares of the atlas picture), "levels"}
var _task := -1
var _image: Image


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func is_open() -> bool:
	return visible


func toggle() -> void:
	visible = not visible
	world.call("sound", "ui_map")
	queue_redraw()


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if not bool(world.get("inside")):
		visible = false
	if _chart == null and _task < 0 and bool(world.get("inside")):
		_fetch_chart()
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_chart = ImageTexture.create_from_image(_image)
		_image.save_png(_chart_file())
	if visible:
		queue_redraw()


func _chart_file() -> String:
	return "user://fantasy_chart_%d_%d_%d.png" % [PIXELS, int(world.terrain.RULES_VERSION), JSON.stringify(world.terrain.data).hash()]


# The saved chart if there is one; otherwise it is painted once the land around the player has streamed in.
func _fetch_chart() -> void:
	var path := _chart_file()
	if FileAccess.file_exists(path):
		var saved := Image.load_from_file(path)
		if saved != null and saved.get_width() == PIXELS:
			_chart = ImageTexture.create_from_image(saved)
			return
	if int((world.get("land").call("counts") as Vector2i).y) == 0:
		_task = WorkerThreadPool.add_task(_paint)  # the terrain rules are pure: safe to read from another thread


# Runs on a worker thread: the cartographer's sheet (game/chart_painter.gd).
func _paint() -> void:
	_image = ChartPainter.paint(world.terrain, PIXELS)


func _spot(local_x: float, local_z: float, sheet: Rect2) -> Vector2:
	var half := float(world.terrain.size) * 0.5
	return sheet.position + Vector2((local_x + half) / (half * 2.0), (local_z + half) / (half * 2.0)) * sheet.size


func _draw() -> void:
	var side := minf(size.x, size.y) - 90.0
	var sheet := Rect2((size - Vector2(side, side)) * 0.5 + Vector2(0, 8.0), Vector2(side, side))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.35))
	Style.frame(self, sheet.grow(14.0))
	if _chart == null:
		draw_rect(sheet, PAPER)
		draw_string(Style.font(), sheet.position + Vector2(0, side * 0.5), "The cartographer is still drawing...", HORIZONTAL_ALIGNMENT_CENTER, side, 20, INKED)
		return
	draw_texture_rect(_chart, sheet, false)
	var terrain: RefCounted = world.terrain
	if terrain.country_shape != null:  # (polish1 F1a) rivers inked over the chart, wider downstream
		for river: Dictionary in terrain.country_shape.rivers:
			var pts: PackedVector2Array = river["points"]
			var wid: PackedFloat32Array = river["width"]
			for i in pts.size() - 1:
				draw_line(_spot(pts[i].x, pts[i].y, sheet), _spot(pts[i + 1].x, pts[i + 1].y, sheet), ChartPainter.RIVER, clampf(wid[i] * 0.14, 1.0, 2.6), true)
	var font := Style.font()
	# roads: dotted ink between the places they join
	for road: PackedVector2Array in terrain.roads:  # each road is a bent line of three points
		for i in road.size() - 1:
			draw_dashed_line(_spot(road[i].x, road[i].y, sheet), _spot(road[i + 1].x, road[i + 1].y, sheet), Color(INKED, 0.55), 1.5, 5.0)
	# regions: a spaced name and the levels found there (a country's regions are only the looks its land wears)
	for region: Dictionary in terrain.regions if not terrain.data.has("country") else []:
		var at := _spot(float(region["center"][0]), float(region["center"][1]), sheet)
		var known: bool = (world.get("found") as Dictionary).has(String(region["id"]))
		var title := String(region["name"]).to_upper() if known else "?  ?  ?"
		draw_string(font, at + Vector2(-150.0, -26.0), title, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 17, Color(INKED, 0.7))
		draw_string(font, at + Vector2(-150.0, -10.0), "levels %d - %d" % [int(region["level"][0]), int(region["level"][1])], HORIZONTAL_ALIGNMENT_CENTER, 300.0, 11, Color(INKED, 0.55))
	for lake: Dictionary in terrain.lakes:
		draw_string(font, _spot(float(lake["x"]), float(lake["z"]) + float(lake["r"]) + 14.0, sheet) + Vector2(-80.0, 0.0), String(lake["name"]), HORIZONTAL_ALIGNMENT_CENTER, 160.0, 10, Color(0.16, 0.26, 0.36, 0.85))
	# (polish1 item 129) named areas once found: a faint dashed edge (a ring round its middle, or along its road) and the name in italics
	for area: Dictionary in terrain.areas:
		if not (world.get("found") as Dictionary).has(String(area["id"])):
			continue
		var line: PackedVector2Array = area["road"]
		var ink := Color(0.42, 0.22, 0.1, 0.55)
		if not line.is_empty():
			for i in line.size() - 1:
				draw_line(_spot(line[i].x, line[i].y, sheet), _spot(line[i + 1].x, line[i + 1].y, sheet), Color(ink, 0.25), maxf(2.0, float(area["width"]) * 2.0 * sheet.size.x / float(terrain.size)))
		else:
			var c := _spot(float(area["cx"]), float(area["cz"]), sheet)
			var r := float(area["radius"]) * sheet.size.x / float(terrain.size)
			for k in 24:
				if k % 2 == 0:
					draw_arc(c, r, TAU * k / 24.0, TAU * (k + 1) / 24.0, 4, ink, 1.0, true)
		draw_string(Style.font_italic(), _spot(float(area["x"]), float(area["z"]), sheet) + Vector2(-90.0, 4.0), String(area["name"]), HORIZONTAL_ALIGNMENT_CENTER, 180.0, 11, Color(0.42, 0.22, 0.1, 0.85))
	# places: a sign by kind; the name once found
	for place: Dictionary in terrain.places:
		if String(place["kind"]) == "landing":  # (polish1 F1a) level ground only, not a place
			continue
		var at := _spot(float(place["pos"][0]), float(place["pos"][1]), sheet)
		var known: bool = (world.get("found") as Dictionary).has(String(place["id"])) or String(place["kind"]) == "crossing"
		_sign(String(place["kind"]), at, known, bool(place.get("hard", false)))
		if known:
			draw_string(font, at + Vector2(-90.0, 17.0), String(place["name"]), HORIZONTAL_ALIGNMENT_CENTER, 180.0, 12, INKED)
	# quests
	for mark: Dictionary in world.call("map_marks"):
		var at := _spot(float(mark["x"]), float(mark["z"]), sheet) + Vector2(9.0, -6.0)
		draw_circle(at, 7.5, Color(0.55, 0.12, 0.1))
		draw_string(font, at + Vector2(-8.0, 5.0), String(mark["mark"]), HORIZONTAL_ALIGNMENT_CENTER, 16.0, 13, Style.PARCHMENT)
		if String(mark.get("who", "")) != "":  # (polish1 item 123) whose mark it is
			draw_string(font, at + Vector2(12.0, 4.0), String(mark["who"]), HORIZONTAL_ALIGNMENT_LEFT, 220.0, 11, Color(0.55, 0.12, 0.1))
	# the party, then the player on top
	var me: Vector3 = world.call("player_local")
	for body: Node3D in world.spawner.call("bodies"):
		var local: Vector3 = world.call("local_of", body.global_position)
		if local.distance_to(me) > 1.0:
			draw_circle(_spot(local.x, local.z, sheet), 4.5, Color(0.15, 0.35, 0.6))
	var here := _spot(me.x, me.z, sheet)
	var facing := -float(world.call("player_yaw"))
	var nose := Vector2(sin(facing), -cos(facing))
	var wing := Vector2(-nose.y, nose.x)
	draw_colored_polygon(PackedVector2Array([here + nose * 11.0, here - nose * 6.0 + wing * 6.5, here - nose * 2.5, here - nose * 6.0 - wing * 6.5]), Color(0.62, 0.1, 0.08))
	draw_polyline(PackedVector2Array([here + nose * 11.0, here - nose * 6.0 + wing * 6.5, here - nose * 2.5, here - nose * 6.0 - wing * 6.5, here + nose * 11.0]), Style.PARCHMENT, 1.2, true)
	# title and compass
	var title := String(terrain.data["name"])
	if terrain.data.has("country"):
		title = "%s  (levels %s)" % [String(terrain.data["country_name"]), String(terrain.data.get("levels", ""))]
		_draw_atlas(Rect2(Vector2(20.0, sheet.position.y), Vector2(maxf(sheet.position.x - 50.0, 0.0), sheet.size.y)))
	Style.text(self, Vector2(sheet.position.x, sheet.position.y - 22.0), title, 24, Style.GOLD, HORIZONTAL_ALIGNMENT_CENTER, side)
	Style.text(self, Vector2(sheet.position.x, sheet.end.y + 30.0), "%s  close the map" % InputSetup.label(settings, "map"), 12, Style.FADED, HORIZONTAL_ALIGNMENT_CENTER, side)
	var rose := sheet.position + Vector2(side - 34.0, 40.0)
	draw_line(rose + Vector2(0, 16), rose + Vector2(0, -16), INKED, 1.5)
	draw_line(rose + Vector2(-10, 0), rose + Vector2(10, 0), INKED, 1.0)
	draw_colored_polygon(PackedVector2Array([rose + Vector2(0, -22), rose + Vector2(4, -12), rose + Vector2(-4, -12)]), INKED)
	draw_string(font, rose + Vector2(-10.0, -25.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 12, INKED)


# (polish1 F1a) The continent in the margin: the countries been to by name, the others unknown, this one ringed.
func _draw_atlas(box: Rect2) -> void:
	if box.size.x < 160.0:
		return
	if _atlas == null:
		_atlas = load("res://assets/ui/atlas.jpg") as Texture2D
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/fantasy/atlas.json"))
		_atlas_names = (parsed as Dictionary).get("countries", {}) if parsed is Dictionary else {}
	if _atlas == null:
		return
	var w := box.size.x
	var h := w * float(_atlas.get_height()) / float(_atlas.get_width())
	var pic := Rect2(box.position + Vector2(0.0, 34.0), Vector2(w, h))
	Style.frame(self, pic.grow(8.0))
	draw_texture_rect(_atlas, pic, false)
	Style.text(self, Vector2(pic.position.x, pic.position.y - 20.0), "The Continent", 18, Style.GOLD, HORIZONTAL_ALIGNMENT_CENTER, w)
	var seen: Dictionary = world.get("countries_seen")
	var here := String(world.terrain.data.get("country", ""))
	for id: String in _atlas_names:
		var spot: Dictionary = _atlas_names[id]
		var at := pic.position + Vector2(float(spot["x"]), float(spot["y"])) * pic.size
		var known := seen.has(id)
		var label := String(world.call("country_title", id)) if known else "?"
		if id == here:
			draw_arc(at, 13.0, 0.0, TAU, 24, Color(0.62, 0.1, 0.08), 2.5, true)
		draw_string(Style.font(), at + Vector2(-80.0, 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, 160.0, 12 if known else 15, Color(0.12, 0.08, 0.05) if known else Color(0.12, 0.08, 0.05, 0.6))
	Style.text(self, Vector2(pic.position.x, pic.end.y + 24.0), "Ringed: where you are", 11, Style.FADED, HORIZONTAL_ALIGNMENT_CENTER, w)


# The little drawing that stands for a kind of place. Faint until the player has been there.
func _sign(kind: String, at: Vector2, known: bool, hard: bool = false) -> void:
	var ink := Color(INKED, 1.0 if known else 0.45)
	if kind == "crossing":  # (polish1 F1a) a border crossing: a gate, red when it leads into hard country
		var gate := Color(0.55, 0.1, 0.08) if hard else INKED
		draw_rect(Rect2(at + Vector2(-7, -6), Vector2(2.5, 11)), gate)
		draw_rect(Rect2(at + Vector2(4.5, -6), Vector2(2.5, 11)), gate)
		draw_arc(at + Vector2(0, -5), 6.0, PI, TAU, 10, gate, 2.0, true)
		return
	if kind.begins_with("town"):
		draw_rect(Rect2(at + Vector2(-6, -3), Vector2(12, 8)), ink)
		draw_colored_polygon(PackedVector2Array([at + Vector2(-8, -3), at + Vector2(0, -10), at + Vector2(8, -3)]), ink)
		draw_rect(Rect2(at + Vector2(-1.5, 0), Vector2(3, 5)), PAPER)
	elif kind in ["village", "farm"]:
		draw_rect(Rect2(at + Vector2(-4, -2), Vector2(8, 6)), ink)
		draw_colored_polygon(PackedVector2Array([at + Vector2(-6, -2), at + Vector2(0, -7), at + Vector2(6, -2)]), ink)
	elif kind == "arena":
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(7, 0), at + Vector2(0, 8), at + Vector2(-7, 0)]), Color(0.5, 0.1, 0.08, ink.a))
		draw_polyline(PackedVector2Array([at + Vector2(0, -8), at + Vector2(7, 0), at + Vector2(0, 8), at + Vector2(-7, 0), at + Vector2(0, -8)]), ink, 1.2, true)
	elif kind.begins_with("tribe") or kind == "camp":
		var cloth := ink
		if kind == "tribe_red":
			cloth = Color(0.6, 0.16, 0.12, ink.a)
		elif kind == "tribe_blue":
			cloth = Color(0.15, 0.28, 0.55, ink.a)
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(7, 5), at + Vector2(-7, 5)]), cloth)
		draw_line(at + Vector2(0, -8), at + Vector2(0, 5), PAPER, 1.0)
	elif kind == "course":  # an Agility course: a pole with a pennant
		draw_line(at + Vector2(-3, 6), at + Vector2(-3, -8), ink, 1.5)
		draw_colored_polygon(PackedVector2Array([at + Vector2(-3, -8), at + Vector2(6, -5), at + Vector2(-3, -2)]), Color(0.75, 0.25, 0.15, ink.a))
	elif kind == "battlefield":
		draw_line(at + Vector2(-6, -6), at + Vector2(6, 6), ink, 2.0)
		draw_line(at + Vector2(6, -6), at + Vector2(-6, 6), ink, 2.0)
	else:  # ruins and anything else: three stones
		for offset: Vector2 in [Vector2(-5, 3), Vector2(0, -4), Vector2(5, 3)]:
			draw_rect(Rect2(at + offset - Vector2(2, 2), Vector2(4, 4)), ink)
