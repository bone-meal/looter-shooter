# Purpose: developer check of the card game's rules engine (core/tcg/match_state.gd + effects.gd + card_db.gd) with a
# small test card set made here: coin toss, hands, mulligan, mana, every keyword, traps, powers, fatigue, burn, deck
# legality, a dice card and determinism. Also checks the real data/tcg files when they exist.
# Log tools/tcg_rules_check.log (TCG_RULES_CHECK_DONE problems=n).
# Also: every real card gets printed rules text, every match event gets a log line (core/tcg/card_text.gd, event_text.gd),
# the full set has its locked shape, every starter is legal, and 40 AI matches of one-of decks play every card.
# The binder's list (core/tcg/binder_list.gd) and the deck builder's rules (core/tcg/deck_edit.gd) too.
# Dependencies: core/tcg/card_db.gd, core/tcg/match_state.gd, core/tcg/card_text.gd, core/tcg/event_text.gd,
# core/tcg/binder_list.gd, core/tcg/deck_edit.gd, core/tcg/collection.gd, core/tcg/pack_open.gd, core/tcg/mat_book.gd, core/wallet.gd.
extends Node

const CardDb = preload("res://core/tcg/card_db.gd")
const Match = preload("res://core/tcg/match_state.gd")
const CardText = preload("res://core/tcg/card_text.gd")
const EventText = preload("res://core/tcg/event_text.gd")

var _lines := PackedStringArray()
var _problems := 0
var _db: RefCounted


func _ready() -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/rules.json"))
	var keywords: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/keywords.json"))
	_db = CardDb.new(rules, keywords, _cards(), _leaders())
	var wrong: Array[String] = _db.problems()
	_say("test cards are well formed%s" % ("" if wrong.is_empty() else ": " + "; ".join(wrong)), wrong.is_empty())
	_check_start()
	_check_mana_and_sleep()
	_check_keywords()
	_check_spells_traps_powers()
	_check_end()
	_check_decks()
	_check_same_seed()
	var real: RefCounted = CardDb.from_files()
	if not (real.get("cards") as Dictionary).is_empty():
		var real_wrong: Array[String] = real.problems()
		_say("data/tcg cards and leaders are well formed (%d cards, %d leaders)%s" % [(real.get("cards") as Dictionary).size(), (real.get("leaders") as Dictionary).size(), "" if real_wrong.is_empty() else ": " + "; ".join(real_wrong)], real_wrong.is_empty())
		var shape: String = real.set_problem()
		_say("the full set has its locked shape (5 x 26 + 20 neutral, 70 / 45 / 23 / 12, 2 leaders a faction)%s" % ("" if shape == "" else ": " + shape), shape == "")
		var starters: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/starters.json")) as Dictionary)["starters"]
		for deck_id: String in starters:
			var why: String = real.deck_problem(starters[deck_id])
			_say("starter %s is legal%s" % [deck_id, "" if why == "" else ": " + why], why == "")
		_check_texts(real)
		_check_every_card(real)
		_check_collection(real)
		_check_packs(real)
		_check_binder(real)
	_finish()


func _cards() -> Dictionary:
	var c := {}
	c["lucky_chip"] = {"name": "Lucky Chip", "faction": "neutral", "type": "spell", "cost": 0, "rarity": "token", "effects": [{"when": "cast", "do": "mana", "amount": 1}]}
	c["grunt"] = _cr(1, 2, 2, [])
	c["wall"] = _cr(2, 1, 5, ["guard"])
	c["plate"] = _cr(1, 1, 1, ["plated"])
	c["charger"] = _cr(2, 2, 1, ["charge"])
	c["rusher"] = _cr(2, 3, 1, ["rush"])
	c["viper"] = _cr(1, 1, 1, ["venom"])
	c["leech"] = _cr(2, 2, 2, ["drain"])
	c["twin"] = _cr(3, 2, 4, ["twin_strike"])
	c["sneak"] = _cr(2, 3, 1, ["hidden"])
	c["sage"] = _cr(2, 1, 3, ["empower"])
	(c["sage"] as Dictionary)["empower"] = 1
	c["clock"] = _cr(2, 1, 2, ["wind_up"])
	c["ghoul"] = _cr(1, 1, 1, ["last_gasp"])
	(c["ghoul"] as Dictionary)["effects"] = [{"when": "last_gasp", "do": "summon", "card": "grunt"}]
	c["drowned"] = _cr(2, 1, 2, ["arrival"])
	(c["drowned"] as Dictionary)["tribe"] = "drowned"
	(c["drowned"] as Dictionary)["effects"] = [{"when": "arrival", "do": "buff", "to": "self", "attack": 1, "per": "friendly_tribe:drowned"}]
	c["bolt"] = {"name": "bolt", "faction": "neutral", "type": "spell", "cost": 1, "rarity": "common", "effects": [{"when": "cast", "do": "damage", "amount": 2, "to": "pick_any"}]}
	c["snare"] = {"name": "snare", "faction": "club", "type": "trap", "cost": 1, "rarity": "rare", "effects": [{"when": "enemy_attack", "do": "destroy", "to": "attacker"}]}
	c["dice"] = {"name": "dice", "faction": "club", "type": "spell", "cost": 1, "rarity": "common", "effects": [{"when": "cast", "do": "roll", "sides": 6, "low": [{"do": "damage", "amount": 1, "to": "enemy_hero"}], "high": [{"do": "draw", "amount": 1}]}]}
	c["legend"] = _cr(5, 5, 5, [])
	(c["legend"] as Dictionary)["rarity"] = "legendary"
	(c["legend"] as Dictionary)["faction"] = "tide"
	c["crypt_guy"] = _cr(1, 1, 1, [])
	(c["crypt_guy"] as Dictionary)["faction"] = "crypt"
	c["club_guy"] = _cr(1, 1, 1, [])
	(c["club_guy"] as Dictionary)["faction"] = "club"
	return {"cards": c}


func _cr(cost: int, atk: int, hp: int, kws: Array) -> Dictionary:
	return {"name": "test", "faction": "neutral", "type": "creature", "cost": cost, "rarity": "common", "attack": atk, "health": hp, "keywords": kws, "effects": []}


func _leaders() -> Dictionary:
	return {"leaders": {
		"tide_test": {"name": "Tide test", "faction": "tide", "power": {"name": "Call", "text": "", "effects": [{"when": "power", "do": "summon", "card": "grunt"}]}},
		"waste_test": {"name": "Waste test", "faction": "waste", "power": {"name": "Shot", "text": "", "effects": [{"when": "power", "do": "damage", "amount": 1, "to": "pick_any"}]}}}}


# A fresh match after both kept their hands; side 0 goes first; both sides' hands and mana can be set by the test.
func _match(seed_value := 7) -> RefCounted:
	var deck := []
	for i in 20:
		deck.append("grunt")
	var m: RefCounted = Match.new(_db, [{"leader": "tide_test", "cards": deck}, {"leader": "waste_test", "cards": deck.duplicate()}], seed_value, 0)
	m.mulligan(0, [])
	m.mulligan(1, [])
	return m


func _hand(m: RefCounted, side: int, ids: Array) -> void:
	m.get("sides")[side]["hand"] = ids.duplicate()


func _mana(m: RefCounted, side: int, n: int) -> void:
	m.get("sides")[side]["mana"] = n


func _check_start() -> void:
	var deck := []
	for i in 20:
		deck.append("grunt")
	var m: RefCounted = Match.new(_db, [{"leader": "tide_test", "cards": deck}, {"leader": "waste_test", "cards": deck.duplicate()}], 3, 0)
	var s: Array = m.get("sides")
	var hand1: Array = s[1]["hand"]
	_say("first player holds 3, second 4 + the Lucky Chip (%d / %d, chip %s)" % [(s[0]["hand"] as Array).size(), hand1.size(), str(hand1.has("lucky_chip"))], (s[0]["hand"] as Array).size() == 3 and hand1.size() == 5 and hand1.has("lucky_chip"))
	_say("nothing can be played before both kept their hands", m.play(0, 0) != "")
	_say("the chip cannot be sent back in a mulligan", m.mulligan(1, [hand1.find("lucky_chip")]) != "")
	m.mulligan(0, [0, 1])
	m.mulligan(1, [])
	_say("after the mulligan the first turn starts with a draw and 1 mana (hand %d, mana %d, deck %d)" % [(s[0]["hand"] as Array).size(), int(s[0]["mana"]), (s[0]["deck"] as Array).size()], m.get("phase") == "play" and (s[0]["hand"] as Array).size() == 4 and int(s[0]["mana"]) == 1 and (s[0]["deck"] as Array).size() == 16)


func _check_mana_and_sleep() -> void:
	var m := _match()
	var s: Array = m.get("sides")
	var crystals: Array = []
	for i in 20:
		crystals.append(int(s[m.get("current")]["crystals"]))
		m.end_turn(m.get("current"))
	_say("crystals grow by one a turn to 8 (%s)" % str(crystals.slice(0, 18)), crystals[0] == 1 and crystals[1] == 1 and crystals[2] == 2 and crystals[15] == 8 and crystals[19] == 8)
	m = _match()
	_hand(m, 0, ["grunt", "charger", "rusher"])
	_mana(m, 0, 10)
	m.play(0, 0)
	var grunt := int((m.get("sides")[0]["board"] as Array)[0]["uid"])
	_say("a fresh creature cannot attack", m.attack(0, grunt, Match.HERO - 1) != "")
	m.play(0, 0)
	var charger := int((m.get("sides")[0]["board"] as Array)[1]["uid"])
	_say("Charge attacks the leader at once", m.attack(0, charger, Match.HERO - 1) == "" and int(m.get("sides")[1]["hp"]) == 18)
	m.end_turn(0)
	_hand(m, 1, ["grunt"])
	_mana(m, 1, 10)
	m.play(1, 0)
	var enemy := int((m.get("sides")[1]["board"] as Array)[0]["uid"])
	m.end_turn(1)
	_hand(m, 0, ["rusher"])
	_mana(m, 0, 10)
	m.play(0, 0)
	var rusher := int((m.get("sides")[0]["board"] as Array)[2]["uid"])
	_say("Rush may hit a creature but not the leader the turn it lands", m.attack(0, rusher, Match.HERO - 1) != "" and m.attack(0, rusher, enemy) == "")
	_say("a creature from last turn attacks (grunt 2/2 -> leader 18 -> 16)", m.attack(0, grunt, Match.HERO - 1) == "" and int(m.get("sides")[1]["hp"]) == 16)


func _check_keywords() -> void:
	var m := _match()
	_hand(m, 0, ["grunt", "viper", "leech", "twin", "sage", "clock"])
	_mana(m, 0, 20)
	for i in 6:
		m.play(0, 0)
	m.end_turn(0)
	_hand(m, 1, ["wall", "plate", "sneak", "grunt"])
	_mana(m, 1, 20)
	for i in 4:
		m.play(1, 0)
	m.end_turn(1)
	var mine: Array = m.get("sides")[0]["board"]
	var theirs: Array = m.get("sides")[1]["board"]
	var uid := func(board: Array, i: int) -> int: return int(board[i]["uid"])
	var wall: int = uid.call(theirs, 0)
	var plate: int = uid.call(theirs, 1)
	var sneak: int = uid.call(theirs, 2)
	var their_grunt: int = uid.call(theirs, 3)
	_say("Guard: only the wall may be attacked", m.attack_targets(0, uid.call(mine, 0)) == [wall])
	_say("Wind-up grew the clock at the start of its turn (%d/%d)" % [int(mine[5]["atk"]), int(mine[5]["hp"])], int(mine[5]["atk"]) == 2 and int(mine[5]["hp"]) == 3)
	m.attack(0, uid.call(mine, 1), wall)  # viper 1/1 venom into the wall
	_say("Venom destroys the wall it touched", m.find(wall).is_empty())
	_say("Hidden cannot be attacked", not m.attack_targets(0, uid.call(mine, 0)).has(sneak))
	var leech: int = uid.call(mine, 0) if String(mine[0]["card"]) == "leech" else -1
	for c: Dictionary in mine:
		if String(c["card"]) == "leech":
			leech = int(c["uid"])
	m.get("sides")[0]["hp"] = 10
	m.attack(0, leech, Match.HERO - 1)
	_say("Drain heals the leader by the damage (10 -> 12)", int(m.get("sides")[0]["hp"]) == 12)
	var twin := -1
	for c: Dictionary in m.get("sides")[0]["board"]:
		if String(c["card"]) == "twin":
			twin = int(c["uid"])
	m.attack(0, twin, plate)
	_say("Plated ignores the first hit", not m.find(plate).is_empty() and int(m.find(plate)["hp"]) == 1)
	_say("Twin Strike attacks a second time", m.attack(0, twin, plate) == "" and m.find(plate).is_empty())
	_say("but not a third", m.attack(0, twin, their_grunt) != "")
	_hand(m, 0, ["bolt"])
	_mana(m, 0, 5)
	var hp_before := int(m.find(their_grunt).get("hp", 0))
	m.play(0, 0, their_grunt)
	_say("Empower 1 makes a 2-damage spell deal 3 (grunt %d -> dead)" % hp_before, m.find(their_grunt).is_empty())
	m.end_turn(0)
	_mana(m, 1, 5)
	var sneak_hit: String = m.attack(1, sneak, Match.HERO)
	_say("a Hidden creature that attacks can be picked afterwards", sneak_hit == "" and m.targets_for(0, "pick_enemy_creature").has(sneak))


func _check_spells_traps_powers() -> void:
	var m := _match()
	_hand(m, 0, ["ghoul", "drowned", "drowned", "drowned"])
	_mana(m, 0, 20)
	for i in 4:
		m.play(0, 0)
	var board: Array = m.get("sides")[0]["board"]
	_say("a Drowned gets +1 attack per other Drowned on arrival (%d, %d, %d)" % [int(board[1]["atk"]), int(board[2]["atk"]), int(board[3]["atk"])], int(board[1]["atk"]) == 1 and int(board[2]["atk"]) == 2 and int(board[3]["atk"]) == 3)
	var ghoul := int(board[0]["uid"])
	m.end_turn(0)
	_hand(m, 1, ["bolt"])
	_mana(m, 1, 5)
	_say("a spell that picks needs a target", m.play(1, 0) != "")
	m.play(1, 0, ghoul)
	_say("Last Gasp: the ghoul left a grunt behind", m.find(ghoul).is_empty() and String((m.get("sides")[0]["board"] as Array).back()["card"]) == "grunt")
	_mana(m, 1, 5)
	_say("the hero power works once a turn (1 damage)", m.power(1, Match.HERO) == "" and int(m.get("sides")[0]["hp"]) == 19 and m.power(1, Match.HERO) != "")
	_hand(m, 1, ["snare"])
	_mana(m, 1, 5)
	m.play(1, 0)
	_say("a trap is set face down", (m.get("sides")[1]["traps"] as Array) == ["snare"])
	m.end_turn(1)
	var attacker := int((m.get("sides")[0]["board"] as Array)[0]["uid"])
	m.attack(0, attacker, Match.HERO - 1)
	_say("the trap destroyed the attacker before it hit (leader still 20)", m.find(attacker).is_empty() and int(m.get("sides")[1]["hp"]) == 20 and (m.get("sides")[1]["traps"] as Array).is_empty())
	_hand(m, 0, ["dice"])
	_mana(m, 0, 5)
	m.play(0, 0)
	var rolls: Array = m.take_log().filter(func(e: Dictionary) -> bool: return String(e["e"]) == "roll")
	_say("a dice card rolls and logs it (%s)" % str(rolls), rolls.size() == 1)


func _check_end() -> void:
	var m := _match()
	var s: Dictionary = m.get("sides")[0]
	s["deck"] = []
	s["hp"] = 20
	m.end_turn(0)
	m.end_turn(1)
	m.end_turn(0)
	m.end_turn(1)
	_say("fatigue grows: 1 then 2 (leader %d)" % int(s["hp"]), int(s["hp"]) == 17)
	var full: Array = []
	for i in 10:
		full.append("grunt")
	var m2 := _match()
	_hand(m2, 1, full)
	m2.end_turn(0)
	var burned: Array = m2.take_log().filter(func(e: Dictionary) -> bool: return String(e["e"]) == "burn")
	_say("a card drawn into a full hand burns", burned.size() == 1 and (m2.get("sides")[1]["hand"] as Array).size() == 10)
	var m3 := _match()
	m3.concede(0)
	_say("conceding hands the win over", m3.get("phase") == "over" and int(m3.get("winner")) == 1 and m3.play(1, 0) != "")


func _check_decks() -> void:
	var good := []
	for id: String in ["grunt", "wall", "plate", "charger", "rusher", "viper", "leech", "twin", "sneak", "sage"]:
		good.append(id)
		good.append(id)
	_say("a 20-card deck with 2 copies is legal", _db.deck_problem({"leader": "tide_test", "cards": good}) == "")
	var three := good.duplicate()
	three[2] = "grunt"
	_say("three copies are refused", _db.deck_problem({"leader": "tide_test", "cards": three}) != "")
	var two_legends := good.duplicate()
	two_legends[0] = "legend"
	two_legends[2] = "legend"
	_say("two of a legendary are refused", _db.deck_problem({"leader": "tide_test", "cards": two_legends}) != "")
	var three_factions := good.duplicate()
	three_factions[0] = "crypt_guy"
	three_factions[2] = "club_guy"
	_say("a third faction is refused", _db.deck_problem({"leader": "tide_test", "cards": three_factions}) != "")
	_say("19 cards are refused", _db.deck_problem({"leader": "tide_test", "cards": good.slice(0, 19)}) != "")


func _check_same_seed() -> void:
	var a := _play_out(11)
	var b := _play_out(11)
	_say("the same seed plays out the same (%d events)" % a.size(), a == b and a.size() > 10)


# Every card with keywords or effects has printed text; a whole match of the real starters gives a log line for every
# event kind that needs one (no event left unnamed).
func _check_texts(real: RefCounted) -> void:
	var blank: PackedStringArray = []
	for id: String in real.get("cards"):
		var c: Dictionary = real.card(id)
		if (not (c.get("keywords", []) as Array).is_empty() or not (c.get("effects", []) as Array).is_empty()) and CardText.of(real, c) == "":
			blank.append(id)
	_say("every real card has rules text%s" % ("" if blank.is_empty() else ": " + ", ".join(blank)), blank.is_empty())
	var starters: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/starters.json")) as Dictionary)["starters"]
	var decks: Array = []
	for id: String in starters:
		decks.append({"leader": starters[id]["leader"], "cards": starters[id]["cards"]})
	var m: RefCounted = Match.new(real, decks.slice(0, 2), 11)
	m.mulligan(0, [])
	m.mulligan(1, [1])
	var AiPlayer: GDScript = load("res://core/tcg/ai_player.gd")
	for t in 40:
		if m.get("phase") != "play":
			break
		AiPlayer.take_turn(m, int(m.get("current")))
	var known := {}
	var silent: PackedStringArray = []
	for e: Dictionary in m.take_log():
		if String(e["e"]) == "summon":
			known[int(e["uid"])] = String(e["card"])
		var quiet: bool = (String(e["e"]) == "summon" and bool(e["from_hand"])) or (String(e["e"]) == "draw" and int(e["side"]) != 0) or (String(e["e"]) == "heal" and int(e["amount"]) == 0) or (String(e["e"]) == "buff" and int(e["attack"]) == 0 and int(e["health"]) == 0)
		if not quiet and EventText.line(real, e, 0, known, ["You", "Dealer"]) == "" and not silent.has(String(e["e"])):
			silent.append(String(e["e"]))
	_say("a starter match ends (%s) and every event has a log line%s" % [m.get("phase"), "" if silent.is_empty() else ": no line for " + ", ".join(silent)], silent.is_empty() and m.get("phase") == "over")


# Every real card is played at least once in AI matches of one-of-each decks (each faction's 26 with neutrals), and every
# match ends. A script error in a card's effect shows in the output as SCRIPT ERROR.
func _check_every_card(real: RefCounted) -> void:
	var by_faction := {}
	for id: String in real.get("cards"):
		var c: Dictionary = real.card(id)
		if String(c["rarity"]) != "token":
			if not by_faction.has(String(c["faction"])):
				by_faction[String(c["faction"])] = []
			(by_faction[String(c["faction"])] as Array).append(id)
	var leader_of := {}
	for id: String in real.get("leaders"):
		leader_of[String(real.get("leaders")[id]["faction"])] = id
	var factions: Array = ["tide", "waste", "crypt", "aurelind", "club"]
	var played := {}
	var unfinished := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var AiPlayer: GDScript = load("res://core/tcg/ai_player.gd")
	for round_i in 40:
		var decks: Array = []
		for side in 2:
			var f: String = factions[(round_i + side * 2) % 5]
			var pool: Array = (by_faction[f] as Array) + (by_faction["neutral"] as Array)
			var list: Array = []
			while list.size() < 20:
				var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
				if not list.has(pick):
					list.append(pick)
			decks.append({"leader": leader_of[f], "cards": list})
		var m: RefCounted = Match.new(real, decks, 100 + round_i)
		m.mulligan(0, [])
		m.mulligan(1, [])
		for t in 80:
			if m.get("phase") != "play":
				break
			AiPlayer.take_turn(m, int(m.get("current")))
		if m.get("phase") != "over":
			unfinished += 1
		for e: Dictionary in m.take_log():
			if String(e["e"]) == "play":
				played[String(e["card"])] = true
	var never: PackedStringArray = []
	for f: String in by_faction:
		for id: String in by_faction[f]:
			if not played.has(id):
				never.append(id)
	_say("40 AI matches of mixed one-of decks all end (%d did not)" % unfinished, unfinished == 0)
	_lines.append("info cards never played by the AI in them: %d%s" % [never.size(), "" if never.is_empty() else " (" + ", ".join(never) + ")"])


# The collection (core/tcg/collection.gd): owning, the starter gift, playable decks, the record, save and load.
func _check_collection(real: RefCounted) -> void:
	var Collection: GDScript = load("res://core/tcg/collection.gd")
	var starters: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/starters.json")) as Dictionary)["starters"]
	var c: RefCounted = Collection.new()
	_say("a new collection has no deck to play", (c.call("playable", real) as Dictionary).is_empty())
	c.call("give_starter", "tide", starters["tide"], "standard")
	_say("the starter gift: 20 cards, the leader, 3 packs, a playable deck in slot 1", int(c.call("count", "reef_crab")) == 2 and int(c.call("count", "tide_brute", "*", true)) == 1 and int(c.call("pack_count")) == 3 and (c.call("playable", real) as Dictionary).has(0))
	c.call("add", "harbor_gull", "pony")
	_say("finishes are counted apart and together", int(c.call("count", "harbor_gull", "pony")) == 1 and int(c.call("count", "harbor_gull")) == 3)
	_say("removing more than owned is refused", not bool(c.call("remove", "harbor_gull", "pony", 2)) and bool(c.call("remove", "harbor_gull", "pony", 1)) and int(c.call("count", "harbor_gull")) == 2)
	c.call("remove", "reef_crab", "", 2)
	_say("a deck missing a card is not playable", not (c.call("playable", real) as Dictionary).has(0))
	c.call("record_result", true, "Lottie", "Rising Tide", true, "tide")
	c.call("record_result", true, "Bonk", "Rising Tide", false)
	var r: Dictionary = c.get("record")
	_say("wins against the House Dealer stay apart from the player record", int(r["house"]["wins"]) == 1 and int(r["wins"]) == 1 and int(r["streak"]) == 1 and (r["house"]["decks_won"] as Array).has("tide"))
	var saved: Dictionary = c.call("to_dict")
	(saved["cards"] as Dictionary)["no_such_card"] = {"": 3}
	var back: RefCounted = Collection.new()
	back.call("from_dict", JSON.parse_string(JSON.stringify(saved)), real)
	_say("save and load keep the collection and drop unknown cards", int(back.call("count", "harbor_gull")) == 2 and int(back.call("count", "no_such_card")) == 0 and int(back.call("pack_count")) == 3 and String(back.get("starter")) == "tide" and int((back.get("record") as Dictionary)["house"]["wins"]) == 1)


# The binder list and the deck builder.
func _check_binder(real: RefCounted) -> void:
	var BinderList: GDScript = load("res://core/tcg/binder_list.gd")
	var DeckEdit: GDScript = load("res://core/tcg/deck_edit.gd")
	var Collection: GDScript = load("res://core/tcg/collection.gd")
	var starters: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/starters.json")) as Dictionary)["starters"]
	var c: RefCounted = Collection.new()
	var nums: Dictionary = BinderList.call("numbers", real)
	_say("the binder numbers all 160 cards and leaders (no tokens)", nums.size() == 160 and not nums.has("slimelet"))
	c.call("give_starter", "tide", starters["tide"], "standard")
	c.call("add", "skeleton_archer")
	var owned_list: Array = BinderList.call("entries", real, c, {"show": "owned"})
	var missing: Array = BinderList.call("entries", real, c, {"show": "missing"})
	_say("owned and missing split the set (10 starter cards, its leader, 1 more)", owned_list.size() == 12 and owned_list.size() + missing.size() == 160)
	var newest: Array = BinderList.call("entries", real, c, {"sort": "newest"})
	_say("newest first puts the last card got on top", String(newest[0]["id"]) == "skeleton_archer")
	var leaders_only: Array = BinderList.call("entries", real, c, {"type": "leader"})
	var cheap: Array = BinderList.call("entries", real, c, {"faction": "tide", "cost": 1})
	_say("filters: 10 leaders; a Tide 1-cost card is Tide and costs 1", leaders_only.size() == 10 and not cheap.is_empty() and String(real.card(String(cheap[0]["id"]))["faction"]) == "tide" and int(real.card(String(cheap[0]["id"]))["cost"]) == 1)
	var saved: Dictionary = c.call("to_dict")
	var back: RefCounted = Collection.new()
	back.call("from_dict", JSON.parse_string(JSON.stringify(saved)), real)
	_say("the newest order survives save and load", back.get("got") == c.get("got"))
	var deck := {"name": "Test", "leader": "", "cards": []}
	_say("a leader you do not own cannot lead", String(DeckEdit.call("set_leader", real, c, deck, "warlord")) != "" and String(DeckEdit.call("set_leader", real, c, deck, "tide_brute")) == "")
	DeckEdit.call("add", real, c, deck, "reef_crab")
	DeckEdit.call("add", real, c, deck, "reef_crab")
	_say("no third copy, no card you do not own", String(DeckEdit.call("add", real, c, deck, "reef_crab")) != "" and String(DeckEdit.call("add", real, c, deck, "brawn_buckshot")) != "" and (deck["cards"] as Array).size() == 2)
	for i in 3:
		c.call("add", "brawn_buckshot")
		c.call("add", "field_slime")
	_say("a third faction is refused", String(DeckEdit.call("add", real, c, deck, "brawn_buckshot")) == "" and String(DeckEdit.call("add", real, c, deck, "field_slime")) != "")
	_say("taking a card out", bool(DeckEdit.call("remove", deck, "brawn_buckshot")) and not bool(DeckEdit.call("remove", deck, "brawn_buckshot")))
	var full: Dictionary = (starters["tide"] as Dictionary).duplicate(true)
	var curve: Array = DeckEdit.call("curve", real, full)
	var total := 0
	for n: int in curve:
		total += n
	_say("the starter is ready to play and its curve holds 20 cards", String(DeckEdit.call("problem", real, c, full)) == "" and total == 20)
	_say("a full deck takes no more", String(DeckEdit.call("add", real, c, full, "skeleton_archer")) != "")
	# opening packs (core/tcg/pack_open.gd)
	var PackOpen: GDScript = load("res://core/tcg/pack_open.gd")
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/packs.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var o: RefCounted = Collection.new()
	o.call("add_pack", "standard", 2)
	o.call("add_box", 2, 1, 1)
	var pity_before: Dictionary = (o.get("pity") as Dictionary).duplicate()
	var r1: Dictionary = PackOpen.call("roll", real, o, cfg, rng)
	PackOpen.call("undo", o, r1)
	_say("a pack rolled but never torn changes nothing", o.get("pity") == pity_before and int(o.call("pack_count")) == 4 and String(r1["kind"]) == "standard")
	var got: Array = PackOpen.call("commit", o, PackOpen.call("roll", real, o, cfg, rng))
	var all_new := true
	for card: Dictionary in got:
		all_new = all_new and bool(card["new"]) == (int(o.call("count", String(card["id"]), "*", bool(card["leader"]))) == got.filter(func(x: Dictionary) -> bool: return x["id"] == card["id"]).size())
	_say("a torn pack: one pack less, its cards owned, new ones marked", got.size() >= 5 and int(o.call("pack_count")) == 3 and all_new)
	var rest: Dictionary = PackOpen.call("open_all", real, o, cfg, rng)
	# play mats (core/tcg/mat_book.gd)
	var MatBook: GDScript = load("res://core/tcg/mat_book.gd")
	var mats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/mats.json"))
	var mo: RefCounted = Collection.new()
	_say("everyone has the start mat and uses it", bool(MatBook.call("owns", mo, mats, "beach_felt")) and String(MatBook.call("current", mo, mats)) == "beach_felt" and not bool(MatBook.call("choose", mo, mats, "neon_club")))
	var sure := mats.duplicate(true)
	sure["pack_one_in"] = 1
	var pulled := {}
	for i in 10:
		var m := String(MatBook.call("pull", mo, sure, rng))
		if m != "":
			MatBook.call("give", mo, m)
			pulled[m] = true
	_say("pack pulls give each pack mat once, then none", pulled.size() == 6 and String(MatBook.call("pull", mo, sure, rng)) == "")
	var purse: RefCounted = load("res://core/wallet.gd").new()
	purse.set("balance", 6000)
	_say("a machine mat costs its chips once", String(MatBook.call("buy", mo, mats, purse, "royal_velvet")) == "" and int(purse.get("balance")) == 1000 and String(MatBook.call("buy", mo, mats, purse, "lobster_red")) != "" and String(MatBook.call("buy", mo, mats, purse, "card_sharp")) != "")
	(mo.get("record") as Dictionary)["wins"] = 25
	var earned: Array = MatBook.call("milestones", mo, mats)
	_say("10 and 25 wins give their mats, not the 50", earned.size() == 2 and earned.has("card_sharp") and earned.has("table_boss") and bool(MatBook.call("choose", mo, mats, "table_boss")))
	_say("Open all opens the rest, box packs last", int(rest["packs"]) == 3 and int(o.call("pack_count")) == 0 and String(PackOpen.call("next_kind", o)) == "" and int((o.get("box") as Dictionary)["left"]) == 0)


# Pack rolls (core/tcg/pack_roll.gd): 5 cards with the last rare or better, the odds over many packs, pity, foils,
# leaders, and a box always holding its guaranteed legendaries and epics.
func _check_packs(real: RefCounted) -> void:
	var Collection: GDScript = load("res://core/tcg/collection.gd")
	var Packs: GDScript = load("res://core/tcg/pack_roll.gd")
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/packs.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var c: RefCounted = Collection.new()
	var rare_last := true
	var counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	var leaders := 0
	var foils := 0
	var gap := 0
	var worst_gap := 0
	for i in 3000:
		var pack: Dictionary = Packs.open(real, c, cfg, rng)
		var cards: Array = pack["cards"]
		if not bool(pack["god"]) and (cards.size() != 5 or String(cards[-1]["rarity"]) == "common"):
			rare_last = false
		var leg := false
		for card: Dictionary in cards:
			counts[String(card["rarity"])] = int(counts[String(card["rarity"])]) + 1
			leaders += 1 if bool(card["leader"]) else 0
			foils += 1 if String(card["finish"]) != "" else 0
			leg = leg or String(card["rarity"]) == "legendary"
		gap = 0 if leg else gap + 1
		worst_gap = maxi(worst_gap, gap)
	_say("3000 packs: 5 cards, the last never common", rare_last)
	_lines.append("info 3000 packs: %s, leaders %d, foils %d (%.1f %%), longest run without a legendary %d packs" % [str(counts), leaders, foils, 100.0 * float(foils) / 15000.0, worst_gap])
	_say("pity: never more than %d packs without a legendary" % int(cfg["pity"]["legendary"]), worst_gap < int(cfg["pity"]["legendary"]))
	var ok := true
	for b in 20:
		var box_owner: RefCounted = Collection.new()
		box_owner.call("add_box", 50, 5, 12)
		var leg_n := 0
		var epic_n := 0
		for p in 50:
			for card: Dictionary in (Packs.open(real, box_owner, cfg, rng, "box") as Dictionary)["cards"]:
				leg_n += 1 if String(card["rarity"]) == "legendary" else 0
				epic_n += 1 if String(card["rarity"]) == "epic" else 0
		ok = ok and leg_n >= 5 and epic_n >= 12
	_say("20 boxes of 50 packs each hold at least 5 legendaries and 12 epics", ok)
	var Wallet: GDScript = load("res://core/wallet.gd")
	var Shop: GDScript = load("res://core/tcg/pack_shop.gd")
	var starters: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/starters.json")) as Dictionary)["starters"]
	var w: RefCounted = Wallet.new(15000)
	var buyer: RefCounted = Collection.new()
	var a: String = Shop.buy("box", w, buyer, cfg, starters)
	var b2: String = Shop.buy("bundle_5", w, buyer, cfg, starters)
	var c2: String = Shop.buy("starter:crypt", w, buyer, cfg, starters)
	_say("the machine: a box (12 000) and a 5-bundle (1 400) bought, then a starter refused for want of chips", a == "" and b2 == "" and c2 != "" and int(buyer.call("pack_count")) == 55 and int((buyer.get("box") as Dictionary)["left"]) == 50 and int(w.get("balance")) == 1600)


func _play_out(seed_value: int) -> Array:
	var deck := []
	for i in 10:
		deck.append("dice")
		deck.append("grunt")
	var m: RefCounted = Match.new(_db, [{"leader": "tide_test", "cards": deck}, {"leader": "waste_test", "cards": deck.duplicate()}], seed_value)
	m.mulligan(0, [])
	m.mulligan(1, [])
	for t in 12:
		var side: int = m.get("current")
		for i in range((m.get("sides")[side]["hand"] as Array).size() - 1, -1, -1):
			if m.can_play(side, i):
				m.play(side, i)
		m.end_turn(side)
	return m.take_log()


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1


func _finish() -> void:
	_lines.append("TCG_RULES_CHECK_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/tcg_rules_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()
