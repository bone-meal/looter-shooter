# Purpose: developer check of the boss trophies (polish1 E4): data problems (core/boss_trophy_db.gd problems against
# data/characters.json wear), every boss has a trophy + ghost + relic, the locker's spot rules (a boss trophy off when
# the circlet goes on, bracers + greaves stay), save and load, a dirty save cleaned, the appearance check. Prints
# BOSS_TROPHY_CHECK_DONE problems=n. Run: godot --headless --path . --script tools/boss_trophy_check.gd
extends SceneTree

const DataStore = preload("res://core/data_store.gd")
const BossTrophyDb = preload("res://core/boss_trophy_db.gd")
const BossTrophyLocker = preload("res://core/boss_trophy_locker.gd")
const AppearanceData = preload("res://game/appearance_data.gd")


func _init() -> void:
	var bad: Array = []
	var db := BossTrophyDb.new(DataStore.load_json("res://data/boss_trophies.json"))
	bad.append_array(db.problems(DataStore.load_json("res://data/characters.json")["wear"]))
	var enemies: Dictionary = DataStore.load_json("res://data/fantasy/enemies.json")["enemies"]
	var gear: Dictionary = DataStore.load_json("res://data/fantasy/gear.json")["items"]
	for id: String in enemies:
		if bool(enemies[id].get("boss", false)):
			if db.for_boss(id) == "" or db.ghost_of(id) == "":
				bad.append("boss %s: no trophy or ghost" % id)
			if not gear.has(String(enemies[id].get("relic", ""))):
				bad.append("boss %s: no relic in gear.json" % id)
	var lk := BossTrophyLocker.new(db)
	for id: String in ["harvest_king", "spectral_bracers", "spectral_greaves", "spectral_circlet"]:
		lk.add(id)
	lk.wear("harvest_king")
	lk.wear("spectral_bracers")
	lk.wear("spectral_greaves")
	if lk.worn != ["harvest_king", "spectral_bracers", "spectral_greaves"]:
		bad.append("wear three: %s" % str(lk.worn))
	lk.wear("spectral_circlet")  # takes the head: the crown + mantle come off
	if lk.worn.has("harvest_king") or not lk.worn.has("spectral_circlet") or lk.worn.size() != 3:
		bad.append("circlet over crown: %s" % str(lk.worn))
	if lk.wear("rootmother"):
		bad.append("wore a trophy not owned")
	var back := BossTrophyLocker.new(db)
	back.from_dict(lk.to_dict())
	if back.worn != lk.worn or back.order() != lk.order():
		bad.append("save and load: %s vs %s" % [str(back.to_dict()), str(lk.to_dict())])
	back.from_dict({"owned": ["harvest_king", "nope", 5], "worn": ["harvest_king", "nope", "rootmother"]})
	if back.order() != ["harvest_king"] or back.worn != ["harvest_king"]:
		bad.append("dirty save: %s" % str(back.to_dict()))
	var look: Dictionary = AppearanceData.db().sanitize({"gender": "female", "boss_trophies": ["harvest_king", "spectral_circlet", "spectral_bracers", "zzz"]})
	if look.get("boss_trophies", []) != ["harvest_king", "spectral_bracers"]:
		bad.append("appearance check: %s" % str(look.get("boss_trophies")))
	for line: String in bad:
		print("PROBLEM: ", line)
	print("trophies %d (with ghosts), spectral set %d" % [db.ids().size(), db.set_pieces("spectral").size()])
	print("BOSS_TROPHY_CHECK_DONE problems=%d" % bad.size())
	quit()
