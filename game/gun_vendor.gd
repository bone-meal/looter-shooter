# Purpose: a casino kiosk that sells one kind of crate (a random rolled gun with a tier floor) for chips. Draws only; game_session handles the purchase.
# Dependencies: none. Crate data comes from data/gun_loot.json `vendor`.
extends Node3D

var crate: Dictionary = {}  # {"id", "name", "price", "luck", "min_tier", "color"}; set before add_child


func _ready() -> void:
	var color := Color(String(crate["color"]))
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 1.1, 1.3)
	body.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.12, 0.06, 0.16)
	body.material_override = bmat
	body.position.y = 0.55
	add_child(body)
	var shape_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = bm.size
	cs.shape = box
	shape_body.add_child(cs)
	shape_body.position.y = 0.55
	add_child(shape_body)
	var glow := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.54, 0.12, 1.34)
	glow.mesh = gm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = color
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.material_override = gmat
	glow.position.y = 1.16
	add_child(glow)
	var crate_box := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.3, 0.3, 0.4)
	crate_box.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = color
	cmat.emission_enabled = true
	cmat.emission = color
	cmat.emission_energy_multiplier = 0.6
	crate_box.material_override = cmat
	crate_box.position = Vector3(0.0, 1.45, 0.0)
	add_child(crate_box)
	var label := Label3D.new()
	label.text = "%s\n%d chips\n[F] buy" % [crate["name"], int(crate["price"])]
	label.font_size = 36
	label.pixel_size = 0.004
	label.modulate = color
	label.shaded = false
	label.rotation_degrees.y = 90.0
	label.position = Vector3(0.27, 0.75, 0.0)
	add_child(label)


func console_position() -> Vector3:
	return global_position
