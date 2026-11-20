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


# Writes a gun's name in three looks (polish1 item 47): the RARITY word (the tier's tag or name) in the tier colour and
# its own bold face (pony: its tag_font, slanted), the MAKER (`maker`, when given and in the name) in its own colour and
# a lettered face, the rest (the gun's own name) in plain white. `width` >= 0 right-aligns the whole name inside that
# width and shrinks the letters until it fits; `scroll_t` >= 0 (seconds): a name too long for `width` scrolls slowly
# from end to end instead (the inventory, the HUD slot).
static func draw_name(canvas: CanvasItem, font: Font, at: Vector2, db: RefCounted, tier_id: String, text: String, points: int, tint: Color, width: float = -1.0, scroll_t: float = -1.0, maker := "") -> void:
	var parts := _parts(font, db, tier_id, text, tint, maker)
	if scroll_t >= 0.0 and width >= 0.0 and _wide(parts, points) > width:
		_scroll(canvas, parts, at, points, width, scroll_t, tint)
		return
	if width >= 0.0:
		while points > 9 and _wide(parts, points) > width:
			points -= 1
	var x := at.x + (maxf(width - _wide(parts, points), 0.0) if width >= 0.0 else 0.0)
	for part: Array in parts:
		var size := points + int(part[3])
		if bool(part[4]):  # the rarity word: a soft shadow under it
			canvas.draw_string(part[1], Vector2(x + 1.0, at.y + 1.0), String(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.6))
		canvas.draw_string(part[1], Vector2(x, at.y), String(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint if part[2] == null else part[2])
		x += (part[1] as Font).get_string_size(String(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


# True when the whole name (each part in its face) is wider than `width` at `points`.
static func overflows(font: Font, db: RefCounted, tier_id: String, text: String, points: int, width: float, maker := "") -> bool:
	return _wide(_parts(font, db, tier_id, text, Color.WHITE, maker), points) > width


const NAME_WHITE := Color(0.95, 0.95, 0.97)
static var _rarity_font: Font = load("res://assets/fonts/LilitaOne.ttf")
static var _maker_font: Font = load("res://assets/fonts/Cinzel.ttf")
static var _maker_colours := {}  # maker name -> its colour (data/manufacturers.json), read once
static var _cache := {}  # name key -> its parts (made once, not every frame); a null colour = the tier's (animated) tint


# The name cut into [text, font, colour (null = the tint), size offset, shadow] parts.
static func _parts(font: Font, db: RefCounted, tier_id: String, text: String, _tint: Color, maker: String) -> Array:
	var key := "%s|%s|%s|%d" % [tier_id, text, maker, font.get_instance_id()]
	if _cache.has(key):
		return _cache[key]
	if _cache.size() > 256:
		_cache.clear()
	var tier_def: Dictionary = db.tier(tier_id)
	var word := String(tier_def.get("tag", tier_def.get("name", "")))
	var fancy := tag_font(db, tier_id)
	var cuts: Array = []  # [at, length, font, colour, size offset, shadow]
	var at := text.find(word) if word != "" else -1
	if at >= 0:
		cuts.append([at, word.length(), fancy if fancy != null else _rarity_font, null, 4 if fancy != null else 1, true])
	var m := text.find(maker) if maker != "" else -1
	if m >= 0 and (at < 0 or m >= at + word.length() or m + maker.length() <= at):
		cuts.append([m, maker.length(), _maker_font, _maker_colour(db, maker), -1, false])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var parts: Array = []
	var from := 0
	for c: Array in cuts:
		if int(c[0]) > from:
			parts.append([text.substr(from, int(c[0]) - from), font, _plain(at), 0, false])
		parts.append([text.substr(int(c[0]), int(c[1])), c[2], c[3], c[4], c[5]])
		from = int(c[0]) + int(c[1])
	if from < text.length():
		parts.append([text.substr(from), font, _plain(at), 0, false])
	_cache[key] = parts
	return parts


# The colour of the plain words: white beside a rarity word, else the tint (null: an armour name without one).
static func _plain(rarity_at: int) -> Variant:
	if rarity_at >= 0:
		return NAME_WHITE
	return null


static func _maker_colour(db: RefCounted, maker: String) -> Color:
	if _maker_colours.is_empty():
		for id: String in db.makers:
			_maker_colours[String(db.makers[id]["name"])] = Color(String(db.makers[id].get("color", "#d0d0d0")))
	return _maker_colours.get(maker, Color(0.8, 0.8, 0.85))


static func _wide(parts: Array, points: int) -> float:
	var w := 0.0
	for part: Array in parts:
		w += (part[1] as Font).get_string_size(String(part[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, points + int(part[3])).x
	return w


# A marquee: rests at the start, slides left to show the end, rests, starts again. Letters are drawn one by one and only
# those wholly inside [at.x, at.x + width] (a canvas cannot clip a single string).
static func _scroll(canvas: CanvasItem, parts: Array, at: Vector2, points: int, width: float, t: float, tint: Color) -> void:
	var travel := _wide(parts, points) - width
	var rest := 1.2
	var slide := travel / 40.0  # 40 pixels a second
	var cycle := fmod(t, rest * 2.0 + slide)
	var offset := clampf((cycle - rest) / maxf(slide, 0.01), 0.0, 1.0) * travel
	var x := at.x - offset
	for part: Array in parts:
		var face: Font = part[1]
		var size := points + int(part[3])
		var text := String(part[0])
		for i in text.length():
			var advance := face.get_char_size(text.unicode_at(i), size).x
			if x >= at.x - 0.5 and x + advance <= at.x + width + 0.5:
				if bool(part[4]):
					canvas.draw_char(face, Vector2(x + 1.0, at.y + 1.0), text[i], size, Color(0, 0, 0, 0.6))
				canvas.draw_char(face, Vector2(x, at.y), text[i], size, tint if part[2] == null else part[2])
			x += advance
