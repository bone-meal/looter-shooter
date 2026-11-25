# Purpose: pure (polish1 F1a): makes one COUNTRY (data/fantasy/countries/<id>.json) into the world data the fantasy
# land runs on (the same keys as data/fantasy/world.json): its shape, size, level band and spawn; the looks of
# world.json's regions as its regions (ground, sky, trees, gatherables), each at the country's level band; its
# CROSSINGS as places (flat ground, a name "To <country>") with what they lead to. Countries start fresh: no people,
# quests' places or roads yet (F2-F4 fill them).
# Dependencies: none. Data: a country file + the loaded world.json (for the looks, names and folk).
extends RefCounted

const FOLDER := "res://data/fantasy/countries/"
const CROSSING_FLAT := 9.0  # metres of level ground at a crossing
const EXIT_FROM_SPAWN := Vector2(10.0, -6.0)  # where the painting home stands, from the country's spawn
const CROSSING_REACH := 30.0  # metres over which a crossing's level ground eases back into the land
const HEART_FLAT := 16.0  # metres of level ground round the spawn (the painting home stands on it too)
const HEART_REACH := 60.0  # ... easing back into the land over this many metres (no pit walls round the spawn)
const HAZE := 0.4  # a country's fog: its looks' fog density times this (the land is seen across kilometres)


static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(FOLDER):
		if f.ends_with(".json"):
			out.append(f.get_basename())
	return out


static func load_country(id: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(FOLDER + id + ".json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


static func country_name(id: String, old_world: Dictionary) -> String:
	for region: Dictionary in old_world.get("regions", []):
		if String(region["id"]) == id:
			return String(region.get("name", id))
	return id.replace("_", " ").capitalize()


static func build(country: Dictionary, old_world: Dictionary) -> Dictionary:
	var id := String(country["id"])
	var band := String(country.get("levels", "1-50")).split("-")
	var level := [int(band[0]), int(band[band.size() - 1])]
	var regions: Array = []
	for template: Dictionary in old_world["regions"]:
		var look := template.duplicate(true)
		look["level"] = level
		regions.append(look)
	var places: Array = []
	for c: Dictionary in country.get("crossings", []):
		var to := String(c["to"])
		var harder := int(String(load_country(to).get("levels", "0")).split("-")[0]) > int(band[0])  # "hard country" only on the way into the harder one
		var way := {"ferry": "Ferry to %s", "voyage": "Ship to %s"}.get(String(c["kind"]), "To %s") as String
		places.append({"id": String(c["id"]), "region": id, "pos": c["pos"], "kind": "crossing", "flat": CROSSING_FLAT, "reach": CROSSING_REACH, "layout": "crossing_" + String(c["kind"]), "yard": "g_dirt",
			"name": way % country_name(to, old_world), "to": to, "crossing": String(c["kind"]), "hard": bool(c.get("hard", false)) and harder})
	var spawn: Array = country["spawn"]
	var exit := [float(spawn[0]) + EXIT_FROM_SPAWN.x, float(spawn[1]) + EXIT_FROM_SPAWN.y]
	# level ground where the party first stands and the painting home hangs, easing into the land over HEART_REACH m
	places.append({"id": id + "_heart", "region": id, "pos": spawn, "kind": "landing", "flat": HEART_FLAT, "reach": HEART_REACH, "yard": "g_dirt", "name": ""})
	# where the country is easiest: the way in from the easiest neighbour (its levels rise from there), else the spawn
	var low_at: Array = spawn
	var easiest := int(band[0])
	for c: Dictionary in country.get("crossings", []):
		var next := load_country(String(c["to"]))
		var from := int(String(next.get("levels", "99")).split("-")[0])
		if from < easiest:
			easiest = from
			low_at = c["pos"]
	var world := {
		"version": int(old_world.get("version", 1)), "country": id, "country_name": country_name(id, old_world),
		"size": float(country["size"]), "seed": int(country.get("seed", 1)), "chunk": int(country.get("chunk", 50)), "sea_level": float(country.get("sea_level", 0.0)),
		"blend": float(old_world.get("blend", 60.0)), "spawn": spawn, "low_at": low_at, "exit_painting": exit,
		"levels": String(country.get("levels", "1-50")), "haze": float(country.get("haze", HAZE)), "grid": float(country.get("grid", 16.0)), "shape": country["shape"], "crossings": country.get("crossings", []),
		"regions": regions, "places": places, "npcs": [], "lakes": [], "roads": [], "areas": [], "patches": [],
		"name": old_world.get("name", "Aurelind"), "first_hint": old_world.get("first_hint", ""), "guard_folk": old_world.get("guard_folk", {}),
	}
	return world
