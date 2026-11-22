# Purpose: check that the Windows export carries the custom icon. Exports the Windows preset
# to build/icontest/ in a detached headless copy, then copies the exe's first 160 MB (the
# template part with its resources, before the embedded game data) to build/icontest/exe_head.bin.
# Log: tools/icon_check.log. Depends on: tools/git_cli.gd, export_presets.cfg.
extends Node

const GitCli = preload("res://tools/git_cli.gd")
const HEAD_BYTES := 160 * 1024 * 1024

func _ready() -> void:
	var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
	if not OS.get_cmdline_user_args().has("worker"):
		OS.create_process(OS.get_executable_path(),
			["--headless", "--path", root, "res://tools/icon_check.tscn", "--", "worker"])
		get_tree().quit()
		return
	var g = GitCli.new(ProjectSettings.globalize_path("res://tools/icon_check.log"))
	var dir: String = root + "/build/icontest"
	DirAccess.make_dir_recursive_absolute(dir)
	var exe: String = dir + "/LooterShooter.exe"
	g.run(OS.get_executable_path(), PackedStringArray(["--headless", "--path", root, "--export-release", "Windows", exe]))
	var src := FileAccess.open(exe, FileAccess.READ)
	if src == null:
		g.line("RESULT STOP: no exe")
	else:
		var out := FileAccess.open(dir + "/exe_head.bin", FileAccess.WRITE)
		out.store_buffer(src.get_buffer(mini(HEAD_BYTES, src.get_length())))
		out.close()
		g.line("exe %.1f MB" % (src.get_length() / 1048576.0))
		g.line("RESULT DONE")
	g.close()
	get_tree().quit()
