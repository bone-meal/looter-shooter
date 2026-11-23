# Purpose: the COACH page of the fantasy window (polish1 E5, item 126), opened by talking to a coachman at a walled
# town's coach house: his line, then every other walled town as a row (its name, its country, the distance and the
# fare in GIL with the gil coin); towns of countries not visited yet are faded with "not visited yet". Picking one
# shows it on the right with the gil you have and one button: ride there. Real fantasy-window UI.
# Dependencies: game/fantasy_panel.gd (the window and its helpers), game/fantasy_world.gd (coach_towns, coach_here,
# coach_fare, coach_ride, gil), game/currency_art.gd (the gil coin), data/fantasy/coaches.json.
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")
const CurrencyArt = preload("res://game/currency_art.gd")

const ROW := 58.0


static func draw(p: Variant, body: Rect2, side: Rect2) -> void:
	var world: Node = p.world
	var here: Dictionary = world.call("coach_here")
	var lines: Array = world.data["coaches"].get("lines", [])
	var top := body.position.y - float(p.scroll)
	if not lines.is_empty():
		var said := String(lines[absi(String(here.get("id", "")).hash()) % lines.size()])
		Style.paragraph(p, Vector2(body.position.x + 4.0, top + 22.0), "\"%s\"" % said, 16, Style.PARCHMENT, body.size.x - 8.0, 2)
	top += 56.0
	var chosen := {}
	for town: Dictionary in world.call("coach_towns"):
		if String(town["id"]) == String(here.get("id", "")):
			continue
		var row := Rect2(body.position.x, top, body.size.x, ROW)
		top += ROW + 6.0
		if not bool(p.shows(body, row.position.y, ROW)):
			continue
		var open := bool(town["visited"])
		var picked := String(town["id"]) == String(p.picked)
		if picked:
			chosen = town
		var over: bool = p.hot(row, func() -> void: p.picked = String(town["id"]))
		p.draw_rect(row, Color(0.4, 0.31, 0.15, 0.4) if picked else Color(0, 0, 0, 0.3))
		p.draw_rect(row, Style.GOLD if picked else (Style.PARCHMENT if over else Style.GOLD_DIM), false, 2.0 if picked else 1.0)
		var tone := Style.PARCHMENT if open else Style.FADED
		Style.text(p, row.position + Vector2(14.0, 25.0), String(town["name"]), 19, tone)
		Style.text(p, row.position + Vector2(14.0, 46.0), "%s   %.1f km" % [String(town["region_name"]), float(town["km"])] if open else "%s   not visited yet" % String(town["region_name"]), 13, Style.FADED)
		if open:
			CurrencyArt.draw(p, "gil", Vector2(row.end.x - 120.0, row.position.y + ROW * 0.5), 11.0)
			Style.text(p, Vector2(row.end.x - 104.0, row.position.y + ROW * 0.5 + 6.0), "%d gil" % int(town["fare"]), 17, Style.GOLD)
	p.content(body, top)
	_card(p, side, chosen)


static func _card(p: Variant, side: Rect2, town: Dictionary) -> void:
	var gil := int((p.world.get("gil") as Callable).call())
	CurrencyArt.draw(p, "gil", side.position + Vector2(28.0, side.size.y - 26.0), 11.0)
	Style.text(p, side.position + Vector2(46.0, side.size.y - 20.0), "You have %d gil" % gil, 15, Style.PARCHMENT)
	if town.is_empty():
		Style.paragraph(p, side.position + Vector2(16.0, 34.0), "Pick a town to ride to. Only countries you have already been to are on the coach's roads.", 14, Style.FADED, side.size.x - 32.0, 4)
		return
	var top: float = p.card_head(side, "map", Style.GOLD, String(town["name"]), String(town["region_name"]))
	if not bool(town["visited"]):
		top = p.card_row(side, top, "lock", Style.FADED, "Go there once on foot first", Style.FADED)
		return
	top = p.card_row(side, top, "map", Style.GOLD, "%.1f km by road" % float(town["km"]))
	top = p.card_row(side, top, "coin", Style.GOLD, "Fare: %d gil" % int(town["fare"]), Style.PARCHMENT if gil >= int(town["fare"]) else Color(0.9, 0.45, 0.4))
	var id := String(town["id"])
	p.card_button(side, "arrow", "Ride to %s" % String(town["name"]), func() -> void: p.note = String(p.world.call("coach_ride", id)))
