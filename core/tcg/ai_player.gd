# Purpose: the card game's computer opponent (the House Dealer, and both sides of the simulator): picks the next move
# for a side from the match state. One plain difficulty (locked): redraw expensive openers, spend mana on the dearest
# cards it can play, aim removal at what it can kill, trade when the trade is good, go for the leader when it can win
# or nothing better is on, use the hero power with spare mana. Pure.
# Dependencies: core/tcg/match_state.gd (the match is handed in).
extends RefCounted


# Hand positions to send back at the start (cards costing 4 or more, never the Lucky Chip).
static func mulligan(m: RefCounted, side: int) -> Array:
	var out: Array = []
	var hand: Array = m.get("sides")[side]["hand"]
	for i in hand.size():
		var c: Dictionary = m.get("db").card(String(hand[i]))
		if int(c["cost"]) >= 4 and String(hand[i]) != String(m.get("rules")["lucky_card"]):
			out.append(i)
	return out


# The next move: {"do": "play", "index", "target"} / {"do": "attack", "uid", "target"} / {"do": "power", "target"} /
# {"do": "end"}.
static func next_move(m: RefCounted, side: int) -> Dictionary:
	var play := _best_play(m, side)
	if not play.is_empty():
		return play
	var hit := _best_attack(m, side)
	if not hit.is_empty():
		return hit
	var power := _power(m, side)
	if not power.is_empty():
		return power
	return {"do": "end"}


# Runs moves until the turn ends (the simulator; the table steps next_move itself with pauses).
static func take_turn(m: RefCounted, side: int) -> void:
	for i in 60:
		if m.get("phase") != "play" or int(m.get("current")) != side:
			return
		var move := next_move(m, side)
		var why := do_move(m, side, move)
		if String(move["do"]) == "end":
			return
		if why != "":  # a move it thought legal was refused: end rather than loop
			m.end_turn(side)
			return
	m.end_turn(side)


static func do_move(m: RefCounted, side: int, move: Dictionary) -> String:
	match String(move["do"]):
		"play":
			return m.play(side, int(move["index"]), int(move.get("target", -1)))
		"attack":
			return m.attack(side, int(move["uid"]), int(move["target"]))
		"power":
			return m.power(side, int(move.get("target", -1)))
	return m.end_turn(side)


static func _best_play(m: RefCounted, side: int) -> Dictionary:
	var s: Dictionary = m.get("sides")[side]
	var hand: Array = s["hand"]
	var db: RefCounted = m.get("db")
	var lucky := String(m.get("rules")["lucky_card"])
	var best := -1
	var best_cost := -1
	var best_target := -1
	for i in hand.size():
		if String(hand[i]) == lucky or not m.can_play(side, i):
			continue
		var c: Dictionary = db.card(String(hand[i]))
		var target := _target_for(m, side, c.get("effects", []))
		if target == -2:  # it would only hurt us or waste itself
			continue
		if int(c["cost"]) > best_cost:
			best = i
			best_cost = int(c["cost"])
			best_target = target
	if best >= 0:
		return {"do": "play", "index": best, "target": best_target}
	var chip := hand.find(lucky)
	if chip >= 0:  # the chip only when one more mana lets a card come down
		for i in hand.size():
			var c: Dictionary = db.card(String(hand[i]))
			if i != chip and int(c["cost"]) == int(s["mana"]) + 1:
				return {"do": "play", "index": chip, "target": -1}
	return {}


# The target a card's pick wants (-1 = none needed, -2 = no sensible target).
static func _target_for(m: RefCounted, side: int, effects: Array) -> int:
	var db: RefCounted = m.get("db")
	var pick: String = db.pick_of(effects)
	if pick == "":
		return -1
	var choices: Array = m.targets_for(side, pick)
	if choices.is_empty():
		return -1  # a creature still comes down; a spell is not playable (can_play said so)
	var effect := {}
	for e: Dictionary in effects:
		if String(e.get("to", "")) == pick:
			effect = e
			break
	var hero: int = m.HERO
	match String(effect.get("do", "")):
		"damage", "destroy", "bounce":
			var amount: int = int(effect.get("amount", 999)) + (int(m.empower(side)) if String(effect.get("when", "")) == "cast" else 0)
			if String(effect["do"]) != "damage":
				amount = 999
			var best := -2
			var best_value := -1
			for t: int in choices:
				if t <= hero or int(m.find(t).get("side", side)) == side:
					continue
				var c: Dictionary = m.find(t)
				var value := int(c["atk"]) + int(c["hp"])
				if int(c["hp"]) <= amount and value > best_value:
					best = t
					best_value = value
			if best == -2 and choices.has(hero - (1 - side)) and String(effect["do"]) == "damage":
				return hero - (1 - side)
			return best
		"heal", "buff", "give":
			var best := -2
			var best_atk := -1
			for t: int in choices:
				if t >= 0 and int(m.find(t)["side"]) == side and int(m.find(t)["atk"]) > best_atk:
					best = t
					best_atk = int(m.find(t)["atk"])
			if best == -2 and String(effect["do"]) == "heal" and choices.has(hero - side):
				return hero - side
			return best
	return choices[0]


static func _best_attack(m: RefCounted, side: int) -> Dictionary:
	var foe := 1 - side
	var hero: int = m.HERO
	var board: Array = m.get("sides")[side]["board"]
	var enemy_hp := int(m.get("sides")[foe]["hp"])
	var face_damage := 0
	for c: Dictionary in board:
		if m.attack_targets(side, int(c["uid"])).has(hero - foe):
			face_damage += int(c["atk"]) * int(c["attacks"])
	var breaker := _break_guard(m, side)
	if not breaker.is_empty():
		return breaker
	for c: Dictionary in board:
		var uid := int(c["uid"])
		var targets: Array = m.attack_targets(side, uid)
		if targets.is_empty():
			continue
		if face_damage >= enemy_hp and targets.has(hero - foe):  # lethal: all in
			return {"do": "attack", "uid": uid, "target": hero - foe}
		var best := -1
		var best_score := 0
		for t: int in targets:
			if t <= hero:
				continue
			var e: Dictionary = m.find(t)
			var kills := int(c["atk"]) >= int(e["hp"])
			var lives := int(e["atk"]) < int(c["hp"])
			var score := 0
			if kills and lives:
				score = 10 + int(e["atk"]) + int(e["hp"])
			elif kills and int(e["atk"]) + int(e["hp"]) > int(c["atk"]) + int(c["hp"]):
				score = 5 + int(e["atk"]) + int(e["hp"]) - int(c["atk"]) - int(c["hp"])
			if score > best_score:
				best = t
				best_score = score
		if best >= 0:
			return {"do": "attack", "uid": uid, "target": best}
		if targets.has(hero - foe):
			return {"do": "attack", "uid": uid, "target": hero - foe}
		if targets.size() > 0 and (targets[0] as int) >= 0 and int(m.find(targets[0])["hp"]) <= int(c["atk"]):  # a Guard in the way it can break
			return {"do": "attack", "uid": uid, "target": targets[0]}
	return {}


static func _power(m: RefCounted, side: int) -> Dictionary:
	var s: Dictionary = m.get("sides")[side]
	if bool(s["power_used"]) or int(s["mana"]) < int(m.get("rules")["power_cost"]):
		return {}
	var effects: Array = m.power_of(side).get("effects", [])
	var target := _target_for(m, side, effects)
	if target == -2:
		return {}
	if m.get("db").pick_of(effects) != "" and target == -1:
		return {}
	return {"do": "power", "target": target}


# Guards in the way: if everyone who can attack together can kill the weakest Guard, send the one that suits best
# (kills it and lives, else lives through its hit, else the strongest).
static func _break_guard(m: RefCounted, side: int) -> Dictionary:
	var hero: int = m.HERO
	var guard := {}
	for c: Dictionary in m.get("sides")[1 - side]["board"]:
		if (c["kw"] as Dictionary).has("guard") and not (c["kw"] as Dictionary).has("hidden") and (guard.is_empty() or int(c["hp"]) < int(guard["hp"])):
			guard = c
	if guard.is_empty():
		return {}
	var gid := int(guard["uid"])
	var able: Array = []
	var total := 0
	for c: Dictionary in m.get("sides")[side]["board"]:
		if m.attack_targets(side, int(c["uid"])).has(gid):
			able.append(c)
			total += int(c["atk"])
	if able.is_empty() or total < int(guard["hp"]):
		return {}
	var pick := {}
	var rank := -1
	for c: Dictionary in able:
		var kills := int(c["atk"]) >= int(guard["hp"])
		var lives := int(guard["atk"]) < int(c["hp"])
		var r := (4 if kills and lives else (3 if kills else (2 if lives else 1))) * 100 + int(c["atk"])
		if r > rank:
			rank = r
			pick = c
	return {"do": "attack", "uid": int(pick["uid"]), "target": gid} if hero != gid else {}

