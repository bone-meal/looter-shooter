# Purpose: the trade window (online): what you give, what you get, both players' "ready" ticks, the second step
# (confirm) and your tradable things to pick from: rolled guns and armour in the bag. Shows what the host's desk
# says (core/trade_desk.gd through game/net_trade.gd); every click is a request, nothing changes hands here.
# Dependencies: game/menu_widgets.gd, core/inventory_state.gd, core/item_db.gd, core/gun_db.gd, core/gun_stats.gd, game/hover_card.gd,
# game/tier_style.gd.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const GunStats = preload("res://core/gun_stats.gd")
const TierStyle = preload("res://game/tier_style.gd")
const HoverCard = preload("res://game/hover_card.gd")

signal offered(thing: Dictionary)  # {"ref": slot, "gun": {...}} or {"ref": slot, "id": item id}
signal withdrawn(ref: int)
signal ready_set(on: bool)
signal confirmed
signal cancelled

var _inventory: InventoryState
var _items: RefCounted
var _gun_db: RefCounted
var _title: Label
var _give: VBoxContainer
var _get: VBoxContainer
var _bag: GridContainer
var _ticks: Label
var _status: Label
var _ready_button: Button
var _confirm_button: Button
var _view := {}
var in_hand := -1  # the holster in the player's hand, -1 = the knife (set by the session): a hovered gun's card compares with that gun
var _hover := {}  # the thing under the mouse (a line of either column or a bag button)
var _card: Control  # lies over everything and draws the hovered thing's card (game/hover_card.gd)


func setup(inventory: InventoryState, items: RefCounted, gun_db: RefCounted) -> void:
	_inventory = inventory
	_items = items
	_gun_db = gun_db
	visible = false
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.05, 0.05, 0.06, 0.88))
	var box := Widgets.centered_column(self, 760)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 30)
	box.add_child(_title)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 24)
	box.add_child(sides)
	_give = _column(sides, "YOU GIVE  (click to take back)")
	_get = _column(sides, "YOU GET")
	_ticks = Label.new()
	_ticks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_ticks)
	Widgets.title(box, "Your guns and armour  (click to offer)", 16)
	_bag = GridContainer.new()
	_bag.columns = 3
	box.add_child(_bag)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	_ready_button = _button(row, "Ready", func() -> void: ready_set.emit(not bool(_view.get("ready_mine", false))))
	_confirm_button = _button(row, "Confirm trade", func() -> void: confirmed.emit())
	_button(row, "Cancel", func() -> void: cancelled.emit())
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(1.0, 0.85, 0.5)
	box.add_child(_status)
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card)
	Widgets.fill(_card)
	_card.draw.connect(_draw_card)


func _process(_delta: float) -> void:
	if visible and not _hover.is_empty():
		_card.queue_redraw()  # the card follows the mouse


# What the hovered thing is, exactly as the bag shows it: a gun with its stats against the gun in hand, armour with its lines.
func _draw_card() -> void:
	if _hover.is_empty():
		return
	var place := _card.get_local_mouse_position() + Vector2(18, 18)
	var view := get_viewport_rect().size
	if _hover.has("gun"):
		var gun: Dictionary = _hover["gun"]
		var held: Dictionary = _inventory.holster_gun(in_hand) if in_hand >= 0 else {}
		HoverCard.draw_gun(_card, ThemeDB.fallback_font, _gun_db, gun, held, place, view, "Rolled gun" if held.is_empty() else "compared with the gun in hand")
	else:
		HoverCard.draw_item(_card, ThemeDB.fallback_font, _items, String(_hover["id"]), place, view)


func _watch(over: Control, thing: Dictionary) -> void:
	over.mouse_filter = Control.MOUSE_FILTER_STOP
	over.mouse_entered.connect(func() -> void:
		_hover = thing
		_card.queue_redraw())
	over.mouse_exited.connect(func() -> void:
		if _hover == thing:
			_hover = {}
			_card.queue_redraw())


# view: what the desk says this player sees (core/trade_desk.gd `_views`).
func show_table(view: Dictionary) -> void:
	_view = view
	_hover = {}
	_card.queue_redraw()
	visible = true
	_title.text = "TRADE WITH %s" % String(view["with"]).to_upper()
	_fill(_give, view["mine"], true)
	_fill(_get, view["theirs"], false)
	for old in _bag.get_children():
		_bag.remove_child(old)
		old.queue_free()
	var on_table := {}
	for thing: Dictionary in view["mine"]:
		on_table[int(thing["ref"])] = true
	for slot in InventoryState.SIZE:
		var thing := _thing_in(slot)
		if thing.is_empty() or on_table.has(slot):
			continue
		var pick := _button(_bag, _name_of(thing), func() -> void: offered.emit(thing))
		pick.add_theme_color_override("font_color", _colour_of(thing))
		pick.custom_minimum_size = Vector2(246, 36)
		_watch(pick, thing)
	var theirs: Array = view["theirs"]
	var mine: Array = view["mine"]
	var short := theirs.size() - (_free_slots() + mine.size())
	var both: bool = view["confirm"]
	_ready_button.text = "Not ready after all" if bool(view["ready_mine"]) else "Ready"
	_ready_button.disabled = short > 0 and not bool(view["ready_mine"])
	_confirm_button.visible = both
	_confirm_button.disabled = bool(view["confirmed_mine"])
	_ticks.text = "You: %s        %s: %s" % ["READY" if bool(view["ready_mine"]) else "choosing", view["with"], "READY" if bool(view["ready_theirs"]) else "choosing"]
	if short > 0:
		_status.text = "Make room first: %d more free bag slot%s needed." % [short, "" if short == 1 else "s"]
	elif both:
		_status.text = "Waiting for %s to confirm." % view["with"] if bool(view["confirmed_mine"]) else "Both ready. Look it over, then confirm. Any change starts over."
	else:
		_status.text = "Any change clears both ready ticks."


func close() -> void:
	visible = false
	_hover = {}
	_view = {}


func is_open() -> bool:
	return visible


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


func _name_of(thing: Dictionary) -> String:
	if thing.has("gun"):
		return GunStats.display_name(_gun_db, thing["gun"])
	return String(_items.call("item_name", String(thing["id"])))


func _colour_of(thing: Dictionary) -> Color:
	if thing.has("gun"):
		return TierStyle.color(_gun_db, String((thing["gun"] as Dictionary)["tier"]), 0.0)
	return Color(0.9, 0.9, 0.9)


func _fill(column: VBoxContainer, things: Array, mine: bool) -> void:
	for old in column.get_children():
		column.remove_child(old)
		old.queue_free()
	for thing: Dictionary in things:
		if mine:
			var back := _button(column, _name_of(thing), withdrawn.emit.bind(int(thing["ref"])))
			back.add_theme_color_override("font_color", _colour_of(thing))
			_watch(back, thing)
		else:
			var line := Label.new()
			line.text = _name_of(thing)
			line.modulate = _colour_of(thing)
			line.custom_minimum_size = Vector2(0, 36)
			column.add_child(line)
			_watch(line, thing)
	if things.is_empty():
		var none := Label.new()
		none.text = "(nothing yet)"
		none.modulate = Color(1, 1, 1, 0.4)
		column.add_child(none)


func _column(parent: Container, heading: String) -> VBoxContainer:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.custom_minimum_size = Vector2(0, 230)
	parent.add_child(outer)
	Widgets.title(outer, heading, 16)
	var list := VBoxContainer.new()
	outer.add_child(list)
	return list


func _button(parent: Container, text: String, on_press: Callable) -> Button:
	var made := Button.new()
	made.text = text
	made.custom_minimum_size = Vector2(0, 36)
	made.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	made.clip_text = true
	made.pressed.connect(on_press)
	parent.add_child(made)
	return made
