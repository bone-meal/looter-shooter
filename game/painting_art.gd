# Purpose: draws the colosseum painting (256x180) once at startup as a texture; no image files needed.
# Dependencies: none.
extends RefCounted

const W := 256
const H := 180
const HORIZON := 140


static func texture() -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			img.set_pixel(x, y, _pixel(x, y))
	return ImageTexture.create_from_image(img)


static func _pixel(x: int, y: int) -> Color:
	if y >= HORIZON:
		return Color(0.85, 0.72, 0.45).darkened(float(y - HORIZON) / 120.0)
	var sun := Vector2(x - 205, y - 38).length()
	if sun < 14.0:
		return Color(1.0, 0.95, 0.6)
	if x >= 40 and x < 216 and y >= 62:
		var ruined: bool = y < 62 + (x - 150) * 0.9 and x > 150  # broken corner on the right
		if not ruined:
			return _wall(x, y)
	return Color(0.35, 0.55, 0.85).lerp(Color(0.98, 0.78, 0.55), float(y) / HORIZON)


static func _wall(x: int, y: int) -> Color:
	var tier: int = floori((y - 62) / 26.0)  # three tiers of arches
	var local_y := (y - 62) % 26
	var local_x := (x - 40) % 22
	var in_arch: bool = local_x >= 6 and local_x < 16 and local_y >= 8 and local_y < 24 and tier < 3
	if in_arch:
		var top: bool = local_y < 13
		if not top or absf(local_x - 10.5) < 3.0 + (local_y - 8) * 0.8:
			return Color(0.18, 0.13, 0.1)
	var shade := 0.82 - 0.1 * tier
	if local_y == 0:
		return Color(0.5, 0.42, 0.32)
	return Color(0.78 * shade, 0.68 * shade, 0.52 * shade)


# Painting that leads back home: a palm island in a blue sea.
static func island_texture() -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			var c := Color(0.45, 0.7, 0.95).lerp(Color(0.8, 0.9, 1.0), float(y) / 120.0)
			if y >= 120:
				c = Color(0.15, 0.45, 0.75).lerp(Color(0.1, 0.3, 0.6), float(y - 120) / 60.0)
			if y >= 105 and absf(float(x) - 128.0) < 60.0 - float(y - 105) * 0.5 and y < 125:
				c = Color(0.9, 0.82, 0.5)
			if absf(float(x) - 128.0 - float(y - 105) * 0.15) < 2.5 and y > 55 and y < 108:
				c = Color(0.45, 0.3, 0.15)
			if y < 70 and y > 45 and Vector2(float(x) - 130.0, float(y) - 55.0).length() < 26.0 and (x + y) % 5 > 0 and y < 62 + (x - 130) % 3:
				c = Color(0.15, 0.55, 0.2)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# Painting that leads to the fantasy world: a golden wheat field beside a large half-timbered farmhouse.
static func wheat_texture() -> ImageTexture:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			img.set_pixel(x, y, _wheat_pixel(x, y))
	return ImageTexture.create_from_image(img)


static func _wheat_pixel(x: int, y: int) -> Color:
	var fx := float(x)
	var fy := float(y)
	# the farmhouse: stone foot, plaster walls with dark beams, a tall roof and a chimney
	if x >= 34 and x <= 128 and y >= 62 and y <= 124:
		var roof_edge := 62.0 + absf(fx - 81.0) * 0.62  # the roof's slope
		if fy < roof_edge:
			if x >= 104 and x <= 112 and y >= 54:
				return Color(0.5, 0.42, 0.38)
		elif fy < 92.0:
			return Color(0.62, 0.3, 0.18).lerp(Color(0.45, 0.2, 0.13), fposmod(fy, 5.0) / 5.0)  # roof tiles in rows
		elif fy > 116.0:
			return Color(0.55, 0.52, 0.48) if (floori(x / 6.0) + floori(y / 4.0)) % 2 == 0 else Color(0.48, 0.45, 0.42)  # stone foot
		else:
			var beam: bool = x % 16 < 2 or y == 92 or y == 104 or absi((x % 16) - (y - 92)) < 1
			if x >= 76 and x <= 86 and y >= 102:
				return Color(0.3, 0.19, 0.1)  # door
			if (x % 32 >= 20 and x % 32 <= 27) and y >= 95 and y <= 102:
				return Color(1.0, 0.86, 0.45)  # lit windows
			return Color(0.25, 0.17, 0.1) if beam else Color(0.93, 0.88, 0.76)
	if x >= 104 and x <= 112 and y >= 50 and y < 70:
		return Color(0.5, 0.42, 0.38)  # chimney above the roof
	# a windmill far off on the right
	if x >= 196 and x <= 204 and y >= 78 and y <= 110:
		return Color(0.8, 0.75, 0.66)
	if absf(absf(fx - 200.0) - absf(fy - 78.0)) < 1.2 and Vector2(fx - 200.0, fy - 78.0).length() < 17.0:
		return Color(0.4, 0.3, 0.2)
	if y >= 108:
		# the wheat: rows of gold with darker stalks, brighter towards the viewer
		var row := sin(fx * 0.9 + fy * 0.35) * 0.5 + 0.5
		var gold := Color(0.78, 0.6, 0.16).lerp(Color(1.0, 0.86, 0.36), row)
		return gold.lerp(Color(0.95, 0.8, 0.3), (fy - 108.0) / 90.0)
	var hill := 100.0 + sin(fx * 0.035) * 6.0 + sin(fx * 0.011 + 2.0) * 5.0
	if fy > hill:
		return Color(0.5, 0.66, 0.3).lerp(Color(0.72, 0.68, 0.3), (fy - hill) / 12.0)
	if Vector2(fx - 222.0, fy - 30.0).length() < 13.0:
		return Color(1.0, 0.95, 0.7)
	return Color(0.32, 0.55, 0.9).lerp(Color(1.0, 0.88, 0.66), fy / 105.0)
