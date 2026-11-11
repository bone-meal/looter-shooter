# Purpose: run git / gh on the director's machine from tool scenes and log the output.
# Depends on: Git for Windows (with git-lfs) and GitHub CLI (gh) on PATH. No game code.
extends RefCounted

const GH_DEFAULT := "C:/Program Files/GitHub CLI/gh.exe"

var root: String = ProjectSettings.globalize_path("res://").trim_suffix("/")
var _log: FileAccess

func _init(log_path: String) -> void:
	_log = FileAccess.open(log_path, FileAccess.WRITE)

func line(text: String) -> void:
	_log.store_line(text)
	_log.flush()
	print(text)

# Runs a program in the project folder; returns the exit code and logs the output.
func run(program: String, args: PackedStringArray) -> int:
	var out: Array = []
	var full: PackedStringArray = PackedStringArray()
	if program == "git":
		full.append_array(["-C", root])
	full.append_array(args)
	var exe: String = program
	if program == "gh" and FileAccess.file_exists(GH_DEFAULT):
		exe = GH_DEFAULT  # the Godot MCP process may have a PATH from before gh was installed
	var code: int = OS.execute(exe, full, out, true)
	line("> %s %s  [exit %d]" % [program, " ".join(args), code])
	for chunk in out:
		line(str(chunk).strip_edges())
	return code

func close() -> void:
	_log.close()
