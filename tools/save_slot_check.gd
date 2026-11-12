# Purpose: developer check of the save slots: drives the real main scene through Start Game -> save menu -> new
# character on SLOT 3 -> session (customize menu open) -> back to the menu -> the slot shows the character -> delete.
# Pictures tools/shots/save_<step>.jpg, log tools/save_slot_check.log (ends SAVE_SLOT_CHECK_DONE problems=n).
# It refuses to run when slot 3 of this version is in use, so it never touches a real character.
# Dependencies: game/main.tscn, game/save_slots.gd, game/settings_io.gd, core/settings_state.gd, game/renderer_switch.gd.
extends Node

const SaveSlots = preload("res://game/save_slots.gd")
const SettingsIO = preload("res://game/settings_io.gd")
const SettingsState = preload("res://core/settings_state.gd")
const RendererSwitch = preload("res://game/renderer_switch.gd")
const SLOT := 3

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var settings := SettingsState.new()
	SettingsIO.load_into(settings)
	if RendererSwitch.relaunch_if_needed(settings.renderer, get_tree(), "res://tools/save_slot_check.tscn"):
		return  # starts again in the renderer the settings ask for, as the game itself would
	if not SaveSlots.summary(SLOT).is_empty():
		_note("slot %d of version %s is in use: nothing done" % [SLOT, SaveSlots.version()], false)
		_finish()
		return
	var main: Node = (load("res://game/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _frames(5)
	var menu: Control = main.get("_save_menu")
	(main.get("_main_menu") as Control).emit_signal("start_pressed")
	await _frames(5)
	_note("save menu shown after Start Game", menu.visible)
	await _snap("1_menu")
	menu.call("_name_it", SLOT)
	await _frames(5)
	await _snap("2_naming")
	menu.call("_create", "  ", SLOT)
	_note("an empty name starts nothing", main.get("_session") == null)
	menu.call("_create", "Tester", SLOT)
	await _frames(30)
	var session: Node = main.get("_session")
	_note("session started", session != null)
	if session != null:
		_note("customize menu open on a new character", (session.get("_customizer") as Control).visible)
		_note("character named", String(session.get("_profile_name")) == "Tester")
		_note("card name is the character's", String((session.get("_progress") as Object).get("callsign")) == "Tester")
		await _snap("3_customize")
		session.set("_best_round", 7)
		main.call("_end_game")
	await _frames(10)
	var info := SaveSlots.summary(SLOT)
	_note("slot holds the character after leaving: %s" % [info], String(info.get("name", "")) == "Tester")
	_note("the slot shows the best round", int(info.get("best_round", 0)) == 7)
	_note("old single save untouched by it", not String(SaveSlots.path(SLOT)).begins_with("user://profile"))
	(main.get("_main_menu") as Control).emit_signal("start_pressed")
	await _frames(5)
	await _snap("4_filled")
	menu.call("_delete", SLOT)
	await _frames(3)
	_note("one press of Delete keeps the save", not SaveSlots.summary(SLOT).is_empty())
	await _snap("5_really")
	menu.call("_delete", SLOT)
	await _frames(3)
	_note("the second press deletes it", SaveSlots.summary(SLOT).is_empty())
	_finish()


func _frames(count: int) -> void:
	for _i in count:
		await get_tree().process_frame


func _snap(step: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	get_viewport().get_texture().get_image().save_jpg("res://tools/shots/save_%s.jpg" % step, 0.85)


func _note(text: String, good: bool) -> void:
	if not good:
		_problems += 1
	_lines.append(("ok   " if good else "FAIL ") + text)


func _finish() -> void:
	_lines.append("SAVE_SLOT_CHECK_DONE problems=%d" % _problems)
	var file := FileAccess.open("res://tools/save_slot_check.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
	get_tree().quit()
