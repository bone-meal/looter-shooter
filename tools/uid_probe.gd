# Purpose: developer tool for "Unrecognized UID" errors in the editor's Output. For each uid in WANTED (typed off the
# director's screenshot) it says whether the project's uid cache knows it and lists every file of the project folder
# (hidden .godot and _to_delete included) whose text holds it, as "uid://..." or as its number. It also counts the
# .import and .uid files whose own source file is gone. Log: tools/uid_probe.log (ends UID_PROBE_DONE).
# Dependencies: none.
extends Node

const WANTED: PackedStringArray = ["c1fevy1pf07n6", "cusbtko5mnhcf", "q0q433uub5de", "c14kip362skxx", "dchwq0y6jwk73", "8x2b1t5qq8fl",
	"cedede15pcvok", "4u1cbumniv7w", "dqn3ruymkx0bi", "bd2q5rbmu8608", "0h80m0ygrsiy", "bmobuwf2kdbii", "c6wqrdc1qqjdw", "8svib4ximek7",
	"8h5qkrcskptx", "cbebat6pbgi54", "cyvftdgoxcgdf", "cs73h145672vq", "kgwv46ewjchm", "bxbb7vu1nfead", "b4y85whmgni0r", "bda6ixoax54yx",
	"b24iu5gefff2c", "c4cpopulh7dil", "elmclpmge3r7", "bxx1rcfing0gb", "caed1h4w6ug7n", "d3p5qfi8rc3nm", "bu6of0x42ss5l", "cuk12jwu3t7nb",
	"c46lq2h71ajj8", "dumlfdb4gak40", "ba4dj58c0818i", "j4ffmcuh882m"]
const TEXT_KINDS: PackedStringArray = ["import", "uid", "tscn", "tres", "cfg", "godot", "gd", "json", "txt", "md", "gltf", "", "cache", "bin"]

var _found := {}  # uid text -> PackedStringArray of files
var _numbers := {}  # uid text -> its number as text
var _files := 0
var _orphan_imports := PackedStringArray()
var _orphan_uids := PackedStringArray()
var _by_folder := {}  # top folder -> how many files hold one of the wanted ids


func _ready() -> void:
	var lines := PackedStringArray()
	for id in WANTED:
		_found[id] = PackedStringArray()
		_numbers[id] = str(ResourceUID.text_to_id("uid://" + id))
	_walk(ProjectSettings.globalize_path("res://").trim_suffix("/"), "")
	for id in WANTED:
		var number := ResourceUID.text_to_id("uid://" + id)
		var known := ResourceUID.has_id(number)
		var where: PackedStringArray = _found[id]
		lines.append("%s known=%s%s in %d files: %s" % [id, str(known), (" -> " + ResourceUID.get_id_path(number)) if known else "", where.size(), ", ".join(where.slice(0, 4))])
	lines.append("files read: %d; files holding a wanted id, by top folder: %s" % [_files, str(_by_folder)])
	lines.append("%d .import files without their source file, first: %s" % [_orphan_imports.size(), ", ".join(_orphan_imports.slice(0, 12))])
	lines.append("%d .uid files without their script, first: %s" % [_orphan_uids.size(), ", ".join(_orphan_uids.slice(0, 12))])
	lines.append("UID_PROBE_DONE")
	var file := FileAccess.open("res://tools/uid_probe.log", FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	get_tree().quit()


func _walk(folder: String, shown: String) -> void:
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		if sub == ".git" or sub == "imported" or sub == "shader_cache" or sub == "exported":
			continue  # huge and binary
		_walk(folder + "/" + sub, shown + sub + "/")
	for entry in dir.get_files():
		var path := folder + "/" + entry
		var kind := entry.get_extension()
		if kind == "import" and not FileAccess.file_exists(path.trim_suffix(".import")):
			_orphan_imports.append(shown + entry)
		if kind == "uid" and not FileAccess.file_exists(path.trim_suffix(".uid")):
			_orphan_uids.append(shown + entry)
		if not TEXT_KINDS.has(kind):
			continue
		var bytes := FileAccess.get_file_as_bytes(path)
		if bytes.size() > 8000000:
			continue
		_files += 1
		var text := bytes.get_string_from_ascii() if kind != "bin" and kind != "cache" and kind != "" else bytes.get_string_from_ascii()
		for id in WANTED:
			if text.contains(id) or text.contains(String(_numbers[id])):
				(_found[id] as PackedStringArray).append(shown + entry)
				var top := shown.get_slice("/", 0) if shown != "" else "(top)"
				_by_folder[top] = int(_by_folder.get(top, 0)) + 1
