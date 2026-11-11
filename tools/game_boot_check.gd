# Purpose: developer check. Starts the REAL game (main scene, straight into a game session) once per renderer as its own
# process, waits for each to finish and leaves in res://tools/userdata/: boot_<renderer>.log (everything the game
# printed, errors included), boot_<renderer>.txt (frame cost) and boot_<renderer>_<stage>.jpg. Vsync and the fps cap of
# the machine's settings apply, so frame_ms is a floor, not a benchmark. Run scene tools/game_boot_check.tscn.
# Dependencies: game/main.gd (--autostart), tools/dev_boot.gd, game/renderer_switch.gd (its relaunch marker).
extends Node

const RendererSwitch = preload("res://game/renderer_switch.gd")
const OUT := "res://tools/userdata/"
const RUNS := [
	["compatibility", ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"]],
	["forward_plus", ["--rendering-method", "forward_plus"]],
]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var lines := PackedStringArray()
	for run: Array in RUNS:
		var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://")])
		args.append_array(PackedStringArray(run[1]))
		args.append_array(["--log-file", ProjectSettings.globalize_path(OUT + "boot_%s.log" % run[0])])
		args.append_array(["--", RendererSwitch.MARK, "--autostart"])
		if FileAccess.file_exists("res://tools/boot_cmd.txt"):  # optional: chat lines and dev steps for tools/dev_boot.gd, separated by ;
			args.append("--cmd=" + FileAccess.get_file_as_string("res://tools/boot_cmd.txt").strip_edges())
		var pid := OS.create_process(OS.get_executable_path(), args)
		var waited := 0.0
		while pid > 0 and OS.is_process_running(pid) and waited < 240.0:
			await get_tree().create_timer(0.5).timeout
			waited += 0.5
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
			lines.append("%s: still running after 240 s, stopped" % run[0])
		else:
			lines.append("%s: pid %d finished after %.1f s" % [run[0], pid, waited])
	lines.append("BOOT_CHECK_DONE")
	var f := FileAccess.open(OUT + "boot_check.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
