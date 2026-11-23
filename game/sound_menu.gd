# Purpose: the Sounds page of the settings (polish1 item 3, redesigned as game UI): MASTER and MUSIC volume at the top,
# then one card per group of sounds (data/sound_list.json) with its own volume slider, a mute switch and a count; a
# card opens to the group's sounds, each with a tick (untick = that one sound is muted). A sound heard right now is lit
# gold, its group card too, and "Hearing now" names them (paused: what was heard at the moment the game stopped).
# Kept in the settings: `volume`, `sound_groups`, `muted_sounds` (core/settings_state.gd); the music volume is the
# music box's own (game/music_box.gd set_volume).
# Dependencies: core/settings_state.gd, core/data_store.gd, game/sound_board.gd, game/menu_widgets.gd, game/ui_skin.gd.
extends Control

const SettingsState = preload("res://core/settings_state.gd")
const DataStore = preload("res://core/data_store.gd")
const SoundBoard = preload("res://game/sound_board.gd")
const Widgets = preload("res://game/menu_widgets.gd")
const UiSkin = preload("res://game/ui_skin.gd")

signal changed
signal closed

const HEARD_MS := 2500  # a sound stays lit this long after it was audible
const QUIET := Color(0.85, 0.85, 0.85)
const LIT := Color(1.0, 0.82, 0.3)
const WIDTH := 720.0

var settings: SettingsState  # set before add_child
var music: Node  # game/music_box.gd (its own volume); null = no music slider

var _rows := {}  # sound id -> {"tick": CheckBox, "label": String, "group": name}
var _groups := {}  # group name -> {"card": PanelContainer, "list": VBoxContainer, "arrow": Button, "count": Label, "ids": Array}
var _now := Label.new()  # "Hearing now: ..." above the list, so nobody has to scroll to find the lit rows
var _timer := 0.0
var _music_row: Control


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.03, 0.035, 0.05, 0.94))
	var box := Widgets.centered_column(self, WIDTH)
	Widgets.title(box, "SOUNDS")
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now.custom_minimum_size = Vector2(WIDTH, 40)
	_now.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_now.modulate = LIT
	box.add_child(_now)
	var top := _card(box, Color(0.08, 0.09, 0.13, 0.98))
	var levels := VBoxContainer.new()
	levels.add_theme_constant_override("separation", 6)
	top.add_child(levels)
	levels.add_child(_head("VOLUME"))
	levels.add_child(_slider_row("Master", settings.volume, func(v: float) -> void:
		settings.volume = v
		changed.emit()))
	_music_row = _slider_row("Music (jukebox)", float(music.get("volume")) if music != null else 0.8, func(v: float) -> void:
		if music != null:
			music.call("set_volume", v))
	levels.add_child(_music_row)
	_music_row.visible = music != null
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	for group: Dictionary in DataStore.load_json("res://data/sound_list.json").get("groups", []):
		_add_group(list, group)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	for entry: Array in [["Unmute all", _unmute_all], ["Reset volumes", _reset_volumes], ["Back", func() -> void: closed.emit()]]:
		var b := Button.new()
		b.text = String(entry[0])
		b.custom_minimum_size = Vector2(180, 44)
		b.pressed.connect(entry[1])
		buttons.add_child(b)
	visibility_changed.connect(func() -> void:
		if visible:
			_music_row.visible = music != null
			_refresh())


# A rounded dark card (game/ui_skin.gd look) holding one child.
func _card(parent: Container, fill: Color) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = UiSkin.EDGE
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	return card


func _head(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.modulate = UiSkin.ACCENT
	return label


# "Name  [=====|----]  80 %"
func _slider_row(text: String, value: float, on_change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var name_label := Label.new()
	name_label.text = text
	name_label.custom_minimum_size = Vector2(220, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var shown := Label.new()
	shown.text = "%d %%" % roundi(value * 100.0)
	shown.custom_minimum_size = Vector2(56, 0)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(shown)
	slider.value_changed.connect(func(v: float) -> void:
		shown.text = "%d %%" % roundi(v * 100.0)
		on_change.call(v))
	return row


# One group: a card with an open / close arrow, its name, how many are muted, its volume and a mute switch; the
# group's sounds below it while open.
func _add_group(parent: Container, group: Dictionary) -> void:
	var group_name := String(group["name"])
	var card := _card(parent, Color(0.06, 0.07, 0.1, 0.96))
	var column := VBoxContainer.new()
	card.add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var arrow := Button.new()
	arrow.text = ">"
	arrow.flat = true
	arrow.custom_minimum_size = Vector2(30, 30)
	row.add_child(arrow)
	var title := Label.new()
	title.text = group_name
	title.custom_minimum_size = Vector2(196, 0)
	row.add_child(title)
	var slider_row := _slider_row("", float(settings.sound_groups.get(group_name, 1.0)), func(v: float) -> void:
		settings.sound_groups[group_name] = v
		SoundBoard.set_groups(settings.sound_groups)
		changed.emit())
	slider_row.get_child(0).custom_minimum_size = Vector2(0, 0)
	slider_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider_row)
	var count := Label.new()
	count.custom_minimum_size = Vector2(96, 0)
	count.add_theme_font_size_override("font_size", 13)
	count.modulate = UiSkin.TEXT_DIM
	row.add_child(count)
	var mute := CheckButton.new()
	mute.tooltip_text = "All of this group on / off"
	row.add_child(mute)
	var list := VBoxContainer.new()
	list.visible = false
	column.add_child(list)
	var ids: Array = []
	for sound: Dictionary in group["sounds"]:
		var id := String(sound["id"])
		var tick := CheckBox.new()
		tick.text = String(sound["label"])
		tick.button_pressed = not settings.muted_sounds.has(id)
		tick.toggled.connect(_on_toggled.bind(id))
		list.add_child(tick)
		_rows[id] = {"tick": tick, "label": String(sound["label"]), "group": group_name}
		ids.append(id)
	_groups[group_name] = {"card": card, "list": list, "arrow": arrow, "count": count, "ids": ids, "mute": mute, "title": title}
	arrow.pressed.connect(func() -> void:
		list.visible = not list.visible
		arrow.text = "v" if list.visible else ">")
	mute.button_pressed = _group_on(group_name)
	mute.toggled.connect(func(on: bool) -> void:
		for id: String in ids:
			(_rows[id]["tick"] as CheckBox).button_pressed = on)  # each tick saves itself
	_count(group_name)


func _group_on(group_name: String) -> bool:
	for id: String in _groups[group_name]["ids"]:
		if not settings.muted_sounds.has(id):
			return true
	return false


func _count(group_name: String) -> void:
	var ids: Array = _groups[group_name]["ids"]
	var off := 0
	for id: String in ids:
		if settings.muted_sounds.has(id):
			off += 1
	(_groups[group_name]["count"] as Label).text = "%d sounds" % ids.size() if off == 0 else "%d of %d muted" % [off, ids.size()]
	(_groups[group_name]["mute"] as CheckButton).set_pressed_no_signal(off < ids.size())


func _on_toggled(on: bool, id: String) -> void:
	settings.muted_sounds.erase(id)
	if not on:
		settings.muted_sounds.append(id)
	SoundBoard.set_muted(settings.muted_sounds)
	_count(String(_rows[id]["group"]))
	changed.emit()


func _unmute_all() -> void:
	settings.muted_sounds.clear()
	SoundBoard.set_muted(settings.muted_sounds)
	for id: String in _rows:
		(_rows[id]["tick"] as CheckBox).set_pressed_no_signal(true)
	for group_name: String in _groups:
		_count(group_name)
	changed.emit()


func _reset_volumes() -> void:
	settings.sound_groups = settings.GROUP_DEFAULTS.duplicate()  # (polish1 item 158) Spells back to 50 %
	SoundBoard.set_groups(settings.sound_groups)
	for group_name: String in _groups:
		var slider := (_groups[group_name]["card"] as Node).find_children("*", "HSlider", true, false)[0] as HSlider
		var v := float(settings.sound_groups.get(group_name, 1.0))
		slider.set_value_no_signal(v)
		((slider.get_parent() as Node).get_child(2) as Label).text = "%d %%" % roundi(v * 100.0)
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
	var lit_groups := {}
	for id: String in _rows:
		var tick: CheckBox = _rows[id]["tick"]
		var lit := tick.button_pressed and SoundBoard.hearing(id, moment, HEARD_MS)
		tick.modulate = LIT if lit else QUIET
		tick.text = String(_rows[id]["label"]) + ("   (playing)" if lit else "")
		if lit:
			names.append(String(_rows[id]["label"]))
			lit_groups[_rows[id]["group"]] = true
	for group_name: String in _groups:
		(_groups[group_name]["title"] as Label).modulate = LIT if lit_groups.has(group_name) else UiSkin.TEXT
	_now.text = "Hearing now: " + (", ".join(names) if not names.is_empty() else "nothing")
