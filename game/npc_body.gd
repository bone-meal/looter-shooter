# Purpose: the body of a non-player character (casino and club staff, lifeguard). With the character packs installed it
# is a rigged body in the outfit and hairstyle listed for NPCs in data/characters.json ("npc"), its clothes tinted with
# the first colour of the look's old outfit, plus the staff accessories that old outfit names: bunny ears, fluffy tail,
# bow tie (always clothed). Without the packs it is the old code-built body.
# Dependencies: game/rigged_body.gd, game/body_builder.gd, game/appearance_data.gd (old outfit lookup).
extends RefCounted

const RiggedBody = preload("res://game/rigged_body.gd")
const BodyBuilder = preload("res://game/body_builder.gd")
const AppearanceData = preload("res://game/appearance_data.gd")

const FUR := Color(0.97, 0.96, 0.94)
const INNER := Color(0.98, 0.72, 0.78)


static func build(look: Dictionary) -> Node3D:
	if not RiggedBody.available():
		return BodyBuilder.build(look)
	var npc: Dictionary = RiggedBody.data().get("npc", {})
	var rig_look := look.duplicate()
	rig_look["rig_outfit"] = String((npc.get("outfits", {}) as Dictionary).get(String(look.get("outfit", "")), npc.get("outfit", "peasant")))  # a person's trade decides the clothes
	rig_look["rig_hair"] = String((npc.get("hair", {}) as Dictionary).get(String(look.get("hair", "")), npc.get("default_hair", "long")))
	var body := RiggedBody.build(AppearanceData.db().sanitize(rig_look), false)
	if body == null:
		return BodyBuilder.build(look)
	var old_outfit: Dictionary = AppearanceData.db().outfit(String(look.get("outfit", "")))
	var colors: Array = old_outfit.get("colors", [])
	var accent := Color.html(String(colors[0])) if not colors.is_empty() else Color.WHITE
	body.call("tint_outfit", Color.WHITE.lerp(accent, float(npc.get("tint", 0.5))))
	if String(old_outfit.get("head", "")) == "bunnyears":
		_ears(body.call("head_anchor") as Node3D)
	if String(old_outfit.get("back", "")) == "foxtail":
		_tail(body.call("attach", "pelvis") as Node3D)
	if String(old_outfit.get("neck", "")) == "bowtie":
		_bow(body.call("attach", "neck_01") as Node3D, accent)
	return body


# Ears, tail and bow tie on a rigged body (the club's stage performers).
static func add_bunny(body: Node3D, bow_color: Color) -> void:
	_ears(body.call("head_anchor") as Node3D)
	_tail(body.call("attach", "pelvis") as Node3D)
	_bow(body.call("attach", "neck_01") as Node3D, bow_color)


# Two tall soft ears on a headband. The anchor is the old head centre, facing -Z.
static func _ears(anchor: Node3D) -> void:
	var band := MeshInstance3D.new()
	var arc := TorusMesh.new()
	arc.inner_radius = 0.094
	arc.outer_radius = 0.106
	arc.rings = 24
	arc.ring_segments = 8
	band.mesh = arc
	band.material_override = _mat(Color(0.1, 0.1, 0.12), 0.5)
	band.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	band.position = Vector3(0.0, 0.14, 0.0)
	band.scale = Vector3(1.0, 0.5, 1.0)
	anchor.add_child(band)
	for side: float in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.position = Vector3(0.05 * side, 0.235, 0.0)
		ear.rotation_degrees = Vector3(-6.0, 0.0, -11.0 * side)
		anchor.add_child(ear)
		_blob(ear, Vector3(0.034, 0.13, 0.014), Vector3(0.0, 0.12, 0.0), FUR, 0.95)
		_blob(ear, Vector3(0.019, 0.1, 0.006), Vector3(0.0, 0.115, -0.011), INNER, 0.9)


# A round fluffy tail at the base of the back (pelvis bone space: +Z is forward on these skeletons).
static func _tail(anchor: Node3D) -> void:
	_blob(anchor, Vector3(0.06, 0.06, 0.055), Vector3(0.0, 0.02, -0.135), FUR, 1.0)
	_blob(anchor, Vector3(0.035, 0.035, 0.03), Vector3(0.0, 0.05, -0.165), FUR, 1.0)


static func _bow(anchor: Node3D, color: Color) -> void:
	for side: float in [-1.0, 1.0]:
		var wing := _blob(anchor, Vector3(0.03, 0.02, 0.008), Vector3(0.032 * side, 0.0, 0.085), color, 0.6)
		wing.rotation_degrees.z = 14.0 * side
	_blob(anchor, Vector3(0.011, 0.013, 0.01), Vector3(0.0, 0.0, 0.088), color.darkened(0.25), 0.6)


static func _blob(parent: Node3D, radii: Vector3, at: Vector3, color: Color, roughness: float) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 20
	ball.rings = 10
	piece.mesh = ball
	piece.scale = radii
	piece.position = at
	piece.material_override = _mat(color, roughness)
	parent.add_child(piece)
	return piece


static func _mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material
