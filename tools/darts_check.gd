# Purpose: (polish1 item 71) checks core/darts_rules.gd: every target's centre scores what it says, busts and
# double-out, Around the Clock, checkouts, and how well each house AI plays (3-dart average, darts for a 501 leg).
# Run: godot --headless --path . --script res://tools/darts_check.gd  (prints DARTS_CHECK lines, "problems n").
# Dependencies: core/darts_rules.gd, core/data_store.gd, data/darts.json.
extends SceneTree

const Rules = preload("res://core/darts_rules.gd")
const DataStore = preload("res://core/data_store.gd")

var _problems := 0


func _init() -> void:
	var data: Dictionary = DataStore.load_json("res://data/darts.json")
	var r := Rules.new(data)
	for n: int in Rules.ORDER:
		_expect(int(r.score_at(r.target_point("T%d" % n))["points"]), n * 3, "T%d" % n)
		_expect(int(r.score_at(r.target_point("D%d" % n))["points"]), n * 2, "D%d" % n)
		_expect(int(r.score_at(r.target_point("S%d" % n))["points"]), n, "S%d" % n)
	_expect(int(r.score_at(Vector2.ZERO)["points"]), 50, "bull")
	_expect(int(r.score_at(r.target_point("25"))["points"]), 25, "25")
	_expect(int(r.score_at(Vector2(0, 200))["points"]), 0, "miss")
	r.start("501", 1)
	r.scores[0] = 40
	r.turn_start = 40
	var t := r.throw_dart(r.target_point("S20"))
	_expect(r.scores[0], 20, "40 - S20")
	t = r.throw_dart(r.target_point("T20"))
	_expect(int(t["bust"]), 1, "bust over")
	_expect(r.scores[0], 40, "bust goes back")
	r.next_turn()
	t = r.throw_dart(r.target_point("S20"))
	t = r.throw_dart(r.target_point("S20"))
	_expect(int(t["bust"]), 1, "0 on a single is a bust")
	r.next_turn()
	t = r.throw_dart(r.target_point("D20"))
	_expect(int(t["won"]), 1, "D20 wins on 40")
	_expect_s(r.checkout(170, 3), "T20 T20 BULL", "170")
	_expect_s(r.checkout(169, 3), "", "169")
	_expect_s(r.checkout(32, 1), "D16", "32")
	_expect_s(r.checkout(50, 1), "BULL", "50")
	r.start("clock", 1)
	for n in range(1, 21):
		r.throw_dart(r.target_point("S%d" % n))
		if r.darts_left == 0:
			r.next_turn()
	t = r.throw_dart(Vector2.ZERO)
	_expect(int(t["won"]), 1, "clock done on the bull")
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for ai: Dictionary in data["ai"]:
		var total := 0
		var darts := 0
		var legs := 0
		var leg_darts := 0
		for leg in 40:
			r.start("501", 1)
			var n_darts := 0
			while r.winner < 0 and n_darts < 300:
				var res := r.throw_dart(Rules.scatter(rng, r.target_point(r.ai_target()), float(ai["sigma"])))
				n_darts += 1
				if res["turn_over"]:
					r.next_turn()
			if r.winner >= 0:
				legs += 1
				leg_darts += n_darts
		for i in 600:
			r.start("501", 1)
			total += int(r.score_at(Rules.scatter(rng, r.target_point("T20"), float(ai["sigma"])))["points"])
			darts += 1
		var clock_darts := 0
		for leg in 20:
			r.start("clock", 1)
			var cd := 0
			while r.winner < 0 and cd < 400:
				var res2 := r.throw_dart(Rules.scatter(rng, r.target_point(r.ai_target()), float(ai["sigma"])))
				cd += 1
				if res2["turn_over"]:
					r.next_turn()
			clock_darts += cd
		print("DARTS_CHECK ai %s: 3-dart average at T20 %.1f, 501 leg in %.1f darts (%d of 40 finished), Around the Clock in %.1f darts" % [ai["id"], 3.0 * float(total) / float(darts), float(leg_darts) / maxf(float(legs), 1.0), legs, float(clock_darts) / 20.0])
	print("DARTS_CHECK problems %d" % _problems)
	quit()


func _expect(got: int, want: int, what: String) -> void:
	if got != want:
		_problems += 1
		print("DARTS_CHECK PROBLEM %s: got %d, want %d" % [what, got, want])


func _expect_s(got: String, want: String, what: String) -> void:
	if got != want:
		_problems += 1
		print("DARTS_CHECK PROBLEM %s: got '%s', want '%s'" % [what, got, want])
