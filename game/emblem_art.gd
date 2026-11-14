# Purpose: draws the player-card emblems onto any CanvasItem. Three kinds (data/achievements.json "emblems"):
# a plain shape in two colours ("shape", the first ones); a LAYERED emblem = a frame ("frame", colours c3 / c4) with a
# symbol on it ("symbol", colours c1 / c2); a PAINTED one = a picture ("picture", res:// path) in a ring.
# Every shape, frame and symbol is our own simple drawing.
# Dependencies: none.
extends RefCounted

const FRAMES := ["disc", "shield", "hex", "diamond", "badge", "banner", "laurel", "wings", "square", "cog"]
const SYMBOLS := ["skull", "swords", "anchor", "wave", "palm", "bell", "crow", "gear", "knife", "wheat", "axe", "pickaxe", "anvil", "fish", "flask", "orb", "moon", "sun", "mountain", "tower", "key", "eye", "feather", "hourglass", "compass", "trident", "horseshoe", "dice", "spade", "ship", "bullet", "crosshair", "snowflake", "leaf", "flower", "paw", "fist", "tentacle", "lantern", "note", "boot", "bear", "chevron", "target", "flame", "shield", "crown", "star", "diamond", "coin", "bolt", "clover", "heart", "bunny", "card", "fan", "lobster", "pack", "binder", "chip"]

static var _pictures := {}  # res:// path -> Texture2D (painted emblems, loaded once)


# Any emblem definition, centred at `center` with radius `r`.
static func draw_def(ci: CanvasItem, def: Dictionary, center: Vector2, r: float) -> void:
	if def.has("picture"):
		var path := String(def["picture"])
		if not _pictures.has(path):
			_pictures[path] = load(path) if ResourceLoader.exists(path) else null
		var art: Texture2D = _pictures[path]
		ci.draw_circle(center, r, Color.html(String(def.get("c3", "#2a2a33"))))
		if art != null:
			ci.draw_texture_rect(art, Rect2(center - Vector2(r, r) * 0.92, Vector2(r, r) * 1.84), false)
		ci.draw_arc(center, r * 0.96, 0.0, TAU, 48, Color.html(String(def.get("c4", "#ffd34d"))), maxf(r * 0.08, 2.0), true)
		return
	var c1 := Color.html(String(def.get("c1", "#ffffff")))
	var c2 := Color.html(String(def.get("c2", "#888888")))
	if def.has("frame"):
		frame(ci, String(def["frame"]), center, r, Color.html(String(def.get("c3", "#30343c"))), Color.html(String(def.get("c4", "#8a8f98"))))
		draw(ci, String(def.get("symbol", "star")), center, r * 0.6, c1, c2)
		return
	draw(ci, String(def.get("shape", "chevron")), center, r, c1, c2)


# The back of a layered emblem: its shape in c3 with an edge or trim in c4.
static func frame(ci: CanvasItem, kind: String, center: Vector2, r: float, c3: Color, c4: Color) -> void:
	match kind:
		"disc":
			ci.draw_circle(center, r, c4)
			ci.draw_circle(center, r * 0.88, c3)
		"shield":
			_poly(ci, [Vector2(-0.85, -0.9), Vector2(0.85, -0.9), Vector2(0.85, 0.1), Vector2(0.0, 1.0), Vector2(-0.85, 0.1)], center, r, c4)
			_poly(ci, [Vector2(-0.74, -0.8), Vector2(0.74, -0.8), Vector2(0.74, 0.05), Vector2(0.0, 0.87), Vector2(-0.74, 0.05)], center, r, c3)
		"hex":
			_poly(ci, _ring(6, 1.0, PI / 6.0), center, r, c4)
			_poly(ci, _ring(6, 0.87, PI / 6.0), center, r, c3)
		"diamond":
			_poly(ci, [Vector2(0, -1.0), Vector2(1.0, 0), Vector2(0, 1.0), Vector2(-1.0, 0)], center, r, c4)
			_poly(ci, [Vector2(0, -0.86), Vector2(0.86, 0), Vector2(0, 0.86), Vector2(-0.86, 0)], center, r, c3)
		"badge":
			_poly(ci, _star(12, 1.0, 0.86), center, r, c4)
			ci.draw_circle(center, r * 0.78, c3)
		"banner":
			_poly(ci, [Vector2(-0.8, -0.95), Vector2(0.8, -0.95), Vector2(0.8, 0.95), Vector2(0.0, 0.6), Vector2(-0.8, 0.95)], center, r, c4)
			_poly(ci, [Vector2(-0.7, -0.85), Vector2(0.7, -0.85), Vector2(0.7, 0.78), Vector2(0.0, 0.48), Vector2(-0.7, 0.78)], center, r, c3)
		"laurel":
			ci.draw_circle(center, r * 0.8, c3)
			for side: float in [-1.0, 1.0]:  # two branches growing up the sides from the bottom
				for i in 7:
					var a := deg_to_rad(105.0 + float(i) * 22.0)
					var at := Vector2(cos(a) * side, sin(a)) * 0.9
					var grow := a + PI * 0.5
					_poly(ci, _leaf_at(at, grow if side > 0.0 else PI - grow, 0.26), center, r, c4)
		"wings":
			for side: float in [-1.0, 1.0]:
				for i in 4:
					var y := -0.35 + float(i) * 0.18
					_poly(ci, [Vector2(0.55 * side, y), Vector2((1.0 - float(i) * 0.08) * side, y - 0.2), Vector2((0.95 - float(i) * 0.1) * side, y + 0.1), Vector2(0.55 * side, y + 0.16)], center, r, c4)
			ci.draw_circle(center, r * 0.66, c4)
			ci.draw_circle(center, r * 0.58, c3)
		"square":
			ci.draw_rect(Rect2(center - Vector2(r, r) * 0.92, Vector2(r, r) * 1.84), c4)
			ci.draw_rect(Rect2(center - Vector2(r, r) * 0.8, Vector2(r, r) * 1.6), c3)
		"cog":
			_poly(ci, _cog(10, 1.0, 0.82), center, r, c4)
			ci.draw_circle(center, r * 0.72, c3)
		_:
			ci.draw_circle(center, r * 0.9, c3)


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
		"card":  # a playing card with a pip
			_poly(ci, [Vector2(-0.55, -0.85), Vector2(0.55, -0.85), Vector2(0.55, 0.85), Vector2(-0.55, 0.85)], center, r, c1)
			_poly(ci, [Vector2(-0.4, -0.68), Vector2(0.4, -0.68), Vector2(0.4, 0.1), Vector2(-0.4, 0.1)], center, r, c2)
			ci.draw_circle(center + Vector2(0.0, 0.45) * r, r * 0.16, c2)
		"fan":  # a hand of four cards fanned
			for i in 4:
				var ang := -0.6 + float(i) * 0.4
				var pts: Array = []
				for q: Vector2 in [Vector2(-0.3, -0.85), Vector2(0.3, -0.85), Vector2(0.3, 0.35), Vector2(-0.3, 0.35)]:
					pts.append(q.rotated(ang) + Vector2(0.0, 0.45))
				_poly(ci, pts, center, r, c1 if i % 2 == 0 else c1.darkened(0.15))
				ci.draw_circle(center + (Vector2(0.0, -0.5).rotated(ang) + Vector2(0.0, 0.45)) * r, r * 0.08, c2)
		"lobster":  # body, tail, two raised claws
			ci.draw_circle(center + Vector2(0.0, -0.05) * r, r * 0.3, c1)
			for k in 3:
				ci.draw_circle(center + Vector2(0.0, 0.3 + k * 0.2) * r, r * (0.24 - k * 0.04), c1)
			_poly(ci, [Vector2(-0.25, 0.85), Vector2(0.25, 0.85), Vector2(0.0, 0.7)], center, r, c1)
			for sx: float in [-1.0, 1.0]:
				_line(ci, Vector2(0.2 * sx, -0.1), Vector2(0.55 * sx, -0.45), center, r, c1, 0.12)
				ci.draw_circle(center + Vector2(0.62 * sx, -0.62) * r, r * 0.2, c1)
				_line(ci, Vector2(0.62 * sx, -0.62), Vector2(0.5 * sx, -0.92), center, r, c2, 0.06)
			ci.draw_circle(center + Vector2(-0.1, -0.15) * r, r * 0.05, c2)
			ci.draw_circle(center + Vector2(0.1, -0.15) * r, r * 0.05, c2)
		"pack":  # a foil pack with crimped ends
			_poly(ci, [Vector2(-0.55, -0.85), Vector2(0.55, -0.85), Vector2(0.55, 0.85), Vector2(-0.55, 0.85)], center, r, c1)
			_poly(ci, [Vector2(-0.55, -0.85), Vector2(0.55, -0.85), Vector2(0.55, -0.62), Vector2(-0.55, -0.62)], center, r, c2)
			_poly(ci, [Vector2(-0.55, 0.62), Vector2(0.55, 0.62), Vector2(0.55, 0.85), Vector2(-0.55, 0.85)], center, r, c2)
			ci.draw_circle(center, r * 0.22, c2)
		"binder":  # an open binder: two pages of pockets and rings
			for sx: float in [-1.0, 1.0]:
				_poly(ci, [Vector2(0.05 * sx, -0.7), Vector2(0.92 * sx, -0.7), Vector2(0.92 * sx, 0.7), Vector2(0.05 * sx, 0.7)], center, r, c1)
				for i in 4:
					var px := (0.26 + float(i % 2) * 0.38) * sx
					var py := -0.32 + float(floori(i / 2.0)) * 0.62
					_poly(ci, [Vector2(px - 0.14, py - 0.24), Vector2(px + 0.14, py - 0.24), Vector2(px + 0.14, py + 0.24), Vector2(px - 0.14, py + 0.24)], center, r, c2)
			for k in 3:
				ci.draw_circle(center + Vector2(0.0, -0.45 + k * 0.45) * r, r * 0.07, c2)
		"chip":  # a poker chip: rim stripes and a centre
			ci.draw_circle(center, r * 0.9, c1)
			for i in 8:
				var a8 := float(i) * TAU / 8.0
				_line(ci, Vector2.from_angle(a8) * 0.62, Vector2.from_angle(a8) * 0.88, center, r, c2, 0.16)
			ci.draw_circle(center, r * 0.5, c2)
			ci.draw_circle(center, r * 0.38, c1)
		"bunny":
			_poly(ci, [Vector2(-0.45, -0.1), Vector2(-0.3, -0.95), Vector2(-0.1, -0.1)], center, r, c1)
			_poly(ci, [Vector2(0.1, -0.1), Vector2(0.3, -0.95), Vector2(0.45, -0.1)], center, r, c1)
			_poly(ci, [Vector2(-0.35, -0.2), Vector2(-0.28, -0.7), Vector2(-0.17, -0.2)], center, r, c2)
			_poly(ci, [Vector2(0.17, -0.2), Vector2(0.28, -0.7), Vector2(0.35, -0.2)], center, r, c2)
			ci.draw_circle(center + Vector2(0.0, 0.3) * r, r * 0.6, c1)
			ci.draw_circle(center + Vector2(-0.2, 0.25) * r, r * 0.07, c2)
			ci.draw_circle(center + Vector2(0.2, 0.25) * r, r * 0.07, c2)
		"skull":
			ci.draw_circle(center + Vector2(0.0, -0.15) * r, r * 0.68, c1)
			_poly(ci, [Vector2(-0.4, 0.3), Vector2(0.4, 0.3), Vector2(0.32, 0.85), Vector2(-0.32, 0.85)], center, r, c1)
			ci.draw_circle(center + Vector2(-0.27, -0.12) * r, r * 0.18, c2)
			ci.draw_circle(center + Vector2(0.27, -0.12) * r, r * 0.18, c2)
			_poly(ci, [Vector2(0.0, 0.08), Vector2(0.09, 0.28), Vector2(-0.09, 0.28)], center, r, c2)
			for i in 3:
				_line(ci, Vector2(-0.16 + float(i) * 0.16, 0.55), Vector2(-0.16 + float(i) * 0.16, 0.85), center, r, c2, 0.06)
		"swords":
			for side: float in [-1.0, 1.0]:
				_poly(ci, [Vector2(-0.75 * side, -0.85), Vector2(-0.62 * side, -0.9), Vector2(0.6 * side, 0.5), Vector2(0.5 * side, 0.6)], center, r, c1)
				_line(ci, Vector2(0.35 * side, 0.7), Vector2(0.75 * side, 0.3), center, r, c2, 0.1)
				_line(ci, Vector2(0.62 * side, 0.62), Vector2(0.85 * side, 0.85), center, r, c2, 0.12)
		"anchor":
			_line(ci, Vector2(0, -0.6), Vector2(0, 0.8), center, r, c1, 0.14)
			_line(ci, Vector2(-0.4, -0.35), Vector2(0.4, -0.35), center, r, c1, 0.12)
			ci.draw_arc(center + Vector2(0, -0.78) * r, r * 0.17, 0.0, TAU, 16, c1, maxf(r * 0.09, 1.5), true)
			ci.draw_arc(center + Vector2(0, 0.2) * r, r * 0.65, deg_to_rad(20.0), deg_to_rad(160.0), 20, c1, maxf(r * 0.13, 2.0), true)
			_poly(ci, [Vector2(-0.75, 0.25), Vector2(-0.5, 0.35), Vector2(-0.68, 0.5)], center, r, c2)
			_poly(ci, [Vector2(0.75, 0.25), Vector2(0.5, 0.35), Vector2(0.68, 0.5)], center, r, c2)
		"wave":
			for row in 3:
				var pts: Array = []
				for i in 13:
					var x := -0.9 + float(i) * 0.15
					pts.append(Vector2(x, -0.4 + float(row) * 0.4 + sin(float(i) * 1.1) * 0.12))
				for i in range(pts.size() - 1):
					_line(ci, pts[i], pts[i + 1], center, r, c1 if row != 1 else c2, 0.12)
		"palm":
			_line(ci, Vector2(0.05, 0.9), Vector2(0.15, -0.3), center, r, c2, 0.16)
			for a: float in [-150.0, -110.0, -70.0, -30.0, 10.0]:
				var tip := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * 0.75 + Vector2(0.15, -0.3)
				_poly(ci, [Vector2(0.15, -0.3), tip + Vector2(0.0, -0.08), tip + Vector2(0.05, 0.08)], center, r, c1)
		"bell":
			_poly(ci, [Vector2(-0.15, -0.8), Vector2(0.15, -0.8), Vector2(0.45, -0.3), Vector2(0.55, 0.45), Vector2(0.8, 0.6), Vector2(-0.8, 0.6), Vector2(-0.55, 0.45), Vector2(-0.45, -0.3)], center, r, c1)
			ci.draw_circle(center + Vector2(0, 0.75) * r, r * 0.16, c2)
			ci.draw_circle(center + Vector2(0, -0.86) * r, r * 0.1, c2)
		"crow":
			_poly(ci, [Vector2(-0.8, 0.35), Vector2(-0.25, -0.1), Vector2(0.15, -0.35), Vector2(0.45, -0.55), Vector2(0.85, -0.45), Vector2(0.5, -0.35), Vector2(0.45, 0.0), Vector2(0.1, 0.4), Vector2(-0.3, 0.45)], center, r, c1)
			_poly(ci, [Vector2(-0.2, 0.0), Vector2(0.25, -0.15), Vector2(0.05, 0.3)], center, r, c2)
			ci.draw_circle(center + Vector2(0.5, -0.47) * r, r * 0.05, c2)
			_line(ci, Vector2(0.0, 0.42), Vector2(-0.05, 0.8), center, r, c2, 0.05)
			_line(ci, Vector2(0.15, 0.4), Vector2(0.15, 0.8), center, r, c2, 0.05)
		"gear":
			_poly(ci, _cog(8, 0.9, 0.7), center, r, c1)
			ci.draw_circle(center, r * 0.32, c2)
		"knife":
			_poly(ci, [Vector2(-0.12, 0.25), Vector2(-0.1, -0.6), Vector2(0.05, -0.95), Vector2(0.12, -0.55), Vector2(0.12, 0.25)], center, r, c1)
			_poly(ci, [Vector2(-0.3, 0.22), Vector2(0.3, 0.22), Vector2(0.3, 0.32), Vector2(-0.3, 0.32)], center, r, c2)
			_poly(ci, [Vector2(-0.1, 0.32), Vector2(0.1, 0.32), Vector2(0.12, 0.92), Vector2(-0.12, 0.92)], center, r, c2)
		"wheat":
			_line(ci, Vector2(0, 0.95), Vector2(0, -0.6), center, r, c2, 0.07)
			for i in 5:
				var y := -0.75 + float(i) * 0.25
				_poly(ci, _leaf_at(Vector2(-0.14, y), deg_to_rad(-120.0), 0.2), center, r, c1)
				_poly(ci, _leaf_at(Vector2(0.14, y), deg_to_rad(-60.0), 0.2), center, r, c1)
			_poly(ci, _leaf_at(Vector2(0, -0.85), deg_to_rad(-90.0), 0.2), center, r, c1)
		"axe":
			_line(ci, Vector2(-0.5, 0.9), Vector2(0.35, -0.75), center, r, c2, 0.12)
			_poly(ci, [Vector2(0.15, -0.6), Vector2(0.75, -0.75), Vector2(0.85, -0.15), Vector2(0.3, -0.15)], center, r, c1)
		"pickaxe":
			_line(ci, Vector2(-0.55, 0.9), Vector2(0.3, -0.45), center, r, c2, 0.12)
			ci.draw_arc(center + Vector2(0.15, 0.1) * r, r * 0.85, deg_to_rad(-140.0), deg_to_rad(-20.0), 20, c1, maxf(r * 0.14, 2.0), true)
		"anvil":
			_poly(ci, [Vector2(-0.85, -0.35), Vector2(0.55, -0.35), Vector2(0.9, -0.15), Vector2(0.4, -0.05), Vector2(0.3, 0.2), Vector2(-0.3, 0.2), Vector2(-0.45, -0.1), Vector2(-0.85, -0.15)], center, r, c1)
			_poly(ci, [Vector2(-0.45, 0.2), Vector2(0.45, 0.2), Vector2(0.6, 0.6), Vector2(-0.6, 0.6)], center, r, c2)
			_line(ci, Vector2(-0.2, -0.95), Vector2(0.3, -0.55), center, r, c2, 0.1)
		"fish":
			_poly(ci, [Vector2(-0.6, 0.0), Vector2(-0.2, -0.38), Vector2(0.3, -0.38), Vector2(0.6, 0.0), Vector2(0.3, 0.38), Vector2(-0.2, 0.38)], center, r, c1)
			_poly(ci, [Vector2(0.55, 0.0), Vector2(0.95, -0.38), Vector2(0.95, 0.38)], center, r, c1)
			ci.draw_circle(center + Vector2(-0.35, -0.08) * r, r * 0.07, c2)
			_line(ci, Vector2(-0.05, -0.3), Vector2(-0.05, 0.3), center, r, c2, 0.05)
		"flask":
			_poly(ci, [Vector2(-0.15, -0.85), Vector2(0.15, -0.85), Vector2(0.15, -0.3), Vector2(0.7, 0.8), Vector2(-0.7, 0.8), Vector2(-0.15, -0.3)], center, r, c1)
			_poly(ci, [Vector2(-0.43, 0.25), Vector2(0.43, 0.25), Vector2(0.62, 0.72), Vector2(-0.62, 0.72)], center, r, c2)
		"orb":
			_line(ci, Vector2(0.0, -0.3), Vector2(0.0, 0.95), center, r, c2, 0.1)
			ci.draw_circle(center + Vector2(0, -0.5) * r, r * 0.42, c1)
			ci.draw_arc(center + Vector2(0, -0.5) * r, r * 0.55, 0.0, TAU, 24, c2, maxf(r * 0.06, 1.5), true)
			ci.draw_circle(center + Vector2(-0.12, -0.62) * r, r * 0.1, Color(1, 1, 1, 0.7))
		"moon":
			ci.draw_circle(center, r * 0.8, c1)
			ci.draw_circle(center + Vector2(0.35, -0.2) * r, r * 0.7, c2)
		"sun":
			for i in 12:
				var a := float(i) * TAU / 12.0
				_line(ci, Vector2(cos(a), sin(a)) * 0.55, Vector2(cos(a), sin(a)) * 0.95, center, r, c2, 0.1)
			ci.draw_circle(center, r * 0.5, c1)
		"mountain":
			_poly(ci, [Vector2(-0.95, 0.7), Vector2(-0.3, -0.5), Vector2(0.05, 0.05), Vector2(0.35, -0.75), Vector2(0.95, 0.7)], center, r, c1)
			_poly(ci, [Vector2(0.35, -0.75), Vector2(0.52, -0.42), Vector2(0.35, -0.48), Vector2(0.2, -0.4)], center, r, c2)
		"tower":
			_poly(ci, [Vector2(-0.35, -0.55), Vector2(0.35, -0.55), Vector2(0.45, 0.9), Vector2(-0.45, 0.9)], center, r, c1)
			for i in 3:
				ci.draw_rect(Rect2(center + Vector2(-0.45 + float(i) * 0.33, -0.85) * r, Vector2(0.24, 0.32) * r), c1)
			ci.draw_rect(Rect2(center + Vector2(-0.1, -0.2) * r, Vector2(0.2, 0.3) * r), c2)
			ci.draw_rect(Rect2(center + Vector2(-0.15, 0.5) * r, Vector2(0.3, 0.4) * r), c2)
		"key":
			ci.draw_arc(center + Vector2(-0.45, -0.4) * r, r * 0.3, 0.0, TAU, 20, c1, maxf(r * 0.13, 2.0), true)
			_line(ci, Vector2(-0.25, -0.2), Vector2(0.7, 0.75), center, r, c1, 0.12)
			_line(ci, Vector2(0.45, 0.5), Vector2(0.65, 0.3), center, r, c2, 0.1)
			_line(ci, Vector2(0.6, 0.65), Vector2(0.8, 0.45), center, r, c2, 0.1)
		"eye":
			_poly(ci, [Vector2(-0.95, 0.0), Vector2(-0.4, -0.45), Vector2(0.4, -0.45), Vector2(0.95, 0.0), Vector2(0.4, 0.45), Vector2(-0.4, 0.45)], center, r, c1)
			ci.draw_circle(center, r * 0.33, c2)
			ci.draw_circle(center, r * 0.14, c1.darkened(0.8))
		"feather":
			_poly(ci, [Vector2(0.55, -0.9), Vector2(0.7, -0.5), Vector2(0.2, 0.35), Vector2(-0.3, 0.6), Vector2(-0.1, 0.1)], center, r, c1)
			_line(ci, Vector2(0.6, -0.8), Vector2(-0.7, 0.9), center, r, c2, 0.06)
		"hourglass":
			_poly(ci, [Vector2(-0.6, -0.85), Vector2(0.6, -0.85), Vector2(0.08, 0.0), Vector2(0.6, 0.85), Vector2(-0.6, 0.85), Vector2(-0.08, 0.0)], center, r, c1)
			_poly(ci, [Vector2(-0.35, 0.55), Vector2(0.35, 0.55), Vector2(0.48, 0.75), Vector2(-0.48, 0.75)], center, r, c2)
			_poly(ci, [Vector2(-0.3, -0.6), Vector2(0.3, -0.6), Vector2(0.0, -0.25)], center, r, c2)
		"compass":
			ci.draw_arc(center, r * 0.85, 0.0, TAU, 32, c2, maxf(r * 0.08, 1.5), true)
			_poly(ci, [Vector2(0, -0.8), Vector2(0.18, 0), Vector2(0, 0.8), Vector2(-0.18, 0)], center, r, c1)
			_poly(ci, [Vector2(-0.8, 0), Vector2(0, -0.12), Vector2(0.8, 0), Vector2(0, 0.12)], center, r, c2)
		"trident":
			_line(ci, Vector2(0, -0.45), Vector2(0, 0.95), center, r, c2, 0.1)
			_line(ci, Vector2(-0.5, -0.45), Vector2(0.5, -0.45), center, r, c1, 0.1)
			for x: float in [-0.5, 0.0, 0.5]:
				_poly(ci, [Vector2(x - 0.08, -0.45), Vector2(x, -0.95), Vector2(x + 0.08, -0.45)], center, r, c1)
		"horseshoe":
			ci.draw_arc(center + Vector2(0, -0.05) * r, r * 0.62, deg_to_rad(-200.0), deg_to_rad(20.0), 28, c1, maxf(r * 0.24, 3.0), true)
			for a: float in [-170.0, -120.0, -60.0, -10.0]:
				ci.draw_circle(center + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * r * 0.62 + Vector2(0, -0.05) * r, r * 0.05, c2)
		"dice":
			ci.draw_rect(Rect2(center - Vector2(0.7, 0.7) * r, Vector2(1.4, 1.4) * r), c1)
			for spot: Vector2 in [Vector2(-0.35, -0.35), Vector2(0.35, 0.35), Vector2(0, 0), Vector2(0.35, -0.35), Vector2(-0.35, 0.35)]:
				ci.draw_circle(center + spot * r, r * 0.12, c2)
		"spade":
			ci.draw_circle(center + Vector2(-0.33, 0.15) * r, r * 0.38, c1)
			ci.draw_circle(center + Vector2(0.33, 0.15) * r, r * 0.38, c1)
			_poly(ci, [Vector2(0.0, -0.9), Vector2(0.7, 0.05), Vector2(-0.7, 0.05)], center, r, c1)
			_poly(ci, [Vector2(0.0, 0.2), Vector2(0.25, 0.9), Vector2(-0.25, 0.9)], center, r, c2)
		"ship":
			_poly(ci, [Vector2(-0.9, 0.35), Vector2(0.9, 0.35), Vector2(0.6, 0.75), Vector2(-0.6, 0.75)], center, r, c2)
			_line(ci, Vector2(0.0, 0.35), Vector2(0.0, -0.9), center, r, c2, 0.07)
			_poly(ci, [Vector2(0.05, -0.85), Vector2(0.7, 0.2), Vector2(0.05, 0.2)], center, r, c1)
			_poly(ci, [Vector2(-0.05, -0.6), Vector2(-0.05, 0.2), Vector2(-0.55, 0.2)], center, r, c1)
		"bullet":
			_poly(ci, [Vector2(-0.22, -0.3), Vector2(-0.12, -0.75), Vector2(0.0, -0.92), Vector2(0.12, -0.75), Vector2(0.22, -0.3)], center, r, c1)
			ci.draw_rect(Rect2(center + Vector2(-0.24, -0.3) * r, Vector2(0.48, 1.15) * r), c2)
			ci.draw_rect(Rect2(center + Vector2(-0.28, 0.75) * r, Vector2(0.56, 0.12) * r), c2.darkened(0.3))
		"crosshair":
			ci.draw_arc(center, r * 0.7, 0.0, TAU, 32, c1, maxf(r * 0.1, 2.0), true)
			for d: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				_line(ci, d * 0.35, d * 0.95, center, r, c1, 0.09)
			ci.draw_circle(center, r * 0.1, c2)
		"snowflake":
			for i in 6:
				var a := float(i) * TAU / 6.0
				var tip := Vector2(cos(a), sin(a)) * 0.9
				_line(ci, Vector2.ZERO, tip, center, r, c1, 0.09)
				_line(ci, tip * 0.6, tip * 0.6 + Vector2(cos(a + 0.8), sin(a + 0.8)) * 0.25, center, r, c2, 0.06)
				_line(ci, tip * 0.6, tip * 0.6 + Vector2(cos(a - 0.8), sin(a - 0.8)) * 0.25, center, r, c2, 0.06)
		"leaf":
			_poly(ci, _leaf_at(Vector2(0, 0.85), deg_to_rad(-90.0), 1.6), center, r, c1)
			_line(ci, Vector2(0, 0.9), Vector2(0, -0.6), center, r, c2, 0.06)
		"flower":
			for i in 6:
				var a := float(i) * TAU / 6.0
				ci.draw_circle(center + Vector2(cos(a), sin(a)) * r * 0.45, r * 0.32, c1)
			ci.draw_circle(center, r * 0.3, c2)
		"paw":
			ci.draw_circle(center + Vector2(0, 0.3) * r, r * 0.42, c1)
			for spot: Vector2 in [Vector2(-0.55, -0.2), Vector2(-0.2, -0.55), Vector2(0.2, -0.55), Vector2(0.55, -0.2)]:
				ci.draw_circle(center + spot * r, r * 0.18, c1)
			ci.draw_circle(center + Vector2(0, 0.3) * r, r * 0.15, c2)
		"fist":
			ci.draw_rect(Rect2(center + Vector2(-0.55, -0.45) * r, Vector2(1.0, 0.95) * r), c1)
			for i in 4:
				_line(ci, Vector2(-0.55 + float(i) * 0.25, -0.45), Vector2(-0.55 + float(i) * 0.25, -0.1), center, r, c2, 0.05)
			_poly(ci, [Vector2(-0.55, 0.05), Vector2(-0.85, -0.2), Vector2(-0.8, 0.35), Vector2(-0.55, 0.45)], center, r, c1)
			ci.draw_rect(Rect2(center + Vector2(-0.4, 0.5) * r, Vector2(0.7, 0.45) * r), c2)
		"tentacle":
			var prev := Vector2(-0.5, 0.95)
			for i in range(1, 14):
				var t := float(i) / 13.0
				var at := Vector2(-0.5 + t * 0.9 + sin(t * 6.0) * 0.25, 0.95 - t * 1.8)
				_line(ci, prev, at, center, r, c1, 0.28 * (1.0 - t * 0.8))
				if i % 3 == 0:
					ci.draw_circle(center + at * r + Vector2(-0.08, 0.0) * r, r * 0.05, c2)
				prev = at
		"lantern":
			_line(ci, Vector2(-0.15, -0.85), Vector2(0.15, -0.85), center, r, c2, 0.08)
			ci.draw_arc(center + Vector2(0, -0.8) * r, r * 0.15, PI, TAU, 10, c2, maxf(r * 0.06, 1.5), true)
			_poly(ci, [Vector2(-0.4, -0.6), Vector2(0.4, -0.6), Vector2(0.48, 0.7), Vector2(-0.48, 0.7)], center, r, c2)
			_poly(ci, [Vector2(-0.28, -0.45), Vector2(0.28, -0.45), Vector2(0.34, 0.55), Vector2(-0.34, 0.55)], center, r, c1)
			_poly(ci, [Vector2(0.0, -0.15), Vector2(0.14, 0.2), Vector2(0.0, 0.42), Vector2(-0.14, 0.2)], center, r, Color(1, 1, 1, 0.8))
		"note":
			ci.draw_circle(center + Vector2(-0.35, 0.55) * r, r * 0.28, c1)
			ci.draw_circle(center + Vector2(0.45, 0.4) * r, r * 0.28, c1)
			_line(ci, Vector2(-0.1, 0.55), Vector2(-0.1, -0.7), center, r, c1, 0.1)
			_line(ci, Vector2(0.7, 0.4), Vector2(0.7, -0.85), center, r, c1, 0.1)
			_poly(ci, [Vector2(-0.15, -0.7), Vector2(0.75, -0.9), Vector2(0.75, -0.6), Vector2(-0.15, -0.4)], center, r, c2)
		"boot":
			_poly(ci, [Vector2(-0.45, -0.85), Vector2(0.2, -0.85), Vector2(0.18, 0.1), Vector2(0.55, 0.22), Vector2(0.82, 0.4), Vector2(0.88, 0.68), Vector2(-0.5, 0.68), Vector2(-0.5, 0.3)], center, r, c1)
			_poly(ci, [Vector2(-0.52, -0.92), Vector2(0.24, -0.92), Vector2(0.24, -0.7), Vector2(-0.52, -0.7)], center, r, c2)
			_poly(ci, [Vector2(-0.55, 0.62), Vector2(0.92, 0.62), Vector2(0.85, 0.82), Vector2(-0.55, 0.82)], center, r, c2)
			for i in 4:
				_line(ci, Vector2(0.0, -0.55 + float(i) * 0.2), Vector2(0.24, -0.6 + float(i) * 0.2), center, r, c2, 0.06)
		"bear":
			ci.draw_circle(center + Vector2(-0.55, -0.55) * r, r * 0.25, c1)
			ci.draw_circle(center + Vector2(0.55, -0.55) * r, r * 0.25, c1)
			ci.draw_circle(center + Vector2(0, 0.05) * r, r * 0.7, c1)
			ci.draw_circle(center + Vector2(0, 0.3) * r, r * 0.3, c2)
			ci.draw_circle(center + Vector2(-0.27, -0.1) * r, r * 0.09, c2)
			ci.draw_circle(center + Vector2(0.27, -0.1) * r, r * 0.09, c2)
			ci.draw_circle(center + Vector2(0, 0.2) * r, r * 0.09, c1.darkened(0.6))
		_:
			ci.draw_circle(center, r * 0.8, c1)


static func _poly(ci: CanvasItem, unit: Array, center: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for p: Vector2 in unit:
		pts.append(center + p * r)
	ci.draw_colored_polygon(pts, color)


# A thick straight stroke between two unit-circle points.
static func _line(ci: CanvasItem, a: Vector2, b: Vector2, center: Vector2, r: float, color: Color, width: float) -> void:
	ci.draw_line(center + a * r, center + b * r, color, maxf(width * r, 1.5), true)


# n points on a circle of radius `rad`, the first at angle `turn`.
static func _ring(n: int, rad: float, turn: float) -> Array:
	var out: Array = []
	for i in n:
		var a := turn + float(i) * TAU / float(n)
		out.append(Vector2(cos(a), sin(a)) * rad)
	return out


# A star with n points between radius `outer` and `inner`.
static func _star(n: int, outer: float, inner: float) -> Array:
	var out: Array = []
	for i in n * 2:
		var a := -PI * 0.5 + float(i) * PI / float(n)
		out.append(Vector2(cos(a), sin(a)) * (outer if i % 2 == 0 else inner))
	return out


# A cog wheel outline: n square teeth between radius `outer` and `inner`.
static func _cog(n: int, outer: float, inner: float) -> Array:
	var out: Array = []
	for i in n:
		var a := float(i) * TAU / float(n)
		var step := TAU / float(n)
		for k: Array in [[0.0, inner], [0.15, outer], [0.5, outer], [0.65, inner]]:
			var at := a + step * float(k[0])
			out.append(Vector2(cos(at), sin(at)) * float(k[1]))
	return out


# A pointed leaf from `base` along angle `a`, `length` long.
static func _leaf_at(base: Vector2, a: float, length: float) -> Array:
	var along := Vector2(cos(a), sin(a))
	var side := along.orthogonal() * length * 0.28
	return [base, base + along * length * 0.5 + side, base + along * length, base + along * length * 0.5 - side]
