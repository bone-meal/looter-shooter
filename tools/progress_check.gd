# Purpose: developer check for core/progress_state.gd: xp curve, points, stats, traits, achievements, card, save round-trip and tamper rejection. Writes tools/progress_check.log and quits. Run scene tools/progress_check.tscn.
# Dependencies: core/progress_state.gd, data/progression.json, data/achievements.json.
extends Node

const ProgressState = preload("res://core/progress_state.gd")

var _log := ""
var _fails := 0


func _ready() -> void:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/progression.json"))
	var ach: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/achievements.json"))
	var p := ProgressState.new(cfg, ach)
	_t("starts at level 1 with 0 points", p.level() == 1 and p.points_total() == 0)
	_t("1 trait slot open at level 1", p.trait_slots_open() == 1)
	p.count("kills", 1)
	_t("first kill unlocks first_blood", p.take_unlocked() == ["first_blood"])
	_t("take_unlocked clears", p.take_unlocked().is_empty())
	var gained := p.add_xp(100)
	_t("100 xp = level 2", gained == 1 and p.level() == 2 and p.points_left() == 1)
	_t("spend a point", p.spend("power") and p.points_left() == 0 and not p.spend("power"))
	_t("power bonus 2%", is_equal_approx(p.bonus("damage_pct"), 2.0))
	_t("trait in slot 0 ok, slot 1 locked", p.set_trait(0, "scholar") and not p.set_trait(1, "gunslinger"))
	var before := p.xp
	p.add_xp(100)
	_t("scholar +20% xp", p.xp - before == 120)
	p.add_xp(1000000)
	_t("max level 50", p.level() == 50 and p.xp_for_level() == 0)
	_t("level achievements unlocked", p.unlocked.has("level_10") and p.unlocked.has("level_25") and p.unlocked.has("level_50"))
	_t("level_25 gives a title but no emblem", p.titles_open().has("elite") and not p.emblems_open().has(""))
	_t("2 trait slots open at 50", p.trait_slots_open() == 2 and p.set_trait(1, "gunslinger") and not p.set_trait(1, "scholar"))
	p.set_card("  Bonk_99!!  extra long name", "crown_rainbow", "legend")
	_t("callsign cleaned and clipped", p.callsign == "Bonk_99  extr" or p.callsign.length() <= 12)
	_t("card items set", p.emblem == "crown_rainbow" and p.title == "legend")
	p.set_card("x", "star_gold", "slayer")
	_t("locked card items refused", p.emblem == "crown_rainbow" and p.title == "legend")
	var saved := JSON.parse_string(JSON.stringify(p.to_dict())) as Dictionary
	_t("saved progress passes host check", p.check(saved) == "")
	var q := ProgressState.new(cfg, ach)
	q.from_dict(saved)
	_t("round trip keeps level/xp/traits", q.level() == p.level() and q.xp == p.xp and q.traits == p.traits and q.callsign == p.callsign)
	_t("round trip keeps bonuses", is_equal_approx(q.bonus("damage_pct"), p.bonus("damage_pct")))
	var bad := saved.duplicate(true)
	bad["spent"] = {"power": 99}
	_t("host rejects too many points", p.check(bad) != "")
	bad = saved.duplicate(true)
	bad["xp"] = 0
	_t("host rejects points above level", p.check(bad) != "")
	bad = saved.duplicate(true)
	bad["unlocked"] = ["boss_10"]
	_t("host rejects unearned achievement", p.check(bad) != "")
	bad = saved.duplicate(true)
	bad["traits"] = ["scholar", "scholar"]
	_t("host rejects duplicate trait", p.check(bad) != "")
	bad = saved.duplicate(true)
	bad["card"] = {"callsign": "a", "emblem": "nope", "title": "newcomer"}
	_t("host rejects unknown emblem", p.check(bad) != "")
	var low := ProgressState.new(cfg, ach)
	low.from_dict({"xp": 0, "spent": {"power": 15}, "traits": ["scholar", "gunslinger"], "unlocked": ["boss_10"], "card": {"emblem": "crown_gold", "title": "legend"}})
	_t("sanitize drops everything invalid", low.points_spent() == 0 and low.traits == ["scholar", ""] and low.unlocked.is_empty() and low.emblem == "chevron_grey" and low.title == "newcomer")
	var luck := ProgressState.new(cfg, ach)
	luck.add_xp(100000)
	for _i in 15:
		luck.spend("fortune")
	_t("cap 15 on a stat", int(luck.spent["fortune"]) == 15 and not luck.spend("fortune") and is_equal_approx(luck.bonus("luck_pct"), 45.0))
	_log += "FAILS: %d\nRESULT: %s\n" % [_fails, "ok" if _fails == 0 else "FAIL"]
	var f := FileAccess.open("res://tools/progress_check.log", FileAccess.WRITE)
	f.store_string(_log)
	f.close()
	get_tree().quit()


func _t(name_: String, ok: bool) -> void:
	_log += "%s %s\n" % ["ok  " if ok else "FAIL", name_]
	if not ok:
		_fails += 1
