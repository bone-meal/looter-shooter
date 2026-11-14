# Purpose: what the binder shows, in which order: every collectible card and leader with its set number (cards in
# data/tcg/cards.json order, tokens left out, then the leaders), filtered by faction / cost / rarity / type / tribe /
# owned or missing and sorted by number, cost, rarity, name or newest. Pure: no nodes.
# Dependencies: core/tcg/card_db.gd and core/tcg/collection.gd (both handed in).
extends RefCounted

const RARITY_ORDER := {"common": 0, "rare": 1, "epic": 2, "legendary": 3}
const ALL := {"faction": "", "cost": -1, "rarity": "", "type": "", "tribe": "", "show": "all", "sort": "number"}


# id -> set number (1 ...), and whether it is a leader.
static func numbers(db: RefCounted) -> Dictionary:
	var out := {}
	var n := 0
	var cards: Dictionary = db.get("cards")
	for id: String in cards:
		if String(cards[id]["rarity"]) != "token":
			n += 1
			out[id] = {"no": n, "leader": false}
	for id: String in db.get("leaders"):
		n += 1
		out[id] = {"no": n, "leader": true}
	return out


# The card-like facts of one entry: faction, cost, rarity, type ("leader" for leaders), tribe, name.
static func facts(db: RefCounted, id: String, leader: bool) -> Dictionary:
	if leader:
		var l: Dictionary = db.get("leaders")[id]
		return {"faction": String(l["faction"]), "cost": int(db.get("rules")["power_cost"]), "rarity": "legendary", "type": "leader",
			"tribe": "", "name": String(l.get("name", id))}
	var c: Dictionary = db.card(id)
	return {"faction": String(c["faction"]), "cost": int(c["cost"]), "rarity": String(c["rarity"]), "type": String(c["type"]),
		"tribe": String(c.get("tribe", "")), "name": String(c.get("name", id))}


# The entries to show: [{"id", "leader", "no", "have"}]. `f` holds the keys of ALL (missing keys = no filter).
# cost 8 means 8 or more.
static func entries(db: RefCounted, owned: RefCounted, f: Dictionary) -> Array:
	var want: Dictionary = ALL.duplicate()
	want.merge(f, true)
	var out: Array = []
	var nums := numbers(db)
	for id: String in nums:
		var leader: bool = nums[id]["leader"]
		var x := facts(db, id, leader)
		var have: int = owned.count(id, "*", leader)
		if want["faction"] != "" and x["faction"] != want["faction"]:
			continue
		if int(want["cost"]) >= 0 and (mini(int(x["cost"]), 8) != int(want["cost"])):
			continue
		if want["rarity"] != "" and x["rarity"] != want["rarity"]:
			continue
		if want["type"] != "" and x["type"] != want["type"]:
			continue
		if want["tribe"] != "" and x["tribe"] != want["tribe"]:
			continue
		if (want["show"] == "owned" and have <= 0) or (want["show"] == "missing" and have > 0):
			continue
		out.append({"id": id, "leader": leader, "no": int(nums[id]["no"]), "have": have, "cost": int(x["cost"]),
			"rarity": RARITY_ORDER.get(x["rarity"], 0), "name": x["name"]})
	var got: Array = owned.get("got")
	match String(want["sort"]):
		"cost":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [a["cost"], a["no"]] < [b["cost"], b["no"]])
		"rarity":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [-int(a["rarity"]), a["no"]] < [-int(b["rarity"]), b["no"]])
		"name":
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["name"]) < String(b["name"]))
		"newest":  # most recently first owned first; never owned at the end by number
			out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [-got.find(a["id"]), a["no"]] < [-got.find(b["id"]), b["no"]])
	return out


# The tribes in the set, for the filter list.
static func tribes(db: RefCounted) -> Array:
	var out: Array = []
	var cards: Dictionary = db.get("cards")
	for id: String in cards:
		var t := String(cards[id].get("tribe", ""))
		if t != "" and String(cards[id]["rarity"]) != "token" and not out.has(t):
			out.append(t)
	out.sort()
	return out
