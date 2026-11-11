# Purpose: colours for gun tiers, including the animated rainbow and pony tiers (hue / pastel cycling over time). Used by the inventory, HUD and later loot beams.
# Dependencies: core/gun_db.gd (tier colour and `animated` fields from data/gun_loot.json).
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
