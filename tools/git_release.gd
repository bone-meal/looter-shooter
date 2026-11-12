# Purpose: export the game with the Windows and Linux presets, zip each build and publish
# the zips as a GitHub prerelease of the origin repo. Notes: tools/release_notes.txt
# (optional, else GitHub writes them from the commits). Tag = v + next version from
# tools/release_version.txt (director, 2026-11-10: v1.03 first, then 1.04, 1.05 ...).
# Log: tools/git_release.log.
# Depends on: tools/git_cli.gd, tools/export_cover.gd (refuses to build when a data file would be left out),
# export_presets.cfg, installed export templates, gh.
extends Node

const GitCli = preload("res://tools/git_cli.gd")
const ExportCover = preload("res://tools/export_cover.gd")
const PRESETS := ["Windows", "Linux"]
const OUT_DIR := "build/release"
const VERSION_FILE := "res://tools/release_version.txt"  # last released version, e.g. 1.02

func _ready() -> void:
	if not OS.get_cmdline_user_args().has("worker"):
		# Do the work in a detached headless copy: a new run_project call (another session,
		# another check) stops this process and would kill a blocking export with it.
		var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
		OS.create_process(OS.get_executable_path(),
			["--headless", "--path", root, "res://tools/git_release.tscn", "--", "worker"])
		get_tree().quit()
		return
	_work()

func _work() -> void:
	var g = GitCli.new(ProjectSettings.globalize_path("res://tools/git_release.log"))
	var left_out := ExportCover.missing()  # data files no export filter names would be missing from the build
	if not left_out.is_empty():
		for line in left_out:
			g.line("NOT PACKED: " + line)
		g.line("RESULT STOP: add the files above to include_filter in export_presets.cfg")
		_done(g)
		return
	var version: String = _next_version()
	var tag: String = "v" + version
	var zips: PackedStringArray = PackedStringArray()
	for preset in PRESETS:
		var name_low: String = str(preset).to_lower()
		var dir: String = "%s/%s/%s/%s" % [g.root, OUT_DIR, tag, name_low]
		DirAccess.make_dir_recursive_absolute(dir)
		var exe: String = dir + ("/LooterShooter.exe" if preset == "Windows" else "/LooterShooter.x86_64")
		var args := PackedStringArray(["--headless", "--path", g.root, "--export-release", str(preset), exe])
		var code: int = g.run(OS.get_executable_path(), args)
		if code != 0 or not FileAccess.file_exists(exe):
			g.line("SKIP %s: export failed" % preset)
			continue
		var zip_path: String = "%s/%s/%s/LooterShooter-%s-%s.zip" % [g.root, OUT_DIR, tag, name_low, tag]
		_zip_dir(dir, zip_path)
		g.line("zip %s  %.1f MB" % [zip_path.get_file(), FileAccess.open(zip_path, FileAccess.READ).get_length() / 1048576.0])
		zips.append(zip_path)
	if zips.is_empty():
		g.line("RESULT STOP: no build exported")
		_done(g)
		return
	var url_out: Array = []
	OS.execute("git", ["-C", g.root, "remote", "get-url", "origin"], url_out)
	var repo: String = str(url_out[0]).strip_edges().trim_suffix(".git").replace("https://github.com/", "")
	var gh_args := PackedStringArray(["release", "create", tag, "--repo", repo, "--prerelease",
		"--target", "main", "--title", "Beta " + tag])
	var notes: String = ProjectSettings.globalize_path("res://tools/release_notes.txt")
	if FileAccess.file_exists(notes):
		gh_args.append_array(["--notes-file", notes])
	else:
		gh_args.append("--generate-notes")
	gh_args.append_array(zips)
	var result: int = g.run("gh", gh_args)
	if result == 0:
		var vf := FileAccess.open(VERSION_FILE, FileAccess.WRITE)
		vf.store_line(version)
		vf.close()
	g.line("RESULT " + ("OK " + tag if result == 0 else "RELEASE FAILED"))
	_done(g)

# Last released version + 0.01 (1.02 -> 1.03, 1.09 -> 1.10).
func _next_version() -> String:
	var last: String = FileAccess.get_file_as_string(VERSION_FILE).strip_edges()
	var parts: PackedStringArray = last.split(".")
	return "%d.%02d" % [parts[0].to_int(), parts[1].to_int() + 1]

# Flat zip of every file in one build folder (exe/pck + GDExtension libraries).
func _zip_dir(dir: String, zip_path: String) -> void:
	var zp := ZIPPacker.new()
	zp.open(zip_path)
	for f in DirAccess.get_files_at(dir):
		zp.start_file(f)
		zp.write_file(FileAccess.get_file_as_bytes(dir + "/" + f))
		zp.close_file()
	zp.close()

func _done(g) -> void:
	g.close()
	get_tree().quit()
