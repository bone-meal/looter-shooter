# Purpose: the one look of each of the game's three monies, drawn the same everywhere (director: "Coins, chips,
# doubloons different and correct icons"): (polish1 E5) GIL = the chips' name and coin in Aurelind; POINTS = the island's coins (a bright milled gold coin with a star), CHIPS =
# the casino's poker chip (game/chip_art.gd), DOUBLOONS = the sea's money (an old struck coin of darker gold, a little
# out of round, with a cross and a dotted rim). draw(canvas, kind, centre, radius) on any CanvasItem.
# Dependencies: game/chip_art.gd.
extends RefCounted

const ChipArt = preload("res://game/chip_art.gd")

const GOLD := Color(1.0, 0.82, 0.25)
const GOLD_DARK := Color(0.78, 0.56, 0.12)
const OLD_GOLD := Color(0.86, 0.64, 0.2)
const OLD_DARK := Color(0.55, 0.38, 0.1)


static func draw(ci: CanvasItem, kind: String, centre: Vector2, r: float) -> void:
	match kind:
		"chips":
			ChipArt.draw(ci, centre, r)
		"doubloons":
			_doubloon(ci, centre, r)
		"gil":
			_gil(ci, centre, r)
		_:
			_coin(ci, centre, r)


# The island's coin (points): round, bright, a milled rim and a five-pointed star.
static func _coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, GOLD_DARK)
	for i in 20:  # milling on the edge
		var a := float(i) * TAU / 20.0
		ci.draw_line(c + Vector2.from_angle(a) * r * 0.82, c + Vector2.from_angle(a) * r, GOLD, maxf(r * 0.1, 1.0))
	ci.draw_circle(c, r * 0.76, GOLD)
	var star := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + float(i) * TAU / 10.0
		star.append(c + Vector2.from_angle(a) * r * (0.5 if i % 2 == 0 else 0.22))
	ci.draw_colored_polygon(star, GOLD_DARK)
	ci.draw_arc(c, r, 0.0, TAU, 24, Color(0, 0, 0, 0.45), maxf(r * 0.08, 1.0), true)


# (polish1 E5) GIL: what the game's chips are called in Aurelind (director): a minted coin, not a poker chip. A thick
# rim of pale gold round a rose-gold face with a little three-pointed crown over a bar.
static func _gil(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, Color(0.72, 0.55, 0.22))
	ci.draw_circle(c, r * 0.8, Color(0.93, 0.74, 0.38))
	ci.draw_arc(c, r * 0.8, 0.0, TAU, 24, Color(0.62, 0.42, 0.16), maxf(r * 0.07, 1.0), true)
	var crown := PackedVector2Array([c + Vector2(-0.42, 0.18) * r, c + Vector2(-0.42, -0.3) * r, c + Vector2(-0.2, -0.06) * r, c + Vector2(0.0, -0.4) * r,
		c + Vector2(0.2, -0.06) * r, c + Vector2(0.42, -0.3) * r, c + Vector2(0.42, 0.18) * r])
	ci.draw_colored_polygon(crown, Color(0.62, 0.42, 0.16))
	ci.draw_rect(Rect2(c + Vector2(-0.42, 0.26) * r, Vector2(0.84, 0.14) * r), Color(0.62, 0.42, 0.16))
	ci.draw_arc(c, r, 0.0, TAU, 24, Color(0, 0, 0, 0.45), maxf(r * 0.08, 1.0), true)


# The sea's doubloon: hand-struck, out of round, a cross with dotted ends, a ring of dots.
static func _doubloon(ci: CanvasItem, c: Vector2, r: float) -> void:
	var edge := PackedVector2Array()
	for i in 14:
		var a := float(i) * TAU / 14.0
		edge.append(c + Vector2.from_angle(a) * r * (1.0 + 0.06 * sin(a * 3.0 + 0.7)))
	ci.draw_colored_polygon(edge, OLD_DARK)
	var face := PackedVector2Array()
	for p: Vector2 in edge:
		face.append(c + (p - c) * 0.84)
	ci.draw_colored_polygon(face, OLD_GOLD)
	for i in 12:  # the ring of dots
		ci.draw_circle(c + Vector2.from_angle(float(i) * TAU / 12.0) * r * 0.66, maxf(r * 0.06, 0.8), OLD_DARK)
	var arm := r * 0.42
	var w := maxf(r * 0.16, 1.5)
	ci.draw_line(c + Vector2(-arm, 0), c + Vector2(arm, 0), OLD_DARK, w)
	ci.draw_line(c + Vector2(0, -arm), c + Vector2(0, arm), OLD_DARK, w)
	for d: Vector2 in [Vector2(arm, 0), Vector2(-arm, 0), Vector2(0, arm), Vector2(0, -arm)]:
		ci.draw_circle(c + d, w * 0.75, OLD_DARK)
	edge.append(edge[0])
	ci.draw_polyline(edge, Color(0, 0, 0, 0.45), maxf(r * 0.08, 1.0), true)
