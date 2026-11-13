# Purpose: developer simulator for the card game: the AI (core/tcg/ai_player.gd) plays every pair of starter decks
# (data/tcg/starters.json) against each other many times, half going first each, and reports win rates, the edge of
# going first, how long games last and how often each deck is still legal. Log tools/tcg_sim.log (TCG_SIM_DONE problems=n:
# a deck that is not legal, a game that did not end, or a script error count as problems).
# Dependencies: core/tcg/card_db.gd, core/tcg/match_state.gd, core/tcg/ai_player.gd.
extends Node

const CardDb = preload("res://core/tcg/card_db.gd")
const Match = preload("res://core/tcg/match_state.gd")
const Ai = preload("res://core/tcg/ai_player.gd")
const GAMES := 400  # per pair (a run may pass -- --games=N)

var _lines := PackedStringArray()
var _problems := 0


func _ready() -> void:
	var db: RefCounted = CardDb.from_files()
	var wrong: Array[String] = db.problems()
	_say("card data well formed%s" % ("" if wrong.is_empty() else ": " + "; ".join(wrong)), wrong.is_empty())
	var starters: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/starters.json")) as Dictionary)["starters"]
	for id: String in starters:
		var why: String = db.deck_problem(starters[id])
		_say("starter %s (%s) is legal%s" % [id, starters[id]["name"], "" if why == "" else ": " + why], why == "")
	var games := GAMES
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = int(arg.get_slice("=", 1))
	var ids := starters.keys()
	var first_wins := 0
	var total := 0
	for a in ids.size():
		for b in range(a + 1, ids.size()):
			var wins := [0, 0, 0]
			var turns := 0
			var unfinished := 0
			var first_won := 0
			for g in games:
				var first := g % 2
				var m: RefCounted = Match.new(db, [starters[ids[a]], starters[ids[b]]], 1000 + g, first)
				m.mulligan(0, Ai.mulligan(m, 0))
				m.mulligan(1, Ai.mulligan(m, 1))
				var guard := 0
				while m.get("phase") == "play" and guard < 80:
					Ai.take_turn(m, int(m.get("current")))
					guard += 1
				if m.get("phase") != "over":
					unfinished += 1
					continue
				var w := int(m.get("winner"))
				wins[w] += 1
				turns += int(m.get("turn"))
				if w == first:
					first_won += 1
			var played := games - unfinished
			first_wins += first_won
			total += played
			_say("%s vs %s: %d - %d (%d draws), first player won %.0f %%, %.1f turns a game" % [ids[a], ids[b], wins[0], wins[1], wins[2], 100.0 * float(first_won) / maxf(float(played), 1.0), float(turns) / maxf(float(played), 1.0)], unfinished == 0)
	_lines.append("all pairs: first player won %.1f %% of %d games" % [100.0 * float(first_wins) / maxf(float(total), 1.0), total])
	_lines.append("TCG_SIM_DONE problems=%d" % _problems)
	var f := FileAccess.open("res://tools/tcg_sim.log", FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	print("\n".join(_lines))
	get_tree().quit()


func _say(text: String, ok: bool) -> void:
	_lines.append(("ok   " if ok else "FAIL ") + text)
	if not ok:
		_problems += 1
