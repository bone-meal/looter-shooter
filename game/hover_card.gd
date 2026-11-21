# Purpose: the hover cards of the bag, shared by every screen that shows what a thing is (inventory, trade window):
# a rolled gun with its stats (compared with another gun), parts, buffs and skills, and a plain item with its lines.
# Drawn onto the canvas item that asks, inside its _draw.
# Dependencies: core/gun_stats.gd, core/skill_state.gd, game/tier_style.gd, core/armour_stats.gd (rolled armour); a gun db (core/gun_db.gd) and item db (core/item_db.gd) are handed in.
extends RefCounted

const GunStats = preload("res://core/gun_stats.gd")
const CamoSkin = preload("res://game/camo_skin.gd")
const SkillState = preload("res://core/skill_state.gd")
const TierStyle = preload("res://game/tier_style.gd")
const ArmourStats = preload("res://core/armour_stats.gd")

const ITEM_WIDTH := 240.0


# Card of a rolled gun at `place`: name in its tier colour, stats compared with `against` (another rolled gun, or {}),
# parts and buffs. Returns where it was drawn.
const WKILLS_COLOR := Color(1.0, 0.55, 0.15)
const TRAIT_COLOR := Color(1.0, 0.42, 0.3)  # gun traits (red-orange, above the buffs)
const SEA_COLOR := Color(0.35, 0.9, 0.85)  # a sea affix (data/sea_affixes.json)


static func draw_gun(canvas: CanvasItem, font: Font, gun_db: RefCounted, gun: Dictionary, against: Dictionary, place: Vector2, view: Vector2, note: String) -> Rect2:
	var stats := GunStats.final_stats(gun_db, gun)
	var other: Dictionary = {} if against.is_empty() else GunStats.final_stats(gun_db, against)
	var lines: Array = []  # [text, colour]
	if gun.has("wkills"):  # the kill counter: on the gun model too (game/wkills_display.gd)
		lines.append(["W kills  Confirmed kills: %d" % int(gun["wkills"]), WKILLS_COLOR])
		lines.append(["This gun counts every kill made with it.", Color(0.95, 0.65, 0.35)])
	if gun.get("camo") is Dictionary and not CamoSkin.look_of(String((gun["camo"] as Dictionary).get("id", ""))).is_empty():  # (polish1 D5a)
		var look := CamoSkin.look_of(String(gun["camo"]["id"]))
		lines.append(["- %s skin applied" % String(look["name"]), Color(String((gun_db.tier(String(look["tier"])) as Dictionary).get("color", "#ffffff")))])
	lines.append(["Item level %d%s" % [int(stats["lvl"]), "" if other.is_empty() else "  (%+d)" % (int(stats["lvl"]) - int(other["lvl"]))], Color(0.9, 0.9, 0.6)])
	lines.append(["Damage %.1f%s" % [stats["damage"], _diff_text(float(stats["damage"]), other, "damage", 1)], _delta_color(float(stats["damage"]), other, "damage", true)])
	lines.append(["Fire rate %.2f/s%s" % [stats["fire_rate"], _diff_text(float(stats["fire_rate"]), other, "fire_rate", 2)], _delta_color(float(stats["fire_rate"]), other, "fire_rate", true)])
	lines.append(["Magazine %d%s" % [stats["mag_size"], _diff_text(float(stats["mag_size"]), other, "mag_size", 0)], _delta_color(float(stats["mag_size"]), other, "mag_size", true)])
	lines.append(["Reload %.2fs%s" % [stats["reload_time"], _diff_text(float(stats["reload_time"]), other, "reload_time", 2)], _delta_color(float(stats["reload_time"]), other, "reload_time", false)])
	lines.append(["Spread %.3f%s" % [stats["spread"], _diff_text(float(stats["spread"]), other, "spread", 3)], _delta_color(float(stats["spread"]), other, "spread", false)])
	lines.append(["Recoil x%.2f   Crit %d%%" % [stats["recoil"], roundi(float(stats["crit_chance"]) * 100.0)], Color(0.85, 0.85, 0.9)])
	if stats.has("move_speed"):  # how fast you run with it in hand (Source units a second; the knife runs at 250)
		lines.append(["Carry speed %d%s" % [roundi(float(stats["move_speed"])), _diff_text(float(stats["move_speed"]), other, "move_speed", 0)], _delta_color(float(stats["move_speed"]), other, "move_speed", true)])
	var dps := float(stats["damage"]) * float(stats["fire_rate"])
	var dps_other := float(other["damage"]) * float(other["fire_rate"]) if not other.is_empty() else 0.0
	lines.append(["DPS %.0f%s" % [dps, "" if other.is_empty() else " (%+.0f)" % (dps - dps_other)], Color(1.0, 0.9, 0.5) if other.is_empty() or dps >= dps_other else Color(1.0, 0.5, 0.45)])
	var gun_parts: Dictionary = gun["parts"]
	for part_slot: String in gun_db.slots:
		if gun_parts.has(part_slot):
			var pd: Dictionary = gun_parts[part_slot]
			lines.append(["%s (%s)" % [gun_db.parts[part_slot][String(pd["kind"])]["name"], gun_db.makers[String(pd["maker"])]["name"]], Color(0.75, 0.85, 1.0)])
	if stats.has("unique"):  # hand-made pony gun: its saying, then what every unique gets
		var u: Dictionary = stats["unique"]
		for wrapped in _wrap(String(u.get("red", "")), 50):  # a chase gun's red text
			lines.append([wrapped, Color(1.0, 0.22, 0.18)])
		if String(u.get("keeps", "")) == "record":  # Fish Story's tag
			lines.append(["Biggest hit on the tag: %s" % (str(int(gun.get("record", 0))) if int(gun.get("record", 0)) > 0 else "none yet"), Color(0.95, 0.78, 0.4)])
		if String(u.get("flavor", "")) != "":
			for wrapped in _wrap("\"%s\"" % String(u["flavor"]), 50):
				lines.append([wrapped, Color(1.0, 0.45, 0.6)])
		lines.append(["Unique: every stat rolled at the top, plus a bonus to each", Color(1.0, 0.7, 0.85)])
	for combo: Dictionary in stats.get("combos", []):  # what the parts do together
		for wrapped in _wrap(String(combo["desc"]), 50):
			lines.append([wrapped, Color(0.6, 1.0, 0.7)])
	for b: Dictionary in gun["buffs"]:
		var def: Dictionary = gun_db.buff_def(String(b["id"]))
		var value := lerpf(float(def["min"]), float(def["max"]), float(b["q"]))
		lines.append(["%s: %s" % [def["name"], String(def["desc"]) % (("%.1f" % value) if value < 10.0 else ("%.0f" % value))], Color(1.0, 0.8, 0.4)])
	for tr_roll: Dictionary in gun.get("traits", []):  # the big effects, in their own colour (data/gun_traits.json)
		var tdef: Dictionary = gun_db.trait_def(String(tr_roll["id"]))
		if tdef.is_empty():
			continue
		var tvalue := lerpf(float(tdef["min"]), float(tdef["max"]), float(tr_roll["q"]))
		var pony_trait := String(tdef.get("family", "")) != ""
		for wrapped in _wrap("%s %s: %s" % ["PONY" if pony_trait else "TRAIT", tdef["name"], String(tdef["desc"]) % (("%.1f" % tvalue) if tvalue < 10.0 else ("%.0f" % tvalue))], 50):
			lines.append([wrapped, TierStyle.family_colour(gun_db, String(tdef["family"])) if pony_trait else TRAIT_COLOR])
	if gun.has("sea"):
		for wrapped in _wrap("SEA " + GunStats.sea_text(gun_db, gun), 50):
			lines.append([wrapped, SEA_COLOR])
	var skill_list: Array = gun.get("skills", [])
	for i in skill_list.size():
		var entry: Dictionary = skill_list[i]
		var sdef: Dictionary = gun_db.skill_def(String(entry["id"]))
		lines.append(["[%s] %s   cooldown %.0f s" % ["Q" if i == 0 else "E", sdef["name"], SkillState.cooldown(gun_db, entry, String(gun["tier"]))], Color(0.5, 0.95, 1.0)])
		for wrapped in _wrap(SkillState.describe(gun_db, entry), 50):
			lines.append(["   " + wrapped, Color(0.7, 0.8, 0.85)])
	var width := 340.0
	var height := 54.0 + lines.size() * 16.0
	var pos := place
	pos.x = minf(pos.x, view.x - width - 8.0)
	pos.y = maxf(minf(pos.y, view.y - height - 8.0), 4.0)
	var tint := TierStyle.color(gun_db, String(gun["tier"]), Time.get_ticks_msec() / 1000.0)
	canvas.draw_rect(Rect2(pos, Vector2(width, height)), Color(0.06, 0.05, 0.1, 0.97))
	canvas.draw_rect(Rect2(pos, Vector2(width, height)), tint, false, 2.0)
	var title := GunStats.display_name(gun_db, gun)
	var maker := GunStats.maker_name(gun_db, gun)
	if TierStyle.overflows(font, gun_db, String(gun["tier"]), title, 17, width - 20.0, maker):  # a long name scrolls (director 2026-11-20)
		TierStyle.draw_name(canvas, font, pos + Vector2(10, 22), gun_db, String(gun["tier"]), title, 17, tint, width - 20.0, Time.get_ticks_msec() / 1000.0, maker)
	else:
		TierStyle.draw_name(canvas, font, pos + Vector2(10, 22), gun_db, String(gun["tier"]), title, 17, tint, -1.0, -1.0, maker)
	canvas.draw_string(font, pos + Vector2(10, 40), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.8))
	var y := 58.0
	for line: Array in lines:
		canvas.draw_string(font, pos + Vector2(10, y), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, width - 20.0, 13, line[1])
		y += 16.0
	return Rect2(pos, Vector2(width, height))


# Card of a plain item (armour, food ...) at `place`.
static func draw_item(canvas: CanvasItem, font: Font, items: RefCounted, id: String, place: Vector2, view: Vector2, arm: Dictionary = {}, gun_db: RefCounted = null) -> void:
	var pos := place
	var flavor: String = items.flavor(id)
	var stack := {"id": id, "count": 1, "arm": arm} if not arm.is_empty() and gun_db != null else {"id": id, "count": 1}
	var stat_lines: Array[String] = ArmourStats.lines(items, stack)
	var title: String = items.item_name(id)
	var title_color := Color(1, 1, 1)
	var under := String(items.kind(id)).capitalize()
	if stack.has("arm"):  # a rolled piece: tier word + set in the name, item level under it, the set's steps after the rolls
		var tier := String(arm["tier"])
		title = ArmourStats.display_name(items, stack, String(gun_db.tier(tier)["name"]))
		title_color = TierStyle.color(gun_db, tier, Time.get_ticks_msec() / 1000.0)
		under = "Armour  -  item level %d" % int(arm["lvl"])
		for line: Array in ArmourStats.set_lines(items, String(arm.get("set", "")), 0):
			stat_lines.append(String(line[0]))
	var lines := ceili(flavor.length() / 30.0)
	var height := 62.0 + stat_lines.size() * 16.0 + lines * 18.0
	pos.x = minf(pos.x, view.x - ITEM_WIDTH - 8.0)
	pos.y = minf(pos.y, view.y - height - 8.0)
	canvas.draw_rect(Rect2(pos, Vector2(ITEM_WIDTH, height)), Color(0.08, 0.04, 0.12, 0.96))
	canvas.draw_rect(Rect2(pos, Vector2(ITEM_WIDTH, height)), Color(0.7, 0.5, 0.9, 0.8), false, 1.5)
	canvas.draw_string(font, pos + Vector2(10, 22), title, HORIZONTAL_ALIGNMENT_LEFT, ITEM_WIDTH - 20.0, 18, title_color)
	canvas.draw_string(font, pos + Vector2(10, 40), under, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.8))
	var y := 60.0
	for line in stat_lines:
		canvas.draw_string(font, pos + Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, ITEM_WIDTH - 20.0, 13, Color(0.6, 1.0, 0.7))
		y += 16.0
	canvas.draw_multiline_string(font, pos + Vector2(10, y + 4.0), flavor, HORIZONTAL_ALIGNMENT_LEFT, ITEM_WIDTH - 20.0, 13, -1, Color(0.85, 0.8, 0.95))


# A small card with a title and a sentence or two (things that are neither guns nor items: the knife).
static func draw_note(canvas: CanvasItem, font: Font, title: String, text: String, place: Vector2, view: Vector2) -> void:
	var wrapped := _wrap(text, 34)
	var height := 40.0 + wrapped.size() * 16.0
	var pos := Vector2(minf(place.x, view.x - ITEM_WIDTH - 8.0), minf(place.y, view.y - height - 8.0))
	canvas.draw_rect(Rect2(pos, Vector2(ITEM_WIDTH, height)), Color(0.08, 0.04, 0.12, 0.96))
	canvas.draw_rect(Rect2(pos, Vector2(ITEM_WIDTH, height)), Color(0.7, 0.5, 0.9, 0.8), false, 1.5)
	canvas.draw_string(font, pos + Vector2(10, 22), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))
	var y := 42.0
	for line in wrapped:
		canvas.draw_string(font, pos + Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.8, 0.95))
		y += 16.0


# Splits text into lines of at most `limit` characters, breaking at spaces.
static func _wrap(text: String, limit: int) -> Array[String]:
	var out: Array[String] = []
	var line := ""
	for word in text.split(" "):
		if line != "" and line.length() + 1 + word.length() > limit:
			out.append(line)
			line = word
		else:
			line = word if line == "" else line + " " + word
	if line != "":
		out.append(line)
	return out


static func _diff_text(value: float, other: Dictionary, key: String, digits: int) -> String:
	if other.is_empty():
		return ""
	var d := value - float(other[key])
	return " (%s%s)" % ["+" if d >= 0.0 else "", String.num(d, digits)]


# Green when better than the held gun, red when worse (higher_better false for stats where lower wins).
static func _delta_color(value: float, other: Dictionary, key: String, higher_better: bool) -> Color:
	if other.is_empty():
		return Color(0.85, 0.85, 0.9)
	var d := value - float(other[key])
	if absf(d) < 0.0005:
		return Color(0.85, 0.85, 0.9)
	return Color(0.5, 1.0, 0.6) if (d > 0.0) == higher_better else Color(1.0, 0.5, 0.45)
