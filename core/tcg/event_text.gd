# Purpose: one line of the table's match log per match event (core/tcg/match_state.gd `events`), seen from one side:
# "You play Shell Bash.", "Reef Crab takes 2 damage." ... Events that need no line (summons from the hand, draws by the
# other side's hidden hand detail) give "". Pure.
# Dependencies: core/tcg/card_db.gd (passed in, for card and power names).
extends RefCounted

const HERO := -10


# known = uid -> card id for every creature seen so far (the caller adds each "summon"; dead ones stay findable).
# who = the two sides' names as the viewer sees them, e.g. ["You", "The Dealer"] when the viewer is side 0.
static func line(db: RefCounted, e: Dictionary, me: int, known: Dictionary, who: Array) -> String:
	var text := _line(db, e, me, known, who)
	return text.substr(0, 1).to_upper() + text.substr(1)


static func _line(db: RefCounted, e: Dictionary, me: int, known: Dictionary, who: Array) -> String:
	var side := int(e.get("side", -1))
	var name_of := func(target: int) -> String: return _target(db, target, me, known, who)
	match String(e["e"]):
		"coin":
			return "Coin toss: %s go%s first." % [who[int(e["first"])], "" if int(e["first"]) == me else "es"]
		"mulligan":
			return "%s redraw%s %d card%s." % [who[side], _s(side, me), int(e["count"]), "" if int(e["count"]) == 1 else "s"] if int(e["count"]) > 0 else "%s keep%s the hand." % [who[side], _s(side, me)]
		"turn":
			return "%s turn - %d mana." % ["Your" if side == me else String(who[side]) + "'s", int(e["mana"])]
		"play":
			return "%s play%s %s." % [who[side], _s(side, me), _card(db, String(e["card"]))]
		"summon":
			return "" if bool(e["from_hand"]) else "%s appears for %s." % [_card(db, String(e["card"])), "you" if side == me else who[side]]
		"attack":
			return "%s attacks %s." % [name_of.call(int(e["uid"])), name_of.call(int(e["target"]))]
		"damage":
			return "%s take%s %d damage." % [name_of.call(int(e["target"])), "" if int(e["target"]) == HERO - me else "s", int(e["amount"])]
		"plated":
			return "%s's plating soaks the hit." % name_of.call(int(e["uid"]))
		"heal":
			return "%s heal%s %d." % [name_of.call(int(e["target"])), "" if int(e["target"]) == HERO - me else "s", int(e["amount"])] if int(e["amount"]) > 0 else ""
		"buff":
			return "" if int(e["attack"]) == 0 and int(e["health"]) == 0 else "%s gets +%d/+%d." % [name_of.call(int(e["uid"])), int(e["attack"]), int(e["health"])]
		"keyword":
			return "%s gains %s." % [name_of.call(int(e["uid"])), String((db.get("keywords") as Dictionary).get(String(e["keyword"]), {}).get("name", e["keyword"]))]
		"bounce":
			return "%s goes back to the hand." % name_of.call(int(e["uid"]))
		"death":
			return "%s dies." % name_of.call(int(e["uid"]))
		"power":
			return "%s use%s %s." % [who[side], _s(side, me), String(((db.get("leaders") as Dictionary).get(String(e.get("leader", "")), {}) as Dictionary).get("power", {}).get("name", "the hero power"))]
		"draw":
			return "You draw %s." % _card(db, String(e["card"])) if side == me else ""
		"add":
			return "%s get%s %s." % [who[side], _s(side, me), _card(db, String(e["card"])) if side == me else "a card"]
		"burn":
			return "%s burns - %s hand is full." % [_card(db, String(e["card"])), "your" if side == me else "the"]
		"fatigue":
			return "%s deck is empty: %d damage." % ["Your" if side == me else String(who[side]) + "'s", int(e["amount"])]
		"trap":
			return "%s Tell springs: %s!" % ["Your" if side == me else String(who[side]) + "'s", _card(db, String(e["card"]))]
		"mana":
			return "%s gain%s %d mana." % [who[side], _s(side, me), int(e["amount"])]
		"crystal":
			return "%s now %s %d mana crystals." % [who[side], "have" if side == me else "has", int(e["crystals"])]
		"roll":
			return "%s roll%s a %d." % [who[side], _s(side, me), int(e["value"])]
		"flip":
			return "The coin shows %s." % ("heads" if bool(e["heads"]) else "tails")
		"concede":
			return "%s concede%s." % [who[side], _s(side, me)]
		"over":
			var w := int(e["winner"])
			return "A draw - both leaders fall." if w == 2 else ("You win!" if w == me else "%s win%s." % [who[w], _s(w, me)])
	return ""


static func _target(db: RefCounted, target: int, me: int, known: Dictionary, who: Array) -> String:
	if target <= HERO:
		var side := HERO - target
		return "you" if side == me else String(who[side])
	if known.has(target):
		return _card(db, String(known[target]))
	return "a creature"


static func _card(db: RefCounted, id: String) -> String:
	return String((db.card(id) as Dictionary).get("name", id))


static func _s(side: int, me: int) -> String:
	return "" if side == me else "s"
