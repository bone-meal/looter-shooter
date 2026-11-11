# Purpose: slot machine rules: 3 reels x 3 rows, 5 paylines, wilds, progressive jackpot. Pure functions over data/slots.json; no rendering.
# Dependencies: none (data passed in). Random stops come from a RandomNumberGenerator the caller owns.
extends RefCounted

var strip: Array = []
var lines: Array = []
var pays: Dictionary = {}
var bets: Array = []
var two_cherries := 0
var jackpot_symbol := "jackpot"
var jackpot_seed := 500.0
var jackpot_contribution := 0.05
var jackpot_bet := 20


func _init(data: Dictionary) -> void:
	strip = data["strip"]
	lines = data["lines"]
	pays = data["pays"]
	bets = data["bets"]
	two_cherries = int(data["two_cherries_pay"])
	var j: Dictionary = data["jackpot"]
	jackpot_symbol = String(j["symbol"])
	jackpot_seed = float(j["seed"])
	jackpot_contribution = float(j["contribution"])
	jackpot_bet = int(j["needs_bet_per_line"])


func cost(bet_per_line: int) -> int:
	return bet_per_line * lines.size()


func random_stops(rng: RandomNumberGenerator) -> Array[int]:
	var s: Array[int] = []
	for i in 3:
		s.append(rng.randi_range(0, strip.size() - 1))
	return s


# The 3x3 window: grid[reel][row] with row 0 = top; `stop` is the middle row's strip index.
func grid(stops: Array[int]) -> Array:
	var g: Array = []
	var n := strip.size()
	for reel in 3:
		var col: Array = []
		for row in 3:
			col.append(String(strip[posmod(stops[reel] + row - 1, n)]))
		g.append(col)
	return g


# Pool after a stake of `stake` coins is added to it.
func grow_pool(pool: float, stake: int) -> float:
	return pool + float(stake) * jackpot_contribution


# Pays for one payline's three symbols (wilds stand in for everything except the jackpot gem).
func line_pay(cells: Array) -> int:
	var all_jackpot := true
	var has_jackpot := false
	for c in cells:
		if String(c) == jackpot_symbol:
			has_jackpot = true
		else:
			all_jackpot = false
	if all_jackpot:
		return int(pays[jackpot_symbol])
	if not has_jackpot:
		var first := ""
		var same := true
		for c in cells:
			var s := String(c)
			if s == "wild":
				continue
			if first == "":
				first = s
			elif s != first:
				same = false
		if same:
			return int(pays["wild"]) if first == "" else int(pays[first])
	var lead := 0
	for c in cells:
		if String(c) == "cherry":
			lead += 1
		else:
			break
	return two_cherries if lead == 2 else 0


# Result of one spin: {"total": coins won, "lines": [{"line", "pay"(coins), "jackpot": bool}], "jackpot_won": bool}.
# `pool` is the current progressive pot (before this spin's stake is added; jackpot pays what was in it).
func evaluate(stops: Array[int], bet_per_line: int, pool: float) -> Dictionary:
	var g := grid(stops)
	var total := 0
	var hits: Array = []
	var jackpot_won := false
	for i in lines.size():
		var ln: Array = lines[i]
		var cells := [g[0][int(ln[0])], g[1][int(ln[1])], g[2][int(ln[2])]]
		var mult := line_pay(cells)
		if mult <= 0:
			continue
		var is_jackpot := mult == int(pays[jackpot_symbol]) and String(cells[0]) == jackpot_symbol and String(cells[1]) == jackpot_symbol and String(cells[2]) == jackpot_symbol
		var coins := mult * bet_per_line
		if is_jackpot and bet_per_line >= jackpot_bet and not jackpot_won:
			coins = int(floor(pool))
			jackpot_won = true
		else:
			is_jackpot = false
		total += coins
		hits.append({"line": i, "pay": coins, "jackpot": is_jackpot})
	return {"total": total, "lines": hits, "jackpot_won": jackpot_won}
