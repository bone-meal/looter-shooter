# Purpose: the LOOT FILTER page of the settings (polish1 item 68, Payday 2 / Diablo 2 style): from which tier gun drops
# show at all (lower ones stay on the ground without beam, name or chime), each tier's beam and chime on or off, and
# what to highlight (chase guns, guns with a trait, chosen makers). Kept in the settings: `loot_filter`
# (core/loot_filter.gd) and the tier chimes in `muted_sounds` (the same ticks as the Sounds page).
# Dependencies: core/settings_state.gd, core/data_store.gd, core/loot_filter.gd, game/menu_widgets.gd, game/ui_skin.gd,
# game/sound_board.gd, data/gun_loot.json (tiers), data/manufacturers.json (makers).
extends Control

const SettingsState = preload("res://core/settings_state.gd")
const DataStore = preload("res://core/data_store.gd")
const LootFilter = preload("res://core/loot_filter.gd")
const Widgets = preload("res://game/menu_widgets.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const SoundBoard = preload("res://game/sound_board.gd")

signal changed
signal closed

const WIDTH := 720.0

var settings: SettingsState  # set before add_child

var _filter := {}
var _tiers: Array = []  # data/gun_loot.json tiers, lowest first


func _ready() -> void:
	_tiers = DataStore.load_json("res://data/gun_loot.json").get("tiers", [])
	Widgets.fill(self)
	_build()
	visibility_changed.connect(func() -> void:
		if visible:
			_build())  # what the settings say now


# The whole page from the settings (made again each time it opens).
func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_filter = LootFilter.clean(settings.loot_filter)
	Widgets.backdrop(self, Color(0.03, 0.035, 0.05, 0.94))
	var box := Widgets.centered_column(self, WIDTH)
	Widgets.title(box, "LOOT FILTER")
	var hint := Label.new()
	hint.text = "Filtered drops stay on the ground (you can still pick them up) but lose their beam, name and chime."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(WIDTH, 0)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = UiSkin.TEXT_DIM
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	# --- which tiers show, their beams and chimes ---
	var tiers_card := _card(list)
	var tiers := VBoxContainer.new()
	tiers_card.add_child(tiers)
	tiers.add_child(_head("TIERS"))
	var from := HBoxContainer.new()
	var from_label := Label.new()
	from_label.text = "Show drops from"
	from_label.custom_minimum_size = Vector2(220, 0)
	from.add_child(from_label)
	var pick := OptionButton.new()
	for i in _tiers.size():
		pick.add_item(String(_tiers[i]["name"]))
		if String(_tiers[i]["id"]) == String(_filter["min"]):
			pick.select(i)
	pick.item_selected.connect(func(index: int) -> void:
		_filter["min"] = String(_tiers[index]["id"])
		_save())
	from.add_child(pick)
	tiers.add_child(from)
	for tier: Dictionary in _tiers:
		var id := String(tier["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		var name_label := Label.new()
		name_label.text = String(tier["name"])
		name_label.custom_minimum_size = Vector2(220, 0)
		var colour: Variant = tier.get("color", "#ffffff")
		name_label.modulate = Color(String(colour)) if colour is String else Color.WHITE
		row.add_child(name_label)
		var beam := CheckBox.new()
		beam.text = "Beam"
		beam.button_pressed = not (_filter["no_beam"] as Array).has(id)
		beam.toggled.connect(func(on: bool) -> void:
			(_filter["no_beam"] as Array).erase(id)
			if not on:
				(_filter["no_beam"] as Array).append(id)
			_save())
		row.add_child(beam)
		var chime := CheckBox.new()
		chime.text = "Chime"
		chime.button_pressed = not settings.muted_sounds.has("chime_" + id)
		chime.toggled.connect(func(on: bool) -> void:
			settings.muted_sounds.erase("chime_" + id)
			if not on:
				settings.muted_sounds.append("chime_" + id)
			SoundBoard.set_muted(settings.muted_sounds)
			changed.emit())
		row.add_child(chime)
		tiers.add_child(row)
	# --- highlights ---
	var marks_card := _card(list)
	var marks := VBoxContainer.new()
	marks_card.add_child(marks)
	marks.add_child(_head("HIGHLIGHT (a star on the name, never filtered)"))
	for entry: Array in [["chase", "Chase guns (red text)"], ["traits", "Guns with a trait"]]:
		var key := String(entry[0])
		var tick := CheckBox.new()
		tick.text = String(entry[1])
		tick.button_pressed = bool(_filter[key])
		tick.toggled.connect(func(on: bool) -> void:
			_filter[key] = on
			_save())
		marks.add_child(tick)
	var makers_label := Label.new()
	makers_label.text = "Makers"
	makers_label.modulate = UiSkin.TEXT_DIM
	marks.add_child(makers_label)
	var grid := GridContainer.new()
	grid.columns = 3
	marks.add_child(grid)
	var makers: Dictionary = DataStore.load_json("res://data/manufacturers.json").get("makers", {})
	for maker_id: String in makers:
		var tick := CheckBox.new()
		tick.text = String(makers[maker_id]["name"])
		tick.custom_minimum_size = Vector2(220, 0)
		tick.modulate = Color(String(makers[maker_id].get("color", "#ffffff")))
		tick.button_pressed = (_filter["makers"] as Array).has(maker_id)
		tick.toggled.connect(func(on: bool) -> void:
			(_filter["makers"] as Array).erase(maker_id)
			if on:
				(_filter["makers"] as Array).append(maker_id)
			_save())
		grid.add_child(tick)
	Widgets.button(box, "Back", func() -> void: closed.emit())


func _save() -> void:
	settings.loot_filter = _filter.duplicate(true)
	changed.emit()


func _card(parent: Container) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.1, 0.96)
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
