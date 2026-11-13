# Purpose: developer check of online play on ONE machine: starts two copies of the real game at once (Compatibility,
# small windows), the first hosts and writes its session id into tools/userdata/pair_session.txt, the second joins
# it; each runs its own chat lines and dev steps (tools/pair_host_cmd.txt, tools/pair_guest_cmd.txt) and writes
# tools/userdata/boot_host.* and boot_guest.*. Log tools/userdata/pair_check.txt (ends PAIR_CHECK_DONE).
# Dependencies: game/main.gd (--autostart, --net-host / --net-join), tools/dev_boot.gd (--boot-tag), game/renderer_switch.gd.
extends Node

const RendererSwitch = preload("res://game/renderer_switch.gd")
const OUT := "res://tools/userdata/"
const LIMIT := 420.0


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var session_file := ProjectSettings.globalize_path(OUT + "pair_session.txt")
	if FileAccess.file_exists(session_file):
		DirAccess.remove_absolute(session_file)
	var lines := PackedStringArray()
	var pids := {}
	for who: String in ["host", "guest"]:
		var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
			"--resolution", "960x540", "--position", "40,40" if who == "host" else "1020,40",
			"--log-file", ProjectSettings.globalize_path(OUT + "boot_%s.log" % who), "--", RendererSwitch.MARK, "--autostart", "--boot-tag=" + who,
			("--net-host=" if who == "host" else "--net-join=") + session_file])
		var cmd_file := "res://tools/pair_%s_cmd.txt" % who
		if FileAccess.file_exists(cmd_file):
			args.append("--cmd=" + FileAccess.get_file_as_string(cmd_file).strip_edges())
		pids[who] = OS.create_process(OS.get_executable_path(), args)
		lines.append("%s: pid %d" % [who, int(pids[who])])
	var waited := 0.0
	while waited < LIMIT and (OS.is_process_running(int(pids["host"])) or OS.is_process_running(int(pids["guest"]))):
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	for who: String in pids:
		if OS.is_process_running(int(pids[who])):
			OS.kill(int(pids[who]))
			lines.append("%s: still running after %d s, stopped" % [who, int(LIMIT)])
	lines.append("both done after %.1f s" % waited)
	lines.append("PAIR_CHECK_DONE")
	var f := FileAccess.open(OUT + "pair_check.txt", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
