# Purpose: all input actions, their default keys, and rebinding. Bindings are saved in settings as strings like "key:87" or "mouse:1".
# Dependencies: core/settings_state.gd (its `bindings` dictionary; an action with no entry uses its default).
extends RefCounted

# [action, label shown in the controls menu]
const ACTIONS := [
	["move_forward", "Move forward"],
	["move_back", "Move backward"],
	["move_left", "Move left"],
	["move_right", "Move right"],
	["jump", "Jump"],
	["sprint", "Sprint"],
	["crouch", "Crouch"],
	["shoot", "Shoot"],
	["aim", "Aim down sights"],
	["reload", "Reload"],
	["interact", "Interact"],
	["skill_1", "Gun skill 1"],
	["skill_2", "Gun skill 2"],
	["toggle_view", "Switch 1st/3rd person"],
	["inventory", "Inventory"],
	["card", "Player card"],
	["chat", "Chat"],
	["command", "Chat command (/)"],
	["skills", "Skills panel"],
	["quests", "Quest log"],
	["map", "World map"],
	["element_water", "Magic: add water (while channelling)"],
	["element_fire", "Magic: add fire (while channelling)"],
	["element_earth", "Magic: add earth (while channelling)"],
	["element_air", "Magic: add air (while channelling)"],
	["element_gravity", "Magic: add gravity (while channelling)"],
	["dodge", "Dodge step (fantasy world)"],
	["drop_item", "Inventory: drop the gun under the mouse"],
	["weapon_1", "Hotbar slot 1"],
	["weapon_2", "Hotbar slot 2"],
	["weapon_3", "Hotbar slot 3"],
	["weapon_4", "Hotbar slot 4"],
	["weapon_5", "Hotbar slot 5"],
	["weapon_6", "Hotbar slot 6"],
	["weapon_7", "Hotbar slot 7"],
	["weapon_8", "Hotbar slot 8"],
	["weapon_9", "Hotbar slot 9"],
]


static func default_code(action: String) -> String:
	match action:
		"move_forward": return "key:%d" % KEY_W
		"move_back": return "key:%d" % KEY_S
		"move_left": return "key:%d" % KEY_A
		"move_right": return "key:%d" % KEY_D
		"jump": return "key:%d" % KEY_SPACE
		"sprint": return "key:%d" % KEY_SHIFT
		"crouch": return "key:%d" % KEY_C
		"shoot": return "mouse:%d" % MOUSE_BUTTON_LEFT
		"aim": return "mouse:%d" % MOUSE_BUTTON_RIGHT
		"reload": return "key:%d" % KEY_R
		"interact": return "key:%d" % KEY_F
		"skill_1": return "key:%d" % KEY_Q
		"skill_2": return "key:%d" % KEY_E
		"toggle_view": return "key:%d" % KEY_B
		"inventory": return "key:%d" % KEY_I
		"card": return "key:%d" % KEY_P
		"chat": return "key:%d" % KEY_ENTER
		"command": return "key:%d" % KEY_SLASH
		"skills": return "key:%d" % KEY_K
		"quests": return "key:%d" % KEY_L
		"map": return "key:%d" % KEY_M
		"element_water": return "key:%d" % KEY_Q  # the element keys share Q, E, 1, 3 with gun skills and the hotbar:
		"element_fire": return "key:%d" % KEY_E  # they only act while left click is held with a staff
		"element_earth": return "key:%d" % KEY_1
		"element_air": return "key:%d" % KEY_3
		"element_gravity": return "key:%d" % KEY_R  # R still reloads guns: it is an element only while channelling
		"dodge": return "key:%d" % KEY_CTRL
		"drop_item": return "key:%d" % KEY_G
	if action.begins_with("weapon_"):
		return "key:%d" % (KEY_1 + int(action.substr(7)) - 1)
	return ""


static func current_code(settings: RefCounted, action: String) -> String:
	return settings.bindings.get(action, default_code(action))


# Creates every action and applies the saved (or default) binding. Call once at startup after settings load.
static func register(settings: RefCounted) -> void:
	for entry in ACTIONS:
		var action: String = entry[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		apply(action, current_code(settings, action))


static func apply(action: String, code: String) -> void:
	InputMap.action_erase_events(action)
	var event := _event_from_code(code)
	if event != null:
		InputMap.action_add_event(action, event)


# Binds `code` to `action`; if another action already uses it, that action gets this action's old binding (swap).
static func bind(settings: RefCounted, action: String, code: String) -> void:
	var old := current_code(settings, action)
	for entry in ACTIONS:
		var other: String = entry[0]
		if other != action and current_code(settings, other) == code and other.begins_with("element_") == action.begins_with("element_"):
			settings.bindings[other] = old
			apply(other, old)
	settings.bindings[action] = code
	apply(action, code)


static func reset_to_defaults(settings: RefCounted) -> void:
	settings.bindings.clear()
	register(settings)


# "key:87" for a key press, "mouse:1" for a mouse button, "" for anything else.
static func event_to_code(event: InputEvent) -> String:
	if event is InputEventKey:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		return "key:%d" % key
	if event is InputEventMouseButton:
		return "mouse:%d" % event.button_index
	return ""


static func describe(code: String) -> String:
	var parts := code.split(":")
	if parts.size() != 2:
		return "?"
	var value := int(parts[1])
	if parts[0] == "key":
		var shown: int = DisplayServer.keyboard_get_label_from_physical(value as Key)
		return OS.get_keycode_string((shown if shown != 0 else value) as Key)
	match value:
		MOUSE_BUTTON_LEFT: return "Left Mouse"
		MOUSE_BUTTON_RIGHT: return "Right Mouse"
		MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
	return "Mouse %d" % value


static func label(settings: RefCounted, action: String) -> String:
	return describe(current_code(settings, action))


static func _event_from_code(code: String) -> InputEvent:
	var parts := code.split(":")
	if parts.size() != 2:
		return null
	var value := int(parts[1])
	if parts[0] == "key":
		var key := InputEventKey.new()
		key.physical_keycode = value as Key
		return key
	if parts[0] == "mouse":
		var mouse := InputEventMouseButton.new()
		mouse.button_index = value as MouseButton
		return mouse
	return null
