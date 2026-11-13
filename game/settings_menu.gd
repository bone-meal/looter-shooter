# Purpose: settings screen (mouse sensitivity, FOV, graphics preset and the player's own graphics choices with what each does,
# lighting shaders, renderer, vsync, fullscreen, fps cap, debug HUD; buttons to the Crosshair, Sounds and Controls pages); used from start and pause menus. Scrolls in a small window.
# Dependencies: game/menu_widgets.gd, core/settings_state.gd, core/data_store.gd, data/graphics.json "options". Emits changed on every edit and closed on Back.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")
const SettingsState = preload("res://core/settings_state.gd")
const DataStore = preload("res://core/data_store.gd")

signal changed
signal closed
signal controls_pressed
signal sounds_pressed
signal crosshair_pressed

var settings: SettingsState  # set before add_child


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.05, 0.05, 0.05, 0.9))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	Widgets.fill(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	Widgets.title(box, "SETTINGS")
	_slider(box, "Mouse sensitivity", SettingsState.MOUSE_SENS_MIN, SettingsState.MOUSE_SENS_MAX, 0.0005, settings.mouse_sens, "%.4f",
		func(v: float) -> void: settings.mouse_sens = v)
	_slider(box, "Field of view", SettingsState.FOV_MIN, SettingsState.FOV_MAX, 1.0, settings.fov, "%d",
		func(v: float) -> void: settings.fov = v)
	_choice(box, "Graphics", SettingsState.GRAPHICS_IDS, settings.graphics, func(id: String) -> void: settings.graphics = id)
	for option: Dictionary in DataStore.load_json("res://data/graphics.json").get("options", []):
		_own_choice(box, option)
	_choice(box, "Lighting shaders", SettingsState.SHADER_IDS, settings.shaders, func(id: String) -> void: settings.shaders = id)
	_choice(box, "Renderer (after restart)", SettingsState.RENDERER_IDS, settings.renderer, func(id: String) -> void: settings.renderer = id)
	_fps_option(box)
	_check(box, "V-Sync", settings.vsync, func(on: bool) -> void: settings.vsync = on)
	_check(box, "Fullscreen", settings.fullscreen, func(on: bool) -> void: settings.fullscreen = on)
	_check(box, "Debug overlay (graphs)", settings.show_debug, func(on: bool) -> void: settings.show_debug = on)
	_slider(box, "Master volume", 0.0, 1.0, 0.05, settings.volume, "%.2f",
		func(v: float) -> void: settings.volume = v)
	Widgets.button(box, "Crosshair", func() -> void: crosshair_pressed.emit())
	Widgets.button(box, "Sounds", func() -> void: sounds_pressed.emit())
	Widgets.button(box, "Controls", func() -> void: controls_pressed.emit())
	Widgets.button(box, "Back", func() -> void: closed.emit())


func _slider(box: Container, label: String, lo: float, hi: float, step: float, value: float, fmt: String, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(240, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var value_label := Label.new()
	value_label.text = fmt % value
	value_label.custom_minimum_size = Vector2(70, 0)
	row.add_child(value_label)
	slider.value_changed.connect(_on_slider.bind(value_label, fmt, on_change))


func _on_slider(value: float, value_label: Label, fmt: String, on_change: Callable) -> void:
	value_label.text = fmt % value
	on_change.call(value)
	changed.emit()


func _check(box: Container, label: String, value: bool, on_change: Callable) -> void:
	var check := CheckBox.new()
	check.text = label
	check.button_pressed = value
	check.toggled.connect(_on_toggle.bind(on_change))
	box.add_child(check)


func _on_toggle(on: bool, on_change: Callable) -> void:
	on_change.call(on)
	changed.emit()


func _fps_option(box: Container) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = "Max FPS"
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)
	var option := OptionButton.new()
	for fps in SettingsState.MAX_FPS_CHOICES:
		option.add_item("Unlimited" if fps == 0 else str(fps))
	option.selected = SettingsState.MAX_FPS_CHOICES.find(settings.max_fps)
	option.item_selected.connect(_on_fps_selected)
	row.add_child(option)


func _on_fps_selected(index: int) -> void:
	settings.max_fps = SettingsState.MAX_FPS_CHOICES[index]
	changed.emit()


# One of the player's own graphics choices (data/graphics.json "options"): a dropdown and, under it, what it changes.
func _own_choice(box: Container, option: Dictionary) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = String(option["label"])
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)
	var choices: Array = option["choices"]
	var picker := OptionButton.new()
	var current := String(settings.picks.get(option["id"], "preset"))
	for index in choices.size():
		picker.add_item(String(choices[index]["label"]))
		if String(choices[index]["id"]) == current:
			picker.selected = index
	picker.item_selected.connect(func(index: int) -> void:
		settings.picks[String(option["id"])] = String(choices[index]["id"])
		changed.emit())
	row.add_child(picker)
	var about := Label.new()
	about.text = String(option["about"])
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size = Vector2(560, 0)
	about.add_theme_font_size_override("font_size", 13)
	about.modulate = Color(1, 1, 1, 0.6)
	box.add_child(about)


# A dropdown of preset IDs (shown capitalized).
func _choice(box: Container, label: String, ids: Array, current: String, on_pick: Callable) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_label)
	var option := OptionButton.new()
	for id: String in ids:
		option.add_item(id.capitalize())
	option.selected = maxi(ids.find(current), 0)
	option.item_selected.connect(func(index: int) -> void:
		on_pick.call(String(ids[index]))
		changed.emit())
	row.add_child(option)
