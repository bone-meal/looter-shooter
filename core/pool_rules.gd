# Purpose: (polish1 item 71) 8-ball rules, pure: whose shot it is, open table and groups (solids 1-7 / stripes 9-15),
# fouls (cue ball potted, nothing hit, the wrong ball hit first, no ball potted and no cushion after the contact,
# the shot clock), ball in hand for the other player after a foul, the 8: potted on the break it is put back on its
# spot; otherwise it wins only when the shooter's group is cleared, the pocket was called and there was no foul, and
# loses the game in any other way. A shot is judged from core/pool_sim.gd's events.
# Dependencies: none.
extends RefCounted

const SOLIDS := [1, 2, 3, 4, 5, 6, 7]
const STRIPES := [9, 10, 11, 12, 13, 14, 15]

var current := 0
var groups := ["", ""]  # "solids" / "stripes" once the table is closed
var break_shot := true
var ball_in_hand := false
var winner := -1
var message := ""  # what happened, for the screen ({p0} / {p1} = the players' names)
var foul := ""  # the last shot's foul, "" if none


func start() -> void:
	current = 0
	groups = ["", ""]
	break_shot = true
	ball_in_hand = false
	winner = -1
	message = "Break!"
	foul = ""


func group_balls(g: String) -> Array:
	return SOLIDS if g == "solids" else (STRIPES if g == "stripes" else [])


# Balls of player i's group still on the table (all 15 but the 8 while the table is open).
func left_of(i: int, on_table: PackedByteArray) -> Array:
	var out: Array = []
	var g := String(groups[i])
	for b in range(1, 16):
		if b == 8 or on_table[b] == 0:
			continue
		if g == "" or group_balls(g).has(b):
			out.append(b)
	return out


# Is player i shooting at the 8 now (group assigned and cleared)?
func on_the_eight(i: int, on_table: PackedByteArray) -> bool:
	return String(groups[i]) != "" and left_of(i, on_table).is_empty()


# The balls player i may hit first.
func legal_targets(i: int, on_table: PackedByteArray) -> Array:
	if on_the_eight(i, on_table):
		return [8]
	return left_of(i, on_table)


# Judges a finished shot. first_hit / pocketed / rail come from the sim; on_table is after the shot; called = the
# pocket called for the 8 (-1 none); timed_out = the shot clock ran out (nothing was shot).
# Returns {"foul", "turn_kept", "eight_respot", "winner"}.
func judge(first_hit: int, pocketed: Array, rail: bool, on_table: PackedByteArray, called: int, timed_out := false) -> Dictionary:
	var shooter := current
	var other := 1 - shooter
	var was_on_eight := String(groups[shooter]) != "" and _left_before(shooter, on_table, pocketed).is_empty()
	var legal_first: Array = [8] if was_on_eight else (_left_before(shooter, on_table, pocketed) if String(groups[shooter]) != "" else _all_but_eight())
	foul = ""
	var potted: Array = []
	var eight_pocket := -2
	var cue_potted := false
	for e: Array in pocketed:
		var b := int(e[0])
		if b == 0:
			cue_potted = true
		elif b == 8:
			eight_pocket = int(e[1])
		else:
			potted.append(b)
	if timed_out:
		foul = "Out of time"
	elif cue_potted:
		foul = "Scratch: the cue ball went down"
	elif first_hit < 0:
		foul = "No ball hit"
	elif not legal_first.has(first_hit) and not (break_shot and first_hit > 0):
		foul = "Wrong ball first (%d)" % first_hit
	elif pocketed.is_empty() and not rail and not break_shot:
		foul = "No cushion after the contact"
	var res := {"foul": foul, "turn_kept": false, "eight_respot": false, "winner": -1}
	# the 8
	if eight_pocket != -2:
		if break_shot:
			res["eight_respot"] = true
			message = "The 8 went down on the break: it goes back on its spot."
		elif was_on_eight and foul == "" and (called < 0 or called == eight_pocket):
			winner = shooter
			message = "The 8 is down: game!"
		else:
			winner = other
			message = "The 8 went down too early, in the wrong pocket or with a foul: game lost."
		if winner >= 0:
			res["winner"] = winner
			return res
	# groups
	if String(groups[shooter]) == "" and not break_shot and foul == "" and not potted.is_empty():
		var g := "solids" if SOLIDS.has(int(potted[0])) else "stripes"
		groups[shooter] = g
		groups[other] = "stripes" if g == "solids" else "solids"
		message = "{p%d} takes the %s." % [shooter, g]
	var own_potted := false
	for b: int in potted:
		if String(groups[shooter]) == "" or group_balls(String(groups[shooter])).has(b):
			own_potted = true
	break_shot = false
	if foul != "":
		ball_in_hand = true
		current = other
		message = "Foul: %s. Ball in hand." % foul
	elif own_potted or (res["eight_respot"] and not potted.is_empty()):
		res["turn_kept"] = true
		ball_in_hand = false
		if message == "" or message.begins_with("Foul") or message == "Break!":
			message = "Good shot, go again."
	else:
		current = other
		ball_in_hand = false
		message = "No ball potted: the other player's shot."
	return res


func _all_but_eight() -> Array:
	var a: Array = SOLIDS.duplicate()
	a.append_array(STRIPES)
	return a


# The shooter's group balls on the table before this shot (on_table is after it: add back what went down).
func _left_before(i: int, on_table: PackedByteArray, pocketed: Array) -> Array:
	var g := String(groups[i])
	var out: Array = []
	var down := {}
	for e: Array in pocketed:
		down[int(e[0])] = true
	for b: int in group_balls(g):
		if on_table[b] == 1 or down.has(b):
			out.append(b)
	return out


# (online) the state the host sends after a shot; the players' copies follow with from_dict().
func to_dict() -> Dictionary:
	return {"current": current, "groups": groups.duplicate(), "break_shot": break_shot, "ball_in_hand": ball_in_hand, "winner": winner, "message": message, "foul": foul}


func from_dict(d: Dictionary) -> void:
	current = int(d["current"])
	groups = (d["groups"] as Array).duplicate()
	break_shot = bool(d["break_shot"])
	ball_in_hand = bool(d["ball_in_hand"])
	winner = int(d["winner"])
	message = String(d["message"])
	foul = String(d["foul"])

