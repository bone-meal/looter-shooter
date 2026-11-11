# Purpose: developer check for the creature models. Stands the two skeletons (one plain, one with an element tint), the
# clockwork bear, the crow and the Omaha enemies of data/omaha/enemies.json (regular types in a row on the south side,
# bosses on the west side, both facing the island centre; these are real game/enemy.gd nodes standing still) in the
# realistic look, built the way the game builds them, and saves
# pictures (tools/shots/creature_<view>.jpg, _fwd on Forward+) plus draw calls and frame time (tools/creature_shot*.log).
# Dependencies: game/character_models.gd, game/crow_model.gd, game/enemy.gd, game/render_style.gd, game/island.gd, game/renderer_switch.gd.
extends Node3D

const RenderStyle = preload("res://game/render_style.gd")
const Island = preload("res://game/island.gd")
const RendererSwitch = preload("res://game/renderer_switch.gd")
const CharacterModels = preload("res://game/character_models.gd")
const CrowModel = preload("res://game/crow_model.gd")
const Enemy = preload("res://game/enemy.gd")

const SCENE := "res://tools/creature_shot.tscn"
const C := Vector3(500, 0, 0)  # island centre
# [name, eye, look-at] relative to the island centre
const VIEWS := [
	["group", Vector3(0.3, 1.6, 4.8), Vector3(0.3, 1.2, 0)],
	["skeletons", Vector3(-0.9, 1.5, 2.3), Vector3(-0.9, 1.15, 0)],
	["skull", Vector3(-1.45, 1.72, 0.75), Vector3(-1.6, 1.62, 0)],
	["bear", Vector3(1.1, 1.6, 3.0), Vector3(1.7, 1.2, 0)],
	["crow", Vector3(-3.5, 2.6, 2.0), Vector3(0, 2.6, -6.0)],
	["wasteland", Vector3(0.0, 1.5, 3.4), Vector3(0.0, 1.05, 9.0)],
	["wasteland_melee", Vector3(-1.9, 1.5, 6.3), Vector3(-2.0, 1.05, 9.0)],
	["wasteland_guns", Vector3(0.9, 1.6, 6.5), Vector3(0.7, 1.2, 9.0)],
	["wasteland_brute", Vector3(2.2, 1.9, 5.4), Vector3(3.0, 1.5, 9.0)],
	["bosses", Vector3(-0.2, 2.6, 0.0), Vector3(-7.0, 2.0, 0.0)],
	["bosses_left", Vector3(-2.2, 2.6, 3.4), Vector3(-7.0, 2.1, 3.5)],
	["bosses_right", Vector3(-2.2, 2.6, -3.4), Vector3(-7.0, 2.1, -3.5)],
	["boss_mid", Vector3(-2.8, 2.4, 0.0), Vector3(-7.0, 2.0, 0.0)],
]
# Omaha enemies: [id, place relative to the island centre]; the bosses face +X. The other creatures are hidden in these views.
const WASTELAND := [["raider", Vector3(-2.7, 0, 9)], ["feral", Vector3(-1.4, 0, 9)], ["scav_gunner", Vector3(0.0, 0, 9)], ["marksman", Vector3(1.3, 0, 9)], ["brute", Vector3(3.0, 0, 9)],
	["boss_butcher", Vector3(-7, 0, 4.6)], ["boss_tyrant", Vector3(-7, 0, 2.3)], ["boss_dome_beast", Vector3(-7, 0, 0)], ["boss_warlord", Vector3(-7, 0, -2.3)], ["boss_overseer", Vector3(-7, 0, -4.6)]]


func _ready() -> void:
	var forward := RendererSwitch.is_forward()
	var suffix := "_fwd" if forward else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var env := Environment.new()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var style := RenderStyle.new()
	style.env = env
	style.sun = sun
	add_child(style)
	Island.build(self)
	var lines := PackedStringArray(["renderer=%s adapter=%s" % ["forward_plus" if forward else "compatibility", RenderingServer.get_video_adapter_name()]])
	var cast := [
		[CharacterModels.skeleton("sword", _bone(Color(0.92, 0.9, 0.82)), Color(1.0, 0.25, 0.2)), Vector3(-1.6, 0, 0)],
		[CharacterModels.skeleton("bow", _bone(Color(0.55, 0.85, 1.0)), Color(0.3, 0.8, 1.0)), Vector3(-0.3, 0, 0)],
		[CharacterModels.clockwork_bear(_bone(Color(0.8, 0.6, 0.25)), Color(1.0, 0.6, 0.1)), Vector3(1.7, 0, 0)],
		[CrowModel.build(), Vector3(0, 0, -6.0)],
	]
	for entry: Array in cast:
		var model: Node3D = entry[0]
		model.position = C + (entry[1] as Vector3)
		model.rotation.y = PI  # models face -Z; turn them to the camera
		add_child(model)
		lines.append("children: %s" % ", ".join(model.get_children().map(func(n: Node) -> String: return String(n.name))))
		for limb: Array in [["LegL", 0.45], ["LegR", -0.45]]:
			var leg := model.get_node_or_null(String(limb[0])) as Node3D
			if leg != null:
				leg.rotation.x = float(limb[1])  # mid-stride, as game/enemy.gd swings them
	CrowModel.pose(cast[3][0] as Node3D, CrowModel.FLAP, 0.12)
	var enemies: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/omaha/enemies.json")) as Dictionary)["enemies"]
	for entry: Array in WASTELAND:
		var stats: Dictionary = enemies[entry[0]]
		if not CharacterModels.has_wastelander(String(stats["model"])):
			lines.append("%s: model %s MISSING" % [entry[0], stats["model"]])
		var enemy := Enemy.new()  # the real enemy node, standing still (no target, physics off)
		enemy.configure(String(entry[0]), stats, null, null, null)
		enemy.set_physics_process(false)
		enemy.position = C + (entry[1] as Vector3)
		enemy.rotation.y = -PI / 2.0 if String(entry[0]).begins_with("boss_") else 0.0
		add_child(enemy)
		var arm := enemy.find_child("ArmR", true, false) as Node3D
		lines.append("%s: joints %s, surfaces %d" % [entry[0], "ok" if arm != null and enemy.find_child("LegL", true, false) != null else "MISSING",
			enemy.find_children("*", "MeshInstance3D", true, false).reduce(func(total: int, piece: Node) -> int: return total + (piece as MeshInstance3D).mesh.get_surface_count(), 0)])
		if arm != null and stats["attack_type"] == "melee":
			arm.rotation.x = deg_to_rad(50.0)  # the rest pose game/enemy.gd holds
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	style.apply("high", "realistic")
	for view: Array in VIEWS:
		cam.position = C + (view[1] as Vector3)
		cam.look_at(C + (view[2] as Vector3), Vector3.UP)
		for entry: Array in cast:
			(entry[0] as Node3D).visible = not (String(view[0]).begins_with("wasteland") or String(view[0]).begins_with("boss"))
		for i in (40 if forward else 12):
			await RenderingServer.frame_post_draw
		var started := Time.get_ticks_usec()
		for i in 10:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/creature_%s%s.jpg" % [view[0], suffix], 0.9)
		lines.append("%s draws=%d tris=%d frame_ms=%.2f" % [view[0], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), float(Time.get_ticks_usec() - started) / 10000.0])
	lines.append("CREATURE_SHOT_DONE")
	var f := FileAccess.open("res://tools/creature_shot%s.log" % suffix, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	if not forward and not OS.get_cmdline_user_args().has("--compat-only") and RendererSwitch.relaunch_if_needed("forward_plus", get_tree(), SCENE):
		return
	get_tree().quit()


# A plain tintable material like the one game/enemy.gd owns per enemy.
func _bone(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material
