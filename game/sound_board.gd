# Purpose: one switchboard for every sound of the game: which ones the player has muted (settings) and which ones are
# being heard right now (shown on the Sounds page of the settings, game/sound_menu.gd). Whoever plays a sound asks
# `allow(id)` first and calls `heard(id)` when it is really audible. Ids, labels and groups: data/sound_list.json.
# Dependencies: none.
extends RefCounted

static var muted := {}  # sound id -> true
static var _last := {}  # sound id -> engine milliseconds when it was last audible
static var _latest := 0


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
