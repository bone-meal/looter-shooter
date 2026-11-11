# Purpose: draws the 8 slot symbols (cherry, lemon, plum, bell, bar, seven, wild, jackpot) into one small atlas texture at startup, no image files needed. Also answers where each symbol sits in the atlas.
# Dependencies: none.
extends RefCounted

const CELL_W := 160
const CELL_H := 96
const COLS := 4
const IDS: Array[String] = ["cherry", "lemon", "plum", "bell", "bar", "seven", "wild", "jackpot"]

static var _tex: ImageTexture
static var _suit_tex: ImageTexture


# The shared atlas (built once).
static func atlas() -> ImageTexture:
	if _tex == null:
		var img := Image.create(CELL_W * COLS, CELL_H * 2, false, Image.FORMAT_RGBA8)
		for i in IDS.size():
			_draw_symbol(img, IDS[i], Vector2i((i % COLS) * CELL_W, floori(float(i) / float(COLS)) * CELL_H))
		img.generate_mipmaps()
		_tex = ImageTexture.create_from_image(img)
	return _tex


# Four card-suit icons side by side, one per 160x96 cell: 0 spades, 1 hearts, 2 diamonds, 3 clubs (white background).
static func suit_atlas() -> ImageTexture:
	if _suit_tex == null:
		var img := Image.create(CELL_W * 4, CELL_H, false, Image.FORMAT_RGBA8)
		var black := Color(0.08, 0.08, 0.1)
		var red := Color(0.85, 0.08, 0.12)
		for i in 4:
			var o := Vector2i(i * CELL_W, 0)
			_rect(img, o, 0, 0, CELL_W, CELL_H, Color(1, 1, 1))
			match i:
				0:
					_ellipse(img, o, 66, 46, 22, 20, black)
					_ellipse(img, o, 94, 46, 22, 20, black)
					_poly(img, o, PackedVector2Array([Vector2(80, 8), Vector2(116, 44), Vector2(44, 44)]), black)
					_poly(img, o, PackedVector2Array([Vector2(80, 50), Vector2(94, 86), Vector2(66, 86)]), black)
				1:
					_ellipse(img, o, 64, 34, 22, 20, red)
					_ellipse(img, o, 96, 34, 22, 20, red)
					_poly(img, o, PackedVector2Array([Vector2(44, 44), Vector2(116, 44), Vector2(80, 88)]), red)
				2:
					_poly(img, o, PackedVector2Array([Vector2(80, 6), Vector2(118, 48), Vector2(80, 90), Vector2(42, 48)]), red)
				3:
					_ellipse(img, o, 80, 26, 20, 19, black)
					_ellipse(img, o, 58, 54, 20, 19, black)
					_ellipse(img, o, 102, 54, 20, 19, black)
					_poly(img, o, PackedVector2Array([Vector2(80, 40), Vector2(94, 88), Vector2(66, 88)]), black)
		img.generate_mipmaps()
		_suit_tex = ImageTexture.create_from_image(img)
	return _suit_tex


# Atlas rectangle in 0..1 UV space.
static func uv_rect(id: String) -> Rect2:
	var i := IDS.find(id)
	var w := float(CELL_W * COLS)
	var h := float(CELL_H * 2)
	return Rect2(float((i % COLS) * CELL_W) / w, float(floori(float(i) / float(COLS)) * CELL_H) / h, float(CELL_W) / w, float(CELL_H) / h)


# Pixel rectangle in the atlas (for drawing in UI).
static func pixel_rect(id: String) -> Rect2:
	var i := IDS.find(id)
	return Rect2(float((i % COLS) * CELL_W), float(floori(float(i) / float(COLS)) * CELL_H), float(CELL_W), float(CELL_H))


static func _rect(img: Image, o: Vector2i, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(o.x + x, o.y + y, w, h), c)


static func _ellipse(img: Image, o: Vector2i, cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	for y in range(floori(cy - ry), ceili(cy + ry) + 1):
		for x in range(floori(cx - rx), ceili(cx + rx) + 1):
			var dx := (float(x) + 0.5 - cx) / rx
			var dy := (float(y) + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0 and x >= 0 and y >= 0 and x < CELL_W and y < CELL_H:
				img.set_pixel(o.x + x, o.y + y, c)


# Even-odd scanline polygon fill; points in cell pixels.
static func _poly(img: Image, o: Vector2i, pts: PackedVector2Array, c: Color) -> void:
	var n := pts.size()
	for y in CELL_H:
		var fy := float(y) + 0.5
		var xs: Array[float] = []
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			if (a.y <= fy and b.y > fy) or (b.y <= fy and a.y > fy):
				xs.append(a.x + (fy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			for x in range(maxi(floori(xs[k]), 0), mini(ceili(xs[k + 1]), CELL_W)):
				img.set_pixel(o.x + x, o.y + y, c)
			k += 2


static func _line(img: Image, o: Vector2i, a: Vector2, b: Vector2, width: float, c: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	for s in steps + 1:
		var p := a.lerp(b, float(s) / float(steps))
		_ellipse(img, o, p.x, p.y, width * 0.5, width * 0.5, c)


static func _draw_symbol(img: Image, id: String, o: Vector2i) -> void:
	var bg := Color(0.98, 0.95, 0.86)
	if id == "wild":
		bg = Color(0.25, 0.08, 0.35)
	elif id == "jackpot":
		bg = Color(0.04, 0.08, 0.25)
	_rect(img, o, 0, 0, CELL_W, CELL_H, bg)
	_rect(img, o, 0, 0, CELL_W, 3, Color(0.6, 0.5, 0.3))
	_rect(img, o, 0, CELL_H - 3, CELL_W, 3, Color(0.6, 0.5, 0.3))
	match id:
		"cherry":
			var red := Color(0.85, 0.08, 0.12)
			_line(img, o, Vector2(62, 62), Vector2(84, 16), 4.0, Color(0.2, 0.5, 0.15))
			_line(img, o, Vector2(100, 64), Vector2(84, 16), 4.0, Color(0.2, 0.5, 0.15))
			_poly(img, o, PackedVector2Array([Vector2(84, 16), Vector2(112, 10), Vector2(104, 28)]), Color(0.25, 0.65, 0.2))
			_ellipse(img, o, 62, 64, 19, 19, red)
			_ellipse(img, o, 100, 66, 19, 19, red)
			_ellipse(img, o, 55, 57, 6, 5, Color(1, 0.7, 0.7))
			_ellipse(img, o, 93, 59, 6, 5, Color(1, 0.7, 0.7))
		"lemon":
			_poly(img, o, PackedVector2Array([Vector2(18, 48), Vector2(34, 40), Vector2(34, 56)]), Color(0.95, 0.8, 0.1))
			_poly(img, o, PackedVector2Array([Vector2(142, 48), Vector2(126, 40), Vector2(126, 56)]), Color(0.95, 0.8, 0.1))
			_ellipse(img, o, 80, 48, 48, 28, Color(0.98, 0.85, 0.12))
			_ellipse(img, o, 66, 38, 14, 7, Color(1.0, 0.97, 0.6))
			_poly(img, o, PackedVector2Array([Vector2(74, 20), Vector2(96, 10), Vector2(92, 22)]), Color(0.25, 0.6, 0.2))
		"plum":
			_ellipse(img, o, 80, 54, 34, 32, Color(0.45, 0.12, 0.6))
			_ellipse(img, o, 68, 42, 10, 8, Color(0.75, 0.5, 0.9))
			_line(img, o, Vector2(80, 24), Vector2(84, 10), 4.0, Color(0.3, 0.5, 0.15))
			_poly(img, o, PackedVector2Array([Vector2(84, 14), Vector2(110, 10), Vector2(100, 26)]), Color(0.25, 0.65, 0.2))
		"bell":
			var gold := Color(0.95, 0.72, 0.1)
			_ellipse(img, o, 80, 40, 30, 28, gold)
			_poly(img, o, PackedVector2Array([Vector2(50, 40), Vector2(110, 40), Vector2(126, 72), Vector2(34, 72)]), gold)
			_rect(img, o, 32, 70, 96, 6, Color(0.75, 0.52, 0.05))
			_ellipse(img, o, 80, 80, 9, 9, Color(0.75, 0.52, 0.05))
			_ellipse(img, o, 66, 36, 8, 12, Color(1.0, 0.92, 0.55))
		"bar":
			_rect(img, o, 20, 20, 120, 56, Color(0.05, 0.05, 0.07))
			_rect(img, o, 26, 26, 108, 44, Color(0.9, 0.7, 0.1))
			for i in 3:
				_rect(img, o, 34 + i * 34, 32, 24, 32, Color(0.05, 0.05, 0.07))
				_rect(img, o, 40 + i * 34, 38, 12, 20, Color(0.9, 0.7, 0.1))
		"seven":
			var red7 := Color(0.9, 0.08, 0.1)
			_poly(img, o, PackedVector2Array([Vector2(40, 14), Vector2(122, 14), Vector2(122, 28), Vector2(92, 84), Vector2(72, 84), Vector2(98, 30), Vector2(40, 30)]), Color(0.45, 0.02, 0.05))
			_poly(img, o, PackedVector2Array([Vector2(44, 16), Vector2(118, 16), Vector2(118, 26), Vector2(88, 80), Vector2(76, 80), Vector2(104, 28), Vector2(44, 28)]), red7)
		"wild":
			var pts := PackedVector2Array()
			for i in 10:
				var r := 40.0 if i % 2 == 0 else 17.0
				var a := -PI * 0.5 + float(i) * PI / 5.0
				pts.append(Vector2(80.0 + cos(a) * r * 1.2, 50.0 + sin(a) * r))
			_poly(img, o, pts, Color(1.0, 0.8, 0.2))
			_ellipse(img, o, 80, 52, 10, 9, Color(1.0, 0.45, 0.7))
		"jackpot":
			var cyan := Color(0.2, 0.9, 1.0)
			_poly(img, o, PackedVector2Array([Vector2(80, 8), Vector2(124, 36), Vector2(80, 90), Vector2(36, 36)]), Color(0.1, 0.55, 0.85))
			_poly(img, o, PackedVector2Array([Vector2(80, 8), Vector2(100, 36), Vector2(80, 90), Vector2(60, 36)]), cyan)
			_poly(img, o, PackedVector2Array([Vector2(80, 8), Vector2(60, 36), Vector2(36, 36)]), Color(0.7, 1.0, 1.0))
			_rect(img, o, 36, 35, 88, 2, Color(0.05, 0.3, 0.5))
