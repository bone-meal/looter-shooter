# Purpose: developer-time tool. Writes every knife type of data/knives.json, built by game/knife_models.gd, as a glTF
# file (tools/tmp/knives/<type>.glb, materials named after data/knives.json "materials") for tools/blender/icons.py,
# which renders the knife icons (assets/ui/icons/knives/<type>.png) with the other item pictures.
# Writes KNIFE_ICONS_DONE n into tools/knife_icons.log.
# Dependencies: game/knife_models.gd, data/knives.json.
extends Node

const KnifeModels = preload("res://game/knife_models.gd")
const OUT := "res://tools/tmp/knives/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var made := 0
	for id: String in JSON.parse_string(FileAccess.get_file_as_string("res://data/knives.json"))["knives"]:
		var knife := KnifeModels.build(id)
		knife.name = id
		add_child(knife)
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_scene(knife, state) == OK and doc.write_to_filesystem(state, ProjectSettings.globalize_path(OUT + id + ".glb")) == OK:
			made += 1
		knife.queue_free()
	var f := FileAccess.open("res://tools/knife_icons.log", FileAccess.WRITE)
	f.store_string("KNIFE_ICONS_DONE %d\n" % made)
	f.close()
	get_tree().quit()
