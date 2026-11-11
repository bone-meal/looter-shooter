# Purpose: loads everything the fantasy world is made of in one go: the rule files (data/fantasy/*.json) and the
# writers' text files (data/fantasy/writing/*.txt), and puts every name and spoken line back where the rules expect it
# (region["name"], quest["text"], item["name"] ...). Anything the writers' files do not name gets its id as a stand-in
# and is listed in "problems", so a missing line never breaks the game and tools/fantasy_check.tscn can report it.
# Dependencies: core/data_store.gd, core/text_book.gd.
extends RefCounted

const DataStore = preload("res://core/data_store.gd")
const TextBook = preload("res://core/text_book.gd")

const FOLDER := "res://data/fantasy/"


# {"world", "quests", "gear", "skilling", "spells", "enemies", "layouts", "sounds", "combat", "ground", "squad", "props", "text", "problems": PackedStringArray}
static func load_all() -> Dictionary:
	var d := {}
	for part: String in ["world", "quests", "gear", "skilling", "spells", "enemies", "layouts", "sounds", "interiors", "combat", "ground", "squad"]:
		d[part] = DataStore.load_json(FOLDER + part + ".json")
	d["props"] = DataStore.load_json(FOLDER + "props.json")["props"]
	var files := PackedStringArray([FOLDER + "writing/spells.txt", FOLDER + "writing/items.txt", FOLDER + "writing/skills.txt", FOLDER + "writing/buildings.txt"])
	var regions: Array = d["world"]["regions"]
	for i in regions.size():
		files.append("%swriting/%d_%s.txt" % [FOLDER, i + 1, regions[i]["id"]])
	d["text"] = TextBook.read_files(files)
	d["problems"] = _apply(d)
	return d


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
	for place: Dictionary in world["places"]:
		place["name"] = _line(text, "place", String(place["id"]), "name", missing)
	for lake: Dictionary in world.get("lakes", []):
		lake["name"] = _line(text, "lake", String(lake["id"]), "name", missing)
	for npc: Dictionary in world["npcs"]:
		npc["name"] = _line(text, "person", String(npc["id"]), "name", missing)
		npc["greet"] = _line(text, "person", String(npc["id"]), "greeting", missing)
	for quest: Dictionary in d["quests"]["quests"]:
		var id := String(quest["id"])
		quest["name"] = _line(text, "quest", id, "title", missing)
		quest["text"] = _line(text, "quest", id, "offer", missing)
		quest["done"] = _line(text, "quest", id, "done", missing)
		var steps: Array = quest["steps"]
		for i in steps.size():
			steps[i]["text"] = _line(text, "quest", id, "step %d" % (i + 1), missing)
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
