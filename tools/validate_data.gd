# Purpose: check data/*.json files for required keys and sane numbers.
# Dependencies: none. Run: godot --headless --script tools/validate_data.gd
extends SceneTree

const WEAPON_KEYS := ["damage", "fire_rate", "mag_size", "reload_time", "spread"]
const ENEMY_KEYS := ["max_hp", "speed", "damage", "attack_range", "attack_interval"]
const RANGED_KEYS := ["projectile_speed", "burst"]
const ARMOR_SLOTS := ["hat", "head", "earrings", "necklace", "glasses", "mouth", "shirt", "chestplate", "gauntlets", "ring", "bracelet", "pants", "leg_armor", "cape", "waist", "boots", "foot_armor"]

func _init() -> void:
	var errors := 0
	errors += _check_weapons("res://data/weapons.json")
	errors += _check_enemies("res://data/enemies.json")
	errors += _check_waves("res://data/waves.json", "res://data/enemies.json")
	errors += _check_player("res://data/player.json")
	errors += _check_world_data("res://data/elements.json", "res://data/crow.json", "res://data/items.json")
	errors += _check_items("res://data/items.json", "res://data/weapons.json", "res://data/loot_tables.json", "res://data/player.json")
	if errors == 0:
		print("Data OK")
	else:
		printerr("Data invalid: %d error(s)" % errors)
	quit(1 if errors > 0 else 0)

func _load(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func _check_weapons(path: String) -> int:
	var data := _load(path)
	if data.is_empty() or not data.has("version") or not data.has("weapons"):
		printerr("%s: missing file, version or weapons" % path)
		return 1
	var errors := 0
	var items: Dictionary = _load("res://data/items.json").get("items", {})
	for id in items:
		if items[id].get("kind", "") != "weapon":
			continue
		if not data["weapons"].has(id):
			printerr("%s: weapon item '%s' has no stats" % [path, id])
			errors += 1
		else:
			var v: Dictionary = data["weapons"][id].get("view", {})
			var ads = v.get("ads_position", [])
			if not (ads is Array) or ads.size() != 3 or not _is_positive(v.get("ads_fov", 0)):
				printerr("%s: slot weapon '%s' needs view.ads_position (3 numbers) and view.ads_fov" % [path, id])
				errors += 1
	for id in data["weapons"]:
		var w: Dictionary = data["weapons"][id]
		for key in WEAPON_KEYS:
			if not w.has(key) or typeof(w[key]) not in [TYPE_INT, TYPE_FLOAT] or w[key] <= 0:
				printerr("%s: weapon '%s' bad or missing '%s'" % [path, id, key])
				errors += 1
	return errors

func _check_items(items_path: String, weapons_path: String, loot_path: String, player_path: String) -> int:
	var data := _load(items_path)
	if data.is_empty() or not data.has("items"):
		printerr("%s: missing file or items" % items_path)
		return 1
	var errors := 0
	var weapons: Dictionary = _load(weapons_path).get("weapons", {})
	for id in data["items"]:
		var it: Dictionary = data["items"][id]
		for key in ["name", "flavor"]:
			if typeof(it.get(key, null)) != TYPE_STRING or it[key] == "":
				printerr("%s: item '%s' needs text '%s'" % [items_path, id, key])
				errors += 1
		if not it.get("kind", "") in ["weapon", "loot", "armor"]:
			printerr("%s: item '%s' kind must be weapon, loot or armor" % [items_path, id])
			errors += 1
		if not _is_positive(it.get("stack_max", 0)) or (it.get("kind", "") in ["weapon", "armor"] and it.get("stack_max", 0) != 1):
			printerr("%s: item '%s' bad stack_max (weapons must be 1)" % [items_path, id])
			errors += 1
		if it.get("kind", "") == "armor" and not it.get("slot", "") in ARMOR_SLOTS:
			printerr("%s: armor '%s' needs a valid slot" % [items_path, id])
			errors += 1
		if it.get("kind", "") == "weapon" and not weapons.has(id):
			printerr("%s: weapon item '%s' missing from weapons.json" % [items_path, id])
			errors += 1
	var tables: Dictionary = _load(loot_path).get("tables", {})
	for table_id in tables:
		for entry in tables[table_id]:
			var ids: Array = []
			if entry.has("pick_one"):
				for option in entry["pick_one"]:
					ids.append(option.get("item", ""))
					if not _is_positive(option.get("weight", 0)):
						printerr("%s: bad weight in table '%s'" % [loot_path, table_id])
						errors += 1
			else:
				ids.append(entry.get("item", ""))
			for item_id in ids:
				if not data["items"].has(item_id):
					printerr("%s: unknown item '%s' in table '%s'" % [loot_path, item_id, table_id])
					errors += 1
			if not (entry.get("chance", -1) >= 0 and entry.get("chance", 2) <= 1) or not (entry.get("min", 0) >= 1 and entry.get("max", 0) >= entry.get("min", 1)):
				printerr("%s: bad chance/min/max in table '%s'" % [loot_path, table_id])
				errors += 1
	for entry in _load(player_path).get("starting_items", []):
		if not (entry is Array) or entry.size() != 2 or not data["items"].has(entry[0]):
			printerr("%s: bad starting_items entry" % player_path)
			errors += 1
	return errors


func _check_world_data(elements_path: String, crow_path: String, items_path: String) -> int:
	var errors := 0
	var elements := _load(elements_path)
	if not elements.has("elements") or not (elements.get("chance", -1) >= 0 and elements.get("chance", 2) <= 1):
		printerr("%s: needs 'elements' and a chance between 0 and 1" % elements_path)
		errors += 1
	else:
		for e in elements["elements"]:
			var d: Dictionary = elements["elements"][e]
			if not _is_positive(d.get("weight", 0)) or not (d.get("tint", []) is Array) or d["tint"].size() != 3:
				printerr("%s: element '%s' needs weight and tint [r,g,b]" % [elements_path, e])
				errors += 1
	var crow := _load(crow_path)
	var items: Dictionary = _load(items_path).get("items", {})
	if not items.has(crow.get("food_item", "")) or not _is_positive(crow.get("worms_needed", 0)) or not _is_positive(crow.get("flight_seconds", 0)) or not _is_positive(crow.get("altitude", 0)):
		printerr("%s: needs a known food_item and positive worms_needed, flight_seconds, altitude" % crow_path)
		errors += 1
	return errors

func _is_positive(v) -> bool:
	return typeof(v) in [TYPE_INT, TYPE_FLOAT] and v > 0

func _check_enemies(path: String) -> int:
	var data := _load(path)
	if data.is_empty() or not data.has("version") or not data.has("enemies"):
		printerr("%s: missing file, version or enemies" % path)
		return 1
	var errors := 0
	for id in data["enemies"]:
		var e: Dictionary = data["enemies"][id]
		var keys: Array = ENEMY_KEYS.duplicate()
		if e.get("attack_type", "") == "ranged":
			keys.append_array(RANGED_KEYS)
		elif e.get("attack_type", "") != "melee":
			printerr("%s: enemy '%s' attack_type must be melee or ranged" % [path, id])
			errors += 1
		for key in keys:
			if not e.has(key) or not _is_positive(e[key]):
				printerr("%s: enemy '%s' bad or missing '%s'" % [path, id, key])
				errors += 1
		for key in ["size", "color"]:
			if not e.has(key) or not (e[key] is Array) or e[key].size() != 3:
				printerr("%s: enemy '%s' needs '%s' as 3 numbers" % [path, id, key])
				errors += 1
	return errors

func _check_waves(path: String, enemies_path: String) -> int:
	var data := _load(path)
	var enemies := _load(enemies_path)
	if data.is_empty() or not data.has("waves") or not enemies.has("enemies"):
		printerr("%s: missing file or waves" % path)
		return 1
	var errors := 0
	for key in ["max_alive", "spawn_interval", "wave_delay", "reset_after_clear_seconds"]:
		if not data.has(key) or not _is_positive(data[key]):
			printerr("%s: bad or missing '%s'" % [path, key])
			errors += 1
	for wave in data["waves"]:
		for id in wave:
			if not enemies["enemies"].has(id) or not _is_positive(wave[id]):
				printerr("%s: wave uses unknown enemy or bad count '%s'" % [path, id])
				errors += 1
	return errors

func _check_player(path: String) -> int:
	var data := _load(path)
	var errors := 0
	for key in ["max_hp", "sprint_multiplier"]:
		if not data.has(key) or not _is_positive(data[key]):
			printerr("%s: bad or missing %s" % [path, key])
			errors += 1
	return errors
