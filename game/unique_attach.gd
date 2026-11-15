# Purpose: puts a named chase gun's gimmick model (data/gun_uniques.json "attach": a file in
# assets/models/weapons/uniques/, made by tools/blender/unique_attach.py in the gun's own space) onto the gun model,
# and takes it off again. Used for the gun in hand and for the gun lying on the ground.
# Dependencies: core/gun_db.gd (uniques).
extends RefCounted

const FOLDER := "res://assets/models/weapons/uniques/"
const META := "unique_attach"

static var _defs := {}  # data/gun_uniques.json "uniques", read once for apply_id


# Removes any gimmick, then adds `gun`'s own (if it is a unique with one). Returns the added model or null.
static func apply(model: Node3D, gun: Dictionary, db: RefCounted) -> Node3D:
	var def: Dictionary = db.uniques.get(String(gun.get("unique", "")), {})
	var piece := _attach(model, def)
	if piece != null and String(def.get("keeps", "")) == "record":
		show_record(piece, int(gun.get("record", 0)))
	return piece


# Fish Story: the biggest hit stamped on the brass tag ("Tag" marker of the gimmick).
static func show_record(piece: Node3D, best: int) -> void:
	var tag := piece.find_child("Tag", true, false) as Node3D
	if tag == null:
		return
	var label := tag.get_node_or_null("Record") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "Record"
		label.font_size = 64
		label.pixel_size = 0.00017
		label.outline_size = 0
		label.modulate = Color(0.12, 0.07, 0.02)
		label.rotation_degrees = Vector3(0, -90, 0)  # the tag's face looks to the gun's left
		label.double_sided = false
		label.shaded = false
		tag.add_child(label)
	label.text = "BEST\n%s" % _grouped(best) if best > 0 else "BEST\n---"


static func _grouped(n: int) -> String:
	var digits := str(n)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


static func _attach(model: Node3D, def: Dictionary) -> Node3D:
	clear(model)
	var path := FOLDER + String(def.get("attach", "")) + ".gltf"
	if not def.has("attach") or not ResourceLoader.exists(path):
		return null
	var piece := (load(path) as PackedScene).instantiate() as Node3D
	piece.set_meta(META, true)
	model.add_child(piece)
	return piece


# The same from a unique's id alone (another player's gun: game/remote_player.gd), reading data/gun_uniques.json.
static func apply_id(model: Node3D, unique_id: String) -> Node3D:
	if _defs.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json"))
		_defs = (data as Dictionary).get("uniques", {}) if data is Dictionary else {}
	return _attach(model, _defs.get(unique_id, {}))


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
