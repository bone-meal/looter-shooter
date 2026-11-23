# Purpose: deals the casino's Texas Hold'em table (polish1 item 167): the seats (an owner per seat: 0 = a house player,
# else the player's id: 1 alone, the peer id online), sitting down (the first player sets the stakes, a player waits
# for the next hand when no free seat is out of the hand), hands one after another, house players thinking for a
# moment, a player's move only when it is their turn, a turn clock online, rebuys, a busted house player replaced by
# the next with a fresh buy-in, standing up (the stack is paid out at once; mid-hand the cards fold when the turn comes,
# and a pot the seat still wins is paid after the hand). The table stops when no player is seated. Used by
# game/poker_game.gd alone and by game/net_poker.gd on the host. Rules in core/poker_rules.gd, the house in
# core/poker_ai.gd, numbers in data/poker.json.
# Dependencies: core/poker_rules.gd, core/poker_ai.gd.
extends Node

const Rules = preload("res://core/poker_rules.gd")
const Ai = preload("res://core/poker_ai.gd")

signal changed(events: Array)  # the table moved on (events: core/poker_rules.gd events since the last call, plus "sit" / "leave" / "clock")
signal paid(who_id: int, chips: int)  # chips going back to a player's wallet (standing up, a pot won after standing up)
signal stopped  # no player is seated any more

var hand_pause := 3.2  # seconds the showdown stays up before the next hand

var cfg: Dictionary = {}  # data/poker.json
var rules: Rules
var stakes := -1  # the table's stakes (index into cfg.stakes), -1 = no table
var owners: Array = []  # seat -> owner id (0 = house)
var turn_s := 0.0  # seconds a player may think (0 = no clock)
var house_bank := 0  # chips the house took off the table minus what it brought (checks: every chip accounted for)
var auto := {}  # (dev) owner id -> hands the house AI plays for them

var _styles: Array = []  # seat -> house style ({} for players)
var _next_house := 0
var _queue: Array = []  # [owner id, name, buy_in] waiting for a free seat (next hand)
var _gone := {}  # seat -> chips already paid at standing up mid-hand
var _running := false
var _waiting_for := -1  # the seat whose player we wait for
var _moved: Dictionary = {}  # that player's move, when it comes
var _events: Array = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func players() -> int:
	var n := 0
	for o: int in owners:
		if o != 0:
			n += 1
	return n


func seat_of(who_id: int) -> int:
	return owners.find(who_id) if who_id != 0 else -1


func queued(who_id: int) -> bool:
	for q: Array in _queue:
		if int(q[0]) == who_id:
			return true
	return false


func waiting_for() -> int:
	return _waiting_for


func stake() -> Dictionary:
	return (cfg["stakes"] as Array)[maxi(stakes, 0)]


# A player sits down with `buy_in` chips (already taken from their wallet). Returns "" or why not (then give the chips back).
func sit(who_id: int, seat_name: String, stakes_i: int, buy_in: int) -> String:
	if who_id == 0 or seat_of(who_id) >= 0 or queued(who_id):
		return "You are already at the table."
	if stakes < 0 or rules == null:
		if stakes_i < 0 or stakes_i >= (cfg["stakes"] as Array).size():
			return "Those stakes are not offered."
		_new_table(stakes_i)
	var st := stake()
	if buy_in < int(st["min_bb"]) * int(st["bb"]) or buy_in > int(st["max_bb"]) * int(st["bb"]):
		return "The buy-in at this table is %d - %d." % [int(st["min_bb"]) * int(st["bb"]), int(st["max_bb"]) * int(st["bb"])]
	if players() + _queue.size() >= owners.size():
		return "Every seat at the table is taken by players."
	var seat := _free_seat()
	if seat < 0:
		_queue.append([who_id, seat_name, buy_in])
		_events.append({"kind": "sit_wait", "name": seat_name})
		_send()
		return ""
	_seat(seat, who_id, seat_name, buy_in)
	_send()
	_play.call_deferred()
	return ""


# A player's move ({"do": fold | check | call | raise | allin, "to"}): taken only on their turn.
func move(who_id: int, mv: Dictionary) -> bool:
	var seat := seat_of(who_id)
	if seat < 0 or seat != _waiting_for or rules == null or rules.current != seat:
		return false
	if rules.legal(seat).is_empty():
		return false
	_moved = mv
	return true


# A busted player buys back in with `amount` (already taken from their wallet). "" or why not.
func rebuy(who_id: int, amount: int) -> String:
	var seat := seat_of(who_id)
	if seat < 0 or rules == null:
		return "You are not at the table."
	if int(rules.seats[seat]["chips"]) > 0:
		return "You still have chips."
	var st := stake()
	if amount < int(st["min_bb"]) * int(st["bb"]) or amount > int(st["max_bb"]) * int(st["bb"]):
		return "The buy-in at this table is %d - %d." % [int(st["min_bb"]) * int(st["bb"]), int(st["max_bb"]) * int(st["bb"])]
	rules.seats[seat]["chips"] = amount
	if rules.phase in ["idle", "showdown"]:
		rules.seats[seat]["out"] = false
	_send()
	_play.call_deferred()
	return ""


# A player stands up: their stack is paid at once (paid signal). Mid-hand their cards fold when their turn comes.
func leave(who_id: int) -> void:
	for k in range(_queue.size() - 1, -1, -1):
		if int(_queue[k][0]) == who_id:
			_queue.remove_at(k)
	var seat := seat_of(who_id)
	if seat < 0 or rules == null:
		return
	var chips := int(rules.seats[seat]["chips"])
	var in_hand := rules.phase not in ["idle", "showdown"] and rules.in_hand(seat)
	if in_hand:
		_gone[seat] = chips
		if rules.current == seat:
			rules.act(seat, {"do": "fold"})
			_moved = {}
	else:
		rules.seats[seat]["chips"] = 0
	_events.append({"kind": "leave", "seat": seat, "name": String(rules.seats[seat]["name"])})
	owners[seat] = 0
	_styles[seat] = {"gone": true, "owner": who_id}
	if not in_hand:
		_house_sits(seat)
	if chips > 0:
		paid.emit(who_id, chips)
	if players() == 0 and _queue.is_empty():
		_stop()
		return
	_send()


func _stop() -> void:
	if rules != null:
		var mid_hand := rules.phase not in ["idle", "showdown"]
		for i in rules.seats.size():  # house stacks (players' are paid already); mid-hand the pot goes back to the house too
			var st: Dictionary = rules.seats[i]
			house_bank += int(st["chips"]) - int(_gone.get(i, 0)) + (int(st["put"]) if mid_hand else 0)
	rules = null
	stakes = -1
	owners = []
	_styles = []
	_gone = {}
	_queue = []
	_waiting_for = -1
	_running = false
	_events.append({"kind": "closed"})
	_send()
	stopped.emit()


func _new_table(stakes_i: int) -> void:
	stakes = stakes_i
	var st := stake()
	rules = Rules.new()
	rules.small_blind = int(st["sb"])
	rules.big_blind = int(st["bb"])
	owners = []
	_styles = []
	for k in int(cfg.get("seats", 6)):
		var h := _next_style()
		rules.add_seat(String(h["name"]), _house_buy_in())
		house_bank -= int(rules.seats[rules.seats.size() - 1]["chips"])
		owners.append(0)
		_styles.append(h)


# The next house player in turn who is not at the table already (two Big Sals at one table read as a bug).
func _next_style() -> Dictionary:
	var house: Array = cfg["house"]
	var seated := {}
	if rules != null:
		for i in rules.seats.size():
			if i < owners.size() and int(owners[i]) == 0 and int(rules.seats[i]["chips"]) > 0:
				seated[String(rules.seats[i]["name"])] = true
	for k in house.size():
		var h: Dictionary = house[_next_house % house.size()]
		_next_house += 1
		if not seated.has(String(h["name"])):
			return h
	var any: Dictionary = house[_next_house % house.size()]
	_next_house += 1
	return any


func _house_buy_in() -> int:
	var st := stake()
	return int(st["bb"]) * _rng.randi_range(int(st["min_bb"]) + 20, int(st["max_bb"]))


# A seat a player may take now: seat 0 (the chair with no house player) first, then a house seat out of this hand.
func _free_seat() -> int:
	var hand_on := rules.phase not in ["idle", "showdown"]
	var order: Array = [0]
	for i in range(1, owners.size()):
		order.append(i)
	for i: int in order:
		if int(owners[i]) == 0 and not _gone.has(i) and (not hand_on or not rules.in_hand(i)):
			return i
	return -1


func _seat(seat: int, who_id: int, seat_name: String, buy_in: int) -> void:
	house_bank += int(rules.seats[seat]["chips"])  # the house player there gets up with their stack
	owners[seat] = who_id
	_styles[seat] = {}
	rules.seats[seat]["name"] = seat_name
	rules.seats[seat]["chips"] = buy_in
	if rules.phase in ["idle", "showdown"]:
		rules.seats[seat]["out"] = false
	else:
		rules.seats[seat]["folded"] = true  # sat down during a hand: plays from the next one
	_events.append({"kind": "sit", "seat": seat, "name": seat_name})


func _house_sits(seat: int) -> void:
	var h := _next_style()
	rules.seats[seat]["name"] = String(h["name"])
	house_bank += int(rules.seats[seat]["chips"])
	rules.seats[seat]["chips"] = _house_buy_in()
	house_bank -= int(rules.seats[seat]["chips"])
	_styles[seat] = h
	_events.append({"kind": "sit", "seat": seat, "name": String(h["name"])})


# Between hands: queued players take free seats, the seats of players who stood up mid-hand (and busted house
# players) get a house player; a pot won after standing up is paid out.
func _between_hands() -> void:
	for seat: int in _gone.keys():
		var won := int(rules.seats[seat]["chips"]) - int(_gone[seat])
		rules.seats[seat]["chips"] = 0
		if won > 0 and (_styles[seat] as Dictionary).has("owner"):  # (the owner was kept at standing up)
			paid.emit(int(_styles[seat]["owner"]), won)
		_house_sits(seat)
	_gone.clear()
	while not _queue.is_empty():
		var seat := _free_seat()
		if seat < 0:
			break
		var q: Array = _queue.pop_front()
		_seat(seat, int(q[0]), String(q[1]), int(q[2]))
	if bool(cfg.get("rebuy_house", true)):
		for i in owners.size():
			if int(owners[i]) == 0 and int(rules.seats[i]["chips"]) <= 0:
				_house_sits(i)


func _can_play() -> bool:
	if rules == null:
		return false
	for i in owners.size():
		if int(owners[i]) != 0 and int(rules.seats[i]["chips"]) > 0:
			return true
	return not _queue.is_empty()


# Hands one after another while a seated player has chips.
func _play() -> void:
	if _running or not _can_play():
		return
	_running = true
	while _can_play():
		_between_hands()
		if not rules.start_hand(_rng):
			break
		_send()
		while rules != null and rules.phase != "showdown":
			var who := rules.current
			if who < 0:
				break
			if _gone.has(who):  # stood up during this hand
				rules.act(who, {"do": "fold"})
				_send()
				continue
			var who_id := int(owners[who])
			if who_id != 0:
				await _players_turn(who, who_id)
				if rules == null:
					break
				_send()
				continue
			var style: Dictionary = _styles[who]
			await get_tree().create_timer(float(style.get("think_s", 1.2)) * _rng.randf_range(0.6, 1.3)).timeout
			if rules == null:
				break
			if rules.current != who:
				continue
			if not rules.act(who, Ai.decide(rules, who, style, _rng)):
				rules.act(who, {"do": "fold"})
			_send()
		if rules == null:
			break
		_send()
		for o: int in auto.keys():
			auto[o] = maxi(int(auto[o]) - 1, 0)
		await get_tree().create_timer(hand_pause).timeout
		if rules == null:
			break
	_running = false
	if rules != null:
		_send()


func _players_turn(seat: int, who_id: int) -> void:
	_waiting_for = seat
	_moved = {}
	_send()
	var waited := 0.0
	while rules != null and rules.current == seat and int(owners[seat]) == who_id:
		if int(auto.get(who_id, 0)) > 0:
			await get_tree().create_timer(0.3).timeout
			if rules != null and rules.current == seat:
				_moved = Ai.decide(rules, seat, (cfg["house"] as Array)[2], _rng)
		if not _moved.is_empty():
			var mv := _moved
			_moved = {}
			if rules.act(seat, mv):
				break
		await get_tree().process_frame
		waited += get_process_delta_time()
		if turn_s > 0.0 and waited >= turn_s:
			var ok := rules.legal(seat)
			_events.append({"kind": "clock", "seat": seat})
			rules.act(seat, {"do": "check"} if int(ok.get("call", 1)) == 0 else {"do": "fold"})
			break
	_waiting_for = -1


func _send() -> void:
	var ev := _events.duplicate()
	_events.clear()
	if rules != null:
		ev.append_array(rules.events)
		rules.events.clear()
	changed.emit(ev)


# The table for one seat (-1 = an onlooker): core/poker_rules.gd view() plus whose seats are players', the stakes, and
# what that seat may do now ({} when it is not their turn).
func view_for(seat: int) -> Dictionary:
	if rules == null:
		return {}
	var v := rules.view(seat)
	var human: Array = []
	for o: int in owners:
		human.append(o != 0)
	v["human"] = human
	v["stakes"] = stakes
	v["legal"] = rules.legal(seat) if seat >= 0 and seat == _waiting_for else {}
	v["turn_s"] = turn_s
	return v
