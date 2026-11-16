# Purpose: the town window of the home port (sea step 7a), real game UI (game/ui_skin.gd). LEFT: the town ledger, every
# building of the port with its level pips (opened from a building's sign it starts on that building; opened from the
# ledger at the harbour master it starts on the harbour master). RIGHT: the chosen building, a picture of how it looks
# now and how it will look after the next upgrade (assets/ui/town/<building>_<level>.png, tools/town_shot.tscn),
# what the next level adds, what it costs (materials from the bag with have / need, doubloons) and the button that
# repairs or upgrades it. Clicks act at once; the answer shows under the title.
# Dependencies: game/ui_skin.gd, game/currency_art.gd, game/icon_art.gd, game/sea_town.gd (set as `town`).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const CurrencyArt = preload("res://game/currency_art.gd")
const IconArt = preload("res://game/icon_art.gd")
const SIZE := Vector2(1040, 640)
const ROW := 52.0
const PICTURE := Vector2(300, 183)

var town: Node3D  # game/sea_town.gd
var chosen := "harbour_master"
var from_ledger := false
var _font: Font = ThemeDB.fallback_font
var _buttons: Array = []  # [Rect2, Callable, key]
var _pictures := {}  # model id -> Texture2D or null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open_at(id: String, ledger: bool) -> void:
	chosen = id
	from_ledger = ledger
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		town.call("close")
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


func _choose(id: String) -> void:
	chosen = id
	town.set("said", "")


func _use(kind: String) -> void:
	town.set("said", String(town.call("use", chosen, kind)))


func _upgrade() -> void:
	town.set("said", String(town.call("upgrade", chosen)))


func _picture(model: String) -> Texture2D:
	if not _pictures.has(model):
		var path := "res://assets/ui/town/%s.png" % model
		_pictures[model] = load(path) if ResourceLoader.exists(path) else null
	return _pictures[model]


func _draw() -> void:
	if town == null:
		return
	_buttons.clear()
	var rules: RefCounted = town.get("rules")
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.5))
	var r := Rect2((view - SIZE) * 0.5, SIZE)
	UiSkin.panel(self, r)
	draw_string(_font, r.position + Vector2(28, 42), "TOWN LEDGER  -  HOME PORT" if from_ledger else "HOME PORT", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiSkin.TEXT)
	var grown := float(rules.call("growth"))
	draw_string(_font, Vector2(r.end.x - 300.0, r.position.y + 40.0), "Town grown", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
	UiSkin.bar(self, Rect2(Vector2(r.end.x - 210.0, r.position.y + 28.0), Vector2(180, 14)), grown, UiSkin.ACCENT)
	var said := String(town.get("said"))
	if said != "":
		draw_string(_font, r.position + Vector2(28, 72), said, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.ACCENT)
	# the list of buildings
	var list := Rect2(r.position + Vector2(24, 90), Vector2(330, r.size.y - 150))
	var i := 0
	for id: String in rules.call("ids"):
		var row := Rect2(Vector2(list.position.x, list.position.y + i * ROW), Vector2(list.size.x, ROW - 6.0))
		UiSkin.slot(self, row, Color(0, 0, 0, 0), id == chosen, "")
		var lv := int(rules.call("level", id))
		var top := int(rules.call("top", id))
		var p: Dictionary = rules.call("plot", id)
		draw_string(_font, row.position + Vector2(14, 21), String(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
		draw_string(_font, row.position + Vector2(14, 39), String(rules.call("entry", id, lv)["name"]), HORIZONTAL_ALIGNMENT_LEFT, 200, 12, UiSkin.TEXT_DIM)
		for k in top:  # level pips
			var pip := Rect2(Vector2(row.end.x - 16.0 - (top - k) * 15.0, row.position.y + 17.0), Vector2(11, 11))
			draw_rect(pip, UiSkin.ACCENT if k < lv else Color(1, 1, 1, 0.12))
		_buttons.append([row, _choose.bind(id), "plot " + id])
		i += 1
	_building(Rect2(Vector2(list.end.x + 24.0, list.position.y), Vector2(r.end.x - list.end.x - 48.0, list.size.y)), rules)
	var by := r.end.y - 44.0
	CurrencyArt.draw(self, "doubloons", Vector2(r.position.x + 38.0, by + 14.0), 10.0)
	draw_string(_font, Vector2(r.position.x + 54.0, by + 20.0), "%d doubloons" % int(town.call("doubloons")), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiSkin.TEXT)
	var kx := r.end.x - 200.0
	kx += UiSkin.key_cap(self, _font, Vector2(kx, by + 4.0), "F / Esc") + 6.0
	draw_string(_font, Vector2(kx, by + 19.0), "Leave", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)


func _building(area: Rect2, rules: RefCounted) -> void:
	var p: Dictionary = rules.call("plot", chosen)
	var lv := int(rules.call("level", chosen))
	var top := int(rules.call("top", chosen))
	var building := String(p["building"])
	draw_string(_font, area.position + Vector2(0, 18), String(p["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiSkin.TEXT)
	draw_multiline_string(_font, area.position + Vector2(0, 38), String(p.get("about", "")), HORIZONTAL_ALIGNMENT_LEFT, area.size.x, 13, 2, UiSkin.TEXT_DIM)
	# now and next, side by side
	var top_y := area.position.y + 66.0
	var cards := [[lv, "NOW"]]
	if lv < top:
		cards.append([lv + 1, "NEXT"])
	for k in cards.size():
		var at := int(cards[k][0])
		var box := Rect2(Vector2(area.position.x + k * (PICTURE.x + 30.0), top_y), PICTURE)
		var tex := _picture("%s_%d" % [building, at])
		if tex != null:
			draw_texture_rect(tex, box, false)
		else:
			draw_rect(box, Color(1, 1, 1, 0.06))
		UiSkin.outline(self, box, UiSkin.ACCENT if k == 1 else Color(1, 1, 1, 0.25), 6, 2)
		var e: Dictionary = rules.call("entry", chosen, at)
		draw_string(_font, Vector2(box.position.x, box.end.y + 20.0), "%s  %s" % [cards[k][1], "Level %d" % at if at > 0 else "Run down"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
		draw_string(_font, Vector2(box.position.x, box.end.y + 40.0), String(e["name"]), HORIZONTAL_ALIGNMENT_LEFT, PICTURE.x, 16, UiSkin.TEXT)
		draw_multiline_string(_font, Vector2(box.position.x, box.end.y + 58.0), String(e.get("adds", "")), HORIZONTAL_ALIGNMENT_LEFT, PICTURE.x, 13, 2, UiSkin.TEXT_DIM)
	if lv < top:
		_arrow(top_y)
	_services(area, rules)
	var y := top_y + PICTURE.y + 96.0
	if lv >= top:
		draw_string(_font, Vector2(area.position.x, y + 20.0), "As grand as it gets.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.ACCENT)
		return
	draw_string(_font, Vector2(area.position.x, y), "COST", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	y += 10.0
	var cost: Dictionary = rules.call("cost", chosen)
	var x := area.position.x
	var items: Dictionary = cost.get("items", {})
	for item: String in items:
		var need := int(items[item])
		var have := int(town.call("have", item))
		var cell := Rect2(Vector2(x, y), Vector2(150, 44))
		UiSkin.slot(self, cell, Color(0, 0, 0, 0), false, "")
		var d: Dictionary = town.call("item_def", item)
		var c: Array = d.get("color", [0.8, 0.8, 0.8])
		IconArt.draw(self, String(d.get("icon", "empty")), Rect2(cell.position + Vector2(5, 5), Vector2(34, 34)), Color(c[0], c[1], c[2]))
		draw_string(_font, cell.position + Vector2(44, 18), String(town.call("item_name", item)), HORIZONTAL_ALIGNMENT_LEFT, 102, 12, UiSkin.TEXT)
		draw_string(_font, cell.position + Vector2(44, 36), "%d / %d" % [have, need], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT if have >= need else Color(1.0, 0.45, 0.4))
		x += 158.0
		if x + 150.0 > area.end.x:
			x = area.position.x
			y += 52.0
	var dbl := int(cost.get("doubloons", 0))
	if dbl > 0:
		var cell := Rect2(Vector2(x, y), Vector2(150, 44))
		UiSkin.slot(self, cell, Color(0, 0, 0, 0), false, "")
		CurrencyArt.draw(self, "doubloons", cell.position + Vector2(22, 22), 13.0)
		var mine := int(town.call("doubloons"))
		draw_string(_font, cell.position + Vector2(44, 18), "Doubloons", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiSkin.TEXT)
		draw_string(_font, cell.position + Vector2(44, 36), "%d / %d" % [mine, dbl], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT if mine >= dbl else Color(1.0, 0.45, 0.4))
	var ok := bool(town.call("can_pay", chosen)) and String(town.get("waiting")) == ""
	var label := "REPAIR" if lv == 0 else "UPGRADE"
	var b := Rect2(Vector2(area.end.x - 190.0, area.end.y - 40.0), Vector2(190, 40))
	UiSkin.pill(self, _font, b, label, ok, false, 17)
	if ok:
		_buttons.append([b, _upgrade, "upgrade"])


# What the building offers, as buttons along the bottom left (dim with the level they need until then).
func _services(area: Rect2, rules: RefCounted) -> void:
	var list: Array = rules.call("services", chosen)
	if list.is_empty():
		return
	var room := area.size.x - 210.0
	var lines: Array = [[]]  # buttons wrapped into lines, the last line along the bottom
	var x := 0.0
	for pair: Array in list:
		var sv: Dictionary = pair[0]
		var label := String(sv["name"]) if bool(pair[1]) else "%s (Lv %d)" % [String(sv["name"]), int(sv["level"])]
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 26.0
		if x + w > room and not (lines[-1] as Array).is_empty():
			lines.append([])
			x = 0.0
		(lines[-1] as Array).append([label, w, sv, bool(pair[1])])
		x += w + 8.0
	var y := area.end.y - 40.0 - 42.0 * (lines.size() - 1)
	draw_string(_font, Vector2(area.position.x, y - 8.0), "USE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	for line: Array in lines:
		x = area.position.x
		for item: Array in line:
			var b := Rect2(Vector2(x, y), Vector2(float(item[1]), 34))
			UiSkin.pill(self, _font, b, String(item[0]), bool(item[3]), false, 13)
			if bool(item[3]):
				_buttons.append([b, _use.bind(String(item[2]["kind"])), "use " + String(item[2]["kind"])])
			x += float(item[1]) + 8.0
		y += 42.0


# The arrow between the two pictures.
func _arrow(top_y: float) -> void:
	var left := (get_viewport_rect().size.x - SIZE.x) * 0.5 + 24.0 + 330.0 + 24.0
	var mid := Vector2(left + PICTURE.x + 15.0, top_y + PICTURE.y * 0.5)
	draw_colored_polygon(PackedVector2Array([mid + Vector2(-7, -10), mid + Vector2(7, 0), mid + Vector2(-7, 10)]), UiSkin.ACCENT)
