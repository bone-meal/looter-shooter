# Purpose: turns the character's record (core/stat_book.gd) into the Combat Report's sections: what is shown, in which
# order, with which names. `ctx` hands in the names the record does not know: callables gun_name(body),
# knife_name(type), item_name(id), skill_name(id), enemy_name(id), and plain values best_round, course_best,
# quests_done, level, tcg_record (the card game record: vs / decks = {name: [wins, losses]}). Returns {"under_portrait": [lines], "sections": [{"title", "rows": [[label, value]]}]}.
# Dependencies: core/stat_book.gd.
extends RefCounted

const StatBook = preload("res://core/stat_book.gd")

const TOP := 12  # rows in the long lists (kills by enemy ...)


static func build(book: StatBook, ctx: Dictionary) -> Dictionary:
	var kills := book.total("kills")
	var shots := book.total("shots_fired")
	var deaths := book.total("deaths")
	var fav := book.favourite("kills_by_weapon")
	var combat := [
		["Kills", _n(kills)],
		["Headshots", "%s  (%s)" % [_n(book.total("headshots")), _pct(book.total("headshots"), kills)]],
		["Elite kills", _n(book.total("elite_kills"))],
		["Boss kills", _n(book.total("boss_kills"))],
		["Deaths", _n(deaths)],
		["Kills per death", "%.2f" % (kills / deaths) if deaths > 0.0 else "no deaths yet"],
		["Damage dealt", _n(book.total("damage_dealt"))],
		["Damage taken", _n(book.total("damage_taken"))],
		["Shots fired", _n(shots)],
		["Accuracy", _pct(book.total("shots_hit"), shots)],
		["Downs / revives given", "%s / %s" % [_n(book.total("downs")), _n(book.total("revives"))]],
		["Favourite weapon", _weapon(fav, ctx) if fav != "" else "none yet"],
	]
	var by_enemy: Array = []
	for pair: Array in book.top("kills_by_enemy", TOP):
		by_enemy.append([_call(ctx, "enemy_name", String(pair[0])), _n(float(pair[1]))])
	var by_weapon: Array = []
	for pair: Array in book.top("kills_by_weapon", TOP):
		by_weapon.append([_weapon(String(pair[0]), ctx), _n(float(pair[1]))])
	var islands := [
		["Rounds survived", _n(book.total("island_rounds"))],
		["Best round", str(int(ctx.get("best_round", 0)))],
		["Games over", _n(book.total("island_games_over"))],
		["Power-ups taken", _n(book.group_sum("powerups"))],
		["Perks bought", _n(book.total("perks_bought"))],
		["Debris cleared", _n(book.total("debris_cleared"))],
		["Boards nailed back", _n(book.total("boards_nailed"))],
		["Mystery box spins", _n(book.total("box_spins"))],
		["Guns re-forged", _n(book.total("upgrades"))],
		["Wall buys", _n(book.total("wall_buys"))],
		["Main quest finished", _n(book.total("main_quests"))],
		["Hidden songs found", _n(book.total("songs_found"))],
	]
	var colosseum := [
		["Runs started", _n(book.total("colosseum_runs"))],
		["Runs won", _n(book.total("colosseum_won"))],
		["Waves cleared", _n(book.total("colosseum_waves"))],
		["Longest run won", "%d waves" % int(book.total("colosseum_longest")) if book.total("colosseum_longest") > 0.0 else "none yet"],
		["Chests opened", _n(book.total("chests"))],
		["Rainbow and pony drops", _n(book.total("rare_drops"))],
		["Guns picked up", _n(book.total("guns_picked_up"))],
	]
	var aurelind: Array = [["Quests done", str(int(ctx.get("quests_done", 0)))], ["Spells cast", _n(book.total("spells_cast"))]]
	for pair: Array in book.top("skill_actions", 0):
		aurelind.append([_call(ctx, "skill_name", String(pair[0])), "%s times" % _n(float(pair[1]))])
	var gathered: Array = []
	for pair: Array in book.top("gathered", TOP):
		gathered.append([_call(ctx, "item_name", String(pair[0])), _n(float(pair[1]))])
	var made: Array = []
	for pair: Array in book.top("made", TOP):
		made.append([_call(ctx, "item_name", String(pair[0])), _n(float(pair[1]))])
	var lobster := [  # the card game (W/L per opponent and per deck: the two sections after it, from ctx tcg_record)
		["Matches played", _n(book.total("tcg_games"))],
		["Wins against players", _n(book.total("tcg_wins_player"))],
		["Best win streak", _n(book.total("tcg_best_streak"))],
		["House Dealer beaten", _n(book.total("tcg_wins_ai"))],
		["Flawless wins", _n(book.total("tcg_flawless"))],
		["Packs opened", _n(book.total("tcg_packs"))],
		["God packs", _n(book.total("tcg_god"))],
		["Foils pulled", _n(book.total("tcg_rainbow") + book.total("tcg_pony"))],
	]
	for pair: Array in book.top("tcg_wins_leader", 0):
		lobster.append(["Wins with %s" % _call(ctx, "leader_name", String(pair[0])), _n(float(pair[1]))])
	var tcg: Dictionary = ctx.get("tcg_record", {})
	var by_opponent := _wins_losses(tcg.get("vs", {}))
	var by_deck := _wins_losses(tcg.get("decks", {}))
	var time_rows := [
		["This session", StatBook.duration(book.session_seconds)],
		["In total", StatBook.duration(book.total("seconds_played"))],
		["Distance travelled", "%.1f km" % (book.total("metres") / 1000.0)],
		["Top speed", "%d u/s" % int(book.total("top_speed"))],
		["Hop course best", _clock(float(ctx.get("course_best", 0.0)))],
		["Hop course runs finished", _n(book.total("course_runs"))],
		["Cigarettes smoked", _n(book.total("cigarettes"))],
	]
	return {
		"under_portrait": ["Level %d" % int(ctx.get("level", 1)), "%s kills, %s deaths" % [_n(kills), _n(deaths)], "Played %s" % StatBook.duration(book.total("seconds_played"))],
		"sections": [
			{"title": "Combat", "rows": combat},
			{"title": "Kills by enemy", "rows": by_enemy},
			{"title": "Kills by weapon", "rows": by_weapon},
			{"title": "The islands", "rows": islands},
			{"title": "The colosseum", "rows": colosseum},
			{"title": "Time and travel", "rows": time_rows},
			{"title": "Aurelind", "rows": aurelind},
			{"title": "Gathered in Aurelind", "rows": gathered},
			{"title": "Made in Aurelind", "rows": made},
			{"title": "You got me Lobster?", "rows": lobster},
			{"title": "Card wins - losses by player", "rows": by_opponent},
			{"title": "Card wins - losses by deck", "rows": by_deck},
		],
	}


# The card game's record by opponent or by deck ({name: [wins, losses]}): the most played first, "W - L" each.
static func _wins_losses(table: Variant) -> Array:
	var rows: Array = []
	if not table is Dictionary:
		return [["Nothing yet.", ""]]
	var names: Array = (table as Dictionary).keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return _played(table[a]) > _played(table[b]))
	for name: Variant in names.slice(0, TOP):
		var row: Variant = table[name]
		if row is Array and (row as Array).size() >= 2:
			rows.append([String(name) if String(name) != "" else "(no name)", "%d - %d" % [int(row[0]), int(row[1])]])
	return rows if not rows.is_empty() else [["Nothing yet.", ""]]


static func _played(row: Variant) -> int:
	return int(row[0]) + int(row[1]) if row is Array and (row as Array).size() >= 2 else 0


# "gun:ak47" -> the gun's name, "knife:karambit" -> the knife's, "staff" and "other" as words.
static func _weapon(id: String, ctx: Dictionary) -> String:
	if id.begins_with("gun:"):
		return _call(ctx, "gun_name", id.substr(4))
	if id.begins_with("knife:"):
		return _call(ctx, "knife_name", id.substr(6))
	return String({"staff": "The staff", "skill": "Gun skills", "other": "Traps and the rest"}.get(id, id.capitalize()))


static func _call(ctx: Dictionary, what: String, id: String) -> String:
	var named: Variant = ctx.get(what)
	return String((named as Callable).call(id)) if named is Callable and (named as Callable).is_valid() else id.capitalize()


static func _n(value: float) -> String:
	var whole := roundi(value)
	var digits := str(absi(whole))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if whole < 0 else "") + digits + out


static func _pct(part: float, whole: float) -> String:
	return "%.1f %%" % (100.0 * part / whole) if whole > 0.0 else "-"


static func _clock(seconds: float) -> String:
	if seconds <= 0.0:
		return "none yet"
	var hundredths := roundi(seconds * 100.0)
	return "%d:%02d.%02d" % [floori(float(hundredths) / 6000.0), floori(float(hundredths) / 100.0) % 60, hundredths % 100]
