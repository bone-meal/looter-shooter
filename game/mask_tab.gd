# Purpose: the MASKS tab of the player card (polish1 D5c, diary/DECISIONS_SKINS.md): filter pills by where masks come
# from (all / boss / elite / loot / playtime / achievement), every mask of that kind as a card with its picture (owned
# ones in full, the rest dark with how to get them), the worn one marked; pick one and the right side shows it large
# with its text and copies, WEAR IT / TAKE IT OFF. Real game UI (game/ui_skin.gd). Draws and asks only: the session
# puts the mask on.
# Dependencies: game/ui_skin.gd, game/camo_icons.gd (mask pictures), core/mask_locker.gd (set `locker`).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const CamoIcons = preload("res://game/camo_icons.gd")

signal wear_requested(id: String)  # "" = take the mask off

const CARD := Vector2(200, 168)
const FILTERS := [["all", "All"], ["boss", "Boss"], ["elite", "Elite"], ["loot", "Loot"], ["playtime", "Playtime"], ["achievement", "Achievements"]]
const SOURCE_TEXT := {"boss": "dropped by bosses", "elite": "dropped by elites and mobs", "loot": "found in the world", "playtime": "earned by time played", "achievement": "earned by an achievement"}

var locker: RefCounted

var _filter := "all"
var _picked := ""
var _scroll := 0.0
var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func refresh() -> void:
	queue_redraw()


# Checks: "filter <id>", "pick <mask id>", "wear", "off".
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


func _set_filter(id: String) -> void:
	_filter = id
	_scroll = 0.0


func _db() -> RefCounted:
	return locker.get("db")


func _shown() -> Array:
	var out: Array = []
	for id: String in _db().call("ids"):
		if _filter == "all" or String((_db().call("mask", id) as Dictionary).get("source", "")) == _filter:
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
		_hits.append([r, _set_filter.bind(id), "filter " + id])
		x += w + 8.0
	var shown := _shown()
	var owned_n := 0
	for id: String in _db().call("ids"):
		if bool(locker.call("has", id)):
			owned_n += 1
	draw_string(_font, Vector2(20, 66), "YOUR MASKS  %d / %d  -  others see the mask you wear, everywhere but Sponde" % [owned_n, (_db().call("ids") as Array).size()], HORIZONTAL_ALIGNMENT_LEFT, left_w, 15, UiSkin.TEXT_DIM)
	var area := Rect2(Vector2(20, 80), Vector2(left_w - 20.0, size.y - 96.0))
	var cols := maxi(int(area.size.x / (CARD.x + 12.0)), 1)
	for n in shown.size():
		var id: String = shown[n]
		var mine := bool(locker.call("has", id))
		var r := Rect2(area.position + Vector2(float(n % cols) * (CARD.x + 12.0), float(floori(float(n) / float(cols))) * (CARD.y + 12.0) - _scroll), CARD)
		if r.end.y < area.position.y or r.position.y > area.end.y:
			continue
		var chosen := id == _picked
		UiSkin.panel(self, r, Color(0.07, 0.07, 0.1, 0.97), Color(UiSkin.ACCENT, 0.95 if chosen or r.has_point(_mouse) else 0.35), 10)
		var pic := CamoIcons.mask(id, self)
		if pic != null:
			draw_texture_rect(pic, Rect2(r.position + Vector2(6, 4), Vector2(r.size.x - 12.0, (r.size.x - 12.0) * 9.0 / 16.0)), false, Color.WHITE if mine else Color(0.12, 0.12, 0.14, 0.9))
		draw_string(_font, Vector2(r.position.x + 10.0, r.end.y - 34.0), String(_db().call("name_of", id)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 15, UiSkin.TEXT if mine else UiSkin.TEXT_DIM)
		var sub := "WORN" if String(locker.get("worn")) == id else ("x%d" % int((locker.get("owned") as Dictionary).get(id, 0)) if mine else "not found yet")
		draw_string(_font, Vector2(r.position.x + 10.0, r.end.y - 14.0), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 12, UiSkin.GOOD if sub == "WORN" else UiSkin.TEXT_DIM)
		_hits.append([r, func() -> void: _picked = id if _picked != id else "", "pick " + id])
	_detail(Rect2(Vector2(left_w + 10.0, 14), Vector2(size.x - left_w - 30.0, size.y - 28.0)))


func _detail(area: Rect2) -> void:
	UiSkin.panel(self, area, Color(0.05, 0.05, 0.08, 0.95), UiSkin.EDGE, 12)
	var worn := String(locker.get("worn"))
	var off_r := Rect2(Vector2(area.position.x + 16.0, area.end.y - 54.0), Vector2(area.size.x - 32.0, 40))
	UiSkin.pill(self, _font, off_r, "Take the mask off" if worn != "" else "No mask worn", worn == "", off_r.has_point(_mouse) and worn != "", 14)
	_hits.append([off_r, func() -> void: wear_requested.emit(""), "off"])
	if _picked == "":
		draw_string(_font, Vector2(area.position.x, area.get_center().y), "Pick a mask.", HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 17, UiSkin.TEXT_DIM)
		return
	var m: Dictionary = _db().call("mask", _picked)
	var mine := bool(locker.call("has", _picked))
	var x := area.position.x + 18.0
	var w := area.size.x - 36.0
	var pic := CamoIcons.mask(_picked, self)
	if pic != null:
		draw_texture_rect(pic, Rect2(Vector2(x, area.position.y + 8.0), Vector2(w, w * 9.0 / 16.0)), false, Color.WHITE if mine else Color(0.12, 0.12, 0.14, 0.9))
	var y := area.position.y + 26.0 + w * 9.0 / 16.0
	draw_string(_font, Vector2(x, y), String(m.get("name", _picked)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w, 24, UiSkin.ACCENT)
	y += 24.0
	var source := String(m.get("source", ""))
	draw_string(_font, Vector2(x, y), "%s mask  -  %s  -  %s" % [source.capitalize(), String(SOURCE_TEXT.get(source, "")), "can be traded" if bool(m.get("trade", false)) else "yours to keep"], HORIZONTAL_ALIGNMENT_LEFT, w, 13, UiSkin.TEXT_DIM)
	y += 14.0
	draw_multiline_string(_font, Vector2(x, y + 16.0), String(m.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, w, 14, 6, UiSkin.TEXT)
	if not mine:
		return
	draw_string(_font, Vector2(x, off_r.position.y - 66.0), "copies: %d" % int((locker.get("owned") as Dictionary).get(_picked, 0)), HORIZONTAL_ALIGNMENT_LEFT, w, 13, UiSkin.TEXT_DIM)
	var wear_r := Rect2(Vector2(x, off_r.position.y - 54.0), Vector2(w, 44))
	var on := worn == _picked
	UiSkin.pill(self, _font, wear_r, "WORN" if on else "WEAR IT", on, wear_r.has_point(_mouse) and not on, 17)
	var id := _picked
	_hits.append([wear_r, func() -> void: wear_requested.emit(id), "wear"])
