# Purpose: full-screen character customization: live rotating 3D preview plus tabs for body (gender, height, weight, chest, glutes, skin), hair (20 styles + color wheel), face (50 expressions) and outfit (100).
# With the rigged characters installed (game/rigged_body.gd) the tabs offer what those bodies have: gender, height and shape sliders, skin, hair + colour, outfit.
# Dependencies: game/rigged_body.gd, game/body_builder.gd, game/appearance_data.gd (core/appearance_db.gd rules), game/menu_widgets.gd. Emits `applied(look)` when saved, `cancelled` when closed without saving.
extends Control

const BodyBuilder = preload("res://game/body_builder.gd")
const RiggedBody = preload("res://game/rigged_body.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const Widgets = preload("res://game/menu_widgets.gd")

signal applied(look: Dictionary)
signal cancelled

var look := {}  # the look being edited

var _db := AppearanceData.db()
var _rigged := RiggedBody.available()  # true: edit rig_hair / rig_outfit and show the rigged body
var _hair_key := "rig_hair" if _rigged else "hair"
var _hair_entries: Array = _db.rig_hair if _rigged else _db.hair_styles
var _viewport: SubViewport
var _model: Node3D
var _dirty := false
var _syncing := false  # true while widgets are set from code, so they do not write back
var _sliders := {}  # key -> HSlider
var _value_labels := {}  # key -> Label
var _gender_buttons := {}  # "female" / "male" -> Button
var _skin_buttons: Array[Button] = []
var _hair_list := ItemList.new()
var _face_list := ItemList.new()
var _outfit_list := ItemList.new()
var _picker := ColorPicker.new()


func _ready() -> void:
	Widgets.fill(self)
	visible = false
	Widgets.backdrop(self, Color(0.05, 0.06, 0.09, 0.96))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	row.add_child(_build_preview())
	row.add_child(_build_panel())


func open(current: Dictionary) -> void:
	look = _db.sanitize(current)
	_sync_widgets()
	_rebuild_model()
	visible = true


func _process(delta: float) -> void:
	if not visible:
		return
	if _dirty:
		_dirty = false
		_rebuild_model()
	if _model != null:
		_model.rotation.y += delta * 0.7
		if _model.has_method("head_anchor"):
			_model.call("animate", 0.0, false)


# --- preview ---

func _build_preview() -> Control:
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(440, 600)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(440, 600)
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	container.add_child(_viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.15, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, -30.0, 0.0)
	_viewport.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 38.0
	cam.position = Vector3(0.0, 1.05, 3.6)
	_viewport.add_child(cam)
	return container


func _rebuild_model() -> void:
	var spin := 0.0
	if _model != null:
		spin = _model.rotation.y
		_model.queue_free()
	_model = RiggedBody.build(look) if _rigged else null
	if _model == null:
		_model = BodyBuilder.build(look)
	_model.rotation.y = spin
	_viewport.add_child(_model)


func _changed() -> void:
	if not _syncing:
		_dirty = true


# --- panel ---

func _build_panel() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	Widgets.title(box, "Customize your look", 28)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(tabs)
	tabs.add_child(_body_tab())
	tabs.add_child(_hair_tab())
	if _rigged:
		tabs.add_child(_list_tab("Outfit", _outfit_list, _db.rig_outfits, "rig_outfit"))
	else:
		tabs.add_child(_list_tab("Face", _face_list, _db.expressions, "face"))
		tabs.add_child(_list_tab("Outfit", _outfit_list, _db.outfits, "outfit"))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_button(buttons, "Randomize", _randomize)
	_button(buttons, "Cancel", func() -> void: cancelled.emit())
	_button(buttons, "Save", func() -> void: applied.emit(look))
	return box


func _button(parent: Container, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _body_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Body"
	tab.add_theme_constant_override("separation", 8)
	var genders := HBoxContainer.new()
	tab.add_child(genders)
	var group := ButtonGroup.new()
	for g in ["female", "male"]:
		var b := Button.new()
		b.text = String(g).capitalize()
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_set_gender.bind(String(g)))
		genders.add_child(b)
		_gender_buttons[g] = b
	_slider(tab, "height", "Height")
	_slider(tab, "weight", "Weight")
	_slider(tab, "bust", "Chest")
	_slider(tab, "glutes", "Glutes")
	var skin_label := Label.new()
	skin_label.text = "Skin tone"
	tab.add_child(skin_label)
	var grid := GridContainer.new()
	grid.columns = 6
	tab.add_child(grid)
	for i in _db.skin_tones.size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(54, 40)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(String(_db.skin_tones[i]))
		sb.set_border_width_all(2)
		sb.border_color = Color(0.2, 0.2, 0.25)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_stylebox_override("pressed", sb)
		b.pressed.connect(_set_skin.bind(i))
		grid.add_child(b)
		_skin_buttons.append(b)
	return tab


func _slider(parent: Container, key: String, text: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(80, 0)
	row.add_child(label)
	var s := HSlider.new()
	var r := _db.range_of(key)
	s.min_value = float(r[0])
	s.max_value = float(r[1])
	s.step = 0.01
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(_on_slider.bind(key))
	row.add_child(s)
	var value := Label.new()
	value.custom_minimum_size = Vector2(50, 0)
	row.add_child(value)
	_sliders[key] = s
	_value_labels[key] = value


func _hair_tab() -> Control:
	var tab := VBoxContainer.new()
	tab.name = "Hair"
	_hair_list.custom_minimum_size = Vector2(0, 190)
	for h in _hair_entries:
		_hair_list.add_item(String(h["name"]))
	_hair_list.item_selected.connect(_on_hair)
	tab.add_child(_hair_list)
	var label := Label.new()
	label.text = "Hair color"
	tab.add_child(label)
	_picker.picker_shape = ColorPicker.SHAPE_HSV_WHEEL
	_picker.edit_alpha = false
	_picker.presets_visible = false
	_picker.sampler_visible = false
	_picker.color_modes_visible = false
	_picker.can_add_swatches = false
	_picker.color_changed.connect(_on_hair_color)
	tab.add_child(_picker)
	return tab


func _list_tab(tab_name: String, list: ItemList, entries: Array, key: String) -> Control:
	var tab := VBoxContainer.new()
	tab.name = tab_name
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for e in entries:
		list.add_item(String(e["name"]))
	list.item_selected.connect(_on_list.bind(key, entries))
	tab.add_child(list)
	return tab


# --- editing ---

func _on_slider(value: float, key: String) -> void:
	if _syncing:
		return
	look[key] = value
	_value_labels[key].text = "%.2f" % value
	_changed()


func _set_gender(gender: String) -> void:
	if _syncing:
		return
	var d := _db.default_for(gender)
	look["gender"] = gender
	look["bust"] = d["bust"]
	look["glutes"] = d["glutes"]
	_sync_widgets()
	_changed()
	_dirty = true


func _set_skin(index: int) -> void:
	look["skin"] = index
	_changed()


func _on_hair(index: int) -> void:
	look[_hair_key] = String(_hair_entries[index]["id"])
	_changed()


func _on_hair_color(color: Color) -> void:
	if _syncing:
		return
	look["hair_color"] = "#" + color.to_html(false)
	_changed()


func _on_list(index: int, key: String, entries: Array) -> void:
	look[key] = String(entries[index]["id"])
	_changed()


func _randomize() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	look["skin"] = rng.randi_range(0, _db.skin_tones.size() - 1)
	look[_hair_key] = String(_hair_entries[rng.randi_range(0, _hair_entries.size() - 1)]["id"])
	look["hair_color"] = "#" + Color.from_hsv(rng.randf(), rng.randf_range(0.2, 0.9), rng.randf_range(0.25, 1.0)).to_html(false)
	look["face"] = String(_db.expressions[rng.randi_range(0, _db.expressions.size() - 1)]["id"])
	look["outfit"] = String(_db.outfits[rng.randi_range(0, _db.outfits.size() - 1)]["id"])
	if _rigged:
		look["rig_outfit"] = String(_db.rig_outfits[rng.randi_range(0, _db.rig_outfits.size() - 1)]["id"])
	look = _db.sanitize(look)
	_sync_widgets()
	_dirty = true


# Sets every widget from `look` without triggering edits.
func _sync_widgets() -> void:
	_syncing = true
	for g in _gender_buttons:
		_gender_buttons[g].button_pressed = (look["gender"] == g)
	for key in _sliders:
		_sliders[key].value = float(look[key])
		_value_labels[key].text = "%.2f" % float(look[key])
	_picker.color = Color(String(look["hair_color"]))
	_select_id(_hair_list, _hair_entries, String(look[_hair_key]))
	if _rigged:
		_select_id(_outfit_list, _db.rig_outfits, String(look["rig_outfit"]))
	else:
		_select_id(_face_list, _db.expressions, String(look["face"]))
		_select_id(_outfit_list, _db.outfits, String(look["outfit"]))
	_syncing = false


func _select_id(list: ItemList, entries: Array, id: String) -> void:
	for i in entries.size():
		if String(entries[i]["id"]) == id:
			list.select(i)
			list.ensure_current_is_visible()
			return
