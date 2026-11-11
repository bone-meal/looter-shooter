# Purpose: developer tool for taking files out of the project without deleting anything: every path listed in
# tools/retire_list.txt (one per line, relative to the project folder; a folder moves whole; # starts a note) is
# MOVED into the project's _to_delete/ folder, keeping its sub-path. Godot ignores that folder (.gdignore), so the
# director can look through it and delete it by hand. Writes tools/retire_files.log (ends RETIRE_DONE).
# Run scene tools/retire_files.tscn. Not part of exports.
# Dependencies: none.
extends Node

const LIST := "res://tools/retire_list.txt"
const BIN := "res://_to_delete/"


func _ready() -> void:
	var lines := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(BIN))
	var mark := FileAccess.open(BIN + ".gdignore", FileAccess.WRITE)
	if mark != null:
		mark.close()
	var moved := 0
	for raw in FileAccess.get_file_as_string(LIST).split("\n"):
		var path := raw.strip_edges()
		if path == "" or path.begins_with("#") or path.contains("..") or path.begins_with("_to_delete"):
			continue
		var from := ProjectSettings.globalize_path("res://" + path)
		var to := ProjectSettings.globalize_path(BIN + path)
		if not FileAccess.file_exists(from) and not DirAccess.dir_exists_absolute(from):
			lines.append("not there (already gone): %s" % path)
			continue
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var result := DirAccess.rename_absolute(from, to)
		if result == OK:
			moved += 1
			lines.append("moved: %s" % path)
		else:
			lines.append("COULD NOT MOVE (error %d): %s" % [result, path])
	lines.append("RETIRE_DONE moved=%d" % moved)
	var log_file := FileAccess.open("res://tools/retire_files.log", FileAccess.WRITE)
	log_file.store_string("\n".join(lines))
	log_file.close()
	get_tree().quit()
