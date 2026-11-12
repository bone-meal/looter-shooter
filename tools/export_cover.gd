# Purpose: developer check. Lists every file under res://data that an exported build would NOT contain, because no
# include_filter of export_presets.cfg names it (plain data files are not packed unless a filter says so; the writers'
# text files were missing from the first releases this way and every name showed as its id).
# Used by tools/fantasy_check.gd (a problem) and tools/git_release.gd (refuses to build). Dependencies: none.
extends RefCounted


static func missing() -> PackedStringArray:
	var out := PackedStringArray()
	var presets := ConfigFile.new()
	if presets.load("res://export_presets.cfg") != OK:
		return PackedStringArray(["export_presets.cfg cannot be read"])
	var files := PackedStringArray()
	_walk("res://data", files)
	for section in presets.get_sections():
		if not presets.has_section_key(section, "include_filter"):
			continue
		var filters := String(presets.get_value(section, "include_filter", "")).split(",", false)
		for file in files:
			var named := false
			for filter in filters:
				named = named or file.trim_prefix("res://").matchn(filter.strip_edges())
			if not named:
				out.append("%s is not in the %s build" % [file.trim_prefix("res://"), String(presets.get_value(section, "name", section))])
	return out


static func _walk(folder: String, into: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(folder):
		if not file.ends_with(".import") and not file.ends_with(".uid"):
			into.append(folder + "/" + file)
	for sub in DirAccess.get_directories_at(folder):
		_walk(folder + "/" + sub, into)
