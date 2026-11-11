# Purpose: loads the appearance data files once and hands out the shared AppearanceDb.
# Dependencies: core/appearance_db.gd, core/data_store.gd, data/appearance.json, data/outfits.json, data/expressions.json, data/characters.json (rigged outfits and hair).
extends RefCounted

const AppearanceDb = preload("res://core/appearance_db.gd")
const DataStore = preload("res://core/data_store.gd")

static var _db: AppearanceDb


static func db() -> AppearanceDb:
	if _db == null:
		_db = AppearanceDb.new(
			DataStore.load_json("res://data/appearance.json"),
			DataStore.load_json("res://data/outfits.json"),
			DataStore.load_json("res://data/expressions.json"),
			DataStore.load_json("res://data/characters.json"))
	return _db
