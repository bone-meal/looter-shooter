# Purpose: the TROPHIES tab of the player card (polish1 E4, items 131 / 133): every boss trophy, ghost trophy and
# spectral piece as a card (owned ones bright, the rest dark with who gives them), the worn ones marked, the four body
# spots (head, back, arms, legs) and what is on each; pick one and the right side shows its text with WEAR IT /
# TAKE IT OFF. Real game UI (game/ui_skin.gd). Draws and asks only: the session puts the piece on.
# Dependencies: game/ui_skin.gd, core/boss_trophy_locker.gd (set `locker`), boss names (set `boss_name`).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")

signal wear_requested(id: String)  # puts the piece on, or takes it off when it is worn

const CARD := Vector2(262, 86)
const FILTERS := [["all", "All"], ["boss", "Bosses"], ["ghost", "Ghosts"], ["spectral", "Spectral set"]]
const BLUE := Color(0.55, 0.78, 1.0)

var locker: RefCounted
var boss_name := Callable()  # func(boss id) -> its name

var _filter := "all"
var _picked := ""
var _scroll := 0.0
var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font
var _names := {}  # boss id -> its name


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func refresh() -> void:
	queue_redraw()


# Checks: "filter <id>", "pick <trophy id>", "wear".
func press(key: String) -> bool:
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			queue_redraw()
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		queue_redraw()
	var b := event as InputEventMouseButton
	if b != null and b.pressed:
		if b.button_index == MOUSE_BUTTON_WHEEL_UP or b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = maxf(_scroll + (-60.0 if b.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0), 0.0)
			accept_event()
			queue_redraw()
		elif b.button_index == MOUSE_BUTTON_LEFT:
			for hit: Array in _hits:
				if (hit[0] as Rect2).has_point(b.position):
					(hit[1] as Callable).call()
					break
			accept_event()
			queue_redraw()


func _db() -> RefCounted:
	return locker.get("db")


func _kind(id: String) -> String:
	var d: Dictionary = _db().call("def", id)
	if d.has("set"):
		return "spectral"
	return "ghost" if d.has("phantom") else "boss"


# Who gives a piece, in words.
func _source(id: String) -> String:
	var d: Dictionary = _db().call("def", id)
	if d.has("boss"):
		return "Defeat %s" % _name_of_boss(String(d["boss"]))
	if d.has("phantom"):
		return "Rare: its echo, %s" % _name_of_boss(String(d["phantom"]))
	return "Rare: any great creature's echo"


func _name_of_boss(id: String) -> String:
	if not _names.has(id):  # asked once per boss
		var called := String(boss_name.call(id)) if boss_name.is_valid() else id
		_names[id] = ("the " + called.substr(4)) if called.begins_with("The ") else called  # in the middle of a line
	return String(_names[id])


func _shown() -> Array:
	var out: Array = []
	for id: String in _db().call("ids"):
		if _filter == "all" or _kind(id) == _filter:
			out.append(id)
	return out


func _draw() -> void:
	_hits.clear()
	if locker == null:
		return
	var left_w := size.x * 0.6
	var x := 20.0
	for f: Array in FILTERS:
		var w := _font.get_string_size(String(f[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 28.0
		var r := Rect2(Vector2(x, 14), Vector2(w, 30))
		UiSkin.pill(self, _font, r, String(f[1]), _filter == String(f[0]), r.has_point(_mouse), 14)
		var id := String(f[0])
		_hits.append([r, func() -> void: _filter = id; _scroll = 0.0, "filter " + id])
		x += w + 8.0
	var all: Array = _db().call("ids")
	draw_string(_font, Vector2(20, 66), "YOUR TROPHIES  %d / %d  -  worn over any outfit, others see them everywhere" % [(locker.call("order") as Array).size(), all.size()], HORIZONTAL_ALIGNMENT_LEFT, left_w, 15, UiSkin.TEXT_DIM)
	var area := Rect2(Vector2(20, 80), Vector2(left_w - 20.0, size.y - 96.0))
	var cols := maxi(int(area.size.x / (CARD.x + 12.0)), 1)
	var shown := _shown()
	for n in shown.size():
		var id: String = shown[n]
		var mine := bool(locker.call("has", id))
		var r := Rect2(area.position + Vector2(float(n % cols) * (CARD.x + 12.0), float(floori(float(n) / float(cols))) * (CARD.y + 12.0) - _scroll), CARD)
		if r.end.y < area.position.y or r.position.y > area.end.y:
			continue
		var ghostly := bool(_db().call("is_ghost", id))
		var edge := BLUE if ghostly else UiSkin.ACCENT
		UiSkin.panel(self, r, Color(0.07, 0.07, 0.1, 0.97), Color(edge, 0.95 if id == _picked or r.has_point(_mouse) else 0.35), 10)
		draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 26.0), String(_db().call("name_of", id)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 15, (BLUE if ghostly else UiSkin.TEXT) if mine else UiSkin.TEXT_DIM)
		draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 46.0), " + ".join(_db().call("spots_of", id)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 11, UiSkin.TEXT_DIM)
		var sub := "WORN" if bool(locker.call("is_worn", id)) else ("owned" if mine else _source(id))
		draw_string(_font, Vector2(r.position.x + 10.0, r.end.y - 14.0), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 12, UiSkin.GOOD if sub == "WORN" else UiSkin.TEXT_DIM)
		_hits.append([r, func() -> void: _picked = id if _picked != id else "", "pick " + id])
	_detail(Rect2(Vector2(left_w + 10.0, 14), Vector2(size.x - left_w - 30.0, size.y - 28.0)))


func _detail(area: Rect2) -> void:
	UiSkin.panel(self, area, Color(0.05, 0.05, 0.08, 0.95), UiSkin.EDGE, 12)
	var x := area.position.x + 18.0
	var w := area.size.x - 36.0
	var y := area.position.y + 30.0
	draw_string(_font, Vector2(x, y), "WORN NOW", HORIZONTAL_ALIGNMENT_LEFT, w, 13, UiSkin.TEXT_DIM)
	for spot: Variant in _db().get("spots"):
		y += 20.0
		var on := "-"
		for id: String in locker.get("worn"):
			if (_db().call("spots_of", id) as Array).has(spot):
				on = String(_db().call("name_of", id))
		draw_string(_font, Vector2(x, y), "%s:  %s" % [String(spot).capitalize(), on], HORIZONTAL_ALIGNMENT_LEFT, w, 14, UiSkin.TEXT if on != "-" else UiSkin.TEXT_DIM)
	y += 40.0
	if _picked == "":
		draw_string(_font, Vector2(area.position.x, y + 40.0), "Pick a trophy.", HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 17, UiSkin.TEXT_DIM)
		return
	var d: Dictionary = _db().call("def", _picked)
	var mine := bool(locker.call("has", _picked))
	draw_string(_font, Vector2(x, y), String(d.get("name", _picked)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w, 22, BLUE if bool(_db().call("is_ghost", _picked)) else UiSkin.ACCENT)
	y += 22.0
	draw_string(_font, Vector2(x, y), _source(_picked), HORIZONTAL_ALIGNMENT_LEFT, w, 13, UiSkin.TEXT_DIM)
	draw_multiline_string(_font, Vector2(x, y + 26.0), String(d.get("about", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 14, 5, UiSkin.TEXT)
	if not mine:
		return
	var on := bool(locker.call("is_worn", _picked))
	var wear_r := Rect2(Vector2(x, area.end.y - 60.0), Vector2(w, 44))
	UiSkin.pill(self, _font, wear_r, "TAKE IT OFF" if on else "WEAR IT", on, wear_r.has_point(_mouse), 17)
	var id := _picked
	_hits.append([wear_r, func() -> void: wear_requested.emit(id), "wear"])
