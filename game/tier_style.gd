# Purpose: how a gun tier looks in text: its colour (the rainbow and pony tiers cycle over time) and its name. A tier
# whose data names a `tag_font` (pony: "*PONY*") gets that word written bold and slanted in that font, the rest of the
# gun's name in the ordinary one. Used by the inventory, the HUD and the drops lying in the world.
# Dependencies: core/gun_db.gd (tier `color`, `animated`, `tag`, `tag_font` from data/gun_loot.json).
extends RefCounted


# Colour of a tier at time `t` seconds. Static tiers return their data colour.
static func color(db: RefCounted, tier_id: String, t: float) -> Color:
	var tier: Dictionary = db.tier(tier_id)
	match String(tier["animated"]):
		"rainbow":
			return Color.from_hsv(fmod(t * 0.35, 1.0), 0.8, 1.0)
		"pony":
			var hue := fmod(0.82 + 0.18 * sin(t * 1.7) + t * 0.05, 1.0)
			var sparkle := 0.5 + 0.5 * sin(t * 9.0)
			return Color.from_hsv(hue, 0.35 + 0.25 * sparkle, 1.0)
	return Color(String(tier["color"]))


# True when the tier's colour changes over time (screens redraw every frame while one is visible).
# A pony family's own colour (data/pony_families.json hue / sat), for its trait line on the gun card.
static func family_colour(db: RefCounted, family: String) -> Color:
	var look: Dictionary = db.family_def(family)
	return Color.from_hsv(float(look.get("hue", 0.85)), clampf(float(look.get("sat", 0.45)) + 0.2, 0.0, 1.0), 1.0)


static func animated(db: RefCounted, tier_id: String) -> bool:
	return String(db.tier(tier_id)["animated"]) != "none"


static var _tag_fonts := {}  # font file -> the bold, slanted face made from it


# The face a tier's tag is written in (null = the tier has none of its own).
static func tag_font(db: RefCounted, tier_id: String) -> Font:
	var path := String(db.tier(tier_id).get("tag_font", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _tag_fonts.has(path):
		var face := FontVariation.new()
		face.base_font = load(path)
		face.variation_embolden = 0.7
		face.variation_transform = Transform2D(Vector2(1.0, 0.22), Vector2(0.0, 1.0), Vector2.ZERO)  # slanted
		_tag_fonts[path] = face
	return _tag_fonts[path]


# Writes a gun's name: the tier's tag in its own face (if it has one; it may follow a prefix such as "W kills "), the
# rest in `font`. `width` >= 0 right-aligns the whole name inside that width, as draw_string does, and shrinks the
# letters until the whole name fits (a long pony name kept its tag out of sight on the HUD).
# `scroll_t` >= 0 (seconds): a name too long for `width` scrolls slowly from end to end instead of shrinking (the inventory).
static func draw_name(canvas: CanvasItem, font: Font, at: Vector2, db: RefCounted, tier_id: String, text: String, points: int, tint: Color, width: float = -1.0, scroll_t: float = -1.0) -> void:
	var tag := String(db.tier(tier_id).get("tag", ""))
	var fancy := tag_font(db, tier_id)
	var cut := text.find(tag) if tag != "" else -1
	if scroll_t >= 0.0 and width >= 0.0 and overflows(font, db, tier_id, text, points, width):
		_scroll(canvas, font, fancy if cut >= 0 else null, at, text, cut, tag, points, tint, width, scroll_t)
		return
	if fancy == null or cut < 0:
		if width >= 0.0:
			while points > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x > width:
				points -= 1
		canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_RIGHT if width >= 0.0 else HORIZONTAL_ALIGNMENT_LEFT, width, points, tint)
		return
	var before := text.substr(0, cut)
	var rest := text.substr(cut + tag.length())
	var wide := func(size: int) -> float:
		return font.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + fancy.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, size + 4).x + font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if width >= 0.0:
		while points > 9 and float(wide.call(points)) > width:
			points -= 1
	var start := at.x + (maxf(width - float(wide.call(points)), 0.0) if width >= 0.0 else 0.0)
	var before_wide := font.get_string_size(before, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x
	var tag_wide := fancy.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, points + 4).x
	if before != "":
		canvas.draw_string(font, Vector2(start, at.y), before, HORIZONTAL_ALIGNMENT_LEFT, -1, points, tint)
	canvas.draw_string(fancy, Vector2(start + before_wide + 1.0, at.y + 1.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, points + 4, Color(0, 0, 0, 0.6))
	canvas.draw_string(fancy, Vector2(start + before_wide, at.y), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, points + 4, tint)
	canvas.draw_string(font, Vector2(start + before_wide + tag_wide, at.y), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, points, tint)


# True when the whole name (tag in its face) is wider than `width` at `points`.
static func overflows(font: Font, db: RefCounted, tier_id: String, text: String, points: int, width: float) -> bool:
	var tag := String(db.tier(tier_id).get("tag", ""))
	var fancy := tag_font(db, tier_id)
	var cut := text.find(tag) if tag != "" else -1
	if fancy == null or cut < 0:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x > width
	var rest := text.substr(0, cut) + text.substr(cut + tag.length())
	return font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x + fancy.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, points + 4).x > width


# A marquee: rests at the start, slides left to show the end, rests, starts again. Letters are drawn one by one and only
# those wholly inside [at.x, at.x + width] (a canvas cannot clip a single string).
static func _scroll(canvas: CanvasItem, font: Font, fancy: Font, at: Vector2, text: String, cut: int, tag: String, points: int, tint: Color, width: float, t: float) -> void:
	var glyphs: Array = []  # [char, font, size, advance]
	var total := 0.0
	for i in text.length():
		var in_tag := fancy != null and i >= cut and i < cut + tag.length()
		var face: Font = fancy if in_tag else font
		var size := points + 4 if in_tag else points
		var advance := face.get_char_size(text.unicode_at(i), size).x
		glyphs.append([text.unicode_at(i), face, size, advance, in_tag])
		total += advance
	var travel := total - width
	var rest := 1.2
	var slide := travel / 40.0  # 40 pixels a second
	var cycle := fmod(t, rest * 2.0 + slide)
	var offset := clampf((cycle - rest) / maxf(slide, 0.01), 0.0, 1.0) * travel
	var x := at.x - offset
	for g: Array in glyphs:
		var advance := float(g[3])
		if x >= at.x - 0.5 and x + advance <= at.x + width + 0.5:
			if bool(g[4]):
				canvas.draw_char(g[1], Vector2(x + 1.0, at.y + 1.0), String.chr(int(g[0])), int(g[2]), Color(0, 0, 0, 0.6))
			canvas.draw_char(g[1], Vector2(x, at.y), String.chr(int(g[0])), int(g[2]), tint)
		x += advance
