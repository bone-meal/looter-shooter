# Purpose: TEXAS HOLD'EM rules (polish1 item 167): seats with chips, the button and blinds, dealing, the four betting
# rounds (pre-flop, flop, turn, river), legal moves (fold / check / call / raise / all-in, no-limit with a minimum
# raise), side pots, showdown with the best five of seven cards, split pots. Pure: no rendering, no randomness of its
# own (the caller's RandomNumberGenerator shuffles). The table screen draws it, the house AI (core/poker_ai.gd) and
# players send moves; online the host runs it and sends what each player may see (view()).
# Cards are ints 0..51: rank = c % 13 (0 = two .. 12 = ace), suit = c / 13 (0 clubs, 1 diamonds, 2 hearts, 3 spades).
# Dependencies: none.
extends RefCounted

const RANKS := "23456789TJQKA"
const SUITS := "cdhs"
const HAND_NAMES := ["High card", "Pair", "Two pair", "Three of a kind", "Straight", "Flush", "Full house", "Four of a kind", "Straight flush"]

var seats: Array = []  # {"name", "chips", "cards": [], "bet": this round, "put": this hand, "folded", "all_in", "out" (no chips / empty), "acted"}
var board: Array = []
var deck: Array = []
var button := -1
var small_blind := 5
var big_blind := 10
var phase := "idle"  # idle, preflop, flop, turn, river, showdown
var current := -1  # who acts now (-1 = nobody)
var to_call := 0  # the highest bet this round
var min_raise := 0  # the smallest raise on top of to_call
var hand_no := 0
var events: Array = []  # what happened since the caller last emptied it: {"kind": ..., ...}
var result: Dictionary = {}  # the last hand's showdown: {"pots": [{"amount", "winners": [seat], "hand": name}], "shown": {seat: score}}


func add_seat(seat_name: String, chips: int) -> int:
	seats.append({"name": seat_name, "chips": chips, "cards": [], "bet": 0, "put": 0, "folded": false, "all_in": false, "out": chips <= 0, "acted": false})
	return seats.size() - 1


func in_hand(i: int) -> bool:
	var s: Dictionary = seats[i]
	return not bool(s["out"]) and not bool(s["folded"])


func players_left() -> int:
	var n := 0
	for i in seats.size():
		if not bool(seats[i]["out"]) and int(seats[i]["chips"]) > 0:
			n += 1
	return n


# Starts a hand: the button moves on, blinds are posted, two cards each. False when fewer than two can play.
func start_hand(rng: RandomNumberGenerator) -> bool:
	for s: Dictionary in seats:
		s["out"] = int(s["chips"]) <= 0
		s["cards"] = []
		s["bet"] = 0
		s["put"] = 0
		s["folded"] = false
		s["all_in"] = false
		s["acted"] = false
	if players_left() < 2:
		phase = "idle"
		return false
	hand_no += 1
	result = {}
	board = []
	deck = range(52)
	for i in range(51, 0, -1):  # Fisher-Yates with the caller's dice
		var j := rng.randi_range(0, i)
		var tmp: int = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	button = _next_seat(button)
	var heads_up := players_left() == 2
	var sb := button if heads_up else _next_seat(button)
	var bb := _next_seat(sb)
	_post(sb, small_blind, "small blind")
	_post(bb, big_blind, "big blind")
	to_call = big_blind
	min_raise = big_blind
	for round_i in 2:
		var i := _next_seat(button)
		for k in seats.size():
			if not bool(seats[i]["out"]):
				(seats[i]["cards"] as Array).append(deck.pop_back())
			i = (i + 1) % seats.size()
	phase = "preflop"
	events.append({"kind": "deal", "button": button, "sb": sb, "bb": bb})
	current = _next_to_act(bb)
	if current < 0:
		_finish_round()
	return true


# What `i` may do now: {"fold", "check", "call": chips to call (0 = none), "min_to": smallest raise-to, "max_to": all-in total}.
func legal(i: int) -> Dictionary:
	if i != current or i < 0:
		return {}
	var s: Dictionary = seats[i]
	var owe := mini(to_call - int(s["bet"]), int(s["chips"]))
	var max_to := int(s["bet"]) + int(s["chips"])
	return {"fold": owe > 0, "check": owe <= 0, "call": maxi(owe, 0), "min_to": mini(to_call + min_raise, max_to), "max_to": max_to, "can_raise": max_to > to_call}


# A move by seat `i`: {"do": "fold" | "check" | "call" | "raise" | "allin", "to": raise-to total for "raise"}. False when
# not allowed (wrong seat, too small a raise ...); the table moves on by itself.
func act(i: int, move: Dictionary) -> bool:
	var ok := legal(i)
	if ok.is_empty():
		return false
	var s: Dictionary = seats[i]
	var what := String(move.get("do", ""))
	match what:
		"fold":
			s["folded"] = true
			events.append({"kind": "fold", "seat": i})
		"check":
			if not bool(ok["check"]):
				return false
			events.append({"kind": "check", "seat": i})
		"call":
			if int(ok["call"]) <= 0:
				return act(i, {"do": "check"})
			_pay(i, int(ok["call"]))
			events.append({"kind": "call", "seat": i, "amount": int(ok["call"])})
		"raise", "allin":
			var target := int(ok["max_to"]) if what == "allin" else int(move.get("to", 0))
			if target > int(ok["max_to"]) or target <= to_call:
				if what == "allin" and target > int(s["bet"]):  # an all-in for less than a call: just a call of what is left
					_pay(i, target - int(s["bet"]))
					events.append({"kind": "call", "seat": i, "amount": target, "all_in": true})
				else:
					return false
			else:
				if target < int(ok["min_to"]) and target < int(ok["max_to"]):
					return false
				var raise_by := target - to_call
				_pay(i, target - int(s["bet"]))
				if raise_by >= min_raise:  # a full raise reopens the betting for everyone
					min_raise = raise_by
					for k in seats.size():
						if k != i:
							seats[k]["acted"] = false
				to_call = maxi(to_call, target)
				events.append({"kind": "raise", "seat": i, "to": target, "all_in": bool(s["all_in"])})
		_:
			return false
	s["acted"] = true
	_advance(i)
	return true


# The hand as one seat may see it (online: the host sends each player only their own cards until the showdown).
func view(for_seat: int) -> Dictionary:
	var out_seats: Array = []
	for i in seats.size():
		var s: Dictionary = seats[i]
		var show := i == for_seat or (phase == "showdown" and in_hand(i) and (result.get("shown", {}) as Dictionary).has(i))
		out_seats.append({"name": s["name"], "chips": s["chips"], "bet": s["bet"], "put": s["put"], "folded": s["folded"], "all_in": s["all_in"], "out": s["out"],
			"cards": (s["cards"] as Array).duplicate() if show else ([-1, -1] if not (s["cards"] as Array).is_empty() else [])})
	return {"seats": out_seats, "board": board.duplicate(), "button": button, "phase": phase, "current": current, "to_call": to_call, "min_raise": min_raise,
		"pot": pot(), "hand_no": hand_no, "sb": small_blind, "bb": big_blind, "result": result.duplicate(true)}


func pot() -> int:
	var total := 0
	for s: Dictionary in seats:
		total += int(s["put"])
	return total


static func card_name(c: int) -> String:
	return RANKS[c % 13] + SUITS[floori(c / 13.0)] if c >= 0 else "??"


# The best five of up to seven cards as one comparable number (bigger wins): category * 15^5 + the ranks that decide.
static func score(cards: Array) -> int:
	var counts := PackedInt32Array()
	counts.resize(13)
	var suits := PackedInt32Array()
	suits.resize(4)
	for c: int in cards:
		counts[c % 13] += 1
		suits[floori(c / 13.0)] += 1
	var flush_suit := -1
	for su in 4:
		if suits[su] >= 5:
			flush_suit = su
	if flush_suit >= 0:
		var fr := PackedInt32Array()
		fr.resize(13)
		for c: int in cards:
			if floori(c / 13.0) == flush_suit:
				fr[c % 13] = 1
		var sf := _straight_top(fr)
		if sf >= 0:
			return _pack(8, [sf])
	var quads := -1
	var trips: Array = []
	var pairs: Array = []
	for r in range(12, -1, -1):
		if counts[r] == 4:
			quads = r
		elif counts[r] == 3:
			trips.append(r)
		elif counts[r] == 2:
			pairs.append(r)
	if quads >= 0:
		return _pack(7, [quads, _high_except(counts, [quads], 1)[0]])
	if trips.size() >= 1 and (trips.size() >= 2 or pairs.size() >= 1):
		var pair_r: int = trips[1] if trips.size() >= 2 and (pairs.is_empty() or int(trips[1]) > int(pairs[0])) else int(pairs[0])
		return _pack(6, [trips[0], pair_r])
	if flush_suit >= 0:
		var top: Array = []
		for r in range(12, -1, -1):
			for c: int in cards:
				if floori(c / 13.0) == flush_suit and c % 13 == r and top.size() < 5:
					top.append(r)
		return _pack(5, top)
	var has := PackedInt32Array()
	has.resize(13)
	for r in 13:
		has[r] = 1 if counts[r] > 0 else 0
	var st := _straight_top(has)
	if st >= 0:
		return _pack(4, [st])
	if trips.size() >= 1:
		return _pack(3, [trips[0]] + _high_except(counts, [trips[0]], 2))
	if pairs.size() >= 2:
		return _pack(2, [pairs[0], pairs[1]] + _high_except(counts, [pairs[0], pairs[1]], 1))
	if pairs.size() == 1:
		return _pack(1, [pairs[0]] + _high_except(counts, [pairs[0]], 3))
	return _pack(0, _high_except(counts, [], 5))


static func hand_name(value: int) -> String:
	return HAND_NAMES[clampi(floori(value / 759375.0), 0, 8)]  # 15^5


static func _pack(category: int, ranks: Array) -> int:
	var v := category
	for k in 5:
		v = v * 15 + (int(ranks[k]) + 1 if k < ranks.size() else 0)
	return v


static func _straight_top(has: PackedInt32Array) -> int:
	for top in range(12, 3, -1):
		if has[top] and has[top - 1] and has[top - 2] and has[top - 3] and has[top - 4]:
			return top
	if has[12] and has[0] and has[1] and has[2] and has[3]:  # the wheel: A-2-3-4-5
		return 3
	return -1


static func _high_except(counts: PackedInt32Array, skip: Array, n: int) -> Array:
	var out: Array = []
	for r in range(12, -1, -1):
		if counts[r] > 0 and not r in skip and out.size() < n:
			out.append(r)
	return out


func _post(i: int, amount: int, why: String) -> void:
	var paid := mini(amount, int(seats[i]["chips"]))
	_pay(i, paid)
	events.append({"kind": "blind", "seat": i, "amount": paid, "what": why})


func _pay(i: int, amount: int) -> void:
	var s: Dictionary = seats[i]
	var paid := mini(amount, int(s["chips"]))
	s["chips"] = int(s["chips"]) - paid
	s["bet"] = int(s["bet"]) + paid
	s["put"] = int(s["put"]) + paid
	if int(s["chips"]) == 0:
		s["all_in"] = true


func _next_seat(from: int) -> int:
	for k in range(1, seats.size() + 1):
		var i := (from + k) % seats.size()
		if not bool(seats[i]["out"]):
			return i
	return -1


# The next seat after `from` that still has a decision this round (in the hand, not all in, owes or has not acted).
func _next_to_act(from: int) -> int:
	var can_act := 0
	for s: Dictionary in seats:
		if not bool(s["out"]) and not bool(s["folded"]) and not bool(s["all_in"]):
			can_act += 1
	for k in range(1, seats.size() + 1):
		var i := (from + k) % seats.size()
		var s: Dictionary = seats[i]
		if bool(s["out"]) or bool(s["folded"]) or bool(s["all_in"]):
			continue
		if not bool(s["acted"]) or int(s["bet"]) < to_call:
			if can_act == 1 and int(s["bet"]) >= to_call:  # the only one who can still bet, nobody to bet against
				return -1
			return i
	return -1


func _advance(last: int) -> void:
	var alive: Array = []
	for i in seats.size():
		if in_hand(i):
			alive.append(i)
	if alive.size() == 1:  # everyone else folded: the pot goes without a showdown
		_award_uncontested(int(alive[0]))
		return
	current = _next_to_act(last)
	if current < 0:
		_finish_round()


func _finish_round() -> void:
	for s: Dictionary in seats:
		s["bet"] = 0
		s["acted"] = false
	to_call = 0
	min_raise = big_blind
	match phase:
		"preflop":
			phase = "flop"
			deck.pop_back()  # the burn card
			for k in 3:
				board.append(deck.pop_back())
		"flop":
			phase = "turn"
			deck.pop_back()
			board.append(deck.pop_back())
		"turn":
			phase = "river"
			deck.pop_back()
			board.append(deck.pop_back())
		"river":
			_showdown()
			return
	events.append({"kind": "street", "phase": phase, "board": board.duplicate()})
	current = _next_to_act(button)
	if current < 0:  # all in (or one left who can bet): the board runs out
		_finish_round()


func _award_uncontested(winner: int) -> void:
	var amount := pot()
	seats[winner]["chips"] = int(seats[winner]["chips"]) + amount
	result = {"pots": [{"amount": amount, "winners": [winner], "hand": ""}], "shown": {}}
	phase = "showdown"
	current = -1
	events.append({"kind": "win", "seat": winner, "amount": amount, "hand": "", "uncontested": true})


# Side pots by how much each put in; each goes to the best hand among those who put that much and did not fold.
func _showdown() -> void:
	phase = "showdown"
	current = -1
	var shown := {}
	for i in seats.size():
		if in_hand(i):
			shown[i] = score((seats[i]["cards"] as Array) + board)
	var levels: Array = []
	for s: Dictionary in seats:
		if int(s["put"]) > 0 and not int(s["put"]) in levels:
			levels.append(int(s["put"]))
	levels.sort()
	var pots: Array = []
	var below := 0
	for level: int in levels:
		var amount := 0
		var eligible: Array = []
		for i in seats.size():
			var put := int(seats[i]["put"])
			amount += clampi(put - below, 0, level - below)
			if put >= level and shown.has(i):
				eligible.append(i)
		below = level
		if amount <= 0:
			continue
		if eligible.is_empty():  # (everyone at this level folded: it joins the pot below)
			if not pots.is_empty():
				(pots.back() as Dictionary)["amount"] = int((pots.back() as Dictionary)["amount"]) + amount
			continue
		var best := -1
		var winners: Array = []
		for i: int in eligible:
			var v := int(shown[i])
			if v > best:
				best = v
				winners = [i]
			elif v == best:
				winners.append(i)
		pots.append({"amount": amount, "winners": winners, "hand": hand_name(best)})
	for p: Dictionary in pots:
		var winners: Array = p["winners"]
		var share := floori(float(p["amount"]) / float(winners.size()))
		var odd := int(p["amount"]) - share * winners.size()
		var order := winners.duplicate()
		order.sort_custom(func(a: int, b: int) -> bool: return (a - button + seats.size()) % seats.size() < (b - button + seats.size()) % seats.size())
		for w: int in order:
			var extra := 1 if odd > 0 else 0
			odd -= extra
			seats[w]["chips"] = int(seats[w]["chips"]) + share + extra
			events.append({"kind": "win", "seat": w, "amount": share + extra, "hand": p["hand"]})
	result = {"pots": pots, "shown": shown}
