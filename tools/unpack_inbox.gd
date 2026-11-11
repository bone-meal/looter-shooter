# Purpose: developer tool. Unpacks every zip in res://tools/inbox/ into the project folder (paths inside the zip are
# project paths, e.g. assets/models/fantasy/well.gltf), removes the zip, and lists what it wrote with sizes in
# tools/unpack_inbox.log. Used to bring many asset files over in one go. Run tools/import_assets.tscn afterwards.
# For every model it writes (.gltf or its .bin) it also deletes the editor's cached import of that model: Godot only
# re-imports a .gltf whose own text changed, so a model whose .bin alone changed would otherwise keep its old look.
# Dependencies: none.
extends Node


func _ready() -> void:
	var lines := PackedStringArray()
	var inbox := "res://tools/inbox/"
	var stale := {}  # "<name>.gltf" of every model written
	for file in DirAccess.get_files_at(inbox):
		if not file.ends_with(".zip"):
			continue
		var reader := ZIPReader.new()
		if reader.open(inbox + file) != OK:
			lines.append("FAILED to open %s" % file)
			continue
		for inner in reader.get_files():
			if inner.ends_with("/") or inner.contains(".."):
				continue
			var bytes := reader.read_file(inner)
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + inner.get_base_dir()))
			var out := FileAccess.open("res://" + inner, FileAccess.WRITE)
			if out == null:
				lines.append("FAILED to write %s" % inner)
				continue
			out.store_buffer(bytes)
			out.close()
			lines.append("%s %d" % [inner, bytes.size()])
			if inner.get_extension() in ["gltf", "bin"]:
				stale[inner.get_basename().get_file() + ".gltf"] = true
		reader.close()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(inbox + file))
		lines.append("unpacked %s" % file)
	var cleared := 0
	for cached in DirAccess.get_files_at("res://.godot/imported/"):
		var cut := cached.find(".gltf-")
		if cut > 0 and stale.has(cached.substr(0, cut + 5)):
			DirAccess.remove_absolute(ProjectSettings.globalize_path("res://.godot/imported/" + cached))
			cleared += 1
	lines.append("cleared %d cached model imports" % cleared)
	lines.append("UNPACK_DONE")
	var log_file := FileAccess.open("res://tools/unpack_inbox.log", FileAccess.WRITE)
	log_file.store_string("\n".join(lines))
	log_file.close()
	get_tree().quit()
