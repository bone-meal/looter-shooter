# Purpose: the host's book of the player card tables (locked: four tables on the beach, one the House Dealer's; at the
# other three two players play each other). Seats, each player's deck (checked for legality; who owns which cards
# cannot be known: saves are local), a 5 s countdown, the match itself (core/tcg/match_state.gd with a host seed;
# every move is a player's intent, judged by the match), the turn timer, and the end: a result, or a loss for whoever
# walks away or drops out. Pure rules, no nodes, no network (like core/trade_desk.gd).
# Every call returns messages to deliver: [[peer (0 = everyone), what, args], ...]:
#   "seats" [view]            who sits where, for everyone (view = seats_view())
#   "pick" [table]            both seats are taken: pick your deck
#   "countdown" [table, s]    both decks are in: the match starts in s seconds
#   "match" [table, snapshot, events, names, turn_left, mats]   the match as it stands, after every change (everyone sees all:
#                             spectators see everything incl. hands, locked); names = the two players' names by side,
#                             mats = each side's play mat id (sent with the deck; letters, digits and _ only)
#   "refused" [why]           an intent or deck was refused
#   "result" [table, winner, peers, names]   winner = side 0 / 1 (2 = both fell), peers / names by side
# Dependencies: core/tcg/match_state.gd, core/tcg/ai_player.gd (do_move); a card db handed in.
extends RefCounted

const MatchState = preload("res://core/tcg/match_state.gd")
const AiPlayer = preload("res://core/tcg/ai_player.gd")

const COUNTDOWN := 5.0
const MAX_APART := 6.0  # metres from the table: a seated player farther away has walked off (a loss mid-match)

var db: RefCounted
var tables: Array = []  # {"at": Vector3 or null (where it stands, once known), "seats": [peer, peer] (0 = free), "decks": [{}, {}], "start_in": -1.0, "match", "turn_left"}
var rng := RandomNumberGenerator.new()


func _init(card_db: RefCounted, count: int) -> void:
	db = card_db
	rng.randomize()
	for i in count:
		tables.append({"at": null, "seats": [0, 0], "decks": [{}, {}], "start_in": -1.0, "match": null, "turn_left": 0.0})


# Where the tables stand in the world (the walk-off check waits until they are known: the club is built lazily).
func set_spots(spots: Array) -> void:
	for i in mini(spots.size(), tables.size()):
		tables[i]["at"] = spots[i]


func seats_view(names: Dictionary) -> Array:
	var out: Array = []
	for t: Dictionary in tables:
		var seats: Array = t["seats"]
		out.append({"peers": seats.duplicate(), "names": [String(names.get(seats[0], "")), String(names.get(seats[1], ""))], "busy": t["match"] != null})
	return out


func table_of(peer: int) -> int:
	for i in tables.size():
		if (tables[i]["seats"] as Array).has(peer):
			return i
	return -1


func sit(peer: int, table: int, names: Dictionary) -> Array:
	if table < 0 or table >= tables.size() or table_of(peer) >= 0:
		return []
	var t: Dictionary = tables[table]
	var seats: Array = t["seats"]
	var free := seats.find(0)
	if free < 0 or t["match"] != null:
		return [[peer, "refused", ["Both seats are taken: you can watch."]]]
	seats[free] = peer
	var out: Array = [[0, "seats", [seats_view(names)]]]
	if not seats.has(0):
		for p: int in seats:
			out.append([p, "pick", [table]])
	return out


# Leaves the seat (walked away, dropped out or chose to): mid-match it is a loss for that side.
func leave(peer: int, names: Dictionary) -> Array:
	var i := table_of(peer)
	if i < 0:
		return []
	var t: Dictionary = tables[i]
	var side := (t["seats"] as Array).find(peer)
	var out: Array = []
	if t["match"] != null and String(t["match"].get("phase")) != "over":
		t["match"].call("concede", side)
		out.append_array(_after(i, names))
	else:
		_clear(t)
		(t["seats"] as Array)[side] = 0
		out.append([0, "seats", [seats_view(names)]])
	return out


func deck(peer: int, chosen: Dictionary, names: Dictionary) -> Array:
	var i := table_of(peer)
	if i < 0:
		return []
	var t: Dictionary = tables[i]
	if t["match"] != null or (t["seats"] as Array).has(0):
		return []
	var clean := {"name": String(chosen.get("name", "")), "leader": String(chosen.get("leader", "")), "cards": []}
	if chosen.get("cards") is Array:
		for id: Variant in chosen["cards"]:
			(clean["cards"] as Array).append(String(id))
	var mat := String(chosen.get("mat", "")).left(32)
	var safe := RegEx.create_from_string("^[a-z0-9_]*$")
	clean["mat"] = mat if safe.search(mat) != null else ""
	var why: String = db.deck_problem(clean)
	if why != "":
		return [[peer, "refused", ["That deck cannot be played: " + why]]]
	(t["decks"] as Array)[(t["seats"] as Array).find(peer)] = clean
	if not ((t["decks"][0] as Dictionary).is_empty() or (t["decks"][1] as Dictionary).is_empty()):
		t["start_in"] = COUNTDOWN
		return [[0, "countdown", [i, COUNTDOWN]]]
	return []


func intent(peer: int, move: Dictionary, names: Dictionary) -> Array:
	var i := table_of(peer)
	if i < 0 or tables[i]["match"] == null:
		return []
	var t: Dictionary = tables[i]
	var m: RefCounted = t["match"]
	var side := (t["seats"] as Array).find(peer)
	var why := ""
	if String(move.get("do", "")) == "mulligan":
		var picks: Array = []
		if move.get("indices") is Array:
			for x: Variant in move["indices"]:
				picks.append(int(x))
		why = m.call("mulligan", side, picks)
	elif String(move.get("do", "")) == "concede":
		m.call("concede", side)
	elif ["play", "attack", "power", "end"].has(String(move.get("do", ""))):
		var before := int(m.get("current"))
		why = AiPlayer.do_move(m, side, move)
		if why == "" and int(m.get("current")) != before:
			t["turn_left"] = float(db.get("rules")["turn_seconds"])
	else:
		why = "unknown move"
	if why != "":
		return [[peer, "refused", [why]]]
	return _after(i, names)


# Countdowns, turn timers, players who dropped out or walked off. positions: peer -> Vector3.
func tick(dt: float, names: Dictionary, positions: Dictionary) -> Array:
	var out: Array = []
	for i in tables.size():
		var t: Dictionary = tables[i]
		for p: int in (t["seats"] as Array).duplicate():
			var gone := p != 0 and not names.has(p)
			var off := p != 0 and t["at"] is Vector3 and positions.has(p) and (positions[p] as Vector3).distance_to(t["at"]) > MAX_APART
			if gone or off:
				out.append_array(leave(p, names))
		if float(t["start_in"]) >= 0.0:
			t["start_in"] = float(t["start_in"]) - dt
			if float(t["start_in"]) < 0.0 and not (t["seats"] as Array).has(0):
				t["start_in"] = -1.0
				t["match"] = MatchState.new(db, t["decks"], rng.randi())
				t["turn_left"] = float(db.get("rules")["turn_seconds"])
				out.append([0, "seats", [seats_view(names)]])
				out.append_array(_after(i, names))
		elif t["match"] != null and String(t["match"].get("phase")) != "over":
			t["turn_left"] = float(t["turn_left"]) - dt
			if float(t["turn_left"]) <= 0.0:  # time is up: the turn ends (in the mulligan: the hands are kept)
				var m: RefCounted = t["match"]
				if String(m.get("phase")) == "mulligan":
					for side in 2:
						if not bool(m.get("sides")[side]["ready"]):
							m.call("mulligan", side, [])
				else:
					m.call("end_turn", int(m.get("current")))
				t["turn_left"] = float(db.get("rules")["turn_seconds"])
				out.append_array(_after(i, names))
	return out


# The match as it stands for everyone, and its end when it is over.
func _after(i: int, names: Dictionary) -> Array:
	var t: Dictionary = tables[i]
	var m: RefCounted = t["match"]
	var seats: Array = t["seats"]
	var who := [String(names.get(seats[0], "Player")), String(names.get(seats[1], "Player"))]
	var mats := [String((t["decks"][0] as Dictionary).get("mat", "")), String((t["decks"][1] as Dictionary).get("mat", ""))]
	var out: Array = [[0, "match", [i, m.call("snapshot"), m.call("take_log"), who, float(t["turn_left"]), mats]]]
	if String(m.get("phase")) == "over":
		out.append([0, "result", [i, int(m.get("winner")), seats.duplicate(), who]])
		_clear(t)
		t["seats"] = [0, 0]
		out.append([0, "seats", [seats_view(names)]])
	return out


func _clear(t: Dictionary) -> void:
	t["decks"] = [{}, {}]
	t["start_in"] = -1.0
	t["match"] = null
