# Purpose: the binder's INSPECT view (polish1 item 82): a clicked card big in the middle of the screen to play with:
# drag left / right to spin it round (its back shows past the edge), drag up / down to tip it, the wheel zooms; it
# drifts back upright when let go. Pills under it switch between every version owned (Plain, Rainbow, Pony, with how
# many) to compare their foils. Esc, the Close pill or a click beside the card closes it. Real game UI (game/ui_skin.gd).
# Dependencies: game/tcg/card_face.gd (the face and its foil shine), game/ui_skin.gd; db (core/tcg/card_db.gd) and owned
# (core/tcg/collection.gd) handed in by open().
extends Control

const CardFace = preload("res://game/tcg/card_face.gd")
const UiSkin = preload("res://game/ui_skin.gd")

const CARD := Vector2(330, 462)
const FINISHES := ["", "rainbow", "pony"]
const NAMES := {"": "Plain", "rainbow": "Rainbow", "pony": "Pony"}

var _face: Control
var _db: RefCounted
var _owned: RefCounted
var _id := ""
var _leader := false
var _finish := ""
var _spin := 0.0  # radians round the upright axis
var _tip := 0.0  # radians forward / back (drawn as a slant)
var _zoom := 1.0
var _dragging := false
var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_face = CardFace.new()
	add_child(_face)
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face.size = CARD
	_face.pivot_offset = CARD * 0.5
	set_process(false)


func open(card_db: RefCounted, collection: RefCounted, id: String, leader: bool) -> void:
	_db = card_db
	_owned = collection
	_id = id
	_leader = leader
	_spin = 0.0
	_tip = 0.0
	_zoom = 1.0
	_finish = ""
	for f: String in ["pony", "rainbow", ""]:  # start on the finest version owned
		if int(_owned.call("count", id, f, leader)) > 0:
			_finish = f
			break
	_face.show_card(_db, _id)
	_face.call("set_finish", _finish)
	visible = true
	set_process(true)


func close() -> void:
	visible = false
	set_process(false)


func _input(event: InputEvent) -> void:  # Esc closes this first, not the whole player card
	if visible and event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(_zoom + 0.08, 1.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(_zoom - 0.08, 0.7)
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			for hit: Array in _hits:
				if (hit[0] as Rect2).has_point(mb.position):
					(hit[1] as Callable).call()
					accept_event()
					return
			if _card_rect().grow(40.0).has_point(mb.position):
				_dragging = true
			else:
				close()
		accept_event()
	elif mb != null and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
	var motion := event as InputEventMouseMotion
	if motion != null:
		_mouse = motion.position
		if _dragging:
			_spin += motion.relative.x * 0.012
			_tip = clampf(_tip + motion.relative.y * 0.006, -0.5, 0.5)


# Checks: "plain" / "rainbow" / "pony" (a version), "spin" (a quarter turn), "close".
func press(key: String) -> bool:
	match key:
		"spin":
			_spin += PI * 0.35
			return true
		"close":
			close()
			return true
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			return true
	return false


func _card_rect() -> Rect2:
	var view := get_viewport_rect().size
	var s := CARD * _zoom
	return Rect2(Vector2(view.x * 0.5, view.y * 0.46) - s * 0.5, s)


func _process(delta: float) -> void:
	if not _dragging:  # drifts back upright, the shortest way round
		var home := roundf(_spin / TAU) * TAU
		_spin = lerpf(_spin, home, minf(delta * 3.0, 1.0))
		_tip = lerpf(_tip, 0.0, minf(delta * 3.0, 1.0))
	var view := get_viewport_rect().size
	var turn := cos(_spin)
	var showing_back := turn < 0.0
	if showing_back != bool(_face.get("back")):
		if showing_back:
			_face.call("show_back")
		else:
			_face.show_card(_db, _id)
	_face.position = Vector2(view.x * 0.5, view.y * 0.46) - CARD * 0.5
	_face.scale = Vector2(maxf(absf(turn), 0.02), 1.0 - absf(_tip) * 0.18) * _zoom
	_face.rotation = _tip * 0.25 * signf(turn)
	queue_redraw()


func _set_finish(f: String) -> void:
	_finish = f
	_face.call("set_finish", f)


func _draw() -> void:
	_hits.clear()
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.02, 0.03, 0.88))
	var title := String((_db.call("card", _id) as Dictionary).get("name", _id)) if not _leader else String((_db.get("leaders") as Dictionary).get(_id, {}).get("name", _id))
	draw_string(_font, Vector2(0, 70), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, view.x, 34, UiSkin.TEXT)
	draw_string(_font, Vector2(0, 100), "drag to turn it - wheel to zoom", HORIZONTAL_ALIGNMENT_CENTER, view.x, 16, UiSkin.TEXT_DIM)
	var y := view.y * 0.46 + CARD.y * 0.5 * 1.12 + 30.0
	var w := 190.0
	var x := view.x * 0.5 - (w * 3.0 + 28.0) * 0.5
	for f: String in FINISHES:
		var have := int(_owned.call("count", _id, f, _leader))
		var r := Rect2(Vector2(x, y), Vector2(w, 46))
		var label := "%s  x%d" % [NAMES[f], have] if have > 0 else "%s  -" % NAMES[f]
		UiSkin.pill(self, _font, r, label, f == _finish and have > 0, r.has_point(_mouse) and have > 0, 18)
		if have > 0:
			_hits.append([r, _set_finish.bind(f), String(NAMES[f]).to_lower()])
		else:
			draw_style_box(UiSkin._box(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), 23, 0), r)
		x += w + 14.0
	var shut := Rect2(Vector2(view.x * 0.5 - 90.0, y + 62.0), Vector2(180, 40))
	UiSkin.pill(self, _font, shut, "Close (Esc)", false, shut.has_point(_mouse), 16)
	_hits.append([shut, close, "close"])
