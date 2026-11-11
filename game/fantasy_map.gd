# Purpose: the world map of the fantasy world (key M): the whole country drawn like an inked chart on parchment, with
# the sea, lakes, hills, roads, every place the player has found by name (others are unnamed dots), region names with
# their levels, quest marks, the player's arrow and the rest of the party. Walking stays possible while it is open.
# The chart itself is painted once from the terrain rules on a background thread when the world is first built.
# Dependencies: game/fantasy_world.gd (terrain, found places, map_marks, player_local), game/fantasy_spawner.gd
# (bodies), game/fantasy_style.gd, game/input_setup.gd.
extends Control

const Style = preload("res://game/fantasy_style.gd")
const InputSetup = preload("res://game/input_setup.gd")

const PIXELS := 320  # the chart is this many dots a side
const PAPER := Color(0.87, 0.8, 0.64)
const INKED := Color(0.2, 0.15, 0.1)
const SEA := Color(0.56, 0.66, 0.68)

var world: Node3D
var settings: RefCounted

var _chart: ImageTexture
var _task := -1
var _image: Image


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_task = WorkerThreadPool.add_task(_paint)  # the terrain rules are pure: safe to read from another thread


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
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_chart = ImageTexture.create_from_image(_image)
	if visible:
		queue_redraw()


# Runs on a worker thread: one dot per patch of land, coloured from the land's own palette, shaded by its slope.
func _paint() -> void:
	var terrain: RefCounted = world.terrain
	var half := float(terrain.size) * 0.5
	var step := float(terrain.size) / float(PIXELS)
	var image := Image.create(PIXELS, PIXELS, false, Image.FORMAT_RGB8)
	for py in PIXELS:
		var z := -half + (float(py) + 0.5) * step
		var west := float(terrain.height(-half, z))
		for px in PIXELS:
			var x := -half + (float(px) + 0.5) * step
			var h := float(terrain.height(x, z))
			var water := String(terrain.water_at(x, z))
			var color: Color
			if water != "":
				color = SEA.darkened(clampf((float(terrain.sea) - h) * 0.03, 0.0, 0.25)) if water != "lava" else Color(0.8, 0.4, 0.2)
			else:
				var land: Color = terrain.color(x, z, h, 0.0)
				var light := clampf((h - west) / step * 0.35, -0.16, 0.14)  # lit from the west: slopes show as soft relief
				color = PAPER.lerp(land, 0.5) * (0.96 + light)
				if h - float(terrain.sea) < 0.6:
					color = color.lerp(INKED, 0.35)  # the shoreline is inked
			image.set_pixel(px, py, color)
			west = h
	_image = image


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
	var font := Style.font()
	# roads: dotted ink between the places they join
	for road: PackedVector2Array in terrain.roads:  # each road is a bent line of three points
		for i in road.size() - 1:
			draw_dashed_line(_spot(road[i].x, road[i].y, sheet), _spot(road[i + 1].x, road[i + 1].y, sheet), Color(INKED, 0.55), 1.5, 5.0)
	# regions: a spaced name and the levels found there
	for region: Dictionary in terrain.regions:
		var at := _spot(float(region["center"][0]), float(region["center"][1]), sheet)
		var known: bool = (world.get("found") as Dictionary).has(String(region["id"]))
		var title := String(region["name"]).to_upper() if known else "?  ?  ?"
		draw_string(font, at + Vector2(-150.0, -26.0), title, HORIZONTAL_ALIGNMENT_CENTER, 300.0, 17, Color(INKED, 0.7))
		draw_string(font, at + Vector2(-150.0, -10.0), "levels %d - %d" % [int(region["level"][0]), int(region["level"][1])], HORIZONTAL_ALIGNMENT_CENTER, 300.0, 11, Color(INKED, 0.55))
	for lake: Dictionary in terrain.lakes:
		draw_string(font, _spot(float(lake["x"]), float(lake["z"]) + float(lake["r"]) + 14.0, sheet) + Vector2(-80.0, 0.0), String(lake["name"]), HORIZONTAL_ALIGNMENT_CENTER, 160.0, 10, Color(0.16, 0.26, 0.36, 0.85))
	# places: a sign by kind; the name once found
	for place: Dictionary in terrain.places:
		var at := _spot(float(place["pos"][0]), float(place["pos"][1]), sheet)
		var known: bool = (world.get("found") as Dictionary).has(String(place["id"]))
		_sign(String(place["kind"]), at, known)
		if known:
			draw_string(font, at + Vector2(-90.0, 17.0), String(place["name"]), HORIZONTAL_ALIGNMENT_CENTER, 180.0, 12, INKED)
	# quests
	for mark: Dictionary in world.call("map_marks"):
		var at := _spot(float(mark["x"]), float(mark["z"]), sheet) + Vector2(9.0, -6.0)
		draw_circle(at, 7.5, Color(0.55, 0.12, 0.1))
		draw_string(font, at + Vector2(-8.0, 5.0), String(mark["mark"]), HORIZONTAL_ALIGNMENT_CENTER, 16.0, 13, Style.PARCHMENT)
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
	Style.text(self, Vector2(sheet.position.x, sheet.position.y - 22.0), String(terrain.data["name"]), 24, Style.GOLD, HORIZONTAL_ALIGNMENT_CENTER, side)
	Style.text(self, Vector2(sheet.position.x, sheet.end.y + 30.0), "%s  close the map" % InputSetup.label(settings, "map"), 12, Style.FADED, HORIZONTAL_ALIGNMENT_CENTER, side)
	var rose := sheet.position + Vector2(side - 34.0, 40.0)
	draw_line(rose + Vector2(0, 16), rose + Vector2(0, -16), INKED, 1.5)
	draw_line(rose + Vector2(-10, 0), rose + Vector2(10, 0), INKED, 1.0)
	draw_colored_polygon(PackedVector2Array([rose + Vector2(0, -22), rose + Vector2(4, -12), rose + Vector2(-4, -12)]), INKED)
	draw_string(font, rose + Vector2(-10.0, -25.0), "N", HORIZONTAL_ALIGNMENT_CENTER, 20.0, 12, INKED)


# The little drawing that stands for a kind of place. Faint until the player has been there.
func _sign(kind: String, at: Vector2, known: bool) -> void:
	var ink := Color(INKED, 1.0 if known else 0.45)
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
	elif kind == "battlefield":
		draw_line(at + Vector2(-6, -6), at + Vector2(6, 6), ink, 2.0)
		draw_line(at + Vector2(6, -6), at + Vector2(-6, 6), ink, 2.0)
	else:  # ruins and anything else: three stones
		for offset: Vector2 in [Vector2(-5, 3), Vector2(0, -4), Vector2(5, 3)]:
			draw_rect(Rect2(at + offset - Vector2(2, 2), Vector2(4, 4)), ink)
