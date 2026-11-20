# Purpose: the CASES tab of the player card, next to the Binder (polish1 item 72): one card per kind of crate with its
# picture (tools/blender/crates.py), name, what it can hold, how many unopened the player has, and OPEN (which shows
# the opening screen, game/case_opening.gd). Real game UI (game/ui_skin.gd). Draws and asks only.
# Dependencies: game/ui_skin.gd, core/case_shelf.gd (set `shelf`), core/gun_db.gd (tier names), data/gun_loot.json
# "vendor" (set `crates`), assets/ui/cases/<id>.png.
extends Control

const UiSkin = preload("res://game/ui_skin.gd")

signal open_requested(crate_id: String)

const CARD := Vector2(400, 520)

var crates: Array = []  # data/gun_loot.json "vendor"
var shelf: RefCounted  # core/case_shelf.gd
var gun_db: RefCounted

var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _pics := {}
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(queue_redraw)


func refresh() -> void:
	queue_redraw()


# Checks: press "open <id>".
func press(key: String) -> bool:
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
		queue_redraw()
	var b := event as InputEventMouseButton
	if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		for hit: Array in _hits:
			if (hit[0] as Rect2).has_point(b.position):
				(hit[1] as Callable).call()
				break
		accept_event()


func _pic(id: String) -> Texture2D:
	if not _pics.has(id):
		var path := "res://assets/ui/cases/%s.png" % id
		_pics[id] = load(path) if ResourceLoader.exists(path) else null
	return _pics[id]


func _draw() -> void:
	_hits.clear()
	if shelf == null:
		return
	var total_w := float(crates.size()) * CARD.x + float(maxi(crates.size() - 1, 0)) * 30.0
	var x0 := (size.x - total_w) * 0.5
	var y0 := maxf((size.y - CARD.y) * 0.5, 50.0)
	draw_string(_font, Vector2(0, y0 - 18.0), "YOUR CASES  -  buy crates at the casino's gun kiosks, open them here", HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, UiSkin.TEXT_DIM)
	for i in crates.size():
		var crate: Dictionary = crates[i]
		var id := String(crate["id"])
		var have := int(shelf.call("count", id))
		var colour := Color(String(crate["color"]))
		var r := Rect2(Vector2(x0 + float(i) * (CARD.x + 30.0), y0), CARD)
		var over := r.has_point(_mouse) and have > 0
		UiSkin.panel(self, r.grow(4.0) if over else r, Color(colour.darkened(0.85), 0.98), Color(colour, 0.9 if over else 0.45), 16)
		var pic := _pic(id)
		if pic != null:
			draw_texture_rect(pic, Rect2(r.position + Vector2(30, 10), Vector2(340, 340)), false, Color(1, 1, 1, 1.0 if have > 0 else 0.35))
		draw_string(_font, Vector2(r.position.x, r.position.y + 370.0), String(crate["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 26, colour.lightened(0.25))
		var floor_name := String(gun_db.tier(String(crate["min_tier"]))["name"]) if gun_db != null else String(crate["min_tier"])
		draw_string(_font, Vector2(r.position.x, r.position.y + 398.0), "one rolled gun, %s or better" % floor_name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, UiSkin.TEXT_DIM)
		draw_string(_font, Vector2(r.position.x, r.position.y + 432.0), "x%d" % have, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 28, UiSkin.TEXT if have > 0 else UiSkin.TEXT_DIM)
		var button := Rect2(Vector2(r.position.x + 70.0, r.end.y - 66.0), Vector2(r.size.x - 140.0, 48))
		if have > 0:
			UiSkin.pill(self, _font, button, "OPEN", true, button.has_point(_mouse), 22)
			_hits.append([button, func() -> void: open_requested.emit(id), "open " + id])
		else:
			draw_string(_font, Vector2(r.position.x, button.get_center().y + 6.0), "%d chips at the kiosk" % int(crate["price"]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, UiSkin.TEXT_DIM)
