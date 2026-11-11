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


# Writes a gun's name: the tier's tag in its own face (if it has one), the rest in `font`. `width` >= 0 right-aligns
# the whole name inside that width, as draw_string does.
static func draw_name(canvas: CanvasItem, font: Font, at: Vector2, db: RefCounted, tier_id: String, text: String, points: int, tint: Color, width: float = -1.0) -> void:
	var tag := String(db.tier(tier_id).get("tag", ""))
	var fancy := tag_font(db, tier_id)
	if fancy == null or tag == "" or not text.begins_with(tag):
		canvas.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_RIGHT if width >= 0.0 else HORIZONTAL_ALIGNMENT_LEFT, width, points, tint)
		return
	var rest := text.substr(tag.length())
	var tag_wide := fancy.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, points + 4).x
	var start := at.x + (maxf(width - tag_wide - font.get_string_size(rest, HORIZONTAL_ALIGNMENT_LEFT, -1, points).x, 0.0) if width >= 0.0 else 0.0)
	canvas.draw_string(fancy, Vector2(start + 1.0, at.y + 1.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, points + 4, Color(0, 0, 0, 0.6))
	canvas.draw_string(fancy, Vector2(start, at.y), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, points + 4, tint)
	canvas.draw_string(font, Vector2(start + tag_wide, at.y), rest, HORIZONTAL_ALIGNMENT_LEFT, -1, points, tint)
