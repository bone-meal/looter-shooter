# Purpose: all input actions, their default keys, and rebinding. A control can have up to SLOTS bindings (keys, mouse
# buttons, wheel directions), saved in settings as codes like "key:87" or "mouse:4" (wheel up).
# Dependencies: core/settings_state.gd (its `bindings` dictionary: action -> list of codes; no entry = the default).
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
	["scoreboard", "Scoreboard (hold)"],
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
	["weapon_1", "Gun 1"],
	["weapon_2", "Gun 2"],
	["knife", "Knife"],
	["shield", "Shield: hold it up / sling it on your back"],
	["weapon_3", "Gun 3 (with a third holster)"],
	["weapon_4", "Gun 4 (with a fourth holster)"],
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
		"scoreboard": return "key:%d" % KEY_TAB
		"chat": return "key:%d" % KEY_ENTER
		"command": return "key:%d" % KEY_SLASH
		"skills": return "key:%d" % KEY_K
		"quests": return "key:%d" % KEY_L
		"map": return "key:%d" % KEY_M
		"element_water": return "key:%d" % KEY_Q  # the element keys share Q, E, 1, 3 with gun skills, gun 1 and the knife:
		"element_fire": return "key:%d" % KEY_E  # they only act while left click is held with a staff
		"element_earth": return "key:%d" % KEY_1
		"element_air": return "key:%d" % KEY_3
		"element_gravity": return "key:%d" % KEY_R  # R still reloads guns: it is an element only while channelling
		"dodge": return "key:%d" % KEY_CTRL
		"drop_item": return "key:%d" % KEY_G
		"weapon_1": return "key:%d" % KEY_1
		"weapon_2": return "key:%d" % KEY_2
		"knife": return "key:%d" % KEY_3
		"shield": return "key:%d" % KEY_X
		"weapon_3": return "key:%d" % KEY_4
		"weapon_4": return "key:%d" % KEY_5
	return ""


const SLOTS := 3  # how many keys, mouse buttons or wheel directions one control can have


# What is bound to an action, first slot first (none = unbound; nothing saved = its default).
static func codes(settings: RefCounted, action: String) -> PackedStringArray:
	var saved: Variant = settings.bindings.get(action)
	if saved is Array:
		return PackedStringArray(saved)
	var default := default_code(action)
	return PackedStringArray([default]) if default != "" else PackedStringArray()


# The first of them ("" = unbound): what prompts and hints show.
static func current_code(settings: RefCounted, action: String) -> String:
	var all := codes(settings, action)
	return all[0] if not all.is_empty() else ""


# True when some control uses this code (the player's wheel stops switching weapons in a direction that is bound).
static func used(settings: RefCounted, code: String) -> bool:
	for entry in ACTIONS:
		if codes(settings, entry[0]).has(code):
			return true
	return false


# Creates every action and applies the saved (or default) bindings. Call once at startup after settings load.
static func register(settings: RefCounted) -> void:
	for entry in ACTIONS:
		var action: String = entry[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		apply(action, codes(settings, action))


static func apply(action: String, bound: PackedStringArray) -> void:
	InputMap.action_erase_events(action)
	for code in bound:
		var event := _event_from_code(code)
		if event != null:
			InputMap.action_add_event(action, event)


# Puts `code` into slot `slot` (0-based) of `action`. A code another control already has MOVES here and leaves that
# control; returns that control's label ("" = it was free). The magic element keys are a group of their own: they may
# share keys with the rest (they only act while a spell is gathered).
static func bind(settings: RefCounted, action: String, slot: int, code: String) -> String:
	var taken := ""
	for entry in ACTIONS:
		var other: String = entry[0]
		if other.begins_with("element_") != action.begins_with("element_"):
			continue
		var theirs := codes(settings, other)
		var at := theirs.find(code)
		if at >= 0:
			theirs.remove_at(at)
			_store(settings, other, theirs)
			if other != action:
				taken = String(entry[1])
	var mine := codes(settings, action)
	if slot < mine.size():
		mine[slot] = code
	elif mine.size() < SLOTS:
		mine.append(code)
	_store(settings, action, mine)
	return taken


# Empties one slot of an action (the later ones move up).
static func unbind(settings: RefCounted, action: String, slot: int) -> void:
	var mine := codes(settings, action)
	if slot < mine.size():
		mine.remove_at(slot)
		_store(settings, action, mine)


static func _store(settings: RefCounted, action: String, bound: PackedStringArray) -> void:
	settings.bindings[action] = Array(bound)
	apply(action, bound)


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
		MOUSE_BUTTON_WHEEL_UP: return "Wheel Up"
		MOUSE_BUTTON_WHEEL_DOWN: return "Wheel Down"
		MOUSE_BUTTON_WHEEL_LEFT: return "Wheel Left"
		MOUSE_BUTTON_WHEEL_RIGHT: return "Wheel Right"
		MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
		MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
	return "Mouse %d" % value


static func label(settings: RefCounted, action: String) -> String:
	var code := current_code(settings, action)
	return describe(code) if code != "" else "unbound"


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
