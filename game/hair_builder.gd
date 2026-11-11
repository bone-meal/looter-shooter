# Purpose: builds one of 20 hair styles from boxes, balls and cones on the head, in any color.
# Dependencies: game/body_parts.gd, game/body_ctx.gd. Style IDs are listed in data/appearance.json "hair_styles".
extends RefCounted

const P = preload("res://game/body_parts.gd")
const Ctx = preload("res://game/body_ctx.gd")


# Head-local coordinates: the head spans y 0..0.24, front is -Z.
static func build(c: Ctx, style: String) -> void:
	var h := P.pivot(c.head, "Hair", Vector3.ZERO)
	var m := P.mat(c.hair_color)
	var hw := c.head_w
	var hd := c.head_d
	match style:
		"buzz":
			_cap(h, m, hw, hd, 0.005)
		"crop":
			_cap(h, m, hw, hd)
		"sidepart":
			_cap(h, m, hw, hd)
			P.box(h, Vector3(hw * 0.65, 0.05, 0.03), Vector3(-hw * 0.14, 0.205, -hd * 0.5 - 0.01), m, Vector3(0, 0, 10))
		"pompadour":
			_cap(h, m, hw, hd)
			P.box(h, Vector3(hw * 0.7, 0.08, hd * 0.9), Vector3(0, 0.29, -0.02), m, Vector3(-12, 0, 0))
		"spiky":
			_cap(h, m, hw, hd)
			for i in 7:
				var ang := float(i) / 7.0 * TAU
				P.cyl(h, 0.0, 0.032, 0.1, Vector3(cos(ang) * hw * 0.32, 0.29, sin(ang) * hd * 0.32), m, Vector3(sin(ang) * 25.0, 0, -cos(ang) * 25.0))
			P.cyl(h, 0.0, 0.035, 0.12, Vector3(0, 0.3, 0), m)
		"mohawk":
			P.box(h, Vector3(0.045, 0.1, hd + 0.03), Vector3(0, 0.285, 0), m)
			P.box(h, Vector3(0.045, 0.07, 0.04), Vector3(0, 0.24, hd * 0.5 + 0.02), m)
		"afro":
			P.ball(h, 0.2, Vector3(0, 0.2, 0.015), m, Vector3(1.0, 0.92, 1.0))
		"curly":
			_cap(h, m, hw, hd)
			for i in 8:
				var ang := float(i) / 8.0 * TAU
				P.ball(h, 0.05, Vector3(cos(ang) * hw * 0.34, 0.285, sin(ang) * hd * 0.34), m)
			P.ball(h, 0.055, Vector3(0, 0.3, 0), m)
		"undercut":
			_cap(h, m, hw, hd, 0.005)
			P.ball(h, hw * 0.42, Vector3(0, 0.255, -0.01), m, Vector3(1.0, 0.45, 1.15))
		"mullet":
			_cap(h, m, hw, hd)
			P.box(h, Vector3(hw + 0.02, 0.3, 0.05), Vector3(0, 0.0, hd * 0.5 + 0.02), m)
		"bob":
			_cap(h, m, hw, hd)
			P.box(h, Vector3(hw + 0.06, 0.2, 0.05), Vector3(0, 0.1, hd * 0.5 + 0.02), m)
			for s: float in [-1.0, 1.0]:
				P.box(h, Vector3(0.045, 0.2, hd + 0.02), Vector3(s * (hw * 0.5 + 0.02), 0.11, 0), m)
			P.box(h, Vector3(hw + 0.02, 0.06, 0.03), Vector3(0, 0.2, -hd * 0.5 - 0.012), m)
		"long_straight":
			_long(h, m, hw, hd, false)
		"long_wavy":
			_long(h, m, hw, hd, true)
		"ponytail":
			_cap(h, m, hw, hd)
			P.box(h, Vector3(0.065, 0.3, 0.065), Vector3(0, 0.04, hd * 0.5 + 0.07), m, Vector3(-12, 0, 0))
			P.ball(h, 0.04, Vector3(0, 0.19, hd * 0.5 + 0.035), P.mat(c.c3))
		"high_ponytail":
			_cap(h, m, hw, hd)
			P.box(h, Vector3(0.06, 0.28, 0.06), Vector3(0, 0.32, hd * 0.5 + 0.06), m, Vector3(25, 0, 0))
			P.ball(h, 0.04, Vector3(0, 0.27, hd * 0.5 + 0.03), P.mat(c.c3))
		"twin_tails":
			_cap(h, m, hw, hd)
			for s: float in [-1.0, 1.0]:
				P.box(h, Vector3(0.06, 0.32, 0.06), Vector3(s * (hw * 0.5 + 0.08), 0.06, 0.03), m, Vector3(0, 0, s * 6.0))
				P.ball(h, 0.035, Vector3(s * (hw * 0.5 + 0.06), 0.21, 0.03), P.mat(c.c3))
		"twin_buns":
			_cap(h, m, hw, hd)
			for s: float in [-1.0, 1.0]:
				P.ball(h, 0.065, Vector3(s * 0.075, 0.3, 0.02), m)
		"bun":
			_cap(h, m, hw, hd)
			P.ball(h, 0.075, Vector3(0, 0.315, 0.025), m)
		"braids":
			_cap(h, m, hw, hd)
			for s: float in [-1.0, 1.0]:
				for i in 5:
					P.ball(h, 0.034, Vector3(s * (hw * 0.5 + 0.03), 0.14 - i * 0.055, 0.05 + (0.012 if i % 2 == 0 else -0.012)), m)
		"bangs":
			_cap(h, m, hw, hd)
			P.box(h, Vector3(hw + 0.03, 0.09, 0.03), Vector3(0, 0.185, -hd * 0.5 - 0.012), m)
			P.box(h, Vector3(hw + 0.04, 0.2, 0.05), Vector3(0, 0.1, hd * 0.5 + 0.02), m)


# Rounded hair cap over the top, back and sides of the skull (hairline above the brows), plus sideburns.
static func _cap(h: Node3D, m: Material, hw: float, hd: float, thick := 0.014) -> void:
	var r := hw * 0.5 + thick
	P.ball(h, r, Vector3(0, 0.15, 0.025), m, Vector3(1.0, 0.122 / r, (hd * 0.5 + thick * 0.6) / r))
	for s: float in [-1.0, 1.0]:
		P.ball(h, 0.022, Vector3(s * (hw * 0.5 - 0.004), 0.12, -0.02), m, Vector3(0.5, 1.6, 0.9))


static func _long(h: Node3D, m: Material, hw: float, hd: float, wavy: bool) -> void:
	_cap(h, m, hw, hd)
	if wavy:
		for i in 5:
			var off := 0.014 if i % 2 == 0 else -0.014
			P.box(h, Vector3(hw + 0.07, 0.11, 0.055), Vector3(off, 0.1 - i * 0.1, hd * 0.5 + 0.025), m)
		for s: float in [-1.0, 1.0]:
			for i in 3:
				P.ball(h, 0.04, Vector3(s * (hw * 0.5 + 0.03), 0.04 - i * 0.09, 0.0 + (0.015 if i % 2 == 0 else -0.015)), m)
	else:
		P.box(h, Vector3(hw + 0.06, 0.5, 0.05), Vector3(0, -0.03, hd * 0.5 + 0.02), m)
		for s: float in [-1.0, 1.0]:
			P.box(h, Vector3(0.04, 0.36, 0.1), Vector3(s * (hw * 0.5 + 0.025), 0.02, 0.0), m)
