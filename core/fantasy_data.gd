# Purpose: loads everything the fantasy world is made of in one go: the rule files (data/fantasy/*.json) and the
# writers' text files (data/fantasy/writing/*.txt), and puts every name and spoken line back where the rules expect it
# (region["name"], quest["text"], item["name"] ...). Anything the writers' files do not name gets its id as a stand-in
# and is listed in "problems", so a missing line never breaks the game and tools/fantasy_check.tscn can report it.
# (polish1 F1a) With a country id the world is that country (core/country_world.gd); world.json's regions are then
# only the looks its land wears, and the old world is kept as "old_world".
# Dependencies: core/data_store.gd, core/text_book.gd, core/country_world.gd.
extends RefCounted

const DataStore = preload("res://core/data_store.gd")
const TextBook = preload("res://core/text_book.gd")
const CountryWorld = preload("res://core/country_world.gd")

const FOLDER := "res://data/fantasy/"


# {"world", "quests", "gear", "skilling", "spells", "enemies", "layouts", "sounds", "combat", "ground", "squad", "agility", "props", "text", "problems": PackedStringArray}
static func load_all(country: String = "") -> Dictionary:
	var d := {}
	for part: String in ["world", "quests", "gear", "skilling", "spells", "enemies", "layouts", "sounds", "interiors", "combat", "ground", "squad", "agility", "coaches", "country_rocks", "livestock"]:
		d[part] = DataStore.load_json(FOLDER + part + ".json")
	d["props"] = DataStore.load_json(FOLDER + "props.json")["props"]
	var files := PackedStringArray([FOLDER + "writing/spells.txt", FOLDER + "writing/items.txt", FOLDER + "writing/skills.txt", FOLDER + "writing/buildings.txt"])
	var regions: Array = d["world"]["regions"]
	for i in regions.size():
		files.append("%swriting/%d_%s.txt" % [FOLDER, i + 1, regions[i]["id"]])
	d["text"] = TextBook.read_files(files)
	d["problems"] = _apply(d)
	if country != "":
		d["old_world"] = d["world"]
		d["world"] = CountryWorld.build(CountryWorld.load_country(country), d["old_world"])
		var problems: PackedStringArray = d["problems"]
		problems.append_array(_name_country(d))
		d["problems"] = problems
		d["old_quests"] = d["quests"]["quests"]
		# (polish1 F4) a country has its own quest file (data/fantasy/quests/<country>.json); none yet = no quests there
		var own := FOLDER + "quests/" + country + ".json"
		d["quests"]["quests"] = DataStore.load_json(own)["quests"] if FileAccess.file_exists(own) else []
		problems.append_array(_name_quests(d["quests"]["quests"], d["text"]))
		d["problems"] = problems
	return d


# The writers' words for a list of quests: title, offer, done, hint, each step's text and what a talk step's person says.
static func _name_quests(quests: Array, text: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	for quest: Dictionary in quests:
		var id := String(quest["id"])
		quest["name"] = _line(text, "quest", id, "title", missing)
		quest["text"] = _line(text, "quest", id, "offer", missing)
		quest["done"] = _line(text, "quest", id, "done", missing)
		quest["hint"] = _line(text, "quest", id, "hint", missing)  # (polish1 item 127) the quest log's medium hint toward its giver
		var steps: Array = quest["steps"]
		for i in steps.size():
			steps[i]["text"] = _line(text, "quest", id, "step %d" % (i + 1), missing)
			if String(steps[i]["type"]) == "talk":  # (polish1 item 103) what the person says when that talk step is done
				var said: Variant = text.get("quest", {}).get(id, {}).get("says %d" % (i + 1))
				steps[i]["says"] = String(said) if said is String else ""
	return missing


# (polish1 F3) Names for a country's own places, areas and lakes from the writers' files (crossings carry theirs).
static func _name_country(d: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	var text: Dictionary = d["text"]
	var world: Dictionary = d["world"]
	for place: Dictionary in world["places"]:
		if not place.has("name"):
			place["name"] = _line(text, "place", String(place["id"]), "name", missing)
	for area: Dictionary in world["areas"]:
		area["name"] = _line(text, "area", String(area["id"]), "name", missing)
	for npc: Dictionary in world["npcs"]:
		npc["name"] = _line(text, "person", String(npc["id"]), "name", missing)
		npc["greet"] = _line(text, "person", String(npc["id"]), "greeting", missing)
	var lakes: Dictionary = world.get("lake_names", {})
	for lake_id: String in lakes:  # the shape's lake id -> the writers' lake id -> its name
		lakes[lake_id] = _line(text, "lake", String(lakes[lake_id]), "name", missing)
	return missing


# One text of the writers' files, or the id itself (and a note in `missing`) when it is not there.
static func _line(text: Dictionary, kind: String, id: String, key: String, missing: PackedStringArray) -> String:
	var found: Variant = text.get(kind, {}).get(id, {}).get(key)
	if found is String:
		return found
	missing.append("no text for [%s %s] %s" % [kind, id, key])
	return id if key in ["name", "title"] else ""


static func _apply(d: Dictionary) -> PackedStringArray:
	var missing := PackedStringArray()
	var text: Dictionary = d["text"]
	var world: Dictionary = d["world"]
	world["name"] = _line(text, "world", "aurelind", "name", missing)
	world["first_hint"] = _line(text, "world", "aurelind", "first hint", missing)
	for region: Dictionary in world["regions"]:
		region["name"] = _line(text, "region", String(region["id"]), "name", missing)
		region["blurb"] = _line(text, "region", String(region["id"]), "about", missing)
		var folk: Dictionary = text.get("folk", {}).get(String(region["id"]), {})
		var says: Variant = folk.get("says", [])
		region["folk"] = {"name": String(folk.get("name", "")), "lines": says if says is Array else [says]}
	var guard: Dictionary = text.get("folk", {}).get("guard", {})
	var guard_says: Variant = guard.get("says", [])
	world["guard_folk"] = {"name": _line(text, "folk", "guard", "name", missing), "lines": guard_says if guard_says is Array else [guard_says]}
	var traveller: Dictionary = text.get("folk", {}).get("traveller", {})  # (polish1 F3) the people walking the roads
	var traveller_says: Variant = traveller.get("says", [])
	world["traveller_folk"] = {"name": _line(text, "folk", "traveller", "name", missing), "lines": traveller_says if traveller_says is Array else [traveller_says]}
	world["border_line"] = _line(text, "folk", "border", "name", missing)  # (polish1 F3) shown when a border ridge turns a player back
	for place: Dictionary in world["places"]:
		place["name"] = _line(text, "place", String(place["id"]), "name", missing)
	for lake: Dictionary in world.get("lakes", []):
		lake["name"] = _line(text, "lake", String(lake["id"]), "name", missing)
	for area: Dictionary in world.get("areas", []):  # (polish1 item 129) named areas a quest can be bound to
		area["name"] = _line(text, "area", String(area["id"]), "name", missing)
	for npc: Dictionary in world["npcs"]:
		npc["name"] = _line(text, "person", String(npc["id"]), "name", missing)
		npc["greet"] = _line(text, "person", String(npc["id"]), "greeting", missing)
	missing.append_array(_name_quests(d["quests"]["quests"], text))
	var words := {}
	for key: String in ["weak", "strong", "perfect"]:
		words[key] = _line(text, "combat", "words", key, missing)
	d["combat"]["words"] = words
	var enemies: Dictionary = d["enemies"]["enemies"]
	for id: String in enemies:
		enemies[id]["name"] = _line(text, "creature", id, "name", missing)
		for move: Dictionary in enemies[id].get("moves", []):
			move["name"] = _line(text, "creature", id, "move " + String(move["id"]), missing)
	var items: Dictionary = d["gear"]["items"]
	for id: String in items:
		items[id]["name"] = _line(text, "items", String(items[id]["kind"]), id, missing)
		if String(items[id]["name"]) == "":
			items[id]["name"] = id
	var inside: Dictionary = d["interiors"]
	inside["names"] = {"building": {}, "container": {}}
	for kind: String in inside["rooms"]:
		inside["names"]["building"][kind] = _line(text, "building", kind, "name", missing)
	for kind: String in inside["rooms"]:
		for piece: Dictionary in inside["rooms"][kind]["items"]:
			if piece.has("loot") and not (inside["names"]["container"] as Dictionary).has(piece["model"]):
				inside["names"]["container"][piece["model"]] = _line(text, "container", String(piece["model"]), "name", missing)
	var skilling: Dictionary = d["skilling"]
	for id: String in skilling["skills"]:
		skilling["skills"][id]["name"] = _line(text, "skill", id, "name", missing)
		skilling["skills"][id]["about"] = _line(text, "skill", id, "about", missing)
	for skill: String in skilling.get("unlocks", {}):  # "5: Oak trees | Chop oak trees in Greenwald."
		for step: Dictionary in skilling["unlocks"][skill]:
			var line := _line(text, "unlock", skill, str(int(step["level"])), missing)
			step["name"] = line.get_slice("|", 0).strip_edges()
			step["about"] = line.get_slice("|", 1).strip_edges() if line.contains("|") else ""
	for id: String in skilling["nodes"]:
		var named := _line(text, "gather", "names", id, missing)
		skilling["nodes"][id]["name"] = named if named != "" else id
	var spells: Dictionary = d["spells"]
	for letter: String in spells["elements"]:
		spells["elements"][letter]["name"] = _line(text, "element", letter, "name", missing)
	for letter: String in spells["forms"]:
		spells["forms"][letter]["name"] = _line(text, "form", letter, "name", missing)
		spells["forms"][letter]["desc"] = _line(text, "form", letter, "about", missing)
	for key: String in spells["substances"]:
		spells["substances"][key]["name"] = _line(text, "substance", key, "name", missing)
	for tier: Dictionary in spells["tiers"]:
		tier["name"] = String(text.get("sizes", {}).get("all", {}).get(str(int(tier["count"])), ""))
	var names: Dictionary = text.get("spell", {}).get("names", {})
	spells["names"] = names
	for secret: Dictionary in spells["secrets"]:
		secret["name"] = _line(text, "secret", String(secret["id"]), "name", missing)
		secret["desc"] = _line(text, "secret", String(secret["id"]), "about", missing)
	return missing
