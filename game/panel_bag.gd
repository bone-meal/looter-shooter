# Purpose: the Bag page of the fantasy window: what is in use (staff, robe, axe, pickaxe, rod) and everything carried,
# sorted into gear, food and drink, materials and pigments, each thing as its icon with a count. Picking one shows what
# it does on the right, with one button to wear, eat, drink or burn it.
# Dependencies: game/fantasy_panel.gd (the window and its helpers), core/fantasy_bag.gd through the world.
extends RefCounted

const Style = preload("res://game/fantasy_style.gd")

const SIZE := 54.0
const GAP := 6.0
const GROUPS := [["Gear", "shield", ["staff", "robe", "tool"]], ["Food and drink", "bread", ["food", "potion"]], ["Materials", "log", ["material"]], ["Pigments", "pigment", ["pigment"]]]
# what an item's numbers mean: [key in the item's data, icon, words]
const FACTS := [["power", "spark", "spell power x%s"], ["slots", "star", "+%s elements in a spell"], ["mana", "drop", "+%s mana"], ["hp", "heart", "+%s health"],
	["armor", "shield", "takes off %s of each hit"], ["regen", "drop", "+%s mana every second"], ["tier", "star", "tier %s"], ["heal", "heart", "heals %s"]]
const KIND_WORDS := {"staff": "Staff", "robe": "Robe", "tool": "Tool", "food": "Food", "potion": "Potion", "material": "Material", "pigment": "Pigment"}


static func draw(p: Variant, body: Rect2, side: Rect2) -> void:
	var bag: RefCounted = p.world.bag
	var top: float = body.position.y - float(p.scroll)
	top = p.heading(body, top, "check", "In use")
	var slots: Array = bag.get("SLOTS")
	for i in slots.size():
		var worn := String(bag.equipped.get(slots[i], ""))
		var area := Rect2(body.position.x + float(i) * (SIZE + GAP), top, SIZE, SIZE)
		if not bool(p.shows(body, top, SIZE)):
			continue
		if worn == "":
			p.cell(area, String(slots[i]), Style.PARCHMENT, "", Callable(), "Nothing in use", 0, true)
		else:
			p.item_cell(area, worn, worn, Callable(p, "pick").bind(worn))
	top += SIZE + 14.0
	var per_row := int(floorf((body.size.x - 6.0) / (SIZE + GAP)))
	for group: Array in GROUPS:
		var ids: Array = []
		for id: String in bag.items:
			if String(bag.def(id)["kind"]) in (group[2] as Array) and int(bag.count(id)) > 0:
				ids.append(id)
		if ids.is_empty():
			continue
		top = p.heading(body, top, String(group[1]), String(group[0]))
		for i in ids.size():
			var area := Rect2(body.position.x + float(i % per_row) * (SIZE + GAP), top + floorf(float(i) / float(per_row)) * (SIZE + GAP), SIZE, SIZE)
			if bool(p.shows(body, area.position.y, SIZE)):
				var in_use := String(bag.equipped.get(String(bag.slot_of(ids[i])), "")) == String(ids[i])
				p.item_cell(area, String(ids[i]), String(ids[i]), Callable(p, "pick").bind(String(ids[i])), int(bag.count(ids[i])), false, "check" if in_use else "")
		top += ceilf(float(ids.size()) / float(per_row)) * (SIZE + GAP) + 10.0
	p.content(body, top)
	_card(p, side)


static func _card(p: Variant, side: Rect2) -> void:
	var bag: RefCounted = p.world.bag
	var item := String(p.picked)
	if item == "" or int(bag.count(item)) <= 0:
		Style.paragraph(p, side.position + Vector2(16.0, 34.0), "Pick something to see what it does.", 14, Style.FADED, side.size.x - 32.0, 3)
		return
	var def: Dictionary = bag.def(item)
	var kind := String(def["kind"])
	var top: float = p.card_head(side, String(p.item_shape(item)), p.item_color(item), String(def["name"]), "%s   x%d" % [KIND_WORDS.get(kind, kind.capitalize()), int(bag.count(item))])
	for fact: Array in FACTS:
		if def.has(fact[0]):
			top = p.card_row(side, top, String(fact[1]), Style.GOLD, String(fact[2]) % str(def[fact[0]]))
	var burns: bool = (p.world.skilling["fire"]["level"] as Dictionary).has(item)
	if kind in ["food", "potion"]:
		p.card_button(side, "heart", "Eat" if kind == "food" else "Drink", _use.bind(p, item))
	elif kind in ["staff", "robe", "tool"]:
		p.card_button(side, "check", "Use this one", _use.bind(p, item))
	elif burns:
		p.card_button(side, "flame", "Light a fire", _use.bind(p, item))


static func _use(p: Variant, item: String) -> void:
	p.note = String(p.world.use_item(item))
