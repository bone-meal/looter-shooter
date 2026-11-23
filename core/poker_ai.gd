# Purpose: the house players at the poker table (polish1 item 167): a move for a seat from how strong its hand is
# (pre-flop: a starting-hand score; after the flop: its chance to win against the players still in, found by playing
# the rest of the board out a number of times) set against the price of calling, shaped by the player's style from
# data/poker.json: tight (folds more), aggression (bets and raises more), bluff (bets with nothing now and then), sims.
# Pure (core/poker_rules.gd only); the caller's RandomNumberGenerator.
# Dependencies: core/poker_rules.gd.
extends RefCounted

const Rules = preload("res://core/poker_rules.gd")


static func decide(r: Rules, seat: int, style: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var ok := r.legal(seat)
	if ok.is_empty():
		return {"do": "fold"}
	var tight := float(style.get("tight", 0.5))
	var aggr := float(style.get("aggression", 0.5))
	var bluff := float(style.get("bluff", 0.1))
	var opponents := 0
	for i in r.seats.size():
		if i != seat and r.in_hand(i):
			opponents += 1
	var cards: Array = r.seats[seat]["cards"]
	var eq := _preflop(cards, opponents) if r.board.is_empty() else equity(cards, r.board, opponents, int(style.get("sims", 120)), rng)
	var owe := int(ok["call"])
	var pot := r.pot()
	var price := float(owe) / float(maxi(pot + owe, 1))
	var chips := int(r.seats[seat]["chips"])
	var noise := rng.randf_range(-0.05, 0.05)
	# a raise: strong hands, more often the more aggressive; sized by the pot and the strength
	if bool(ok["can_raise"]) and eq + noise > 0.78 - 0.22 * aggr - 0.05 * float(3 - mini(opponents, 3)):
		var size := int(float(pot) * (0.5 + eq * 0.7)) + int(ok["call"])
		var to := clampi(r.to_call + maxi(size, int(ok["min_to"]) - r.to_call), int(ok["min_to"]), int(ok["max_to"]))
		if eq > 0.9 and rng.randf() < 0.25 + aggr * 0.3:
			to = int(ok["max_to"])
		return {"do": "allin"} if to >= int(ok["max_to"]) else {"do": "raise", "to": to}
	# a bluff: nothing to call and a quiet table now and then
	if owe == 0 and bool(ok["can_raise"]) and rng.randf() < bluff * (0.6 if opponents <= 2 else 0.25):
		var to2 := clampi(r.to_call + maxi(int(float(pot) * 0.55), r.big_blind), int(ok["min_to"]), int(ok["max_to"]))
		return {"do": "allin"} if to2 >= int(ok["max_to"]) else {"do": "raise", "to": to2}
	if owe == 0:
		return {"do": "check"}
	# a call: when the hand is worth the price (tight players want more); a big bet into a short stack is all or nothing
	var need := price + tight * 0.12 + (0.08 if owe * 2 > chips else 0.0)
	if eq + noise >= need:
		return {"do": "call"}
	return {"do": "fold"}


# Chance to win (ties count half) against `opponents` random hands, the rest of the board dealt `sims` times.
static func equity(cards: Array, board: Array, opponents: int, sims: int, rng: RandomNumberGenerator) -> float:
	if opponents <= 0:
		return 1.0
	var used := {}
	for c: int in cards + board:
		used[c] = true
	var rest: Array = []
	for c in 52:
		if not used.has(c):
			rest.append(c)
	var won := 0.0
	for n in sims:
		var pick := rest.duplicate()
		var need := (5 - board.size()) + opponents * 2
		for k in need:  # a partial shuffle: just the cards this deal needs
			var j := rng.randi_range(k, pick.size() - 1)
			var tmp: int = pick[k]
			pick[k] = pick[j]
			pick[j] = tmp
		var full := board.duplicate()
		var at := 0
		while full.size() < 5:
			full.append(pick[at])
			at += 1
		var mine := Rules.score(cards + full)
		var best_other := -1
		for o in opponents:
			var v := Rules.score([pick[at], pick[at + 1]] + full)
			at += 2
			if v > best_other:
				best_other = v
		if mine > best_other:
			won += 1.0
		elif mine == best_other:
			won += 0.5
	return won / float(maxi(sims, 1))


# A starting hand's rough chance against `opponents` (Chen-style points mapped to a share).
static func _preflop(cards: Array, opponents: int) -> float:
	var a: int = cards[0] % 13
	var b: int = cards[1] % 13
	var hi := maxi(a, b)
	var lo := mini(a, b)
	var pts: float = [1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0, 4.5, 5.0, 6.0, 7.0, 8.0, 10.0][hi]
	if a == b:
		pts = maxf(pts * 2.0, 5.0)
	else:
		if floori(cards[0] / 13.0) == floori(cards[1] / 13.0):
			pts += 2.0
		var gap := hi - lo - 1
		pts -= [0.0, 1.0, 2.0, 4.0, 5.0][mini(gap, 4)]
		if gap <= 1 and hi < 10:
			pts += 1.0
	var vs_one := clampf(0.3 + pts * 0.028, 0.3, 0.86)  # ~ AA 0.85, 72o 0.33 heads up
	return clampf(pow(vs_one, 1.0 + 0.55 * float(maxi(opponents - 1, 0))), 0.05, 0.95)
