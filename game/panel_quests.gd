# Purpose: the Quests page of the fantasy window, and the page shown when talking to someone. A quest is a card: an
# icon for what its current step asks (talk, defeat, bring, reach, cast ...), its title, the step in one line and one
# pip per step. Picking it shows the whole quest on the right; when talking, a button takes it.
# Dependencies: game/fantasy_panel.gd (the window and its helpers), core/quest_log.gd through the world.
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")
const IconArt = preload("res://game/icon_art.gd")

const STEP_SHAPES := {"talk": "talk", "cast": "spark", "kill": "sword", "have": "bag", "reach": "pin", "fire": "flame", "skill": "star"}
const ROW := 62.0


static func draw(p: Variant, body: Rect2, side: Rect2, talking: bool) -> void:
	var quests: RefCounted = p.world.quests
	var top: float = body.position.y - float(p.scroll)
	if talking:
		if bool(p.shows(body, top, 70.0)):
			Style.paragraph(p, Vector2(body.position.x + 4.0, top + 20.0), String(p.person.get("greet", "")), 15, Style.PARCHMENT, body.size.x - 16.0, 3)
		top += 78.0
		var who := String(p.person.get("id", ""))
		var any := false
		for id: String in quests.offers(who):
			top = _row(p, body, top, id, "exclaim")
			any = true
		for id: String in quests.active:
			if String(quests.quest(id)["giver"]) == who:
				top = _row(p, body, top, id, "")
				any = true
		if not any and bool(p.shows(body, top, 30.0)):
			Style.text(p, Vector2(body.position.x + 4.0, top + 20.0), "Nothing more to ask of you for now.", 14, Style.FADED)
	else:
		top = p.heading(body, top, "scroll", "Chapter %d of 8" % mini(int(quests.chapter()), 8))
		for id: String in quests.active:
			top = _row(p, body, top, id, "")
		if (quests.active as Dictionary).is_empty() and bool(p.shows(body, top, 60.0)):
			IconArt.draw(p, "exclaim", Rect2(body.position.x + 4.0, top + 4.0, 30.0, 30.0), Style.GOLD)
			Style.paragraph(p, Vector2(body.position.x + 44.0, top + 20.0), String(p.world.first_hint()) if (quests.done as Array).is_empty() else "Look for someone with a ! above their head.", 15, Style.PARCHMENT, body.size.x - 60.0, 2)
			top += 60.0
		if not (quests.done as Array).is_empty():
			top = p.heading(body, top + 6.0, "check", "Done")
			for id: String in quests.done:
				if bool(p.shows(body, top, 28.0)):
					var line := Rect2(body.position.x, top, body.size.x - 8.0, 26.0)
					var over: bool = p.hot(line, Callable(p, "pick").bind(id))
					if over or String(p.picked) == id:
						p.draw_rect(line, Color(1, 1, 1, 0.06))
					IconArt.draw(p, "check", Rect2(line.position + Vector2(4.0, 3.0), Vector2(20.0, 20.0)), Style.GOLD_DIM)
					Style.text(p, line.position + Vector2(32.0, 19.0), String(quests.quest(id)["name"]), 14, Style.FADED)
				top += 28.0
	p.content(body, top)
	_card(p, side, talking)


# One quest as a card. `lead` = an icon to show instead of the step's own (a quest on offer).
static func _row(p: Variant, body: Rect2, top: float, id: String, lead: String) -> float:
	if not bool(p.shows(body, top, ROW)):
		return top + ROW + 6.0
	var quests: RefCounted = p.world.quests
	var quest: Dictionary = quests.quest(id)
	var card := Rect2(body.position.x, top, body.size.x - 8.0, ROW)
	var over: bool = p.hot(card, Callable(p, "pick").bind(id))
	var chosen := String(p.picked) == id
	p.draw_rect(card, Color(0.4, 0.31, 0.15, 0.4) if chosen else Color(0, 0, 0, 0.3))
	p.draw_rect(card, Style.GOLD if chosen else (Style.PARCHMENT if over else Style.GOLD_DIM), false, 2.0 if chosen else 1.0)
	var steps: Array = quest["steps"]
	var at := int(quests.active[id]["step"]) if (quests.active as Dictionary).has(id) else -1
	var shape := lead if lead != "" else String(STEP_SHAPES.get(String(steps[clampi(at, 0, steps.size() - 1)]["type"]), "dots"))
	p.draw_circle(card.position + Vector2(31.0, 31.0), 24.0, Style.INK)
	IconArt.draw(p, shape, Rect2(card.position + Vector2(13.0, 13.0), Vector2(36.0, 36.0)), Style.GOLD)
	Style.text(p, card.position + Vector2(66.0, 25.0), String(quest["name"]), 17, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 76.0 - float(steps.size()) * 12.0)
	var under := String(quests.step_text(id)) if at >= 0 else String(quest["text"])
	Style.text(p, card.position + Vector2(66.0, 47.0), under, 13, Style.PARCHMENT, HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 76.0)
	for i in steps.size():  # one pip per step: done, now, still to come
		var pip := Rect2(card.end.x - 14.0 - float(steps.size() - i) * 12.0, card.position.y + 12.0, 8.0, 8.0)
		if i < at:
			p.draw_rect(pip, Style.GOLD)
		else:
			p.draw_rect(pip, Style.PARCHMENT if i == at else Style.GOLD_DIM, false, 1.0)
	return top + ROW + 6.0


static func _card(p: Variant, side: Rect2, talking: bool) -> void:
	var quests: RefCounted = p.world.quests
	var id := String(p.picked)
	if id == "" or (quests.quest(id) as Dictionary).is_empty():
		Style.paragraph(p, side.position + Vector2(16.0, 34.0), "Pick a quest to read it.", 14, Style.FADED, side.size.x - 32.0, 3)
		return
	var quest: Dictionary = quests.quest(id)
	Style.paragraph(p, side.position + Vector2(16.0, 32.0), String(quest["name"]), 19, Style.GOLD, side.size.x - 32.0, 2)
	Style.paragraph(p, side.position + Vector2(16.0, 84.0), String(quest["text"]), 13, Style.PARCHMENT, side.size.x - 32.0, 9)
	var top := side.position.y + 240.0
	if quest.has("level"):
		top = p.card_row(side, top, "spark", Style.GOLD, "Magic level %d advised" % int(quest["level"]), Style.FADED)
	var at := int(quests.active[id]["step"]) if (quests.active as Dictionary).has(id) else (999 if bool(quests.is_done(id)) else -1)
	var steps: Array = quest["steps"]
	for i in steps.size():
		if top > side.end.y - 90.0:
			break
		var shape := "check" if i < at else String(STEP_SHAPES.get(String(steps[i]["type"]), "dots"))
		top = p.card_row(side, top, shape, Style.GOLD if i <= at else Style.GOLD_DIM, String(steps[i]["text"]), Style.FADED if i < at else (Style.PARCHMENT if i == at else Style.FADED))
	if talking and bool(quests.can_start(id)):
		p.card_button(side, "scroll", "Take this quest", _take.bind(p, id))


static func _take(p: Variant, id: String) -> void:
	p.world.accept(id)
