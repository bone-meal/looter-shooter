# Purpose: the inventory screen, laid out like a looter shooter's (director's choice 2026-11-14, diary/DECISIONS_SEA.md):
# full screen; a header with the tabs Guns / Gear / Items / All and a sort button; LEFT the character (3D portrait) with
# the 18 gear slots round it (at the bank: the bank's slots instead, core/bank_state.gd); MIDDLE the READY guns as big
# gun cards with the knife, and the BACKPACK (36 slots, filtered and sorted by the tabs); RIGHT the chosen item's card
# DOCKED (game/inventory_card.gd) with Equip / Wear / Unequip / Drop buttons; a bottom bar with chips, points and keys.
# Click to pick up / place / swap / wear, right click for half or one; the drop key (or carrying a gun out of the window
# and clicking) lays a rolled gun on the ground (signal `dropped`); holding Shift shows the gun in hand on the card.
# Dependencies: core/inventory_state.gd, core/item_db.gd, core/gun_db.gd, game/item_icons.gd, game/icon_art.gd,
# game/ui_skin.gd, game/inventory_card.gd, game/portrait_view.gd, game/tier_style.gd, core/gun_stats.gd. Emits `changed`
# after every change so the player re-reads the held item.
extends Control

const IconArt = preload("res://game/icon_art.gd")
const ItemIcons = preload("res://game/item_icons.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunStats = preload("res://core/gun_stats.gd")
const TierStyle = preload("res://game/tier_style.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const InventoryCard = preload("res://game/inventory_card.gd")
const PortraitView = preload("res://game/portrait_view.gd")

signal changed
signal dropped(gun: Dictionary)  # a rolled gun left the inventory: the session lays it on the ground
signal bank_upgrade  # the bank's "more slots" button was clicked: the session takes the price and upgrades it

const EQUIP_BASE := 100  # slot indices >= this are equipment slots (index - EQUIP_BASE into EQUIP_SLOTS)
const HOLSTER_BASE := 200  # slot indices >= this are holsters
const KNIFE_SLOT := 300  # the knife's card
const BANK_BASE := 400  # slot indices >= this are the bank's
const BANK_BUTTON := 900  # the bank's "more slots" button
const TAB_BASE := 1000  # the header's tabs
const SORT_BUTTON := 1100
const CLOSE_BUTTON := 1200
const COLUMNS := 9
const GAP := 8.0
const PAD := 22.0
const TABS := [["guns", "Guns"], ["gear", "Gear"], ["items", "Items"], ["all", "All"]]
const SORTS := [["slot", "Bag order"], ["tier", "Rarity"], ["level", "Item level"], ["type", "Type"]]
const SLOT_LABELS := {"hat": "Hat", "head": "Head", "earrings": "Ears", "necklace": "Neck", "glasses": "Eyes", "mouth": "Mouth", "shirt": "Shirt", "chestplate": "Chest", "gauntlets": "Hands", "ring_1": "Ring", "ring_2": "Ring", "bracelet": "Wrist", "pants": "Pants", "leg_armor": "Legs", "cape": "Cape", "waist": "Belt", "boots": "Boots", "foot_armor": "Feet"}

var inventory: InventoryState  # set before add_child
var items: ItemDb  # set before add_child
var gun_db: GunDb  # set before add_child (rolled guns: colours, names, stats)
var in_hand := 0  # which holster is in the player's hand (-1 = the knife), set by the session: that card is lit
var knife := "combat"  # the knife type carried, set by the session
var knife_name := ""
var knife_key := ""  # the labels of the keys that take a gun or the knife in hand, set by the session
var gun_keys: Array[String] = []
var bank: RefCounted  # core/bank_state.gd while the window is open AT the bank (its slots show on the left), else null
var bank_price := ""  # what the next bank upgrade costs, worded by the session ("" = no upgrade left)
var chips := -1  # casino chips and points for the bottom bar (set by the session when it opens the window; -1 = hide)
var points := -1
var look := {}  # the character's look for the portrait

var tab := "all"
var sort_by := "slot"
var _mouse := Vector2.ZERO
var _font: Font = ThemeDB.fallback_font
var _focus := -1  # the slot whose card is docked on the right (it stays after the mouse leaves)
var _order: Array[int] = []  # the backpack as shown: cell -> real slot (-1 = an empty cell)
var _buttons: Array = []  # the card's buttons from the last frame: [[Rect2, action]]
var _portrait: PortraitView
var _shown_look := {}
# Three layers, each drawn again only when it must: the window itself (everything still: slots, cards, bars) when what
# it shows changes; the docked card (game/inventory_card.gd) when its item changes, the mouse is over it or its colour
# moves; and a thin top layer (hover and chosen outlines, the stack on the mouse) when the mouse moves.
var _card_layer := Control.new()
var _top := Control.new()
var _drawn_mouse := Vector2(-1, -1)
var _since_check := 0.0
var _since_card := 0.0
var _base_sig := 0  # what the window showed when it was last drawn (a hash of the bag, holsters, gear, mouse stack...)
var _card_moves := false  # the card shows a rainbow / pony colour
var _shift := false
const CHECK_EVERY := 0.25  # seconds between looks for changes made from outside (ammo, pickups, chips)
const CARD_ANIMATED := 1.0 / 15.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_portrait = PortraitView.new()
	_portrait.custom_minimum_size = Vector2.ZERO  # it fits between the gear columns
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	for layer: Control in [_card_layer, _top]:
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_layer.draw.connect(_draw_card_layer)
	_top.draw.connect(_draw_top)


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if look != _shown_look:
		_shown_look = look.duplicate(true)
		_portrait.show_look(look)
	_redraw_all()


# Returns the stack on the mouse to the inventory, then hides.
func close() -> void:
	inventory.return_cursor()
	bank = null
	visible = false
	changed.emit()


# Rebuilding the whole window every frame cost ~20 ms on the 1080 in a debug run, so only what changed is drawn again.
func _process(delta: float) -> void:
	if not visible:
		return
	_since_check += delta
	_since_card += delta
	if _since_check >= CHECK_EVERY:
		_since_check = 0.0
		if _signature() != _base_sig:
			_redraw_all()
	var card := false
	if _mouse != _drawn_mouse:
		var over := _slot_at(_mouse)
		if (over == KNIFE_SLOT or _id_at(over) != "") and over != _focus:
			_focus = over  # the card stays on it after the mouse moves on
			card = true
		card = card or _columns()[2].has_point(_mouse) or _columns()[2].has_point(_drawn_mouse)  # its buttons light up
		_drawn_mouse = _mouse
		_top.queue_redraw()
	var shift := Input.is_key_pressed(KEY_SHIFT)
	if shift != _shift:
		_shift = shift
		card = true
	if card or (_card_moves and _since_card >= CARD_ANIMATED):
		_card_layer.queue_redraw()


func _redraw_all() -> void:
	_base_sig = _signature()
	queue_redraw()
	_card_layer.queue_redraw()
	_top.queue_redraw()


func _signature() -> int:
	return [inventory._slots, inventory.holsters, inventory.equipment, inventory.loaded, inventory.cursor, inventory.holster_count, in_hand, chips, points, tab, sort_by, bank != null, bank_price, knife_name, 0 if bank == null else int(bank.call("used"))].hash()


func _place_portrait() -> void:
	var place := _portrait_rect()
	_portrait.visible = bank == null and place.size.x > 40.0
	_portrait.position = place.position
	_portrait.size = place.size


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------- layout (all from the window's size)

# The layout is worked out once per window size (and holster count) and kept: the rects below are only read from it.
var _laid_for := Vector3(-1, -1, -1)
var _frame_r := Rect2()
var _cols: Array[Rect2] = []
var _cell_s := 0.0
var _equip_s := 0.0
var _card_w := 0.0
var _card_h := 0.0
var _bag_y := 0.0
var _grid_x := 0.0


func _layout() -> void:
	var view := get_viewport_rect().size
	var key := Vector3(view.x, view.y, inventory.holster_count)
	if key == _laid_for:
		return
	_laid_for = key
	var m := Vector2(maxf(view.x * 0.025, 16.0), maxf(view.y * 0.035, 14.0))
	_frame_r = Rect2(m, view - 2.0 * m)
	var f := _frame_r
	var top := f.position.y + 64.0 + 14.0
	var h := f.end.y - 50.0 - 14.0 - top
	var left_w := f.size.x * 0.25
	var right_w := f.size.x * 0.28
	var mid_w := f.size.x - left_w - right_w - 28.0
	_cols = [Rect2(f.position.x, top, left_w, h), Rect2(f.position.x + left_w + 14.0, top, mid_w, h), Rect2(f.end.x - right_w, top, right_w, h)]
	var mid := _cols[1]
	_cell_s = clampf((mid.size.x - 2.0 * PAD - GAP * float(COLUMNS - 1)) / float(COLUMNS), 36.0, 84.0)
	_equip_s = clampf(minf((_cols[0].size.y - 2.0 * PAD - 40.0) / 9.0 - GAP, _cols[0].size.x * 0.17), 30.0, 62.0)
	_card_w = (mid.size.x - 2.0 * PAD - GAP) * 0.5
	_card_h = clampf(_cell_s * 1.35, 70.0, 110.0)
	_bag_y = _holster_rect(inventory.holster_count).end.y + 26.0
	_grid_x = mid.position.x + PAD + (mid.size.x - 2.0 * PAD - (_cell_s + GAP) * float(COLUMNS) + GAP) * 0.5


func _frame() -> Rect2:
	_layout()
	return _frame_r


func _header() -> Rect2:
	var f := _frame()
	return Rect2(f.position, Vector2(f.size.x, 64.0))


func _footer() -> Rect2:
	var f := _frame()
	return Rect2(Vector2(f.position.x, f.end.y - 50.0), Vector2(f.size.x, 50.0))


# The three columns between header and footer: left (character), middle (ready + backpack), right (card).
func _columns() -> Array[Rect2]:
	_layout()
	return _cols


func _cell() -> float:  # one backpack slot's side
	_layout()
	return _cell_s


func _equip_cell() -> float:
	_layout()
	return _equip_s


func _portrait_rect() -> Rect2:
	_layout()
	var left := _cols[0]
	var x0 := left.position.x + PAD + _equip_s + 12.0
	return Rect2(x0, left.position.y + PAD + 40.0, left.end.x - PAD - _equip_s - 12.0 - x0, 9.0 * (_equip_s + GAP) - GAP)


func _equip_rect(k: int) -> Rect2:
	_layout()
	var left := _cols[0]
	var x := left.position.x + PAD if k < 9 else left.end.x - PAD - _equip_s
	return Rect2(x, left.position.y + PAD + 40.0 + float(k % 9) * (_equip_s + GAP), _equip_s, _equip_s)


func _holster_rect(i: int) -> Rect2:  # i == holster_count is the knife's card
	_layout()
	var mid := _cols[1]
	return Rect2(mid.position.x + PAD + float(i % 2) * (_card_w + GAP), mid.position.y + PAD + 40.0 + float(floori(float(i) / 2.0)) * (_card_h + GAP), _card_w, _card_h)


func _bag_top() -> float:
	_layout()
	return _bag_y


func _cell_rect(cell: int) -> Rect2:
	_layout()
	return Rect2(_grid_x + float(cell % COLUMNS) * (_cell_s + GAP), _bag_y + 40.0 + float(floori(float(cell) / float(COLUMNS))) * (_cell_s + GAP), _cell_s, _cell_s)


# The rect where a backpack slot is shown now (an empty Rect2 when the tab hides it).
func _slot_rect(i: int) -> Rect2:
	var cell := _order.find(i)
	return _cell_rect(cell) if cell >= 0 else Rect2()


func _tab_rect(k: int) -> Rect2:
	var h := _header()
	return Rect2(h.position.x + 250.0 + float(k) * 112.0, h.position.y + 14.0, 102.0, 36.0)


func _sort_rect() -> Rect2:
	var h := _header()
	return Rect2(h.end.x - 300.0, h.position.y + 14.0, 210.0, 36.0)


func _close_rect() -> Rect2:
	var h := _header()
	return Rect2(h.end.x - 76.0, h.position.y + 14.0, 60.0, 36.0)


func _bank_cell() -> float:
	return minf(_equip_cell(), 52.0)


func _bank_rect(i: int) -> Rect2:
	var left := _columns()[0]
	var s := _bank_cell()
	var per_row := maxi(1, floori((left.size.x - 2.0 * PAD + GAP) / (s + GAP)))
	return Rect2(left.position.x + PAD + float(i % per_row) * (s + GAP), left.position.y + PAD + 40.0 + float(floori(float(i) / float(per_row))) * (s + GAP), s, s)


func _bank_button() -> Rect2:
	var left := _columns()[0]
	return Rect2(left.position.x + PAD, left.end.y - PAD - 40.0, left.size.x - 2.0 * PAD, 40.0)


# ---------------------------------------------------------------- what is where

# The backpack as shown: the tab's matches in the sort order, then the empty slots (so things can be put down).
func _make_order() -> void:
	if tab == "all" and sort_by == "slot":  # the bag as it is
		if _order.size() != inventory.SIZE or _order[inventory.SIZE - 1] != inventory.SIZE - 1:
			_order.clear()
			for i in inventory.SIZE:
				_order.append(i)
		return
	var hits: Array[int] = []
	var empty: Array[int] = []
	for i in inventory.SIZE:
		var id: String = inventory.item_id(i)
		if id == "":
			empty.append(i)
		elif _in_tab(i):
			hits.append(i)
	if sort_by != "slot":
		hits.sort_custom(func(a: int, b: int) -> bool: return _sort_key(a) > _sort_key(b))
	_order.clear()
	_order.append_array(hits)
	_order.append_array(empty)
	if tab == "all":  # every slot keeps a cell; the order only changes with a sort
		while _order.size() < inventory.SIZE:
			_order.append(-1)


# A backpack slot's stack as InventoryState sees it (a "gun" key only on rolled guns).
func _stack(i: int) -> Dictionary:
	var gun: Dictionary = inventory.gun_at(i)
	return {"id": inventory.item_id(i), "count": inventory.item_count(i), "gun": gun} if not gun.is_empty() else {"id": inventory.item_id(i), "count": inventory.item_count(i)}


func _gear_slot(id: String) -> String:
	return String(items.equip_slot(id)) if items.has_item(id) else ""


func _in_tab(i: int) -> bool:
	var stack := _stack(i)
	match tab:
		"guns":
			return inventory.is_weapon(stack)
		"gear":
			return not inventory.is_weapon(stack) and _gear_slot(inventory.item_id(i)) != ""
		"items":
			return not inventory.is_weapon(stack) and _gear_slot(inventory.item_id(i)) == ""
	return true


func _sort_key(i: int) -> float:
	var gun: Dictionary = inventory.gun_at(i)
	match sort_by:
		"tier":
			return float(gun_db.tier_index(String(gun["tier"]))) if not gun.is_empty() else -1.0
		"level":
			return float(gun.get("lvl", 1)) if not gun.is_empty() else -1.0
		"type":
			return -float(String(gun.get("body", inventory.item_id(i))).hash() % 1000)
	return -float(i)


func _slot_at(pos: Vector2) -> int:
	for cell in _order.size():
		if _cell_rect(cell).has_point(pos):
			return _order[cell] if _order[cell] >= 0 else _first_empty()
	if bank == null:
		for k in inventory.EQUIP_SLOTS.size():
			if _equip_rect(k).has_point(pos):
				return EQUIP_BASE + k
	for i in inventory.holster_count:
		if _holster_rect(i).has_point(pos):
			return HOLSTER_BASE + i
	if _holster_rect(inventory.holster_count).has_point(pos):
		return KNIFE_SLOT
	if bank != null:
		for i in int(bank.call("capacity")):
			if _bank_rect(i).has_point(pos):
				return BANK_BASE + i
		if bank_price != "" and _bank_button().has_point(pos):
			return BANK_BUTTON
	return -1


func _first_empty() -> int:
	for i in inventory.SIZE:
		if inventory.item_id(i) == "":
			return i
	return -1


# The rolled gun in a backpack slot, a holster or a bank slot ({} for anything else).
func _gun_at(slot: int) -> Dictionary:
	if slot >= BANK_BASE and slot < BANK_BUTTON:
		return (bank.call("stack", slot - BANK_BASE) as Dictionary).get("gun", {})
	if slot >= HOLSTER_BASE and slot < KNIFE_SLOT:
		return inventory.holster_gun(slot - HOLSTER_BASE)
	return inventory.gun_at(slot) if slot >= 0 and slot < inventory.SIZE else {}


func _id_at(slot: int) -> String:
	if slot < 0 or slot >= BANK_BUTTON:
		return ""
	if slot >= BANK_BASE:
		return String((bank.call("stack", slot - BANK_BASE) as Dictionary).get("id", ""))
	if slot >= KNIFE_SLOT:
		return ""
	if slot >= HOLSTER_BASE:
		return String(inventory.holsters[slot - HOLSTER_BASE].get("id", ""))
	if slot >= EQUIP_BASE:
		var stack: Dictionary = inventory.equipment[inventory.EQUIP_SLOTS[slot - EQUIP_BASE]]
		return "" if stack.is_empty() else String(stack["id"])
	return inventory.item_id(slot)


# ---------------------------------------------------------------- input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var button: int = event.button_index
	var pos: Vector2 = event.position
	if button == MOUSE_BUTTON_LEFT:
		for k in TABS.size():
			if _tab_rect(k).has_point(pos):
				tab = String(TABS[k][0])
				_make_order()
				if _focus >= 0 and _focus < inventory.SIZE and _order.find(_focus) < 0:
					_focus = -1  # its item is not shown on this tab
				_redraw_all()
				return
		if _sort_rect().has_point(pos):
			var at := 0
			for k in SORTS.size():
				if String(SORTS[k][0]) == sort_by:
					at = k
			sort_by = String(SORTS[(at + 1) % SORTS.size()][0])
			_redraw_all()
			return
		if _close_rect().has_point(pos):
			_close_by_button()
			return
		for b: Array in _buttons:
			if (b[0] as Rect2).has_point(pos):
				_act(String(b[1]))
				return
	var slot := _slot_at(pos)
	if slot < 0:
		if button == MOUSE_BUTTON_LEFT and not _frame().has_point(pos):
			_drop(-1)  # carried out of the window and let go
		return
	if slot == BANK_BUTTON:
		if button == MOUSE_BUTTON_LEFT:
			bank_upgrade.emit()
			_redraw_all()
		return
	if slot >= BANK_BASE:
		if button != MOUSE_BUTTON_LEFT:
			return
		bank.call("click", slot - BANK_BASE, inventory)
	elif slot >= KNIFE_SLOT:
		return
	elif slot >= HOLSTER_BASE:
		if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
			return
		inventory.click_holster(slot - HOLSTER_BASE)
	elif slot >= EQUIP_BASE:
		if button != MOUSE_BUTTON_LEFT and button != MOUSE_BUTTON_RIGHT:
			return
		inventory.click_equipment(inventory.EQUIP_SLOTS[slot - EQUIP_BASE])
	elif button == MOUSE_BUTTON_LEFT:
		inventory.click_slot(slot)
	elif button == MOUSE_BUTTON_RIGHT:
		inventory.right_click_slot(slot)
	else:
		return
	changed.emit()
	_redraw_all()


# The Esc of the header's close button: the session's own key closes the window the normal way.
func _close_by_button() -> void:
	var press := InputEventAction.new()
	press.action = "inventory"
	press.pressed = true
	Input.parse_input_event(press)


# The drop key: the gun on the mouse, else the gun under it.
func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("drop_item"):
		_drop(-1 if not inventory.cursor.is_empty() else _slot_at(_mouse))
		get_viewport().set_input_as_handled()


# Takes the rolled gun off the mouse (slot -1), out of a slot or out of a holster and hands it to the session to lay
# on the ground.
func _drop(slot: int) -> void:
	if slot < 0 and inventory.cursor.is_empty():
		return
	var gun := {}
	if slot >= HOLSTER_BASE and slot < KNIFE_SLOT:
		if not inventory.holster_gun(slot - HOLSTER_BASE).is_empty():
			gun = inventory.take_holster(slot - HOLSTER_BASE).get("gun", {})
	elif slot < inventory.SIZE:
		gun = inventory.take_gun(slot)  # (-1 = the gun on the mouse)
	if gun.is_empty():
		return
	dropped.emit(gun)
	changed.emit()
	_redraw_all()


# The card's buttons: one move each, done with the same clicks a player would make.
func _act(action: String) -> void:
	if not inventory.cursor.is_empty():
		return
	match action:
		"equip":  # a gun from the backpack into a free holster, else in place of the gun in hand
			var h := inventory.free_holster()
			if h < 0:
				h = maxi(in_hand, 0)
			inventory.click_slot(_focus)
			inventory.click_holster(h)
			if not inventory.cursor.is_empty():
				inventory.click_slot(_focus)
			_focus = HOLSTER_BASE + h
		"unequip":
			var free := _first_empty()
			if free < 0:
				return
			inventory.click_holster(_focus - HOLSTER_BASE)
			inventory.click_slot(free)
			_focus = free
		"wear":
			var wanted := _gear_slot(inventory.item_id(_focus))
			var place := wanted
			if wanted == "ring":
				place = "ring_1" if inventory.equipment["ring_1"].is_empty() else "ring_2"
			inventory.click_slot(_focus)
			inventory.click_equipment(place)
			if not inventory.cursor.is_empty():
				inventory.click_slot(_focus)
			_focus = EQUIP_BASE + inventory.EQUIP_SLOTS.find(place)
		"take_off":
			var spot := _first_empty()
			if spot < 0:
				return
			inventory.click_equipment(inventory.EQUIP_SLOTS[_focus - EQUIP_BASE])
			inventory.click_slot(spot)
			_focus = spot
		"drop":
			_drop(_focus)
	changed.emit()
	_redraw_all()


# What the card's foot offers for the focused thing.
func _actions() -> Array:
	if not inventory.cursor.is_empty() or _focus < 0:
		return []
	if _focus >= HOLSTER_BASE and _focus < KNIFE_SLOT:
		return [["Unequip", "unequip"], ["Drop", "drop"]] if not _gun_at(_focus).is_empty() else ([["Unequip", "unequip"]] if _id_at(_focus) != "" else [])
	if _focus >= EQUIP_BASE and _focus < HOLSTER_BASE:
		return [["Take off", "take_off"]] if _id_at(_focus) != "" else []
	if _focus < inventory.SIZE and _id_at(_focus) != "":
		if inventory.is_weapon(_stack(_focus)):
			return [["Equip", "equip"], ["Drop", "drop"]] if not inventory.gun_at(_focus).is_empty() else [["Equip", "equip"]]
		if _gear_slot(inventory.item_id(_focus)) != "":
			return [["Wear", "wear"]]
	return []


# ---------------------------------------------------------------- drawing

# The still layer: everything but the card, the outlines and the mouse's stack.
func _draw() -> void:
	_place_portrait()
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.01, 0.012, 0.02, 0.82))
	_make_order()
	_draw_header()
	var cols := _columns()
	UiSkin.panel(self, cols[0])
	UiSkin.panel(self, cols[1])
	if bank != null:
		_draw_bank()
	else:
		_draw_character()
	_draw_ready()
	_draw_backpack()
	_draw_footer()


func _draw_card_layer() -> void:
	_since_card = 0.0
	_card_moves = false
	_draw_card(_columns()[2])


# The top layer: the chosen thing's gold outline, a white one on what the mouse is over, and the stack on the mouse.
func _draw_top() -> void:
	var chosen := _rect_of(_focus)
	if chosen.has_area():
		UiSkin.outline(_top, chosen, UiSkin.ACCENT)
	var r := _rect_of(_slot_at(_mouse))
	var round := 8
	for pill: Rect2 in [_tab_rect(0), _tab_rect(1), _tab_rect(2), _tab_rect(3), _sort_rect(), _close_rect()]:
		if pill.has_point(_mouse):
			r = pill
			round = 18
	if r.has_area():
		UiSkin.outline(_top, r, Color(1, 1, 1, 0.85), round)
	_draw_cursor()


# Where a slot index (backpack, gear, holster, knife, bank, bank button) is drawn; an empty Rect2 when it is not shown.
func _rect_of(slot: int) -> Rect2:
	if slot < 0:
		return Rect2()
	if slot < inventory.SIZE:
		return _slot_rect(slot)
	if slot >= BANK_BUTTON:
		return _bank_button() if bank != null and bank_price != "" else Rect2()
	if slot >= BANK_BASE:
		return _bank_rect(slot - BANK_BASE) if bank != null else Rect2()
	if slot >= KNIFE_SLOT:
		return _holster_rect(inventory.holster_count)
	if slot >= HOLSTER_BASE:
		return _holster_rect(slot - HOLSTER_BASE)
	return _equip_rect(slot - EQUIP_BASE) if bank == null else Rect2()


func _draw_header() -> void:
	var h := _header()
	UiSkin.panel(self, h, UiSkin.INK_DEEP)
	draw_string(_font, h.position + Vector2(24, 42), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiSkin.TEXT)
	for k in TABS.size():
		var r := _tab_rect(k)
		UiSkin.pill(self, _font, r, String(TABS[k][1]), tab == String(TABS[k][0]), false)
	var sort_name := ""
	for s: Array in SORTS:
		if String(s[0]) == sort_by:
			sort_name = String(s[1])
	UiSkin.pill(self, _font, _sort_rect(), "Sort: %s" % sort_name, false, false, 14)
	UiSkin.pill(self, _font, _close_rect(), "Close", false, false, 14)


func _draw_character() -> void:
	var left := _columns()[0]
	UiSkin.header(self, _font, left.position + Vector2(PAD, PAD - 6.0), left.size.x - 2.0 * PAD, "CHARACTER", "what you wear")
	var e := _equip_cell()
	for k in inventory.EQUIP_SLOTS.size():
		var slot: String = inventory.EQUIP_SLOTS[k]
		var r := _equip_rect(k)
		var stack: Dictionary = inventory.equipment[slot]
		var state := "fits" if inventory.can_equip_cursor(slot) else ""
		UiSkin.slot(self, r, Color(0.6, 0.75, 1.0), not stack.is_empty(), state)
		if stack.is_empty():
			IconArt.draw(self, ItemIcons.slot_shape(slot), r.grow(-e * 0.22), Color.WHITE, 0.22)  # what goes here
			draw_string(_font, Vector2(r.position.x, r.end.y - 4.0), SLOT_LABELS[slot], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 9, Color(1, 1, 1, 0.38))
		else:
			ItemIcons.draw(self, String(stack["id"]), r.grow(-e * 0.12), Color.WHITE)
	var p := _portrait_rect()
	draw_rect(p, Color(0, 0, 0, 0.25), false, 1.0)


func _draw_ready() -> void:
	var mid := _columns()[1]
	UiSkin.header(self, _font, mid.position + Vector2(PAD, PAD - 6.0), mid.size.x - 2.0 * PAD, "READY", "the guns you carry (one put in by hand starts empty)")
	var fits: bool = inventory.is_weapon(inventory.cursor)
	for i in inventory.holster_count:
		var r := _holster_rect(i)
		var gun: Dictionary = inventory.holster_gun(i)
		var body: String = inventory.holster_body(i)
		var tint := _tint(gun) if not gun.is_empty() else Color(0.7, 0.72, 0.8)
		var state := "fits" if fits else ("chosen" if i == in_hand else "")
		UiSkin.slot(self, r, tint, body != "", state)
		UiSkin.key_cap(self, _font, r.position + Vector2(8, 8), gun_keys[i] if i < gun_keys.size() else str(i + 1))
		if body == "":
			draw_string(_font, Vector2(r.position.x, r.get_center().y + 6.0), "empty", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 15, UiSkin.TEXT_DIM)
			continue
		var icon := Rect2(r.position + Vector2(10, 30), Vector2(r.size.x * 0.4, r.size.y - 38.0))
		ItemIcons.draw(self, body, icon, tint)
		var tx := r.position.x + r.size.x * 0.46
		var tw := r.size.x * 0.52
		if gun.is_empty():
			draw_string(_font, Vector2(tx, r.position.y + 30), items.item_name(String(inventory.holsters[i].get("id", ""))), HORIZONTAL_ALIGNMENT_LEFT, tw, 15, UiSkin.TEXT)
		else:
			TierStyle.draw_name(self, _font, Vector2(tx, r.position.y + 28), gun_db, String(gun["tier"]), GunStats.display_name(gun_db, gun), 15, tint, tw)
			var stats := GunStats.final_stats(gun_db, gun)
			draw_string(_font, Vector2(tx, r.position.y + 50), "%s   Lv %d" % [String(gun_db.tier(String(gun["tier"]))["name"]), int(stats["lvl"])], HORIZONTAL_ALIGNMENT_LEFT, tw, 13, UiSkin.TEXT_DIM)
			draw_string(_font, Vector2(tx, r.position.y + 72), "DPS %.0f" % (float(stats["damage"]) * float(stats["fire_rate"])), HORIZONTAL_ALIGNMENT_LEFT, tw, 15, UiSkin.ACCENT)
		if inventory.loaded[i] >= 0:
			draw_string(_font, Vector2(r.position.x, r.end.y - 10.0), "%d rounds" % inventory.loaded[i], HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 12.0, 12, UiSkin.TEXT_DIM)
	var k := _holster_rect(inventory.holster_count)
	UiSkin.slot(self, k, Color(0.7, 0.72, 0.8), true, "chosen" if in_hand < 0 else "")
	UiSkin.key_cap(self, _font, k.position + Vector2(8, 8), knife_key)
	ItemIcons.draw(self, "knife", Rect2(k.position + Vector2(10, 30), Vector2(k.size.x * 0.4, k.size.y - 38.0)), Color.WHITE)
	draw_string(_font, Vector2(k.position.x + k.size.x * 0.46, k.position.y + 30), knife_name, HORIZONTAL_ALIGNMENT_LEFT, k.size.x * 0.52, 15, UiSkin.TEXT)
	draw_string(_font, Vector2(k.position.x + k.size.x * 0.46, k.position.y + 52), "Knife: always with you", HORIZONTAL_ALIGNMENT_LEFT, k.size.x * 0.52, 13, UiSkin.TEXT_DIM)


func _draw_backpack() -> void:
	var mid := _columns()[1]
	var used := 0
	for i in inventory.SIZE:
		if inventory.item_id(i) != "":
			used += 1
	UiSkin.header(self, _font, Vector2(mid.position.x + PAD, _bag_top()), mid.size.x - 2.0 * PAD, "BACKPACK", "%d / %d" % [used, inventory.SIZE])
	var s := _cell()
	for cell in _order.size():
		var r := _cell_rect(cell)
		var i: int = _order[cell]
		if i < 0 or inventory.item_id(i) == "":
			UiSkin.slot(self, r, Color.WHITE, false, "")
			continue
		var gun: Dictionary = inventory.gun_at(i)
		var tint := _tint(gun) if not gun.is_empty() else Color(0.6, 0.65, 0.78)
		UiSkin.slot(self, r, tint, true, "")
		if gun.is_empty():
			ItemIcons.draw(self, inventory.item_id(i), r.grow(-s * 0.14), Color.WHITE)
		else:
			ItemIcons.draw(self, String(gun["body"]), r.grow(-s * 0.12), tint)
			draw_string(_font, r.position + Vector2(5, 14), str(int(gun.get("lvl", 1))), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.75))
		_draw_count(self, r, inventory.item_count(i))


# The bank's slots in the left column (only when the window was opened at the bank), and its upgrade button.
func _draw_bank() -> void:
	var left := _columns()[0]
	var capacity: int = bank.call("capacity")
	UiSkin.header(self, _font, left.position + Vector2(PAD, PAD - 6.0), left.size.x - 2.0 * PAD, "BANK", "safe when you go down  -  %d / %d" % [int(bank.call("used")), capacity])
	for i in capacity:
		var r := _bank_rect(i)
		var stack: Dictionary = bank.call("stack", i)
		var gun: Dictionary = stack.get("gun", {})
		var tint := _tint(gun) if not gun.is_empty() else Color(0.6, 0.65, 0.78)
		UiSkin.slot(self, r, tint, not stack.is_empty(), "")
		if stack.is_empty():
			continue
		ItemIcons.draw(self, String(gun["body"]) if not gun.is_empty() else String(stack["id"]), r.grow(-r.size.x * 0.12), tint if not gun.is_empty() else Color.WHITE)
		_draw_count(self, r, int(stack["count"]))
	if bank_price != "":
		UiSkin.pill(self, _font, _bank_button(), bank_price, false, false, 14)


func _draw_card(r: Rect2) -> void:
	var what := {}
	var shown := _focus
	var holding := not inventory.cursor.is_empty()
	var in_hand_gun: Dictionary = {} if in_hand < 0 else inventory.holster_gun(in_hand)
	if holding:
		var cgun: Dictionary = inventory.cursor.get("gun", {})
		what = {"gun": cgun, "against": in_hand_gun} if not cgun.is_empty() else {"id": String(inventory.cursor["id"]), "count": int(inventory.cursor["count"])}
	elif shown == KNIFE_SLOT:
		what = {"note": [knife_name, "Your knife. Always with you: it cannot be dropped, traded or lost."]}
	elif _id_at(shown) != "":
		var gun := _gun_at(shown)
		if not gun.is_empty():
			var against: Dictionary = {} if shown == HOLSTER_BASE + in_hand else in_hand_gun
			if _shift and not against.is_empty():  # Shift: the gun in hand, against the chosen one
				what = {"gun": against, "against": gun}
			else:
				what = {"gun": gun, "against": against}
		else:
			var count := inventory.item_count(shown) if shown < inventory.SIZE else 1
			what = {"id": _id_at(shown), "count": count}
	var hovered_action := ""
	for b: Array in _buttons:
		if (b[0] as Rect2).has_point(_mouse):
			hovered_action = String(b[1])
	if what.has("gun") and not (what["gun"] as Dictionary).is_empty():
		_card_moves = TierStyle.animated(gun_db, String(what["gun"]["tier"]))
	_buttons = InventoryCard.draw(_card_layer, _font, r, what, gun_db, items, _actions(), hovered_action, _now())


func _draw_footer() -> void:
	var f := _footer()
	UiSkin.panel(self, f, UiSkin.INK_DEEP)
	var x := f.position.x + 24.0
	var y := f.position.y + 32.0
	if chips >= 0:
		draw_circle(Vector2(x + 8, y - 6), 8.0, Color(0.95, 0.75, 0.25))
		draw_string(_font, Vector2(x + 22, y), "%s chips" % _thousands(chips), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
		x += 200.0
	if points >= 0:
		draw_circle(Vector2(x + 8, y - 6), 8.0, Color(0.45, 0.85, 1.0))
		draw_string(_font, Vector2(x + 22, y), "%s points" % _thousands(points), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
	var keys := [[_action_key("drop_item"), "Drop gun"], ["Shift", "Compare with gun in hand"], ["Right click", "Split a stack"], [_action_key("inventory"), "Close"]]
	var kx := f.end.x - 24.0
	for k in range(keys.size() - 1, -1, -1):
		var label := String(keys[k][1])
		var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		kx -= lw
		draw_string(_font, Vector2(kx, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
		var cap := String(keys[k][0])
		var cw := maxf(_font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0, 22.0)
		kx -= cw + 8.0
		UiSkin.key_cap(self, _font, Vector2(kx, y - 15.0), cap)
		kx -= 26.0


func _draw_cursor() -> void:
	if inventory.cursor.is_empty():
		return
	var s := _cell()
	var r := Rect2(_mouse - Vector2(s, s) * 0.45, Vector2(s, s) * 0.9)
	var cgun: Dictionary = inventory.cursor.get("gun", {})
	if cgun.is_empty():
		ItemIcons.draw(_top, String(inventory.cursor["id"]), r, Color.WHITE)
	else:
		ItemIcons.draw(_top, String(cgun["body"]), r, _tint(cgun))
	_draw_count(_top, r, int(inventory.cursor["count"]))


# A rolled gun's rarity colour (rainbow / pony ones as they are at the moment the window is drawn).
func _tint(gun: Dictionary) -> Color:
	return TierStyle.color(gun_db, String(gun["tier"]), _now())


func _draw_count(canvas: CanvasItem, r: Rect2, count: int) -> void:
	if count > 1:
		canvas.draw_string_outline(_font, Vector2(r.position.x, r.end.y - 6.0), str(count), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6.0, 15, 4, Color(0, 0, 0, 0.8))
		canvas.draw_string(_font, Vector2(r.position.x, r.end.y - 6.0), str(count), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 6.0, 15, Color.WHITE)


func _action_key(action: String) -> String:
	var events := InputMap.action_get_events(action)
	return "?" if events.is_empty() else events[0].as_text().replace(" - Physical", "").replace(" (Physical)", "")


func _thousands(n: int) -> String:
	var text := str(absi(n))
	var out := ""
	while text.length() > 3:
		out = "," + text.substr(text.length() - 3) + out
		text = text.substr(0, text.length() - 3)
	return ("-" if n < 0 else "") + text + out
