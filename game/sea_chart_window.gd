# Purpose: the sea chart window (sea step 6, key M at sea), real game UI (game/ui_skin.gd): the whole sea as a grid
# of squares A1..I9 tinted by region, the fog of war over the water not yet sailed, islands seen (named and ticked once
# explored), squares completed (gold corner), secret marks from charts in the bag, pins (left click sets / removes
# one), the fleet's ships, the party and the player's arrow. Beside it: the square under the mouse (or the player),
# totals, and the tracker of unfinished squares.
# Dependencies: game/ui_skin.gd, core/sea/sea_chart.gd + game/sea_world.gd (set by the sea world: chart, map,
# writing names, secrets, positions).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")

var chart: RefCounted  # core/sea/sea_chart.gd
var sea: Node3D  # game/sea_world.gd
var names := {}  # island id -> name (data/sea/writing/chart.txt)
var secret_words := {}  # secret id -> [title, line]
var _font: Font = ThemeDB.fallback_font
var _fog_tex: ImageTexture
var _fog_img: Image
var _area := Rect2()
var _hover := Vector2i(-1, -1)
var _slow := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	visible = true
	_refresh_fog(true)
	queue_redraw()


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_slow -= delta
	if _slow <= 0.0:
		_slow = 0.25
		_refresh_fog(false)
		queue_redraw()


func _refresh_fog(force: bool) -> void:
	if chart == null or (not force and not bool(chart.get("changed"))):
		return
	chart.set("changed", false)
	var w := int(chart.get("fog_w"))
	var h := int(chart.get("fog_h"))
	if _fog_img == null or _fog_img.get_width() != w:
		_fog_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	var veil := Color(0.1, 0.12, 0.16, 0.8)
	for z in h:
		for x in w:
			_fog_img.set_pixel(x, z, Color(0, 0, 0, 0) if chart.call("cleared", x, z) else veil)
	if _fog_tex == null:
		_fog_tex = ImageTexture.create_from_image(_fog_img)
	else:
		_fog_tex.update(_fog_img)


# Sea position (x, z) -> a point on the chart.
func _to_chart(p: Vector2) -> Vector2:
	var w := float(chart.get("width"))
	var h := float(chart.get("height"))
	return _area.position + Vector2((p.x + w * 0.5) / w * _area.size.x, (p.y + h * 0.5) / h * _area.size.y)


func _to_sea(at: Vector2) -> Vector2:
	var w := float(chart.get("width"))
	var h := float(chart.get("height"))
	return Vector2((at.x - _area.position.x) / _area.size.x * w - w * 0.5, (at.y - _area.position.y) / _area.size.y * h - h * 0.5)


func _gui_input(event: InputEvent) -> void:
	if chart == null:
		return
	if event is InputEventMouseMotion:
		var at := (event as InputEventMouseMotion).position
		var sea_at := _to_sea(at)
		_hover = chart.call("square_of", sea_at.x, sea_at.y) if _area.has_point(at) else Vector2i(-1, -1)
		queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var at := (event as InputEventMouseButton).position
		if _area.has_point(at):
			chart.call("toggle_pin", _to_sea(at))
			queue_redraw()
		accept_event()


func _draw() -> void:
	if chart == null or sea == null:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.55))
	var side := minf(view.y - 120.0, view.x - 460.0)
	var whole := Rect2(Vector2((view.x - side - 380.0) * 0.5, (view.y - side) * 0.5 - 10.0) - Vector2(24, 52), Vector2(side + 380.0 + 48.0, side + 84.0))
	UiSkin.panel(self, whole)
	draw_string(_font, whole.position + Vector2(24, 38), "SEA CHART", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, UiSkin.TEXT)
	_area = Rect2(whole.position + Vector2(40, 64), Vector2(side, side))
	var cols := int(chart.get("cols"))
	var rows := int(chart.get("rows"))
	var cell := Vector2(_area.size.x / cols, _area.size.y / rows)
	var map: RefCounted = sea.get("map")
	for r in rows:  # the squares, tinted by their region's sea
		for c in cols:
			var sq := Vector2i(c, r)
			var rect := Rect2(_area.position + Vector2(c, r) * cell, cell)
			var middle: Rect2 = chart.call("square_rect", sq)
			var region: Dictionary = map.call("region_at", middle.get_center().x, middle.get_center().y)
			var tint: Array = region.get("sea", [0.12, 0.5, 0.6])
			draw_rect(rect, Color(float(tint[0]), float(tint[1]), float(tint[2])).lerp(Color(0.85, 0.8, 0.66), 0.35))
	if _fog_tex != null:
		draw_texture_rect(_fog_tex, _area, false)
	for i in range(cols + 1):  # grid lines (region borders heavier), letters and numbers
		var heavy := i % 3 == 0
		draw_line(_area.position + Vector2(i * cell.x, 0), _area.position + Vector2(i * cell.x, _area.size.y), Color(0.95, 0.9, 0.75, 0.55 if heavy else 0.2), 2.0 if heavy else 1.0)
		if i < cols:
			draw_string(_font, _area.position + Vector2((i + 0.5) * cell.x - 5.0, -6.0), char(65 + i), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
	for i in range(rows + 1):
		var heavy := i % 3 == 0
		draw_line(_area.position + Vector2(0, i * cell.y), _area.position + Vector2(_area.size.x, i * cell.y), Color(0.95, 0.9, 0.75, 0.55 if heavy else 0.2), 2.0 if heavy else 1.0)
		if i < rows:
			draw_string(_font, _area.position + Vector2(-22.0, (i + 0.5) * cell.y + 5.0), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
	for r in rows:  # completed squares: a gold corner
		for c in cols:
			if chart.call("complete", Vector2i(c, r)):
				var corner := _area.position + Vector2(c + 1, r) * cell
				draw_colored_polygon(PackedVector2Array([corner, corner + Vector2(-14, 0), corner + Vector2(0, 14)]), UiSkin.ACCENT)
	var per_m := _area.size.x / float(chart.get("width"))
	var explored: Dictionary = chart.get("explored")
	for island: Dictionary in chart.get("islands"):  # islands seen: a shape, named + ticked when explored
		var p: Vector2 = island["pos"]
		if not explored.has(island["id"]) and not bool(chart.call("cleared_at", p.x, p.y)):
			continue
		var at := _to_chart(p)
		var radius := maxf(float(island["radius"]) * per_m, 3.0)
		draw_circle(at, radius, Color(0.62, 0.55, 0.36))
		draw_arc(at, radius, 0.0, TAU, 24, Color(0.25, 0.2, 0.12), 1.5, true)
		if explored.has(island["id"]):
			draw_string(_font, at + Vector2(radius + 4.0, 4.0), String(names.get(island["id"], island["id"])), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiSkin.TEXT)
		else:
			draw_string(_font, at + Vector2(radius + 3.0, 4.0), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	for mark: Dictionary in sea.call("chart_secrets"):  # charts in the bag: a red X with its title
		var at := _to_chart(Vector2(float(mark["at"][0]), float(mark["at"][1])))
		draw_line(at + Vector2(-6, -6), at + Vector2(6, 6), UiSkin.BAD, 3.0)
		draw_line(at + Vector2(-6, 6), at + Vector2(6, -6), UiSkin.BAD, 3.0)
		draw_string(_font, at + Vector2(9.0, -6.0), String((secret_words.get(mark["id"], [mark["id"]]) as Array)[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiSkin.BAD)
	for ship: Node3D in sea.get("ships").get("ships"):  # the fleet where its water is charted
		var s: Dictionary = ship.get("state")
		if bool(chart.call("cleared_at", float(s["x"]), float(s["z"]))):
			_boat(_to_chart(Vector2(float(s["x"]), float(s["z"]))), float(s["yaw"]), Color(0.95, 0.9, 0.8))
	for pin: Vector2 in chart.get("pins"):
		var at := _to_chart(pin)
		draw_circle(at + Vector2(0, -10), 5.0, UiSkin.BAD)
		draw_line(at + Vector2(0, -6), at, UiSkin.BAD, 2.0)
	for other: Vector3 in sea.call("party_on_chart"):  # teammates at sea
		draw_circle(_to_chart(Vector2(other.x, other.z)), 4.5, Color(0.5, 0.85, 1.0))
	var me: Vector3 = sea.call("local_of", (sea.get("_player") as Node3D).global_position)
	var cam := get_viewport().get_camera_3d()
	var yaw := cam.global_rotation.y if cam != null else 0.0
	_arrow(_to_chart(Vector2(me.x, me.z)), yaw)
	_side(Rect2(Vector2(_area.end.x + 30.0, _area.position.y), Vector2(340.0, _area.size.y)), me)


func _arrow(at: Vector2, yaw: float) -> void:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([at + fwd * 11.0, at - fwd * 7.0 + right * 7.0, at - fwd * 3.0, at - fwd * 7.0 - right * 7.0]), Color(1.0, 0.85, 0.3))


func _boat(at: Vector2, yaw: float, colour: Color) -> void:
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var right := Vector2(-fwd.y, fwd.x)
	draw_colored_polygon(PackedVector2Array([at + fwd * 7.0, at + right * 3.0, at - fwd * 6.0 + right * 3.0, at - fwd * 6.0 - right * 3.0, at - right * 3.0]), colour)


func _side(r: Rect2, me: Vector3) -> void:
	var sq: Vector2i = _hover if _hover.x >= 0 else chart.call("square_of", me.x, me.z)
	var middle: Rect2 = chart.call("square_rect", sq)
	var region: Dictionary = sea.get("map").call("region_at", middle.get_center().x, middle.get_center().y)
	var y := UiSkin.header(self, _font, r.position, r.size.x, "SQUARE %s" % String(chart.call("square_name", sq)), String(region.get("name", "")))
	var prog: Vector2i = chart.call("progress", sq)
	var line := ("Islands explored %d / %d" % [prog.x, prog.y]) if prog.y > 0 else ("Open sea, %d%% charted" % roundi(float(chart.call("cleared_share", sq)) * 100.0))
	draw_string(_font, Vector2(r.position.x, y + 18.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT)
	draw_string(_font, Vector2(r.position.x, y + 40.0), "COMPLETE" if bool(chart.call("complete", sq)) else "Not complete", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.GOOD if bool(chart.call("complete", sq)) else UiSkin.TEXT_DIM)
	y += 70.0
	var total := int(chart.get("cols")) * int(chart.get("rows"))
	y = UiSkin.header(self, _font, Vector2(r.position.x, y), r.size.x, "THE SEA", "%d / %d squares complete" % [int(chart.call("complete_count")), total])
	var explored: Dictionary = chart.get("explored")
	draw_string(_font, Vector2(r.position.x, y + 18.0), "Islands explored %d / %d" % [explored.size(), (chart.get("islands") as Array).size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT)
	y += 44.0
	y = UiSkin.header(self, _font, Vector2(r.position.x, y), r.size.x, "UNFINISHED", "")
	var left: Array = chart.call("unfinished")
	for i in mini(left.size(), 9):
		var u: Vector2i = left[i]
		var p: Vector2i = chart.call("progress", u)
		var say := "%s   islands %d / %d" % [String(chart.call("square_name", u)), p.x, p.y] if p.y > 0 else "%s   open sea %d%%" % [String(chart.call("square_name", u)), roundi(float(chart.call("cleared_share", u)) * 100.0)]
		draw_string(_font, Vector2(r.position.x + 6.0, y + 18.0 + i * 20.0), say, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
	if left.is_empty():
		draw_string(_font, Vector2(r.position.x + 6.0, y + 18.0), "Nothing half-done.", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
	var ky := r.end.y - 30.0
	var kx := r.position.x
	for pair: Array in [["M", "Close"], ["Left Mouse", "Pin / unpin"]]:
		kx += UiSkin.key_cap(self, _font, Vector2(kx, ky), String(pair[0])) + 6.0
		draw_string(_font, Vector2(kx, ky + 15), String(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
		kx += _font.get_string_size(String(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18.0
