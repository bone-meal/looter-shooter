# Purpose: the board at the colosseum painting: pick a ticket (how many waves, for how many points), tick the
# modifiers that make the run harder and its loot better, and go in. Draws and asks only: core/colosseum_rules.gd
# knows the tickets and modifiers, the session pays and starts the run.
# Dependencies: core/colosseum_rules.gd, game/menu_widgets.gd. `open(points)` shows it; signals chosen / closed.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")

signal chosen(ticket: int, modifiers: PackedStringArray)
signal closed

const HOVER_HINT := "Point at a modifier to see what it does."

var rules: RefCounted  # core/colosseum_rules.gd, set before add_child
var tier_name := Callable()  # func(tier id) -> String, for the summary line

var _points := 0
var _ticket := 0
var _tickets: Array[Button] = []
var _ticks := {}  # modifier id -> CheckBox
var _have := Label.new()
var _summary := Label.new()
var _about := Label.new()  # what the modifier under the mouse does (also its tooltip)
var _go: Button


func _ready() -> void:
	visible = false
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.05, 0.04, 0.03, 0.9))
	var box := Widgets.centered_column(self, 760)
	Widgets.title(box, "THE COLOSSEUM")
	_have.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_have)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(row)
	var group := ButtonGroup.new()
	for i in int(rules.call("ticket_count")):
		var entry: Dictionary = rules.call("ticket", i)
		var pick := Button.new()
		pick.toggle_mode = true
		pick.button_group = group
		pick.text = "%s\n%d points" % [String(entry["name"]), int(entry["price"])]
		pick.custom_minimum_size = Vector2(240, 64)
		pick.pressed.connect(_pick.bind(i))
		row.add_child(pick)
		_tickets.append(pick)
	var mods: Array = rules.call("modifiers") if rules.has_method("modifiers") else []
	if not mods.is_empty():
		var head := Label.new()
		head.text = "MODIFIERS: each makes the run harder and the loot better"
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.modulate = Color(0.95, 0.8, 0.5)
		box.add_child(head)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(760, 300)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		box.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)
		for mod: Dictionary in mods:
			var tick := CheckBox.new()
			tick.text = "%s  (+%d %% loot)" % [String(mod["name"]), roundi(float(mod["loot"]) * 100.0)]
			tick.tooltip_text = "%s\n+%d %% loot" % [String(mod["desc"]), roundi(float(mod["loot"]) * 100.0)]
			tick.custom_minimum_size = Vector2(370, 0)
			tick.toggled.connect(func(_on: bool) -> void: _refresh())
			tick.mouse_entered.connect(func() -> void: _about.text = "%s: %s" % [String(mod["name"]), String(mod["desc"])])
			tick.mouse_exited.connect(func() -> void: _about.text = HOVER_HINT)
			grid.add_child(tick)
			_ticks[String(mod["id"])] = tick
	_about.text = HOVER_HINT
	_about.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(760, 46)
	_about.modulate = Color(0.95, 0.85, 0.6)
	box.add_child(_about)
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.custom_minimum_size = Vector2(760, 76)
	box.add_child(_summary)
	_go = Button.new()
	_go.custom_minimum_size = Vector2(0, 48)
	_go.pressed.connect(func() -> void: chosen.emit(_ticket, picked()))
	box.add_child(_go)
	Widgets.button(box, "Back", func() -> void: closed.emit())


# Shows the board for a player with that many points.
func open(points: int) -> void:
	_points = points
	visible = true
	_tickets[_ticket].set_pressed_no_signal(true)
	_refresh()


func close() -> void:
	visible = false


# The ids of the ticked modifiers.
func picked() -> PackedStringArray:
	var ids := PackedStringArray()
	for id: String in _ticks:
		if (_ticks[id] as CheckBox).button_pressed:
			ids.append(id)
	return ids


# Test scripts: choose a ticket and tick modifiers as a player would.
func choose(ticket: int, modifiers: PackedStringArray) -> void:
	_ticket = clampi(ticket, 0, _tickets.size() - 1)
	_tickets[_ticket].set_pressed_no_signal(true)
	for id: String in _ticks:
		(_ticks[id] as CheckBox).set_pressed_no_signal(modifiers.has(id))
	_refresh()


func _pick(index: int) -> void:
	_ticket = index
	_refresh()


func _refresh() -> void:
	var entry: Dictionary = rules.call("ticket", _ticket)
	var waves := int(entry["waves"])
	var price := int(entry["price"])
	_have.text = "You have %d points" % _points
	var chest: Array = rules.call("chest_tiers", waves)
	var lines := "%d waves, each tougher than the last. Ordinary kills leave %s guns at the end; the chest holds %d %s." % [waves, _named(String(rules.call("band_tier", waves))), chest.size(), _named(String(chest[0]))]
	var mods := picked()
	if not mods.is_empty():
		lines += "\n%d modifiers: loot chances x%.2f." % [mods.size(), float(rules.call("loot_mult", mods))]
	_summary.text = lines
	_go.text = "Go in  (%d points)" % price
	_go.disabled = _points < price


func _named(tier: String) -> String:
	return String(tier_name.call(tier)) if tier_name.is_valid() else tier
