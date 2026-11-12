# Purpose: the island's endless rounds: when a round starts, how many enemies it holds and which kinds, how much
# tougher they are than in round 1, when a boss or a special round comes, and the pacing (first delay, the gap
# between two spawns, the break between rounds). Pure rules: no nodes, no rendering.
# Dependencies: none. Numbers come from data/island_rounds.json, passed to the constructor.
extends RefCounted

signal round_started(number: int, kind: String)  # kind: "normal", "boss" or "special"
signal round_ended(number: int, kind: String)

var number := 0  # the round being fought, or the one just won during the break (0 = before round 1)
var kind := "normal"
var players := 1  # how many players the round is sized for (set before a round starts)
var alive_cap := 24  # most enemies alive at once

var _cfg: Dictionary
var _rng: RandomNumberGenerator
var _queue: Array[String] = []  # enemy ids still to come this round
var _fighting := false
var _running := false
var _next_time := 0.0  # when the next round starts (in a break) or the next enemy comes (in a round)


func _init(cfg: Dictionary, rng: RandomNumberGenerator) -> void:
	_cfg = cfg
	_rng = rng


# A run begins: round 1 starts after the first delay.
func start(now: float) -> void:
	number = 0
	kind = "normal"
	_queue.clear()
	_fighting = false
	_running = true
	_next_time = now + float(_cfg["start_delay"])


# Back to before a run (game over): nothing happens until start().
func stop() -> void:
	number = 0
	kind = "normal"
	_queue.clear()
	_fighting = false
	_running = false


# For testing (/round): whatever is going on ends, and round `round_number` starts in a few seconds.
func skip_to(round_number: int, now: float) -> void:
	number = maxi(round_number, 1) - 1
	_queue.clear()
	_fighting = false
	_running = true
	_next_time = now + 3.0


func running() -> bool:
	return _running


func fighting() -> bool:
	return _fighting


# Call every tick with the number of this round's enemies alive. Returns the id of an enemy to send in now, or "".
func update(now: float, alive: int) -> String:
	if not _running:
		return ""
	if not _fighting:
		if now < _next_time:
			return ""
		number += 1
		kind = kind_of(number)
		_queue = roster(number, players)
		_fighting = true
		_next_time = now
		round_started.emit(number, kind)
	if _queue.is_empty():
		if alive <= 0:
			_fighting = false
			_next_time = now + float(_cfg["break_seconds"])
			round_ended.emit(number, kind)
		return ""
	if alive >= alive_cap or now < _next_time:
		return ""
	_next_time = now + spawn_gap(number, kind)
	return _queue.pop_front()


# Enemies of this round still to beat: the living plus those not yet sent in.
func left(alive: int) -> int:
	return alive + _queue.size() if _fighting else 0


# Seconds until the next round starts (0 while one is being fought or nothing runs).
func seconds_to_round(now: float) -> float:
	return maxf(_next_time - now, 0.0) if _running and not _fighting else 0.0


# Enemies taken off the island because everybody left: they come out of the sea again later.
func put_back(ids: Array) -> void:
	for id: String in ids:
		_queue.append(id)


# Holds the clock still for `seconds` (nobody was on the islands for that long).
func delay(seconds: float) -> void:
	_next_time += seconds


func kind_of(round_number: int) -> String:
	var boss: Dictionary = _cfg["boss"]
	if round_number % int(boss["every"]) == 0:
		return "boss"
	var special: Dictionary = _cfg["special"]
	if round_number >= int(special["first"]) and (round_number - int(special["first"])) % int(special["every"]) == 0:
		return "special"
	return "normal"


# How many ordinary enemies a normal round of that number holds.
func count(round_number: int, player_count: int) -> int:
	var c: Dictionary = _cfg["count"]
	var base := float(c["first"]) + float(c["per_round"]) * float(round_number - 1)
	return roundi(base * (1.0 + float(c["per_extra_player"]) * float(maxi(player_count, 1) - 1)))


# The boss of a boss round, and which time round the list it is (0 = the first).
func boss_of(round_number: int) -> String:
	var boss: Dictionary = _cfg["boss"]
	var order: Array = boss["order"]
	return String(order[(roundi(float(round_number) / float(boss["every"])) - 1) % order.size()])


func boss_cycle(round_number: int) -> int:
	var boss: Dictionary = _cfg["boss"]
	return floori(float(roundi(float(round_number) / float(boss["every"])) - 1) / float((boss["order"] as Array).size()))


# The ids of everything a round sends in, in order.
func roster(round_number: int, player_count: int) -> Array[String]:
	var out: Array[String] = []
	var round_kind := kind_of(round_number)
	var total := count(round_number, player_count)
	if round_kind == "special":
		for i in maxi(roundi(float(total) * float(_cfg["special"]["count_mult"])), 1):
			out.append(String(_cfg["special"]["enemy"]))
		return out
	if round_kind == "boss":
		total = maxi(roundi(float(total) * float(_cfg["boss"]["count_mult"])), 1)
	var weights: Dictionary = _mix(round_number)
	var sum := 0.0
	for id: String in weights:
		sum += float(weights[id])
	for i in total:
		var pick := _rng.randf() * sum
		for id: String in weights:
			pick -= float(weights[id])
			if pick < 0.0:
				out.append(id)
				break
	if round_kind == "boss":
		out.insert(mini(3, out.size()), boss_of(round_number))  # the boss comes ashore after the first few
	return out


func _mix(round_number: int) -> Dictionary:
	var best: Dictionary = {}
	var best_from := 0
	for entry: Dictionary in _cfg["mix"]:
		if int(entry["from"]) <= round_number and int(entry["from"]) >= best_from:
			best_from = int(entry["from"])
			best = entry["enemies"]
	return best


func spawn_gap(round_number: int, round_kind: String) -> float:
	var gaps: Array = _cfg["spawn_gap"]
	var t := clampf(float(round_number - 1) / maxf(float(_cfg["spawn_gap_full_at"]) - 1.0, 1.0), 0.0, 1.0)
	var gap := lerpf(float(gaps[0]), float(gaps[1]), t)
	return gap * float(_cfg["special"]["gap_mult"]) if round_kind == "special" else gap


func health_mult(round_number: int) -> float:
	var h: Dictionary = _cfg["health"]
	var straight := mini(round_number, int(h["compound_from"]))
	return (1.0 + float(h["per_round"]) * float(straight - 1)) * pow(float(h["compound"]), float(maxi(round_number - int(h["compound_from"]), 0)))


func speed_mult(round_number: int) -> float:
	return minf(1.0 + float(_cfg["speed"]["per_round"]) * float(round_number - 1), float(_cfg["speed"]["max"]))


func damage_mult(round_number: int) -> float:
	return minf(1.0 + float(_cfg["damage"]["per_round"]) * float(round_number - 1), float(_cfg["damage"]["max"]))


# An enemy's stats as it is in that round: `base` (its stats in round 1; a boss's ordinary stats) made tougher.
# Bosses get tougher by how often the boss list has been gone through, not by the round.
func stats_for(base: Dictionary, round_number: int, is_boss: bool) -> Dictionary:
	var out := base.duplicate(true)
	if is_boss:
		out["max_hp"] = float(base["max_hp"]) * pow(float(_cfg["boss"]["health_per_cycle"]), float(boss_cycle(round_number)))
		return out
	out["max_hp"] = float(base["max_hp"]) * health_mult(round_number)
	out["speed"] = float(base["speed"]) * speed_mult(round_number)
	out["damage"] = float(base["damage"]) * damage_mult(round_number)
	return out
