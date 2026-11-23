# Purpose: (polish1 items 99 / 104) Aurelind's feedback on the HUD. The LOOT LIST: what came into the bag, one line
# per item with its icon, stacked ("Bread x3": the same item adds to its line and starts its timer again), each line on
# its own timer, the oldest fading first. The SKILL BANNER: a level-up as a manuscript page sliding down from the top
# (the skill's icon in a gold roundel, the skill in blackletter, "Level n", what the level opens), with the level-up
# sound played by the world. Pure drawing over any CanvasItem.
# Dependencies: game/fantasy_style.gd (fonts, colours), game/icon_art.gd (item / skill icons).
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")
const IconArt = preload("res://game/icon_art.gd")

const LINE_SECONDS := 6.0
const FADE := 0.9
const MAX_LINES := 9
const BANNER_SECONDS := 4.5
const RED := Color(0.62, 0.1, 0.07)
const PAPER := Color(0.92, 0.85, 0.66)
const INK := Color(0.2, 0.12, 0.06)

var lines: Array = []  # {"item", "name", "count", "icon", "color", "left"}
var _banners: Array = []  # {"skill", "name", "level", "opened", "icon", "color", "age"}


func add_item(item: String, item_name: String, count: int, icon: String, color: Color) -> void:
	for line: Dictionary in lines:
		if String(line["item"]) == item:
			line["count"] = int(line["count"]) + count
			line["left"] = LINE_SECONDS
			return
	if lines.size() >= MAX_LINES:
		lines.pop_front()
	lines.append({"item": item, "name": item_name, "count": count, "icon": icon, "color": color, "left": LINE_SECONDS})


func add_level(skill_name: String, level: int, opened: PackedStringArray, icon: String, color: Color) -> void:
	_banners.append({"name": skill_name, "level": level, "opened": opened, "icon": icon, "color": color, "age": 0.0})


func update(delta: float, hold_banner: bool = false) -> void:  # hold_banner: the level-up waits (a vanquished page is up)
	for i in range(lines.size() - 1, -1, -1):
		lines[i]["left"] = float(lines[i]["left"]) - delta
		if float(lines[i]["left"]) <= 0.0:
			lines.remove_at(i)
	if not _banners.is_empty() and not hold_banner:  # one banner at a time, the next after it
		_banners[0]["age"] = float(_banners[0]["age"]) + delta
		if float(_banners[0]["age"]) >= BANNER_SECONDS:
			_banners.pop_front()


func busy() -> bool:
	return not lines.is_empty() or not _banners.is_empty()


# The loot list, right-aligned, its first line at `top_right`.
func draw_loot(c: CanvasItem, top_right: Vector2) -> void:
	var font := Style.font()
	var y := top_right.y
	for line: Dictionary in lines:
		var left := float(line["left"])
		var a := clampf(left / FADE, 0.0, 1.0) * clampf((LINE_SECONDS - left) / 0.15, 0.0, 1.0)
		var words := String(line["name"]) + ("  x%d" % int(line["count"]) if int(line["count"]) > 1 else "")
		var width := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		var row := Rect2(Vector2(top_right.x - width - 58.0, y), Vector2(width + 58.0, 32.0))
		c.draw_rect(row, Color(0.06, 0.045, 0.03, 0.62 * a))
		c.draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), Color(Style.GOLD, 0.8 * a))
		var tint: Color = line["color"]
		IconArt.draw(c, String(line["icon"]), Rect2(row.position + Vector2(10.0, 4.0), Vector2(24.0, 24.0)), Color(tint, a))
		c.draw_string_outline(font, row.position + Vector2(44.0, 23.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, 4, Color(0, 0, 0, 0.6 * a))
		c.draw_string(font, row.position + Vector2(44.0, 23.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(Style.PARCHMENT, a))
		y += 36.0


# The level-up banner, centred on `top_middle`.
func draw_banner(c: CanvasItem, top_middle: Vector2) -> void:
	if _banners.is_empty():
		return
	var b: Dictionary = _banners[0]
	var age := float(b["age"])
	var slide := clampf(age / 0.35, 0.0, 1.0)
	var a := clampf((BANNER_SECONDS - age) / 0.6, 0.0, 1.0)
	var opened: PackedStringArray = b["opened"]
	var w := 460.0
	var now_words := ("Now: " + ", ".join(opened)) if not opened.is_empty() else ""
	var now_lines := 0 if now_words == "" else mini(ceili(Style.font_italic().get_string_size(now_words, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x / (w - 140.0)), 3)
	var h := 112.0 + 20.0 * float(now_lines)
	var page := Rect2(Vector2(top_middle.x - w * 0.5, top_middle.y - (1.0 - ease(slide, 0.4)) * (h + 30.0)), Vector2(w, h))
	c.draw_rect(page.grow(3.0), Color(0, 0, 0, 0.4 * a))
	c.draw_rect(page, Color(PAPER, a))
	for k in 5:  # aged edges
		c.draw_rect(Rect2(page.position + Vector2(0, k * 2.0), Vector2(w, 2.0)), Color(0.7, 0.58, 0.38, 0.12 * a))
		c.draw_rect(Rect2(Vector2(page.position.x, page.end.y - 2.0 - k * 2.0), Vector2(w, 2.0)), Color(0.7, 0.58, 0.38, 0.12 * a))
	c.draw_rect(page.grow(-6.0), Color(RED, 0.55 * a), false, 1.2)  # a red ruled border, gold inside it
	c.draw_rect(page.grow(-9.0), Color(Style.GOLD, 0.7 * a), false, 1.0)
	var tint: Color = b["color"]
	var ring := page.position + Vector2(62.0, 56.0)  # the roundel: gold ring, the skill's colour, its icon
	c.draw_circle(ring, 38.0, Color(0.82, 0.62, 0.22, a))
	c.draw_circle(ring, 33.0, Color(INK, a))
	c.draw_circle(ring, 30.0, Color(tint.darkened(0.45), a))
	for k in 12:  # little gold points round the ring, as an illuminator would
		var d := Vector2.from_angle(TAU * k / 12.0)
		c.draw_circle(ring + d * 41.5, 2.2, Color(0.82, 0.62, 0.22, a))
	IconArt.draw(c, String(b["icon"]), Rect2(ring - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), Color(tint.lightened(0.25), a))
	var text_x := page.position.x + 118.0
	var bl := Style.blackletter()
	c.draw_string(bl, Vector2(text_x, page.position.y + 50.0), String(b["name"]), HORIZONTAL_ALIGNMENT_LEFT, w - 130.0, 34, Color(RED, a))
	c.draw_string(Style.gothic(), Vector2(text_x, page.position.y + 84.0), "has risen to level %d" % int(b["level"]), HORIZONTAL_ALIGNMENT_LEFT, w - 130.0, 22, Color(INK, a))
	if now_lines > 0:  # what the level opens, wrapped (up to three lines)
		c.draw_multiline_string(Style.font_italic(), Vector2(text_x, page.position.y + 110.0), now_words, HORIZONTAL_ALIGNMENT_LEFT, w - 140.0, 16, 3, Color(0.35, 0.22, 0.08, a))
