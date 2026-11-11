# Purpose: developer render of the player card menu: card tab, stats, traits and achievements with sample progress. Saves tools/shots/card_*.png and quits. Run scene tools/card_shot.tscn.
# Dependencies: game/card_screen.gd, core/progress_state.gd, data/progression.json, data/achievements.json.
extends Node

const ProgressState = preload("res://core/progress_state.gd")
const CardScreen = preload("res://game/card_screen.gd")

var _screen: Control
var _frames := 0
var _tab := 0


func _ready() -> void:
	get_window().size = Vector2i(1152, 648)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/progression.json"))
	var ach: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))
	var p := ProgressState.new(cfg, ach)
	p.add_xp(4200)
	p.count("kills", 140)
	p.count("elite_kills", 12)
	p.count("boss_kills", 1)
	p.count("chests", 3)
	p.take_unlocked()
	p.spend("power")
	p.spend("power")
	p.spend("fortune")
	p.set_trait(0, "gunslinger")
	p.set_card("Bonk", "crown_gold", "bear_slayer")
	var layer := CanvasLayer.new()
	add_child(layer)
	_screen = CardScreen.new()
	_screen.progress = p
	layer.add_child(_screen)
	_screen.open("Kills 140   Elites 12   Bosses 1   Chests 3")


func _process(_delta: float) -> void:
	_frames += 1
	if _frames % 20 != 0:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	get_viewport().get_texture().get_image().save_png("res://tools/shots/card_%d.png" % _tab)
	_tab += 1
	if _tab > 3:
		get_tree().quit()
		return
	(_screen.get_child(1).get_child(0).get_child(1) as TabContainer).current_tab = _tab
