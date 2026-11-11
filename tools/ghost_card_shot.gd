# Purpose: developer render of another player's overhead card (callsign, level, title, emblem) on a RemotePlayer. Saves tools/shots/ghost_card.png and quits. Run scene tools/ghost_card_shot.tscn.
# Dependencies: game/remote_player.gd, core/progress_state.gd, data/progression.json, data/achievements.json.
extends Node3D

const RemotePlayer = preload("res://game/remote_player.gd")
const ProgressState = preload("res://core/progress_state.gd")

var _frames := 0


func _ready() -> void:
	get_window().size = Vector2i(700, 600)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.1, 0.12, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.8)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	add_child(sun)
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/progression.json"))
	var ach: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))
	var rules := ProgressState.new(cfg, ach)
	rules.add_xp(4200)
	rules.count("boss_kills", 1)
	rules.take_unlocked()
	rules.set_card("Bonk", "crown_gold", "bear_slayer")
	var ghost := RemotePlayer.new()
	ghost.display_name = "Host Name"
	ghost.appearance = {}
	ghost.card = {"callsign": rules.callsign, "title": rules.title_name(rules.title), "level": rules.level(), "emblem_def": rules.emblem_def(rules.emblem)}
	add_child(ghost)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.7, -3.6)
	cam.look_at(Vector3(0, 1.7, 0), Vector3.UP)
	ghost.rotation_degrees.y = 180.0


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 30:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
		get_viewport().get_texture().get_image().save_png("res://tools/shots/ghost_card.png")
		get_tree().quit()
