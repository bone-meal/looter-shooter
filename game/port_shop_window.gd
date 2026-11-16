# Purpose: the harbour master's window (sea step 6), real game UI (game/ui_skin.gd): tabs BUY (charts for chips,
# supplies and the salvage crane for doubloons), SELL (rolled guns and armour from the backpack for doubloons), CHANGE
# (casino chips into doubloons at the stall's really bad rate, one way) and FERRY (to other ports whose island is
# explored); the chips and doubloons in hand along the bottom. Clicks act at once; the answer shows under the tabs.
# Dependencies: game/ui_skin.gd, game/tier_style.gd (tier colours), game/sea_port.gd (set as `port`: rules, money,
# goods).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const TierStyle = preload("res://game/tier_style.gd")
const CurrencyArt = preload("res://game/currency_art.gd")
const SIZE := Vector2(900, 600)
const TABS := ["BUY", "SELL", "CHANGE", "FERRY"]
const ROW := 46.0

var port: Node3D  # game/sea_port.gd
var tab := 0
var here := ""  # the port's id
var said := ""
var _font: Font = ThemeDB.fallback_font
var _buttons: Array = []  # [Rect2, Callable]
var _scroll := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open_at(id: String) -> void:
	here = id
	said = ""
	_scroll = 0
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		port.call("close")
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
					(pair[1] as Callable).call()
					break
		accept_event()
		queue_redraw()


# Dev / checks: press the button whose label starts with `text` on the open tab (returns false if none).
func press(text: String) -> bool:
	for pair: Array in _buttons:
		if String(pair[2]).begins_with(text):
			(pair[1] as Callable).call()
			queue_redraw()
			return true
	return false


# A button: `label` drawn, `key` matched by press() (dev / checks).
func _button(r: Rect2, label: String, key: String, enabled: bool, act: Callable) -> void:
	UiSkin.pill(self, _font, r, label, enabled, false, 14)
	if enabled:
		_buttons.append([r, act, key])


func _set_tab(k: int) -> void:
	tab = k
	_scroll = 0
	said = ""


func _draw() -> void:
	if port == null:
		return
	_buttons.clear()
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.5))
	var r := Rect2((view - SIZE) * 0.5, SIZE)
	UiSkin.panel(self, r)
	var name_here := String((port.get("rules").call("port", here) as Dictionary).get("name", "Port"))
	draw_string(_font, r.position + Vector2(28, 42), "HARBOUR MASTER  -  %s" % name_here.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiSkin.TEXT)
	var tx := r.position.x + 28.0
	for i in TABS.size():
		var w := _font.get_string_size(TABS[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 34.0
		var tr_tab := Rect2(Vector2(tx, r.position.y + 58), Vector2(w, 30))
		UiSkin.pill(self, _font, tr_tab, TABS[i], i == tab, false, 15)
		var k := i
		_buttons.append([tr_tab, _set_tab.bind(k), "tab " + TABS[i]])
		tx += w + 8.0
	if said != "":
		draw_string(_font, Vector2(r.position.x + 28.0, r.position.y + 114.0), said, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.ACCENT)
	var area := Rect2(r.position + Vector2(28, 128), Vector2(r.size.x - 56, r.size.y - 196))
	match tab:
		0: _buy(area)
		1: _sell(area)
		2: _change(area)
		3: _ferry(area)
	var chips := int(port.call("chips").get("balance")) if port.call("chips") != null else 0
	var dbl := int(port.call("doubloons").get("balance")) if port.call("doubloons") != null else 0
	var by := r.end.y - 44.0
	CurrencyArt.draw(self, "chips", Vector2(r.position.x + 38.0, by + 14.0), 10.0)
	draw_string(_font, Vector2(r.position.x + 54.0, by + 20.0), "%d chips" % chips, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiSkin.TEXT)
	CurrencyArt.draw(self, "doubloons", Vector2(r.position.x + 238.0, by + 14.0), 10.0)
	draw_string(_font, Vector2(r.position.x + 254.0, by + 20.0), "%d doubloons" % dbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiSkin.TEXT)
	var kx := r.end.x - 200.0
	kx += UiSkin.key_cap(self, _font, Vector2(kx, by + 4.0), "F / Esc") + 6.0
	draw_string(_font, Vector2(kx, by + 19.0), "Leave", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)


func _row(area: Rect2, i: int) -> Rect2:
	return Rect2(Vector2(area.position.x, area.position.y + i * ROW), Vector2(area.size.x, ROW - 6.0))


func _buy(area: Rect2) -> void:
	var stock: Array = port.get("rules").call("stock")
	var i := 0
	for entry: Dictionary in stock:
		var row := _row(area, i)
		UiSkin.slot(self, row, Color(0, 0, 0, 0), false, "")
		var count := int(entry.get("count", 1))
		draw_string(_font, row.position + Vector2(14, 26), "%s%s" % [port.call("item_name", String(entry["item"])), "  x%d" % count if count > 1 else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
		var price := "%d chips" % int(entry["chips"]) if entry.has("chips") else "%d doubloons" % int(entry["doubloons"])
		CurrencyArt.draw(self, "chips" if entry.has("chips") else "doubloons", Vector2(row.end.x - 312.0, row.position.y + 20.0), 8.0)
		draw_string(_font, Vector2(row.end.x - 300.0, row.position.y + 26.0), price, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
		var e := entry
		_button(Rect2(Vector2(row.end.x - 110.0, row.position.y + 6.0), Vector2(100, 28)), "Buy", "Buy " + String(entry["item"]), true, func() -> void: said = String(port.call("buy", e)))
		i += 1
	var crane := _row(area, i)
	UiSkin.slot(self, crane, Color(0, 0, 0, 0), false, "")
	draw_string(_font, crane.position + Vector2(14, 26), "Salvage crane, fitted to the ship at the shipyard", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
	draw_string(_font, Vector2(crane.end.x - 300.0, crane.position.y + 26.0), "%d doubloons" % int(port.get("rules").cfg["crane"]["doubloons"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
	_button(Rect2(Vector2(crane.end.x - 110.0, crane.position.y + 6.0), Vector2(100, 28)), "Buy", "Buy crane", true, func() -> void: said = String(port.call("buy_crane")))


func _sell(area: Rect2) -> void:
	var goods: Array = port.call("sellable")
	if goods.is_empty():
		draw_string(_font, area.position + Vector2(6, 26), "Nothing in the backpack the harbour master buys (rolled guns and armour).", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
		return
	var fits := int(area.size.y / ROW)
	_scroll = clampi(_scroll, 0, maxi(goods.size() - fits, 0))
	for i in mini(fits, goods.size() - _scroll):
		var g: Array = goods[i + _scroll]
		var row := _row(area, i)
		var tint := TierStyle.color(port.get("_player").get("gun_db"), String(g[3]), 0.0)
		UiSkin.slot(self, row, tint, false, "")
		draw_string(_font, row.position + Vector2(14, 26), String(g[2]), HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 340.0, 16, tint)
		draw_string(_font, Vector2(row.end.x - 300.0, row.position.y + 26.0), "%d doubloons" % int(g[4]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
		var slot := int(g[0])
		_button(Rect2(Vector2(row.end.x - 110.0, row.position.y + 6.0), Vector2(100, 28)), "Sell", "Sell %d" % slot, true, func() -> void: said = String(port.call("sell", slot)))
	if goods.size() > fits:
		draw_string(_font, Vector2(area.position.x, area.end.y + 4.0), "Mouse wheel: more (%d)" % goods.size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)


func _change(area: Rect2) -> void:
	var rate := int(port.get("rules").cfg["chips_per_doubloon"])
	draw_string(_font, area.position + Vector2(6, 26), "The harbour master changes casino chips into doubloons at a poor rate: %d chips for 1 doubloon." % rate, HORIZONTAL_ALIGNMENT_LEFT, area.size.x, 15, UiSkin.TEXT)
	draw_string(_font, area.position + Vector2(6, 50), "Doubloons never change back into chips.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
	var y := area.position.y + 76.0
	var chips := int(port.call("chips").get("balance")) if port.call("chips") != null else 0
	for n: int in [1, 10, 100]:
		var cost := n * rate
		_button(Rect2(Vector2(area.position.x, y), Vector2(320, 32)), "Change %d chips into %d doubloon%s" % [cost, n, "" if n == 1 else "s"], "Change %d" % n, chips >= cost, func() -> void: said = String(port.call("exchange", cost)))
		y += 42.0
	_button(Rect2(Vector2(area.position.x, y), Vector2(320, 32)), "Change all I can", "Change all", chips >= rate, func() -> void: said = String(port.call("exchange", chips)))


func _ferry(area: Rect2) -> void:
	var chart: RefCounted = port.get("_sea").get("chart")
	var to: Array = port.get("rules").call("ferry_to", here, chart.get("explored"))
	draw_string(_font, area.position + Vector2(6, 26), "The ferry carries you (not your ship, ore or bars) to any port whose island you have explored.", HORIZONTAL_ALIGNMENT_LEFT, area.size.x, 15, UiSkin.TEXT)
	if to.is_empty():
		draw_string(_font, area.position + Vector2(6, 60), "No other port charted yet.", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
		return
	var i := 1
	for p: Dictionary in to:
		var row := _row(area, i)
		UiSkin.slot(self, row, Color(0, 0, 0, 0), false, "")
		draw_string(_font, row.position + Vector2(14, 26), String(p["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
		var target := p
		_button(Rect2(Vector2(row.end.x - 110.0, row.position.y + 6.0), Vector2(100, 28)), "Sail there", "Sail to " + String(p["id"]), true, func() -> void: said = String(port.call("ferry", target)))
		i += 1
