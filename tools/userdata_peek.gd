# Purpose: developer tool. Copies the game's own log files and settings file (user://logs, user://settings.cfg) into
# res://tools/userdata/ so a crash on the director's machine can be read from the project folder. Run scene tools/userdata_peek.tscn.
# Dependencies: none.
extends Node

const OUT := "res://tools/userdata/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var lines := PackedStringArray(["user dir: " + OS.get_user_data_dir()])
	for file_name in DirAccess.get_files_at("user://logs"):
		var text := FileAccess.get_file_as_string("user://logs/" + file_name)
		var copy := FileAccess.open(OUT + file_name.replace(":", "_") + ".txt", FileAccess.WRITE)
		if copy != null:
			copy.store_string(text)
			copy.close()
		lines.append("%s  %d bytes  modified %d" % [file_name, text.length(), FileAccess.get_modified_time("user://logs/" + file_name)])
	var settings := FileAccess.get_file_as_string("user://settings.cfg")
	var settings_copy := FileAccess.open(OUT + "settings.cfg.txt", FileAccess.WRITE)
	settings_copy.store_string(settings)
	settings_copy.close()
	lines.append("now %d" % int(Time.get_unix_time_from_system()))
	var index := FileAccess.open(OUT + "index.txt", FileAccess.WRITE)
	index.store_string("\n".join(lines))
	index.close()
	get_tree().quit()
