# Purpose: pure player progression rules: XP and level, stat points, traits, achievement counters and unlocks, and the player card (callsign, emblem, title). Also sanitizes a loaded save and lets the host validate a joiner's progress. No nodes, no rendering.
# Dependencies: none (config comes from data/progression.json and data/achievements.json, passed to the constructor).
extends RefCounted

var xp := 0
var spent := {}  # stat id -> points spent
var traits: Array = []  # trait id per slot ("" = empty)
var counters := {}  # counter id -> int
var stat_values := {}  # "stat" achievement key -> the highest reading seen (core/achievement_reader.gd)
var unlocked: Array = []  # achievement ids
var callsign := ""
var emblem := ""
var title := ""

var _cfg: Dictionary
var _ach: Dictionary
var _level := 1
var _into := 0  # xp earned inside the current level
var _need := 0  # xp this level needs (0 at max level)
var _fresh: Array = []  # achievements unlocked since the last take_unlocked()


func _init(progression: Dictionary, achievements: Dictionary) -> void:
	_cfg = progression
	_ach = achievements
	emblem = String(_ach["default_emblem"])
	title = String(_ach["default_title"])
	for id: String in _cfg["stats"]:
		spent[id] = 0
	for _i in (_cfg["trait_slot_levels"] as Array).size():
		traits.append("")
	_recalc()


# --- level ---

func level() -> int:
	return _level


func xp_into_level() -> int:
	return _into


func xp_for_level() -> int:
	return _need


func _xp_needed(at_level: int) -> int:
	return roundi(float(_cfg["xp_base"]) * pow(float(_cfg["xp_growth"]), float(at_level - 1)))


func _level_for(total_xp: int) -> int:
	var lvl := 1
	var left := total_xp
	while lvl < int(_cfg["max_level"]):
		var need := _xp_needed(lvl)
		if left < need:
			break
		left -= need
		lvl += 1
	return lvl


func _recalc() -> void:
	var lvl := 1
	var left := xp
	var max_level := int(_cfg["max_level"])
	while lvl < max_level and left >= _xp_needed(lvl):
		left -= _xp_needed(lvl)
		lvl += 1
	_level = lvl
	_into = left
	_need = _xp_needed(lvl) if lvl < max_level else 0


# Adds XP (with the Scholar-style xp_pct bonus). Returns how many levels were gained.
func add_xp(amount: int) -> int:
	var before := _level
	xp += roundi(float(amount) * (1.0 + bonus("xp_pct") / 100.0))
	_recalc()
	if _level != before:
		_check("level")
	return _level - before


# --- points, stats, traits ---

func points_total() -> int:
	return (_level - 1) * int(_cfg["points_per_level"])


func points_spent() -> int:
	var n := 0
	for id: String in spent:
		n += int(spent[id])
	return n


func points_left() -> int:
	return points_total() - points_spent()


func spend(stat: String) -> bool:
	if not _cfg["stats"].has(stat) or points_left() <= 0:
		return false
	if int(spent[stat]) >= int((_cfg["stats"][stat] as Dictionary)["cap"]):
		return false
	spent[stat] = int(spent[stat]) + 1
	return true


func reset_stats() -> void:
	for id: String in spent:
		spent[id] = 0


func trait_slots_open() -> int:
	var n := 0
	for lvl: Variant in _cfg["trait_slot_levels"]:
		if _level >= int(lvl):
			n += 1
	return n


func set_trait(slot: int, id: String) -> bool:
	if slot < 0 or slot >= trait_slots_open():
		return false
	if id != "":
		if not _cfg["traits"].has(id):
			return false
		for i in traits.size():
			if i != slot and traits[i] == id:
				return false
	traits[slot] = id
	return true


# Sum of every stat and trait bonus for an effect key (max_hp_pct, damage_pct, speed_pct, luck_pct, xp_pct).
func bonus(effect: String) -> float:
	var total := 0.0
	var stats: Dictionary = _cfg["stats"]
	for id: String in stats:
		var def: Dictionary = stats[id]
		if String(def["effect"]) == effect:
			total += float(spent[id]) * float(def["per_point"])
	var defs: Dictionary = _cfg["traits"]
	for i in traits.size():
		var t := String(traits[i])
		if t != "" and i < trait_slots_open() and defs.has(t) and String((defs[t] as Dictionary)["effect"]) == effect:
			total += float((defs[t] as Dictionary)["value"])
	return total


# --- achievements and the card ---

func count(counter: String, amount: int = 1) -> void:
	counters[counter] = int(counters.get(counter, 0)) + amount
	_check(counter)


func value_of(counter: String) -> int:
	return _level if counter == "level" else int(counters.get(counter, 0))


# How far an achievement has got: its counter, or its stat reading.
func progress_of(a: Dictionary) -> int:
	return int(stat_values.get(String(a["stat"]), 0)) if a.has("stat") else value_of(String(a["counter"]))


func _check(counter: String) -> void:
	var all: Dictionary = _ach["achievements"]
	for id: String in all:
		var a: Dictionary = all[id]
		if String(a.get("counter", "")) == counter and not unlocked.has(id) and value_of(counter) >= int(a["goal"]):
			unlocked.append(id)
			_fresh.append(id)


# Every key the "stat" achievements read (the session reads these from the combat record).
func stat_keys() -> Array:
	var out: Array = []
	for id: String in _ach["achievements"]:
		var a: Dictionary = _ach["achievements"][id]
		if a.has("stat") and not out.has(String(a["stat"])):
			out.append(String(a["stat"]))
	return out


# New readings (key -> int): each keeps its highest value, then stat achievements that reached their goal unlock.
func read_stats(values: Dictionary) -> void:
	for key: String in values:
		stat_values[key] = maxi(int(stat_values.get(key, 0)), int(values[key]))
	var all: Dictionary = _ach["achievements"]
	for id: String in all:
		var a: Dictionary = all[id]
		if a.has("stat") and not unlocked.has(id) and progress_of(a) >= int(a["goal"]):
			unlocked.append(id)
			_fresh.append(id)


# Whether achievement `a` is earned by these counters, stat readings and level (loading and the host check).
func _earned(a: Dictionary, counts: Dictionary, stats: Dictionary, lvl: int) -> bool:
	if a.has("stat"):
		return int(stats.get(String(a["stat"]), 0)) >= int(a["goal"])
	var counter := String(a["counter"])
	return (lvl if counter == "level" else int(counts.get(counter, 0))) >= int(a["goal"])


# Achievements unlocked since the last call (the session shows a notice for each).
func take_unlocked() -> Array:
	var out := _fresh
	_fresh = []
	return out


func emblems_open() -> Array:
	var out: Array = [String(_ach["default_emblem"])]
	for id: String in unlocked:
		var e := String((_ach["achievements"][id] as Dictionary)["emblem"])
		if e != "" and not out.has(e):
			out.append(e)
	return out


func titles_open() -> Array:
	var out: Array = [String(_ach["default_title"])]
	for id: String in unlocked:
		var t := String((_ach["achievements"][id] as Dictionary)["title"])
		if t != "" and not out.has(t):
			out.append(t)
	return out


func clean_callsign(raw: String) -> String:
	var out := ""
	var text := raw.strip_edges()
	for i in text.length():
		var ch: String = text[i]
		if ch.is_valid_identifier() or ch == " " or ch == "-" or ch.is_valid_int():
			out += ch
	return out.substr(0, int(_cfg["callsign_max"]))


func set_card(new_callsign: String, emblem_id: String, title_id: String) -> void:
	callsign = clean_callsign(new_callsign)
	if emblems_open().has(emblem_id):
		emblem = emblem_id
	if titles_open().has(title_id):
		title = title_id


# --- lookups for the UI ---

func emblem_def(id: String) -> Dictionary:
	return _ach["emblems"].get(id, _ach["emblems"][_ach["default_emblem"]])


func title_name(id: String) -> String:
	return String(_ach["titles"].get(id, id))


func achievement_defs() -> Dictionary:
	return _ach["achievements"]


func stat_defs() -> Dictionary:
	return _cfg["stats"]


func trait_defs() -> Dictionary:
	return _cfg["traits"]


func trait_unlock_level(slot: int) -> int:
	return int((_cfg["trait_slot_levels"] as Array)[slot])


func callsign_max() -> int:
	return int(_cfg["callsign_max"])


func xp_reward(kind: String) -> int:
	return int((_cfg["xp"] as Dictionary).get(kind, 0))


func stat_text(id: String) -> String:
	var def: Dictionary = _cfg["stats"][id]
	return String(def["desc"]).replace("{v}", "%.0f" % (float(spent[id]) * float(def["per_point"])))


# --- save and validation ---

func to_dict() -> Dictionary:
	return {"v": 1, "xp": xp, "spent": spent.duplicate(), "traits": traits.duplicate(), "counters": counters.duplicate(), "stats": stat_values.duplicate(),
		"unlocked": unlocked.duplicate(), "card": {"callsign": callsign, "emblem": emblem, "title": title}}


# Loads a saved dictionary, dropping or clamping anything invalid (a damaged or edited file never breaks the game).
func from_dict(d: Variant) -> void:
	if not d is Dictionary:
		return
	var src: Dictionary = d
	xp = maxi(int(src.get("xp", 0)), 0)
	_recalc()
	var stats: Dictionary = _cfg["stats"]
	var left := points_total()
	var saved_spent: Dictionary = src["spent"] if src.get("spent") is Dictionary else {}
	for id: String in stats:
		var n := clampi(int(saved_spent.get(id, 0)), 0, mini(int((stats[id] as Dictionary)["cap"]), left))
		spent[id] = n
		left -= n
	counters = {}
	if src.get("counters") is Dictionary:
		for key: String in src["counters"]:
			counters[key] = maxi(int(src["counters"][key]), 0)
	stat_values = {}
	if src.get("stats") is Dictionary:
		var keys := stat_keys()
		for key: String in src["stats"]:
			if keys.has(key):
				stat_values[key] = maxi(int(src["stats"][key]), 0)
	unlocked = []
	if src.get("unlocked") is Array:
		for id: Variant in src["unlocked"]:
			var a: Variant = _ach["achievements"].get(String(id))
			if a is Dictionary and _earned(a, counters, stat_values, _level) and not unlocked.has(String(id)):
				unlocked.append(String(id))
	var open := trait_slots_open()
	for i in traits.size():
		traits[i] = ""
	if src.get("traits") is Array:
		var list: Array = src["traits"]
		for i in mini(list.size(), open):
			var t := String(list[i])
			if t != "" and _cfg["traits"].has(t) and not traits.has(t):
				traits[i] = t
	var card: Dictionary = src["card"] if src.get("card") is Dictionary else {}
	set_card(String(card.get("callsign", "")), String(card.get("emblem", "")), String(card.get("title", "")))


# Host-side check of a joiner's progress: "" when valid, otherwise what is wrong.
func check(d: Variant) -> String:
	if not d is Dictionary:
		return "progress missing"
	var src: Dictionary = d
	var xp_raw: Variant = src.get("xp", 0)
	if not (xp_raw is int or xp_raw is float) or float(xp_raw) < 0.0:
		return "bad xp"
	var lvl := _level_for(int(xp_raw))
	var points := (lvl - 1) * int(_cfg["points_per_level"])
	var used := 0
	var spent_raw: Variant = src.get("spent", {})
	if spent_raw is Dictionary:
		for id: String in spent_raw:
			if not _cfg["stats"].has(id):
				return "unknown stat %s" % id
			var n := int(spent_raw[id])
			if n < 0 or n > int((_cfg["stats"][id] as Dictionary)["cap"]):
				return "stat %s out of range" % id
			used += n
	if used > points:
		return "too many stat points"
	var slots := 0
	for need: Variant in _cfg["trait_slot_levels"]:
		if lvl >= int(need):
			slots += 1
	var seen: Array = []
	var trait_raw: Variant = src.get("traits", [])
	if trait_raw is Array:
		for i in (trait_raw as Array).size():
			var t := String(trait_raw[i])
			if t == "":
				continue
			if i >= slots or not _cfg["traits"].has(t) or seen.has(t):
				return "bad trait %s" % t
			seen.append(t)
	var counter_raw: Variant = src.get("counters", {})
	var counts: Dictionary = counter_raw if counter_raw is Dictionary else {}
	var stats_raw: Variant = src.get("stats", {})
	var stats: Dictionary = stats_raw if stats_raw is Dictionary else {}
	var open_emblems: Array = [String(_ach["default_emblem"])]
	var open_titles: Array = [String(_ach["default_title"])]
	var unlocked_raw: Variant = src.get("unlocked", [])
	if unlocked_raw is Array:
		for id: Variant in unlocked_raw:
			var a: Variant = _ach["achievements"].get(String(id))
			if not a is Dictionary:
				return "unknown achievement"
			if not _earned(a, counts, stats, lvl):
				return "achievement %s not earned" % String(id)
			open_emblems.append(String((a as Dictionary)["emblem"]))
			open_titles.append(String((a as Dictionary)["title"]))
	var card_raw: Variant = src.get("card", {})
	if card_raw is Dictionary:
		var card: Dictionary = card_raw
		if not open_emblems.has(String(card.get("emblem", _ach["default_emblem"]))):
			return "emblem not unlocked"
		if not open_titles.has(String(card.get("title", _ach["default_title"]))):
			return "title not unlocked"
		if String(card.get("callsign", "")).length() > int(_cfg["callsign_max"]):
			return "callsign too long"
	return ""
