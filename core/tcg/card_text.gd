# Purpose: the rules text printed on a card, written out from its keywords and effects (data/tcg/cards.json), e.g.
# "Guard. Arrival: Deal 1 damage to an enemy." Pure. (Flavour text and hand-written overrides come with step 6.)
# Dependencies: core/tcg/card_db.gd (passed in, for keyword and card names).
extends RefCounted

# Keywords that are printed as a word on their own; Arrival / Last Gasp are printed as the start of their effect.
const PREFIX := {
	"arrival": "Arrival: ", "last_gasp": "Last Gasp: ", "turn_start": "At the start of your turn: ",
	"turn_end": "At the end of your turn: ", "attack": "When it attacks: ", "friendly_death": "When a friendly creature dies: ",
	"spell_cast": "When you cast a spell: ", "enemy_attack": "Tell - when an enemy attacks: ",
	"enemy_creature": "Tell - when the enemy plays a creature: ", "enemy_spell": "Tell - when the enemy casts a spell: ",
	"cast": "", "power": "",
}
const WHO := {
	"pick_any": "anything", "pick_creature": "a creature", "pick_enemy": "an enemy", "pick_enemy_creature": "an enemy creature",
	"pick_friendly_creature": "a friendly creature", "self": "itself", "own_hero": "your leader", "enemy_hero": "the enemy leader",
	"both_heroes": "both leaders", "all_enemy_creatures": "all enemy creatures", "all_friendly_creatures": "your creatures",
	"all_other_friendly": "your other creatures", "all_creatures": "all creatures", "all_enemies": "all enemies",
	"random_enemy_creature": "a random enemy creature", "random_enemy": "a random enemy",
	"random_friendly_creature": "a random friendly creature", "attacker": "the attacker", "played": "that creature",
}


static func of(db: RefCounted, c: Dictionary) -> String:
	var parts: PackedStringArray = []
	for kw: Variant in c.get("keywords", []):
		if not PREFIX.has(String(kw)):
			parts.append(keyword_name(db, String(kw)))
	var last_when := ""
	var last_to := ""
	var line := ""
	for e: Dictionary in c.get("effects", []):
		var when := String(e.get("when", ""))
		if when != last_when:
			if line != "":
				parts.append(line)
			line = String(PREFIX.get(when, "")) + _cap(effect(db, e, ""))
		else:
			line += ", then " + effect(db, e, last_to)
		last_when = when
		last_to = String(e.get("to", ""))
	if line != "":
		parts.append(line)
	return ". ".join(parts) + ("." if not parts.is_empty() else "")


# One effect in words. `same_as` = the previous effect's target: the same pick again is "it".
static func effect(db: RefCounted, e: Dictionary, same_as: String) -> String:
	var to := String(e.get("to", "self"))
	var who := "it" if to == same_as and to.begins_with("pick") else String(WHO.get(to, to))
	var amount := int(e.get("amount", 1))
	var per := _per(String(e.get("per", "")))
	match String(e["do"]):
		"damage":
			return "deal %d damage to %s%s" % [amount, who, per]
		"heal":
			return "restore %d health to %s%s" % [amount, who, per]
		"draw":
			return ("draw a card" if amount == 1 else "draw %d cards" % amount) + per
		"summon":
			var n := int(e.get("count", 1))
			var c: Dictionary = db.card(String(e["card"]))
			var stats := "%d/%d" % [int(c.get("attack", 0)), int(c.get("health", 0))]
			var whose := " for the enemy" if to == "enemy_hero" else ""
			return ("summon a %s %s" % [stats, c["name"]] if n == 1 else "summon %d %s %ss" % [n, stats, c["name"]]) + whose + per
		"buff":
			return "give %s %s%s" % [who, _plus(int(e.get("attack", 0)), int(e.get("health", 0))), per]
		"give":
			return "give %s %s" % [who, keyword_name(db, String(e["keyword"]))]
		"destroy":
			return "destroy %s" % who
		"mana":
			return "gain %d mana this turn" % amount
		"crystal":
			return "gain %d mana crystal%s" % [amount, "" if amount == 1 else "s"]
		"bounce":
			return "return %s to its owner's hand" % who
		"add":
			return "add a %s to your hand" % (db.card(String(e["card"])) as Dictionary).get("name", e["card"])
		"roll":
			var half := floori(float(int(e.get("sides", 6))) / 2.0)
			return "roll a die: 1-%d %s; %d-%d %s" % [half, _subs(db, e.get("low", [])), half + 1, int(e.get("sides", 6)), _subs(db, e.get("high", []))]
		"flip":
			return "flip a coin: heads %s; tails %s" % [_subs(db, e.get("heads", [])), _subs(db, e.get("tails", []))]
	return String(e["do"])


static func keyword_name(db: RefCounted, kw: String) -> String:
	return String((db.get("keywords") as Dictionary).get(kw, {}).get("name", kw.capitalize()))


# The hover lines for every keyword on a card: [[name, what it does], ...].
static func keyword_help(db: RefCounted, c: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	var words: Array = (c.get("keywords", []) as Array).duplicate()
	for e: Dictionary in c.get("effects", []):
		if String(e.get("do", "")) == "give":
			words.append(String(e["keyword"]))
	for kw: Variant in words:
		var k := String(kw)
		var row: Dictionary = (db.get("keywords") as Dictionary).get(k, {})
		if not seen.has(k) and not row.is_empty():
			seen[k] = true
			out.append([String(row["name"]), String(row["text"])])
	return out


static func _subs(db: RefCounted, list: Array) -> String:
	var bits: PackedStringArray = []
	for e: Dictionary in list:
		bits.append(effect(db, e, ""))
	return " and ".join(bits)


static func _per(per: String) -> String:
	match per.get_slice(":", 0):
		"":
			return ""
		"friendly_tribe":
			return " for each other friendly %s" % per.get_slice(":", 1).capitalize()
		"friendly_creatures":
			return " for each other friendly creature"
		"enemy_creatures":
			return " for each enemy creature"
		"cards_in_hand":
			return " for each card in your hand"
	return ""


static func _plus(a: int, h: int) -> String:
	if a != 0 and h != 0:
		return "+%d/+%d" % [a, h]
	return "+%d attack" % a if a != 0 else "+%d health" % h


static func _cap(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)
