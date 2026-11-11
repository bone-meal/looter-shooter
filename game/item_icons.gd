# Purpose: draws the icon of an item of the gun side of the game into any CanvasItem: guns and the worm as simple
# drawn shapes, armour as the icon of the slot it is worn in (ring, trousers, helmet ...) in the item's own colour.
# Used by the HUD and the inventory screen.
# Dependencies: game/icon_art.gd (the icon sheet), data/items.json (slot and color of armour).
extends RefCounted

const IconArt = preload("res://game/icon_art.gd")

const WORM := Color(0.95, 0.55, 0.68)
# equipment slot -> shape of the icon sheet
const SLOT_SHAPES := {"hat": "hat", "head": "helm", "earrings": "earrings", "necklace": "necklace", "glasses": "glasses", "mouth": "dots", "shirt": "shirt",
	"chestplate": "chestplate", "gauntlets": "gauntlets", "ring": "ring", "bracelet": "bracelet", "pants": "pants", "leg_armor": "leg_armor", "cape": "cape",
	"waist": "belt", "boots": "boots", "foot_armor": "sabatons"}

static var _items := {}
const WORM_LIGHT := Color(1.0, 0.75, 0.82)


# Draws the icon for `id` centered inside `rect`. Guns use `tint`; the worm keeps its pink.
static func draw(canvas: CanvasItem, id: String, rect: Rect2, tint: Color) -> void:
	var s := minf(rect.size.x / 96.0, rect.size.y / 40.0)
	var o := rect.position + (rect.size - Vector2(90, 36) * s) * 0.5
	match id:
		"pistol_basic":
			canvas.draw_rect(Rect2(o + Vector2(2, 4) * s, Vector2(38, 10) * s), tint)
			canvas.draw_rect(Rect2(o + Vector2(6, 14) * s, Vector2(26, 5) * s), tint)
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(8, 19) * s, o + Vector2(19, 19) * s, o + Vector2(16, 33) * s, o + Vector2(5, 33) * s]), tint)
		"sniper_basic":
			canvas.draw_rect(Rect2(o + Vector2(14, 12) * s, Vector2(44, 7) * s), tint)
			canvas.draw_rect(Rect2(o + Vector2(58, 14) * s, Vector2(30, 3) * s), tint)
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(0, 10) * s, o + Vector2(14, 12) * s, o + Vector2(14, 22) * s, o + Vector2(3, 25) * s]), tint)
			canvas.draw_rect(Rect2(o + Vector2(26, 6) * s, Vector2(24, 5) * s), tint)
			canvas.draw_rect(Rect2(o + Vector2(32, 19) * s, Vector2(7, 9) * s), tint)
		"worm":
			var points := PackedVector2Array()
			for i in 13:
				var t := i / 12.0
				points.append(o + Vector2(8.0 + 74.0 * t, 18.0 + sin(t * TAU * 1.5) * 9.0) * s)
			canvas.draw_polyline(points, WORM, maxf(8.0 * s, 2.0), true)
			canvas.draw_polyline(points, WORM_LIGHT, maxf(2.5 * s, 1.0), true)
			canvas.draw_circle(points[0], maxf(4.5 * s, 1.5), WORM)
			canvas.draw_circle(points[12], maxf(4.0 * s, 1.5), WORM)
		"ak47", "m16", "m60":
			canvas.draw_rect(Rect2(o + Vector2(20, 10) * s, Vector2(40, 8) * s), tint)  # receiver
			canvas.draw_rect(Rect2(o + Vector2(60, 12) * s, Vector2(30, 3) * s), tint)  # barrel
			canvas.draw_rect(Rect2(o + Vector2(0, 11) * s, Vector2(20, 10) * s), tint)  # stock
			canvas.draw_rect(Rect2(o + Vector2(32, 18) * s, Vector2(8, 14 if id != "m60" else 10) * s), tint)  # magazine
			if id == "m60":
				canvas.draw_rect(Rect2(o + Vector2(24, 24) * s, Vector2(16, 10) * s), tint)  # ammo box
		"shotgun_double":
			canvas.draw_rect(Rect2(o + Vector2(24, 10) * s, Vector2(66, 3) * s), tint)  # barrels
			canvas.draw_rect(Rect2(o + Vector2(24, 14) * s, Vector2(66, 3) * s), tint)
			canvas.draw_rect(Rect2(o + Vector2(14, 9) * s, Vector2(14, 10) * s), tint)  # breech
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(0, 10) * s, o + Vector2(14, 10) * s, o + Vector2(14, 20) * s, o + Vector2(2, 26) * s]), tint)  # stock
		"rocket_launcher":
			canvas.draw_rect(Rect2(o + Vector2(6, 8) * s, Vector2(76, 14) * s), tint)  # tube
			canvas.draw_rect(Rect2(o + Vector2(2, 5) * s, Vector2(8, 20) * s), tint)  # rear flare
			canvas.draw_rect(Rect2(o + Vector2(78, 5) * s, Vector2(8, 20) * s), tint)  # front flare
			canvas.draw_rect(Rect2(o + Vector2(36, 22) * s, Vector2(8, 12) * s), tint)  # grip
		"grenade_launcher":
			canvas.draw_rect(Rect2(o + Vector2(44, 12) * s, Vector2(44, 6) * s), tint)  # barrel
			canvas.draw_circle(o + Vector2(38, 15) * s, 11.0 * s, tint)  # drum
			canvas.draw_rect(Rect2(o + Vector2(0, 12) * s, Vector2(26, 8) * s), tint)  # stock
			canvas.draw_rect(Rect2(o + Vector2(30, 24) * s, Vector2(8, 10) * s), tint)  # grip
		"cigarette":
			canvas.draw_rect(Rect2(o + Vector2(8, 15) * s, Vector2(56, 6) * s), Color(0.95, 0.93, 0.88))  # paper
			canvas.draw_rect(Rect2(o + Vector2(8, 15) * s, Vector2(14, 6) * s), Color(0.85, 0.55, 0.2))  # filter
			canvas.draw_rect(Rect2(o + Vector2(64, 15) * s, Vector2(6, 6) * s), Color(0.5, 0.5, 0.5))  # ash
			canvas.draw_rect(Rect2(o + Vector2(70, 15) * s, Vector2(5, 6) * s), Color(1.0, 0.45, 0.1))  # ember
			canvas.draw_polyline(PackedVector2Array([o + Vector2(74, 12) * s, o + Vector2(70, 6) * s, o + Vector2(76, 0) * s]), Color(0.8, 0.8, 0.85, 0.7), maxf(2.0 * s, 1.0), true)  # smoke
		_:
			# Armour: the shape says where it is worn (a ring, trousers, a helmet ...), the colour is the item's own (data/items.json).
			var def: Dictionary = _defs().get(id, {})
			var shape := slot_shape(String(def.get("slot", "")))
			var c: Array = def.get("color", [0.8, 0.8, 0.82])
			IconArt.draw(canvas, shape, rect, Color(c[0], c[1], c[2]))


# The icon that stands for an equipment slot ("ring_2" and "ring" are both a ring).
static func slot_shape(slot: String) -> String:
	return String(SLOT_SHAPES.get(slot.trim_suffix("_1").trim_suffix("_2"), "shield"))


static func _defs() -> Dictionary:
	if _items.is_empty():
		_items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))["items"]
	return _items
