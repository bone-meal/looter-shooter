# Purpose: (polish1 item 167) checks game/poker_dealer.gd as players sit, play (the house AI plays for them), stand up
# mid-hand, come back, bust and rebuy, with a second and third player as online: every chip a player put on the table
# comes back to their wallet or is still on the table (the house's chips counted in and out by house_bank); the table stops when all leave.
# Run: godot --headless --path . -s tools/poker_dealer_check.gd
# Dependencies: game/poker_dealer.gd, data/poker.json.
extends SceneTree

const Dealer = preload("res://game/poker_dealer.gd")
const DataStore = preload("res://core/data_store.gd")

var problems := 0
var wallets := {1: 5000, 2: 5000, 3: 5000}
var d: Dealer


func _initialize() -> void:
	_run.call_deferred()


func _expect(ok: bool, what: String) -> void:
	if not ok:
		problems += 1
		print("POKER_DEALER_CHECK FAIL ", what)


func _player_total() -> int:
	var t := 0
	for o: int in wallets:
		t += int(wallets[o])
	if d.rules != null:
		var pot_on := d.rules.phase not in ["idle", "showdown"]  # (after the showdown "put" is already in the winners' chips)
		for i in d.owners.size():
			if not d._gone.has(i):  # (a seat that stood up mid-hand was paid its stack: only what it may still win counts)
				t += int(d.rules.seats[i]["chips"]) + (int(d.rules.seats[i]["put"]) if pot_on else 0)
			else:
				t += int(d.rules.seats[i]["chips"]) + (int(d.rules.seats[i]["put"]) if pot_on else 0) - int(d._gone[i])
	for q: Array in d._queue:  # waiting for a seat: their buy-in is held
		t += int(q[2])
	return t + d.house_bank


func _sit(o: int, stakes: int, amount: int) -> void:
	wallets[o] = int(wallets[o]) - amount
	var why := d.sit(o, "P%d" % o, stakes, amount)
	if why != "":
		wallets[o] = int(wallets[o]) + amount
		print("POKER_DEALER_CHECK refused P%d: %s" % [o, why])


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _run() -> void:
	var cfg: Dictionary = DataStore.load_json("res://data/poker.json")
	for h: Dictionary in cfg["house"]:
		h["think_s"] = 0.01
	d = Dealer.new()
	d.cfg = cfg
	d.hand_pause = 0.05
	root.add_child(d)
	var events := [0]
	var closed := [false]
	d.changed.connect(func(ev: Array) -> void:
		events[0] += ev.size()
		for e: Dictionary in ev:
			if String(e["kind"]) == "closed":
				closed[0] = true)
	d.paid.connect(func(o: int, chips: int) -> void: wallets[o] = int(wallets[o]) + chips)
	var start := _player_total()
	d.auto = {1: 9999, 2: 9999, 3: 9999}
	_sit(1, 0, 1000)
	_expect(d.seat_of(1) == 0, "the first player takes the empty chair")
	await _wait(1.0)
	_sit(2, 2, 600)  # other stakes asked: the table's stay
	_expect(d.stakes == 0, "stakes set by the first player")
	await _wait(2.0)
	_expect(d.seat_of(2) > 0 or d.queued(2), "a second player gets a seat or waits for the next hand")
	await _wait(2.0)
	_expect(d.seat_of(2) > 0, "the second player is seated by the next hand")
	_sit(3, 0, 50)  # a buy-in below the minimum
	_expect(d.seat_of(3) < 0 and not d.queued(3), "a buy-in below the minimum is refused")
	_sit(3, 0, 800)
	var hands0: int = d.rules.hand_no
	for k in 40:
		await _wait(0.25)
		_expect(_player_total() == start, "player chips kept (%d vs %d) hand %d" % [_player_total(), start, d.rules.hand_no if d.rules else -1])
		if k == 10:
			d.leave(2)  # mid-hand most likely
			_expect(d.seat_of(2) < 0, "standing up frees the seat")
		if k == 20:
			_sit(2, 0, 1000)
		if d.rules != null and d.seat_of(1) >= 0 and int(d.rules.seats[d.seat_of(1)]["chips"]) == 0 and d.rules.phase in ["idle", "showdown"]:
			wallets[1] = int(wallets[1]) - 500
			if d.rebuy(1, 500) != "":
				wallets[1] = int(wallets[1]) + 500
	var names := {}
	for i in d.owners.size():
		if int(d.owners[i]) == 0:
			_expect(not names.has(String(d.rules.seats[i]["name"])), "no house player twice at the table (%s)" % String(d.rules.seats[i]["name"]))
			names[String(d.rules.seats[i]["name"])] = true
	print("POKER_DEALER_CHECK %d hands, %d events, wallets %s" % [d.rules.hand_no - hands0, events[0], str(wallets)])
	d.leave(1)
	d.leave(3)
	await _wait(0.5)
	_expect(_player_total() == start or d.rules != null, "chips kept after two left")
	d.leave(2)
	await _wait(0.5)
	_expect(closed[0] and d.rules == null, "the table stops when every player has left")
	_expect(_player_total() == start, "every chip back in the wallets (%d vs %d)" % [_player_total(), start])
	# the turn clock: a player who does not move is checked / folded
	var clocks := [0]
	d.changed.connect(func(ev: Array) -> void:
		for e: Dictionary in ev:
			if String(e["kind"]) == "clock":
				clocks[0] += 1)
	d.auto = {}
	d.turn_s = 0.3
	_sit(1, 1, 2500)
	await _wait(4.0)
	_expect(clocks[0] > 0, "the turn clock moved for a player who did not")
	d.leave(1)
	await _wait(0.3)
	_expect(_player_total() == start, "every chip back after the clock test (%d vs %d)" % [_player_total(), start])
	print("POKER_DEALER_CHECK problems %d" % problems)
	quit()
