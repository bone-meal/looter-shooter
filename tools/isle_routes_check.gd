# Purpose: developer check (director: proper paths to every place on each island): for every island in
# data/sea/islands.json whose data/sea/isles/<props>.json has generated paths, does the path network join every place
# to the start (core/sea/isle_routes.gd) and is there a way along the paths from the start to each place. Writes
# tools/isle_routes_check.log (ends ISLE_ROUTES problems=n). Whether the paths can really be WALKED is the game's
# `!isle walk` (tools/isle_walker.gd, run through tools/game_boot_check.tscn). Run scene tools/isle_routes_check.tscn.
# Dependencies: core/sea/isle_routes.gd, data/sea/islands.json, data/sea/isles/*.json.
extends Node

const IsleRoutes = preload("res://core/sea/isle_routes.gd")


func _ready() -> void:
	var out := PackedStringArray()
	var problems := 0
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/islands.json"))
	for island: Dictionary in cfg["islands"]:
		if not island.has("props"):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/isles/%s.json" % String(island["props"])))
		if not data.has("paths"):
			out.append("%s: no generated paths (no places to reach)" % String(island["id"]))
			continue
		var routes := IsleRoutes.new(data)
		for line in routes.problems():
			out.append("FAIL %s: %s" % [String(island["id"]), line])
			problems += 1
		for place: String in routes.pois:
			var way := routes.way(routes.pois[routes.start], routes.pois[place])
			if way.is_empty():
				out.append("FAIL %s: no way from %s to %s" % [String(island["id"]), routes.start, place])
				problems += 1
			else:
				out.append("ok   %s: %s -> %s, %d points" % [String(island["id"]), routes.start, place, way.size()])
	out.append("ISLE_ROUTES problems=%d" % problems)
	var f := FileAccess.open("res://tools/isle_routes_check.log", FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()
	get_tree().quit()
