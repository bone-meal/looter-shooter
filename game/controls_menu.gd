# Purpose: controls screen: one row per action; click a row's button, then press a key or mouse button to rebind (Esc cancels).
# Dependencies: game/input_setup.gd, game/menu_widgets.gd, core/settings_state.gd. Emits changed on every rebind and closed on Back.
extends Control

const InputSetup = preload("res://game/input_setup.gd")
const Widgets = preload("res://game/menu_widgets.gd")
const SettingsState = preload("res://core/settings_state.gd")

signal changed
signal closed

var settings: SettingsState  # set before add_child

var _buttons := {}  # action -> Button
var _waiting := ""  # action currently waiting for a key press ("" = none)


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.05, 0.05, 0.05, 0.92))
	var box := Widgets.centered_column(self, 520)
	Widgets.title(box, "CONTROLS")
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 360)
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for entry in InputSetup.ACTIONS:
		_add_row(rows, entry[0], entry[1])
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
	var is_mouse: bool = event is InputEventMouseButton and event.pressed and event.button_index <= MOUSE_BUTTON_MIDDLE
	if not (is_key or is_mouse):
		return
	InputSetup.bind(settings, _waiting, InputSetup.event_to_code(event))
	_waiting = ""
	_refresh()
	changed.emit()
	get_viewport().set_input_as_handled()


func _add_row(rows: Container, action: String, label_text: String) -> void:
	var row := HBoxContainer.new()
	rows.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(250, 0)
	row.add_child(label)
	var button := Button.new()
	button.custom_minimum_size = Vector2(200, 0)
	button.pressed.connect(_begin_wait.bind(action))
	row.add_child(button)
	_buttons[action] = button


func _begin_wait(action: String) -> void:
	_waiting = action
	_refresh()


func _reset() -> void:
	_waiting = ""
	InputSetup.reset_to_defaults(settings)
	_refresh()
	changed.emit()


func _refresh() -> void:
	for action in _buttons:
		_buttons[action].text = "Press a key..." if action == _waiting else InputSetup.label(settings, action)
