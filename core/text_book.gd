# Purpose: reads the writers' text files (data/fantasy/writing/*.txt). A file is sections headed `[kind id]`, lines
# `key: text`, and `#` note lines that are ignored. A key that appears more than once in a section becomes a list
# (e.g. several `says:` lines). Result: {kind: {id: {key: String or Array of Strings}}}.
# Dependencies: none.
extends RefCounted


static func parse(text: String, into: Dictionary = {}) -> Dictionary:
	var section := {}
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			var head := line.substr(1, line.length() - 2).strip_edges()
			var gap := head.find(" ")
			var kind := head if gap < 0 else head.substr(0, gap)
			var id := "" if gap < 0 else head.substr(gap + 1).strip_edges()
			if not into.has(kind):
				into[kind] = {}
			if not into[kind].has(id):
				into[kind][id] = {}
			section = into[kind][id]
			continue
		var cut := line.find(": ")
		if cut < 0 and line.ends_with(":"):
			cut = line.length() - 1  # a key with nothing after it: an empty text on purpose
		if cut < 0:
			continue
		var key := line.substr(0, cut).strip_edges()
		var value := line.substr(cut + 1).strip_edges()
		if section.has(key):
			if section[key] is Array:
				(section[key] as Array).append(value)
			else:
				section[key] = [section[key], value]
		else:
			section[key] = value
	return into


static func read_files(paths: PackedStringArray) -> Dictionary:
	var out := {}
	for path in paths:
		if FileAccess.file_exists(path):
			parse(FileAccess.get_file_as_string(path), out)
	return out
