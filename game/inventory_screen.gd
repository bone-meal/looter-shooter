# Purpose: the inventory screen: the 36 backpack slots, the holsters under them (the guns carried ready; only guns go in, and one put there by hand has to be reloaded), the knife's box (it cannot be moved) and an 18-slot equipment panel; click to pick up / place / swap / wear, right click for half or one, hover tooltip with stats and flavor text. A rolled gun is dropped into the world by the drop key while the mouse is over it, or by carrying it out of the window and clicking (signal `dropped`); holding Shift over a gun shows the gun in hand beside it.
# Dependencies: core/inventory_state.gd, core/item_db.gd, game/item_icons.gd. Emits `changed` after every click so the player re-reads the held item.
extends Control

const IconArt = preload("res://game/icon_art.gd")
const ItemIcons = preload("res://game/item_icons.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const SkillState = preload("res://core/skill_state.gd")
const GunStats = preload("res://core/gun_stats.gd")
const TierStyle = preload("res://game/tier_style.gd")
const HoverCard = preload("res://game/hover_card.gd")

signal changed
signal dropped(gun: Dictionary)  # a rolled gun left the inventory: the session lays it on the ground

const SLOT := 48.0
const GAP := 4.0
const COLUMNS := 9
const TOOLTIP_WIDTH := 240.0
const EQUIP_BASE := 100  # slot indices >= this are equipment slots (index - EQUIP_BASE into EQUIP_SLOTS)
const HOLSTER_BASE := 200  # slot indices >= this are holsters
const KNIFE_SLOT := 300  # the knife's box
const HOLSTER_W := 2.0 * SLOT + GAP  # a holster is two slots wide
const EQUIP_COLUMNS := 3
const SLOT_LABELS := {"hat": "Hat", "head": "Head", "earrings": "Ears", "necklace": "Neck", "glasses": "Eyes", "mouth": "Mouth", "shirt": "Shirt", "chestplate": "Chest", "gauntlets": "Hands", "ring_1": "Ring", "ring_2": "Ring", "bracelet": "Wrist", "pants": "Pants", "leg_armor": "Legs", "cape": "Cape", "waist": "Belt", "boots": "Boots", "foot_armor": "Feet"}

var inventory: InventoryState  # set before add_child
var items: ItemDb  # set before add_child
var gun_db: GunDb  # set before add_child (rolled guns: colours, names, stats)
var in_hand := 0  # which holster is in the player's hand (-1 = the knife), set by the session: that box is lit
var knife := "combat"  # the knife type carried, set by the session
var knife_name := ""
var knife_key := ""  # the labels of the keys that take a gun or the knife in hand, set by the session
var gun_keys: Array[String] = []

var _mouse := Vector2.ZERO
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


# Returns the stack on the mouse to the inventory, then hides.
func close() -> void:
	inventory.return_cursor()
	visible = false
	changed.emit()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # animated tier colours (rainbow, pony)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _gun_in(stack: Dictionary) -> Dictionary:
	return stack.get("gun", {})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var slot := _slot_at(event.position)
		if slot < 0:
			if event.button_index == MOUSE_BUTTON_LEFT and not _panel(get_viewport_rect().size).has_point(event.position):
				_drop(-1)  # carried out of the window and let go
			return
		if slot >= KNIFE_SLOT:
			return
		if slot >= HOLSTER_BASE:
			if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
				return
			inventory.click_holster(slot - HOLSTER_BASE)
		elif slot >= EQUIP_BASE:
			if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
				return
			inventory.click_equipment(inventory.EQUIP_SLOTS[slot - EQUIP_BASE])
		elif event.button_index == MOUSE_BUTTON_LEFT:
			inventory.click_slot(slot)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			inventory.right_click_slot(slot)
		else:
			return
		changed.emit()
		queue_redraw()


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
		gun = inventory.take_gun(slot)
	if gun.is_empty():
		return
	dropped.emit(gun)
	changed.emit()
	queue_redraw()


func _panel(view: Vector2) -> Rect2:
	var left := EQUIP_COLUMNS * (SLOT + GAP) + 44.0
	return Rect2(_origin(view) - Vector2(16 + left, 44), Vector2(COLUMNS * (SLOT + GAP) - GAP + 32 + left, 6 * (SLOT + GAP) + 64))


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.6))
	var origin := _origin(view)
	var panel := _panel(view)
	draw_rect(panel, Color(0.12, 0.12, 0.14, 0.95))
	draw_rect(panel, Color(1, 1, 1, 0.3), false, 2.0)
	draw_string(_font, origin + Vector2(0, -16), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
	var drop_keys := InputMap.action_get_events("drop_item")
	draw_string(_font, Vector2(panel.position.x + 16.0, panel.end.y + 18.0), "%s over a gun, or carry it out of the window and click: drop it      Hold Shift over a gun: the gun in hand beside it" % ("?" if drop_keys.is_empty() else drop_keys[0].as_text().replace(" - Physical", "").replace(" (Physical)", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.6))
	var hover := _slot_at(_mouse)
	for i in inventory.SIZE:
		_draw_slot(i, hover == i)
	_draw_holsters(hover)
	_draw_equipment(hover)
	var hovered_id := _id_at(hover)
	if hover == KNIFE_SLOT and inventory.cursor.is_empty():
		HoverCard.draw_note(self, _font, knife_name, "Your knife. Always with you: it cannot be dropped, traded or lost.", _mouse + Vector2(18, 18), view)
	elif hovered_id != "" and inventory.cursor.is_empty():
		var hovered_gun := _gun_at(hover)
		if not hovered_gun.is_empty():
			var held: Dictionary = {} if (in_hand < 0 or hover == HOLSTER_BASE + in_hand) else inventory.holster_gun(in_hand)
			var box := _draw_gun_tooltip(hovered_gun, held, _mouse + Vector2(18, 18), view, "Rolled gun" if held.is_empty() else "compared with the gun in hand")
			if Input.is_key_pressed(KEY_SHIFT) and not held.is_empty():  # the gun in hand beside it, numbers against the hovered one
				var beside := Vector2(box.position.x - box.size.x - 8.0, box.position.y)
				if beside.x < 8.0:
					beside.x = box.end.x + 8.0
				_draw_gun_tooltip(held, hovered_gun, beside, view, "IN HAND")
		else:
			_draw_tooltip(hovered_id, view)
	if not inventory.cursor.is_empty():
		var r := Rect2(_mouse - Vector2(SLOT, SLOT) * 0.4, Vector2(SLOT, SLOT) * 0.8)
		var cgun := _gun_in(inventory.cursor)
		if cgun.is_empty():
			ItemIcons.draw(self, inventory.cursor["id"], r, Color.WHITE)
		else:
			ItemIcons.draw(self, String(cgun["body"]), r, TierStyle.color(gun_db, String(cgun["tier"]), _now()))
		_draw_count(r, int(inventory.cursor["count"]))


# The holsters (the ready guns) and the knife, in the order of their keys.
func _draw_holsters(hover: int) -> void:
	var o := _origin(get_viewport_rect().size)
	draw_string(_font, o + Vector2(0, 4 * (SLOT + GAP) + 16.0), "READY (only guns; one put here by hand must be reloaded)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
	var fits: bool = inventory.is_weapon(inventory.cursor)
	for i in inventory.holster_count:
		var r := _holster_rect(i)
		var held := i == in_hand
		draw_rect(r, Color(0.05, 0.05, 0.06, 0.9))
		draw_rect(r, Color(0.4, 1.0, 0.5, 0.95) if fits else (Color(1, 1, 1, 0.95) if held else (Color(1, 1, 0.6, 0.9) if hover == HOLSTER_BASE + i else Color(1, 1, 1, 0.25))), false, 2.0 if (fits or held or hover == HOLSTER_BASE + i) else 1.0)
		draw_string(_font, r.position + Vector2(4, 13), gun_keys[i] if i < gun_keys.size() else "", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
		var body: String = inventory.holster_body(i)
		if body == "":
			continue
		var gun: Dictionary = inventory.holster_gun(i)
		var tint := Color.WHITE
		if not gun.is_empty():
			tint = TierStyle.color(gun_db, String(gun["tier"]), _now())
			draw_rect(r, tint, false, 2.0)
		ItemIcons.draw(self, body, r.grow(-6), tint)
		if inventory.loaded[i] >= 0:
			draw_string(_font, r.end - Vector2(34, 5), str(inventory.loaded[i]), HORIZONTAL_ALIGNMENT_RIGHT, 30, 13, Color.WHITE)
	var k := _holster_rect(inventory.holster_count)
	draw_rect(k, Color(0.05, 0.05, 0.06, 0.9))
	draw_rect(k, Color(1, 1, 1, 0.95) if in_hand < 0 else (Color(1, 1, 0.6, 0.9) if hover == KNIFE_SLOT else Color(1, 1, 1, 0.25)), false, 2.0 if (in_hand < 0 or hover == KNIFE_SLOT) else 1.0)
	draw_string(_font, k.position + Vector2(4, 13), knife_key, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
	ItemIcons.draw(self, "knife", k.grow(-6), Color.WHITE)


# The rolled gun in a backpack slot or a holster ({} for anything else).
func _gun_at(slot: int) -> Dictionary:
	if slot >= HOLSTER_BASE and slot < KNIFE_SLOT:
		return inventory.holster_gun(slot - HOLSTER_BASE)
	return inventory.gun_at(slot) if slot >= 0 and slot < inventory.SIZE else {}


func _holster_rect(i: int) -> Rect2:
	var o := _origin(get_viewport_rect().size)
	return Rect2(o + Vector2(i * (HOLSTER_W + GAP), 4 * (SLOT + GAP) + 22.0), Vector2(HOLSTER_W, SLOT))


func _draw_slot(i: int, hovered: bool) -> void:
	var r := _slot_rect(i)
	draw_rect(r, Color(0.05, 0.05, 0.06, 0.9))
	draw_rect(r, Color(1, 1, 0.6, 0.9) if hovered else Color(1, 1, 1, 0.25), false, 2.0 if hovered else 1.0)
	var id: String = inventory.item_id(i)
	if id == "":
		return
	var gun: Dictionary = inventory.gun_at(i)
	if gun.is_empty():
		ItemIcons.draw(self, id, r.grow(-5), Color.WHITE)
	else:
		var tint := TierStyle.color(gun_db, String(gun["tier"]), _now())
		draw_rect(r, tint, false, 2.0)
		ItemIcons.draw(self, String(gun["body"]), r.grow(-5), tint)
	_draw_count(r, inventory.item_count(i))


func _draw_equipment(hover: int) -> void:
	var o := _equip_origin(get_viewport_rect().size)
	draw_string(_font, o + Vector2(0, -16), "EQUIPMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
	for k in inventory.EQUIP_SLOTS.size():
		var slot: String = inventory.EQUIP_SLOTS[k]
		var r := _equip_rect(k)
		var fits: bool = inventory.can_equip_cursor(slot)
		draw_rect(r, Color(0.05, 0.05, 0.06, 0.9))
		draw_rect(r, Color(0.4, 1.0, 0.5, 0.95) if fits else (Color(1, 1, 0.6, 0.9) if hover == EQUIP_BASE + k else Color(1, 1, 1, 0.25)), false, 2.0 if (fits or hover == EQUIP_BASE + k) else 1.0)
		var stack: Dictionary = inventory.equipment[slot]
		if stack.is_empty():
			IconArt.draw(self, ItemIcons.slot_shape(slot), r.grow(-9), Color.WHITE, 0.2)  # what goes here
			draw_string(_font, r.position + Vector2(0, SLOT - 4), SLOT_LABELS[slot], HORIZONTAL_ALIGNMENT_CENTER, SLOT, 9, Color(1, 1, 1, 0.35))
		else:
			ItemIcons.draw(self, stack["id"], r.grow(-5), Color.WHITE)


func _id_at(slot: int) -> String:
	if slot < 0:
		return ""
	if slot >= KNIFE_SLOT:
		return ""
	if slot >= HOLSTER_BASE:
		return String(inventory.holsters[slot - HOLSTER_BASE].get("id", ""))
	if slot >= EQUIP_BASE:
		var stack: Dictionary = inventory.equipment[inventory.EQUIP_SLOTS[slot - EQUIP_BASE]]
		return "" if stack.is_empty() else String(stack["id"])
	return inventory.item_id(slot)


func _draw_count(r: Rect2, count: int) -> void:
	if count > 1:
		draw_string(_font, r.end - Vector2(30, 6), str(count), HORIZONTAL_ALIGNMENT_RIGHT, 26, 15, Color.WHITE)


# The hover cards themselves are game/hover_card.gd (the trade window shows the same ones).
func _draw_gun_tooltip(gun: Dictionary, against: Dictionary, place: Vector2, view: Vector2, note: String) -> Rect2:
	return HoverCard.draw_gun(self, _font, gun_db, gun, against, place, view, note)


func _draw_tooltip(id: String, view: Vector2) -> void:
	HoverCard.draw_item(self, _font, items, id, _mouse + Vector2(18, 18), view)


func _origin(view: Vector2) -> Vector2:
	return Vector2((view.x - (COLUMNS * (SLOT + GAP) - GAP)) * 0.5, view.y * 0.5 - 130.0)


func _slot_rect(i: int) -> Rect2:
	var o := _origin(get_viewport_rect().size)
	return Rect2(o + Vector2((i % COLUMNS) * (SLOT + GAP), floori(i / float(COLUMNS)) * (SLOT + GAP)), Vector2(SLOT, SLOT))


func _equip_origin(view: Vector2) -> Vector2:
	var o := _origin(view)
	return Vector2(o.x - EQUIP_COLUMNS * (SLOT + GAP) - 44.0, o.y)


func _equip_rect(k: int) -> Rect2:
	var o := _equip_origin(get_viewport_rect().size)
	return Rect2(o + Vector2(floori(k / 6.0) * (SLOT + GAP), (k % 6) * (SLOT + GAP)), Vector2(SLOT, SLOT))


func _slot_at(pos: Vector2) -> int:
	for i in inventory.SIZE:
		if _slot_rect(i).has_point(pos):
			return i
	for k in inventory.EQUIP_SLOTS.size():
		if _equip_rect(k).has_point(pos):
			return EQUIP_BASE + k
	for i in inventory.holster_count:
		if _holster_rect(i).has_point(pos):
			return HOLSTER_BASE + i
	if _holster_rect(inventory.holster_count).has_point(pos):
		return KNIFE_SLOT
	return -1
