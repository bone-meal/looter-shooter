# Purpose: Minecraft-style inventory screen: 27 main slots + 9 hotbar slots + an 18-slot equipment panel; click to pick up / place / swap / wear, right click for half or one, hover tooltip with stats and flavor text.
# Dependencies: core/inventory_state.gd, core/item_db.gd, game/item_icons.gd. Emits `changed` after every click so the player re-reads the held item.
extends Control

const ItemIcons = preload("res://game/item_icons.gd")
const InventoryState = preload("res://core/inventory_state.gd")
const ItemDb = preload("res://core/item_db.gd")
const GunDb = preload("res://core/gun_db.gd")
const SkillState = preload("res://core/skill_state.gd")
const GunStats = preload("res://core/gun_stats.gd")
const TierStyle = preload("res://game/tier_style.gd")

signal changed

const SLOT := 48.0
const GAP := 4.0
const COLUMNS := 9
const TOOLTIP_WIDTH := 240.0
const EQUIP_BASE := 100  # slot indices >= this are equipment slots (index - EQUIP_BASE into EQUIP_SLOTS)
const EQUIP_COLUMNS := 3
const SLOT_LABELS := {"hat": "Hat", "head": "Head", "earrings": "Ears", "necklace": "Neck", "glasses": "Eyes", "mouth": "Mouth", "shirt": "Shirt", "chestplate": "Chest", "gauntlets": "Hands", "ring_1": "Ring", "ring_2": "Ring", "bracelet": "Wrist", "pants": "Pants", "leg_armor": "Legs", "cape": "Cape", "waist": "Belt", "boots": "Boots", "foot_armor": "Feet"}

var inventory: InventoryState  # set before add_child
var items: ItemDb  # set before add_child
var gun_db: GunDb  # set before add_child (rolled guns: colours, names, stats)
var selected_hotbar := 0  # set by the session so the held slot is highlighted

var _mouse := Vector2.ZERO
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


func open() -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	queue_redraw()


# Returns the stack on the mouse to the inventory, then hides.
func close() -> void:
	inventory.return_cursor()
	visible = false
	changed.emit()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # animated tier colours (rainbow, pony)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _gun_in(stack: Dictionary) -> Dictionary:
	return stack.get("gun", {})


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var slot := _slot_at(event.position)
		if slot < 0:
			return
		if slot >= EQUIP_BASE:
			if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
				return
			inventory.click_equipment(inventory.EQUIP_SLOTS[slot - EQUIP_BASE])
		elif event.button_index == MOUSE_BUTTON_LEFT:
			inventory.click_slot(slot)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			inventory.right_click_slot(slot)
		else:
			return
		changed.emit()
		queue_redraw()


func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.6))
	var origin := _origin(view)
	var left := EQUIP_COLUMNS * (SLOT + GAP) + 44.0
	var panel := Rect2(origin - Vector2(16 + left, 44), Vector2(COLUMNS * (SLOT + GAP) - GAP + 32 + left, 6 * (SLOT + GAP) + 64))
	draw_rect(panel, Color(0.12, 0.12, 0.14, 0.95))
	draw_rect(panel, Color(1, 1, 1, 0.3), false, 2.0)
	draw_string(_font, origin + Vector2(0, -16), "INVENTORY", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
	var hover := _slot_at(_mouse)
	for i in inventory.SIZE:
		_draw_slot(i, hover == i)
	_draw_equipment(hover)
	var hovered_id := _id_at(hover)
	if hovered_id != "" and inventory.cursor.is_empty():
		if hovered_id == "gun" and hover < EQUIP_BASE:
			_draw_gun_tooltip(inventory.gun_at(hover), hover, view)
		else:
			_draw_tooltip(hovered_id, view)
	if not inventory.cursor.is_empty():
		var r := Rect2(_mouse - Vector2(SLOT, SLOT) * 0.4, Vector2(SLOT, SLOT) * 0.8)
		var cgun := _gun_in(inventory.cursor)
		if cgun.is_empty():
			ItemIcons.draw(self, inventory.cursor["id"], r, Color.WHITE)
		else:
			ItemIcons.draw(self, String(cgun["body"]), r, TierStyle.color(gun_db, String(cgun["tier"]), _now()))
		_draw_count(r, int(inventory.cursor["count"]))


func _draw_slot(i: int, hovered: bool) -> void:
	var r := _slot_rect(i)
	draw_rect(r, Color(0.05, 0.05, 0.06, 0.9))
	var held: bool = i == selected_hotbar
	draw_rect(r, Color(1, 1, 1, 0.95) if held else (Color(1, 1, 0.6, 0.9) if hovered else Color(1, 1, 1, 0.25)), false, 2.0 if (held or hovered) else 1.0)
	var id: String = inventory.item_id(i)
	if id == "":
		return
	var gun: Dictionary = inventory.gun_at(i)
	if gun.is_empty():
		ItemIcons.draw(self, id, r.grow(-5), Color.WHITE)
	else:
		var tint := TierStyle.color(gun_db, String(gun["tier"]), _now())
		draw_rect(r, tint, false, 2.0)
		ItemIcons.draw(self, String(gun["body"]), r.grow(-5), tint)
	_draw_count(r, inventory.item_count(i))


func _draw_equipment(hover: int) -> void:
	var o := _equip_origin(get_viewport_rect().size)
	draw_string(_font, o + Vector2(0, -16), "EQUIPMENT", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.95))
	for k in inventory.EQUIP_SLOTS.size():
		var slot: String = inventory.EQUIP_SLOTS[k]
		var r := _equip_rect(k)
		var fits: bool = inventory.can_equip_cursor(slot)
		draw_rect(r, Color(0.05, 0.05, 0.06, 0.9))
		draw_rect(r, Color(0.4, 1.0, 0.5, 0.95) if fits else (Color(1, 1, 0.6, 0.9) if hover == EQUIP_BASE + k else Color(1, 1, 1, 0.25)), false, 2.0 if (fits or hover == EQUIP_BASE + k) else 1.0)
		var stack: Dictionary = inventory.equipment[slot]
		if stack.is_empty():
			draw_string(_font, r.position + Vector2(0, SLOT * 0.5 + 5), SLOT_LABELS[slot], HORIZONTAL_ALIGNMENT_CENTER, SLOT, 12, Color(1, 1, 1, 0.3))
		else:
			ItemIcons.draw(self, stack["id"], r.grow(-5), Color.WHITE)


func _id_at(slot: int) -> String:
	if slot < 0:
		return ""
	if slot >= EQUIP_BASE:
		var stack: Dictionary = inventory.equipment[inventory.EQUIP_SLOTS[slot - EQUIP_BASE]]
		return "" if stack.is_empty() else String(stack["id"])
	return inventory.item_id(slot)


func _draw_count(r: Rect2, count: int) -> void:
	if count > 1:
		draw_string(_font, r.end - Vector2(30, 6), str(count), HORIZONTAL_ALIGNMENT_RIGHT, 26, 15, Color.WHITE)


# Tooltip of a rolled gun: name in its tier colour, stats compared with the gun in the selected hotbar slot, parts and buffs.
func _draw_gun_tooltip(gun: Dictionary, slot: int, view: Vector2) -> void:
	var stats := GunStats.final_stats(gun_db, gun)
	var held: Dictionary = inventory.gun_at(selected_hotbar)
	var other: Dictionary = {} if held.is_empty() or slot == selected_hotbar else GunStats.final_stats(gun_db, held)
	var lines: Array = []  # [text, colour]
	lines.append(["Damage %.1f%s" % [stats["damage"], _diff_text(float(stats["damage"]), other, "damage", 1)], _delta_color(float(stats["damage"]), other, "damage", true)])
	lines.append(["Fire rate %.2f/s%s" % [stats["fire_rate"], _diff_text(float(stats["fire_rate"]), other, "fire_rate", 2)], _delta_color(float(stats["fire_rate"]), other, "fire_rate", true)])
	lines.append(["Magazine %d%s" % [stats["mag_size"], _diff_text(float(stats["mag_size"]), other, "mag_size", 0)], _delta_color(float(stats["mag_size"]), other, "mag_size", true)])
	lines.append(["Reload %.2fs%s" % [stats["reload_time"], _diff_text(float(stats["reload_time"]), other, "reload_time", 2)], _delta_color(float(stats["reload_time"]), other, "reload_time", false)])
	lines.append(["Spread %.3f%s" % [stats["spread"], _diff_text(float(stats["spread"]), other, "spread", 3)], _delta_color(float(stats["spread"]), other, "spread", false)])
	lines.append(["Recoil x%.2f   Crit %d%%" % [stats["recoil"], roundi(float(stats["crit_chance"]) * 100.0)], Color(0.85, 0.85, 0.9)])
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
	var pos := _mouse + Vector2(18, 18)
	pos.x = minf(pos.x, view.x - width - 8.0)
	pos.y = minf(pos.y, view.y - height - 8.0)
	var tint := TierStyle.color(gun_db, String(gun["tier"]), _now())
	draw_rect(Rect2(pos, Vector2(width, height)), Color(0.06, 0.05, 0.1, 0.97))
	draw_rect(Rect2(pos, Vector2(width, height)), tint, false, 2.0)
	draw_string(_font, pos + Vector2(10, 22), GunStats.display_name(gun_db, gun), HORIZONTAL_ALIGNMENT_LEFT, -1, 17, tint)
	draw_string(_font, pos + Vector2(10, 40), "vs held gun" if not other.is_empty() else "Rolled gun", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.8))
	var y := 58.0
	for line: Array in lines:
		draw_string(_font, pos + Vector2(10, y), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, width - 20.0, 13, line[1])
		y += 16.0


# Splits text into lines of at most `limit` characters, breaking at spaces.
func _wrap(text: String, limit: int) -> Array[String]:
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


func _diff_text(value: float, other: Dictionary, key: String, digits: int) -> String:
	if other.is_empty():
		return ""
	var d := value - float(other[key])
	return " (%s%s)" % ["+" if d >= 0.0 else "", String.num(d, digits)]


# Green when better than the held gun, red when worse (higher_better false for stats where lower wins).
func _delta_color(value: float, other: Dictionary, key: String, higher_better: bool) -> Color:
	if other.is_empty():
		return Color(0.85, 0.85, 0.9)
	var d := value - float(other[key])
	if absf(d) < 0.0005:
		return Color(0.85, 0.85, 0.9)
	return Color(0.5, 1.0, 0.6) if (d > 0.0) == higher_better else Color(1.0, 0.5, 0.45)


func _draw_tooltip(id: String, view: Vector2) -> void:
	var pos := _mouse + Vector2(18, 18)
	var flavor: String = items.flavor(id)
	var stat_lines: Array[String] = items.stat_lines(id)
	var lines := ceili(flavor.length() / 30.0)
	var height := 62.0 + stat_lines.size() * 16.0 + lines * 18.0
	pos.x = minf(pos.x, view.x - TOOLTIP_WIDTH - 8.0)
	pos.y = minf(pos.y, view.y - height - 8.0)
	draw_rect(Rect2(pos, Vector2(TOOLTIP_WIDTH, height)), Color(0.08, 0.04, 0.12, 0.96))
	draw_rect(Rect2(pos, Vector2(TOOLTIP_WIDTH, height)), Color(0.7, 0.5, 0.9, 0.8), false, 1.5)
	draw_string(_font, pos + Vector2(10, 22), items.item_name(id), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1))
	draw_string(_font, pos + Vector2(10, 40), String(items.kind(id)).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.7, 0.8))
	var y := 60.0
	for line in stat_lines:
		draw_string(_font, pos + Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 1.0, 0.7))
		y += 16.0
	draw_multiline_string(_font, pos + Vector2(10, y + 4.0), flavor, HORIZONTAL_ALIGNMENT_LEFT, TOOLTIP_WIDTH - 20.0, 13, -1, Color(0.85, 0.8, 0.95))


func _origin(view: Vector2) -> Vector2:
	return Vector2((view.x - (COLUMNS * (SLOT + GAP) - GAP)) * 0.5, view.y * 0.5 - 130.0)


func _slot_rect(i: int) -> Rect2:
	var o := _origin(get_viewport_rect().size)
	if i < inventory.HOTBAR:
		return Rect2(o + Vector2(i * (SLOT + GAP), 3 * (SLOT + GAP) + 14.0), Vector2(SLOT, SLOT))
	var k := i - inventory.HOTBAR
	return Rect2(o + Vector2((k % COLUMNS) * (SLOT + GAP), floori(k / float(COLUMNS)) * (SLOT + GAP)), Vector2(SLOT, SLOT))


func _equip_origin(view: Vector2) -> Vector2:
	var o := _origin(view)
	return Vector2(o.x - EQUIP_COLUMNS * (SLOT + GAP) - 44.0, o.y)


func _equip_rect(k: int) -> Rect2:
	var o := _equip_origin(get_viewport_rect().size)
	return Rect2(o + Vector2(floori(k / 6.0) * (SLOT + GAP), (k % 6) * (SLOT + GAP)), Vector2(SLOT, SLOT))


func _slot_at(pos: Vector2) -> int:
	for i in inventory.SIZE:
		if _slot_rect(i).has_point(pos):
			return i
	for k in inventory.EQUIP_SLOTS.size():
		if _equip_rect(k).has_point(pos):
			return EQUIP_BASE + k
	return -1
