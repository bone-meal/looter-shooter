# Purpose: the VANQUISHED page (polish1 E4, item 131): when a great creature falls, a large manuscript page unrolls
# under the compass: "Vanquished" in red blackletter with an illuminated first letter, the creature's name in Grenze
# Gotisch, a gold rule, then what THIS player won (trophy, relic, ghost pieces) in italics. A phantom's end is the same
# page in cold blue ink: "The echo fades". 7 seconds, one page at a time; the skill banner waits under it.
# Pure drawing over any CanvasItem (game/fantasy_hud.gd).
# Dependencies: game/fantasy_style.gd (fonts, colours).
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")

const SECONDS := 7.0
const RED := Color(0.62, 0.1, 0.07)
const BLUE_INK := Color(0.12, 0.3, 0.55)
const PAPER := Color(0.93, 0.86, 0.67)
const INK := Color(0.2, 0.12, 0.06)

var _pages: Array = []  # {"name", "phantom", "lines", "age"}


func add(creature: String, phantom: bool, lines: Array) -> void:
	_pages.append({"name": creature, "phantom": phantom, "lines": lines, "age": 0.0})


func update(delta: float) -> void:
	if not _pages.is_empty():
		_pages[0]["age"] = float(_pages[0]["age"]) + delta
		if float(_pages[0]["age"]) >= SECONDS:
			_pages.pop_front()


func busy() -> bool:
	return not _pages.is_empty()


func draw(c: CanvasItem, top_middle: Vector2) -> void:
	if _pages.is_empty():
		return
	var p: Dictionary = _pages[0]
	var age := float(p["age"])
	var open := ease(clampf(age / 0.6, 0.0, 1.0), 0.35)  # unrolls downward
	var a := clampf((SECONDS - age) / 0.8, 0.0, 1.0)
	var phantom := bool(p["phantom"])
	var ink := BLUE_INK if phantom else RED
	var lines: Array = p["lines"]
	var w := 620.0
	var h := 150.0 + 24.0 * float(lines.size())
	var page := Rect2(Vector2(top_middle.x - w * 0.5, top_middle.y), Vector2(w, h * open))
	c.draw_rect(page.grow(4.0), Color(0, 0, 0, 0.45 * a))
	c.draw_rect(page, Color(PAPER.lerp(Color(0.8, 0.88, 0.95), 0.35 if phantom else 0.0), a))
	for k in 6:  # aged edges
		c.draw_rect(Rect2(page.position + Vector2(0, k * 2.0), Vector2(w, 2.0)), Color(0.7, 0.58, 0.38, 0.12 * a))
	c.draw_rect(page.grow(-7.0), Color(ink, 0.6 * a), false, 1.4)
	c.draw_rect(page.grow(-11.0), Color(Style.GOLD, 0.75 * a), false, 1.0)
	for x: float in [page.position.x - 8.0, page.end.x - 8.0]:  # the rolls at both ends of the top
		c.draw_rect(Rect2(Vector2(x, page.position.y - 6.0), Vector2(16.0, 12.0)), Color(0.45, 0.3, 0.16, a))
	if open < 0.98:
		return
	var bl := Style.blackletter()
	var head := "The echo fades" if phantom else "Vanquished"
	var cap := Rect2(Vector2(page.position.x + 30.0, page.position.y + 18.0), Vector2(56.0, 56.0))  # an illuminated first letter
	c.draw_rect(cap, Color(Style.GOLD, a))
	c.draw_rect(cap.grow(-3.0), Color(ink, a))
	c.draw_string(bl, Vector2(cap.position.x, cap.end.y - 10.0), head.substr(0, 1), HORIZONTAL_ALIGNMENT_CENTER, cap.size.x, 48, Color(Style.GOLD, a))
	c.draw_string(bl, Vector2(cap.end.x + 6.0, page.position.y + 64.0), head.substr(1), HORIZONTAL_ALIGNMENT_LEFT, w - 140.0, 44, Color(ink, a))
	c.draw_string(Style.gothic(), Vector2(page.position.x, page.position.y + 106.0), String(p["name"]), HORIZONTAL_ALIGNMENT_CENTER, w, 28, Color(INK, a))
	var rule_y := page.position.y + 122.0
	c.draw_line(Vector2(page.position.x + 90.0, rule_y), Vector2(page.end.x - 90.0, rule_y), Color(Style.GOLD, 0.8 * a), 1.5)
	var y := rule_y + 26.0
	for line: Variant in lines:
		c.draw_string(Style.font_italic(), Vector2(page.position.x + 30.0, y), String(line), HORIZONTAL_ALIGNMENT_CENTER, w - 60.0, 17, Color(0.35, 0.22, 0.08, a))
		y += 24.0
