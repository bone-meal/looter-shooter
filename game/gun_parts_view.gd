# Purpose: shows a rolled gun's parts on its model. Barrel parts scale the model's own "Barrel" node; muzzle, sight,
# grip and magazine parts are models from assets/models/weapons/parts/ placed on the model's "Mount<Slot>" points
# (a fitted magazine hides the gun's own "Mag"); each part carries a band in its manufacturer's colour. Which model or
# scale a part uses is data: data/gun_parts.json parts.<slot>.<kind>.view, bodies.<body>.part_scale.
# Dependencies: core/gun_db.gd (parts, bodies, makers). Works on models from game/weapon_models.gd; old code-built
# guns have no mounts and simply stay as they are.
extends RefCounted

const FOLDER := "res://assets/models/weapons/parts/"

static var _maker_materials := {}  # colour -> StandardMaterial3D


# Fits the parts of `gun` (clears any earlier ones). Returns the height of the sight line above the gun's origin when
# an optic was fitted (model units), otherwise 0: the caller aims through it.
static func apply(model: Node3D, gun: Dictionary, db: RefCounted) -> float:
	clear(model)
	var parts: Dictionary = gun.get("parts", {})
	var body: Dictionary = db.bodies.get(String(gun.get("body", "")), {})
	var size := float(body.get("part_scale", 1.0))
	var barrel := model.get_node_or_null("Barrel") as Node3D
	var eye := 0.0
	for slot: String in db.slots:  # barrel first: the muzzle mount rides on it
		if not parts.has(slot):
			continue
		var part: Dictionary = parts[slot]
		var view: Dictionary = (db.parts[slot][String(part["kind"])] as Dictionary).get("view", {})
		if view.has("barrel_scale"):
			if barrel != null:
				var by: Array = view["barrel_scale"]
				barrel.scale = Vector3(float(by[0]), float(by[0]), float(by[1]))
			continue
		var mount := model.find_child("Mount" + slot.capitalize(), true, false) as Node3D
		var path := FOLDER + String(view.get("model", "")) + ".gltf"
		if mount == null or not ResourceLoader.exists(path):
			continue
		var piece := (load(path) as PackedScene).instantiate() as Node3D
		piece.set_meta("gun_part", true)
		piece.scale = Vector3.ONE * size
		if barrel != null and mount.get_parent() == barrel:  # keep the part's own shape on a stretched barrel
			piece.scale = Vector3(size / barrel.scale.x, size / barrel.scale.y, size / barrel.scale.z)
		mount.add_child(piece)
		_paint(piece, Color.html(String(db.makers[String(part["maker"])]["color"])))
		if slot == "mag" and model.has_node("Mag"):
			(model.get_node("Mag") as Node3D).visible = false
		if slot == "sight":
			eye = mount.position.y + float(view.get("eye", 0.04)) * size
	return eye


# Takes fitted parts off again: the plain gun.
static func clear(model: Node3D) -> void:
	for found in model.find_children("*", "Node3D", true, false):
		if found.has_meta("gun_part"):
			found.get_parent().remove_child(found)
			found.queue_free()
	if model.has_node("Barrel"):
		(model.get_node("Barrel") as Node3D).scale = Vector3.ONE
	if model.has_node("Mag"):
		(model.get_node("Mag") as Node3D).visible = true


static func _paint(piece: Node3D, color: Color) -> void:
	var key := color.to_html(false)
	if not _maker_materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = 0.3
		material.roughness = 0.45
		_maker_materials[key] = material
	for found in piece.find_children("*", "MeshInstance3D", true, false):
		var mesh := found as MeshInstance3D
		for surface in mesh.mesh.get_surface_count():
			var made := mesh.mesh.surface_get_material(surface)
			if made != null and made.resource_name == "maker":
				mesh.set_surface_override_material(surface, _maker_materials[key])
			elif made != null and made.resource_name == "dot":
				mesh.set_surface_override_material(surface, _dot())


static func _dot() -> StandardMaterial3D:
	if not _maker_materials.has("dot"):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.1, 0.05)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_maker_materials["dot"] = material
	return _maker_materials["dot"]
