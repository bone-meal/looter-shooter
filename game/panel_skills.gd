# Purpose: the Skills page of the fantasy window: one card per skill (its icon in a ring that fills towards the next
# level, the level itself large). Picking a skill shows on the right what it has unlocked and what comes next, as the
# icons of the things themselves with the level each needs.
# Dependencies: game/fantasy_panel.gd (the window and its helpers), core/skill_levels.gd through the world.
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")
const IconArt = preload("res://game/icon_art.gd")


static func draw(p: Variant, body: Rect2, side: Rect2) -> void:
	var skills: RefCounted = p.world.skills
	var ids: Array = skills.ids()
	var wide := (body.size.x - 20.0) / 3.0
	for i in ids.size():
		var id := String(ids[i])
		var about: Dictionary = p.world.skilling["skills"][id]
		var tint := Color(about["color"][0], about["color"][1], about["color"][2])
		var card := Rect2(body.position.x + float(i % 3) * (wide + 10.0), body.position.y + floorf(float(i) / 3.0) * 156.0, wide, 146.0)
		var over: bool = p.hot(card, Callable(p, "pick").bind(id))
		var chosen := String(p.picked) == id
		p.draw_rect(card, Color(0.4, 0.31, 0.15, 0.4) if chosen else Color(0, 0, 0, 0.3))
		p.draw_rect(card, Style.GOLD if chosen else (Style.PARCHMENT if over else Style.GOLD_DIM), false, 2.0 if chosen else 1.0)
		var middle := card.position + Vector2(56.0, 62.0)
		p.draw_circle(middle, 40.0, Style.INK)
		p.draw_arc(middle, 40.0, 0.0, TAU, 40, Style.GOLD_DIM, 1.0, true)
		var share := float(skills.progress(id))
		if share > 0.0:
			p.draw_arc(middle, 40.0, -PI * 0.5, -PI * 0.5 + TAU * share, 40, tint, 4.0, true)
		IconArt.draw(p, String(about["icon"]), Rect2(middle - Vector2(25.0, 25.0), Vector2(50.0, 50.0)), tint)
		Style.text(p, card.position + Vector2(108.0, 72.0), str(int(skills.level(id))), 40, Style.PARCHMENT)
		Style.text(p, card.position + Vector2(0.0, 130.0), String(about["name"]), 16, tint.lerp(Style.PARCHMENT, 0.5), HORIZONTAL_ALIGNMENT_CENTER, wide)
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
	Style.paragraph(p, Vector2(side.position.x + 16.0, top + 12.0), String(about["about"]), 13, Style.PARCHMENT, side.size.x - 32.0, 4)
	top += 84.0
	if level < int(skills.max_level()):
		Style.bar(p, Rect2(side.position.x + 16.0, top, side.size.x - 32.0, 10.0), float(skills.progress(id)), tint)
		Style.text(p, Vector2(side.position.x + 16.0, top + 26.0), "%d / %d" % [int(skills.xp.get(id, 0)), int(skills.xp_for(level + 1))], 12, Style.FADED)
	top += 40.0
	# what the skill opens up: the thing gathered or made, with the level it needs
	var opens: Array = []  # [level, item, tip]
	for node_id: String in p.world.skilling["nodes"]:
		var node: Dictionary = p.world.skilling["nodes"][node_id]
		if String(node["skill"]) == id:
			opens.append([int(node["level"]), String(node["gives"]), String(node["name"])])
	for recipe: Dictionary in p.world.skilling["recipes"]:
		if String(recipe["skill"]) == id:
			var made := String((recipe["out"] as Dictionary).keys()[0])
			opens.append([int(recipe["level"]), made, String(p.world.bag.item_name(made))])
	opens.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	for i in mini(opens.size(), 30):
		var area := Rect2(side.position.x + 16.0 + float(i % 6) * 45.0, top + floorf(float(i) / 6.0) * 45.0, 41.0, 41.0)
		var open := level >= int(opens[i][0])
		p.cell(area, String(p.item_shape(opens[i][1])), p.item_color(opens[i][1]), "", Callable(), "%s  (level %d)" % [opens[i][2], int(opens[i][0])], 0, not open, "" if open else "lock")
		Style.text(p, Vector2(area.position.x + 2.0, area.end.y - 3.0), str(int(opens[i][0])), 11, Style.GOLD if open else Style.FADED)
