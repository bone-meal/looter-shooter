# Purpose: one match of "You got me Lobster?" (rules locked in diary/DECISIONS_TCG.md): two leaders, decks, hands, mana
# 1 -> 8, creatures on the mat, combat (attacker picks the target), the 12 keywords, traps, hero powers, fatigue, the
# coin toss and mulligan, and a log of everything that happened for the table to animate. Every move is an intent that
# is checked here and refused with a reason; randomness comes only from the seeded generator, so the host's match is the
# match. Pure: no nodes, no rendering, no clock (the table enforces the turn timer by ending the turn).
# Dependencies: core/tcg/card_db.gd (passed in), core/tcg/effects.gd.
extends RefCounted

const Effects = preload("res://core/tcg/effects.gd")
const HERO := -10  # target codes: a creature's uid (1, 2, ...), or HERO - side for a leader (-10 = side 0, -11 = side 1)

var db: RefCounted
var rules: Dictionary
var rng := RandomNumberGenerator.new()
var sides: Array = []  # two dictionaries: leader, hp, max_hp, crystals, mana, deck, hand, board, traps, fatigue, power_used, mulligans
var current := 0  # whose turn
var turn := 0  # turns played so far (both sides)
var phase := "mulligan"  # "mulligan", "play", "over"
var winner := -1  # 0 / 1, or 2 = both leaders fell together
var events: Array = []  # what happened, for the table (see _event): read and clear it with take_log()
var _next_uid := 1


# decks = [{"leader": id, "cards": [ids]}, {...}]; first = -1: a coin toss decides.
func _init(card_db: RefCounted, decks: Array, seed_value: int, first := -1) -> void:
	db = card_db
	rules = card_db.get("rules")
	rng.seed = seed_value
	for i in 2:
		var deck: Dictionary = decks[i]
		var leader: Dictionary = db.get("leaders")[String(deck["leader"])]
		var cards: Array = (deck["cards"] as Array).duplicate()
		_shuffle(cards)
		var hp := int(leader.get("health", rules["hero_health"]))
		sides.append({"leader": String(deck["leader"]), "hp": hp, "max_hp": hp, "crystals": 0, "mana": 0, "deck": cards,
			"hand": [], "board": [], "traps": [], "fatigue": 0, "power_used": false, "mulligans": int(rules["mulligans"]), "ready": false})
	current = first if first >= 0 else rng.randi_range(0, 1)
	_event({"e": "coin", "first": current})
	for i in int(rules["first_hand"]):
		_draw(current)
	for i in int(rules["second_hand"]):
		_draw(1 - current)
	_give(1 - current, String(rules["lucky_card"]))


# ---- intents (each returns "" or why it is refused) ----

# Redraw the cards at these hand positions once (empty = keep the hand). When both are ready the first turn starts.
func mulligan(side: int, indices: Array) -> String:
	if phase != "mulligan" or bool(sides[side]["ready"]):
		return "not now"
	var s: Dictionary = sides[side]
	var hand: Array = s["hand"]
	var picked: Array = []
	for i: Variant in indices:
		if int(i) < 0 or int(i) >= hand.size() or picked.has(int(i)) or String(hand[int(i)]) == String(rules["lucky_card"]):
			return "bad card"
		picked.append(int(i))
	picked.sort()
	picked.reverse()
	for i: int in picked:
		(s["deck"] as Array).append(hand[i])
		hand.remove_at(i)
	_shuffle(s["deck"])
	for i in picked.size():
		_draw(side)
	s["ready"] = true
	_event({"e": "mulligan", "side": side, "count": picked.size()})
	if bool(sides[0]["ready"]) and bool(sides[1]["ready"]):
		phase = "play"
		_start_turn()
	return ""


# Play the card at hand position `index`; `target` for cards that pick; `slot` = where on the row (-1 = right end).
func play(side: int, index: int, target := -1, slot := -1) -> String:
	var why := _my_turn(side)
	if why != "":
		return why
	var s: Dictionary = sides[side]
	if index < 0 or index >= (s["hand"] as Array).size():
		return "no such card"
	var id := String(s["hand"][index])
	var c: Dictionary = db.card(id)
	if int(c["cost"]) > int(s["mana"]):
		return "not enough mana"
	var pick: String = db.pick_of(c.get("effects", []))
	var choices := targets_for(side, pick) if pick != "" else []
	if pick != "" and String(c["type"]) == "spell" and choices.is_empty():
		return "nothing to target"
	if pick != "" and not choices.is_empty() and not choices.has(target):
		return "pick a target"
	match String(c["type"]):
		"creature":
			if (s["board"] as Array).size() >= int(rules["board_max"]):
				return "your side is full"
		"trap":
			if (s["traps"] as Array).size() >= int(rules["max_traps"]):
				return "too many traps set"
	(s["hand"] as Array).remove_at(index)
	s["mana"] = int(s["mana"]) - int(c["cost"])
	_event({"e": "play", "side": side, "card": id, "type": c["type"]})
	match String(c["type"]):
		"creature":
			var uid := summon(side, id, slot, true)
			_spring_traps(1 - side, "enemy_creature", uid)
			if find(uid).is_empty():
				return ""
			Effects.run(self, side, c.get("effects", []), "arrival", uid, target)
		"spell":
			_spring_traps(1 - side, "enemy_spell", -1)
			Effects.run(self, side, c.get("effects", []), "cast", -1, target, true)
			_trigger_board(side, "spell_cast", -1)
		"trap":
			(s["traps"] as Array).append(id)
	settle()
	return ""


# A creature attacks a creature or the enemy leader.
func attack(side: int, attacker_uid: int, target: int) -> String:
	var why := _my_turn(side)
	if why != "":
		return why
	if not attack_targets(side, attacker_uid).has(target):
		return "cannot attack that"
	var a := find(attacker_uid)
	a["attacks"] = int(a["attacks"]) - 1
	_kw_off(a, "hidden")
	_event({"e": "attack", "side": side, "uid": attacker_uid, "target": target})
	_spring_traps(1 - side, "enemy_attack", attacker_uid)
	if find(attacker_uid).is_empty() or hp_of(target) <= 0:
		settle()
		return ""
	Effects.run(self, side, db.card(String(a["card"])).get("effects", []), "attack", attacker_uid, target)
	if find(attacker_uid).is_empty():
		settle()
		return ""
	var back := 0
	if target >= 0:
		back = int(find(target).get("atk", 0))
	damage(target, int(a["atk"]), attacker_uid)
	if target >= 0 and back > 0:
		damage(attacker_uid, back, target)
	settle()
	return ""


# The leader's hero power (once a turn).
func power(side: int, target := -1) -> String:
	var why := _my_turn(side)
	if why != "":
		return why
	var s: Dictionary = sides[side]
	if bool(s["power_used"]):
		return "already used this turn"
	if int(s["mana"]) < int(rules["power_cost"]):
		return "not enough mana"
	var effects: Array = power_of(side).get("effects", [])
	var pick: String = db.pick_of(effects)
	if pick != "" and not targets_for(side, pick).has(target):
		return "pick a target"
	s["mana"] = int(s["mana"]) - int(rules["power_cost"])
	s["power_used"] = true
	_event({"e": "power", "side": side})
	Effects.run(self, side, effects, "power", -1, target)
	settle()
	return ""


func end_turn(side: int) -> String:
	var why := _my_turn(side)
	if why != "":
		return why
	for c: Dictionary in (sides[side]["board"] as Array).duplicate():
		if not find(int(c["uid"])).is_empty():
			Effects.run(self, side, db.card(String(c["card"])).get("effects", []), "turn_end", int(c["uid"]), -1)
	settle()
	if phase == "over":
		return ""
	current = 1 - current
	_start_turn()
	return ""


# Giving up (Esc twice at the table, walking away, a dropped connection).
func concede(side: int) -> void:
	if phase == "over":
		return
	sides[side]["hp"] = 0
	_event({"e": "concede", "side": side})
	_finish()


# ---- what may be done (for the table, the AI and the checks) ----

func power_of(side: int) -> Dictionary:
	return (db.get("leaders")[String(sides[side]["leader"])] as Dictionary).get("power", {})


func can_play(side: int, index: int) -> bool:
	if phase != "play" or side != current:
		return false
	var s: Dictionary = sides[side]
	var c: Dictionary = db.card(String(s["hand"][index]))
	if int(c["cost"]) > int(s["mana"]):
		return false
	if String(c["type"]) == "creature" and (s["board"] as Array).size() >= int(rules["board_max"]):
		return false
	if String(c["type"]) == "trap" and (s["traps"] as Array).size() >= int(rules["max_traps"]):
		return false
	var pick: String = db.pick_of(c.get("effects", []))
	return not (String(c["type"]) == "spell" and pick != "" and targets_for(side, pick).is_empty())


# Target codes a pick allows for `side` (enemies that are Hidden cannot be picked).
func targets_for(side: int, pick: String) -> Array:
	var out: Array = []
	var foe := 1 - side
	if pick in ["pick_any", "pick_enemy"]:
		out.append(HERO - foe)
	if pick == "pick_any":
		out.append(HERO - side)
	for c: Dictionary in sides[foe]["board"]:
		if pick in ["pick_any", "pick_creature", "pick_enemy", "pick_enemy_creature"] and not _has(c, "hidden"):
			out.append(int(c["uid"]))
	for c: Dictionary in sides[side]["board"]:
		if pick in ["pick_any", "pick_creature", "pick_friendly_creature"]:
			out.append(int(c["uid"]))
	return out


# Where this creature may attack now (empty = it cannot).
func attack_targets(side: int, uid: int) -> Array:
	if phase != "play" or side != current:
		return []
	var a := find(uid)
	if a.is_empty() or int(a["side"]) != side or int(a["atk"]) <= 0 or int(a["attacks"]) <= 0:
		return []
	var fresh := int(a["born"]) == turn
	if fresh and not _has(a, "rush") and not _has(a, "charge"):
		return []
	var foe := 1 - side
	var guards: Array = []
	var open: Array = []
	for c: Dictionary in sides[foe]["board"]:
		if _has(c, "hidden"):
			continue
		open.append(int(c["uid"]))
		if _has(c, "guard"):
			guards.append(int(c["uid"]))
	if not guards.is_empty():
		return guards
	if not (fresh and _has(a, "rush") and not _has(a, "charge")):
		open.append(HERO - foe)
	return open


func find(uid: int) -> Dictionary:
	for s: Dictionary in sides:
		for c: Dictionary in s["board"]:
			if int(c["uid"]) == uid:
				return c
	return {}


func hp_of(target: int) -> int:
	if target <= HERO:
		return int(sides[HERO - target]["hp"])
	return int(find(target).get("hp", 0))


func empower(side: int) -> int:
	var n := 0
	for c: Dictionary in sides[side]["board"]:
		n += int(db.card(String(c["card"])).get("empower", 0)) if _has(c, "empower") else 0
	return n


# The events since the last call (and forgets them).
func take_log() -> Array:
	var out := events
	events = []
	return out


# ---- the pieces effects and combat use ----

# Puts a creature on `side`'s row and returns its uid (-1 when the row is full).
func summon(side: int, id: String, slot := -1, from_hand := false) -> int:
	var board: Array = sides[side]["board"]
	if board.size() >= int(rules["board_max"]):
		return -1
	var c: Dictionary = db.card(id)
	var kw := {}
	for k: Variant in c.get("keywords", []):
		kw[String(k)] = true
	var creature := {"uid": _next_uid, "card": id, "side": side, "atk": int(c["attack"]), "hp": int(c["health"]),
		"max_hp": int(c["health"]), "kw": kw, "attacks": 0, "born": turn, "doomed": false}
	if kw.has("rush") or kw.has("charge"):
		creature["attacks"] = 2 if kw.has("twin_strike") else 1
	_next_uid += 1
	if slot < 0 or slot > board.size():
		board.append(creature)
	else:
		board.insert(slot, creature)
	_event({"e": "summon", "side": side, "uid": creature["uid"], "card": id, "slot": board.find(creature), "from_hand": from_hand})
	return int(creature["uid"])


# Damage to a creature or a leader from `source` (a uid, or -1 = a spell / power / fatigue).
func damage(target: int, amount: int, source := -1) -> void:
	if amount <= 0:
		return
	var src := find(source) if source >= 0 else {}
	if target <= HERO:
		var s: Dictionary = sides[HERO - target]
		s["hp"] = int(s["hp"]) - amount
		_event({"e": "damage", "target": target, "amount": amount, "source": source})
	else:
		var c := find(target)
		if c.is_empty():
			return
		if _has(c, "plated"):
			_kw_off(c, "plated")
			_event({"e": "plated", "uid": target})
			return
		c["hp"] = int(c["hp"]) - amount
		_event({"e": "damage", "target": target, "amount": amount, "source": source})
		if not src.is_empty() and _has(src, "venom"):
			c["doomed"] = true
	if not src.is_empty() and _has(src, "drain"):
		heal(HERO - int(src["side"]), amount)


func heal(target: int, amount: int) -> void:
	if target <= HERO:
		var s: Dictionary = sides[HERO - target]
		var before := int(s["hp"])
		s["hp"] = mini(int(s["max_hp"]), before + amount)
		if int(s["hp"]) > before:
			_event({"e": "heal", "target": target, "amount": int(s["hp"]) - before})
		return
	var c := find(target)
	if not c.is_empty():
		var was := int(c["hp"])
		c["hp"] = mini(int(c["max_hp"]), was + amount)
		if int(c["hp"]) > was:
			_event({"e": "heal", "target": target, "amount": int(c["hp"]) - was})


func buff(uid: int, add_attack: int, add_health: int) -> void:
	var c := find(uid)
	if c.is_empty():
		return
	c["atk"] = maxi(int(c["atk"]) + add_attack, 0)
	c["max_hp"] = int(c["max_hp"]) + add_health
	c["hp"] = int(c["hp"]) + add_health
	_event({"e": "buff", "uid": uid, "attack": add_attack, "health": add_health})


func give_keyword(uid: int, kw: String) -> void:
	var c := find(uid)
	if c.is_empty():
		return
	(c["kw"] as Dictionary)[kw] = true
	if kw == "twin_strike" and int(c["attacks"]) == 1:
		c["attacks"] = 2
	if kw in ["rush", "charge"] and int(c["born"]) == turn and int(c["attacks"]) == 0:
		c["attacks"] = 2 if _has(c, "twin_strike") else 1
	_event({"e": "keyword", "uid": uid, "keyword": kw})


func destroy(uid: int) -> void:
	var c := find(uid)
	if not c.is_empty():
		c["doomed"] = true


# A creature goes back to its owner's hand (burns when the hand is full).
func bounce(uid: int) -> void:
	var c := find(uid)
	if c.is_empty():
		return
	(sides[int(c["side"])]["board"] as Array).erase(c)
	_event({"e": "bounce", "uid": uid})
	_give(int(c["side"]), String(c["card"]))


func draw(side: int, count := 1) -> void:
	for i in count:
		_draw(side)


func add_card(side: int, id: String) -> void:
	_give(side, id)


func gain_mana(side: int, amount: int) -> void:
	sides[side]["mana"] = int(sides[side]["mana"]) + amount
	_event({"e": "mana", "side": side, "amount": amount})


func gain_crystal(side: int, amount: int) -> void:
	var s: Dictionary = sides[side]
	s["crystals"] = clampi(int(s["crystals"]) + amount, 0, int(rules["mana_max"]))
	_event({"e": "crystal", "side": side, "crystals": s["crystals"]})


# Removes the dead (Last Gasps may kill more), then ends the match if a leader fell.
func settle() -> void:
	var guard := 0
	while guard < 50:
		guard += 1
		var dead: Array = []
		for s: Dictionary in sides:
			for c: Dictionary in s["board"]:
				if int(c["hp"]) <= 0 or bool(c["doomed"]):
					dead.append(c)
		if dead.is_empty():
			break
		for c: Dictionary in dead:
			(sides[int(c["side"])]["board"] as Array).erase(c)
			_event({"e": "death", "uid": c["uid"], "card": c["card"], "side": c["side"]})
		for c: Dictionary in dead:
			Effects.run(self, int(c["side"]), db.card(String(c["card"])).get("effects", []), "last_gasp", -1, -1)
			_trigger_board(int(c["side"]), "friendly_death", int(c["uid"]))
	if int(sides[0]["hp"]) <= 0 or int(sides[1]["hp"]) <= 0:
		_finish()


func log_event(e: Dictionary) -> void:
	_event(e)


# ---- inside ----

func _start_turn() -> void:
	turn += 1
	var s: Dictionary = sides[current]
	s["crystals"] = mini(int(s["crystals"]) + 1, int(rules["mana_max"]))
	s["mana"] = int(s["crystals"])
	s["power_used"] = false
	_event({"e": "turn", "side": current, "turn": turn, "mana": s["mana"]})
	for c: Dictionary in s["board"]:
		c["attacks"] = 2 if _has(c, "twin_strike") else 1
		if _has(c, "wind_up"):
			buff(int(c["uid"]), 1, 1)
	for c: Dictionary in (s["board"] as Array).duplicate():
		if not find(int(c["uid"])).is_empty():
			Effects.run(self, current, db.card(String(c["card"])).get("effects", []), "turn_start", int(c["uid"]), -1)
	settle()
	if phase == "over":
		return
	_draw(current)
	settle()


func _my_turn(side: int) -> String:
	if phase == "over":
		return "the match is over"
	if phase != "play":
		return "the match has not started"
	if side != current:
		return "not your turn"
	return ""


func _draw(side: int) -> void:
	var s: Dictionary = sides[side]
	var deck: Array = s["deck"]
	if deck.is_empty():
		s["fatigue"] = int(s["fatigue"]) + 1
		var hurt := int(rules["fatigue_start"]) + int(s["fatigue"]) - 1
		_event({"e": "fatigue", "side": side, "amount": hurt})
		damage(HERO - side, hurt)
		return
	var id := String(deck.pop_back())
	_give(side, id, true)


func _give(side: int, id: String, drawn := false) -> void:
	var hand: Array = sides[side]["hand"]
	if hand.size() >= int(rules["hand_max"]):
		_event({"e": "burn", "side": side, "card": id})
		return
	hand.append(id)
	_event({"e": "draw" if drawn else "add", "side": side, "card": id})


# The first trap of `side` that answers `when` fires (and is used up).
func _spring_traps(side: int, when: String, uid: int) -> void:
	var traps: Array = sides[side]["traps"]
	for i in traps.size():
		var effects: Array = db.card(String(traps[i])).get("effects", [])
		if effects.any(func(e: Dictionary) -> bool: return String(e["when"]) == when):
			var id := String(traps[i])
			traps.remove_at(i)
			_event({"e": "trap", "side": side, "card": id})
			Effects.run(self, side, effects, when, -1, uid)
			settle()
			return


func _trigger_board(side: int, when: String, other: int) -> void:
	for c: Dictionary in (sides[side]["board"] as Array).duplicate():
		if int(c["uid"]) != other and not find(int(c["uid"])).is_empty():
			Effects.run(self, side, db.card(String(c["card"])).get("effects", []), when, int(c["uid"]), -1)


func _finish() -> void:
	if phase == "over":
		return
	phase = "over"
	var down0 := int(sides[0]["hp"]) <= 0
	var down1 := int(sides[1]["hp"]) <= 0
	winner = 2 if down0 and down1 else (1 if down0 else 0)
	_event({"e": "over", "winner": winner})


func _has(c: Dictionary, kw: String) -> bool:
	return (c["kw"] as Dictionary).has(kw)


func _kw_off(c: Dictionary, kw: String) -> void:
	(c["kw"] as Dictionary).erase(kw)


func _shuffle(list: Array) -> void:
	for i in range(list.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = list[i]
		list[i] = list[j]
		list[j] = t


func _event(e: Dictionary) -> void:
	events.append(e)
