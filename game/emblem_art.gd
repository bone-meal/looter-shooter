# Purpose: draws the player-card emblems (simple original shapes: chevron, target, flame, shield, crown, star, diamond, coin, bolt, clover, heart, bunny) in two colours onto any CanvasItem.
# Dependencies: none. Shapes and colours are chosen by data/achievements.json (emblems).
extends RefCounted


# Draws `shape` centred at `center` with radius `r`. c1 is the main colour, c2 the accent.
static func draw(ci: CanvasItem, shape: String, center: Vector2, r: float, c1: Color, c2: Color) -> void:
	match shape:
		"chevron":
			_poly(ci, [Vector2(-0.9, -0.1), Vector2(0.0, -0.8), Vector2(0.9, -0.1), Vector2(0.9, 0.2), Vector2(0.0, -0.5), Vector2(-0.9, 0.2)], center, r, c1)
			_poly(ci, [Vector2(-0.9, 0.35), Vector2(0.0, -0.35), Vector2(0.9, 0.35), Vector2(0.9, 0.65), Vector2(0.0, -0.05), Vector2(-0.9, 0.65)], center, r, c2)
		"target":
			ci.draw_circle(center, r * 0.9, c1)
			ci.draw_circle(center, r * 0.65, c2)
			ci.draw_circle(center, r * 0.4, c1)
			ci.draw_circle(center, r * 0.15, c2)
		"flame":
			_poly(ci, [Vector2(0.0, -0.95), Vector2(0.45, -0.3), Vector2(0.75, 0.2), Vector2(0.5, 0.75), Vector2(0.0, 0.95), Vector2(-0.5, 0.75), Vector2(-0.75, 0.2), Vector2(-0.4, -0.2), Vector2(-0.2, -0.5)], center, r, c1)
			_poly(ci, [Vector2(0.0, -0.25), Vector2(0.3, 0.25), Vector2(0.2, 0.65), Vector2(0.0, 0.8), Vector2(-0.2, 0.65), Vector2(-0.3, 0.25)], center, r, c2)
		"shield":
			_poly(ci, [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.05), Vector2(0.0, 0.95), Vector2(-0.8, 0.05)], center, r, c1)
			_poly(ci, [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.0), Vector2(0.0, 0.6), Vector2(-0.5, 0.0)], center, r, c2)
		"crown":
			_poly(ci, [Vector2(-0.9, 0.65), Vector2(-0.9, -0.55), Vector2(-0.45, 0.0), Vector2(0.0, -0.85), Vector2(0.45, 0.0), Vector2(0.9, -0.55), Vector2(0.9, 0.65)], center, r, c1)
			_poly(ci, [Vector2(-0.9, 0.3), Vector2(0.9, 0.3), Vector2(0.9, 0.65), Vector2(-0.9, 0.65)], center, r, c2)
			ci.draw_circle(center + Vector2(0.0, -0.85) * r, r * 0.1, c2)
		"star":
			var pts: Array = []
			for i in 10:
				var ang := -PI * 0.5 + float(i) * PI / 5.0
				var rad := 0.95 if i % 2 == 0 else 0.4
				pts.append(Vector2(cos(ang), sin(ang)) * rad)
			_poly(ci, pts, center, r, c1)
			ci.draw_circle(center, r * 0.18, c2)
		"diamond":
			_poly(ci, [Vector2(0.0, -0.95), Vector2(0.8, -0.2), Vector2(0.0, 0.95), Vector2(-0.8, -0.2)], center, r, c1)
			_poly(ci, [Vector2(0.0, -0.95), Vector2(0.8, -0.2), Vector2(-0.8, -0.2)], center, r, c2)
		"coin":
			ci.draw_circle(center, r * 0.92, c2)
			ci.draw_circle(center, r * 0.78, c1)
			ci.draw_rect(Rect2(center + Vector2(-0.1, -0.5) * r, Vector2(0.2, 1.0) * r), c2)
			ci.draw_rect(Rect2(center + Vector2(-0.35, -0.15) * r, Vector2(0.7, 0.3) * r), c2)
		"bolt":
			_poly(ci, [Vector2(0.15, -0.95), Vector2(-0.6, 0.1), Vector2(-0.05, 0.1), Vector2(-0.2, 0.95), Vector2(0.6, -0.15), Vector2(0.05, -0.15)], center, r, c1)
		"clover":
			for off: Vector2 in [Vector2(-0.35, -0.35), Vector2(0.35, -0.35), Vector2(-0.35, 0.3), Vector2(0.35, 0.3)]:
				ci.draw_circle(center + off * r, r * 0.4, c1)
			ci.draw_line(center + Vector2(0.0, 0.1) * r, center + Vector2(0.15, 0.95) * r, c2, maxf(r * 0.12, 2.0))
		"heart":
			ci.draw_circle(center + Vector2(-0.36, -0.3) * r, r * 0.45, c1)
			ci.draw_circle(center + Vector2(0.36, -0.3) * r, r * 0.45, c1)
			_poly(ci, [Vector2(-0.78, -0.12), Vector2(0.78, -0.12), Vector2(0.0, 0.9)], center, r, c1)
			ci.draw_circle(center + Vector2(-0.4, -0.38) * r, r * 0.12, c2)
		"bunny":
			_poly(ci, [Vector2(-0.45, -0.1), Vector2(-0.3, -0.95), Vector2(-0.1, -0.1)], center, r, c1)
			_poly(ci, [Vector2(0.1, -0.1), Vector2(0.3, -0.95), Vector2(0.45, -0.1)], center, r, c1)
			_poly(ci, [Vector2(-0.35, -0.2), Vector2(-0.28, -0.7), Vector2(-0.17, -0.2)], center, r, c2)
			_poly(ci, [Vector2(0.17, -0.2), Vector2(0.28, -0.7), Vector2(0.35, -0.2)], center, r, c2)
			ci.draw_circle(center + Vector2(0.0, 0.3) * r, r * 0.6, c1)
			ci.draw_circle(center + Vector2(-0.2, 0.25) * r, r * 0.07, c2)
			ci.draw_circle(center + Vector2(0.2, 0.25) * r, r * 0.07, c2)
		_:
			ci.draw_circle(center, r * 0.8, c1)


static func _poly(ci: CanvasItem, unit: Array, center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in unit:
		pts.append(center + p * r)
	ci.draw_colored_polygon(pts, color)
