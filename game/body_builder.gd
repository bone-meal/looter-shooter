# Purpose: builds a complete character model (body shape, skin, face, hair, 100 outfits) from an appearance dictionary. Replaces the old single-look player model.
# Dependencies: game/appearance_data.gd (+ core/appearance_db.gd), game/body_parts.gd, game/body_ctx.gd, game/face_builder.gd, game/hair_builder.gd, game/outfit_tops.gd, game/outfit_gear.gd.
# Layout (for animation): root > Torso (pivot at the hips) > Head, ArmL, ArmR; root > LegL, LegR. The model faces -Z, feet at y=0, about 1.8 m tall before the height slider.
extends RefCounted

const P = preload("res://game/body_parts.gd")
const Ctx = preload("res://game/body_ctx.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const FaceBuilder = preload("res://game/face_builder.gd")
const HairBuilder = preload("res://game/hair_builder.gd")
const OutfitTops = preload("res://game/outfit_tops.gd")
const OutfitGear = preload("res://game/outfit_gear.gd")
const BodyJiggle = preload("res://game/body_jiggle.gd")

const HIP_Y := 0.88
const ARM_LEN := 0.55
const LEG_LEN := 0.88


static func build(appearance: Dictionary) -> Node3D:
	var db := AppearanceData.db()
	var a := db.sanitize(appearance)
	var outfit := db.outfit(String(a["outfit"]))
	var c := Ctx.new()
	c.female = String(a["gender"]) == "female"
	c.weight = float(a["weight"])
	c.bust = float(a["bust"])
	c.glutes = float(a["glutes"])
	var wt := c.weight
	var depth_scale := 1.0 + (wt - 1.0) * 0.8
	var limb_scale := 1.0 + (wt - 1.0) * 0.7
	if c.female:
		c.head_w = 0.235
		c.chest_w = 0.31 * wt
		c.waist_w = 0.225 * wt
		c.hip_w = 0.36 * wt
		c.depth = 0.2 * depth_scale
		c.arm_t = 0.085 * limb_scale
		c.leg_w = 0.145 * limb_scale
	else:
		c.head_w = 0.25
		c.chest_w = 0.4 * wt
		c.waist_w = 0.34 * wt
		c.hip_w = 0.34 * wt
		c.depth = 0.22 * depth_scale
		c.arm_t = 0.115 * limb_scale
		c.leg_w = 0.15 * limb_scale
	c.head_d = 0.23
	c.leg_x = c.leg_w * 0.5 + 0.015

	var tones: Array = db.skin_tones
	c.skin = P.mat(Color(String(tones[int(a["skin"])])))
	var colors: Array = outfit["colors"]
	c.c1 = Color(String(colors[0]))
	c.c2 = Color(String(colors[1]))
	c.c3 = Color(String(colors[2]))
	c.m1 = P.mat(c.c1)
	c.m2 = P.mat(c.c2)
	c.m3 = P.mat(c.c3)
	c.hair_color = Color(String(a["hair_color"]))

	var top_style := String(outfit["top"])
	var bottom_style := String(outfit["bottom"])
	var head_style := String(outfit["head"])
	var top_info := OutfitTops.top_info(top_style)
	var bottom_info := OutfitTops.bottom_info(bottom_style)
	var torso_mat := c.slot(String(top_info[1]))
	var sleeve_mat := c.slot(String(top_info[2]))
	var leg_mat := c.slot(String(bottom_info[1]))
	c.hide_hair = OutfitGear.hides_hair(head_style)

	var root := Node3D.new()
	root.name = "Character"
	c.torso = P.pivot(root, "Torso", Vector3(0.0, HIP_Y, 0.0))
	_torso_shape(c, torso_mat, leg_mat)
	c.head = P.pivot(c.torso, "Head", Vector3(0.0, 0.6, 0.0))
	_head_shape(c)
	c.arm_l = _arm(c, "ArmL", -1.0, float(top_info[0]), sleeve_mat)
	c.arm_r = _arm(c, "ArmR", 1.0, float(top_info[0]), sleeve_mat)
	c.leg_l = _leg(c, "LegL", -1.0, float(bottom_info[0]), leg_mat, root)
	c.leg_r = _leg(c, "LegR", 1.0, float(bottom_info[0]), leg_mat, root)

	FaceBuilder.build(c, db.expression(String(a["face"])))
	if not c.hide_hair:
		HairBuilder.build(c, String(a["hair"]))
	OutfitTops.add_top(top_style, c)
	OutfitTops.add_bottom(bottom_style, c)
	OutfitGear.add_head(head_style, c)
	OutfitGear.add_back(String(outfit["back"]), c)
	OutfitGear.add_feet(String(outfit["feet"]), c)
	OutfitGear.add_neck(String(outfit["neck"]), c)
	OutfitGear.add_hands(String(outfit["hands"]), c)
	root.scale = Vector3.ONE * float(a["height"])
	BodyJiggle.new().setup(root)  # soft-body jiggle driver (only added when the body has soft parts)
	return root


# Rounded skull, jaw, ears and nose (the face is drawn on the skull's curve by face_builder.gd).
static func _head_shape(c: Ctx) -> void:
	var rx := c.head_w * 0.5
	var rz := c.head_d * 0.5
	P.ball(c.head, rx, Vector3(0.0, 0.12, 0.0), c.skin, Vector3(1.0, 0.128 / rx, rz / rx))
	var jaw := rx * (0.74 if c.female else 0.82)
	P.ball(c.head, jaw, Vector3(0.0, 0.05, -0.006), c.skin, Vector3(1.0, 0.075 / jaw, rz * 0.72 / jaw))  # stays behind the face curve so the mouth shows
	for s: float in [-1.0, 1.0]:
		P.ball(c.head, 0.03, Vector3(s * rx * 0.97, 0.11, 0.012), c.skin, Vector3(0.42, 1.0, 0.7))
	P.ball(c.head, 0.017, Vector3(0.0, 0.1, -rz - 0.004), c.skin, Vector3(0.8, 1.15, 0.95))


# A tapered elliptical slab (width w, depth d, height h) for the torso pieces.
static func _slab(c: Ctx, w: float, d: float, h: float, y: float, top_ratio: float, m: Material) -> void:
	var piece := P.cyl(c.torso, 0.5 * top_ratio, 0.5, h, Vector3(0, y, 0), m)
	piece.scale = Vector3(w, 1.0, d)


# Hips, waist and chest (female: hourglass; male: broad shoulders), neck, and the bust / glute volumes in clothing color.
static func _torso_shape(c: Ctx, torso_mat: Material, leg_mat: Material) -> void:
	_slab(c, c.hip_w, c.depth * 1.02, 0.18, 0.09, c.waist_w / c.hip_w * 1.02, leg_mat)
	_slab(c, c.waist_w * 1.02, c.depth * 0.96, 0.18, 0.27, c.chest_w / c.waist_w * 0.98, torso_mat)
	_slab(c, c.chest_w, c.depth, 0.16, 0.44, 0.9, torso_mat)
	P.ball(c.torso, 0.5, Vector3(0, 0.52, 0), torso_mat, Vector3(c.chest_w * 0.9, 0.08, c.depth))  # rounded shoulders
	P.cyl(c.torso, 0.045, 0.052, 0.11, Vector3(0, 0.57, 0), c.skin)
	var bust_r := (0.04 + 0.06 * c.bust) * (1.0 if c.female else 0.85)
	if c.bust > 0.02:
		for s: float in [-1.0, 1.0]:
			P.ball(c.torso, bust_r, Vector3(s * c.chest_w * 0.23, 0.41, -c.depth * 0.5 + 0.005), torso_mat, Vector3(1.0, 0.95, 0.85)).set_meta("soft", c.bust)
	var glute_r := 0.045 + 0.065 * c.glutes
	if c.glutes > 0.02:
		for s: float in [-1.0, 1.0]:
			P.ball(c.torso, glute_r, Vector3(s * c.hip_w * 0.22, 0.09, c.depth * 0.5 - 0.005), leg_mat, Vector3(1.0, 1.05, 0.9)).set_meta("soft", c.glutes)


static func _arm(c: Ctx, node_name: String, side: float, sleeve: float, sleeve_mat: Material) -> Node3D:
	var arm := P.pivot(c.torso, node_name, Vector3(side * (c.chest_w * 0.5 + c.arm_t * 0.35), 0.5, 0.0))
	var r := c.arm_t * 0.5
	var upper := ARM_LEN * sleeve
	P.ball(arm, r * 1.25, Vector3(0, -r * 0.3, 0), sleeve_mat if upper > 0.001 else c.skin)  # shoulder
	if upper > 0.001:
		P.cyl(arm, r * 1.05, r * 0.95, upper, Vector3(0, -upper * 0.5, 0), sleeve_mat)
	var lower := ARM_LEN - upper
	if lower > 0.001:
		P.cyl(arm, r * 0.9, r * 0.78, lower, Vector3(0, -upper - lower * 0.5, 0), c.skin)
	var elbow := ARM_LEN * 0.5
	P.ball(arm, r * 0.92, Vector3(0, -elbow, 0), sleeve_mat if upper > elbow else c.skin)
	P.ball(arm, r * 1.05, Vector3(0, -ARM_LEN - r * 0.6, -r * 0.15), c.skin, Vector3(0.75, 1.3, 0.95))  # hand
	arm.rotation_degrees.z = -side * 4.0
	return arm


static func _leg(c: Ctx, node_name: String, side: float, cover: float, leg_mat: Material, root: Node3D) -> Node3D:
	var leg := P.pivot(root, node_name, Vector3(side * c.leg_x, HIP_Y, 0.0))
	var r := c.leg_w * 0.5
	var upper := LEG_LEN * cover
	if upper > 0.001:
		P.cyl(leg, r * 1.08, r * 0.9, upper, Vector3(0, -upper * 0.5, 0), leg_mat)
	var lower := LEG_LEN - upper
	if lower > 0.001:
		P.cyl(leg, r * 0.92, r * 0.72, lower, Vector3(0, -upper - lower * 0.5, 0), c.skin)
	var knee := LEG_LEN * 0.5
	P.ball(leg, r * 0.95, Vector3(0, -knee, -r * 0.1), leg_mat if upper > knee else c.skin)
	return leg
