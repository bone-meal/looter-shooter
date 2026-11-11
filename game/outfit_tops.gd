# Purpose: the shirt-like and trouser-like pieces of the 100 outfits (16 tops, 14 bottoms), added as colored boxes on the torso, arms, hips and legs.
# Dependencies: game/body_parts.gd, game/body_ctx.gd. Outfit definitions: data/outfits.json (top / bottom style IDs and 3 colors).
extends RefCounted

const P = preload("res://game/body_parts.gd")
const Ctx = preload("res://game/body_ctx.gd")

# style -> [sleeve length 0..1 of the arm, torso color slot, sleeve color slot]
const TOP_INFO := {
	"tee": [0.4, "m1", "m1"], "tank": [0.0, "m1", "m1"], "hoodie": [1.0, "m1", "m1"], "jacket": [1.0, "m1", "m1"],
	"plate": [1.0, "m2", "m2"], "robe": [1.0, "m1", "m1"], "tux": [1.0, "m1", "m1"], "labcoat": [1.0, "m1", "m1"],
	"kimono": [1.0, "m1", "m1"], "sweater": [1.0, "m1", "m1"], "vest": [0.45, "m3", "m3"], "spacesuit": [1.0, "m1", "m1"],
	"pirate": [1.0, "m1", "m1"], "bodice": [0.0, "m3", "m3"], "poncho": [0.0, "m2", "m2"], "sporty": [0.4, "m1", "m1"],
}
# style -> [leg coverage 0..1 (0 = bare skin or hidden under a skirt), color slot]
const BOTTOM_INFO := {
	"jeans": [1.0, "m2"], "shorts": [0.4, "m2"], "skirt": [0.0, "m2"], "longskirt": [0.0, "m2"], "greaves": [1.0, "m2"],
	"cargo": [1.0, "m2"], "kilt": [0.0, "m2"], "hakama": [0.0, "m2"], "leggings": [1.0, "m2"], "overalls": [1.0, "m2"],
	"trunks": [0.3, "m2"], "spacepants": [1.0, "m2"], "baggy": [1.0, "m2"], "chaps": [1.0, "m2"],
}


static func top_info(style: String) -> Array:
	return TOP_INFO.get(style, TOP_INFO["tee"])


static func bottom_info(style: String) -> Array:
	return BOTTOM_INFO.get(style, BOTTOM_INFO["jeans"])


static func add_top(style: String, c: Ctx) -> void:
	var t := c.torso
	var d := c.depth
	match style:
		"tee":
			P.box(t, Vector3(c.chest_w + 0.006, 0.03, d + 0.006), Vector3(0, 0.46, 0), c.m3)
		"tank":
			P.box(t, Vector3(c.waist_w + 0.006, 0.03, d + 0.006), Vector3(0, 0.2, 0), c.m3)
		"hoodie":
			P.box(t, Vector3(0.2, 0.13, 0.1), Vector3(0, 0.57, d * 0.5 + 0.03), c.m1)
			P.box(t, Vector3(c.chest_w * 0.7, 0.08, 0.012), Vector3(0, 0.25, -d * 0.5 - 0.006), c.m3)
		"jacket":
			P.box(t, Vector3(c.chest_w * 0.3, 0.32, d + 0.008), Vector3(0, 0.36, 0), c.m3)
			P.box(t, Vector3(c.chest_w + 0.01, 0.05, d + 0.03), Vector3(0, 0.54, 0), c.m1)
			P.box(t, Vector3(0.012, 0.34, 0.012), Vector3(0, 0.36, -d * 0.5 - 0.012), P.mat(Color(0.15, 0.15, 0.17)))
		"plate":
			P.box(t, Vector3(c.chest_w + 0.03, 0.17, d + 0.04), Vector3(0, 0.44, 0), c.m1)
			P.box(t, Vector3(c.waist_w + 0.03, 0.14, d + 0.03), Vector3(0, 0.26, 0), c.m1)
			P.box(t, Vector3(0.03, 0.15, 0.012), Vector3(0, 0.44, -d * 0.5 - 0.025), c.m3)
			for s: float in [-1.0, 1.0]:
				P.ball(t, 0.08, Vector3(s * (c.chest_w * 0.5 + 0.045), 0.52, 0), c.m1, Vector3(1.0, 0.7, 1.0))
		"robe":
			P.cyl(t, c.waist_w * 0.52, c.hip_w * 1.0, 0.82, Vector3(0, -0.2, 0), c.m1)
			P.box(t, Vector3(c.waist_w + 0.03, 0.06, d + 0.03), Vector3(0, 0.22, 0), c.m3)
			_flare(c, c.m1, 2.4)
		"tux":
			P.box(t, Vector3(c.chest_w * 0.34, 0.3, d + 0.008), Vector3(0, 0.37, 0), c.m3)
			P.box(t, Vector3(c.chest_w * 0.8, 0.32, 0.02), Vector3(0, 0.0, d * 0.5 + 0.012), c.m1)
			for s: float in [-1.0, 1.0]:
				P.box(t, Vector3(0.04, 0.3, 0.02), Vector3(s * c.chest_w * 0.2, 0.37, -d * 0.5 - 0.012), c.m1, Vector3(0, 0, s * 10.0))
		"labcoat":
			P.box(t, Vector3(c.chest_w + 0.03, 0.66, d + 0.04), Vector3(0, 0.12, 0), c.m1)
			P.box(t, Vector3(0.012, 0.6, 0.012), Vector3(0, 0.12, -d * 0.5 - 0.024), c.m3)
			for s: float in [-1.0, 1.0]:
				P.box(t, Vector3(0.07, 0.06, 0.012), Vector3(s * c.chest_w * 0.3, 0.1, -d * 0.5 - 0.024), c.m3)
		"kimono":
			for s: float in [-1.0, 1.0]:
				P.box(t, Vector3(c.chest_w * 0.55, 0.34, 0.015), Vector3(s * c.chest_w * 0.12, 0.36, -d * 0.5 - 0.01), c.m3, Vector3(0, 0, s * 18.0))
			P.box(t, Vector3(c.waist_w + 0.04, 0.11, d + 0.04), Vector3(0, 0.22, 0), c.m3)
			_flare(c, c.m1, 2.2)
		"sweater":
			P.box(t, Vector3(c.chest_w + 0.008, 0.035, d + 0.008), Vector3(0, 0.47, 0), c.m3)
			P.box(t, Vector3(c.waist_w + 0.008, 0.035, d + 0.008), Vector3(0, 0.3, 0), c.m3)
			P.cyl(t, 0.07, 0.075, 0.07, Vector3(0, 0.57, 0), c.m1)
		"vest":
			for s: float in [-1.0, 1.0]:
				P.box(t, Vector3(c.chest_w * 0.42, 0.34, 0.014), Vector3(s * c.chest_w * 0.26, 0.36, -d * 0.5 - 0.008), c.m1)
			P.box(t, Vector3(c.chest_w + 0.01, 0.34, 0.014), Vector3(0, 0.36, d * 0.5 + 0.008), c.m1)
		"spacesuit":
			P.box(t, Vector3(0.14, 0.11, 0.02), Vector3(0, 0.4, -d * 0.5 - 0.012), c.m3)
			for i in 3:
				P.box(t, Vector3(0.02, 0.02, 0.02), Vector3(-0.04 + i * 0.04, 0.4, -d * 0.5 - 0.026), P.mat(c.c3.lightened(0.4), true))
			P.box(t, Vector3(c.waist_w + 0.03, 0.05, d + 0.03), Vector3(0, 0.2, 0), c.m3)
			P.torus(t, 0.045, 0.085, Vector3(0, 0.56, 0), c.m3)
		"pirate":
			P.box(t, Vector3(0.1, 0.16, 0.012), Vector3(0, 0.45, -d * 0.5 - 0.008), c.skin, Vector3(0, 0, 0))
			P.box(t, Vector3(c.waist_w + 0.03, 0.08, d + 0.03), Vector3(0, 0.2, 0), c.m3)
			_flare(c, c.m1, 1.5)
		"bodice":
			P.box(t, Vector3(c.chest_w + 0.012, 0.3, d + 0.012), Vector3(0, 0.37, 0), c.m3)
			for i in 4:
				P.box(t, Vector3(0.07, 0.008, 0.01), Vector3(0, 0.28 + i * 0.07, -d * 0.5 - 0.012), c.m1)
		"poncho":
			P.box(t, Vector3(c.chest_w + 0.24, 0.36, d + 0.22), Vector3(0, 0.35, 0), c.m1)
			P.box(t, Vector3(c.chest_w + 0.25, 0.05, d + 0.23), Vector3(0, 0.2, 0), c.m3)
			P.box(t, Vector3(0.14, 0.09, 0.14), Vector3(0, 0.55, 0), c.m3)
		"sporty":
			for s: float in [-1.0, 1.0]:
				P.box(t, Vector3(0.025, 0.34, d + 0.006), Vector3(s * (c.chest_w * 0.5 - 0.02), 0.36, 0), c.m3)
			P.box(t, Vector3(0.1, 0.04, d + 0.01), Vector3(0, 0.55, 0), c.m3)


static func add_bottom(style: String, c: Ctx) -> void:
	var t := c.torso
	var hw := c.hip_w
	match style:
		"jeans":
			P.box(t, Vector3(hw + 0.006, 0.03, c.depth + 0.006), Vector3(0, 0.165, 0), P.mat(Color(0.15, 0.13, 0.12)))
		"shorts":
			P.box(t, Vector3(hw + 0.006, 0.025, c.depth + 0.006), Vector3(0, 0.165, 0), c.m3)
		"skirt":
			P.cyl(t, hw * 0.5, hw * 0.82, 0.32, Vector3(0, -0.1, 0), c.m2)
			P.cyl(t, hw * 0.82, hw * 0.83, 0.03, Vector3(0, -0.25, 0), c.m3)
		"longskirt":
			P.cyl(t, hw * 0.5, hw * 1.0, 0.8, Vector3(0, -0.32, 0), c.m2)
			P.cyl(t, hw * 1.0, hw * 1.01, 0.04, Vector3(0, -0.72, 0), c.m3)
		"greaves":
			P.box(t, Vector3(hw + 0.02, 0.07, c.depth + 0.02), Vector3(0, 0.15, 0), c.m3)
			for leg: Node3D in [c.leg_l, c.leg_r]:
				P.box(leg, Vector3(c.leg_w + 0.03, 0.09, c.leg_w + 0.03), Vector3(0, -0.45, 0), c.m3)
				P.box(leg, Vector3(c.leg_w + 0.025, 0.34, c.leg_w + 0.025), Vector3(0, -0.66, 0), c.m3)
		"cargo":
			P.box(t, Vector3(hw + 0.006, 0.03, c.depth + 0.006), Vector3(0, 0.165, 0), c.m3)
			for leg: Node3D in [c.leg_l, c.leg_r]:
				P.box(leg, Vector3(c.leg_w + 0.02, 0.13, c.leg_w + 0.02), Vector3(0, -0.3, 0), c.m3)
		"kilt":
			P.cyl(t, hw * 0.5, hw * 0.78, 0.42, Vector3(0, -0.12, 0), c.m2)
			for i in 3:
				P.cyl(t, hw * (0.58 + i * 0.1), hw * (0.6 + i * 0.1), 0.025, Vector3(0, -0.02 - i * 0.1, 0), c.m3)
		"hakama":
			P.box(t, Vector3(hw + 0.02, 0.06, c.depth + 0.02), Vector3(0, 0.15, 0), c.m3)
			for leg: Node3D in [c.leg_l, c.leg_r]:
				P.box(leg, Vector3(c.leg_w * 2.0, 0.7, c.leg_w * 2.2), Vector3(0, -0.4, 0), c.m2)
		"leggings":
			for s: float in [-1.0, 1.0]:
				var leg := c.leg_l if s < 0.0 else c.leg_r
				P.box(leg, Vector3(0.016, 0.82, c.leg_w * 0.5), Vector3(s * (c.leg_w * 0.5 + 0.002), -0.45, 0), c.m3)
		"overalls":
			P.box(t, Vector3(c.chest_w * 0.5, 0.2, 0.014), Vector3(0, 0.34, -c.depth * 0.5 - 0.008), c.m2)
			for s: float in [-1.0, 1.0]:
				P.box(t, Vector3(0.03, 0.2, c.depth + 0.014), Vector3(s * c.chest_w * 0.22, 0.44, 0), c.m2)
				P.ball(t, 0.016, Vector3(s * c.chest_w * 0.2, 0.43, -c.depth * 0.5 - 0.016), c.m3)
		"trunks":
			for s: float in [-1.0, 1.0]:
				var leg := c.leg_l if s < 0.0 else c.leg_r
				P.box(leg, Vector3(0.014, 0.26, c.leg_w * 0.45), Vector3(s * (c.leg_w * 0.5 + 0.002), -0.13, 0), c.m3)
			P.box(t, Vector3(hw + 0.006, 0.03, c.depth + 0.006), Vector3(0, 0.165, 0), c.m3)
		"spacepants":
			P.box(t, Vector3(hw + 0.03, 0.05, c.depth + 0.03), Vector3(0, 0.16, 0), c.m3)
			for leg: Node3D in [c.leg_l, c.leg_r]:
				P.box(leg, Vector3(c.leg_w + 0.04, 0.8, c.leg_w + 0.04), Vector3(0, -0.45, 0), c.m2)
				P.box(leg, Vector3(c.leg_w + 0.06, 0.05, c.leg_w + 0.06), Vector3(0, -0.45, 0), c.m3)
		"baggy":
			for leg: Node3D in [c.leg_l, c.leg_r]:
				P.box(leg, Vector3(c.leg_w * 1.5, 0.74, c.leg_w * 1.5), Vector3(0, -0.45, 0), c.m2)
				P.box(leg, Vector3(c.leg_w * 1.55, 0.05, c.leg_w * 1.55), Vector3(0, -0.8, 0), c.m3)
			P.box(t, Vector3(hw + 0.006, 0.03, c.depth + 0.006), Vector3(0, 0.165, 0), c.m3)
		"chaps":
			P.box(t, Vector3(hw + 0.01, 0.04, c.depth + 0.01), Vector3(0, 0.16, 0), c.m3)
			for s: float in [-1.0, 1.0]:
				var leg := c.leg_l if s < 0.0 else c.leg_r
				P.box(leg, Vector3(0.03, 0.74, c.leg_w + 0.04), Vector3(s * (c.leg_w * 0.5 + 0.01), -0.45, 0), c.m3)


# Wide hanging sleeves (robes, kimonos, pirate shirts).
static func _flare(c: Ctx, material: Material, widen: float) -> void:
	for arm: Node3D in [c.arm_l, c.arm_r]:
		P.box(arm, Vector3(c.arm_t * widen, 0.28, c.arm_t * widen), Vector3(0, -0.3, 0), material)
