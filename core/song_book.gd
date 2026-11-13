# Purpose: pure rules of the hidden songs: which song file belongs to which secret (the n-th file by name), what a
# file name says ("Artist - Title.mp3"), which floats of a secret have been shot, which songs a character has
# unlocked. No nodes; the caller lists the folder and plays the files.
# Dependencies: none. Data: data/zombies/songs.json, passed to setup().
extends RefCounted

var cfg: Dictionary = {}
var files: PackedStringArray = []  # the song files found, sorted by name
var unlocked: Array[int] = []  # secrets (0-based) this character has found, saved
var _hit: Array = []  # per secret: Array[bool], one per float, this session


func setup(config: Dictionary) -> void:
	cfg = config
	_hit.clear()
	for secret: Dictionary in config.get("secrets", []):
		var floats: Array[bool] = []
		floats.resize((secret["things"] as Array).size())
		floats.fill(false)
		_hit.append(floats)


func secret_count() -> int:
	return _hit.size()


# The folder's file names (with their extension); only .mp3 / .ogg / .wav count, sorted by name.
func set_files(names: PackedStringArray) -> void:
	files.clear()
	for file_name: String in names:
		var lower := file_name.to_lower()
		if lower.ends_with(".mp3") or lower.ends_with(".ogg") or lower.ends_with(".wav"):
			files.append(file_name)
	files.sort()


# {"file", "artist", "title"} of secret n's song, or {} when there are fewer files than that.
func song(secret: int) -> Dictionary:
	if secret < 0 or secret >= files.size():
		return {}
	var named := split_name(files[secret])
	named["file"] = files[secret]
	return named


# "Artist - Title.mp3" -> {"artist": "Artist", "title": "Title"}; a name without " - " is all title.
static func split_name(file_name: String) -> Dictionary:
	var stem := file_name.get_basename()
	var cut := stem.find(" - ")
	if cut < 0:
		return {"artist": "", "title": stem.strip_edges()}
	return {"artist": stem.substr(0, cut).strip_edges(), "title": stem.substr(cut + 3).strip_edges()}


# A float of a secret was shot. True when that was the last of its floats (then they all count as unshot again,
# so the song can be found again in the same session).
func shoot(secret: int, thing: int) -> bool:
	if secret < 0 or secret >= _hit.size() or thing < 0 or thing >= (_hit[secret] as Array).size():
		return false
	_hit[secret][thing] = true
	if (_hit[secret] as Array).has(false):
		return false
	(_hit[secret] as Array).fill(false)
	if not unlocked.has(secret):
		unlocked.append(secret)
		unlocked.sort()
	return true


func is_shot(secret: int, thing: int) -> bool:
	return bool(_hit[secret][thing])


func to_list() -> Array:
	return unlocked.duplicate()


func from_list(list: Variant) -> void:
	unlocked.clear()
	if list is Array:
		for n: Variant in list:
			if (n is int or n is float) and int(n) >= 0 and int(n) < _hit.size() and not unlocked.has(int(n)):
				unlocked.append(int(n))
	unlocked.sort()
