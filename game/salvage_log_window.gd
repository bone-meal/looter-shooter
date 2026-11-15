# Purpose: the salvage logbook window (sea step 5b, key J at sea), real game UI (game/ui_skin.gd): one card per set
# (each region's hand-placed finds, then Odds and Ends = the random trinkets with how many of each), every find as a
# slot with its icon (faded until found), its name, the set's count and reward, and the line of the last one found.
# Read only: no clicks.
# Dependencies: game/ui_skin.gd, game/icon_art.gd, core/sea/salvage_book.gd (set by game/sea_salvage.gd).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const IconArt = preload("res://game/icon_art.gd")
const SIZE := Vector2(980, 640)  # width; the height follows the number of sets
const CELL := 74.0

var book: RefCounted  # core/sea/salvage_book.gd
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	if book == null:
		return
	var view := get_viewport_rect().size
	var box := Vector2(SIZE.x, 96.0 + 196.0 * float((book.call("set_ids") as Array).size() + 1))
	var r := Rect2((view - box) * 0.5, box)
	UiSkin.panel(self, r)
	draw_string(_font, r.position + Vector2(28, 46), "SALVAGE LOGBOOK", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, UiSkin.TEXT)
	var hint := "J  close"
	draw_string(_font, Vector2(r.end.x - 28.0 - _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x, r.position.y + 44), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
	var y := r.position.y + 70.0
	var sets: Array = (book.call("set_ids") as Array).duplicate()
	sets.append("trinkets")
	for set_id: String in sets:
		y = _set_card(Rect2(r.position.x + 24.0, y, r.size.x - 48.0, 0.0), set_id) + 14.0


func _set_card(area: Rect2, set_id: String) -> float:
	var finds: Array = book.call("set_finds", set_id)
	var have := int(book.call("have", set_id))
	var full := have >= finds.size()
	var title := String(book.get("titles").get(set_id, set_id))
	var reward: Dictionary = book.call("reward", set_id)
	var bottom := UiSkin.header(self, _font, area.position, area.size.x, title.to_upper(), "%d / %d   reward %d chips%s" % [have, finds.size(), int(reward["chips"]), "  - PAID" if (book.get("paid") as Dictionary).has(set_id) else ""])
	var x := area.position.x
	var last := ""
	for id: String in finds:
		var got := int((book.get("trinkets") as Dictionary).get(id, 0)) if set_id == "trinkets" else (1 if (book.get("found") as Dictionary).has(id) else 0)
		var slot := Rect2(Vector2(x, bottom), Vector2(CELL, CELL))
		UiSkin.slot(self, slot, UiSkin.ACCENT if got > 0 else Color(0, 0, 0, 0), got > 0, "")
		IconArt.draw(self, String(book.call("icon_of", id)), slot.grow(-12.0), Color(0.9, 0.82, 0.6), 1.0 if got > 0 else 0.22)
		if set_id == "trinkets" and got > 1:
			draw_string(_font, Vector2(slot.position.x, slot.end.y - 6.0), "x%d" % got, HORIZONTAL_ALIGNMENT_RIGHT, CELL - 6.0, 13, UiSkin.TEXT)
		var label := String(book.call("name_of", id)) if got > 0 else "?"
		draw_string(_font, Vector2(slot.position.x - 8.0, slot.end.y + 16.0), label, HORIZONTAL_ALIGNMENT_CENTER, CELL + 16.0, 11, UiSkin.TEXT if got > 0 else UiSkin.TEXT_DIM)
		if got > 0:
			last = id
		x += CELL + 26.0
	var note := String(book.get("done_lines").get(set_id, "")) if full else (String(book.get("lines").get(last, "")) if last != "" else "Nothing found yet.")
	draw_string(_font, Vector2(area.position.x, bottom + CELL + 40.0), note, HORIZONTAL_ALIGNMENT_LEFT, area.size.x, 13, UiSkin.TEXT_DIM)
	return bottom + CELL + 50.0
