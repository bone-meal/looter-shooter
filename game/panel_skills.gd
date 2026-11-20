# Purpose: the Skills page of the fantasy window: one card per skill (15, five to a row: its icon in a ring that fills
# towards the next level, the level under it). Picking a skill shows on the right its ten milestones (levels 5, 10 ...
# 50 of data/fantasy/skilling.json "unlocks": new things to gather or make, or perks), reached ones lit, the rest locked.
# Dependencies: game/fantasy_panel.gd (the window and its helpers), core/skill_levels.gd through the world.
extends RefCounted

const FantasyWork = preload("res://game/fantasy_work.gd")
const Style = preload("res://game/fantasy_style.gd")
const IconArt = preload("res://game/icon_art.gd")

const COLUMNS := 5


static func draw(p: Variant, body: Rect2, side: Rect2) -> void:
	var skills: RefCounted = p.world.skills
	var ids: Array = skills.ids()
	var wide := (body.size.x - 10.0 * float(COLUMNS - 1)) / float(COLUMNS)
	var tall := minf(156.0, (body.size.y - 20.0) / ceilf(float(ids.size()) / float(COLUMNS)))
	for i in ids.size():
		var id := String(ids[i])
		var about: Dictionary = p.world.skilling["skills"][id]
		var tint := Color(about["color"][0], about["color"][1], about["color"][2])
		var card := Rect2(body.position.x + float(i % COLUMNS) * (wide + 10.0), body.position.y + floorf(float(i) / float(COLUMNS)) * (tall + 6.0), wide, tall)
		var over: bool = p.hot(card, Callable(p, "pick").bind(id))
		var chosen := String(p.picked) == id
		p.draw_rect(card, Color(0.4, 0.31, 0.15, 0.4) if chosen else Color(0, 0, 0, 0.3))
		p.draw_rect(card, Style.GOLD if chosen else (Style.PARCHMENT if over else Style.GOLD_DIM), false, 2.0 if chosen else 1.0)
		var middle := card.position + Vector2(wide * 0.5, 46.0)
		p.draw_circle(middle, 32.0, Style.INK)
		p.draw_arc(middle, 32.0, 0.0, TAU, 40, Style.GOLD_DIM, 1.0, true)
		var share := float(skills.progress(id))
		if share > 0.0:
			p.draw_arc(middle, 32.0, -PI * 0.5, -PI * 0.5 + TAU * share, 40, tint, 4.0, true)
		IconArt.draw(p, String(about["icon"]), Rect2(middle - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), tint)
		Style.text(p, card.position + Vector2(0.0, 108.0), str(int(skills.level(id))), 26, Style.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, wide)
		Style.text(p, card.position + Vector2(0.0, tall - 10.0), String(about["name"]), 14, tint.lerp(Style.PARCHMENT, 0.5), HORIZONTAL_ALIGNMENT_CENTER, wide)
	_card(p, side)


static func _card(p: Variant, side: Rect2) -> void:
	var skills: RefCounted = p.world.skills
	var id := String(p.picked)
	if id == "" or not (p.world.skilling["skills"] as Dictionary).has(id):
		Style.paragraph(p, side.position + Vector2(16.0, 34.0), "Pick a skill to see what it unlocks.", 14, Style.FADED, side.size.x - 32.0, 3)
		return
	var about: Dictionary = p.world.skilling["skills"][id]
	var tint := Color(about["color"][0], about["color"][1], about["color"][2])
	var level := int(skills.level(id))
	var top: float = p.card_head(side, String(about["icon"]), tint, String(about["name"]), "Level %d of %d" % [level, int(skills.max_level())])
	Style.paragraph(p, Vector2(side.position.x + 16.0, top + 10.0), String(about["about"]), 13, Style.PARCHMENT, side.size.x - 32.0, 3)
	top += 64.0
	if level < int(skills.max_level()):
		Style.bar(p, Rect2(side.position.x + 16.0, top, side.size.x - 32.0, 8.0), float(skills.progress(id)), tint)
		Style.text(p, Vector2(side.position.x + 16.0, top + 22.0), "%d / %d" % [int(skills.xp.get(id, 0)), int(skills.xp_for(level + 1))], 12, Style.FADED)
	top += 34.0
	if (p.world.skilling.get("success", {}) as Dictionary).has(id):  # (polish1 item 121) how often each node finds something now
		var parts: PackedStringArray = []
		for nid: String in p.world.skilling["nodes"]:
			var nd: Dictionary = p.world.skilling["nodes"][nid]
			if String(nd.get("skill", "")) == id and level >= int(nd["level"]):
				var odds := FantasyWork.success(p.world.skilling, id, level, int(nd["level"]))
				parts.append("%s %d%%%s" % [String(p.world.bag.item_name(String(nd["gives"]))) if nd.has("gives") else nid, mini(roundi(odds * 100.0), 100), (" +%d%% bonus" % roundi((odds - 1.0) * 100.0)) if odds > 1.0 else ""])
		Style.paragraph(p, Vector2(side.position.x + 16.0, top + 4.0), "Success: " + ",  ".join(parts), 12, Style.PARCHMENT, side.size.x - 32.0, 2)
		top += 34.0
	var steps: Array = p.world.skilling.get("unlocks", {}).get(id, [])
	if steps.is_empty():
		Style.paragraph(p, Vector2(side.position.x + 16.0, top + 16.0), "Its milestones arrive later in this update.", 13, Style.FADED, side.size.x - 32.0, 2)
		return
	var row := minf(27.0, (side.end.y - top - 8.0) / float(steps.size()))
	for step: Dictionary in steps:
		var open := level >= int(step["level"])
		var area := Rect2(side.position.x + 10.0, top, side.size.x - 20.0, row - 3.0)
		var over: bool = p.hot(area, Callable(), "%s (level %d): %s" % [String(step["name"]), int(step["level"]), String(step.get("about", ""))])
		p.draw_rect(area, Color(tint.r, tint.g, tint.b, 0.16) if open else Color(0, 0, 0, 0.22))
		if over:
			p.draw_rect(area, Style.PARCHMENT, false, 1.0)
		var shape := _shape(p, step, String(about["icon"]))
		IconArt.draw(p, shape, Rect2(area.position + Vector2(4.0, 2.0), Vector2(row - 7.0, row - 7.0)), tint if open else Style.FADED, 1.0 if open else 0.5)
		Style.text(p, Vector2(area.position.x + row + 2.0, area.position.y + row * 0.62), str(int(step["level"])), 13, Style.GOLD if open else Style.FADED)
		Style.text(p, Vector2(area.position.x + row + 30.0, area.position.y + row * 0.62), String(step["name"]), 13, Style.PARCHMENT if open else Style.FADED, HORIZONTAL_ALIGNMENT_LEFT, area.size.x - row - 54.0)
		if not open:
			IconArt.draw(p, "lock", Rect2(area.end.x - 20.0, area.position.y + 3.0, row - 9.0, row - 9.0), Style.FADED, 0.6)
		top += row


# A milestone's icon: the first thing a content step opens (what it gives), a star for a perk, the skill's own icon
# for something still to come.
static func _shape(p: Variant, step: Dictionary, fallback: String) -> String:
	if String(step["kind"]) != "content":
		return "star"
	var skilling: Dictionary = p.world.skilling
	for id: String in step.get("ids", []):
		if (skilling["nodes"] as Dictionary).has(id):
			return String(p.item_shape(String(skilling["nodes"][id]["gives"])))
		for recipe: Dictionary in skilling["recipes"]:
			if String(recipe["id"]) == id:
				return String(p.item_shape(String((recipe["out"] as Dictionary).keys()[0])))
		if (skilling["fire"]["level"] as Dictionary).has(id):
			return "flame"
		if id == "slot":
			return "spark"
	return fallback  # a sea system still to come
