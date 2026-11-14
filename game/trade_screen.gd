# Purpose: the trade window (online), drawn as pictures: two trays side by side, YOU GIVE (orange) and YOU GET (blue),
# eight slots each, every thing a tile with its icon (guns in their tier colour, armour in its own colour, card game
# cards as small cards); a green tick or an hourglass under each tray for the "ready" ticks; below, your things to
# offer behind two icon tabs (bag: guns and armour; cards: the collection, one copy a click, unopened packs are not
# tradeable, locked); big READY / CONFIRM / CANCEL buttons and one short status line. Hover a tile = its card.
# Shows what the host's desk says (core/trade_desk.gd through game/net_trade.gd); every click is a request, nothing
# changes hands here. Laid out for a 648-pixel-high window and scaled up (like the card machine).
# Dependencies: game/menu_widgets.gd, core/inventory_state.gd, core/item_db.gd, core/gun_db.gd, core/gun_stats.gd, game/hover_card.gd,
# game/tier_style.gd, game/item_icons.gd, game/icon_art.gd, game/tcg/card_face.gd (cards: core/tcg/collection.gd and
# core/tcg/card_db.gd via set_cards).
extends Control

const Widgets = preload("res://game/menu_widgets.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const GunStats = preload("res://core/gun_stats.gd")
const TierStyle = preload("res://game/tier_style.gd")
const HoverCard = preload("res://game/hover_card.gd")
const ItemIcons = preload("res://game/item_icons.gd")
const IconArt = preload("res://game/icon_art.gd")
const CardFace = preload("res://game/tcg/card_face.gd")

signal offered(thing: Dictionary)  # {"ref": slot, "gun": {...}}, {"ref": slot, "id": item id} or {"ref", "card", "finish", "leader"}
signal withdrawn(ref: int)
signal ready_set(on: bool)
signal confirmed
signal cancelled

const BASE_HEIGHT := 648.0
const W := 1152.0
const CARD_REF := 1000  # refs from here up mark offered cards (bag slots are below)
const SLOTS := 8
const TILE := Vector2(76, 96)
const GAP := 8.0
const GIVE := Color(1.0, 0.6, 0.22)
const GET := Color(0.35, 0.8, 1.0)
const OK := Color(0.4, 0.95, 0.5)
const RARITY_COLORS := {"common": Color(0.92, 0.92, 0.92), "rare": Color(0.4, 0.65, 1.0), "epic": Color(0.75, 0.45, 1.0), "legendary": Color(1.0, 0.65, 0.2)}
const GIVE_AT := Vector2(150, 92)  # top left of the give tray's tiles
const GET_AT := Vector2(674, 92)

var _inventory: InventoryState
var _items: RefCounted
var _gun_db: RefCounted
var _cards: RefCounted  # core/tcg/collection.gd
var _card_db: RefCounted  # core/tcg/card_db.gd
var _board := Control.new()  # trays, arrows, ticks, status: drawn
var _give_tiles: Array = []
var _get_tiles: Array = []
var _strip := GridContainer.new()
var _tab := "bag"
var _tabs: Array = []  # two IconButton
var _ready_button: IconButton
var _confirm_button: IconButton
var _status := ""
var _status_icon := "exclaim"
var _view := {}
var in_hand := -1  # the holster in the player's hand, -1 = the knife (set by the session): a hovered gun's card compares with that gun
var _hover := {}  # the thing under the mouse
var _card: Control  # lies over everything and draws the hovered thing's card (game/hover_card.gd)
var _card_face: Control  # the hovered card game card, drawn big
var _next_ref := CARD_REF
var offered_cards := {}  # ref -> card thing offered in this trade (the session takes these out when it is done)
var _font: Font = ThemeDB.fallback_font


# One slot: a thing's icon (or an empty dashed slot). Drawn by the screen.
class Tile extends Control:
	signal clicked(tile: Control)
	var thing := {}
	var screen: Control
	var role := ""  # "give" (click = take back), "get", "offer" (click = offer)
	var count := 0  # copies left to offer (cards)
	var face: Control  # a small card for card game cards
	var lit := false

	func _init() -> void:
		custom_minimum_size = Vector2(76, 96)
		size = custom_minimum_size
		mouse_entered.connect(func() -> void:
			lit = true
			screen.call("_set_hover", thing)
			queue_redraw())
		mouse_exited.connect(func() -> void:
			lit = false
			screen.call("_set_hover", {})
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not thing.is_empty():
			clicked.emit(self)

	func _draw() -> void:
		screen.call("_draw_tile", self)


# A big button with an icon from the icon sheet (or a card) and one word.
class IconButton extends Control:
	signal pressed
	var shape := ""
	var word := ""
	var color := Color.WHITE
	var on := false  # chosen tab / pulsing
	var disabled := false
	var lit := false
	var font: Font

	func _init() -> void:
		mouse_entered.connect(func() -> void:
			lit = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			lit = false
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and not disabled:
			pressed.emit()

	func _process(_delta: float) -> void:
		if on and is_visible_in_tree():
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var a := 0.35 if disabled else 1.0
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 160.0) if on else 0.0
		var back := StyleBoxFlat.new()
		back.set_corner_radius_all(int(size.y * 0.3))
		back.bg_color = Color(color, (0.22 if lit else 0.12) + 0.15 * pulse).darkened(0.3)
		back.border_color = Color(color, a)
		back.set_border_width_all(3 if lit or on else 2)
		draw_style_box(back, r)
		var icon_r := Rect2(Vector2(10, 6), Vector2(size.y - 12, size.y - 12))
		if shape == "card":  # a little card with the logo colours
			var c := Rect2(icon_r.position + Vector2(icon_r.size.x * 0.18, 0), Vector2(icon_r.size.x * 0.64, icon_r.size.y))
			draw_rect(c, Color(0.75, 0.1, 0.35, a))
			draw_rect(c, Color(1.0, 0.8, 0.35, a), false, 2.0)
			draw_circle(c.get_center(), c.size.x * 0.22, Color(1.0, 0.8, 0.35, a))
		else:
			IconArt.draw(self, shape, icon_r, color, a)
		draw_string(font, Vector2(size.y + 2, size.y * 0.5 + 7), word, HORIZONTAL_ALIGNMENT_LEFT, size.x - size.y - 6, 20, Color(1, 1, 1, a))


func setup(inventory: InventoryState, items: RefCounted, gun_db: RefCounted) -> void:
	_inventory = inventory
	_items = items
	_gun_db = gun_db
	visible = false
	_font = CardFace.font("title")
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.9)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_board.size = Vector2(W, BASE_HEIGHT)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.draw.connect(_draw_board)
	add_child(_board)
	for i in SLOTS:
		for side: Array in [[_give_tiles, GIVE_AT, "give"], [_get_tiles, GET_AT, "get"]]:
			var t := Tile.new()
			t.screen = self
			t.role = side[2]
			t.position = (side[1] as Vector2) + Vector2(i % 4, floori(i / 4.0)) * (TILE + Vector2(GAP, GAP))
			t.clicked.connect(_on_tile)
			add_child(t)
			(side[0] as Array).append(t)
	var tab_row := [["bag", "bag", "GEAR"], ["cards", "card", "CARDS"]]
	for i in tab_row.size():
		var b := _icon_button(String(tab_row[i][1]), String(tab_row[i][2]), Color(0.85, 0.85, 0.9), Rect2(76 + i * 170, 352, 160, 40))
		var which := String(tab_row[i][0])
		b.pressed.connect(func() -> void:
			_tab = which
			show_table(_view))
		_tabs.append(b)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(76, 400)
	scroll.size = Vector2(1000, 2 * TILE.y + GAP + 4)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_strip.columns = 11
	_strip.add_theme_constant_override("h_separation", int(GAP) + 4)
	_strip.add_theme_constant_override("v_separation", int(GAP))
	scroll.add_child(_strip)
	_ready_button = _icon_button("check", "READY", OK, Rect2(492, 600, 214, 42))
	_ready_button.pressed.connect(func() -> void: ready_set.emit(not bool(_view.get("ready_mine", false))))
	_confirm_button = _icon_button("star", "CONFIRM", Color(1.0, 0.82, 0.3), Rect2(718, 600, 194, 42))
	_confirm_button.pressed.connect(func() -> void: confirmed.emit())
	var cancel := _icon_button("cross", "CANCEL", Color(1.0, 0.4, 0.35), Rect2(924, 600, 180, 42))
	cancel.pressed.connect(func() -> void: cancelled.emit())
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	Widgets.fill(_card)
	_card.draw.connect(_draw_card)
	_card_face = CardFace.new()
	_card_face.visible = false
	_card_face.size = Vector2(200, 280)
	add_child(_card_face)
	_card_face.mouse_filter = Control.MOUSE_FILTER_IGNORE



func _ready() -> void:
	get_viewport().size_changed.connect(_fit)


func set_cards(collection: RefCounted, db: RefCounted) -> void:
	_cards = collection
	_card_db = db


func _fit() -> void:
	var view := get_viewport_rect().size
	var k := clampf(view.y / BASE_HEIGHT, 1.0, 4.0)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	scale = Vector2(k, k)
	size = view / k
	position = Vector2((view.x - W * k) * 0.5, 0.0) if view.x > W * k else Vector2.ZERO


func _icon_button(shape: String, word: String, color: Color, at: Rect2) -> IconButton:
	var b := IconButton.new()
	b.shape = shape
	b.word = word
	b.color = color
	b.font = _font
	b.position = at.position
	b.size = at.size
	add_child(b)
	return b


func _process(_delta: float) -> void:
	if visible and not _hover.is_empty():
		_card.queue_redraw()


func _set_hover(thing: Dictionary) -> void:
	_hover = thing
	_card.queue_redraw()


func _draw_card() -> void:
	_card_face.visible = _hover.has("card") and _card_db != null
	if _hover.is_empty():
		return
	var place := _card.get_local_mouse_position() + Vector2(18, 18)
	var view := size
	if _hover.has("card"):
		if _card_face.visible:
			_card_face.show_card(_card_db, String(_hover["card"]))
			_card_face.position = Vector2(minf(place.x, view.x - _card_face.size.x), clampf(place.y - _card_face.size.y * 0.5, 0.0, view.y - _card_face.size.y))
		return
	if _hover.has("gun"):
		var gun: Dictionary = _hover["gun"]
		var held: Dictionary = _inventory.holster_gun(in_hand) if in_hand >= 0 else {}
		HoverCard.draw_gun(_card, ThemeDB.fallback_font, _gun_db, gun, held, place, view, "Rolled gun" if held.is_empty() else "compared with the gun in hand")
	else:
		HoverCard.draw_item(_card, ThemeDB.fallback_font, _items, String(_hover["id"]), place, view)


# view: what the desk says this player sees (core/trade_desk.gd `_views`).
func show_table(view: Dictionary) -> void:
	if not visible:  # a new trade: the card marks start over (kept after close, the session reads them when it is done)
		offered_cards = {}
		_next_ref = CARD_REF
		_tab = "bag"
	_view = view
	_hover = {}
	_card.queue_redraw()
	visible = true
	_fit()
	var mine: Array = view["mine"]
	var theirs: Array = view["theirs"]
	for i in SLOTS:
		_set_tile(_give_tiles[i], mine[i] if i < mine.size() else {})
		_set_tile(_get_tiles[i], theirs[i] if i < theirs.size() else {})
	_fill_strip(mine)
	(_tabs[0] as IconButton).on = _tab == "bag"
	(_tabs[1] as IconButton).on = _tab == "cards"
	(_tabs[1] as IconButton).visible = _cards != null
	var short := _bag_things(theirs) - (_free_slots() + _bag_things(mine))  # cards need no bag room
	var both: bool = view["confirm"]
	var ready_mine := bool(view["ready_mine"])
	_ready_button.word = "NOT READY" if ready_mine else "READY"
	_ready_button.shape = "cross" if ready_mine else "check"
	_ready_button.disabled = short > 0 and not ready_mine
	_ready_button.on = not ready_mine and not both and not (mine.is_empty() and theirs.is_empty())
	_confirm_button.visible = both
	_confirm_button.disabled = bool(view["confirmed_mine"])
	_confirm_button.on = both and not bool(view["confirmed_mine"])
	if short > 0:
		_status_icon = "exclaim"
		_status = "Make room: %d more free bag slot%s" % [short, "" if short == 1 else "s"]
	elif both:
		_status_icon = "clock" if bool(view["confirmed_mine"]) else "star"
		_status = "Waiting for %s" % view["with"] if bool(view["confirmed_mine"]) else "Both ready: check it, then CONFIRM"
	elif mine.is_empty() and theirs.is_empty():
		_status_icon = "arrow"
		_status = "Click your things below to offer them"
	else:
		_status_icon = "check"
		_status = "Press READY when it looks fair"
	for b: Control in [_ready_button, _confirm_button, _tabs[0], _tabs[1]]:
		b.queue_redraw()
	_board.queue_redraw()


func close() -> void:
	visible = false
	_hover = {}
	_card_face.visible = false


func is_open() -> bool:
	return visible


func _set_tile(tile: Tile, thing: Dictionary) -> void:
	tile.thing = thing
	tile.mouse_filter = Control.MOUSE_FILTER_STOP if not thing.is_empty() else Control.MOUSE_FILTER_IGNORE
	_dress_card(tile)
	tile.queue_redraw()


# A card thing shows a small card face inside its tile.
func _dress_card(tile: Tile) -> void:
	if tile.thing.has("card") and _card_db != null:
		if tile.face == null:
			tile.face = CardFace.new()
			tile.add_child(tile.face)
			tile.face.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tile.face.size = Vector2(62, 87)
			tile.face.position = Vector2(7, 4)
		tile.face.visible = true
		tile.face.show_card(_card_db, String(tile.thing["card"]))
		var finish := String(tile.thing.get("finish", ""))
		if tile.face.finish != finish:
			tile.face.set_finish(finish)
	elif tile.face != null:
		tile.face.visible = false


func _on_tile(tile: Control) -> void:
	var thing: Dictionary = tile.get("thing")
	match String(tile.get("role")):
		"give":
			withdrawn.emit(int(thing["ref"]))
		"offer":
			if thing.has("card"):
				var sent := thing.duplicate()
				sent["ref"] = _next_ref
				offered_cards[_next_ref] = sent
				_next_ref += 1
				offered.emit(sent)
			else:
				offered.emit(thing)


# The things to offer under the chosen tab.
func _fill_strip(mine: Array) -> void:
	for old in _strip.get_children():
		_strip.remove_child(old)
		old.queue_free()
	var things: Array = []  # [thing, copies]
	if _tab == "bag":
		var on_table := {}
		for thing: Dictionary in mine:
			if thing.has("ref"):
				on_table[int(thing["ref"])] = true
		for slot in InventoryState.SIZE:
			var thing := _thing_in(slot)
			if not thing.is_empty() and not on_table.has(slot):
				things.append([thing, 0])
	elif _cards != null and _card_db != null:
		var on_table := {}
		for thing: Dictionary in mine:
			if thing.has("card"):
				var key := "%s|%s|%s" % [thing["card"], thing["finish"], thing["leader"]]
				on_table[key] = int(on_table.get(key, 0)) + 1
		for pair: Array in [[_cards.get("leaders"), true], [_cards.get("cards"), false]]:
			var book: Dictionary = pair[0]
			for id: String in book:
				for f: String in book[id]:
					var left := int(book[id][f]) - int(on_table.get("%s|%s|%s" % [id, f, pair[1]], 0))
					if left > 0:
						things.append([{"card": id, "finish": f, "leader": pair[1]}, left])
	for entry: Array in things:
		var t := Tile.new()
		t.screen = self
		t.role = "offer"
		t.thing = entry[0]
		t.count = int(entry[1])
		t.clicked.connect(_on_tile)
		_strip.add_child(t)
		_dress_card(t)


func _bag_things(things: Array) -> int:
	var n := 0
	for thing: Dictionary in things:
		if not thing.has("card"):
			n += 1
	return n


# The tradable thing in a bag slot: a rolled gun or one piece of armour ({} = nothing to trade there).
func _thing_in(slot: int) -> Dictionary:
	var gun := _inventory.gun_at(slot)
	if not gun.is_empty():
		return {"ref": slot, "gun": gun}
	var id := _inventory.item_id(slot)
	if id != "" and String(_items.call("equip_slot", id)) != "":
		return {"ref": slot, "id": id}
	return {}


func _free_slots() -> int:
	var free := 0
	for slot in InventoryState.SIZE:
		if _inventory.item_id(slot) == "":
			free += 1
	return free


func _colour_of(thing: Dictionary) -> Color:
	if thing.has("card"):
		return RARITY_COLORS.get("legendary" if bool(thing["leader"]) else String(_card_db.card(String(thing["card"])).get("rarity", "common")), Color.WHITE)
	if thing.has("gun"):
		return TierStyle.color(_gun_db, String((thing["gun"] as Dictionary)["tier"]), Time.get_ticks_msec() / 1000.0)
	return Color(0.9, 0.9, 0.9)


func _draw_tile(tile: Tile) -> void:
	var r := Rect2(Vector2.ZERO, tile.size)
	var back := StyleBoxFlat.new()
	back.set_corner_radius_all(8)
	if tile.thing.is_empty():
		back.bg_color = Color(1, 1, 1, 0.03)
		back.border_color = Color(1, 1, 1, 0.12)
		back.set_border_width_all(1)
		tile.draw_style_box(back, r)
		return
	var c := _colour_of(tile.thing)
	back.bg_color = Color(c, 0.14 if tile.lit else 0.08).darkened(0.4)
	back.border_color = c
	back.set_border_width_all(3 if tile.lit else 2)
	tile.draw_style_box(back, r)
	if tile.thing.has("gun"):
		var gun: Dictionary = tile.thing["gun"]
		ItemIcons.draw(tile, String(gun["body"]), Rect2(6, 26, r.size.x - 12, 40), c)
		tile.draw_rect(Rect2(10, r.size.y - 14, r.size.x - 20, 5), c)  # the tier band
	elif tile.thing.has("id"):
		ItemIcons.draw(tile, String(tile.thing["id"]), Rect2(8, 16, r.size.x - 16, r.size.y - 32), Color.WHITE)
	if tile.count > 1:
		var t := "x%d" % tile.count
		tile.draw_string_outline(_font, Vector2(r.size.x - 30, r.size.y - 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color.BLACK)
		tile.draw_string(_font, Vector2(r.size.x - 30, r.size.y - 6), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.9, 0.5))
	if tile.lit and tile.role == "give":  # click takes it back
		tile.draw_circle(Vector2(r.size.x - 10, 10), 10, Color(0.8, 0.15, 0.1))
		IconArt.draw(tile, "cross", Rect2(r.size.x - 18, 2, 16, 16), Color.WHITE)
	elif tile.lit and tile.role == "offer":  # click puts it on the table
		tile.draw_circle(Vector2(r.size.x - 10, 10), 10, Color(0.15, 0.55, 0.2))
		IconArt.draw(tile, "arrow", Rect2(r.size.x - 18, 2, 16, 16), Color.WHITE)


func _draw_board() -> void:
	var tray := Vector2(4 * TILE.x + 3 * GAP, 2 * TILE.y + GAP)
	var with := String(_view.get("with", "?"))
	_board.draw_string(_font, Vector2(0, 40), "TRADE WITH %s" % with.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, W, 30, Color(1, 0.9, 0.6))
	for side: Array in [[GIVE_AT, GIVE, "YOU GIVE", bool(_view.get("ready_mine", false)), bool(_view.get("confirmed_mine", false))],
			[GET_AT, GET, "YOU GET", bool(_view.get("ready_theirs", false)), false]]:
		var at: Vector2 = side[0]
		var col: Color = side[1]
		var ready: bool = side[3]
		var frame := Rect2(at - Vector2(14, 14), tray + Vector2(28, 28))
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(14)
		box.bg_color = Color(col, 0.07)
		box.border_color = OK if ready else Color(col, 0.7)
		box.set_border_width_all(4 if ready else 2)
		if ready:
			box.shadow_color = Color(OK, 0.35)
			box.shadow_size = 12
		_board.draw_style_box(box, frame)
		_board.draw_string(_font, at + Vector2(0, -22), String(side[2]), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
		# the tick under the tray: green check when ready, an hourglass while choosing
		var pill := Rect2(Vector2(frame.get_center().x - 80, frame.end.y + 10), Vector2(160, 34))
		var p := StyleBoxFlat.new()
		p.set_corner_radius_all(17)
		p.bg_color = Color(OK, 0.25) if ready else Color(1, 1, 1, 0.06)
		_board.draw_style_box(p, pill)
		IconArt.draw(_board, "check" if ready else "clock", Rect2(pill.position + Vector2(10, 4), Vector2(26, 26)), OK if ready else Color(0.7, 0.7, 0.75))
		var who := "YOU" if side[2] == "YOU GIVE" else with.to_upper()
		_board.draw_string(_font, pill.position + Vector2(44, 24), ("%s: OK" % who) if ready else who, HORIZONTAL_ALIGNMENT_LEFT, 110, 16, OK if ready else Color(1, 1, 1, 0.6))
		if bool(side[4]):  # confirmed: a gold seal on the tray
			_board.draw_circle(frame.end - Vector2(6, 6), 18, Color(1.0, 0.8, 0.3))
			IconArt.draw(_board, "star", Rect2(frame.end - Vector2(20, 20), Vector2(28, 28)), Color(0.5, 0.3, 0.0))
	# the swap arrows between the trays
	var mid := Vector2(W * 0.5, GIVE_AT.y + tray.y * 0.5)
	for k: Array in [[-1.0, GIVE, -14.0], [1.0, GET, 14.0]]:
		var dir: float = k[0]
		var y := mid.y + float(k[2])
		var a := Vector2(mid.x - 34.0 * dir, y)
		var b := Vector2(mid.x + 34.0 * dir, y)
		var c: Color = k[1]
		_board.draw_line(a, b, c, 5.0)
		_board.draw_colored_polygon(PackedVector2Array([b + Vector2(10 * dir, 0), b + Vector2(-6 * dir, -9), b + Vector2(-6 * dir, 9)]), c)
	# status
	IconArt.draw(_board, _status_icon, Rect2(76, 603, 34, 34), Color(1.0, 0.85, 0.5))
	_board.draw_string(_font, Vector2(118, 628), _status, HORIZONTAL_ALIGNMENT_LEFT, 370, 17, Color(1.0, 0.9, 0.65))
