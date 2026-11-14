# Purpose: one player's card game collection of "You got me Lobster?" (locked: permanent, cards only ever traded):
# cards and leaders owned per finish ("" plain, "rainbow", "pony"), unopened packs, the five deck slots, play mats,
# pity counters for pack rolls, and the record (wins / losses against players, per opponent name and per deck; the
# House Dealer's own record apart: wins against her never count toward the win milestones). Saved in the profile's
# extra "tcg" as plain ids + counts + a version number. Pure: no nodes.
# Dependencies: core/tcg/card_db.gd (handed in, for checking ids and deck legality).
extends RefCounted

const VERSION := 1
const FINISHES := ["", "rainbow", "pony"]
const DECK_SLOTS := 5
const START_PACKS := 3  # locked: a new player picks one starter deck + 3 packs

var cards: Dictionary = {}  # id -> {finish: count}
var leaders: Dictionary = {}  # leader id -> {finish: count}
var packs: Dictionary = {}  # pack kind -> count
var decks: Array = []  # DECK_SLOTS entries: {} empty or {"name", "leader", "cards": [ids]}
var mats: Array = []  # play mat ids owned
var mat := ""  # the mat in use
var pity: Dictionary = {"epic": 0, "legendary": 0}  # packs opened since the last epic / legendary
var record: Dictionary = {}
var starter := ""  # the starter deck picked at the first sit-down ("" = not yet)
var box: Dictionary = {"left": 0, "legendaries": 0, "epics": 0}  # unopened box packs and what they still owe (core/tcg/pack_roll.gd)
var got: Array = []  # card and leader ids in the order first owned (the binder's "newest" sort), newest last


func _init() -> void:
	_blank()


func _blank() -> void:
	cards = {}
	leaders = {}
	packs = {}
	decks = []
	for i in DECK_SLOTS:
		decks.append({})
	mats = []
	mat = ""
	pity = {"epic": 0, "legendary": 0}
	record = {"wins": 0, "losses": 0, "streak": 0, "best_streak": 0, "vs": {}, "decks": {}, "house": {"wins": 0, "losses": 0, "decks_won": []}}
	starter = ""
	box = {"left": 0, "legendaries": 0, "epics": 0}
	got = []


# ---- owning ----

func add(id: String, finish := "", n := 1, leader := false) -> void:
	var book: Dictionary = leaders if leader else cards
	if not book.has(id):
		book[id] = {}
		got.erase(id)
		got.append(id)
	book[id][finish] = int((book[id] as Dictionary).get(finish, 0)) + n


# Takes n copies of one finish away (a trade); false and nothing changes when there are not that many.
func remove(id: String, finish := "", n := 1, leader := false) -> bool:
	var book: Dictionary = leaders if leader else cards
	var have := int((book.get(id, {}) as Dictionary).get(finish, 0))
	if n <= 0 or have < n:
		return false
	book[id][finish] = have - n
	if int(book[id][finish]) == 0:
		(book[id] as Dictionary).erase(finish)
	if (book[id] as Dictionary).is_empty():
		book.erase(id)
	return true


# Copies owned of a card (all finishes together unless one is named).
func count(id: String, finish := "*", leader := false) -> int:
	var per: Dictionary = (leaders if leader else cards).get(id, {})
	if finish != "*":
		return int(per.get(finish, 0))
	var n := 0
	for f: String in per:
		n += int(per[f])
	return n


func add_pack(kind: String, n := 1) -> void:
	packs[kind] = int(packs.get(kind, 0)) + n


func take_pack(kind: String) -> bool:
	if int(packs.get(kind, 0)) <= 0:
		return false
	packs[kind] = int(packs[kind]) - 1
	if int(packs[kind]) == 0:
		packs.erase(kind)
	return true


# A bought box: its packs (kind "box") and the guarantee they carry.
func add_box(packs_in: int, legendaries: int, epics: int) -> void:
	add_pack("box", packs_in)
	box["left"] = int(box["left"]) + packs_in
	box["legendaries"] = int(box["legendaries"]) + legendaries
	box["epics"] = int(box["epics"]) + epics


func pack_count() -> int:
	var n := 0
	for k: String in packs:
		n += int(packs[k])
	return n


# The first sit-down: the chosen starter's 20 cards and leader, the deck in the first empty slot, and 3 packs.
func give_starter(starter_id: String, deck: Dictionary, pack_kind: String) -> void:
	starter = starter_id
	for id: Variant in deck["cards"]:
		add(String(id))
	add(String(deck["leader"]), "", 1, true)
	set_deck(first_free_slot(), {"name": deck["name"], "leader": deck["leader"], "cards": (deck["cards"] as Array).duplicate()})
	add_pack(pack_kind, START_PACKS)


# A whole starter deck bought at the machine: its cards and leader (the deck is not put in a slot by itself).
func give_deck_cards(deck: Dictionary) -> void:
	for id: Variant in deck["cards"]:
		add(String(id))
	add(String(deck["leader"]), "", 1, true)


func first_free_slot() -> int:
	for i in DECK_SLOTS:
		if (decks[i] as Dictionary).is_empty():
			return i
	return DECK_SLOTS - 1


func set_deck(slot: int, deck: Dictionary) -> void:
	if slot >= 0 and slot < DECK_SLOTS:
		decks[slot] = deck


# "" when the player owns everything this deck needs (copies of each card and the leader), else what is missing.
func missing_for(deck: Dictionary) -> String:
	if count(String(deck.get("leader", "")), "*", true) <= 0:
		return "you do not own the leader"
	var need := {}
	for id: Variant in deck.get("cards", []):
		need[String(id)] = int(need.get(String(id), 0)) + 1
	for id: String in need:
		if count(id) < int(need[id]):
			return "you own %d of %s (the deck uses %d)" % [count(id), id, int(need[id])]
	return ""


# The decks that can be played now: slot index -> deck, for full, legal, owned slots.
func playable(db: RefCounted) -> Dictionary:
	var out := {}
	for i in DECK_SLOTS:
		var d: Dictionary = decks[i]
		if not d.is_empty() and db.deck_problem(d) == "" and missing_for(d) == "":
			out[i] = d
	return out


# ---- the record ----

# vs_ai: a match against the House Dealer (her own record; never the player W/L, streak or milestones).
func record_result(won: bool, opponent: String, deck_name: String, vs_ai: bool, starter_id := "") -> void:
	if vs_ai:
		var house: Dictionary = record["house"]
		house["wins" if won else "losses"] = int(house["wins" if won else "losses"]) + 1
		if won and starter_id != "" and not (house["decks_won"] as Array).has(starter_id):
			(house["decks_won"] as Array).append(starter_id)
		return
	record["wins" if won else "losses"] = int(record["wins" if won else "losses"]) + 1
	record["streak"] = int(record["streak"]) + 1 if won else 0
	record["best_streak"] = maxi(int(record["best_streak"]), int(record["streak"]))
	for pair: Array in [[record["vs"], opponent], [record["decks"], deck_name]]:
		var table: Dictionary = pair[0]
		var row: Array = table.get(String(pair[1]), [0, 0])
		row[0 if won else 1] = int(row[0 if won else 1]) + 1
		table[String(pair[1])] = row


# ---- save ----

func to_dict() -> Dictionary:
	return {"version": VERSION, "cards": cards, "leaders": leaders, "packs": packs, "decks": decks, "mats": mats, "mat": mat,
		"pity": pity, "record": record, "starter": starter, "box": box, "got": got}


# Reads a saved collection; unknown ids, bad counts and broken decks are dropped (the rest is kept).
func from_dict(d: Variant, db: RefCounted) -> void:
	_blank()
	if not d is Dictionary or int((d as Dictionary).get("version", 0)) < 1:
		return
	var src: Dictionary = d
	for pair: Array in [[src.get("cards", {}), false], [src.get("leaders", {}), true]]:
		if not pair[0] is Dictionary:
			continue
		for id: String in pair[0]:
			var known: bool = (db.get("leaders") as Dictionary).has(id) if pair[1] else not (db.card(id) as Dictionary).is_empty()
			if not known or not pair[0][id] is Dictionary:
				continue
			for f: String in pair[0][id]:
				if FINISHES.has(f) and int(pair[0][id][f]) > 0:
					add(id, f, int(pair[0][id][f]), pair[1])
	if src.get("packs") is Dictionary:
		for k: String in src["packs"]:
			if int(src["packs"][k]) > 0:
				add_pack(k, int(src["packs"][k]))
	if src.get("decks") is Array:
		for i in mini((src["decks"] as Array).size(), DECK_SLOTS):
			var deck: Variant = src["decks"][i]
			if deck is Dictionary and not (deck as Dictionary).is_empty() and (deck as Dictionary).get("cards") is Array:
				decks[i] = {"name": String(deck.get("name", "Deck %d" % (i + 1))), "leader": String(deck.get("leader", "")), "cards": (deck["cards"] as Array).map(func(x: Variant) -> String: return String(x))}
	if src.get("mats") is Array:
		mats = (src["mats"] as Array).map(func(x: Variant) -> String: return String(x))
	mat = String(src.get("mat", ""))
	if src.get("pity") is Dictionary:
		for k: String in ["epic", "legendary"]:
			pity[k] = maxi(int(src["pity"].get(k, 0)), 0)
	if src.get("record") is Dictionary:
		var r: Dictionary = src["record"]
		for k: String in ["wins", "losses", "streak", "best_streak"]:
			record[k] = maxi(int(r.get(k, 0)), 0)
		for k: String in ["vs", "decks"]:
			if r.get(k) is Dictionary:
				record[k] = r[k]
		if r.get("house") is Dictionary:
			for k: String in ["wins", "losses"]:
				record["house"][k] = maxi(int(r["house"].get(k, 0)), 0)
			if r["house"].get("decks_won") is Array:
				record["house"]["decks_won"] = r["house"]["decks_won"]
	starter = String(src.get("starter", ""))
	if src.get("got") is Array:  # the saved order first, then anything owned it misses
		var order: Array = []
		for id: Variant in src["got"]:
			if (cards.has(String(id)) or leaders.has(String(id))) and not order.has(String(id)):
				order.append(String(id))
		for id: String in got:
			if not order.has(id):
				order.append(id)
		got = order
	if src.get("box") is Dictionary:
		for k: String in ["left", "legendaries", "epics"]:
			box[k] = maxi(int(src["box"].get(k, 0)), 0)
