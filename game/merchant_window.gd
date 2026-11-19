# Purpose: a merchant raft's window (sea step 13d), real game UI (game/ui_skin.gd): the merchant's name and greeting,
# her goods (each a row: what, price in doubloons, how many more she sells this player, Buy), the doubloons in hand.
# Purchases are the player's own (game/sea_events.gd buy). F / Esc leaves.
# Dependencies: game/ui_skin.gd, game/currency_art.gd, game/sea_events.gd (set as `events`).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const CurrencyArt = preload("res://game/currency_art.gd")
const SIZE := Vector2(820, 520)
const ROW := 50.0

var events: Node3D  # game/sea_events.gd
var event_id := -1
var said := ""
var _font: Font = ThemeDB.fallback_font
var _buttons: Array = []  # [Rect2, Callable, key]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open_for(id: int) -> void:
	event_id = id
	said = ""
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	event_id = -1


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		events.call("close_window")
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		for pair: Array in _buttons:
			if (pair[0] as Rect2).has_point((event as InputEventMouseButton).position):
				(pair[1] as Callable).call()
				break
		accept_event()
		queue_redraw()


# Dev / checks: press the button whose key starts with `text` (returns false if none).
func press(text: String) -> bool:
	for pair: Array in _buttons:
		if String(pair[2]).begins_with(text):
			(pair[1] as Callable).call()
			queue_redraw()
			return true
	return false


func _draw() -> void:
	if events == null:
		return
	_buttons.clear()
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.5))
	var r := Rect2((view - SIZE) * 0.5, SIZE)
	UiSkin.panel(self, r)
	var e: Dictionary = (events.get("events") as Dictionary).get(event_id, {})
	var who := String(events.get("rules").call("name_of", "merchants", String(e.get("name", "")))) if not e.is_empty() else "The merchant"
	draw_string(_font, r.position + Vector2(28, 42), "MERCHANT RAFT  -  %s" % who.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiSkin.TEXT)
	if said != "":
		draw_string(_font, r.position + Vector2(28, 74), said, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 56.0, 15, UiSkin.ACCENT)
	var y := r.position.y + 96.0
	if e.is_empty():
		draw_string(_font, Vector2(r.position.x + 28.0, y + 26.0), "She has paddled off.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT_DIM)
	for g: Array in events.call("goods", event_id):
		var row := Rect2(Vector2(r.position.x + 28.0, y), Vector2(r.size.x - 56.0, ROW - 8.0))
		UiSkin.slot(self, row, Color(0, 0, 0, 0), false, "")
		var entry: Dictionary = g[1]
		draw_string(_font, row.position + Vector2(14, 27), String(g[2]), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 380.0, 16, UiSkin.ACCENT if entry.has("gun") else UiSkin.TEXT)
		CurrencyArt.draw(self, "doubloons", Vector2(row.end.x - 322.0, row.position.y + 21.0), 8.0)
		draw_string(_font, Vector2(row.end.x - 310.0, row.position.y + 27.0), "%d doubloons" % int(g[3]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
		draw_string(_font, Vector2(row.end.x - 186.0, row.position.y + 27.0), "%d left" % maxi(int(g[4]), 0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
		var idx := int(g[0])
		var id := event_id
		var buy_r := Rect2(Vector2(row.end.x - 110.0, row.position.y + 7.0), Vector2(100, 28))
		UiSkin.pill(self, _font, buy_r, "Buy", int(g[4]) > 0, false, 14)
		if int(g[4]) > 0:
			_buttons.append([buy_r, func() -> void: said = String(events.call("buy", id, idx)), "Buy %d" % idx])
		y += ROW
	var s: Node = get_tree().get_first_node_in_group("game_session")
	var dbl := int((s.call("doubloons") as RefCounted).get("balance")) if s != null and s.has_method("doubloons") else 0
	var by := r.end.y - 44.0
	CurrencyArt.draw(self, "doubloons", Vector2(r.position.x + 38.0, by + 14.0), 10.0)
	draw_string(_font, Vector2(r.position.x + 54.0, by + 20.0), "%d doubloons" % dbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiSkin.TEXT)
	var kx := r.end.x - 200.0
	kx += UiSkin.key_cap(self, _font, Vector2(kx, by + 4.0), "F / Esc") + 6.0
	draw_string(_font, Vector2(kx, by + 19.0), "Leave", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
