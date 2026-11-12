# Purpose: the save screen between the main menu and the game: the three slots of this build version. Play a
# character, name a new one on an empty slot, or delete one (asked twice).
# Dependencies: game/menu_widgets.gd, game/save_slots.gd.
extends Control

const Widgets = preload("res://game/menu_widgets.gd")
const SaveSlots = preload("res://game/save_slots.gd")

signal chosen(character: String, fresh: bool)  # the slot is already the active one (SaveSlots.choose); fresh = just created
signal back_pressed

var _list: VBoxContainer
var _naming := -1  # the empty slot whose character is being named
var _asking := -1  # the slot whose Delete was pressed once


func _ready() -> void:
	Widgets.fill(self)
	Widgets.backdrop(self, Color(0.09, 0.08, 0.07))
	var box := Widgets.centered_column(self, 480)
	Widgets.title(box, "CHOOSE A SAVE", 36)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	box.add_child(_list)
	Widgets.button(box, "Back", func() -> void: back_pressed.emit())
	Widgets.title(box, "Version %s. Every new version starts with three empty saves." % SaveSlots.version(), 13)
	visibility_changed.connect(_on_shown)


func _on_shown() -> void:
	if visible:
		_naming = -1
		_asking = -1
		_rebuild()


func _rebuild() -> void:
	for old in _list.get_children():
		_list.remove_child(old)
		old.queue_free()
	for slot in range(1, SaveSlots.COUNT + 1):
		var info := SaveSlots.summary(slot)
		var text := "Slot %d:  empty" % slot
		if info.has("name"):
			text = "Slot %d:  %s    level %d    best round %d    %d points    %d coins" % [slot, info["name"], info["level"], info["best_round"], info["points"], info["coins"]]
		elif info.has("damaged"):
			text = "Slot %d:  damaged save (a new game replaces it)" % slot
		Widgets.title(_list, text, 18)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		if info.has("name"):
			Widgets.button(row, "Play", _play.bind(slot, String(info["name"])))
			Widgets.button(row, "Really delete?" if _asking == slot else "Delete", _delete.bind(slot))
		elif _naming == slot:
			var edit := LineEdit.new()
			edit.placeholder_text = "Character name"
			edit.max_length = 20
			edit.custom_minimum_size = Vector2(0, 44)
			edit.text_submitted.connect(_create.bind(slot))
			row.add_child(edit)
			edit.grab_focus.call_deferred()
			Widgets.button(row, "Create", func() -> void: _create(edit.text, slot))
		else:
			Widgets.button(row, "New Game", _name_it.bind(slot))
		for part in row.get_children():
			(part as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _play(slot: int, character: String) -> void:
	SaveSlots.choose(slot)
	chosen.emit(character, false)


func _name_it(slot: int) -> void:
	_naming = slot
	_asking = -1
	_rebuild()


func _create(typed: String, slot: int) -> void:
	var character := typed.strip_edges().substr(0, 20)
	if character == "":
		return
	SaveSlots.erase(slot)  # a damaged file must not come back
	SaveSlots.choose(slot)
	chosen.emit(character, true)


func _delete(slot: int) -> void:
	if _asking == slot:
		SaveSlots.erase(slot)
		_asking = -1
	else:
		_asking = slot
	_rebuild()
