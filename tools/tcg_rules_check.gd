# Purpose: developer check of the card game's rules engine (core/tcg/match_state.gd + effects.gd + card_db.gd) with a
# small test card set made here: coin toss, hands, mulligan, mana, every keyword, traps, powers, fatigue, burn, deck
# legality, a dice card and determinism. Also checks the real data/tcg files when they exist.
# Log tools/tcg_rules_check.log (TCG_RULES_CHECK_DONE problems=n).
# Dependencies: core/tcg/card_db.gd, core/tcg/match_state.gd.
extends Node

const CardDb = preload("res://core/tcg/card_db.gd")
const Match = preload("res://core/tcg/match_state.gd")

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
