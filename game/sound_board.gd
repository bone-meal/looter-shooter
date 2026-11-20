# Purpose: one switchboard for every sound of the game: which ones the player has muted (settings) and which ones are
# being heard right now (shown on the Sounds page of the settings, game/sound_menu.gd). Whoever plays a sound asks
# `allow(id)` first and calls `heard(id)` when it is really audible. Ids, labels and groups: data/sound_list.json.
# (polish1 item 3) Each group has a volume of its own (settings `sound_groups`): players add `gain_db(id)`.
# Dependencies: none.
extends RefCounted

static var muted := {}  # sound id -> true
static var _last := {}  # sound id -> engine milliseconds when it was last audible
static var _latest := 0
static var _group_of := {}  # sound id -> its group's name (data/sound_list.json), read once
static var _volumes := {}  # group name -> 0..1 (missing = 1)


static func allow(id: String) -> bool:
	return not muted.has(id)


static func heard(id: String) -> void:
	_last[id] = Time.get_ticks_msec()
	_latest = Time.get_ticks_msec()


# When anything at all was last audible (engine milliseconds).
static func latest() -> int:
	return _latest


# True when the sound was audible within `within_ms` before the moment `at_ms`.
static func hearing(id: String, at_ms: int, within_ms: int) -> bool:
	return _last.has(id) and at_ms - int(_last[id]) <= within_ms


# Takes the muted list of the settings (core/settings_state.gd `muted_sounds`).
static func set_muted(ids: Array) -> void:
	muted.clear()
	for id: Variant in ids:
		muted[String(id)] = true


# Takes the group volumes of the settings (core/settings_state.gd `sound_groups`).
static func set_groups(volumes: Dictionary) -> void:
	_volumes = volumes.duplicate()


# How much louder or softer this sound plays for its group's volume (decibels; 0 = as made).
static func gain_db(id: String) -> float:
	if _group_of.is_empty():
		var list: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sound_list.json"))
		if list is Dictionary:
			for group: Dictionary in (list as Dictionary).get("groups", []):
				for sound: Dictionary in group["sounds"]:
					_group_of[String(sound["id"])] = String(group["name"])
	var share := float(_volumes.get(String(_group_of.get(id, "")), 1.0))
	return linear_to_db(maxf(share, 0.0001))
