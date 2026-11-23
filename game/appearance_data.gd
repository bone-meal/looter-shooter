# Purpose: loads the appearance data files once and hands out the shared AppearanceDb.
# Dependencies: core/appearance_db.gd, core/data_store.gd, data/appearance.json, data/outfits.json, data/expressions.json, data/characters.json (rigged outfits and hair), data/masks.json (mask ids), core/boss_trophy_db.gd + data/boss_trophies.json (worn boss trophies).
extends RefCounted

const AppearanceDb = preload("res://core/appearance_db.gd")
const DataStore = preload("res://core/data_store.gd")
const BossTrophyDb = preload("res://core/boss_trophy_db.gd")

static var _db: AppearanceDb
static var _trophies: BossTrophyDb


static func db() -> AppearanceDb:
	if _db == null:
		_db = AppearanceDb.new(
			DataStore.load_json("res://data/appearance.json"),
			DataStore.load_json("res://data/outfits.json"),
			DataStore.load_json("res://data/expressions.json"),
			DataStore.load_json("res://data/characters.json"))
		for id: String in (DataStore.load_json("res://data/masks.json").get("masks", {}) as Dictionary):
			_db.mask_ids[id] = true
		_db.boss_trophies = trophies()
	return _db


# (polish1 E4) The boss trophies' rules (data/boss_trophies.json), shared.
static func trophies() -> BossTrophyDb:
	if _trophies == null:
		_trophies = BossTrophyDb.new(DataStore.load_json("res://data/boss_trophies.json"))
	return _trophies
