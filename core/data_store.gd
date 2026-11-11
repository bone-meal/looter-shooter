# Purpose: load a JSON data file from data/ into a Dictionary. No nodes, no rendering.
# Dependencies: none.
extends RefCounted


static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("DataStore: cannot open %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		return parsed
	push_error("DataStore: %s is not a JSON object" % path)
	return {}
