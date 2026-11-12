# Purpose: controls screen: one row per action with up to three bindings; click a slot, then press a key or mouse button
# or roll the wheel (Delete empties the slot, Esc cancels). A key another control had moves over and the screen says so.
# Dependencies: game/input_setup.gd, game/menu_widgets.gd, core/settings_state.gd. Emits changed on every rebind and closed on Back.
extends Control

const InputSetup = preload("res://game/input_setup.gd")
const Widgets = preload("res://game/menu_widgets.gd")
const SettingsState = preload("res://core/settings_state.gd")

signal changed
signal closed

var settings: SettingsState  # set before add_child

var _buttons := {}  # action -> its SLOTS buttons
var _waiting := ""  # action currently waiting for a key press ("" = none)
var _slot := 0  # which of its slots
var _note: Label  # what the last change did (e.g. which control a key was taken from)


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.05, 0.05, 0.05, 0.92))
	var box := Widgets.centered_column(self, 700)
	Widgets.title(box, "CONTROLS")
	var hint := Label.new()
	hint.text = "Each control takes up to three: click a slot, then press a key or a mouse button, or roll the wheel. Delete empties the slot, Esc cancels."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(700, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for entry in InputSetup.ACTIONS:
		_add_row(rows, entry[0], entry[1])
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_font_size_override("font_size", 14)
	_note.modulate = Color(1.0, 0.85, 0.5)
	box.add_child(_note)
	Widgets.button(box, "Reset to defaults", _reset)
	Widgets.button(box, "Back", func() -> void: closed.emit())
	_refresh()


# True while a rebind is in progress, so Esc cancels it instead of closing the menu.
func is_waiting() -> bool:
	return _waiting != ""


func cancel_wait() -> void:
	_waiting = ""
	_refresh()


func _input(event: InputEvent) -> void:
	if _waiting == "" or not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_wait()
		get_viewport().set_input_as_handled()
		return
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	var is_mouse: bool = event is InputEventMouseButton and event.pressed and event.button_index <= MOUSE_BUTTON_XBUTTON2
	if not (is_key or is_mouse):
		return
	_note.text = ""
	if is_key and event.keycode == KEY_DELETE:
		InputSetup.unbind(settings, _waiting, _slot)
	else:
		var code := InputSetup.event_to_code(event)
		var from := InputSetup.bind(settings, _waiting, _slot, code)
		if from != "":
			_note.text = "%s was taken from \"%s\"." % [InputSetup.describe(code), from]
	_waiting = ""
	_refresh()
	changed.emit()
	get_viewport().set_input_as_handled()


func _add_row(rows: Container, action: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	rows.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(270, 0)
	row.add_child(label)
	var slots: Array[Button] = []
	for slot in InputSetup.SLOTS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(130, 0)
		button.pressed.connect(_begin_wait.bind(action, slot))
		row.add_child(button)
		slots.append(button)
	_buttons[action] = slots


func _begin_wait(action: String, slot: int) -> void:
	_waiting = action
	_slot = mini(slot, InputSetup.codes(settings, action).size())  # the first empty slot when a later one was clicked
	_refresh()


func _reset() -> void:
	_waiting = ""
	_note.text = ""
	InputSetup.reset_to_defaults(settings)
	_refresh()
	changed.emit()


func _refresh() -> void:
	for action: String in _buttons:
		var bound := InputSetup.codes(settings, action)
		for slot in InputSetup.SLOTS:
			var button: Button = _buttons[action][slot]
			if action == _waiting and slot == _slot:
				button.text = "Press..."
			else:
				button.text = InputSetup.describe(bound[slot]) if slot < bound.size() else "-"
