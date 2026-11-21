# Purpose: the KNIVES tab of the player card (polish1 D5b, diary/DESIGN_KNIVES.md): every skinned knife the player
# owns as a card (its picture, finish name in its tier colour, knife type, chase / phase / gem, level), the carried one
# marked; pick one and the right side shows it large with its pattern number, wear, level and kills toward the next,
# and its power at its present strength; CARRY IT puts it in hand instead of the character's own knife, which the
# bottom button brings back. Real game UI (game/ui_skin.gd). Draws and asks only: the session equips.
# Dependencies: game/ui_skin.gd, game/camo_icons.gd, game/camo_skin.gd, game/tier_style.gd, game/knife_models.gd,
# core/knife_locker.gd (set `locker`), core/gun_db.gd (set `gun_db`).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const CamoIcons = preload("res://game/camo_icons.gd")
const CamoSkin = preload("res://game/camo_skin.gd")
const TierStyle = preload("res://game/tier_style.gd")
const KnifeModels = preload("res://game/knife_models.gd")

signal equip_requested(index: int)  # -1 = back to the character's own knife

const CARD := Vector2(232, 150)

var locker: RefCounted
var gun_db: RefCounted
var own_knife := ""  # the character's rolled knife type (for the bottom button)

var _picked := -1
var _scroll := 0.0
var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font
var _t := 0.0


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP


func refresh() -> void:
	if locker != null and _picked >= (locker.get("items") as Array).size():
		_picked = -1
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()


# Checks: "pick n" (the n-th card shown), "carry", "own".
func press(key: String) -> bool:
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
	var b := event as InputEventMouseButton
	if b != null and b.pressed:
		if b.button_index == MOUSE_BUTTON_WHEEL_UP or b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll = maxf(_scroll + (-60.0 if b.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0), 0.0)
			accept_event()
		elif b.button_index == MOUSE_BUTTON_LEFT:
			for hit: Array in _hits:
				if (hit[0] as Rect2).has_point(b.position):
					(hit[1] as Callable).call()
					break
			accept_event()


func _rules() -> RefCounted:
	return locker.get("rules")


func _tier_name(tier: String) -> String:
	return String(gun_db.tier(tier).get("name", tier)) if gun_db != null else tier


func _draw() -> void:
	_hits.clear()
	if locker == null or gun_db == null:
		return
	var items: Array = locker.get("items")
	var rules := _rules()
	var left_w := size.x * 0.58
	draw_string(_font, Vector2(20, 34), "YOUR KNIVES  -  from crates and bosses; each levels up from the kills made with it", HORIZONTAL_ALIGNMENT_LEFT, left_w, 17, UiSkin.TEXT_DIM)
	if items.is_empty():
		draw_string(_font, Vector2(20, 90), "No skinned knives yet. Silver and Gold crates (and bosses) can give one: a rare special item.", HORIZONTAL_ALIGNMENT_LEFT, left_w, 18, UiSkin.TEXT_DIM)
	var area := Rect2(Vector2(20, 54), Vector2(left_w - 20.0, size.y - 70.0))
	var cols := maxi(int(area.size.x / (CARD.x + 12.0)), 1)
	var order: Array = locker.call("order")
	for n in order.size():
		var i: int = order[n]
		var item: Dictionary = items[i]
		var fin: Dictionary = rules.call("finish", String(item["finish"]))
		var tier := String(fin.get("tier", "blue"))
		var tint := TierStyle.color(gun_db, tier, _t)
		var r := Rect2(area.position + Vector2(float(n % cols) * (CARD.x + 12.0), float(floori(float(n) / float(cols))) * (CARD.y + 12.0) - _scroll), CARD)
		if r.end.y < area.position.y or r.position.y > area.end.y:
			continue
		var chosen := i == _picked
		UiSkin.panel(self, r, Color(0.07, 0.07, 0.1, 0.97), Color(tint, 0.95 if chosen or r.has_point(_mouse) else 0.45), 10)
		var pic := CamoIcons.knife(item, self)
		if pic != null:
			draw_texture_rect(pic, Rect2(r.position + Vector2(8, 4), Vector2(r.size.x - 16.0, 84)), false)
		draw_rect(Rect2(Vector2(r.position.x + 1.0, r.position.y + 90.0), Vector2(r.size.x - 2.0, 3.0)), tint)
		draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 110.0), String(fin.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 60.0, 15, tint)
		draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 110.0), "LV %d" % int(rules.call("level", item)), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 20.0, 13, UiSkin.TEXT)
		var look: Dictionary = rules.call("pattern_look", item)
		var chase := String(look.get("name", ""))
		draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 128.0), String(KnifeModels.db().name_of(String(item["type"]))) + ("   " + chase if chase != "" else ""), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 12, UiSkin.ACCENT if int(look.get("variant", 0)) > 0 else UiSkin.TEXT_DIM)
		if i == int(locker.get("on")):
			draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 144.0), "CARRIED", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiSkin.GOOD)
		var index := i
		_hits.append([r, func() -> void: _picked = index if _picked != index else -1, "pick %d" % n])
	_detail(Rect2(Vector2(left_w + 10.0, 30), Vector2(size.x - left_w - 30.0, size.y - 44.0)))


func _detail(area: Rect2) -> void:
	UiSkin.panel(self, area, Color(0.05, 0.05, 0.08, 0.95), UiSkin.EDGE, 12)
	var items: Array = locker.get("items")
	var own_r := Rect2(Vector2(area.position.x + 16.0, area.end.y - 54.0), Vector2(area.size.x - 32.0, 40))
	var carrying := int(locker.get("on")) >= 0
	UiSkin.pill(self, _font, own_r, "Carry my own knife (%s)" % String(KnifeModels.db().name_of(own_knife)) if carrying else "Carrying your own knife (%s)" % String(KnifeModels.db().name_of(own_knife)), not carrying, own_r.has_point(_mouse) and carrying, 14)
	_hits.append([own_r, func() -> void: equip_requested.emit(-1), "own"])
	if _picked < 0 or _picked >= items.size():
		draw_string(_font, Vector2(area.position.x, area.get_center().y), "Pick a knife.", HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 17, UiSkin.TEXT_DIM)
		return
	var rules := _rules()
	var item: Dictionary = items[_picked]
	var fin: Dictionary = rules.call("finish", String(item["finish"]))
	var fam: Dictionary = rules.call("family", item)
	var tier := String(fin.get("tier", "blue"))
	var tint := TierStyle.color(gun_db, tier, _t)
	var x := area.position.x + 18.0
	var w := area.size.x - 36.0
	var pic := CamoIcons.knife(item, self)
	if pic != null:
		draw_texture_rect(pic, Rect2(Vector2(x, area.position.y + 8.0), Vector2(w, w * 0.5)), false)
	var y := area.position.y + 16.0 + w * 0.5
	draw_string(_font, Vector2(x, y), String(fin.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w, 24, tint)
	y += 24.0
	var look: Dictionary = rules.call("pattern_look", item)
	draw_string(_font, Vector2(x, y), "%s  %s  -  %s" % [_tier_name(tier), String(KnifeModels.db().name_of(String(item["type"]))), String(rules.cfg["collections"].get(String(fin.get("collection", "")), ""))], HORIZONTAL_ALIGNMENT_LEFT, w, 14, UiSkin.TEXT)
	y += 22.0
	var chase := String(look.get("name", ""))
	draw_string(_font, Vector2(x, y), "%s%s  -  pattern %d  -  %s" % [String(fam.get("name", "")), ("  " + chase) if chase != "" else "", int(item["pattern"]), CamoSkin.wear_name(float(item["wear"]))], HORIZONTAL_ALIGNMENT_LEFT, w, 14, UiSkin.ACCENT if int(look.get("variant", 0)) > 0 else UiSkin.TEXT_DIM)
	y += 30.0
	var lv := int(rules.call("level", item))
	var prog: Array = rules.call("level_progress", item)
	draw_string(_font, Vector2(x, y), "LEVEL %d / %d" % [lv, int(rules.call("max_level"))], HORIZONTAL_ALIGNMENT_LEFT, w, 16, UiSkin.TEXT)
	draw_string(_font, Vector2(x, y), "%d kills" % int(item["kills"]), HORIZONTAL_ALIGNMENT_RIGHT, w, 13, UiSkin.TEXT_DIM)
	y += 8.0
	UiSkin.bar(self, Rect2(Vector2(x, y), Vector2(w, 8)), 1.0 if int(prog[1]) == 0 else float(prog[0]) / float(prog[1]), tint)
	y += 22.0
	draw_string(_font, Vector2(x, y), "next level: %d more kills" % (int(prog[1]) - int(prog[0])) if int(prog[1]) > 0 else "top level", HORIZONTAL_ALIGNMENT_LEFT, w, 12, UiSkin.TEXT_DIM)
	draw_string(_font, Vector2(x, y), "damage x%.2f" % float(rules.call("damage_mult", item)), HORIZONTAL_ALIGNMENT_RIGHT, w, 12, UiSkin.TEXT_DIM)
	y += 30.0
	var pw: Dictionary = rules.call("power", item)
	draw_string(_font, Vector2(x, y), "POWER  -  %s" % String(pw.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, w, 16, UiSkin.ACCENT)
	draw_string(_font, Vector2(x, y), "%d%%" % roundi(float(rules.call("power_scale", item)) * 100.0), HORIZONTAL_ALIGNMENT_RIGHT, w, 13, UiSkin.TEXT_DIM)
	y += 8.0
	draw_multiline_string(_font, Vector2(x, y + 16.0), String(rules.call("power_text", item)), HORIZONTAL_ALIGNMENT_LEFT, w, 14, 4, UiSkin.TEXT)
	var carry_r := Rect2(Vector2(x, own_r.position.y - 54.0), Vector2(w, 44))
	var is_on := _picked == int(locker.get("on"))
	UiSkin.pill(self, _font, carry_r, "CARRIED" if is_on else "CARRY IT", is_on, carry_r.has_point(_mouse) and not is_on, 17)
	var index := _picked
	_hits.append([carry_r, func() -> void: equip_requested.emit(index), "carry"])
