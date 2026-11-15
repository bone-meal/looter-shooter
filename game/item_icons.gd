# Purpose: draws the icon of an item of the gun side of the game into any CanvasItem. Guns and armour use the rendered
# pictures of tools/blender/icons.py (assets/ui/icons/guns/<body>.png; assets/ui/icons/items/<id>_<tier>.png: an
# armour piece looks finer at every tier, a plain unrolled piece wears the Common look); anything without a picture
# falls back to the old drawn shapes (the knife, the worm) or the slot icon of the sheet. `plate` draws the tier's
# backdrop behind an icon (more ornament the rarer it is) and the item level's badge (its metal by sea region).
# Used by the HUD, the inventory, the bank and the trade window.
# Dependencies: game/icon_art.gd (the icon sheet), game/tier_style.gd (tier colours), data/items.json (slot and color of armour).
extends RefCounted

const IconArt = preload("res://game/icon_art.gd")
const TierStyle = preload("res://game/tier_style.gd")
const GUN_PICTURES := "res://assets/ui/icons/guns/"
const ITEM_PICTURES := "res://assets/ui/icons/items/"
const KNIFE_PICTURES := "res://assets/ui/icons/knives/"
const TIER_ORDER := ["grey", "green", "blue", "purple", "gold", "orange", "rainbow", "pony"]
# badge metal by sea region band of the item level (1-10, 11-20 ... 61-70): bronze, iron, steel, silver, gold, platinum, obsidian
const BAND_METAL := [Color(0.72, 0.45, 0.24), Color(0.5, 0.52, 0.55), Color(0.7, 0.76, 0.84), Color(0.86, 0.88, 0.92), Color(1.0, 0.8, 0.3), Color(0.85, 0.95, 1.0), Color(0.55, 0.12, 0.22)]

const WORM := Color(0.95, 0.55, 0.68)
# equipment slot -> shape of the icon sheet
const SLOT_SHAPES := {"hat": "hat", "head": "helm", "earrings": "earrings", "necklace": "necklace", "glasses": "glasses", "mouth": "dots", "shirt": "shirt",
	"chestplate": "chestplate", "gauntlets": "gauntlets", "ring": "ring", "bracelet": "bracelet", "pants": "pants", "leg_armor": "leg_armor", "cape": "cape",
	"waist": "belt", "boots": "boots", "foot_armor": "sabatons"}

static var _items := {}
static var _pictures := {}  # path -> Texture2D or null (looked for once)
static var _glow: GradientTexture2D
const WORM_LIGHT := Color(1.0, 0.75, 0.82)


# Draws the icon for `id` centered inside `rect`. A rendered picture when there is one (`tier` picks an armour piece's
# look; guns' pictures are the same for every tier), else the drawn shape in `tint` (the worm keeps its pink).
static func draw(canvas: CanvasItem, id: String, rect: Rect2, tint: Color, tier: String = "") -> void:
	var picture := _picture(id, tier)
	if picture != null:
		var size := picture.get_size()
		var fit := minf(rect.size.x / size.x, rect.size.y / size.y)
		canvas.draw_texture_rect(picture, Rect2(rect.get_center() - size * fit * 0.5, size * fit), false, Color(1, 1, 1, tint.a))
		return
	if id.begins_with("knife:"):  # a knife type with no picture yet: the drawn knife
		id = "knife"
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
		"smg":
			canvas.draw_rect(Rect2(o + Vector2(24, 9) * s, Vector2(34, 10) * s), tint)  # receiver
			canvas.draw_rect(Rect2(o + Vector2(58, 12) * s, Vector2(18, 4) * s), tint)  # barrel
			canvas.draw_rect(Rect2(o + Vector2(8, 11) * s, Vector2(16, 4) * s), tint)  # folded stock
			canvas.draw_rect(Rect2(o + Vector2(40, 19) * s, Vector2(7, 15) * s), tint)  # magazine
			canvas.draw_rect(Rect2(o + Vector2(28, 19) * s, Vector2(7, 10) * s), tint)  # grip
		"revolver":
			canvas.draw_rect(Rect2(o + Vector2(36, 9) * s, Vector2(44, 6) * s), tint)  # barrel
			canvas.draw_rect(Rect2(o + Vector2(26, 7) * s, Vector2(14, 12) * s), tint)  # cylinder
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(18, 9) * s, o + Vector2(28, 9) * s, o + Vector2(24, 32) * s, o + Vector2(12, 30) * s]), tint)  # grip
		"lever_rifle":
			canvas.draw_rect(Rect2(o + Vector2(26, 11) * s, Vector2(26, 7) * s), tint)  # receiver
			canvas.draw_rect(Rect2(o + Vector2(52, 12) * s, Vector2(38, 3) * s), tint)  # barrel
			canvas.draw_rect(Rect2(o + Vector2(52, 16) * s, Vector2(30, 2) * s), tint)  # tube
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(0, 12) * s, o + Vector2(26, 11) * s, o + Vector2(26, 18) * s, o + Vector2(2, 24) * s]), tint)  # stock
			canvas.draw_arc(o + Vector2(33, 22) * s, 5.0 * s, 0.0, PI, 10, tint, maxf(2.0 * s, 1.0))  # lever loop
		"harpoon_gun":
			canvas.draw_rect(Rect2(o + Vector2(20, 12) * s, Vector2(40, 7) * s), tint)  # body
			canvas.draw_rect(Rect2(o + Vector2(30, 14) * s, Vector2(56, 2) * s), tint)  # spear
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(84, 10) * s, o + Vector2(92, 15) * s, o + Vector2(84, 20) * s]), tint)  # head
			canvas.draw_rect(Rect2(o + Vector2(26, 19) * s, Vector2(7, 12) * s), tint)  # grip
			canvas.draw_circle(o + Vector2(14, 16) * s, 6.0 * s, tint)  # reel
		"flare_gun":
			canvas.draw_rect(Rect2(o + Vector2(28, 8) * s, Vector2(36, 12) * s), tint)  # fat barrel
			canvas.draw_rect(Rect2(o + Vector2(20, 9) * s, Vector2(10, 9) * s), tint)  # breech
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(20, 18) * s, o + Vector2(30, 18) * s, o + Vector2(28, 33) * s, o + Vector2(17, 32) * s]), tint)  # grip
		"flamethrower":
			canvas.draw_rect(Rect2(o + Vector2(22, 10) * s, Vector2(56, 6) * s), tint)  # wand
			canvas.draw_rect(Rect2(o + Vector2(78, 8) * s, Vector2(8, 10) * s), tint)  # nozzle
			canvas.draw_circle(o + Vector2(14, 20) * s, 10.0 * s, tint)  # tank
			canvas.draw_rect(Rect2(o + Vector2(40, 16) * s, Vector2(7, 12) * s), tint)  # grip
		"crossbow":
			canvas.draw_rect(Rect2(o + Vector2(6, 14) * s, Vector2(64, 5) * s), tint)  # stock
			canvas.draw_polyline(PackedVector2Array([o + Vector2(70, 2) * s, o + Vector2(62, 16) * s, o + Vector2(70, 30) * s]), tint, maxf(3.0 * s, 1.0), true)  # limbs
			canvas.draw_line(o + Vector2(70, 2) * s, o + Vector2(70, 30) * s, Color(tint, tint.a * 0.6), maxf(1.0 * s, 1.0))  # string
			canvas.draw_rect(Rect2(o + Vector2(30, 12) * s, Vector2(58, 2) * s), tint)  # bolt
			canvas.draw_rect(Rect2(o + Vector2(28, 19) * s, Vector2(7, 11) * s), tint)  # grip
		"blunderbuss":
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(34, 10) * s, o + Vector2(80, 8) * s, o + Vector2(90, 3) * s, o + Vector2(90, 22) * s, o + Vector2(80, 17) * s, o + Vector2(34, 16) * s]), tint)  # flared barrel
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(0, 14) * s, o + Vector2(34, 10) * s, o + Vector2(34, 18) * s, o + Vector2(4, 26) * s]), tint)  # stock
		"knife":
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(38, 11) * s, o + Vector2(74, 11) * s, o + Vector2(88, 19) * s, o + Vector2(72, 23) * s, o + Vector2(38, 23) * s]), tint)  # blade
			canvas.draw_rect(Rect2(o + Vector2(33, 6) * s, Vector2(5, 22) * s), tint)  # guard
			canvas.draw_rect(Rect2(o + Vector2(4, 12) * s, Vector2(29, 10) * s), Color(tint, tint.a * 0.7))  # handle
		"cigarette":
			canvas.draw_rect(Rect2(o + Vector2(8, 15) * s, Vector2(56, 6) * s), Color(0.95, 0.93, 0.88))  # paper
			canvas.draw_rect(Rect2(o + Vector2(8, 15) * s, Vector2(14, 6) * s), Color(0.85, 0.55, 0.2))  # filter
			canvas.draw_rect(Rect2(o + Vector2(64, 15) * s, Vector2(6, 6) * s), Color(0.5, 0.5, 0.5))  # ash
			canvas.draw_rect(Rect2(o + Vector2(70, 15) * s, Vector2(5, 6) * s), Color(1.0, 0.45, 0.1))  # ember
			canvas.draw_polyline(PackedVector2Array([o + Vector2(74, 12) * s, o + Vector2(70, 6) * s, o + Vector2(76, 0) * s]), Color(0.8, 0.8, 0.85, 0.7), maxf(2.0 * s, 1.0), true)  # smoke
		_:
			# Armour: the shape says where it is worn (a ring, trousers, a helmet ...), the colour is the item's own (data/items.json).
			var def: Dictionary = _defs().get(id.get_slice("+", 0), {})  # a variant ("<id>+holster") looks like its plain item
			var shape := slot_shape(String(def.get("slot", "")))
			var c: Array = def.get("color", [0.8, 0.8, 0.82])
			IconArt.draw(canvas, shape, rect, Color(c[0], c[1], c[2]))


# The rendered picture of an item (null = none: draw the old way).
static func _picture(id: String, tier: String) -> Texture2D:
	var base := id.get_slice("+", 0)
	var paths: Array[String] = [GUN_PICTURES + base + ".png"]
	if base.begins_with("knife:"):  # a knife type ("knife:bowie"): its rendered picture
		paths = [KNIFE_PICTURES + base.trim_prefix("knife:") + ".png"]
	if base != "knife" and base != "worm":
		paths.append(ITEM_PICTURES + "%s_%s.png" % [base, tier if TIER_ORDER.has(tier) else "grey"])
		paths.append(ITEM_PICTURES + base + ".png")
	for path: String in paths:
		if not _pictures.has(path):
			_pictures[path] = load(path) if ResourceLoader.exists(path) else null
		if _pictures[path] != null:
			return _pictures[path]
	return null


# The tier's backdrop behind an icon inside `rect`: a glow in the tier's colour, then ornament that grows with rarity
# (Uncommon an inner line, Rare corner brackets, Epic a gem, Legendary filigree, Mythic an ember edge, Prismatic a
# shimmer of every colour, Pony twinkling stars). `lvl` > 0 adds the item level's badge (needs `font`).
static func plate(canvas: CanvasItem, rect: Rect2, db: RefCounted, tier: String, t: float, lvl: int = 0, font: Font = null) -> void:
	var rank := TIER_ORDER.find(tier)
	if rank < 0:
		return
	var tint := TierStyle.color(db, tier, t)
	if _glow == null:
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 0.0)])
		_glow = GradientTexture2D.new()
		_glow.gradient = grad
		_glow.fill = GradientTexture2D.FILL_RADIAL
		_glow.fill_from = Vector2(0.5, 0.5)
		_glow.fill_to = Vector2(0.5, 0.0)
		_glow.width = 64
		_glow.height = 64
	var inner := rect.grow(-3.0)
	var low := Color(tint, 0.10 + 0.035 * rank)
	canvas.draw_polygon(PackedVector2Array([inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]),
		PackedColorArray([Color(tint, 0.0), Color(tint, 0.0), low, low]))
	canvas.draw_texture_rect(_glow, inner.grow(-inner.size.x * 0.08), false, Color(tint, 0.12 + 0.04 * rank))
	var s := minf(inner.size.x, inner.size.y)
	var edge := Color(tint, 0.75)
	if rank >= 1:
		canvas.draw_rect(inner, Color(tint, 0.35), false, 1.0)
	if rank >= 2:  # corner brackets
		var arm := s * 0.18
		for c: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
			var dx := arm if c.x < inner.get_center().x else -arm
			var dy := arm if c.y < inner.get_center().y else -arm
			canvas.draw_polyline(PackedVector2Array([c + Vector2(dx, 0), c, c + Vector2(0, dy)]), edge, 2.0)
	if rank >= 3:  # a gem at the top
		var g := Vector2(inner.get_center().x, inner.position.y + 1.0)
		var r := maxf(s * 0.05, 3.0)
		canvas.draw_colored_polygon(PackedVector2Array([g + Vector2(0, -r), g + Vector2(r, 0), g + Vector2(0, r), g + Vector2(-r, 0)]), tint.lightened(0.3))
		canvas.draw_polyline(PackedVector2Array([g + Vector2(0, -r), g + Vector2(r, 0), g + Vector2(0, r), g + Vector2(-r, 0), g + Vector2(0, -r)]), Color(0, 0, 0, 0.5), 1.0)
	if rank >= 4:  # filigree curls in the corners
		var curl := s * 0.12
		for c: Vector2 in [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]:
			var toward := (inner.get_center() - c).normalized()
			canvas.draw_arc(c + toward * curl * 1.1, curl * 0.55, 0.0, TAU * 0.75, 12, Color(tint, 0.6), 1.5)
	if rank == 5:  # a warm ember edge along the bottom
		canvas.draw_line(Vector2(inner.position.x + 4, inner.end.y - 2), Vector2(inner.end.x - 4, inner.end.y - 2), Color(1.0, 0.5, 0.1, 0.7 + 0.2 * sin(t * 5.0)), 2.0)
	if rank == 6:  # every colour sweeping round the edge
		for i in 12:
			var u := float(i) / 12.0
			var a := inner.position + Vector2(inner.size.x * u, 0)
			canvas.draw_line(a, a + Vector2(inner.size.x / 12.0, 0), Color.from_hsv(fmod(u + t * 0.3, 1.0), 0.8, 1.0, 0.8), 2.0)
			var b := Vector2(inner.end.x - inner.size.x * u, inner.end.y)
			canvas.draw_line(b, b - Vector2(inner.size.x / 12.0, 0), Color.from_hsv(fmod(u + 0.5 + t * 0.3, 1.0), 0.8, 1.0, 0.8), 2.0)
	if rank == 7:  # twinkling stars
		for i in 4:
			var spot := inner.position + inner.size * Vector2(fmod(0.17 + 0.61 * i, 1.0), fmod(0.23 + 0.37 * i, 0.9) + 0.05)
			var twinkle := maxf(sin(t * 3.0 + i * 1.7), 0.0)
			var r := maxf(s * 0.06, 3.0) * (0.4 + 0.6 * twinkle)
			var c := Color(1, 1, 1, 0.3 + 0.6 * twinkle)
			canvas.draw_line(spot - Vector2(r, 0), spot + Vector2(r, 0), c, 1.5)
			canvas.draw_line(spot - Vector2(0, r), spot + Vector2(0, r), c, 1.5)
	if lvl > 0 and font != null:
		badge(canvas, font, Vector2(inner.position.x + 2.0, inner.end.y - 2.0), lvl, clampf(s * 0.16, 9.0, 14.0))


# The item level's badge with its bottom-left corner at `at`: a small plate in the metal of the level's sea region band
# (bronze 1-10 ... obsidian 61-70), one notch per band.
static func badge(canvas: CanvasItem, font: Font, at: Vector2, lvl: int, points: float) -> void:
	var band := clampi(ceili(float(lvl) / 10.0), 1, 7)
	var metal: Color = BAND_METAL[band - 1]
	var text := str(lvl)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(points)).x + 8.0
	var box := Rect2(at - Vector2(0, points + 4.0), Vector2(w, points + 4.0))
	canvas.draw_rect(box, Color(0.04, 0.04, 0.06, 0.85))
	canvas.draw_rect(box, metal, false, 1.5)
	for i in band:  # notches along the top
		canvas.draw_line(box.position + Vector2(3.0 + i * 3.0, 0), box.position + Vector2(3.0 + i * 3.0, -2.5), metal, 1.5)
	canvas.draw_string(font, box.position + Vector2(4.0, points + 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(points), metal.lightened(0.35))


# The icon that stands for an equipment slot ("ring_2" and "ring" are both a ring).
static func slot_shape(slot: String) -> String:
	return String(SLOT_SHAPES.get(slot.trim_suffix("_1").trim_suffix("_2"), "shield"))


static func _defs() -> Dictionary:
	if _items.is_empty():
		_items = JSON.parse_string(FileAccess.get_file_as_string("res://data/items.json"))["items"]
	return _items
