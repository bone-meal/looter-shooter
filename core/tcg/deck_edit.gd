# Purpose: the deck builder's rules for "You got me Lobster?": add a card (deck not full, copy limits, cards owned,
# at most two factions besides neutral), take one out, pick the leader, the mana curve, and whether the deck can be
# played. A deck is {"name", "leader", "cards": [ids]} as in core/tcg/collection.gd. Pure: no nodes.
# Dependencies: core/tcg/card_db.gd and core/tcg/collection.gd (both handed in).
extends RefCounted

const CURVE_TOP := 8  # the last curve bar holds 8 and more


# Puts one copy in; "" when done, else why not (nothing changes).
static func add(db: RefCounted, owned: RefCounted, deck: Dictionary, id: String) -> String:
	var rules: Dictionary = db.get("rules")
	var c: Dictionary = db.card(id)
	if c.is_empty() or String(c["rarity"]) == "token":
		return "That card cannot go in a deck"
	var list: Array = deck.get("cards", [])
	if list.size() >= int(rules["deck_size"]):
		return "The deck is full (%d cards)" % int(rules["deck_size"])
	var in_deck := list.count(id)
	var limit := int(rules["legendary_copies"]) if String(c["rarity"]) == "legendary" else int(rules["copies"])
	if in_deck >= limit:
		return "At most %d of %s" % [limit, c.get("name", id)]
	if owned.count(id) <= in_deck:
		return "You own %d of %s" % [owned.count(id), c.get("name", id)]
	var f := String(c["faction"])
	if f != "neutral" and not factions(db, deck).has(f) and factions(db, deck).size() >= int(rules["max_factions"]):
		return "A deck mixes at most %d factions" % int(rules["max_factions"])
	list.append(id)
	deck["cards"] = list
	return ""


# Takes one copy out; false when it was not there.
static func remove(deck: Dictionary, id: String) -> bool:
	var list: Array = deck.get("cards", [])
	var at := list.find(id)
	if at < 0:
		return false
	list.remove_at(at)
	return true


static func set_leader(db: RefCounted, owned: RefCounted, deck: Dictionary, leader_id: String) -> String:
	if not (db.get("leaders") as Dictionary).has(leader_id):
		return "Not a leader"
	if owned.count(leader_id, "*", true) <= 0:
		return "You do not own this leader yet"
	deck["leader"] = leader_id
	return ""


# The factions in the deck (the leader's first), neutral left out.
static func factions(db: RefCounted, deck: Dictionary) -> Array:
	var out: Array = []
	var l: Dictionary = (db.get("leaders") as Dictionary).get(String(deck.get("leader", "")), {})
	if not l.is_empty():
		out.append(String(l["faction"]))
	for id: Variant in deck.get("cards", []):
		var f := String(db.card(String(id)).get("faction", "neutral"))
		if f != "neutral" and not out.has(f):
			out.append(f)
	return out


# Cards per cost: index 0 ... CURVE_TOP (the last holds CURVE_TOP and more).
static func curve(db: RefCounted, deck: Dictionary) -> Array:
	var out: Array = []
	out.resize(CURVE_TOP + 1)
	out.fill(0)
	for id: Variant in deck.get("cards", []):
		var c: Dictionary = db.card(String(id))
		if not c.is_empty():
			out[mini(int(c["cost"]), CURVE_TOP)] += 1
	return out


# "" when the deck can be played, else the first thing in the way.
static func problem(db: RefCounted, owned: RefCounted, deck: Dictionary) -> String:
	var p: String = db.deck_problem(deck)
	if p == "":
		p = owned.missing_for(deck)
	return p
