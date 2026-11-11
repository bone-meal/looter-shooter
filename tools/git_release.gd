# Purpose: export the game with the Windows and Linux presets, zip each build and publish
# the zips as a GitHub prerelease of the origin repo. Notes: tools/release_notes.txt
# (optional, else GitHub writes them from the commits). Log: tools/git_release.log.
# Depends on: tools/git_cli.gd, export_presets.cfg, installed export templates, gh.
extends Node

const GitCli = preload("res://tools/git_cli.gd")
const PRESETS := ["Windows", "Linux"]
const OUT_DIR := "build/release"

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
	var stamp: String = Time.get_datetime_string_from_system().replace(":", "").replace("T", "-")
	var tag: String = "beta-" + stamp.substr(0, 15)
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
	g.line("RESULT " + ("OK " + tag if result == 0 else "RELEASE FAILED"))
	_done(g)

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
