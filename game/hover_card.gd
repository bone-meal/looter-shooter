# Purpose: the hover cards of the bag, shared by every screen that shows what a thing is (inventory, trade window):
# a rolled gun with its stats (compared with another gun), parts, buffs and skills, and a plain item with its lines.
# Drawn onto the canvas item that asks, inside its _draw.
# Dependencies: core/gun_stats.gd, core/skill_state.gd, game/tier_style.gd; a gun db (core/gun_db.gd) and item db (core/item_db.gd) are handed in.
extends RefCounted

const GunStats = preload("res://core/gun_stats.gd")
const SkillState = preload("res://core/skill_state.gd")
const TierStyle = preload("res://game/tier_style.gd")

const ITEM_WIDTH := 240.0


# Card of a rolled gun at `place`: name in its tier colour, stats compared with `against` (another rolled gun, or {}),
# parts and buffs. Returns where it was drawn.
static func draw_gun(canvas: CanvasItem, font: Font, gun_db: RefCounted, gun: Dictionary, against: Dictionary, place: Vector2, view: Vector2, note: String) -> Rect2:
	var stats := GunStats.final_stats(gun_db, gun)
	var other: Dictionary = {} if against.is_empty() else GunStats.final_stats(gun_db, against)
	var lines: Array = []  # [text, colour]
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
		for wrapped in _wrap("\"%s\"" % String((stats["unique"] as Dictionary).get("flavor", "")), 50):
			lines.append([wrapped, Color(1.0, 0.45, 0.6)])
		lines.append(["Unique: every stat rolled at the top, plus a bonus to each", Color(1.0, 0.7, 0.85)])
	for combo: Dictionary in stats.get("combos", []):  # what the parts do together
		for wrapped in _wrap(String(combo["desc"]), 50):
			lines.append([wrapped, Color(0.6, 1.0, 0.7)])
	for b: Dictionary in gun["buffs"]:
		var def: Dictionary = gun_db.buff_def(String(b["id"]))
		var value := lerpf(float(def["min"]), float(def["max"]), float(b["q"]))
		lines.append(["%s: %s" % [def["name"], String(def["desc"]) % (("%.1f" % value) if value < 10.0 else ("%.0f" % value))], Color(1.0, 0.8, 0.4)])
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
	TierStyle.draw_name(canvas, font, pos + Vector2(10, 22), gun_db, String(gun["tier"]), GunStats.display_name(gun_db, gun), 17, tint)
	canvas.draw_string(font, pos + Vector2(10, 40), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.8))
	var y := 58.0
	for line: Array in lines:
		canvas.draw_string(font, pos + Vector2(10, y), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, width - 20.0, 13, line[1])
		y += 16.0
	return Rect2(pos, Vector2(width, height))


# Card of a plain item (armour, food ...) at `place`.
static func draw_item(canvas: CanvasItem, font: Font, items: RefCounted, id: String, place: Vector2, view: Vector2) -> void:
	var pos := place
	var flavor: String = items.flavor(id)
	var stat_lines: Array[String] = items.stat_lines(id)
	var lines := ceili(flavor.length() / 30.0)
	var height := 62.0 + stat_lines.size() * 16.0 + lines * 18.0
	pos.x = minf(pos.x, view.x - ITEM_WIDTH - 8.0)
	pos.y = minf(pos.y, view.y - height - 8.0)
	canvas.draw_rect(Rect2(pos, Vector2(ITEM_WIDTH, height)), Color(0.08, 0.04, 0.12, 0.96))
	canvas.draw_rect(Rect2(pos, Vector2(ITEM_WIDTH, height)), Color(0.7, 0.5, 0.9, 0.8), false, 1.5)
	canvas.draw_string(font, pos + Vector2(10, 22), items.item_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))
	canvas.draw_string(font, pos + Vector2(10, 40), String(items.kind(id)).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.8))
	var y := 60.0
	for line in stat_lines:
		canvas.draw_string(font, pos + Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 1.0, 0.7))
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
