# Purpose: the three save slots of THIS build version. Each slot is one whole character (name, look, guns, armour,
# coins, level, fantasy progress) in one signed file, user://saves/<version>/slot<n>.sav. A new version starts with
# three empty slots: saves of other versions (and the old user://profile*.sav files) stay on disk, untouched and
# not offered, until the director asks for a transfer.
# Dependencies: game/profile_io.gd, core/progress_state.gd, core/data_store.gd, data/build.json.
extends RefCounted

const ProfileIO = preload("res://game/profile_io.gd")
const ProgressState = preload("res://core/progress_state.gd")
const DataStore = preload("res://core/data_store.gd")

const COUNT := 3


# "dev" when run from the editor, else the released version (tools/git_release.gd writes data/build.json).
static func version() -> String:
	if OS.has_feature("editor"):
		return "dev"
	return String(DataStore.load_json("res://data/build.json").get("version", "0"))


static func path(slot: int) -> String:
	return "user://saves/%s/slot%d.sav" % [version(), slot]


# What the menu shows of a slot: {} = empty, {"damaged": true} = a file nobody can read, else name, level, points, coins, best round on the islands.
static func summary(slot: int) -> Dictionary:
	var saved := ProfileIO.read(path(slot))
	if saved.is_empty():
		return {"damaged": true} if ProfileIO.last_problem != "" else {}
	var extra: Dictionary = saved["extra"]
	var progress := ProgressState.new(DataStore.load_json("res://data/progression.json"), DataStore.load_json("res://data/achievements.json"))
	progress.from_dict(extra.get("progress", {}))
	var score: Variant = extra.get("score")
	return {"name": String(saved["name"]), "level": progress.level(), "coins": int(extra.get("coins", 0)), "points": int(score.get("points", 0)) if score is Dictionary else 0, "best_round": maxi(int(extra.get("best_round", 0)), 0)}


# From now on the profile is read from and written to this slot (game/profile_io.gd `active`).
static func choose(slot: int) -> void:
	DirAccess.make_dir_recursive_absolute(path(slot).get_base_dir())
	ProfileIO.active = path(slot)


static func erase(slot: int) -> void:
	if FileAccess.file_exists(path(slot)):
		DirAccess.remove_absolute(path(slot))
