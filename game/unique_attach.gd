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


# The part of another player's held string after "#" (game/player.gd held_id): Fish Story's record, or "out" for a
# Keeper's Lantern that was thrown, Hot Potato heat, Brain Freeze cup level.
static func show_extra(piece: Node3D, unique_id: String, extra: String) -> void:
	var def := _def_of(unique_id)
	if String(def.get("keeps", "")) == "record":
		show_record(piece, extra.to_int())
	if bool(def.get("lantern", false)):
		var swing := piece.find_child("Swing", true, false) as Node3D
		if swing != null:
			swing.visible = extra != "out"
	if bool(def.get("hot", false)) and piece.get_parent() is Node3D:  # Hot Potato: "out" = thrown, "h0".."h9" = how hot
		var gun_model := piece.get_parent() as Node3D
		gun_model.visible = extra != "out"
		if extra.begins_with("h"):
			(load("res://game/signatures/hot_potato.gd") as GDScript).call("paint", gun_model, float(extra.substr(1).to_int()) / 9.0)


	if bool(def.get("clam", false)):  # Clam Shell: "p0".."p4" = the pearl growing
		(load("res://game/signatures/clam_shell.gd") as GDScript).call("show_pearl", piece.find_child("Pearl", true, false), float(extra.substr(1).to_int() + 1) / 5.0 if extra.begins_with("p") else 0.0)
	if bool(def.get("noodle", false)) and piece.get_parent() is Node3D:  # Spaghetti: "c" = a charged shot ready (the gun glows)
		(load("res://game/signatures/spaghetti.gd") as GDScript).call("glow", piece.get_parent(), extra == "c")
	if bool(def.get("shark", false)):  # Loan Shark: "s0".."s9" = how big the debt (and the shark) is
		var full := int((def.get("cfg", {}) as Dictionary).get("full_size_at", 60))
		(load("res://game/signatures/loan_shark.gd") as GDScript).call("show_shark", piece.find_child("Shark", true, false), floori(float(extra.substr(1).to_int()) / 9.0 * float(full)), full)
	if bool(def.get("clock", false)):  # Time Card: "o" = clocked out, "t0".."t3" = the pay rate
		var words: Label3D = (load("res://game/signatures/time_card.gd") as GDScript).call("face_label", piece)
		if words != null:
			var pay: Array = (def.get("cfg", {}) as Dictionary).get("pay", [])
			var r := extra.substr(1).to_int()
			words.text = "OUT" if extra == "o" or not extra.begins_with("t") else "IN\nx%s" % str(float((pay[mini(r, pay.size() - 1)] as Dictionary).get("mult", 1.0)) if not pay.is_empty() else 1.0)
	if bool(def.get("keys", false)):  # Key Ring: "k0".."k9" = how many keys
		(load("res://game/signatures/key_ring.gd") as GDScript).call("show_keys", piece, extra.substr(1).to_int())
	if bool(def.get("coin", false)):  # Split Decision: "f" / "i" = the coin's face for the next shot
		(load("res://game/signatures/split_decision.gd") as GDScript).call("show_coin", piece.find_child("Coin", true, false), extra == "f")
	if bool(def.get("slushie", false)):  # Brain Freeze: "c0".."c9" = how full the cup is, "bf" = brain freeze
		(load("res://game/signatures/brain_freeze.gd") as GDScript).call("show_cup", piece, 0.0 if extra == "bf" else float(extra.substr(1).to_int()) / 9.0, extra == "bf")


static func _def_of(unique_id: String) -> Dictionary:
	if _defs.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/gun_uniques.json"))
		_defs = (data as Dictionary).get("uniques", {}) if data is Dictionary else {}
	return _defs.get(unique_id, {})


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
	if bool(def.get("lantern", false)):
		_light_lantern(piece)
	var glass := piece.find_child("Glass", true, false)
	if glass != null:  # a bottle / bowl: its glass is made see-through
		_see_through(glass)
	if bool(def.get("angler", false)):  # Angler Light: the lure's bulb glows and lights a little round it
		_glow_node(piece.find_child("Lure", true, false), Color(0.7, 1.0, 0.85), Color(0.6, 1.0, 0.8), 8.0, 0.9)
	if bool(def.get("beam", false)):  # Lighthouse in a Bottle: the lamp glows
		_glow_node(piece.find_child("Lamp", true, false), Color(1.0, 0.85, 0.4), Color.BLACK, 0.0, 0.0)
	if bool(def.get("vane", false)):  # Weathervane: the rooster turns into the wind on every machine
		var turner := (load("res://game/vane_turner.gd") as GDScript).new() as Node3D
		piece.add_child(turner)
	return piece


# An unshaded glow on a node's meshes and, with range > 0, a small light (no shadows) on it.
static func _glow_node(node: Node, glow_color: Color, light_color: Color, light_range: float, energy: float) -> void:
	if node == null:
		return
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = glow_color
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = glow
	if light_range > 0.0:
		var light := OmniLight3D.new()
		light.light_color = light_color
		light.omni_range = light_range
		light.light_energy = energy
		light.shadow_enabled = false
		node.add_child(light)


# Glass seen through (one shared material: pale, mostly clear).
static func _see_through(node: Node) -> void:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.8, 0.92, 0.9, 0.22)
	glass.roughness = 0.1
	glass.cull_mode = BaseMaterial3D.CULL_BACK
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = glass
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = glass


# Keeper's Lantern: its flame glows and gives a small warm light (no shadows); game/lantern_glow.gd finds it.
static func _light_lantern(piece: Node3D) -> void:
	piece.add_to_group("lanterns")
	var flame := piece.find_child("Flame", true, false) as Node3D
	if flame == null:
		return
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = Color(1.0, 0.75, 0.35)
	for mesh in flame.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = glow
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.omni_range = 7.0
	light.light_energy = 1.1
	light.shadow_enabled = false
	flame.add_child(light)


# The same from a unique's id alone (another player's gun: game/remote_player.gd), reading data/gun_uniques.json.
static func apply_id(model: Node3D, unique_id: String) -> Node3D:
	var def := _def_of(unique_id)
	var piece := _attach(model, def)
	if piece != null and String(def.get("keeps", "")) == "record":
		show_record(piece, 0)
	if piece != null and bool(def.get("kite", false)):  # Kite Flyer: his kite flies over him here too (a string to grab)
		var kite := (load("res://game/kite.gd") as GDScript).new() as Node3D
		kite.set("owned", false)
		piece.add_child(kite)
	if piece != null and bool(def.get("beam", false)):  # Lighthouse in a Bottle: his beam sweeps here too (and heals us)
		(load("res://game/signatures/lighthouse.gd") as GDScript).call("make_beam", piece, def.get("cfg", {}), false)
	if piece != null and bool(def.get("gulls", false)):  # Chip Thief: his gulls circle him here too
		(load("res://game/signatures/chip_thief.gd") as GDScript).call("make_flock", piece, def.get("cfg", {}))
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
