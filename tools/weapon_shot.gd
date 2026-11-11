# Purpose: developer check for the weapon models. Hangs the eight guns side-on in two rows on the island in the
# realistic look and saves pictures (tools/shots/weapon_<view>.jpg, _fwd on Forward+) plus draw calls and frame time
# (tools/weapon_shot.log / weapon_shot_fwd.log). Runs on Compatibility, then again on Forward+ (not with --compat-only).
# The Forward+ pass, or the user argument --parts, fits every gun with a full set of parts (game/gun_parts_view.gd).
# Dependencies: game/weapon_models.gd, game/render_style.gd, game/island.gd, game/renderer_switch.gd.
extends Node3D

const RenderStyle = preload("res://game/render_style.gd")
const Island = preload("res://game/island.gd")
const RendererSwitch = preload("res://game/renderer_switch.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const GunPartsView = preload("res://game/gun_parts_view.gd")
const GunDb = preload("res://core/gun_db.gd")
const GunStats = preload("res://core/gun_stats.gd")

const SCENE := "res://tools/weapon_shot.tscn"
const C := Vector3(500, 0, 0)  # island centre
const ROWS := [["pistol_basic", "ak47", "m16", "m60"], ["shotgun_double", "sniper_basic", "rocket_launcher", "grenade_launcher"]]
# [name, eye, look-at] relative to the island centre
const VIEWS := [
	["all", Vector3(0, 1.4, 2.3), Vector3(0, 1.35, 0)],
	["a", Vector3(-1.0, 1.65, 0.75), Vector3(-1.0, 1.6, 0)],
	["b", Vector3(1.0, 1.65, 0.75), Vector3(1.0, 1.6, 0)],
	["c", Vector3(-1.0, 1.15, 0.75), Vector3(-1.0, 1.1, 0)],
	["d", Vector3(1.0, 1.15, 0.75), Vector3(1.0, 1.1, 0)],
	["angle", Vector3(-0.15, 1.75, 0.5), Vector3(-0.6, 1.58, -0.05)],
]


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
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"))
	var lines := PackedStringArray(["renderer=%s adapter=%s" % ["forward_plus" if forward else "compatibility", RenderingServer.get_video_adapter_name()]])
	for row in ROWS.size():
		for column in 4:
			var gun := WeaponModels.build(String(ROWS[row][column]))
			if OS.get_cmdline_user_args().has("--parts") or forward:  # a full set of parts, different per gun
				var number := row * 4 + column
				var parts := {}
				for slot: String in db.bodies[String(ROWS[row][column])]["slots"]:
					var kinds: Array = (db.parts[slot] as Dictionary).keys()
					parts[slot] = {"kind": String(kinds[(number + slot.length()) % kinds.size()]), "maker": String(db.makers.keys()[(number + slot.length()) % db.makers.size()])}
				var rolled := {"body": String(ROWS[row][column]), "maker": "kestrel", "tier": "grey", "parts": parts, "rolls": {}, "buffs": []}
				GunPartsView.apply(gun, rolled, db)
				lines.append(GunStats.display_name(db, rolled))
			gun.position = C + Vector3(-1.5 + column, 1.6 - 0.5 * row, 0.0)
			gun.rotation.y = PI / 2  # side-on, barrel to the left
			add_child(gun)
			lines.append("%s children: %s" % [ROWS[row][column], ", ".join(gun.get_children().map(func(n: Node) -> String: return String(n.name)))])
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	style.apply("high", "realistic")
	for view: Array in VIEWS:
		cam.position = C + (view[1] as Vector3)
		cam.look_at(C + (view[2] as Vector3), Vector3.UP)
		for i in (40 if forward else 12):
			await RenderingServer.frame_post_draw
		var started := Time.get_ticks_usec()
		for i in 10:
			await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/weapon_%s%s.jpg" % [view[0], suffix], 0.9)
		lines.append("%s draws=%d tris=%d frame_ms=%.2f" % [view[0], int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), float(Time.get_ticks_usec() - started) / 10000.0])
	lines.append("WEAPON_SHOT_DONE")
	var f := FileAccess.open("res://tools/weapon_shot%s.log" % suffix, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	if not forward and not OS.get_cmdline_user_args().has("--compat-only") and RendererSwitch.relaunch_if_needed("forward_plus", get_tree(), SCENE):
		return
	get_tree().quit()


func _json(file: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % file))
