extends SceneTree
# Purpose: developer check (polish1 F3) that a country's hand-placed places and roads stay on its OWN land: no place
# on a neighbour's land beyond the border wall (core/country_shape.gd away_at) or in water, no road that leaves the
# country except to reach a crossing. Prints one line per problem and a summary; writes nothing.
# Run: godot --headless --path . --script res://tools/country_check.gd -- country=amberfield
# Dependencies: core/fantasy_data.gd, core/fantasy_terrain.gd (its country_shape).
const FantasyData = preload("res://core/fantasy_data.gd")
const FantasyTerrain = preload("res://core/fantasy_terrain.gd")


func _init() -> void:
	var country := "amberfield"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("country="):
			country = arg.trim_prefix("country=")
	var d: Dictionary = FantasyData.load_all(country)
	var t: FantasyTerrain = FantasyTerrain.new(d["world"])
	var shape: RefCounted = t.country_shape
	var away_cells := 0
	for k in (shape.get("away") as PackedByteArray).size():
		away_cells += int((shape.get("away") as PackedByteArray)[k])
	var cell := float(shape.get("cell"))
	print("%s: neighbours' land beyond the wall %.2f km2" % [country, away_cells * cell * cell / 1000000.0])
	var problems := 0
	for p: Dictionary in d["world"]["places"]:
		var x := float(p["pos"][0])
		var z := float(p["pos"][1])
		if String(p.get("kind", "")) == "crossing":
			continue
		if bool(shape.call("away_at", x, z)):
			print("PLACE BEYOND THE BORDER: %s (%d, %d)" % [p["id"], x, z])
			problems += 1
		elif t.water_at(x, z) != "":
			print("PLACE IN WATER: %s (%d, %d)" % [p["id"], x, z])
			problems += 1
	var names: Array = d["world"]["roads"]
	for r in t.roads.size():
		var road: PackedVector2Array = t.roads[r]
		var length := road[0].distance_to(road[1]) + road[1].distance_to(road[2])
		var out := 0.0
		for i in int(length / 4.0) + 1:
			var q := t.road_point(r, float(i) * 4.0)
			if bool(shape.call("away_at", q.x, q.y)):
				out += 4.0
		if out > 0.0:
			print("ROAD LEAVES THE COUNTRY: %s - %s, %d m beyond the border" % [names[r][0], names[r][1], out])
			problems += 1
	print("%s: %d problems" % [country, problems])
	quit()
