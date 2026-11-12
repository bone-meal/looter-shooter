# Purpose: saves and loads the local profile (player name + inventory/equipment) with an HMAC signature: into the chosen
# save slot (`active`), or user://profile.sav when no slot is chosen.
# Dependencies: game/appearance_data.gd, core/profile_sign.gd, core/inventory_state.gd, core/item_db.gd, core/data_store.gd.
extends RefCounted

const ProfileSign = preload("res://core/profile_sign.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const DataStore = preload("res://core/data_store.gd")
const AppearanceData = preload("res://game/appearance_data.gd")

const PATH := "user://profile.sav"
const FORMAT := 1

# The chosen save slot's file (game/save_slots.gd `choose`). While set, every save and load goes there whatever the key.
static var active := ""


# Without a slot (scripted developer runs): one save file per typed name; "" = the original single file.
static func path_for(key: String) -> String:
	if active != "":
		return active
	var safe := ""
	for ch in key.strip_edges().to_lower().substr(0, 20):
		safe += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return PATH if safe.is_empty() else "user://profile_%s.sav" % safe


# Set by load_profile(): "", "tampered" (signature wrong) or "unreadable".
static var last_problem := ""


static func save(player_name: String, inv: Dictionary, look: Dictionary = {}, key := "", extra: Dictionary = {}) -> void:
	var payload := JSON.stringify({"format": FORMAT, "name": player_name, "inv": inv, "look": look, "extra": extra}, "", true)
	var f := FileAccess.open(path_for(key), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"data": payload, "sig": ProfileSign.sign_payload(payload)}))


# Returns {"name": String, "inv": Dictionary, "look": Dictionary, "extra": Dictionary (casino coins/jackpot)} or {} when there is no usable save (see last_problem).
static func load_profile(key := "") -> Dictionary:
	return read(path_for(key))


# The same for one named file.
static func read(path: String) -> Dictionary:
	last_problem = ""
	if not FileAccess.file_exists(path):
		return {}
	var outer: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (outer is Dictionary) or not (outer.get("data") is String) or not (outer.get("sig") is String):
		last_problem = "unreadable"
		return {}
	if not ProfileSign.verify(outer["data"], outer["sig"]):
		last_problem = "tampered"
		return {}
	var inner: Variant = JSON.parse_string(outer["data"])
	if not (inner is Dictionary) or not (inner.get("inv") is Dictionary):
		last_problem = "unreadable"
		return {}
	var look: Dictionary = {}
	if inner.get("look") is Dictionary:
		look = inner["look"]
	var extra: Dictionary = {}
	if inner.get("extra") is Dictionary:
		extra = inner["extra"]
	return {"name": String(inner.get("name", "")), "inv": inner["inv"], "look": look, "extra": extra}


# The profile to show other players: the saved one if it is valid, else a fresh character with the starting items.
# The inventory is passed through InventoryState so numbers come back as ints.
static func current(player_name: String) -> Dictionary:
	var db := ItemDb.new(DataStore.load_json("res://data/items.json"))
	var inv := InventoryState.new(db)
	var saved := load_profile(player_name)
	var look: Dictionary = {}
	var progress: Dictionary = {}
	if saved.is_empty():
		for entry in DataStore.load_json("res://data/player.json")["starting_items"]:
			inv.add(String(entry[0]), int(entry[1]))
	else:
		inv.from_dict(saved["inv"])
		look = saved["look"]
		if (saved["extra"] as Dictionary).get("progress") is Dictionary:
			progress = (saved["extra"] as Dictionary)["progress"]
		if player_name == "":
			player_name = String(saved["name"])
	if player_name == "":
		player_name = "Player%d" % randi_range(1000, 9999)
	return {"name": player_name.strip_edges().substr(0, 20), "inv": inv.to_dict(), "look": AppearanceData.db().sanitize(look), "progress": progress}
