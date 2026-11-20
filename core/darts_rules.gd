# Purpose: (polish1 item 71) darts rules, pure: where a dart scores on a standard board (sector order, bulls, treble
# and double rings in millimetres), the two games (501 double-out with busts; Around the Clock 1-20 then the bull),
# turns of three darts (Around the Clock: a double / treble of the number moves on 2 / 3), and the house AI (picks a target the way a player would and throws with a skill scatter).
# Board coordinates: millimetres from the bull's centre, x right, y up.
# Dependencies: data/darts.json (ring sizes, AI skills, stakes) passed in. No nodes, no rendering.
extends RefCounted

const ORDER := [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]  # clockwise from the top

var r_bull := 6.35
var r_outer_bull := 15.9
var r_treble_in := 99.0
var r_treble_out := 107.0
var r_double_in := 162.0
var r_double_out := 170.0

var mode := "501"  # "501" or "clock"
var players := 2
var scores := PackedInt32Array()  # 501: what each player still needs; clock: the number each is on (21 = the bull)
var current := 0  # whose turn
var darts_left := 3
var turn_start := 0  # 501: the score at the start of this turn (a bust goes back to it)
var turn_hits: Array = []  # this turn's hits: {"label", "points"}
var winner := -1
var last_bust := false
var clock_skip := true  # Around the Clock: a double moves on two numbers, a treble three


func _init(data: Dictionary = {}) -> void:
	var b: Dictionary = data.get("board", {})
	r_bull = float(b.get("bull", r_bull))
	r_outer_bull = float(b.get("outer_bull", r_outer_bull))
	r_treble_in = float(b.get("treble_in", r_treble_in))
	r_treble_out = float(b.get("treble_out", r_treble_out))
	r_double_in = float(b.get("double_in", r_double_in))
	r_double_out = float(b.get("double_out", r_double_out))
	clock_skip = bool(data.get("clock_skip", clock_skip))


# What a dart at (x, y) mm scores: {"number" 0-20 or 25, "mult" 0-3, "points", "label"} ("MISS" off the board).
func score_at(p: Vector2) -> Dictionary:
	var r := p.length()
	if r <= r_bull:
		return {"number": 25, "mult": 2, "points": 50, "label": "BULL"}
	if r <= r_outer_bull:
		return {"number": 25, "mult": 1, "points": 25, "label": "25"}
	if r > r_double_out:
		return {"number": 0, "mult": 0, "points": 0, "label": "MISS"}
	var deg := fposmod(rad_to_deg(atan2(p.x, p.y)) + 9.0, 360.0)
	var n: int = ORDER[floori(deg / 18.0) % 20]
	var mult := 1
	if r >= r_double_in:
		mult = 2
	elif r >= r_treble_in and r <= r_treble_out:
		mult = 3
	return {"number": n, "mult": mult, "points": n * mult, "label": ("D%d" % n) if mult == 2 else (("T%d" % n) if mult == 3 else str(n))}


# The middle of a target ("T20", "D16", "S5" (the fat single), "BULL", "25") in board mm.
func target_point(target: String) -> Vector2:
	if target == "BULL":
		return Vector2.ZERO
	if target == "25":
		return Vector2(0, (r_bull + r_outer_bull) * 0.5)
	var n := int(target.substr(1))
	var r := (r_outer_bull + r_treble_in) * 0.5
	if target.begins_with("T"):
		r = (r_treble_in + r_treble_out) * 0.5
	elif target.begins_with("D"):
		r = (r_double_in + r_double_out) * 0.5
	var a := deg_to_rad(float(ORDER.find(n)) * 18.0)
	return Vector2(sin(a), cos(a)) * r


func start(game_mode: String, player_count: int) -> void:
	mode = game_mode
	players = player_count
	scores.resize(players)
	for i in players:
		scores[i] = 501 if mode == "501" else 1
	current = 0
	winner = -1
	_new_turn()


func _new_turn() -> void:
	darts_left = 3
	turn_start = scores[current]
	turn_hits.clear()
	last_bust = false


# One dart of the current player. Returns {"hit" (score_at), "bust", "turn_over", "won"}.
func throw_dart(p: Vector2) -> Dictionary:
	var hit := score_at(p)
	var bust := false
	if winner >= 0:
		return {"hit": hit, "bust": false, "turn_over": true, "won": true}
	darts_left -= 1
	turn_hits.append({"label": hit["label"], "points": hit["points"]})
	if mode == "501":
		var left := scores[current] - int(hit["points"])
		if left < 0 or left == 1 or (left == 0 and int(hit["mult"]) != 2):
			bust = true
			scores[current] = turn_start
		else:
			scores[current] = left
			if left == 0:
				winner = current
	else:
		var on := scores[current]
		if on <= 20 and int(hit["number"]) == on:
			scores[current] = mini(on + (int(hit["mult"]) if clock_skip else 1), 21)  # a double / treble moves on 2 / 3
		elif on == 21 and int(hit["number"]) == 25:
			scores[current] = 22
			winner = current
	last_bust = bust
	var over := bust or darts_left <= 0 or winner >= 0
	return {"hit": hit, "bust": bust, "turn_over": over, "won": winner >= 0}


# After a turn is over (and shown): the next player.
func next_turn() -> void:
	if winner >= 0:
		return
	current = (current + 1) % players
	_new_turn()


# What the current player needs, as words for the board ("501", "On 7", "On the BULL").
func need_text(i: int) -> String:
	if mode == "501":
		return str(scores[i])
	return "On the BULL" if scores[i] >= 21 else ("On %d" % scores[i])


# 501: a finish for this score with the darts left ("T20 T20 BULL"), "" when there is none.
func checkout(left: int, darts: int) -> String:
	if left > 170 or left < 2 or darts <= 0:
		return ""
	var path := _finish(left, darts)
	return " ".join(path)


func _finish(left: int, darts: int) -> PackedStringArray:
	if left == 50:
		return PackedStringArray(["BULL"])
	if left <= 40 and left % 2 == 0:
		return PackedStringArray(["D%d" % (left >> 1)])
	if darts <= 1:
		return PackedStringArray()
	for first: String in _setup_shots():
		var pts := _points(first)
		var rest := left - pts
		if rest >= 2:
			var tail := _finish(rest, darts - 1)
			if not tail.is_empty():
				var out := PackedStringArray([first])
				out.append_array(tail)
				return out
	return PackedStringArray()


static func _setup_shots() -> Array:
	var shots: Array = []
	for n in range(20, 9, -1):
		shots.append("T%d" % n)
	shots.append("25")
	for n in range(20, 0, -1):
		shots.append("S%d" % n)
	return shots


static func _points(target: String) -> int:
	if target == "BULL":
		return 50
	if target == "25":
		return 25
	var n := int(target.substr(1))
	return n * (3 if target.begins_with("T") else (2 if target.begins_with("D") else 1))


# The house AI's target for the current player (it plays like a club player: T20 to score, the checkout when it can).
func ai_target() -> String:
	if mode == "clock":
		var on := scores[current]
		return "BULL" if on >= 21 else "S%d" % on
	var left := scores[current]
	var path := _finish(left, darts_left)
	if not path.is_empty():
		return path[0]
	if left > 60:
		return "T20" if left - 60 != 1 else "T19"
	return "S%d" % clampi(left - 32 if left > 32 else left - 2, 1, 20)


# A throw at `target` with a round scatter of `sigma` mm (normal in x and y).
static func scatter(rng: RandomNumberGenerator, at: Vector2, sigma: float) -> Vector2:
	return at + Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
