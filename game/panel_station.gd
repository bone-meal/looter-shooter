# Purpose: the page of the fantasy window shown at a station (a fire, a forge, a workbench, a cauldron): every recipe
# of that station as a card of pictures: what goes in (with how many), an arrow, what comes out, and the skill level
# it needs. A recipe that cannot be made is faded. Picking one shows on the right what is still missing; clicking a
# picked card again, or the button, makes it.
# Dependencies: game/fantasy_panel.gd (the window and its helpers), game/fantasy_work.gd (recipes, cannot_make, make).
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")
const IconArt = preload("res://game/icon_art.gd")

const ROW := 62.0


static func draw(p: Variant, body: Rect2, side: Rect2) -> void:
	var recipes: Array = p.work.call("recipes", String(p.station))
	var wide := (body.size.x - 16.0) * 0.5
	var chosen := {}
	for i in recipes.size():
		var recipe: Dictionary = recipes[i]
		var id := String(recipe["id"])
		if id == String(p.picked):
			chosen = recipe
		var card := Rect2(body.position.x + float(i % 2) * (wide + 8.0), body.position.y - float(p.scroll) + floorf(float(i) / 2.0) * (ROW + 6.0), wide, ROW)
		if not bool(p.shows(body, card.position.y, ROW)):
			continue
		var blocked := String(p.work.call("cannot_make", recipe)) != ""
		var over: bool = p.hot(card, _click.bind(p, recipe))
		var picked := id == String(p.picked)
		p.draw_rect(card, Color(0.4, 0.31, 0.15, 0.4) if picked else Color(0, 0, 0, 0.3))
		p.draw_rect(card, Style.GOLD if picked else (Style.PARCHMENT if over else Style.GOLD_DIM), false, 2.0 if picked else 1.0)
		var x := card.position.x + 8.0
		for item: String in recipe["in"]:
			p.item_cell(Rect2(x, card.position.y + 10.0, 42.0, 42.0), item, "", Callable(), int(recipe["in"][item]), int(p.world.bag.count(item)) < int(recipe["in"][item]))
			x += 46.0
		IconArt.draw(p, "arrow", Rect2(x + 2.0, card.position.y + 20.0, 22.0, 22.0), Style.GOLD, 0.35 if blocked else 1.0)
		x += 30.0
		for item: String in recipe["out"]:
			p.item_cell(Rect2(x, card.position.y + 8.0, 46.0, 46.0), item, "", Callable(), int(recipe["out"][item]), blocked)
			x += 50.0
		var skill: Dictionary = p.world.skilling["skills"][String(recipe["skill"])]
		var enough := int(p.world.skills.level(String(recipe["skill"]))) >= int(recipe["level"])
		IconArt.draw(p, String(skill["icon"]) if enough else "lock", Rect2(card.end.x - 30.0, card.position.y + 8.0, 22.0, 22.0), Color(skill["color"][0], skill["color"][1], skill["color"][2]))
		Style.text(p, Vector2(card.end.x - 44.0, card.end.y - 10.0), str(int(recipe["level"])), 13, Style.PARCHMENT if enough else Color(0.9, 0.45, 0.4), HORIZONTAL_ALIGNMENT_RIGHT, 36.0)
	p.content(body, body.position.y - float(p.scroll) + ceilf(float(recipes.size()) / 2.0) * (ROW + 6.0))
	_card(p, side, chosen)


static func _card(p: Variant, side: Rect2, recipe: Dictionary) -> void:
	if recipe.is_empty():
		Style.paragraph(p, side.position + Vector2(16.0, 34.0), "Pick something to make. Click it again to make it.", 14, Style.FADED, side.size.x - 32.0, 3)
		return
	var made := String((recipe["out"] as Dictionary).keys()[0])
	var skill := String(recipe["skill"])
	var top: float = p.card_head(side, String(p.item_shape(made)), p.item_color(made), String(p.world.bag.item_name(made)), "You have %d" % int(p.world.bag.count(made)))
	for item: String in recipe["in"]:
		var have := int(p.world.bag.count(item))
		var need := int(recipe["in"][item])
		top = p.card_row(side, top, String(p.item_shape(item)), p.item_color(item), "%s   %d / %d" % [p.world.bag.item_name(item), have, need], Style.PARCHMENT if have >= need else Color(0.9, 0.45, 0.4))
	var about: Dictionary = p.world.skilling["skills"][skill]
	var enough := int(p.world.skills.level(skill)) >= int(recipe["level"])
	top = p.card_row(side, top + 6.0, String(about["icon"]), Color(about["color"][0], about["color"][1], about["color"][2]), "%s level %d   (+%d xp)" % [about["name"], int(recipe["level"]), int(recipe["xp"])], Style.PARCHMENT if enough else Color(0.9, 0.45, 0.4))
	if String(p.work.call("cannot_make", recipe)) == "":
		p.card_button(side, String(p.world.skilling["stations"][String(p.station)]["icon"]), "Make", _make.bind(p, recipe))


static func _click(p: Variant, recipe: Dictionary) -> void:
	if String(p.picked) == String(recipe["id"]):
		_make(p, recipe)
	else:
		p.pick(String(recipe["id"]))


static func _make(p: Variant, recipe: Dictionary) -> void:
	p.note = String(p.work.call("make", recipe))
