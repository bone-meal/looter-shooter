# Purpose: the Spells page of the fantasy window, almost without words: how many elements a spell may hold now (a row
# of sockets), what the first element does to the spell's shape, what each mix of elements is made of (the signs and
# the substance's own colour), the long spells that have been taught, and the spells cast so far, all as element signs.
# Dependencies: game/fantasy_panel.gd (the window and its helpers), core/spell_book.gd and core/quest_log.gd through the world.
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")


static func draw(p: Variant, body: Rect2, side: Rect2) -> void:
	var book: Dictionary = p.world.spells.data
	var top: float = body.position.y - float(p.scroll)
	var hint := ""
	# how many elements fit in one spell
	top = p.heading(body, top, "star", "Elements in one spell: %d" % int(p.world.slots()))
	if bool(p.shows(body, top, 26.0)):
		for i in int(book["max_slots"]):
			var middle := Vector2(body.position.x + 13.0 + float(i) * 28.0, top + 12.0)
			if i < int(p.world.slots()):
				p.draw_circle(middle, 10.0, Style.GOLD)
			p.draw_arc(middle, 10.0, 0.0, TAU, 20, Style.GOLD_DIM, 1.0, true)
	top += 36.0
	# the first element decides the shape
	top = p.heading(body, top, "arrow", "The first element shapes the spell")
	var forms: Dictionary = book["forms"]
	var wide := (body.size.x - 8.0 - float(forms.size() - 1) * 8.0) / float(forms.size())
	var n := 0
	for letter: String in forms:
		var card := Rect2(body.position.x + float(n) * (wide + 8.0), top, wide, 44.0)
		if bool(p.shows(body, top, 44.0)):
			p.draw_rect(card, Color(0, 0, 0, 0.3))
			if card.has_point(p.mouse):
				hint = "%s first: %s. %s" % [book["elements"][letter]["name"], forms[letter]["name"], forms[letter]["desc"]]
				p.draw_rect(card, Style.PARCHMENT, false, 1.0)
			p.signs(card.position + Vector2(6.0, 22.0), letter, 15.0)
			Style.text(p, card.position + Vector2(44.0, 28.0), String(forms[letter]["name"]), 15, Style.PARCHMENT, HORIZONTAL_ALIGNMENT_LEFT, wide - 48.0)
		n += 1
	top += 56.0
	# the mix decides what it is made of
	top = p.heading(body, top, "pot", "The mix decides what it is made of")
	var mixes: Dictionary = book["substances"]
	var keys: Array = mixes.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return a.length() < b.length() if a.length() != b.length() else a < b)
	var per_row := 3
	var mix_wide := (body.size.x - 8.0 - float(per_row - 1) * 8.0) / float(per_row)
	for i in keys.size():
		var key := String(keys[i])
		var row_top := top + floorf(float(i) / float(per_row)) * 40.0
		if bool(p.shows(body, row_top, 36.0)):
			var card := Rect2(body.position.x + float(i % per_row) * (mix_wide + 8.0), row_top, mix_wide, 34.0)
			var c: Array = mixes[key]["color"]
			p.draw_rect(card, Color(0, 0, 0, 0.3))
			p.draw_rect(Rect2(card.position, Vector2(4.0, card.size.y)), Color(c[0], c[1], c[2]))
			var used: float = p.signs(card.position + Vector2(10.0, 17.0), key, 10.0)
			Style.text(p, card.position + Vector2(14.0 + used, 23.0), String(mixes[key]["name"]), 14, Color(c[0], c[1], c[2]).lerp(Style.PARCHMENT, 0.4), HORIZONTAL_ALIGNMENT_LEFT, mix_wide - used - 18.0)
	top += ceilf(float(keys.size()) / float(per_row)) * 40.0 + 10.0
	# long spells that someone has taught
	var taught: Array = p.world.quests.secrets()
	if not taught.is_empty():
		top = p.heading(body, top, "scroll", "Long spells you were taught (exact order)")
		for id: String in taught:
			var secret: Dictionary = p.world.spells.secret_for_id(id)
			if bool(p.shows(body, top, 40.0)):
				var card := Rect2(body.position.x, top, body.size.x - 8.0, 36.0)
				p.draw_rect(card, Color(0, 0, 0, 0.3))
				if card.has_point(p.mouse):
					hint = "%s. %s" % [secret["name"], secret["desc"]]
					p.draw_rect(card, Style.PARCHMENT, false, 1.0)
				Style.text(p, card.position + Vector2(10.0, 24.0), String(secret["name"]), 15, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT, 170.0)
				p.signs(card.position + Vector2(190.0, 18.0), String(secret["sequence"]), 10.0)
			top += 42.0
	# what has been cast so far
	if not (p.found as Dictionary).is_empty():
		top = p.heading(body, top + 4.0, "spark", "Cast so far")
		for cast_name: String in p.found:
			if bool(p.shows(body, top, 32.0)):
				var used: float = p.signs(Vector2(body.position.x + 4.0, top + 14.0), String(p.found[cast_name]), 10.0)
				Style.text(p, Vector2(body.position.x + 14.0 + used, top + 20.0), cast_name, 14, Style.PARCHMENT)
			top += 32.0
	p.content(body, top)
	# the card on the right: how casting works, in three short lines, and whatever the mouse is over
	var line := side.position.y + 30.0
	for step: Array in [["1", "Hold the cast key with the staff out."], ["2", "Add elements. The first one shapes the spell, all of them together decide what it is made of, and more of them make it larger."], ["3", "Let go."]]:
		Style.text(p, Vector2(side.position.x + 16.0, line), String(step[0]), 22, Style.GOLD)
		Style.paragraph(p, Vector2(side.position.x + 42.0, line - 4.0), String(step[1]), 13, Style.PARCHMENT, side.size.x - 58.0, 5)
		line += 34.0 if String(step[0]) != "2" else 96.0
	var sizes := PackedStringArray()
	for tier: Dictionary in book["tiers"]:
		if String(tier.get("name", "")) != "":
			sizes.append("%d: %s" % [int(tier["count"]), tier["name"]])
	Style.paragraph(p, Vector2(side.position.x + 16.0, line + 14.0), "Sizes   " + "   ".join(sizes), 12, Style.FADED, side.size.x - 32.0, 4)
	if hint != "":
		Style.paragraph(p, Vector2(side.position.x + 16.0, side.end.y - 110.0), hint, 14, Style.GOLD, side.size.x - 32.0, 6)
