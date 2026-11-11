# Purpose: developer check of the casino rules: exact slot return by enumeration + a simulated run with the progressive jackpot, blackjack invariants over many rounds, roulette bet validity and return. Writes tools/casino_check.log and quits. Run scene tools/casino_check.tscn.
# Dependencies: core/slot_math.gd, core/blackjack_rules.gd, core/roulette_rules.gd, core/data_store.gd, data/slots.json.
extends Node

const SlotMath = preload("res://core/slot_math.gd")
const Blackjack = preload("res://core/blackjack_rules.gd")
const Roulette = preload("res://core/roulette_rules.gd")
const DataStore = preload("res://core/data_store.gd")

var _log := PackedStringArray()


func _ready() -> void:
	_slots()
	_blackjack()
	_roulette()
	var f := FileAccess.open("res://tools/casino_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_log))
	f.close()
	get_tree().quit()


func _slots() -> void:
	var math := SlotMath.new(DataStore.load_json("res://data/slots.json"))
	var n := math.strip.size()
	var total := 0
	var winning := 0
	for a in n:
		for b in n:
			for c in n:
				var stops: Array[int] = [a, b, c]
				var r := math.evaluate(stops, 1, 0.0)  # bet 1 per line: gem lines pay the fixed 200x
				total += int(r["total"])
				if int(r["total"]) > 0:
					winning += 1
	var combos := n * n * n
	_log.append("slots enumerate: base return %.4f hit rate %.4f (stops %d)" % [float(total) / float(combos * math.lines.size()), float(winning) / float(combos), combos])
	# simulated session at max bet with the progressive pot
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var bet := 20
	var pool := math.jackpot_seed
	var spent := 0
	var won := 0
	var jackpots := 0
	var biggest := 0
	for i in 400000:
		var stake := math.cost(bet)
		spent += stake
		pool = math.grow_pool(pool, stake)
		var stops2 := math.random_stops(rng)
		var r2 := math.evaluate(stops2, bet, pool)
		won += int(r2["total"])
		biggest = maxi(biggest, int(r2["total"]))
		if bool(r2["jackpot_won"]):
			jackpots += 1
			pool = math.jackpot_seed
	_log.append("slots simulate 400k spins at max bet: return %.4f jackpots %d biggest win %d" % [float(won) / float(spent), jackpots, biggest])
	var sample: Array[int] = [0, 0, 0]
	var strip_has_wild := math.strip.find("wild")
	var sw: Array[int] = [strip_has_wild, strip_has_wild, strip_has_wild]
	_log.append("slots check: stops %s middle row %s ; all-wild stops pay %s" % [str(sample), str(math.grid(sample)[0][1]), str(math.evaluate(sw, 1, 0.0)["total"])])


func _blackjack() -> void:
	var bj := Blackjack.new(6, 0.25)
	bj.rng.seed = 777
	var rounds := 100000
	var net := 0
	var stake_total := 0
	var bad := 0
	var outcomes := {}
	var naturals := 0
	for i in rounds:
		bj.start(10)
		var guard := 0
		while bj.phase == "player" and guard < 20:
			guard += 1
			var o := bj.options(1000)
			var cards := bj.hand_cards(bj.active)
			var ev := Blackjack.evaluate(cards)
			var total := int(ev["total"])
			if o["split"] and Blackjack.rank_of(cards[0]) in [0, 7]:
				bj.split()
			elif o["double"] and (total == 11 or (total == 10 and bj.dealer[0] % 13 > 1 and bj.dealer[0] % 13 < 9)):
				bj.double_down()
			elif o["hit"] and (total < 17 and not (total >= 12 and bj.dealer[0] % 13 >= 1 and bj.dealer[0] % 13 <= 5)):
				bj.hit()
			else:
				bj.stand()
		guard = 0
		while bj.phase == "dealer" and guard < 20:
			guard += 1
			bj.dealer_step()
		if bj.phase != "done" or bj.results.size() != bj.hands.size():
			bad += 1
			continue
		if Blackjack.is_blackjack(bj.hand_cards(0)) and bj.hands.size() == 1:
			naturals += 1
		stake_total += bj.staked
		net += bj.returned - bj.staked
		for r in bj.results:
			outcomes[r["outcome"]] = int(outcomes.get(r["outcome"], 0)) + 1
	_log.append("blackjack %d rounds: stuck rounds %d, naturals %d, net %d on %d staked (%.3f), outcomes %s" % [rounds, bad, naturals, net, stake_total, float(net) / float(stake_total), str(outcomes)])
	var ace_pair: Array[int] = [0, 13]
	var ten_pair: Array[int] = [9, 12]
	_log.append("blackjack totals: A+A=%s A+K=%s soft=%s 10+K+5 bust=%s" % [str(Blackjack.total_of(ace_pair)), str(Blackjack.total_of([0, 12] as Array[int])), str(Blackjack.evaluate([0, 5] as Array[int])["soft"]), str(Blackjack.total_of([9, 12, 4] as Array[int]))])
	_log.append("blackjack ten-pair splits allowed: %s" % str(bj._same_value(ten_pair[0], ten_pair[1])))


func _roulette() -> void:
	var keys := ["straight:17", "straight:0", "split:17-20", "split:1-2", "split:3-4", "street:1", "corner:17", "line:1", "dozen:2", "column:3", "red", "black", "odd", "even", "low", "high"]
	var lines := PackedStringArray()
	for key: String in keys:
		var back := 0
		for n in 37:
			back += Roulette.payout(key, 10, n)
		lines.append("%s(valid=%s odds=%d return=%.4f)" % [key, str(Roulette.is_valid(key)), Roulette.odds(key), float(back) / 370.0])
	_log.append("roulette: " + " ".join(lines))
	var wheel_ok := Roulette.WHEEL.size() == 37
	var seen := {}
	for n: int in Roulette.WHEEL:
		seen[n] = true
	_log.append("roulette wheel size ok=%s all distinct=%s reds=%d" % [str(wheel_ok), str(seen.size() == 37), Roulette.REDS.size()])
