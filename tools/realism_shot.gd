# Purpose: developer check for the realistic look. Builds the island and the colosseum, then saves pictures of both from
# fixed cameras for several graphics tiers (plus the toon look for comparison) into tools/shots/real_*.jpg and writes
# draw calls, triangles and frame time to tools/realism_shot.log. With FORWARD_TOO it then starts itself again on the
# Forward+ renderer and repeats (pictures end in _fwd, log tools/realism_shot_fwd.log). Run scene tools/realism_shot.tscn.
# Optional arguments after "--": --quick (first tier only, short waits), --compat-only (no Forward+ pass),
# --view=<name> (only that camera), --tier=<graphics id> --look=<lighting id> (only that combination).
# Dependencies: game/render_style.gd, game/island.gd, game/colosseum.gd, game/renderer_switch.gd.
extends Node3D

const RenderStyle = preload("res://game/render_style.gd")
const Island = preload("res://game/island.gd")
const Colosseum = preload("res://game/colosseum.gd")
const RendererSwitch = preload("res://game/renderer_switch.gd")

const SCENE := "res://tools/realism_shot.tscn"
const FORWARD_TOO := true
const C := Vector3(500, 0, 0)  # island centre
# [name, eye, look-at]
const VIEWS := [
	["island_wide", C + Vector3(21, 7, 24), C + Vector3(0, 1.5, -2)],
	["island_spawn", C + Vector3(0, 1.7, 4), C + Vector3(0, 2.2, -8)],
	["island_shore", C + Vector3(7, 1.3, 9), C + Vector3(12, 0.0, 14)],
	["island_palm", C + Vector3(3, 1.6, 2), C + Vector3(8.6, 3.5, 2.7)],
	["sky_sun", C + Vector3(0, 1.7, 0), C + Vector3(3.2, 9.4, 5.6)],
	["arena_wide", Vector3(-30, 1.7, -4), Vector3(10, 4, 2)],
	["arena_gate", Vector3(24, 1.7, 3), Vector3(36, 2.2, 0)],
	["arena_seats", Vector3(0, 1.7, -8), Vector3(0, 9, -30)],
	["arena_top", Vector3(0, 30, 45), Vector3(0, 0, 0)],
]
const RUNS := [["high", "realistic"], ["medium", "realistic"], ["potato", "realistic"], ["high", "toon"]]
const RUNS_FORWARD := [["high", "realistic"], ["ultimate", "realistic"]]

var _lines := PackedStringArray()


func _ready() -> void:
	var forward := RendererSwitch.is_forward()
	var options := OS.get_cmdline_user_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
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
	Colosseum.build(self)
	Island.build(self)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.current = true
	_lines.append("renderer=%s adapter=%s" % ["forward_plus" if forward else "compatibility", RenderingServer.get_video_adapter_name()])
	var suffix := "_fwd" if forward else ""
	var settle := 40 if forward else 20
	var runs: Array = RUNS_FORWARD if forward else RUNS
	var timed := 30
	var tier := _value(options, "--tier=")
	if tier != "":
		runs = [[tier, _value(options, "--look=")]]
	if options.has("--quick"):
		runs = [runs[0]]
		settle = 4
		timed = 2
	for run: Array in runs:
		style.apply(String(run[0]), String(run[1]))
		await _frames(settle)
		for view: Array in VIEWS:
			if not _wanted(options, String(view[0])):
				continue
			cam.position = view[1]
			cam.look_at(view[2], Vector3.UP)
			await _frames(settle)
			var started := Time.get_ticks_usec()
			await _frames(timed)
			var ms := float(Time.get_ticks_usec() - started) / (1000.0 * timed)
			var path := "res://tools/shots/real_%s_%s_%s%s.jpg" % [run[0], run[1], view[0], suffix]
			get_viewport().get_texture().get_image().save_jpg(path, 0.88)
			_lines.append("%s %s %s draws=%d tris=%d frame_ms=%.2f" % [run[0], run[1], view[0],
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), ms])
	_lines.append("video_mem_mb=%.0f" % (Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	_lines.append("REALISM_SHOT_DONE")
	var f := FileAccess.open("res://tools/realism_shot%s.log" % suffix, FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	if FORWARD_TOO and not forward and not options.has("--compat-only") and RendererSwitch.relaunch_if_needed("forward_plus", get_tree(), SCENE):
		return
	get_tree().quit()


func _value(options: PackedStringArray, key: String) -> String:
	for option in options:
		if option.begins_with(key):
			return option.trim_prefix(key)
	return ""


# True unless a --view=<name> argument names a different camera.
func _wanted(options: PackedStringArray, view_name: String) -> bool:
	for option in options:
		if option.begins_with("--view=") and option != "--view=" + view_name:
			return false
	return true


func _frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
