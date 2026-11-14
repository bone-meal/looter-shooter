# Purpose: what the card game writes into the combat record (core/stat_book.gd) for its achievements
# (diary/TCG_ACHIEVEMENTS.md, data/achievements.json "tcg_*"): matches played and won (against players and against the
# House Dealer apart), wins per leader and per faction, the House Dealer beaten with each starter deck, flawless and
# by-a-whisker wins, a full mat, packs, box packs, god packs and foils. Also the readings taken from the collection
# (leaders owned, the set owned, legal decks, mats owned). Pure: no nodes.
# Dependencies: core/stat_book.gd, core/tcg/card_db.gd, core/tcg/collection.gd, core/tcg/mat_book.gd (handed in / used).
extends RefCounted

const MatBook = preload("res://core/tcg/mat_book.gd")


# A match ended. side = ours in `m` (core/tcg/match_state.gd); vs_ai = against the House Dealer; starter = the
# starter deck id when ours was exactly one ("" otherwise); best_streak = the record's best win streak.
static func match_end(stats: RefCounted, m: RefCounted, side: int, vs_ai: bool, starter: String, best_streak: int) -> void:
	if stats == null:
		return
	stats.add("tcg_games")
	var winner := int(m.get("winner"))
	if winner != side:
		return
	var mine: Dictionary = (m.get("sides") as Array)[side]
	var leader := String(mine["leader"])
	stats.add("tcg_wins_ai" if vs_ai else "tcg_wins_player")
	if vs_ai and starter != "":
		stats.add_to("tcg_dealer_starter", starter)
	if not vs_ai:
		stats.best("tcg_best_streak", float(best_streak))
	stats.add_to("tcg_wins_leader", leader)
	var l: Dictionary = (m.get("db").get("leaders") as Dictionary).get(leader, {})
	stats.add_to("tcg_wins_faction", String(l.get("faction", "neutral")))
	if int(mine["hp"]) >= int(mine["max_hp"]):
		stats.add("tcg_flawless")
	elif int(mine["hp"]) == 1:
		stats.add("tcg_whisker")


# Seven creatures on our side (the table calls this once a match).
static func full_board(stats: RefCounted, m: RefCounted, side: int) -> bool:
	if stats == null or ((m.get("sides") as Array)[side]["board"] as Array).size() < int(m.get("rules")["board_max"]):
		return false
	stats.add("tcg_full_board")
	return true


# One pack opened: its cards ({"finish"}), whether it was a god pack, its kind.
static func pack(stats: RefCounted, cards: Array, god: bool, kind: String) -> void:
	if stats == null:
		return
	stats.add("tcg_packs")
	if kind == "box":
		stats.add("tcg_box_packs")
	if god:
		stats.add("tcg_god")
	for c: Dictionary in cards:
		if String(c.get("finish", "")) == "rainbow":
			stats.add("tcg_rainbow")
		elif String(c.get("finish", "")) == "pony":
			stats.add("tcg_pony")


# Readings from the collection for "ctx:" achievements.
static func readings(owned: RefCounted, db: RefCounted, mats: Dictionary) -> Dictionary:
	var leaders := 0
	for id: String in owned.get("leaders"):
		if int(owned.call("count", id, "*", true)) > 0:
			leaders += 1
	var cards := 0
	for id: String in owned.get("cards"):
		var c: Dictionary = db.card(id)
		if not c.is_empty() and String(c["rarity"]) != "token" and int(owned.call("count", id)) > 0:
			cards += 1
	var mat_count := 0
	for id: String in mats.get("mats", {}):
		if MatBook.owns(owned, mats, id):
			mat_count += 1
	return {"tcg_leaders_owned": leaders, "tcg_set_owned": cards + leaders, "tcg_legal_decks": (owned.call("playable", db) as Dictionary).size(), "tcg_mats_owned": mat_count}
