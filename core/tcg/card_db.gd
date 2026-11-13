# Purpose: the card game's data ("You got me Lobster?"): rules, keywords, cards and leaders by string id, the checks
# that every card / leader / effect is well formed, and deck legality. Pure: no nodes, no rendering.
# Names and flavour come from the writers' file data/tcg/writing/cards.txt (merged in by from_files).
# Dependencies: data/tcg/rules.json, keywords.json, cards.json, leaders.json, writing/cards.txt (or dictionaries handed in
# by a check tool), core/text_book.gd.
extends RefCounted

const TextBook = preload("res://core/text_book.gd")

const FACTIONS := ["tide", "waste", "crypt", "aurelind", "club", "neutral"]
const TYPES := ["creature", "spell", "trap"]
const RARITIES := ["common", "rare", "epic", "legendary", "token"]
const WHENS := ["arrival", "last_gasp", "turn_start", "turn_end", "cast", "attack", "friendly_death", "spell_cast",
	"enemy_attack", "enemy_creature", "enemy_spell", "power"]
const TRAP_WHENS := ["enemy_attack", "enemy_creature", "enemy_spell"]
const DOES := ["damage", "heal", "draw", "summon", "buff", "give", "destroy", "mana", "crystal", "bounce", "add", "roll", "flip"]
const TARGETS := ["pick_any", "pick_creature", "pick_enemy", "pick_enemy_creature", "pick_friendly_creature", "self",
	"own_hero", "enemy_hero", "both_heroes", "all_enemy_creatures", "all_friendly_creatures", "all_other_friendly",
	"all_creatures", "all_enemies", "random_enemy_creature", "random_enemy", "random_friendly_creature", "attacker", "played"]

var rules: Dictionary
var keywords: Dictionary
var cards: Dictionary  # id -> card
var leaders: Dictionary  # id -> leader

const WRITING := "res://data/tcg/writing/cards.txt"


func _init(rules_data: Dictionary, keyword_data: Dictionary, card_data: Dictionary, leader_data: Dictionary) -> void:
	rules = rules_data
	keywords = keyword_data
	cards = card_data.get("cards", card_data)
	leaders = leader_data.get("leaders", leader_data)


static func from_files() -> RefCounted:
	var script: GDScript = load("res://core/tcg/card_db.gd")
	var db: RefCounted = script.new(_json("res://data/tcg/rules.json"), _json("res://data/tcg/keywords.json"),
		_json("res://data/tcg/cards.json"), _json("res://data/tcg/leaders.json"))
	if FileAccess.file_exists(WRITING):
		db.call("add_words", TextBook.parse(FileAccess.get_file_as_string(WRITING)))
	return db


# The writers' file: [card id] name / flavor, [leader id] name / power / flavor.
func add_words(book: Dictionary) -> void:
	for id: String in book.get("card", {}):
		if cards.has(id):
			var words: Dictionary = book["card"][id]
			cards[id]["name"] = String(words.get("name", ""))
			cards[id]["flavor"] = String(words.get("flavor", ""))
	for id: String in book.get("leader", {}):
		if leaders.has(id):
			var words: Dictionary = book["leader"][id]
			leaders[id]["name"] = String(words.get("name", ""))
			leaders[id]["flavor"] = String(words.get("flavor", ""))
			(leaders[id]["power"] as Dictionary)["name"] = String(words.get("power", ""))


static func _json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func card(id: String) -> Dictionary:
	return cards.get(id, {})


func has_keyword(c: Dictionary, kw: String) -> bool:
	return (c.get("keywords", []) as Array).has(kw)


# The pick a card or power asks for when played ("" = none): the first pick_* target of its arrival / cast / power.
func pick_of(effects: Array) -> String:
	for e: Dictionary in effects:
		if String(e.get("when", "")) in ["arrival", "cast", "power"] and String(e.get("to", "")).begins_with("pick_"):
			return String(e["to"])
	return ""


# Is this deck legal? {"leader": id, "cards": [ids]} -> "" or why not.
func deck_problem(deck: Dictionary) -> String:
	var leader: Dictionary = leaders.get(String(deck.get("leader", "")), {})
	if leader.is_empty():
		return "no leader"
	var list: Array = deck.get("cards", [])
	if list.size() != int(rules["deck_size"]):
		return "a deck holds %d cards (this one %d)" % [int(rules["deck_size"]), list.size()]
	var counts := {}
	var factions := {String(leader["faction"]): true}
	for id: Variant in list:
		var c := card(String(id))
		if c.is_empty() or String(c["rarity"]) == "token":
			return "%s is not a card you can put in a deck" % id
		counts[id] = int(counts.get(id, 0)) + 1
		var limit := int(rules["legendary_copies"]) if String(c["rarity"]) == "legendary" else int(rules["copies"])
		if int(counts[id]) > limit:
			return "too many copies of %s" % c["name"]
		if String(c["faction"]) != "neutral":
			factions[String(c["faction"])] = true
	if factions.size() > int(rules["max_factions"]):
		return "a deck mixes at most %d factions" % int(rules["max_factions"])
	return ""


# Everything wrong with the data (empty = fine).
func problems() -> Array[String]:
	var out: Array[String] = []
	for key: String in ["hero_health", "mana_max", "deck_size", "copies", "legendary_copies", "first_hand", "second_hand",
			"lucky_card", "hand_max", "board_max", "mulligans", "fatigue_start", "power_cost", "turn_seconds", "max_factions", "max_traps"]:
		if not rules.has(key):
			out.append("rules: missing %s" % key)
	for id: String in cards:
		var c: Dictionary = cards[id]
		var where := "card %s" % id
		if not FACTIONS.has(String(c.get("faction", ""))) or not TYPES.has(String(c.get("type", ""))) or not RARITIES.has(String(c.get("rarity", ""))):
			out.append("%s: faction / type / rarity" % where)
			continue
		if int(c.get("cost", -1)) < 0 or int(c.get("cost", -1)) > int(rules.get("mana_max", 8)):
			out.append("%s: cost" % where)
		if String(c["type"]) == "creature" and (int(c.get("attack", -1)) < 0 or int(c.get("health", 0)) < 1):
			out.append("%s: a creature needs attack >= 0 and health >= 1" % where)
		if String(c.get("name", "")) == "":
			out.append("%s: no name (data/tcg/writing/cards.txt)" % where)
		if String(c["type"]) == "trap" and String(c["faction"]) != "club":
			out.append("%s: traps are Club only" % where)
		for kw: Variant in c.get("keywords", []):
			if not keywords.has(String(kw)):
				out.append("%s: unknown keyword %s" % [where, kw])
		_check_effects(c.get("effects", []), where, String(c["type"]), out)
	for id: String in leaders:
		var l: Dictionary = leaders[id]
		if not FACTIONS.has(String(l.get("faction", ""))) or String(l.get("faction", "")) == "neutral":
			out.append("leader %s: faction" % id)
		var power: Dictionary = l.get("power", {})
		if String(l.get("name", "")) == "":
			out.append("leader %s: no name (data/tcg/writing/cards.txt)" % id)
		if power.is_empty() or String(power.get("name", "")) == "":
			out.append("leader %s: no hero power (or no power name in data/tcg/writing/cards.txt)" % id)
		_check_effects(power.get("effects", []), "leader %s" % id, "power", out)
	if not cards.has(String(rules.get("lucky_card", ""))):
		out.append("rules: lucky_card %s is not a card" % rules.get("lucky_card", ""))
	return out


# The full set against its locked shape (rules.json "set"): "" or what is off.
func set_problem() -> String:
	var shape: Dictionary = rules.get("set", {})
	if shape.is_empty():
		return ""
	var by_faction := {}
	var by_rarity := {}
	for id: String in cards:
		var c: Dictionary = cards[id]
		if String(c["rarity"]) == "token":
			continue
		by_faction[String(c["faction"])] = int(by_faction.get(String(c["faction"]), 0)) + 1
		by_rarity[String(c["rarity"])] = int(by_rarity.get(String(c["rarity"]), 0)) + 1
	var off: PackedStringArray = []
	for f: String in FACTIONS:
		var want := int(shape["neutral_cards"]) if f == "neutral" else int(shape["faction_cards"])
		if int(by_faction.get(f, 0)) != want:
			off.append("%s has %d cards (want %d)" % [f, int(by_faction.get(f, 0)), want])
	for r: String in shape["rarity"]:
		if int(by_rarity.get(r, 0)) != int(shape["rarity"][r]):
			off.append("%d %s (want %d)" % [int(by_rarity.get(r, 0)), r, int(shape["rarity"][r])])
	var lead := {}
	for id: String in leaders:
		lead[String(leaders[id]["faction"])] = int(lead.get(String(leaders[id]["faction"]), 0)) + 1
	for f: String in FACTIONS:
		if f != "neutral" and int(lead.get(f, 0)) != int(shape["leaders_per_faction"]):
			off.append("%s has %d leaders" % [f, int(lead.get(f, 0))])
	return ", ".join(off)


func _check_effects(effects: Array, where: String, kind: String, out: Array[String]) -> void:
	for e: Dictionary in effects:
		var when := String(e.get("when", ""))
		var does := String(e.get("do", ""))
		if not WHENS.has(when) or not DOES.has(does):
			out.append("%s: effect when / do (%s / %s)" % [where, when, does])
			continue
		if kind == "trap" and not TRAP_WHENS.has(when):
			out.append("%s: a trap fires on an enemy's move" % where)
		if e.has("to") and not TARGETS.has(String(e["to"])):
			out.append("%s: unknown target %s" % [where, e["to"]])
		if does in ["summon", "add"] and not cards.has(String(e.get("card", ""))):
			out.append("%s: %s names no card (%s)" % [where, does, e.get("card", "")])
		if does == "give" and not keywords.has(String(e.get("keyword", ""))):
			out.append("%s: give names no keyword" % where)
		for branch: String in ["low", "high", "heads", "tails"]:
			if e.has(branch):
				var inner: Array = []
				for sub: Dictionary in e[branch]:
					var copy := sub.duplicate()
					copy["when"] = when
					inner.append(copy)
				_check_effects(inner, where + " (" + branch + ")", kind, out)
