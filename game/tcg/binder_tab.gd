# Purpose: the BINDER tab of the player card (locked: 4 x 4 pockets a page, page flip, missing cards as faint outlines
# with their number, sort / filter, five deck slots, deck builder). A leather binder open on two pages; drag across a
# page, use the arrow keys, the mouse wheel or the < > buttons to turn; hovering a card shows it big. "Decks" opens
# the five slots: pick one and the binder becomes the deck builder (click a card to put it in, click a row of the
# list to take it out, click a leader to lead the deck; mana curve and whether the deck can be played).
# "Open packs" starts the pack opening over the whole screen (game/tcg/pack_opening.gd). "Play mats" lists every mat
# (owned ones to pick for your half of the table, locked ones dim with how they come; core/tcg/mat_book.gd).
# Dependencies: core/tcg/binder_list.gd, core/tcg/deck_edit.gd, game/tcg/card_face.gd, game/tcg/card_shine.gd, game/tcg/pack_opening.gd, data/tcg/packs.json;
# db (core/tcg/card_db.gd) and owned (core/tcg/collection.gd) handed in by build().
extends VBoxContainer

const BinderList = preload("res://core/tcg/binder_list.gd")
const DeckEdit = preload("res://core/tcg/deck_edit.gd")
const CardFace = preload("res://game/tcg/card_face.gd")
const PackOpening = preload("res://game/tcg/pack_opening.gd")
const MatBook = preload("res://core/tcg/mat_book.gd")

signal changed  # a deck slot was saved, or packs were opened

const PER_PAGE := 16
const COLS := 4
const ASPECT := 600.0 / 840.0
const FACTIONS := ["tide", "waste", "crypt", "aurelind", "club", "neutral"]
const LEATHER := Color(0.27, 0.15, 0.08)
const PAGE := Color(0.09, 0.09, 0.1)
const GOLD := Color(1.0, 0.82, 0.4)

var db: RefCounted
var owned: RefCounted

var _filter: Dictionary = BinderList.ALL.duplicate()
var _list: Array = []
var _first := 0  # index of the left page
var _turning := false
var _spread: Spread
var _pages: Array = []  # two Page
var _float: Control  # big hover card in the builder, over the other page
var _page_label := Label.new()
var _preview: Control
var _info := Label.new()
var _browse_panel := VBoxContainer.new()
var _deck_panel := VBoxContainer.new()
var _slots := HBoxContainer.new()
var _name := LineEdit.new()
var _leader_label := Label.new()
var _rows := VBoxContainer.new()
var _curve: ManaCurve
var _status := Label.new()
var _open_button: Button
var _mat_panel := VBoxContainer.new()
var _mat_list := VBoxContainer.new()
var _mats_cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/mats.json"))
var _opening: Control
var _slot := -1  # deck slot being built, -1 = just browsing
var _deck: Dictionary = {}


# One page: 16 plastic pockets; owned cards are card faces, missing ones a faint outline with the set number.
class Page extends Control:
	var entries: Array = []
	var faces: Array = []
	var badges: Array = []  # text under each face ("x2", "1/2")
	var tints: Array = []  # faction colour of each missing outline
	var cell := Vector2.ZERO
	var origin := Vector2.ZERO
	var gap := 6.0

	func pocket(i: int) -> Rect2:
		return Rect2(origin + Vector2(i % 4, floori(i / 4.0)) * (cell + Vector2(gap, gap)), cell)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.09, 0.1))
		var f: Font = CardFace.font("title")
		for i in 16:
			var r := pocket(i).grow(3)
			draw_rect(r, Color(1, 1, 1, 0.04))
			draw_line(r.position + Vector2(4, 4), r.position + Vector2(r.size.x * 0.4, 4), Color(1, 1, 1, 0.12), 1.0)  # the plastic's shine
			draw_rect(r, Color(1, 1, 1, 0.1), false, 1.0)
			if i < entries.size() and int(entries[i]["have"]) <= 0:
				var o := pocket(i).grow(-3)
				draw_rect(o, Color(tints[i], 0.08))
				draw_rect(o, Color(tints[i], 0.45), false, 1.5)
				var t := "#%03d" % int(entries[i]["no"])
				var fs := int(cell.x * 0.2)
				var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(f, Vector2(o.get_center().x - w * 0.5, o.get_center().y + fs * 0.35), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.35))



# Draws its page's badges over the card faces.
class Badges extends Control:
	var page: Control

	func _draw() -> void:
		var f: Font = CardFace.font("title")
		var badges: Array = page.get("badges")
		var cell: Vector2 = page.get("cell")
		for i in badges.size():
			if String(badges[i]) != "":
				var b := String(badges[i])
				var fs2 := int(cell.x * 0.16)
				var bw := f.get_string_size(b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2).x + 8
				var br := Rect2((page.call("pocket", i) as Rect2).end - Vector2(bw + 2, fs2 + 6), Vector2(bw, fs2 + 4))
				draw_rect(br, Color(0, 0, 0, 0.75))
				draw_string(f, br.position + Vector2(4, fs2), b, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(1.0, 0.85, 0.4))


# The open binder: leather, a spine with rings, two pages. Drag across it to turn.
class Spread extends Control:
	signal turn(dir: int)
	var press_x := -1.0
	var book := Rect2()  # where the binder lies (the rest of the area stays empty)

	func _draw() -> void:
		var r := book
		draw_rect(r, Color(0.27, 0.15, 0.08))
		draw_rect(r.grow(-5), Color(0.2, 0.11, 0.06), false, 2.0)
		var y := 4.0
		while y < size.y - 4:  # stitching
			draw_line(Vector2(r.position.x + 9, y), Vector2(r.position.x + 9, y + 5), Color(0.75, 0.6, 0.4, 0.5), 1.5)
			draw_line(Vector2(r.end.x - 9, y), Vector2(r.end.x - 9, y + 5), Color(0.75, 0.6, 0.4, 0.5), 1.5)
			y += 10
		var mid := r.get_center().x
		draw_rect(Rect2(mid - 11, 0, 22, size.y), Color(0.16, 0.09, 0.05))
		for k in 3:  # rings
			var cy := size.y * (0.2 + 0.3 * k)
			draw_arc(Vector2(mid, cy), 9, 0, TAU, 20, Color(0.75, 0.75, 0.8), 3.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
				turn.emit(1)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
				turn.emit(-1)
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.pressed:
					press_x = mb.position.x
				elif press_x >= 0.0:
					var dx := mb.position.x - press_x
					press_x = -1.0
					if absf(dx) > 60.0:
						turn.emit(1 if dx < 0.0 else -1)


# One play mat in the list: its picture, name and (locked) how it comes.
class MatTile extends Control:
	signal picked(id: String)
	var id := ""
	var title := ""
	var note := ""
	var owned := false
	var chosen := false
	var tex: Texture2D

	func _init() -> void:
		custom_minimum_size = Vector2(266, 128)

	func _gui_input(event: InputEvent) -> void:
		if owned and event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			picked.emit(id)

	func _draw() -> void:
		var r := Rect2(Vector2(4, 4), size - Vector2(8, 30))
		if tex != null:
			draw_texture_rect(tex, r, false, Color.WHITE if owned else Color(0.35, 0.35, 0.4))
		draw_rect(r, Color(1.0, 0.82, 0.4) if chosen else Color(1, 1, 1, 0.25), false, 4.0 if chosen else 1.0)
		var f: Font = CardFace.font("title")
		draw_string(f, Vector2(6, size.y - 8), title + ("  (in use)" if chosen else ""), HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, 14, Color.WHITE if owned else Color(1, 1, 1, 0.5))
		if not owned:
			draw_string(f, r.get_center() + Vector2(-r.size.x * 0.45, 5), note, HORIZONTAL_ALIGNMENT_CENTER, r.size.x * 0.9, 13, Color(1.0, 0.85, 0.5))


# The mana curve: one bar per cost, 0 ... 8+.
class ManaCurve extends Control:
	var values: Array = []

	func _init() -> void:
		custom_minimum_size = Vector2(0, 78)

	func _draw() -> void:
		var f: Font = CardFace.font("number")
		var top := 1
		for v: int in values:
			top = maxi(top, v)
		var w := size.x / maxf(values.size(), 1)
		for i in values.size():
			var h := (size.y - 30) * float(values[i]) / float(top)  # room above the tallest bar for its number
			var r := Rect2(i * w + 3, size.y - 16 - h, w - 6, h)
			draw_rect(r, Color(0.3, 0.55, 1.0))
			if int(values[i]) > 0:
				draw_string(f, Vector2(r.position.x, r.position.y - 2), str(values[i]), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11, Color.WHITE)
			draw_string(f, Vector2(i * w, size.y - 2), ("%d+" % i) if i == values.size() - 1 else str(i), HORIZONTAL_ALIGNMENT_CENTER, w, 11, Color(1, 1, 1, 0.6))


func build(card_db: RefCounted, collection: RefCounted) -> void:
	db = card_db
	owned = collection
	add_theme_constant_override("separation", 6)
	add_child(_filters())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	_spread = Spread.new()
	_spread.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spread.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spread.turn.connect(_flip)
	_spread.resized.connect(_layout)
	left.add_child(_spread)
	for p in 2:
		var page := Page.new()
		page.mouse_filter = Control.MOUSE_FILTER_PASS
		_spread.add_child(page)
		_pages.append(page)
		for i in PER_PAGE:
			var face := CardFace.new()
			face.visible = false
			face.pressed.connect(_on_card)
			face.hovered.connect(_on_hover)
			page.add_child(face)
			face.mouse_filter = Control.MOUSE_FILTER_PASS  # after its _ready: drags over cards still turn the page
			page.faces.append(face)
		var over := Badges.new()
		over.page = page
		page.add_child(over)
		over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_float = CardFace.new()
	_float.visible = false
	_spread.add_child(_float)
	_float.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var turn_row := HBoxContainer.new()
	turn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	left.add_child(turn_row)
	_button(turn_row, "<", func() -> void: _flip(-1))
	_page_label.custom_minimum_size = Vector2(150, 0)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_row.add_child(_page_label)
	_button(turn_row, ">", func() -> void: _flip(1))
	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(290, 0)
	body.add_child(side)
	var stack := VBoxContainer.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(stack)
	_build_browse(stack)
	_build_deck(stack)
	refresh()


func _filters() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var tribe_names: Array = [["Any tribe", ""]]
	for t: String in BinderList.tribes(db):
		tribe_names.append([t.capitalize(), t])
	var costs: Array = [["Any cost", -1]]
	for c in 9:
		costs.append([("%d+" % c) if c == 8 else str(c), c])
	var faction_names: Array = [["All factions", ""]]
	for f: String in FACTIONS:
		faction_names.append([f.capitalize(), f])
	for spec: Array in [["faction", faction_names], ["cost", costs],
			["rarity", [["Any rarity", ""], ["Common", "common"], ["Rare", "rare"], ["Epic", "epic"], ["Legendary", "legendary"]]],
			["type", [["Any type", ""], ["Creatures", "creature"], ["Spells", "spell"], ["Tells", "trap"], ["Leaders", "leader"]]],
			["tribe", tribe_names],
			["show", [["Owned and missing", "all"], ["Owned", "owned"], ["Missing", "missing"]]],
			["sort", [["By number", "number"], ["By cost", "cost"], ["By rarity", "rarity"], ["By name", "name"], ["Newest", "newest"]]]]:
		var pick := OptionButton.new()
		var key: String = spec[0]
		for item: Array in spec[1]:
			pick.add_item(String(item[0]))
			pick.set_item_metadata(pick.item_count - 1, item[1])
		pick.item_selected.connect(func(i: int) -> void:
			_filter[key] = pick.get_item_metadata(i)
			_first = 0
			refresh())
		row.add_child(pick)
	return row


func _build_browse(stack: VBoxContainer) -> void:
	stack.add_child(_browse_panel)
	_preview = CardFace.new()
	_preview.custom_minimum_size = Vector2(240, 336)
	_preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_preview.visible = false
	_browse_panel.add_child(_preview)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.text = "Hover a card to see it."
	_browse_panel.add_child(_info)
	_open_button = _button(_browse_panel, "Open packs", func() -> void:
		_opening.call("open", db, owned, JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/packs.json"))))
	_button(_browse_panel, "Decks", func() -> void: _open_slots())
	_button(_browse_panel, "Play mats", func() -> void: _show_mats())
	stack.add_child(_mat_panel)
	_mat_panel.visible = false
	_mat_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var mat_scroll := ScrollContainer.new()
	mat_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mat_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mat_scroll.add_child(_mat_list)
	_mat_panel.add_child(mat_scroll)
	_button(_mat_panel, "Back", func() -> void:
		_mat_panel.visible = false
		_browse_panel.visible = true)
	var layer := CanvasLayer.new()  # over the whole menu, Close button included
	layer.layer = 60
	add_child(layer)
	_opening = PackOpening.new()
	layer.add_child(_opening)
	_opening.connect("changed", func() -> void: changed.emit())
	_opening.connect("closed", refresh)


func _build_deck(stack: VBoxContainer) -> void:
	stack.add_child(_deck_panel)
	_deck_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_deck_panel.visible = false
	_slots.add_theme_constant_override("separation", 4)
	_deck_panel.add_child(_slots)
	_name.placeholder_text = "Deck name"
	_name.text_changed.connect(func(t: String) -> void: _deck["name"] = t)
	_deck_panel.add_child(_name)
	_deck_panel.add_child(_leader_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 150)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 1)
	scroll.add_child(_rows)
	_deck_panel.add_child(scroll)
	_curve = ManaCurve.new()
	_deck_panel.add_child(_curve)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deck_panel.add_child(_status)
	var buttons := HBoxContainer.new()
	_deck_panel.add_child(buttons)
	_button(buttons, "Save", _save_deck)
	_button(buttons, "Clear", func() -> void:
		_deck["cards"] = []
		_show_deck())
	_button(buttons, "Done", func() -> void: _leave_deck())


func _button(box: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if box is HBoxContainer and text.length() > 1 else Control.SIZE_SHRINK_CENTER
	b.pressed.connect(on_press)
	box.add_child(b)
	return b


# Re-reads the collection (cards bought or traded since) and shows the current pages.
func refresh() -> void:
	if db == null:
		return
	var packs: int = owned.pack_count()
	_open_button.text = "Open packs (%d)" % packs
	_open_button.disabled = packs <= 0
	_list = BinderList.entries(db, owned, _filter)
	_first = clampi(_first, 0, maxi(_page_count() - 1, 0))
	_first -= _first % 2
	_show_pages()


# A canvas layer does not hide with the menu: the opening closes when the binder goes out of sight (menu closed, other tab).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _opening != null and _opening.visible and not is_visible_in_tree():
		_opening.call("close")


func _page_count() -> int:
	return maxi(ceili(_list.size() / float(PER_PAGE)), 1)


func _layout() -> void:
	var margin := 12.0
	var spine := 22.0
	var pad := 8.0
	var gap: float = (_pages[0] as Page).gap
	var room := (_spread.size.x - 2 * margin - spine) * 0.5  # widest a page may be
	var ph := _spread.size.y - 2 * margin
	var ch := (ph - 2 * pad - 3 * gap) / 4.0
	var cw := ch * ASPECT
	if 4 * cw + 3 * gap + 2 * pad > room:
		cw = (room - 2 * pad - 3 * gap) / 4.0
		ch = cw / ASPECT
	var pw := 4 * cw + 3 * gap + 2 * pad
	var left := (_spread.size.x - 2 * pw - spine - 2 * margin) * 0.5
	_spread.book = Rect2(left, 0, 2 * pw + spine + 2 * margin, _spread.size.y)
	_spread.queue_redraw()
	for p in 2:
		var page: Page = _pages[p]
		page.position = Vector2(left + margin + p * (pw + spine), margin)
		page.size = Vector2(pw, ph)
		page.cell = Vector2(cw, ch)
		page.origin = (page.size - Vector2(4 * cw + 3 * page.gap, 4 * ch + 3 * page.gap)) * 0.5
		for i in PER_PAGE:
			var face: Control = page.faces[i]
			var r := page.pocket(i)
			face.position = r.position
			face.size = r.size
			if face.finish != "":  # the foil shine is made for the face's size
				face.set_finish(face.finish)
		var over: Control = page.get_child(page.get_child_count() - 1)
		over.size = page.size
		page.queue_redraw()
	_float.size = Vector2(ph * ASPECT, ph) * 0.92
	_show_pages()


func _show_pages() -> void:
	if _pages.is_empty():
		return
	for p in 2:
		var page: Page = _pages[p]
		var start := (_first + p) * PER_PAGE
		page.entries = _list.slice(start, start + PER_PAGE)
		page.badges = []
		page.tints = []
		for i in PER_PAGE:
			var face: Control = page.faces[i]
			if i >= page.entries.size():
				face.visible = false
				page.badges.append("")
				page.tints.append(Color.WHITE)
				continue
			var e: Dictionary = page.entries[i]
			var facts := BinderList.facts(db, String(e["id"]), bool(e["leader"]))
			page.tints.append(CardFace.FACTION_COLORS.get(facts["faction"], Color.GRAY))
			var have := int(e["have"])
			face.visible = have > 0
			if have > 0:
				face.show_card(db, String(e["id"]))
				var best := ""
				for f: String in ["rainbow", "pony"]:
					if owned.count(String(e["id"]), f, bool(e["leader"])) > 0:
						best = f
				if face.finish != best and face.size.x > 0.0:
					face.set_finish(best)
				face.slot = start + i
			var badge := ""
			if _slot >= 0 and not bool(e["leader"]):
				var used := (_deck.get("cards", []) as Array).count(String(e["id"]))
				badge = "%d/%d" % [used, have] if have > 0 else ""
				face.mark(GOLD if used > 0 else Color(0, 0, 0, 0))
			elif _slot >= 0:
				badge = "LEADER" if String(_deck.get("leader", "")) == String(e["id"]) else ""
				face.mark(GOLD if badge != "" else Color(0, 0, 0, 0))
			else:
				badge = "x%d" % have if have > 1 else ""
				face.mark(Color(0, 0, 0, 0))
			page.badges.append(badge)
		page.queue_redraw()
		(page.get_child(page.get_child_count() - 1) as Control).queue_redraw()
	var pages := _page_count()
	_page_label.text = "Pages %d-%d of %d" % [_first + 1, mini(_first + 2, pages), pages] if pages > 1 else "Page 1 of 1"
	if _list.is_empty():
		_page_label.text = "No cards match"


func _flip(dir: int) -> void:
	var next := _first + 2 * dir
	if _turning or next < 0 or next >= _page_count():
		return
	_turning = true
	_float.visible = false
	var leaving: Page = _pages[1] if dir > 0 else _pages[0]
	var coming: Page = _pages[0] if dir > 0 else _pages[1]
	leaving.pivot_offset = Vector2(0.0 if dir > 0 else leaving.size.x, 0.0)  # the spine side
	coming.pivot_offset = Vector2(coming.size.x if dir > 0 else 0.0, 0.0)
	var t := create_tween()
	t.tween_property(leaving, "scale:x", 0.0, 0.13).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(leaving, "modulate", Color(0.5, 0.5, 0.5), 0.13)
	t.tween_callback(func() -> void:
		_first = next
		_show_pages()
		leaving.scale.x = 1.0
		leaving.modulate = Color.WHITE
		coming.scale.x = 0.0
		coming.modulate = Color(0.5, 0.5, 0.5))
	t.tween_property(coming, "scale:x", 1.0, 0.13).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(coming, "modulate", Color.WHITE, 0.13)
	t.tween_callback(func() -> void: _turning = false)


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or _name.has_focus():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_LEFT or key == KEY_RIGHT:
		_flip(-1 if key == KEY_LEFT else 1)
		get_viewport().set_input_as_handled()


func _entry(face: Control) -> Dictionary:
	var at: int = face.slot
	return _list[at] if at >= 0 and at < _list.size() else {}


func _on_hover(face: Control, on: bool) -> void:
	var e := _entry(face)
	if not on or e.is_empty():
		_float.visible = false
		return
	if _slot >= 0:  # builder: the big card over the other page
		var right: bool = face.get_parent() == _pages[1]
		var other: Page = _pages[0] if right else _pages[1]
		_float.show_card(db, String(e["id"]))
		_float.position = other.position + (other.size - _float.size) * 0.5
		_float.visible = true
		return
	_preview.show_card(db, String(e["id"]))
	_preview.visible = true
	var lines := ["#%03d" % int(e["no"])]
	var parts: Array = []
	for f: String in ["", "rainbow", "pony"]:
		var n: int = owned.count(String(e["id"]), f, bool(e["leader"]))
		if n > 0:
			parts.append("%d %s" % [n, "plain" if f == "" else f])
	lines.append("Owned: " + ", ".join(parts))
	_info.text = "\n".join(lines)


func _on_card(face: Control, _right: bool) -> void:
	var e := _entry(face)
	if _slot < 0 or e.is_empty():
		return
	var why: String
	if bool(e["leader"]):
		why = DeckEdit.set_leader(db, owned, _deck, String(e["id"]))
	else:
		why = DeckEdit.add(db, owned, _deck, String(e["id"]))
	_show_deck(why)


# ---- play mats ----

func _show_mats() -> void:
	_browse_panel.visible = false
	_mat_panel.visible = true
	for child in _mat_list.get_children():
		_mat_list.remove_child(child)
		child.queue_free()
	var now := MatBook.current(owned, _mats_cfg)
	for id: String in _mats_cfg["mats"]:
		var t := MatTile.new()
		t.id = id
		t.title = String(_mats_cfg["mats"][id]["name"])
		t.note = MatBook.how(_mats_cfg, id)
		t.owned = MatBook.owns(owned, _mats_cfg, id)
		t.chosen = id == now
		var pic := "res://assets/tcg/mats/%s.jpg" % id
		t.tex = load(pic) as Texture2D if ResourceLoader.exists(pic) else null  # not cached: twelve big pictures
		t.tooltip_text = t.note
		t.picked.connect(func(which: String) -> void:
			MatBook.choose(owned, _mats_cfg, which)
			changed.emit()
			_show_mats())
		_mat_list.add_child(t)


# ---- decks ----

func _open_slots() -> void:
	_browse_panel.visible = false
	_deck_panel.visible = true
	_fill_slots()
	if _slot < 0:
		_pick_slot(0)


func _fill_slots() -> void:
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	var decks: Array = owned.get("decks")
	for i in decks.size():
		var d: Dictionary = decks[i]
		var b := Button.new()
		b.text = str(i + 1)
		b.tooltip_text = String(d.get("name", "Empty slot")) if not d.is_empty() else "Empty slot"
		b.toggle_mode = true
		b.button_pressed = i == _slot
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.modulate = Color.WHITE if not d.is_empty() else Color(1, 1, 1, 0.55)
		b.pressed.connect(func() -> void: _pick_slot(i))
		_slots.add_child(b)


func _pick_slot(i: int) -> void:
	_slot = i
	var saved: Dictionary = (owned.get("decks") as Array)[i]
	_deck = saved.duplicate(true) if not saved.is_empty() else {"name": "Deck %d" % (i + 1), "leader": "", "cards": []}
	_name.text = String(_deck.get("name", ""))
	_fill_slots()
	_show_deck()


func _show_deck(why := "") -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var leader: Dictionary = (db.get("leaders") as Dictionary).get(String(_deck.get("leader", "")), {})
	_leader_label.text = "Leader: %s" % leader.get("name", "none - click a leader card") if not leader.is_empty() else "Leader: none - click a leader card"
	var counts := {}
	for id: Variant in _deck.get("cards", []):
		counts[String(id)] = int(counts.get(String(id), 0)) + 1
	var ids: Array = counts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return [int(db.card(a)["cost"]), String(db.card(a).get("name", a))] < [int(db.card(b)["cost"]), String(db.card(b).get("name", b))])
	for id: String in ids:
		var row := Button.new()
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = "%d   %s%s" % [int(db.card(id)["cost"]), db.card(id).get("name", id), "  x%d" % counts[id] if int(counts[id]) > 1 else ""]
		row.tooltip_text = "Click to take one out"
		row.pressed.connect(func() -> void:
			DeckEdit.remove(_deck, id)
			_show_deck())
		_rows.add_child(row)
	_curve.values = DeckEdit.curve(db, _deck)
	_curve.queue_redraw()
	var size_now := (_deck.get("cards", []) as Array).size()
	var problem := DeckEdit.problem(db, owned, _deck)
	if why != "":
		_status.text = why
		_status.modulate = Color(1.0, 0.6, 0.4)
	elif problem == "":
		_status.text = "%d / %d cards - ready to play" % [size_now, int(db.get("rules")["deck_size"])]
		_status.modulate = Color(0.5, 1.0, 0.5)
	else:
		_status.text = "%d / %d cards - %s" % [size_now, int(db.get("rules")["deck_size"]), problem]
		_status.modulate = Color(1.0, 0.85, 0.5)
	_show_pages()


func _save_deck() -> void:
	var empty := String(_deck.get("leader", "")) == "" and (_deck.get("cards", []) as Array).is_empty()
	owned.set_deck(_slot, {} if empty else _deck.duplicate(true))
	_fill_slots()
	_status.text = "Saved." if not empty else "Slot emptied."
	_status.modulate = Color(0.5, 1.0, 0.5)
	changed.emit()


func _leave_deck() -> void:
	_slot = -1
	_deck = {}
	_float.visible = false
	_deck_panel.visible = false
	_browse_panel.visible = true
	_show_pages()
