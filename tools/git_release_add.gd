# Purpose: export ONE preset and attach its zip to an EXISTING GitHub release (for a build that
# failed in git_release). Job in tools/release_add.txt: "<preset> <tag>", e.g. "macOS v1.05".
# Also refreshes the release notes from tools/release_notes.txt. Log: tools/git_release_add.log.
# Depends on: tools/git_cli.gd, export_presets.cfg, export templates, gh. Runs detached like git_release.
extends Node

const GitCli = preload("res://tools/git_cli.gd")
const JOB_FILE := "res://tools/release_add.txt"
const EXE_NAMES := {"Windows": "/LooterShooter.exe", "Linux": "/LooterShooter.x86_64", "macOS": "/LooterShooter.zip"}

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("worker"):
		var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
		OS.create_process(OS.get_executable_path(),
			["--headless", "--path", root, "res://tools/git_release_add.tscn", "--", "worker"])
		get_tree().quit()
		return
	_work()

func _work() -> void:
	var g = GitCli.new(ProjectSettings.globalize_path("res://tools/git_release_add.log"))
	var job: PackedStringArray = FileAccess.get_file_as_string(JOB_FILE).strip_edges().split(" ", false)
	var preset: String = job[0]
	var tag: String = job[1]
	var name_low: String = preset.to_lower()
	var dir: String = "%s/build/release/%s/%s" % [g.root, tag, name_low]
	DirAccess.make_dir_recursive_absolute(dir)
	var exe: String = dir + str(EXE_NAMES[preset])
	var code: int = g.run(OS.get_executable_path(), PackedStringArray(["--headless", "--path", g.root, "--export-release", preset, exe]))
	if code != 0 or not FileAccess.file_exists(exe):
		g.line("RESULT STOP: export failed")
		_done(g)
		return
	var zip_path: String = "%s/build/release/%s/LooterShooter-%s-%s.zip" % [g.root, tag, name_low, tag]
	if preset == "macOS":
		DirAccess.rename_absolute(exe, zip_path)
	else:
		var zp := ZIPPacker.new()
		zp.open(zip_path)
		for f in DirAccess.get_files_at(dir):
			zp.start_file(f)
			zp.write_file(FileAccess.get_file_as_bytes(dir + "/" + f))
			zp.close_file()
		zp.close()
	g.line("zip %s  %.1f MB" % [zip_path.get_file(), FileAccess.open(zip_path, FileAccess.READ).get_length() / 1048576.0])
	var url_out: Array = []
	OS.execute("git", ["-C", g.root, "remote", "get-url", "origin"], url_out)
	var repo: String = str(url_out[0]).strip_edges().trim_suffix(".git").replace("https://github.com/", "")
	var result: int = g.run("gh", PackedStringArray(["release", "upload", tag, zip_path, "--repo", repo, "--clobber"]))
	g.run("gh", PackedStringArray(["release", "edit", tag, "--repo", repo, "--notes-file",
		ProjectSettings.globalize_path("res://tools/release_notes.txt")]))
	g.line("RESULT " + ("OK " + tag if result == 0 else "UPLOAD FAILED"))
	_done(g)

func _done(g) -> void:
	g.close()
	get_tree().quit()
