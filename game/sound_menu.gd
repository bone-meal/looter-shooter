# Purpose: the Sounds page of the settings: every sound of the game by its label, in groups (data/sound_list.json).
# A tick = the sound plays; untick it to mute that one sound. A sound that is being heard right now is lit (gold,
# "playing"); while the game is paused the page shows what was heard at the moment it stopped. The muted ids are
# kept in the settings (core/settings_state.gd `muted_sounds`).
# Dependencies: core/settings_state.gd, core/data_store.gd, game/sound_board.gd, game/menu_widgets.gd.
extends Control

const SettingsState = preload("res://core/settings_state.gd")
const DataStore = preload("res://core/data_store.gd")
const SoundBoard = preload("res://game/sound_board.gd")
const Widgets = preload("res://game/menu_widgets.gd")

signal changed
signal closed

const HEARD_MS := 2500  # a sound stays lit this long after it was audible
const QUIET := Color(0.85, 0.85, 0.85)
const LIT := Color(1.0, 0.82, 0.3)

var settings: SettingsState  # set before add_child

var _rows := {}  # sound id -> {"tick": CheckBox, "label": String}
var _now := Label.new()  # "Hearing now: ..." above the list, so nobody has to scroll to find the lit rows
var _timer := 0.0


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.05, 0.05, 0.05, 0.9))
	var box := Widgets.centered_column(self, 560)
	Widgets.title(box, "SOUNDS")
	var hint := Label.new()
	hint.text = "Untick a sound to mute it. Gold = you are hearing it now."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now.custom_minimum_size = Vector2(560, 48)
	_now.modulate = LIT
	box.add_child(_now)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 330)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for group: Dictionary in DataStore.load_json("res://data/sound_list.json").get("groups", []):
		var head := Label.new()
		head.text = String(group["name"]).to_upper()
		head.add_theme_font_size_override("font_size", 14)
		head.modulate = Color(0.6, 0.78, 0.95)
		list.add_child(head)
		for sound: Dictionary in group["sounds"]:
			var id := String(sound["id"])
			var tick := CheckBox.new()
			tick.text = String(sound["label"])
			tick.button_pressed = not settings.muted_sounds.has(id)
			tick.toggled.connect(_on_toggled.bind(id))
			list.add_child(tick)
			_rows[id] = {"tick": tick, "label": String(sound["label"])}
	Widgets.button(box, "Unmute all", _unmute_all)
	Widgets.button(box, "Back", func() -> void: closed.emit())
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func _on_toggled(on: bool, id: String) -> void:
	settings.muted_sounds.erase(id)
	if not on:
		settings.muted_sounds.append(id)
	SoundBoard.set_muted(settings.muted_sounds)
	changed.emit()


func _unmute_all() -> void:
	settings.muted_sounds.clear()
	SoundBoard.set_muted(settings.muted_sounds)
	for id: String in _rows:
		(_rows[id]["tick"] as CheckBox).set_pressed_no_signal(true)
	changed.emit()


# Five times a second: lights the sounds that are audible now (paused: at the moment the game stopped).
func _process(delta: float) -> void:
	if not visible:
		return
	_timer += delta
	if _timer >= 0.2:
		_timer = 0.0
		_refresh()


func _refresh() -> void:
	var moment := SoundBoard.latest() if get_tree().paused else Time.get_ticks_msec()
	var names := PackedStringArray()
	for id: String in _rows:
		var tick: CheckBox = _rows[id]["tick"]
		var lit := tick.button_pressed and SoundBoard.hearing(id, moment, HEARD_MS)
		tick.modulate = LIT if lit else QUIET
		tick.text = String(_rows[id]["label"]) + ("   (playing)" if lit else "")
		if lit:
			names.append(String(_rows[id]["label"]))
	_now.text = "Hearing now: " + (", ".join(names) if not names.is_empty() else "nothing")
