# Purpose: the helm panel shown while steering a ship (sea step 5a), real game UI (game/ui_skin.gd): a compass with
# the ship pointing up and the wind's arrow round it, the sail stages as pills (the one set lit), the point of sail
# with the share of the wind the heading gets, the speed in knots, the rudder, the anchor warning and the keys.
# Dependencies: game/ui_skin.gd, core/sea/ship_rules.gd (passed in).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const ShipRules = preload("res://core/sea/ship_rules.gd")

const SIZE := Vector2(560, 150)
const KNOTS := 1.944

var _font: Font = ThemeDB.fallback_font
var _state: Dictionary
var _spec: Dictionary
var _rules: ShipRules
var _wind := 0.0
var _wind_dir := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_ship(state: Dictionary, spec: Dictionary, rules: ShipRules, wind: float, wind_dir: float) -> void:
	_state = state
	_spec = spec
	_rules = rules
	_wind = wind
	_wind_dir = wind_dir
	queue_redraw()


func _draw() -> void:
	if _state.is_empty():
		return
	var view := get_viewport_rect().size
	var r := Rect2(Vector2((view.x - SIZE.x) * 0.5, view.y - SIZE.y - 80.0), SIZE)
	UiSkin.panel(self, r)
	# the compass: the ship points up, the wind's arrow shows where it blows to
	var c := r.position + Vector2(78, 75)
	draw_circle(c, 56.0, Color(1, 1, 1, 0.05))
	draw_arc(c, 56.0, 0.0, TAU, 48, Color(1, 1, 1, 0.22), 2.0, true)
	for k in 8:
		var a := k * TAU / 8.0
		draw_line(c + Vector2.from_angle(a) * 50.0, c + Vector2.from_angle(a) * 56.0, Color(1, 1, 1, 0.3), 1.5)
	var hull := PackedVector2Array([c + Vector2(0, -26), c + Vector2(9, -6), c + Vector2(8, 20), c + Vector2(-8, 20), c + Vector2(-9, -6)])
	draw_colored_polygon(hull, Color(0.82, 0.66, 0.42))
	var yaw := float(_state["yaw"])
	var to := Basis(Vector3.UP, yaw).inverse() * Vector3(cos(_wind_dir), 0.0, sin(_wind_dir))  # ship space: -z ahead = up
	var dir := Vector2(to.x, to.z).normalized()
	var tail := c - dir * 44.0
	var head := c + dir * 44.0
	var wind_col := Color(0.55, 0.85, 1.0)
	draw_line(tail, head, wind_col, 3.0, true)
	draw_colored_polygon(PackedVector2Array([head, head - dir * 13.0 + dir.orthogonal() * 7.0, head - dir * 13.0 - dir.orthogonal() * 7.0]), wind_col)
	draw_string(_font, c + Vector2(-56, 74), "WIND %d%%" % roundi(_wind * 100.0), HORIZONTAL_ALIGNMENT_CENTER, 112, 12, UiSkin.TEXT_DIM)
	# name, stages, point of sail
	var x := r.position.x + 160.0
	draw_string(_font, Vector2(x, r.position.y + 30), String(_spec["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiSkin.ACCENT)
	var speed := float(_state["speed"]) * KNOTS
	_right(Vector2(r.end.x - 20, r.position.y + 30), "%.1f kn" % speed, 20, UiSkin.TEXT)
	var stages: Array = _rules.cfg["stages"]
	var px := x
	for i in stages.size():
		var label := String(stages[i]["name"])
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18.0
		UiSkin.pill(self, _font, Rect2(Vector2(px, r.position.y + 42), Vector2(w, 24)), label, i == int(_state["stage"]), false, 13)
		px += w + 6.0
	var off := ShipRules.off_wind(yaw, _wind_dir)
	var share := _rules.wind_share(off)
	var sail := float(_rules.stage(_state)["sail"]) > 0.0
	var line := "%s  -  %d%% of the wind" % [ShipRules.point_of_sail(off), roundi(share * 100.0)] if sail else "Rowing" if float(_rules.stage(_state)["oars"]) != 0.0 else "Sails furled"
	draw_string(_font, Vector2(x, r.position.y + 90), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.GOOD if share > 0.6 or not sail else (UiSkin.TEXT if share > 0.2 else UiSkin.BAD))
	if bool(_state["anchored"]):
		_right(Vector2(r.end.x - 20, r.position.y + 90), "ANCHORED: weigh it at the bow", 14, UiSkin.BAD)
	# rudder
	var bar := Rect2(Vector2(x, r.position.y + 102), Vector2(r.end.x - x - 20.0, 6))
	UiSkin.bar(self, bar, 0.0, UiSkin.ACCENT)
	var mid := bar.position.x + bar.size.x * 0.5
	draw_line(Vector2(mid, bar.position.y - 3), Vector2(mid, bar.end.y + 3), Color(1, 1, 1, 0.35), 1.0)
	var at := mid + float(_state["rudder"]) * bar.size.x * 0.5
	draw_rect(Rect2(Vector2(minf(mid, at), bar.position.y), Vector2(absf(at - mid), bar.size.y)), UiSkin.ACCENT)
	# keys
	var kx := x
	var ky := r.position.y + 118.0
	for pair: Array in [["W/S", "Sails"], ["A/D", "Rudder"], ["F", "Let go"]]:
		kx += UiSkin.key_cap(self, _font, Vector2(kx, ky), String(pair[0])) + 6.0
		draw_string(_font, Vector2(kx, ky + 15), String(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
		kx += _font.get_string_size(String(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 18.0


func _right(at: Vector2, text: String, size_px: int, colour: Color) -> void:
	draw_string(_font, at - Vector2(_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, colour)
