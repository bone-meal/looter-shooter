# Purpose: developer check: builds every outfit for both genders, every hair style and every face, then prints the result and writes tools/appearance_check.log, and quits. Run scene tools/appearance_check.tscn.
# Dependencies: game/body_builder.gd, game/appearance_data.gd.
extends Node

const BodyBuilder = preload("res://game/body_builder.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const RemotePlayer = preload("res://game/remote_player.gd")


func _ready() -> void:
	var db := AppearanceData.db()
	var meshes := 0
	var built := 0
	for gender in ["female", "male"]:
		for o in db.outfits:
			var a := db.default_for(gender)
			a["outfit"] = o["id"]
			meshes += _count(BodyBuilder.build(a))
			built += 1
		for h in db.hair_styles:
			var a := db.default_for(gender)
			a["hair"] = h["id"]
			meshes += _count(BodyBuilder.build(a))
			built += 1
		for f in db.expressions:
			var a := db.default_for(gender)
			a["face"] = f["id"]
			meshes += _count(BodyBuilder.build(a))
			built += 1
	var body := RemotePlayer.new()
	body.display_name = "Test"
	add_child(body)
	var look := db.default_for("male")
	look["outfit"] = "knight"
	body.set_appearance(look)
	body.set_smoking(true)
	body.set_held("ak47")
	body.set_appearance(db.default_for("female"))
	var remote_ok := body.get_node_or_null("Character/Torso/Head") != null
	var report := "APPEARANCE OK: built %d characters, %d meshes total, %d outfits, %d hair, %d faces, remote player ok: %s" % [built, meshes, db.outfits.size(), db.hair_styles.size(), db.expressions.size(), str(remote_ok)]
	print(report)
	var log_file := FileAccess.open("res://tools/appearance_check.log", FileAccess.WRITE)
	if log_file != null:
		log_file.store_string(report + "\n")
	get_tree().quit()


func _count(root: Node3D) -> int:
	var n := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			n += 1
		stack.append_array(node.get_children())
	root.free()
	return n
