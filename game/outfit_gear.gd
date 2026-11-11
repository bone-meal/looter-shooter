# Purpose: the accessory pieces of the 100 outfits: 23 headwear styles, 10 backpieces, 6 shoe styles, 5 neck items and 3 hand items.
# Dependencies: game/body_parts.gd, game/body_ctx.gd. Style IDs come from data/outfits.json.
extends RefCounted

const P = preload("res://game/body_parts.gd")
const Ctx = preload("res://game/body_ctx.gd")

# Headwear that fully covers the hair.
const HIDES_HAIR := ["knight", "hood", "viking", "spacehelm"]


static func hides_hair(head_style: String) -> bool:
	return HIDES_HAIR.has(head_style)


# Head-local coordinates (head spans y 0..0.24, front is -Z).
static func add_head(style: String, c: Ctx) -> void:
	var h := c.head
	var hw := c.head_w
	var hd := c.head_d
	match style:
		"cap":
			P.ball(h, hw * 0.58, Vector3(0, 0.22, 0), c.m1, Vector3(1.0, 0.55, 1.0))
			P.box(h, Vector3(hw * 0.85, 0.012, 0.1), Vector3(0, 0.215, -hd * 0.5 - 0.04), c.m3)
		"beanie":
			P.cyl(h, 0.1, 0.14, 0.1, Vector3(0, 0.27, 0), c.m1)
			P.cyl(h, 0.142, 0.142, 0.04, Vector3(0, 0.225, 0), c.m3)
			P.ball(h, 0.04, Vector3(0, 0.34, 0), c.m3)
		"tophat":
			P.cyl(h, 0.11, 0.11, 0.2, Vector3(0, 0.35, 0), c.m1)
			P.cyl(h, 0.18, 0.18, 0.015, Vector3(0, 0.25, 0), c.m1)
			P.cyl(h, 0.112, 0.112, 0.04, Vector3(0, 0.285, 0), c.m3)
		"cowboy":
			P.cyl(h, 0.21, 0.21, 0.012, Vector3(0, 0.25, 0), c.m1)
			P.cyl(h, 0.085, 0.105, 0.1, Vector3(0, 0.305, 0), c.m1)
			P.cyl(h, 0.106, 0.106, 0.025, Vector3(0, 0.275, 0), c.m3)
		"crown":
			P.cyl(h, 0.105, 0.115, 0.07, Vector3(0, 0.285, 0), c.m3)
			for i in 6:
				var ang := float(i) / 6.0 * TAU
				P.cyl(h, 0.0, 0.025, 0.07, Vector3(cos(ang) * 0.1, 0.35, sin(ang) * 0.1), c.m3)
			P.ball(h, 0.022, Vector3(0, 0.285, -0.115), c.m1)
		"knight":
			P.box(h, Vector3(hw + 0.04, 0.28, hd + 0.04), Vector3(0, 0.13, 0), c.m1)
			P.box(h, Vector3(hw * 0.8, 0.025, 0.012), Vector3(0, 0.15, -hd * 0.5 - 0.022), P.mat(Color(0.05, 0.05, 0.07)))
			P.box(h, Vector3(0.03, 0.12, 0.2), Vector3(0, 0.33, 0.0), c.m3)
		"spacehelm":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.7, 0.9, 1.0, 0.28)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			P.ball(h, 0.2, Vector3(0, 0.13, 0), glass)
			P.torus(h, 0.1, 0.17, Vector3(0, -0.01, 0), c.m3)
		"bandana":
			P.box(h, Vector3(hw + 0.02, 0.05, hd + 0.02), Vector3(0, 0.205, 0), c.m1)
			P.box(h, Vector3(0.05, 0.05, 0.03), Vector3(0.03, 0.2, hd * 0.5 + 0.03), c.m3, Vector3(0, 0, 25))
		"headphones":
			P.box(h, Vector3(hw + 0.1, 0.02, 0.03), Vector3(0, 0.265, 0), c.m1)
			for s: float in [-1.0, 1.0]:
				P.cyl(h, 0.05, 0.05, 0.045, Vector3(s * (hw * 0.5 + 0.045), 0.13, 0), c.m1, Vector3(0, 0, 90))
				P.box(h, Vector3(0.018, 0.14, 0.03), Vector3(s * (hw * 0.5 + 0.045), 0.2, 0), c.m3)
		"chef":
			P.cyl(h, 0.115, 0.105, 0.16, Vector3(0, 0.32, 0), c.m1)
			P.ball(h, 0.13, Vector3(0, 0.43, 0), c.m1, Vector3(1.0, 0.8, 1.0))
		"piratehat":
			P.box(h, Vector3(0.36, 0.04, 0.2), Vector3(0, 0.27, 0), c.m1, Vector3(0, 0, 0))
			P.box(h, Vector3(0.2, 0.08, 0.2), Vector3(0, 0.32, 0), c.m1)
			P.ball(h, 0.03, Vector3(0, 0.3, -0.105), c.m3)
		"wizard":
			P.cyl(h, 0.0, 0.14, 0.36, Vector3(0, 0.43, 0), c.m1, Vector3(-6, 0, 0))
			P.cyl(h, 0.2, 0.2, 0.012, Vector3(0, 0.25, 0), c.m1)
			P.cyl(h, 0.142, 0.142, 0.035, Vector3(0, 0.275, 0), c.m3)
		"bunnyears":
			for s: float in [-1.0, 1.0]:
				P.box(h, Vector3(0.05, 0.28, 0.025), Vector3(s * 0.06, 0.4, 0.02), c.m3, Vector3(0, 0, -s * 8.0))
				P.box(h, Vector3(0.026, 0.2, 0.015), Vector3(s * 0.06, 0.4, -0.004), c.m1, Vector3(0, 0, -s * 8.0))
		"catears":
			for s: float in [-1.0, 1.0]:
				P.cyl(h, 0.0, 0.05, 0.09, Vector3(s * 0.075, 0.29, 0), c.m1, Vector3(0, 0, -s * 12.0))
				P.cyl(h, 0.0, 0.03, 0.06, Vector3(s * 0.075, 0.285, -0.012), c.m3, Vector3(0, 0, -s * 12.0))
		"halo":
			P.torus(h, 0.085, 0.11, Vector3(0, 0.42, 0), P.mat(Color(1.0, 0.85, 0.25), true))
		"horns":
			for s: float in [-1.0, 1.0]:
				P.cyl(h, 0.0, 0.035, 0.15, Vector3(s * 0.09, 0.3, -0.02), c.m3, Vector3(0, 0, -s * 25.0))
		"party":
			P.cyl(h, 0.0, 0.075, 0.22, Vector3(0, 0.34, 0), c.m1, Vector3(0, 0, 8))
			P.ball(h, 0.03, Vector3(0.03, 0.45, 0), c.m3)
		"viking":
			P.ball(h, 0.15, Vector3(0, 0.2, 0), c.m1, Vector3(1.0, 0.7, 1.0))
			P.box(h, Vector3(0.03, 0.12, 0.012), Vector3(0, 0.15, -hd * 0.5 - 0.03), c.m1)
			for s: float in [-1.0, 1.0]:
				P.cyl(h, 0.0, 0.04, 0.17, Vector3(s * 0.15, 0.3, 0), c.m3, Vector3(0, 0, -s * 60.0))
		"headband":
			P.box(h, Vector3(hw + 0.015, 0.035, hd + 0.015), Vector3(0, 0.2, 0), c.m1)
			for s: float in [-1.0, 1.0]:
				P.box(h, Vector3(0.03, 0.13, 0.015), Vector3(s * 0.025, 0.14, hd * 0.5 + 0.03), c.m1, Vector3(0, 0, s * 12.0))
		"hood":
			P.box(h, Vector3(hw + 0.09, 0.3, 0.1), Vector3(0, 0.12, hd * 0.5 + 0.04), c.m1)
			P.box(h, Vector3(hw + 0.1, 0.06, hd + 0.08), Vector3(0, 0.25, 0.0), c.m1)
			for s: float in [-1.0, 1.0]:
				P.box(h, Vector3(0.05, 0.27, hd + 0.04), Vector3(s * (hw * 0.5 + 0.03), 0.12, 0.0), c.m1)
		"sunhat":
			P.cyl(h, 0.23, 0.23, 0.01, Vector3(0, 0.25, 0), c.m1)
			P.cyl(h, 0.1, 0.12, 0.08, Vector3(0, 0.29, 0), c.m1)
			P.cyl(h, 0.121, 0.121, 0.03, Vector3(0, 0.275, 0), c.m3)
		"beret":
			P.ball(h, 0.14, Vector3(0.02, 0.265, 0), c.m1, Vector3(1.0, 0.35, 1.0))
			P.cyl(h, 0.012, 0.012, 0.04, Vector3(0.02, 0.31, 0), c.m3)


# Torso-local coordinates; the back of the body is +Z.
static func add_back(style: String, c: Ctx) -> void:
	var t := c.torso
	var bz := c.depth * 0.5
	match style:
		"cape":
			P.box(t, Vector3(c.chest_w + 0.08, 0.82, 0.02), Vector3(0, 0.1, bz + 0.05), c.m3, Vector3(-6, 0, 0))
			P.ball(t, 0.025, Vector3(0, 0.55, -bz - 0.01), c.m1)
		"backpack":
			P.box(t, Vector3(0.27, 0.36, 0.14), Vector3(0, 0.34, bz + 0.08), c.m3)
			P.box(t, Vector3(0.2, 0.14, 0.04), Vector3(0, 0.28, bz + 0.17), c.m1)
			for s: float in [-1.0, 1.0]:
				P.box(t, Vector3(0.03, 0.3, 0.012), Vector3(s * c.chest_w * 0.28, 0.4, -bz - 0.006), c.m3)
		"wings":
			for s: float in [-1.0, 1.0]:
				for i in 3:
					P.box(t, Vector3(0.05, 0.34 - i * 0.07, 0.015), Vector3(s * (0.16 + i * 0.07), 0.46 - i * 0.03, bz + 0.07), c.m3, Vector3(0, s * 25.0, s * (-18.0 + i * 12.0)))
		"quiver":
			P.cyl(t, 0.045, 0.04, 0.4, Vector3(0.09, 0.4, bz + 0.07), c.m3, Vector3(0, 0, -18))
			for i in 3:
				P.cyl(t, 0.006, 0.006, 0.14, Vector3(0.05 + i * 0.03, 0.62, bz + 0.07), c.m1, Vector3(0, 0, -18))
		"foxtail":
			P.ball(t, 0.055, Vector3(0, 0.1, bz + 0.07), c.m3)
			P.ball(t, 0.075, Vector3(0, 0.14, bz + 0.16), c.m3, Vector3(1.0, 1.2, 1.0))
			P.ball(t, 0.065, Vector3(0, 0.24, bz + 0.2), c.m1)
		"jetpack":
			for s: float in [-1.0, 1.0]:
				P.cyl(t, 0.07, 0.07, 0.36, Vector3(s * 0.09, 0.36, bz + 0.1), c.m3)
				P.cyl(t, 0.05, 0.075, 0.07, Vector3(s * 0.09, 0.14, bz + 0.1), c.m1)
				P.ball(t, 0.04, Vector3(s * 0.09, 0.09, bz + 0.1), P.mat(Color(1.0, 0.55, 0.15), true))
		"guitar":
			P.ball(t, 0.13, Vector3(0, 0.2, bz + 0.07), c.m3, Vector3(0.9, 1.1, 0.3))
			P.box(t, Vector3(0.035, 0.5, 0.02), Vector3(0.04, 0.55, bz + 0.07), c.m1, Vector3(0, 0, -12))
		"shell":
			P.ball(t, 0.23, Vector3(0, 0.34, bz + 0.1), c.m3, Vector3(1.0, 1.0, 0.45))
			P.box(t, Vector3(0.1, 0.1, 0.02), Vector3(0, 0.34, bz + 0.2), c.m1, Vector3(0, 0, 45))
		"sword":
			P.box(t, Vector3(0.04, 0.72, 0.014), Vector3(0, 0.34, bz + 0.06), c.m1, Vector3(0, 0, 38))
			P.box(t, Vector3(0.12, 0.025, 0.03), Vector3(-0.2, 0.06, bz + 0.06), c.m3, Vector3(0, 0, 38))


# Leg-local coordinates; the foot is at y -0.88.
static func add_feet(style: String, c: Ctx) -> void:
	for leg: Node3D in [c.leg_l, c.leg_r]:
		var w := c.leg_w
		match style:
			"sneakers":
				P.box(leg, Vector3(w + 0.025, 0.08, 0.27), Vector3(0, -0.84, -0.05), c.m3)
				P.box(leg, Vector3(w + 0.03, 0.02, 0.28), Vector3(0, -0.87, -0.05), P.mat(Color(0.95, 0.95, 0.95)))
			"boots":
				P.box(leg, Vector3(w + 0.035, 0.24, 0.27), Vector3(0, -0.76, -0.04), c.m3)
				P.box(leg, Vector3(w + 0.045, 0.03, w + 0.045), Vector3(0, -0.64, 0), c.m1)
			"plateboots":
				P.box(leg, Vector3(w + 0.045, 0.26, 0.29), Vector3(0, -0.75, -0.05), c.m1)
				P.box(leg, Vector3(w + 0.05, 0.05, 0.1), Vector3(0, -0.84, -0.17), c.m3)
				P.box(leg, Vector3(w + 0.055, 0.03, w + 0.055), Vector3(0, -0.62, 0), c.m3)
			"geta":
				P.box(leg, Vector3(w + 0.02, 0.025, 0.25), Vector3(0, -0.855, -0.04), c.m3)
				P.box(leg, Vector3(w + 0.02, 0.04, 0.03), Vector3(0, -0.88, -0.11), c.m3)
				P.box(leg, Vector3(w + 0.02, 0.04, 0.03), Vector3(0, -0.88, 0.03), c.m3)
				P.box(leg, Vector3(w + 0.03, 0.02, 0.04), Vector3(0, -0.83, -0.08), c.m1)
			"flats":
				P.box(leg, Vector3(w + 0.02, 0.05, 0.25), Vector3(0, -0.855, -0.04), c.m3)
			"clogs":
				P.ball(leg, 0.095, Vector3(0, -0.82, -0.05), c.m3, Vector3(0.85, 0.7, 1.35))
				P.box(leg, Vector3(w + 0.025, 0.03, 0.25), Vector3(0, -0.87, -0.05), c.m1)


static func add_neck(style: String, c: Ctx) -> void:
	var t := c.torso
	var fz := -c.depth * 0.5
	match style:
		"scarf":
			P.cyl(t, 0.085, 0.09, 0.07, Vector3(0, 0.55, 0), c.m3)
			P.box(t, Vector3(0.06, 0.24, 0.02), Vector3(0.07, 0.42, fz - 0.02), c.m3)
		"necklace":
			P.torus(t, 0.005, 0.075, Vector3(0, 0.52, 0), P.mat(Color(0.95, 0.8, 0.3)), Vector3(70, 0, 0))
			P.ball(t, 0.02, Vector3(0, 0.46, fz - 0.03), c.m3)
		"bowtie":
			for s: float in [-1.0, 1.0]:
				P.cyl(t, 0.0, 0.035, 0.05, Vector3(s * 0.035, 0.53, fz - 0.015), c.m3, Vector3(0, 0, -s * 90.0))
			P.ball(t, 0.014, Vector3(0, 0.53, fz - 0.018), c.m1)
		"tie":
			P.box(t, Vector3(0.04, 0.24, 0.012), Vector3(0, 0.42, fz - 0.01), c.m3)
			P.box(t, Vector3(0.05, 0.04, 0.02), Vector3(0, 0.54, fz - 0.01), c.m3)


# Arm-local coordinates; the hand is at y -0.55.
static func add_hands(style: String, c: Ctx) -> void:
	for arm: Node3D in [c.arm_l, c.arm_r]:
		match style:
			"gloves":
				P.box(arm, Vector3(c.arm_t * 0.98, 0.13, c.arm_t * 0.98), Vector3(0, -0.48, 0), c.m3)
				P.ball(arm, c.arm_t * 0.56, Vector3(0, -0.58, -c.arm_t * 0.07), c.m3, Vector3(0.78, 1.32, 0.98))
			"gauntlets":
				P.box(arm, Vector3(c.arm_t + 0.04, 0.2, c.arm_t + 0.04), Vector3(0, -0.43, 0), c.m1)
				P.box(arm, Vector3(c.arm_t + 0.02, 0.1, c.arm_t + 0.02), Vector3(0, -0.52, 0), c.m3)
				P.ball(arm, c.arm_t * 0.58, Vector3(0, -0.58, -c.arm_t * 0.07), c.m1, Vector3(0.8, 1.3, 1.0))
