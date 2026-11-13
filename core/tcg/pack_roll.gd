# Purpose: what a card pack of "You got me Lobster?" holds when it is opened (data/tcg/packs.json, locked odds): four
# cards at slot odds and a last card that is always rare or better, leaders at epic odds (a faction's second leader
# 10x rarer once the player owns one of its leaders), rainbow / pony foils per card, the pity counters (an epic within
# 15 packs, a legendary within 45), the god pack (1 in 2 000: 8 cards, all rare or better) and the box guarantee (a
# 50-pack box holds at least 5 legendaries and 12 epics: the last packs of a box are raised when they must be).
# Updates the collection's pity and box counters; the caller adds the cards. Pure.
# Dependencies: core/tcg/card_db.gd and core/tcg/collection.gd (handed in).
extends RefCounted

const ORDER := ["common", "rare", "epic", "legendary"]


# Opens one pack of `kind` ("standard" or "box"). Returns {"cards": [{"id", "finish", "leader", "rarity"}], "god": bool}.
static func open(db: RefCounted, owned: RefCounted, cfg: Dictionary, rng: RandomNumberGenerator, kind := "standard") -> Dictionary:
	var pity: Dictionary = owned.get("pity")
	pity["epic"] = int(pity["epic"]) + 1
	pity["legendary"] = int(pity["legendary"]) + 1
	var god := rng.randi_range(1, int(cfg["god"]["one_in"])) == 1
	var rarities: Array = []
	if god:
		for i in int(cfg["god"]["cards"]):
			rarities.append(_pick(cfg["god"]["odds"], rng))
	else:
		var std: Dictionary = cfg["standard"]
		for i in int(std["cards"]) - 1:
			rarities.append(_pick(std["slot"], rng))
		rarities.append(_pick(std["last"], rng))
	# the last card is raised by pity or the box's legendary guarantee, the one before it by the box's epic guarantee
	var need := ""
	if int(pity["legendary"]) >= int(cfg["pity"]["legendary"]):
		need = "legendary"
	elif int(pity["epic"]) >= int(cfg["pity"]["epic"]):
		need = "epic"
	var box_epic := false
	if kind == "box":
		var box: Dictionary = owned.get("box")
		var left := int(box.get("left", 0))
		if int(box.get("legendaries", 0)) >= left and _count(rarities, "legendary") == 0:
			need = "legendary"
		box_epic = int(box.get("epics", 0)) >= left and _count(rarities, "epic") == 0
	if need != "" and ORDER.find(String(rarities[-1])) < ORDER.find(need) and _count(rarities, need) == 0:
		rarities[-1] = need
	if box_epic and _count(rarities, "epic") == 0:
		rarities[-2 if String(rarities[-1]) == "legendary" else -1] = "epic"
	var out: Array = []
	var taken := {}
	for r: String in rarities:
		out.append(_card(db, owned, cfg, rng, r, taken))
	var best := 0
	for c: Dictionary in out:
		best = maxi(best, ORDER.find(String(c["rarity"])))
	if best >= ORDER.find("epic"):
		pity["epic"] = 0
	if best >= ORDER.find("legendary"):
		pity["legendary"] = 0
	if kind == "box":
		var box2: Dictionary = owned.get("box")
		box2["left"] = maxi(int(box2.get("left", 0)) - 1, 0)
		box2["legendaries"] = maxi(int(box2.get("legendaries", 0)) - _count_cards(out, "legendary"), 0)
		box2["epics"] = maxi(int(box2.get("epics", 0)) - _count_cards(out, "epic"), 0)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return ORDER.find(String(a["rarity"])) < ORDER.find(String(b["rarity"])))
	return {"cards": out, "god": god}


static func _card(db: RefCounted, owned: RefCounted, cfg: Dictionary, rng: RandomNumberGenerator, rarity: String, taken: Dictionary) -> Dictionary:
	var pool: Array = []  # [id, weight, is_leader]
	for id: String in db.get("cards"):
		var c: Dictionary = db.card(id)
		if String(c["rarity"]) == rarity and not taken.has(id):
			pool.append([id, 1.0, false])
	if rarity == "epic":  # leaders weigh like one epic each; the second of a faction much less once one is owned
		var leaders: Dictionary = db.get("leaders")
		for id: String in leaders:
			var w := 1.0
			for other: String in leaders:
				if other != id and String(leaders[other]["faction"]) == String(leaders[id]["faction"]) and int(owned.call("count", other, "*", true)) > 0:
					w = float(cfg["second_leader"])
			pool.append([id, w, true])
	var total := 0.0
	for p: Array in pool:
		total += float(p[1])
	var roll := rng.randf() * total
	var chosen: Array = pool[pool.size() - 1]
	for p: Array in pool:
		roll -= float(p[1])
		if roll <= 0.0:
			chosen = p
			break
	taken[chosen[0]] = true
	var finish := ""
	var f := rng.randf()
	if f < float(cfg["foil"]["pony"]):
		finish = "pony"
	elif f < float(cfg["foil"]["pony"]) + float(cfg["foil"]["rainbow"]):
		finish = "rainbow"
	return {"id": chosen[0], "finish": finish, "leader": chosen[2], "rarity": "epic" if chosen[2] else rarity}


static func _pick(odds: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k: String in odds:
		total += float(odds[k])
	var roll := rng.randf() * total
	for k: String in odds:
		roll -= float(odds[k])
		if roll <= 0.0:
			return k
	return String(odds.keys()[-1])


static func _count(list: Array, rarity: String) -> int:
	return list.count(rarity)


static func _count_cards(cards: Array, rarity: String) -> int:
	var n := 0
	for c: Dictionary in cards:
		if String(c["rarity"]) == rarity:
			n += 1
	return n
