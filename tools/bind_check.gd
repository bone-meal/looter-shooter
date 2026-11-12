# Purpose: developer check of the key bindings (game/input_setup.gd with core/settings_state.gd): three bindings per
# control, the wheel as a binding, a key moving from one control to another, emptying a slot, the magic keys' own
# group, and saving / loading (old one-key settings included). Log tools/bind_check.log (ends BIND_CHECK_DONE problems=n).
# It works on its own SettingsState and puts the real bindings back before it quits.
# Dependencies: game/input_setup.gd, core/settings_state.gd.
extends Node

const InputSetup = preload("res://game/input_setup.gd")
const SettingsState = preload("res://core/settings_state.gd")

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var settings := SettingsState.new()
	InputSetup.register(settings)
	var space := "key:%d" % KEY_SPACE
	var up := "mouse:%d" % MOUSE_BUTTON_WHEEL_UP
	var down := "mouse:%d" % MOUSE_BUTTON_WHEEL_DOWN
	_say("jump starts as Space only", InputSetup.codes(settings, "jump") == PackedStringArray([space]))
	_say("the wheel is free at first", not InputSetup.used(settings, up) and not InputSetup.used(settings, down))
	InputSetup.bind(settings, "jump", 1, up)
	InputSetup.bind(settings, "jump", 2, down)
	_say("jump = Space + wheel up + wheel down", InputSetup.codes(settings, "jump") == PackedStringArray([space, up, down]))
	_say("the engine knows all three", InputMap.action_get_events("jump").size() == 3)
	_say("the wheel counts as used now (it stops switching guns)", InputSetup.used(settings, up) and InputSetup.used(settings, down))
	var tick := InputEventMouseButton.new()
	tick.button_index = MOUSE_BUTTON_WHEEL_DOWN
	tick.pressed = true
	_say("a wheel tick is a jump press", tick.is_action_pressed("jump"))
	_say("names: %s / %s / %s" % [InputSetup.describe(space), InputSetup.describe(up), InputSetup.describe("mouse:%d" % MOUSE_BUTTON_XBUTTON1)], InputSetup.describe(up) == "Wheel Up")
	InputSetup.bind(settings, "jump", 2, "key:%d" % KEY_V)
	_say("a slot can be overwritten, never more than three", InputSetup.codes(settings, "jump").size() == 3 and not InputSetup.used(settings, down))

	var w := "key:%d" % KEY_W
	var from := InputSetup.bind(settings, "crouch", 1, w)
	_say("W moved from \"%s\" to crouch" % from, from == "Move forward" and InputSetup.codes(settings, "crouch").has(w) and InputSetup.codes(settings, "move_forward").is_empty())
	_say("a control left with nothing reads \"unbound\"", InputSetup.label(settings, "move_forward") == "unbound" and InputMap.action_get_events("move_forward").is_empty())
	InputSetup.unbind(settings, "crouch", 0)
	_say("emptying a slot moves the rest up", InputSetup.codes(settings, "crouch") == PackedStringArray([w]))
	var q := "key:%d" % KEY_Q
	InputSetup.bind(settings, "element_water", 1, q)
	_say("the magic keys share with the rest (Q is still gun skill 1)", InputSetup.codes(settings, "skill_1").has(q) and InputSetup.codes(settings, "element_water").has(q))

	var again := SettingsState.new()
	again.from_dict(JSON.parse_string(JSON.stringify(settings.to_dict())))
	_say("saved and loaded: jump keeps its three", InputSetup.codes(again, "jump") == InputSetup.codes(settings, "jump") and InputSetup.codes(again, "move_forward").is_empty())
	var old := SettingsState.new()
	old.from_dict({"bindings": {"jump": "key:%d" % KEY_J}})
	_say("settings from before (one key per control) still load", InputSetup.codes(old, "jump") == PackedStringArray(["key:%d" % KEY_J]) and InputSetup.codes(old, "sprint").size() == 1)
	InputSetup.reset_to_defaults(settings)
	_say("reset: Space only again, forward is W", InputSetup.codes(settings, "jump") == PackedStringArray([space]) and InputSetup.codes(settings, "move_forward") == PackedStringArray([w]))

	_lines.append("BIND_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/bind_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()


func _say(text: String, fine: bool) -> void:
	if not fine:
		_problems += 1
	_lines.append(("ok   " if fine else "FAIL ") + text)
