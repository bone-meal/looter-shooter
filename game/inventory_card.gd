# Purpose: the inventory's docked item card (locked 2026-11-14 layout, diary/DECISIONS_SEA.md): the right-hand panel
# showing the chosen gun (rarity band, name, level, big icon, maker, stats compared with the gun in hand, parts,
# combos, buffs, traits, Q / E skills) or item (icon, kind, stats, flavor), with its action buttons at the foot.
# Dependencies: game/ui_skin.gd, game/item_icons.gd, game/tier_style.gd, core/gun_stats.gd, core/skill_state.gd, core/armour_stats.gd (rolled armour).
extends RefCounted

const UiSkin = preload("res://game/ui_skin.gd")
const IconArt = preload("res://game/icon_art.gd")
const ItemIcons = preload("res://game/item_icons.gd")
const TierStyle = preload("res://game/tier_style.gd")
const GunStats = preload("res://core/gun_stats.gd")
const SkillState = preload("res://core/skill_state.gd")
const ArmourStats = preload("res://core/armour_stats.gd")

const PAD := 22.0
const BUTTON_H := 40.0
const TRAIT_COLOUR := Color(1.0, 0.42, 0.3)
const BUFF_COLOUR := Color(1.0, 0.8, 0.4)
const COMBO_COLOUR := Color(0.6, 1.0, 0.7)
const SKILL_COLOUR := Color(0.5, 0.95, 1.0)
const SEA_COLOUR := Color(0.35, 0.9, 0.85)
const RED_TEXT := Color(1.0, 0.22, 0.18)


# Draws the card for `what` inside r and returns its buttons [[Rect2, action id]].
# what: {"gun": gun, "against": gun in hand or {}} | {"id": item id, "count": n} | {"note": [title, text]} | {}.
# actions: [[label, action id]] for the foot of the card.
static func draw(canvas: CanvasItem, font: Font, r: Rect2, what: Dictionary, gun_db: RefCounted, items: RefCounted, actions: Array, hovered_action: String, t: float) -> Array:
	UiSkin.panel(canvas, r)
	if what.is_empty():
		canvas.draw_string(font, Vector2(r.position.x, r.get_center().y), "Point at an item to see it here", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 16, UiSkin.TEXT_DIM)
		return []
	var foot := r.end.y - PAD - (BUTTON_H if not actions.is_empty() else 0.0)
	if what.has("gun"):
		_gun(canvas, font, r, foot, what["gun"], what.get("against", {}), gun_db, t)
	elif what.has("id") and not (what.get("arm", {}) as Dictionary).is_empty():
		_armour(canvas, font, r, foot, what, gun_db, items, t)
	elif what.has("id"):
		_item(canvas, font, r, foot, String(what["id"]), int(what.get("count", 1)), items)
	elif what.has("note"):
		var note: Array = what["note"]
		_band(canvas, font, r, Color(0.7, 0.75, 0.85), "KNIFE", "")
		canvas.draw_string(font, r.position + Vector2(PAD, 110), String(note[0]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2.0 * PAD, 26, UiSkin.TEXT)
		ItemIcons.draw(canvas, "knife", Rect2(r.position + Vector2(PAD, 130), Vector2(r.size.x - 2.0 * PAD, 150)), Color.WHITE)
		canvas.draw_multiline_string(font, r.position + Vector2(PAD, 320), String(note[1]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 2.0 * PAD, 15, -1, UiSkin.TEXT_DIM)
	var buttons: Array = []
	if not actions.is_empty():
		var w := (r.size.x - 2.0 * PAD - 10.0 * float(actions.size() - 1)) / float(actions.size())
		for i in actions.size():
			var b := Rect2(r.position.x + PAD + float(i) * (w + 10.0), foot, w, BUTTON_H)
			UiSkin.pill(canvas, font, b, String(actions[i][0]), false, String(actions[i][1]) == hovered_action, 16)
			buttons.append([b, String(actions[i][1])])
	return buttons


# The coloured band at the top: rarity word left, level right.
static func _band(canvas: CanvasItem, font: Font, r: Rect2, tint: Color, left: String, right: String) -> void:
	var band := Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2.0, 46.0))
	var a := Color(tint, 0.55)
	var b := Color(tint, 0.05)
	canvas.draw_polygon(PackedVector2Array([band.position, Vector2(band.end.x, band.position.y), band.end, Vector2(band.position.x, band.end.y)]), PackedColorArray([a, b, b, a]))
	canvas.draw_line(Vector2(band.position.x, band.end.y), band.end, Color(tint, 0.9), 2.0)
	canvas.draw_string(font, band.position + Vector2(PAD, 30), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiSkin.TEXT)
	if right != "":
		canvas.draw_string(font, Vector2(band.position.x, band.position.y + 30), right, HORIZONTAL_ALIGNMENT_RIGHT, band.size.x - PAD, 16, UiSkin.TEXT)


static func _gun(canvas: CanvasItem, font: Font, r: Rect2, foot: float, gun: Dictionary, against: Dictionary, db: RefCounted, t: float) -> void:
	var tier_id := String(gun["tier"])
	var tint := TierStyle.color(db, tier_id, t)
	var stats := GunStats.final_stats(db, gun)
	var other: Dictionary = {} if against.is_empty() else GunStats.final_stats(db, against)
	_band(canvas, font, r, tint, String(db.tier(tier_id)["name"]).to_upper(), "Lv %d" % int(stats["lvl"]))
	var x := r.position.x + PAD
	var w := r.size.x - 2.0 * PAD
	var y := r.position.y + 84.0
	TierStyle.draw_name(canvas, font, Vector2(x, y), db, tier_id, GunStats.display_name(db, gun), 24, tint, w)
	y += 12.0
	ItemIcons.draw(canvas, String(gun["body"]), Rect2(x + w * 0.12, y, w * 0.76, 120.0), tint)
	y += 132.0
	var maker: Dictionary = db.makers[String(gun["maker"])]
	canvas.draw_circle(Vector2(x + 6, y - 5), 5.0, Color.html(String(maker["color"])))
	canvas.draw_string(font, Vector2(x + 18, y), String(maker["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
	if not against.is_empty():
		canvas.draw_string(font, Vector2(x, y), "vs. in hand", HORIZONTAL_ALIGNMENT_RIGHT, w, 13, UiSkin.TEXT_DIM)
	y += 14.0
	var rows := [["Damage", "damage", "%.1f", true], ["Fire rate", "fire_rate", "%.2f/s", true], ["Magazine", "mag_size", "%d", true],
		["Reload", "reload_time", "%.2f s", false], ["Spread", "spread", "%.3f", false], ["Crit chance", "crit_chance", "%.0f%%", true]]
	for row: Array in rows:
		y += 22.0
		var key := String(row[1])
		var value := float(stats[key]) * (100.0 if key == "crit_chance" else 1.0)
		canvas.draw_string(font, Vector2(x, y), String(row[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
		var shown := String(row[2]) % _num(value, key == "mag_size")
		canvas.draw_string(font, Vector2(x, y), shown, HORIZONTAL_ALIGNMENT_RIGHT, w - 70.0, 15, UiSkin.TEXT)
		if not other.is_empty():
			var was := float(other[key]) * (100.0 if key == "crit_chance" else 1.0)
			if absf(value - was) > 0.0005:
				var better := (value > was) == bool(row[3])
				canvas.draw_string(font, Vector2(x, y), ("+" if value > was else "") + (String(row[2]) % _num(value - was, key == "mag_size")), HORIZONTAL_ALIGNMENT_RIGHT, w, 13, UiSkin.GOOD if better else UiSkin.BAD)
	y += 30.0
	var dps := float(stats["damage"]) * float(stats["fire_rate"])
	canvas.draw_string(font, Vector2(x, y), "DPS", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiSkin.ACCENT)
	canvas.draw_string(font, Vector2(x, y), "%.0f" % dps, HORIZONTAL_ALIGNMENT_RIGHT, w - 70.0, 22, UiSkin.ACCENT)
	if not other.is_empty():
		var dps_was := float(other["damage"]) * float(other["fire_rate"])
		canvas.draw_string(font, Vector2(x, y), "%+.0f" % (dps - dps_was), HORIZONTAL_ALIGNMENT_RIGHT, w, 15, UiSkin.GOOD if dps >= dps_was else UiSkin.BAD)
	y += 16.0
	var lines: Array = []  # [text, colour, boxed, icon shape ("" = none)]
	if stats.has("unique") and String((stats["unique"] as Dictionary).get("red", "")) != "":  # a chase gun's red text comes first
		lines.append([String(stats["unique"]["red"]), RED_TEXT, false, ""])
	if stats.has("unique") and String((stats["unique"] as Dictionary).get("keeps", "")) == "record":  # Fish Story's tag
		lines.append(["Biggest hit on the tag: %s" % (str(int(gun.get("record", 0))) if int(gun.get("record", 0)) > 0 else "none yet"), Color(0.95, 0.78, 0.4), false, ""])
	if gun.has("family"):
		var fam: Dictionary = db.family_def(String(gun["family"]))
		lines.append(["%s  -  %s\n%s" % [String(fam.get("name", "")), String(fam.get("virtue", "")), String(fam.get("role", ""))], TierStyle.family_colour(db, String(gun["family"])), false, ""])
	for tr_roll: Dictionary in gun.get("traits", []):
		var tdef: Dictionary = db.trait_def(String(tr_roll["id"]))
		if not tdef.is_empty():
			var of := String(tdef.get("family", ""))  # a pony-only trait wears its family's colour
			lines.append(["%s  -  %s" % [tdef["name"], _fill(tdef, float(tr_roll["q"]))], TierStyle.family_colour(db, of) if of != "" else TRAIT_COLOUR, true, ""])
	if gun.has("sea"):
		lines.append([GunStats.sea_text(db, gun), SEA_COLOUR, true, ""])
	for b: Dictionary in gun["buffs"]:
		var bdef: Dictionary = db.buff_def(String(b["id"]))
		lines.append(["%s: %s" % [bdef["name"], _fill(bdef, float(b["q"]))], BUFF_COLOUR, false, ""])
	for combo: Dictionary in stats.get("combos", []):
		lines.append([String(combo["desc"]), COMBO_COLOUR, false, ""])
	var skill_list: Array = gun.get("skills", [])
	for i in skill_list.size():
		var sdef: Dictionary = db.skill_def(String((skill_list[i] as Dictionary)["id"]))
		var sc: Array = sdef.get("color", [SKILL_COLOUR.r, SKILL_COLOUR.g, SKILL_COLOUR.b])
		var text := "[%s] %s   %.0f s\n%s" % ["Q" if i == 0 else "E", sdef["name"], SkillState.cooldown(db, skill_list[i], tier_id), SkillState.describe(db, skill_list[i])]
		lines.append([text, Color(float(sc[0]), float(sc[1]), float(sc[2])), false, String(sdef.get("icon", ""))])
	var gun_parts: Dictionary = gun["parts"]
	var part_names: Array[String] = []
	for part_slot: String in db.slots:
		if gun_parts.has(part_slot):
			part_names.append(String(db.parts[part_slot][String((gun_parts[part_slot] as Dictionary)["kind"])]["name"]))
	if not part_names.is_empty():
		lines.append(["Parts: " + ", ".join(part_names), UiSkin.TEXT_DIM, false, ""])
	if stats.has("unique"):
		var u: Dictionary = stats["unique"]
		if String(u.get("flavor", "")) != "":
			lines.append(["\"%s\"" % String(u["flavor"]), Color(1.0, 0.55, 0.7), false, ""])
	for line: Array in lines:
		var indent := 40.0 if String(line[3]) != "" else (6.0 if bool(line[2]) else 0.0)  # a skill's icon sits left of its text
		var text_h := maxf(font.get_multiline_string_size(String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, w - 10.0 - indent, 14).y, 34.0 if indent > 30.0 else 0.0)
		if y + text_h + 14.0 > foot - 8.0:
			canvas.draw_string(font, Vector2(x, foot - 12.0), "...", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
			break
		y += 10.0
		if bool(line[2]):  # traits get a box of their own
			canvas.draw_rect(Rect2(x - 6.0, y - 2.0, w + 12.0, text_h + 10.0), Color(line[1], 0.12))  # in the line's own colour
			canvas.draw_rect(Rect2(x - 6.0, y - 2.0, 3.0, text_h + 10.0), line[1])
		if String(line[3]) != "":
			IconArt.draw(canvas, String(line[3]), Rect2(x, y, 34.0, 34.0), line[1])
		canvas.draw_multiline_string(font, Vector2(x + indent, y + 14.0), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, w - 10.0 - indent, 14, -1, line[1])
		y += text_h + (8.0 if bool(line[2]) else 2.0)


# A whole number for counts (the magazine), the value itself otherwise.
static func _num(value: float, whole: bool) -> Variant:
	if whole:
		return roundi(value)
	return value


static func _fill(def: Dictionary, q: float) -> String:
	var value := lerpf(float(def["min"]), float(def["max"]), q)
	return String(def["desc"]) % (("%.1f" % value) if value < 10.0 else ("%.0f" % value))


# A rolled armour piece: tier band with its item level, name, icon, the stat and roll lines, then its set's steps
# (lit when that many pieces are worn: what["worn_sets"]).
static func _armour(canvas: CanvasItem, font: Font, r: Rect2, foot: float, what: Dictionary, gun_db: RefCounted, items: RefCounted, t: float) -> void:
	var id := String(what["id"])
	var arm: Dictionary = what["arm"]
	var stack := {"id": id, "count": 1, "arm": arm}
	var tier := String(arm["tier"])
	var tint := TierStyle.color(gun_db, tier, t)
	_band(canvas, font, r, tint, "%s %s" % [String(gun_db.tier(tier)["name"]).to_upper(), String(items.equip_slot(id)).capitalize().to_upper()], "Lv %d" % int(arm["lvl"]))
	var x := r.position.x + PAD
	var w := r.size.x - 2.0 * PAD
	canvas.draw_string(font, Vector2(x, r.position.y + 90.0), ArmourStats.display_name(items, stack, String(gun_db.tier(tier)["name"])), HORIZONTAL_ALIGNMENT_LEFT, w, 22, tint)
	ItemIcons.draw(canvas, id, Rect2(x + w * 0.3, r.position.y + 106.0, w * 0.4, 110.0), Color.WHITE)
	var y := r.position.y + 240.0
	for line: String in ArmourStats.lines(items, stack):
		canvas.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, w, 16, UiSkin.GOOD)
		y += 22.0
	var set_id := String(arm.get("set", ""))
	if set_id != "":
		y += 6.0
		var set_tint := Color(String(items.armour["sets"][set_id]["color"]))
		var worn := int((what.get("worn_sets", {}) as Dictionary).get(set_id, 0))
		for line: Array in ArmourStats.set_lines(items, set_id, worn):
			canvas.draw_string(font, Vector2(x, y), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, w, 15, set_tint if bool(line[1]) else UiSkin.TEXT_DIM)
			y += 20.0
	y += 8.0
	if y < foot - 30.0:
		canvas.draw_multiline_string(font, Vector2(x, y + 10.0), items.flavor(id), HORIZONTAL_ALIGNMENT_LEFT, w, 15, maxi(1, floori((foot - y - 20.0) / 20.0)), Color(0.85, 0.82, 0.95))


static func _item(canvas: CanvasItem, font: Font, r: Rect2, foot: float, id: String, count: int, items: RefCounted) -> void:
	var kind := String(items.kind(id)).capitalize()
	_band(canvas, font, r, Color(0.55, 0.6, 0.75), kind.to_upper(), ("x%d" % count) if count > 1 else "")
	var x := r.position.x + PAD
	var w := r.size.x - 2.0 * PAD
	canvas.draw_string(font, Vector2(x, r.position.y + 90.0), items.item_name(id), HORIZONTAL_ALIGNMENT_LEFT, w, 24, UiSkin.TEXT)
	ItemIcons.draw(canvas, id, Rect2(x + w * 0.25, r.position.y + 110.0, w * 0.5, 150.0), Color.WHITE)
	var y := r.position.y + 290.0
	var slot_name := String(items.equip_slot(id))
	if slot_name != "":
		canvas.draw_string(font, Vector2(x, y), "Worn on: " + slot_name.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiSkin.TEXT_DIM)
		y += 26.0
	for line: String in items.stat_lines(id):
		canvas.draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, w, 16, UiSkin.GOOD)
		y += 22.0
	y += 8.0
	if y < foot - 30.0:
		canvas.draw_multiline_string(font, Vector2(x, y + 10.0), items.flavor(id), HORIZONTAL_ALIGNMENT_LEFT, w, 15, maxi(1, floori((foot - y - 20.0) / 20.0)), Color(0.85, 0.82, 0.95))
