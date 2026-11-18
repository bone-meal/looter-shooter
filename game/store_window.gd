# Purpose: the home port's STORE CHEST window (sea step 7b, storehouse), real game UI (game/ui_skin.gd). LEFT: what the
# player carries in his bag (the fantasy world's goods: planks, bars, food ...), RIGHT: the chest's slots (as many as the
# storehouse's level gives; at the top level one chest shared by the whole crew). Clicking a stack moves one, with Shift
# all of it. Mouse wheel scrolls the bag.
# Dependencies: game/ui_skin.gd, game/icon_art.gd, game/sea_town.gd or game/ship_hold.gd (set as `town`: bag, chest,
# put, take; a hold also gives store_title).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const IconArt = preload("res://game/icon_art.gd")
const SIZE := Vector2(980, 600)
const CELL := 64.0
const COLS := 6

var town: Node3D  # game/sea_town.gd
var said := ""
var _font: Font = ThemeDB.fallback_font
var _buttons: Array = []  # [Rect2, Callable, key]
var _scroll := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	said = ""
	_scroll = 0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # a shared chest can change while it is open


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		town.call("close_store")
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var b := event as InputEventMouseButton
		if b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll += 1
		elif b.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll = maxi(_scroll - 1, 0)
		elif b.button_index == MOUSE_BUTTON_LEFT:
			for pair: Array in _buttons:
				if (pair[0] as Rect2).has_point(b.position):
					(pair[1] as Callable).call(b.shift_pressed)
					break
		accept_event()
		queue_redraw()


# Dev / checks: "put <item> [all]" / "take <item> [all]".
func press(text: String) -> bool:
	var w := text.split(" ", false)
	if w.size() < 2:
		return false
	said = String(town.call("put" if w[0] == "put" else "take", w[1], 9999 if w.size() > 2 else 1))
	queue_redraw()
	return true


func _put(all: bool, item: String) -> void:
	said = String(town.call("put", item, 9999 if all else 1))


func _take(all: bool, item: String) -> void:
	said = String(town.call("take", item, 9999 if all else 1))


func _cell(r: Rect2, item: String, n: int) -> void:
	UiSkin.slot(self, r, Color(0, 0, 0, 0), false, "")
	var d: Dictionary = town.call("item_def", item)
	var c: Array = d.get("color", [0.8, 0.8, 0.8])
	IconArt.draw(self, String(d.get("icon", "empty")), r.grow(-10.0), Color(c[0], c[1], c[2]))
	var label := str(n) if n < 10000 else "%dk" % floori(float(n) / 1000.0)
	draw_string(_font, Vector2(r.end.x - 6.0 - _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, r.end.y - 6.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT)


func _draw() -> void:
	if town == null:
		return
	_buttons.clear()
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.5))
	var r := Rect2((view - SIZE) * 0.5, SIZE)
	UiSkin.panel(self, r)
	var chest: RefCounted = town.call("chest")
	var shared := bool(town.call("chest_shared"))
	var title := String(town.get("store_title")) if town.get("store_title") != null else "STOREHOUSE  -  %s" % ("THE CREW'S CHEST" if shared else "YOUR CHEST")  # (a ship's hold names itself)
	draw_string(_font, r.position + Vector2(28, 42), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiSkin.TEXT)
	if said != "":
		draw_string(_font, r.position + Vector2(28, 70), said, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.ACCENT)
	var left := Rect2(r.position + Vector2(28, 92), Vector2(COLS * (CELL + 6.0), r.size.y - 160))
	var right := Rect2(Vector2(r.end.x - 28.0 - COLS * (CELL + 6.0), left.position.y), left.size)
	draw_string(_font, left.position + Vector2(0, -4), "YOUR BAG  (click: one, Shift: all)", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	draw_string(_font, right.position + Vector2(0, -4), ("CARGO" if town.get("store_title") != null else "CHEST") + "  %d / %d slots" % [(chest.get("slots") as Array).size(), int(chest.get("capacity"))], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	var rows := int(left.size.y / (CELL + 6.0))
	var mine: Array = town.call("bag_stacks")
	_scroll = clampi(_scroll, 0, maxi(0, ceili(float(mine.size()) / COLS) - rows))
	for i in mine.size():
		var row := floori(float(i) / COLS) - _scroll
		if row < 0 or row >= rows:
			continue
		var cell := Rect2(left.position + Vector2((i % COLS) * (CELL + 6.0), 8.0 + row * (CELL + 6.0)), Vector2(CELL, CELL))
		_cell(cell, String(mine[i][0]), int(mine[i][1]))
		_buttons.append([cell, _put.bind(String(mine[i][0])), "bag " + String(mine[i][0])])
	var slots: Array = chest.get("slots")
	for i in int(chest.get("capacity")):
		var row := floori(float(i) / COLS)
		if row >= rows:
			break
		var cell := Rect2(right.position + Vector2((i % COLS) * (CELL + 6.0), 8.0 + row * (CELL + 6.0)), Vector2(CELL, CELL))
		if i < slots.size():
			_cell(cell, String(slots[i][0]), int(slots[i][1]))
			_buttons.append([cell, _take.bind(String(slots[i][0])), "chest " + String(slots[i][0])])
		else:
			UiSkin.slot(self, cell, Color(0, 0, 0, 0), false, "")
	var by := r.end.y - 44.0
	var kx := r.end.x - 200.0
	kx += UiSkin.key_cap(self, _font, Vector2(kx, by + 4.0), "F / Esc") + 6.0
	draw_string(_font, Vector2(kx, by + 19.0), "Leave", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
