# Purpose: Settings > Crosshair. Left: the 30 ready-made crosshairs as pictures (click one to use it). Right: a big
# preview over sky and sand, a slider for every setting (data/crosshairs.json "fields") and the four arms, and the
# SHARE CODE: copy yours to send to a friend, paste theirs and press Use code. Every change is kept in the settings
# (core/settings_state.gd `crosshair`); the HUD shows it at once.
# Dependencies: core/crosshair_style.gd, core/data_store.gd, core/settings_state.gd, game/crosshair_view.gd, game/menu_widgets.gd.
extends Control

const CrosshairStyle = preload("res://core/crosshair_style.gd")
const CrosshairView = preload("res://game/crosshair_view.gd")
const DataStore = preload("res://core/data_store.gd")
const SettingsState = preload("res://core/settings_state.gd")
const Widgets = preload("res://game/menu_widgets.gd")

signal changed
signal closed

const COLUMNS := 6
const CELL := Vector2(112, 92)
const PICKED := Color(1.0, 0.82, 0.3)
const ARM_NAMES := ["Top", "Right", "Bottom", "Left"]

var settings: SettingsState  # set before add_child

var styles := CrosshairStyle.new()
var _style := {}
var _cells: Array = []  # one Button per preset
var _sliders := {}  # field id -> HSlider
var _values := {}  # field id -> Label with the number
var _arm_ticks: Array = []  # four CheckBoxes
var _preview := CrosshairView.new()
var _code := LineEdit.new()
var _note := Label.new()
var _name := Label.new()


func _ready() -> void:
	styles.setup(DataStore.load_json("res://data/crosshairs.json"))
	_style = styles.clean(settings.crosshair) if not settings.crosshair.is_empty() else styles.preset(0)
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.05, 0.05, 0.05, 0.92))
	var scroll := ScrollContainer.new()
	add_child(scroll)
	Widgets.fill(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	center.add_child(page)
	Widgets.title(page, "CROSSHAIR")
	var halves := HBoxContainer.new()
	halves.add_theme_constant_override("separation", 28)
	page.add_child(halves)
	_build_presets(halves)
	_build_editor(halves)
	Widgets.button(page, "Back", func() -> void: closed.emit())
	_show_all()


func _build_presets(parent: Container) -> void:
	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for n in styles.presets.size():
		var cell := Button.new()
		cell.custom_minimum_size = CELL
		cell.toggle_mode = true
		cell.focus_mode = Control.FOCUS_NONE
		cell.pressed.connect(_pick.bind(n))
		var back := ColorRect.new()
		back.color = Color(0.32, 0.4, 0.48)
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		back.position = Vector2(4, 4)
		back.size = Vector2(CELL.x - 8, CELL.y - 26)
		cell.add_child(back)
		var view := CrosshairView.new()
		view.zoom = 1.0
		view.position = back.position
		view.size = back.size
		view.show_style(styles.preset(n))
		cell.add_child(view)
		var label := Label.new()
		label.text = String(styles.presets[n].get("name", "%d" % (n + 1)))
		label.add_theme_font_size_override("font_size", 12)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.position = Vector2(0, CELL.y - 21)
		label.size = Vector2(CELL.x, 18)
		cell.add_child(label)
		grid.add_child(cell)
		_cells.append(cell)


func _build_editor(parent: Container) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(430, 0)
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var stage := Control.new()  # sky over sand, so a crosshair is judged on what it will be seen against
	stage.custom_minimum_size = Vector2(430, 170)
	stage.clip_contents = true
	box.add_child(stage)
	for part: Array in [[Color(0.45, 0.65, 0.9), 0.0, 0.55], [Color(0.85, 0.75, 0.55), 0.55, 0.3], [Color(0.25, 0.45, 0.2), 0.85, 0.15]]:
		var band := ColorRect.new()
		band.color = part[0]
		band.position = Vector2(0, 170.0 * float(part[1]))
		band.size = Vector2(430, 170.0 * float(part[2]))
		stage.add_child(band)
	_preview.zoom = 1.6
	_preview.size = Vector2(430, 170)
	stage.add_child(_preview)
	_name.add_theme_font_size_override("font_size", 14)
	box.add_child(_name)
	for f: Dictionary in styles.fields:
		if String(f["id"]) == "arms":
			_arms_row(box)
		else:
			_slider_row(box, f)
	var code_row := HBoxContainer.new()
	box.add_child(code_row)
	_code.custom_minimum_size = Vector2(190, 0)
	_code.placeholder_text = "Share code"
	code_row.add_child(_code)
	for pair: Array in [["Copy", _copy_code], ["Paste", _paste_code], ["Use code", _use_code]]:
		var b := Button.new()
		b.text = String(pair[0])
		b.pressed.connect(pair[1])
		code_row.add_child(b)
	_note.add_theme_font_size_override("font_size", 13)
	_note.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_note)


func _slider_row(box: Container, f: Dictionary) -> void:
	var id := String(f["id"])
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = String(f["label"])
	label.custom_minimum_size = Vector2(130, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = float(f["min"])
	slider.max_value = float(f["max"])
	slider.step = float(f["step"])
	slider.custom_minimum_size = Vector2(230, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_slider.bind(id))
	row.add_child(slider)
	var number := Label.new()
	number.custom_minimum_size = Vector2(56, 0)
	number.add_theme_font_size_override("font_size", 14)
	row.add_child(number)
	_sliders[id] = slider
	_values[id] = number


func _arms_row(box: Container) -> void:
	var row := HBoxContainer.new()
	box.add_child(row)
	var label := Label.new()
	label.text = "Arms"
	label.custom_minimum_size = Vector2(130, 0)
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	for bit in 4:
		var tick := CheckBox.new()
		tick.text = String(ARM_NAMES[bit])
		tick.focus_mode = Control.FOCUS_NONE
		tick.toggled.connect(_on_arm.bind(bit))
		row.add_child(tick)
		_arm_ticks.append(tick)


func _pick(n: int) -> void:
	_style = styles.preset(n)
	_store("")


func _on_slider(value: float, id: String) -> void:
	_style[id] = value
	_style["name"] = "Custom"
	_store("")


func _on_arm(on: bool, bit: int) -> void:
	var arms := int(_style.get("arms", 15))
	_style["arms"] = float(arms | (1 << bit)) if on else float(arms & ~(1 << bit))
	_style["name"] = "Custom"
	_store("")


func _copy_code() -> void:
	DisplayServer.clipboard_set(styles.code_of(_style))
	_note.text = "Code copied. Send it to a friend; they paste it here."


func _paste_code() -> void:
	_code.text = DisplayServer.clipboard_get().strip_edges()
	_use_code()


func _use_code() -> void:
	var got := styles.from_code(_code.text)
	if got.is_empty():
		_note.text = "That is not a crosshair code (it starts with %s)." % styles.prefix
		return
	var known := styles.preset_of(got)
	got["name"] = String(styles.presets[known]["name"]) if known >= 0 else "Shared"
	_style = got
	_store("Crosshair taken from the code.")


# Keeps the style in the settings and shows it everywhere on the page.
func _store(note: String) -> void:
	_style = styles.clean(_style)
	settings.crosshair = _style.duplicate()
	_show_all()
	_note.text = note
	changed.emit()


func _show_all() -> void:
	var known := styles.preset_of(_style)
	for n in _cells.size():
		(_cells[n] as Button).set_pressed_no_signal(n == known)
		(_cells[n] as Button).modulate = PICKED if n == known else Color.WHITE
	_name.text = "Now: %s" % (String(styles.presets[known]["name"]) if known >= 0 else String(_style.get("name", "Custom")))
	for id: String in _sliders:
		(_sliders[id] as HSlider).set_value_no_signal(float(_style[id]))
		(_values[id] as Label).text = ("%d" % int(_style[id])) if is_equal_approx(fmod(float(_style[id]), 1.0), 0.0) else ("%.2f" % float(_style[id])).rstrip("0")
	for bit in _arm_ticks.size():
		(_arm_ticks[bit] as CheckBox).set_pressed_no_signal(int(_style.get("arms", 15)) & (1 << bit) != 0)
	_code.text = styles.code_of(_style)
	_preview.show_style(_style)
