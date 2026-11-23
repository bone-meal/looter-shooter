# Purpose: the house players at the poker table (polish1 item 167): a move for a seat from how strong its hand is
# (pre-flop: its starting hand ranked among all 1326 against how many hands the player plays and raises; after the flop: its chance to win against the players still in, found by playing
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
	if r.board.is_empty():
		return _preflop_move(r, seat, ok, cards, tight, aggr, rng)
	var eq := equity(cards, r.board, opponents, int(style.get("sims", 120)), rng)
	var owe := int(ok["call"])
	var pot := r.pot()
	var price := float(owe) / float(maxi(pot + owe, 1))
	var chips := int(r.seats[seat]["chips"])
	var noise := rng.randf_range(-0.05, 0.05)
	# a raise: strong hands, more often the more aggressive; sized by the pot and the strength
	if bool(ok["can_raise"]) and eq + noise > 0.72 - 0.25 * aggr - 0.05 * float(3 - mini(opponents, 3)):
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
	var need := price + tight * 0.08 - 0.04 + (0.08 if owe * 2 > chips else 0.0)  # a little loose: house players chase draws
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


# Pre-flop by hand rank (the share of the 1326 starting hands as good or better, 0 = aces): a player PLAYS its best
# `vpip` share (looser the less tight), RAISES first in with the best part of that (more the more aggressive), and
# against a raise plays a smaller share the bigger the raise, re-raising with the very best.
static func _preflop_move(r: Rules, seat: int, ok: Dictionary, cards: Array, tight: float, aggr: float, rng: RandomNumberGenerator) -> Dictionary:
	var rank := hand_rank(cards) + rng.randf_range(-0.04, 0.04)
	var vpip := lerpf(0.75, 0.3, tight)
	var bb := r.big_blind
	var owe := int(ok["call"])
	var chips := int(r.seats[seat]["chips"])
	var raised := r.to_call > bb
	var play := vpip
	if raised:
		play = vpip * clampf(6.0 * float(bb) / float(maxi(r.to_call, 1)), 0.15, 1.0)
	if owe * 2 > chips:
		play *= 0.6  # most of the stack: only the better part
	var raise_share := play * ((0.15 + 0.4 * aggr) if not raised else (0.12 + 0.25 * aggr))
	if bool(ok["can_raise"]) and rank <= raise_share:
		var extra := maxi(r.pot() - r.small_blind - bb, 0)  # callers in already make the raise bigger
		var to := 3 * bb + extra if not raised else r.to_call * 3
		to = clampi(to, int(ok["min_to"]), int(ok["max_to"]))
		if to * 3 > int(ok["max_to"]) * 2:  # most of the stack anyway: all in
			to = int(ok["max_to"])
		return {"do": "allin"} if to >= int(ok["max_to"]) else {"do": "raise", "to": to}
	if owe == 0:
		return {"do": "check"}
	if rank <= play:
		return {"do": "call"}
	return {"do": "fold"}


static var _ranks := {}  # starting-hand key -> share of hands as good or better


# The share (0..1) of all starting hands as good as or better than these two cards (0 = the best).
static func hand_rank(cards: Array) -> float:
	if _ranks.is_empty():
		var all: Array = []
		for a in 52:
			for b in range(a + 1, 52):
				all.append([_preflop([a, b], 1), _key([a, b])])
		all.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) > float(y[0]))
		var seen := 0
		var i := 0
		while i < all.size():  # equal scores share the rank of the last of them
			var j := i
			while j < all.size() and float(all[j][0]) == float(all[i][0]):
				j += 1
			seen = j
			for k in range(i, j):
				_ranks[String(all[k][1])] = float(seen) / float(all.size())
			i = j
	return float(_ranks.get(_key(cards), 1.0))


static func _key(cards: Array) -> String:
	var a: int = cards[0] % 13
	var b: int = cards[1] % 13
	var suited := floori(cards[0] / 13.0) == floori(cards[1] / 13.0)
	return "%d_%d_%s" % [maxi(a, b), mini(a, b), "s" if suited else "o"]


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
