# Purpose: full-screen player card menu (key P): the card banner plus tabs for the Card (callsign, emblem, title), Stats (spend points), Traits (slots) and Achievements (progress and rewards). Edits a core/progress_state.gd and emits `changed` so the session can apply bonuses and save.
# Dependencies: core/progress_state.gd (set `progress` before open), game/player_card.gd, game/emblem_art.gd, game/menu_widgets.gd.
extends Control

const PlayerCard = preload("res://game/player_card.gd")
const EmblemArt = preload("res://game/emblem_art.gd")
const Widgets = preload("res://game/menu_widgets.gd")

signal changed
signal closed

var progress: RefCounted  # core/progress_state.gd instance owned by the session

var _card: Control
var _tabs: TabContainer
var _info := ""  # one stats line shown on the card (set by the session)


# Small clickable emblem tile.
class EmblemTile extends Control:
	signal picked(id: String)
	var emblem_id := ""
	var shape := "chevron"
	var c1 := Color.WHITE
	var c2 := Color.GRAY
	var selected := false

	func _init() -> void:
		custom_minimum_size = Vector2(58, 58)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(emblem_id)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.14, 0.16, 0.22))
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.3) if selected else Color(1, 1, 1, 0.15), false, 3.0 if selected else 1.0)
		EmblemArt.draw(self, shape, size * 0.5, 22.0, c1, c2)


func _ready() -> void:
	Widgets.fill(self)
	visible = false
	Widgets.backdrop(self, Color(0.04, 0.05, 0.08, 0.96))
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 28)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	_card = PlayerCard.new()
	_card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_card)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	Widgets.button(box, "Close (Esc)", close)


func open(stats_line: String) -> void:
	_info = stats_line
	_refresh()
	visible = true


func close() -> void:
	if visible:
		visible = false
		closed.emit()


# Rebuilds the card and every tab from the current progress (cheap: the menu is rarely open).
func _refresh() -> void:
	var current := _tabs.current_tab
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_show_card()
	_tabs.add_child(_card_tab())
	_tabs.add_child(_stats_tab())
	_tabs.add_child(_traits_tab())
	_tabs.add_child(_achievements_tab())
	for i in 4:
		_tabs.set_tab_title(i, ["Card", "Stats", "Traits", "Achievements"][i])
	_tabs.current_tab = clampi(current, 0, 3)


func _show_card() -> void:
	var need := maxi(progress.xp_for_level(), 1)
	var ratio := 1.0 if progress.xp_for_level() == 0 else float(progress.xp_into_level()) / float(need)
	_card.show_card(progress.callsign, progress.title_name(progress.title), progress.level(), ratio, progress.emblem_def(progress.emblem), _info)


func _commit() -> void:
	changed.emit()
	_show_card()


# --- tabs ---

func _page() -> VBoxContainer:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	return page


func _label(text: String, size_px: int = 16, color: Color = Color(1, 1, 1, 0.9)) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	return label


func _card_tab() -> Control:
	var page := _page()
	page.add_child(_label("Callsign (letters, numbers, spaces; up to %d)" % progress.callsign_max()))
	var edit := LineEdit.new()
	edit.text = progress.callsign
	edit.max_length = progress.callsign_max()
	edit.custom_minimum_size = Vector2(320, 0)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	edit.text_submitted.connect(func(text: String) -> void: _set_card(text, progress.emblem, progress.title))
	edit.focus_exited.connect(func() -> void: _set_card(edit.text, progress.emblem, progress.title))
	page.add_child(edit)
	page.add_child(_label("Title"))
	var titles := OptionButton.new()
	var open_titles: Array = progress.titles_open()
	for i in open_titles.size():
		titles.add_item(progress.title_name(String(open_titles[i])), i)
		if String(open_titles[i]) == progress.title:
			titles.select(i)
	titles.item_selected.connect(func(index: int) -> void: _set_card(progress.callsign, progress.emblem, String(open_titles[index])))
	titles.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	page.add_child(titles)
	page.add_child(_label("Emblem (earn more with achievements)"))
	var grid := GridContainer.new()
	grid.columns = 12
	for id: String in progress.emblems_open():
		var def: Dictionary = progress.emblem_def(id)
		var tile := EmblemTile.new()
		tile.emblem_id = id
		tile.shape = String(def["shape"])
		tile.c1 = Color.html(String(def["c1"]))
		tile.c2 = Color.html(String(def["c2"]))
		tile.selected = id == progress.emblem
		tile.picked.connect(func(picked: String) -> void: _set_card(progress.callsign, picked, progress.title))
		grid.add_child(tile)
	page.add_child(grid)
	return page


func _set_card(callsign: String, emblem_id: String, title_id: String) -> void:
	if callsign == progress.callsign and emblem_id == progress.emblem and title_id == progress.title:
		return
	progress.set_card(callsign, emblem_id, title_id)
	_commit()
	_refresh()


func _stats_tab() -> Control:
	var page := _page()
	page.add_child(_label("Points to spend: %d   (1 point per level)" % progress.points_left(), 18, Color(1.0, 0.85, 0.3)))
	var defs: Dictionary = progress.stat_defs()
	for id: String in defs:
		var def: Dictionary = defs[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := _label(String(def["name"]), 18)
		name_label.custom_minimum_size = Vector2(120, 0)
		row.add_child(name_label)
		var rank := _label("%d / %d" % [int(progress.spent[id]), int(def["cap"])])
		rank.custom_minimum_size = Vector2(70, 0)
		row.add_child(rank)
		var plus := Button.new()
		plus.text = "+"
		plus.disabled = progress.points_left() <= 0 or int(progress.spent[id]) >= int(def["cap"])
		plus.pressed.connect(func() -> void:
			if progress.spend(id):
				_commit()
				_refresh())
		row.add_child(plus)
		row.add_child(_label(progress.stat_text(id), 16, Color(0.7, 0.9, 1.0)))
		page.add_child(row)
	var reset := Button.new()
	reset.text = "Reset all points"
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(func() -> void:
		progress.reset_stats()
		_commit()
		_refresh())
	page.add_child(reset)
	return page


func _traits_tab() -> Control:
	var page := _page()
	page.add_child(_label("Traits are small permanent perks. More slots open at higher levels."))
	var defs: Dictionary = progress.trait_defs()
	var ids: Array = defs.keys()
	for slot in progress.traits.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var slot_open: bool = slot < progress.trait_slots_open()
		row.add_child(_label("Slot %d" % (slot + 1), 18))
		var pick := OptionButton.new()
		pick.add_item("(none)", 0)
		for i in ids.size():
			var def: Dictionary = defs[ids[i]]
			pick.add_item("%s: %s" % [def["name"], def["desc"]], i + 1)
			if String(progress.traits[slot]) == String(ids[i]):
				pick.select(i + 1)
		pick.disabled = not slot_open
		pick.item_selected.connect(func(index: int) -> void:
			var id := "" if index == 0 else String(ids[index - 1])
			if progress.set_trait(slot, id):
				_commit()
			_refresh())
		row.add_child(pick)
		if not slot_open:
			row.add_child(_label("unlocks at level %d" % progress.trait_unlock_level(slot), 14, Color(1, 1, 1, 0.5)))
		page.add_child(row)
	return page


func _achievements_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var page := _page()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	var defs: Dictionary = progress.achievement_defs()
	for id: String in defs:
		var a: Dictionary = defs[id]
		var done: bool = progress.unlocked.has(id)
		var have := mini(progress.value_of(String(a["counter"])), int(a["goal"]))
		var rewards: Array[String] = []
		if String(a["emblem"]) != "":
			rewards.append("emblem: %s" % String((progress.emblem_def(String(a["emblem"])))["name"]))
		if String(a["title"]) != "":
			rewards.append("title: %s" % progress.title_name(String(a["title"])))
		var text := "%s %s  -  %s  (%d / %d)   reward %s" % ["[x]" if done else "[ ]", a["name"], a["desc"], have, int(a["goal"]), ", ".join(rewards)]
		page.add_child(_label(text, 16, Color(0.5, 0.95, 0.55) if done else Color(1, 1, 1, 0.6)))
	return scroll
