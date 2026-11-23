# Purpose: headless checks of the Texas Hold'em rules and the house players (polish1 item 167): hand ranks in order,
# ties and kickers, the wheel, side pots and split pots, chips never made or lost over thousands of hands of house
# players against each other, every hand ends. Run: godot --headless --path . --script res://tools/poker_check.gd
# (prints POKER_CHECK lines and "problems n").
# Dependencies: core/poker_rules.gd, core/poker_ai.gd, core/data_store.gd, data/poker.json.
extends SceneTree

const Rules = preload("res://core/poker_rules.gd")
const Ai = preload("res://core/poker_ai.gd")
const DataStore = preload("res://core/data_store.gd")

var problems := 0


func _init() -> void:
	_ranks()
	_side_pots()
	_play_many()
	print("POKER_CHECK problems %d" % problems)
	quit()


func _c(text: String) -> int:  # "Ah" -> card
	return Rules.RANKS.find(text[0]) + 13 * Rules.SUITS.find(text[1])


func _hand(words: String) -> Array:
	var out: Array = []
	for w in words.split(" "):
		out.append(_c(w))
	return out


func _expect(ok: bool, what: String) -> void:
	if not ok:
		problems += 1
		print("POKER_CHECK PROBLEM: " + what)


func _ranks() -> void:
	var order := ["2c 5d 9h Js Kc 3d 7h", "2c 2d 9h Js Kc 3d 7h", "2c 2d 9h 9s Kc 3d 7h", "2c 2d 2h 9s Kc 3d 7h", "Ac 2d 3h 4s 5c 9d Jh",
		"6c 7d 8h 9s Tc 2d 2h", "2c 5c 9c Jc Kc 3d 7h", "2c 2d 2h 9s 9c 3d 7h", "2c 2d 2h 2s 9c 3d 7h", "5h 6h 7h 8h 9h 2c 2d"]
	var last := -1
	for k in order.size():
		var v := Rules.score(_hand(order[k]))
		_expect(v > last, "rank order at %d (%s) %s" % [k, order[k], Rules.hand_name(v)])
		_expect(Rules.hand_name(v) == Rules.HAND_NAMES[[0, 1, 2, 3, 4, 4, 5, 6, 7, 8][k]], "name %s for %s" % [Rules.hand_name(v), order[k]])
		last = v
	_expect(Rules.score(_hand("Ac Kd 9h 7s 5c 3d 2h")) > Rules.score(_hand("Ac Qd 9h 7s 5c 3d 2h")), "kicker K over Q")
	_expect(Rules.score(_hand("Ac Ad 9h 7s 5c 3d 2h")) == Rules.score(_hand("As Ah 9c 7d 5h 3s 2c")), "same pair same kickers tie")
	_expect(Rules.score(_hand("6c 7d 8h 9s Tc Jd 2h")) > Rules.score(_hand("Ac 2d 3h 4s 5c 9d Jh")), "J-high straight over the wheel")
	_expect(Rules.score(_hand("Kc Kd Kh Qs Qc Qd 2h")) == Rules.score(_hand("Kc Kd Kh Qs Qc 3d 2h")), "two trips = kings full of queens")
	print("POKER_CHECK ranks done")


func _side_pots() -> void:
	# three players all in for 100 / 300 / 500 pre-flop: the short stack can only win the main pot
	var r := Rules.new()
	r.add_seat("a", 100)
	r.add_seat("b", 300)
	r.add_seat("c", 500)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	r.start_hand(rng)
	var guard := 0
	while r.phase != "showdown" and guard < 20:
		guard += 1
		r.act(r.current, {"do": "allin"})
	_expect(r.phase == "showdown", "side pot hand finished")
	var total := 0
	for s: Dictionary in r.seats:
		total += int(s["chips"])
	_expect(total == 900, "side pots keep the chips (%d)" % total)
	var pots: Array = r.result.get("pots", [])
	_expect(pots.size() >= 2, "a main pot and side pots (%d)" % pots.size())
	if pots.size() >= 1:
		_expect(int((pots[0] as Dictionary)["amount"]) == 300, "main pot 3 x 100 (%d)" % int((pots[0] as Dictionary)["amount"]))
	print("POKER_CHECK side pots %s" % str(pots))


func _play_many() -> void:
	var cfg: Dictionary = DataStore.load_json("res://data/poker.json")
	var house: Array = cfg["house"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hands := 0
	var showdowns := 0
	var biggest := 0
	var t0 := Time.get_ticks_msec()
	var think_ms := 0
	var moves := 0
	for game in 30:
		var r := Rules.new()
		r.small_blind = 5
		r.big_blind = 10
		for k in 5:
			r.add_seat(String((house[k % house.size()] as Dictionary)["name"]), 1000)
		var total := 5000
		while r.players_left() >= 2 and r.hand_no < 120:
			if not r.start_hand(rng):
				break
			hands += 1
			var guard := 0
			while r.phase != "showdown" and guard < 200:
				guard += 1
				var who := r.current
				var t := Time.get_ticks_usec()
				var move := Ai.decide(r, who, house[who % house.size()], rng)
				think_ms += Time.get_ticks_usec() - t
				moves += 1
				if not r.act(who, move):
					_expect(false, "the AI made a move the rules refused: %s %s" % [str(move), str(r.legal(who))])
					r.act(who, {"do": "fold"})
			_expect(r.phase == "showdown", "hand %d ended" % r.hand_no)
			if not (r.result.get("shown", {}) as Dictionary).is_empty():
				showdowns += 1
			var now := 0
			for s: Dictionary in r.seats:
				now += int(s["chips"])
				_expect(int(s["chips"]) >= 0, "no negative chips")
			_expect(now == total, "chips kept after hand %d (%d)" % [r.hand_no, now])
			biggest = maxi(biggest, r.pot())
	print("POKER_CHECK %d hands of house players: %d to a showdown, biggest pot %d, %.1f ms a decision, %d ms in all" % [hands, showdowns, biggest, float(think_ms) / 1000.0 / maxf(float(moves), 1.0), Time.get_ticks_msec() - t0])
