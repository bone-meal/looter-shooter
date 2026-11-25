# Purpose: paints the fantasy map's chart (polish1 F1a: a cartographer's sheet, not a flat colour picture): the land's
# colours on parchment, lit from the north-west, HEIGHT LINES every 10 m (every 50 m in darker ink), the shore inked
# with ripple lines out to sea, little TREES where the land is forest, HACHURES (mountain strokes) on the high steep
# ground, rivers and lakes in blue. Pure reading of the terrain rules: safe on a worker thread.
# Dependencies: core/fantasy_terrain.gd (height, water_at, color, weights, regions).
extends RefCounted

const PAPER := Color(0.87, 0.8, 0.64)
const INKED := Color(0.2, 0.15, 0.1)
const SEA := Color(0.56, 0.66, 0.68)
const RIVER := Color(0.3, 0.45, 0.62)
const FOREST := Color(0.2, 0.3, 0.16)
const LINE_M := 10.0  # metres between height lines
const BOLD_EVERY := 5  # every 5th line is darker
const WOODED := ["greenwald", "brinemouth"]  # looks whose land is drawn with trees


static func paint(terrain: RefCounted, pixels: int) -> Image:
	var half := float(terrain.size) * 0.5
	var step := float(terrain.size) / float(pixels)
	var heights := PackedFloat32Array()
	heights.resize(pixels * pixels)
	var wet := PackedByteArray()
	wet.resize(pixels * pixels)
	for py in pixels:
		var z := -half + (float(py) + 0.5) * step
		for px in pixels:
			var x := -half + (float(px) + 0.5) * step
			var k := py * pixels + px
			heights[k] = float(terrain.height(x, z))
			var water := String(terrain.water_at(x, z))
			wet[k] = 0 if water == "" else (2 if water == "salt" else (3 if water == "lava" else 1))
	var image := Image.create(pixels, pixels, false, Image.FORMAT_RGB8)
	var sea := float(terrain.sea)
	heights = _soften(_soften(heights, pixels), pixels)  # a cartographer draws the shape of the land, not every stone
	for py in pixels:
		var z := -half + (float(py) + 0.5) * step
		for px in pixels:
			var x := -half + (float(px) + 0.5) * step
			var k := py * pixels + px
			var h := heights[k]
			var left := heights[k - 1] if px > 0 else h
			var up := heights[k - pixels] if py > 0 else h
			var color: Color
			if wet[k] == 2 or (wet[k] == 0 and h < sea):
				color = SEA.darkened(clampf((sea - h) * 0.025, 0.0, 0.3))
				var ripple := fmod(maxf(sea - h, 0.0), 3.0)  # lines following the shore out to sea
				if sea - h < 9.0 and ripple < 0.35:
					color = color.lerp(INKED, 0.22)
			elif wet[k] == 3:
				color = Color(0.8, 0.4, 0.2)
			elif wet[k] == 1:
				color = RIVER.lerp(SEA, 0.35)
			else:
				var land: Color = terrain.color(x, z, h, clampf(Vector2(h - left, h - up).length() / step * 0.7, 0.0, 1.0))
				var light := clampf(((h - left) + (h - up)) / step * 0.45, -0.3, 0.22)  # lit from the north-west
				color = PAPER.lerp(land, 0.55) * (0.95 + light)
				var line_here := floorf(h / LINE_M)
				var crossed := line_here != floorf(left / LINE_M) or line_here != floorf(up / LINE_M)
				if crossed:
					color = color.lerp(INKED, 0.42 if int(line_here) % BOLD_EVERY == 0 else 0.2)
				if h - sea < 0.8:
					color = color.lerp(INKED, 0.5)  # the shoreline is inked
			color.a = 1.0
			image.set_pixel(px, py, color)
	_symbols(terrain, image, heights, wet, pixels, step, half)
	return image


# Trees over forest, hachures over high steep ground: small ink marks on a loose grid, the same every time.
static func _symbols(terrain: RefCounted, image: Image, heights: PackedFloat32Array, wet: PackedByteArray, pixels: int, step: float, half: float) -> void:
	var gap := 7
	for gy in range(gap, pixels - gap, gap):
		for gx in range(gap, pixels - gap, gap):
			var jx := gx + (hash(Vector2i(gx, gy)) % 5) - 2
			var jy := gy + (hash(Vector2i(gy, gx)) % 5) - 2
			var k := jy * pixels + jx
			if wet[k] != 0 or heights[k] < float(terrain.sea) + 1.0:
				continue
			var x := -half + (float(jx) + 0.5) * step
			var z := -half + (float(jy) + 0.5) * step
			var dx := heights[k + 1] - heights[k - 1]
			var dz := heights[k + pixels] - heights[k - pixels]
			var steep := Vector2(dx, dz).length() / (2.0 * step)
			if heights[k] > 45.0 and steep > 0.22:  # a hachure: two strokes running down the slope
				var down := -Vector2(dx, dz).normalized()
				for side: float in [-1.5, 1.5]:
					var across := Vector2(-down.y, down.x) * side
					for s in 5:
						var p := Vector2(jx, jy) + across + down * float(s)
						_dot(image, p, INKED, 0.55)
				continue
			var w: PackedFloat32Array = terrain.weights(x, z)
			var wood := 0.0
			for i in w.size():
				if WOODED.has(String(terrain.regions[i]["id"])):
					wood += w[i]
			if wood > 0.5 and steep < 0.3:  # a little tree: a crown on a stem
				for r: Vector2i in [Vector2i(0, -2), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
					_dot(image, Vector2(jx + r.x, jy + r.y), FOREST, 0.7)


# Each height the mean of its 3 x 3 neighbours (edges keep their own).
static func _soften(src: PackedFloat32Array, pixels: int) -> PackedFloat32Array:
	var out := src.duplicate()
	for py in range(1, pixels - 1):
		for px in range(1, pixels - 1):
			var k := py * pixels + px
			out[k] = (src[k - pixels - 1] + src[k - pixels] + src[k - pixels + 1] + src[k - 1] + src[k] + src[k + 1] + src[k + pixels - 1] + src[k + pixels] + src[k + pixels + 1]) / 9.0
	return out


static func _dot(image: Image, p: Vector2, ink: Color, amount: float) -> void:
	var x := int(roundf(p.x))
	var y := int(roundf(p.y))
	if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
		return
	image.set_pixel(x, y, image.get_pixel(x, y).lerp(ink, amount))
