# Purpose: puts a named chase gun's gimmick model (data/gun_uniques.json "attach": a file in
# assets/models/weapons/uniques/, made by tools/blender/unique_attach.py in the gun's own space) onto the gun model,
# and takes it off again. Used for the gun in hand and for the gun lying on the ground.
# Dependencies: core/gun_db.gd (uniques).
extends RefCounted

const FOLDER := "res://assets/models/weapons/uniques/"
const META := "unique_attach"


# Removes any gimmick, then adds `gun`'s own (if it is a unique with one). Returns the added model or null.
static func apply(model: Node3D, gun: Dictionary, db: RefCounted) -> Node3D:
	clear(model)
	var def: Dictionary = db.uniques.get(String(gun.get("unique", "")), {})
	var path := FOLDER + String(def.get("attach", "")) + ".gltf"
	if not def.has("attach") or not ResourceLoader.exists(path):
		return null
	var piece := (load(path) as PackedScene).instantiate() as Node3D
	piece.set_meta(META, true)
	model.add_child(piece)
	return piece


static func clear(model: Node3D) -> void:
	for child in model.get_children():
		if child.has_meta(META):
			model.remove_child(child)
			child.queue_free()


# The gimmick on this model now (null = none).
static func on(model: Node3D) -> Node3D:
	for child in model.get_children():
		if child.has_meta(META):
			return child
	return null
