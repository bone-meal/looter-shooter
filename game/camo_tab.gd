# Purpose: the CAMOS tab of the player card (polish1 D5a, DECISIONS_SKINS.md: a camo is its own item, applied from its
# own tab): every camo the player owns as a card (its swatch, name in its tier colour, wear, pattern number, uses
# left), filtered by tier; pick one and the right side lists your rolled guns (holsters first, then the backpack),
# each wearing what it has now; pick a gun and it takes the camo (one use; a camo it wore before is replaced).
# Real game UI (game/ui_skin.gd). Draws and asks only: the session applies it.
# Dependencies: game/ui_skin.gd, game/camo_skin.gd, game/camo_icons.gd, game/item_icons.gd, game/tier_style.gd,
# core/camo_locker.gd (set `locker`), core/inventory_state.gd (set `inventory`), core/gun_db.gd (set `gun_db`).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const CamoSkin = preload("res://game/camo_skin.gd")
const CamoIcons = preload("res://game/camo_icons.gd")
const ItemIcons = preload("res://game/item_icons.gd")
const TierStyle = preload("res://game/tier_style.gd")
const GunStats = preload("res://core/gun_stats.gd")

signal apply_requested(camo_index: int, where: Dictionary)  # where = {"holster": i} or {"slot": i}

const FILTERS := [["", "All"], ["green", "Uncommon"], ["blue", "Rare"], ["purple", "Epic"], ["gold", "Legendary"], ["pony", "Pony"]]
const CARD := Vector2(214, 176)

var locker: RefCounted
var inventory: RefCounted
var gun_db: RefCounted

var _filter := ""
var _picked := -1  # index into locker.items
var _scroll := 0.0
var _gun_scroll := 0.0
var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font
var _t := 0.0


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(queue_redraw)


func refresh() -> void:
	if locker != null and _picked >= (locker.get("items") as Array).size():
		_picked = -1
	queue_redraw()


func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()  # swatches arrive one by one; gold / pony names shimmer


# Checks: press "pick n" (the n-th card shown), "gun holster i" / "gun slot i", "filter <tier>".
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
			var step := -60.0 if b.button_index == MOUSE_BUTTON_WHEEL_UP else 60.0
			if b.position.x > size.x * 0.62:
				_gun_scroll = maxf(_gun_scroll + step, 0.0)
			else:
				_scroll = maxf(_scroll + step, 0.0)
			accept_event()
		elif b.button_index == MOUSE_BUTTON_LEFT:
			for hit: Array in _hits:
				if (hit[0] as Rect2).has_point(b.position):
					(hit[1] as Callable).call()
					break
			accept_event()


func _shown() -> Array:
	var out: Array = []
	if locker == null:
		return out
	for i: int in locker.call("order"):
		var item: Dictionary = locker.get("items")[i]
		if _filter == "" or String(CamoSkin.look_of(String(item["id"])).get("tier", "")) == _filter:
			out.append(i)
	return out


func _draw() -> void:
	_hits.clear()
	if locker == null or gun_db == null:
		return
	var items: Array = locker.get("items")
	var left_w := size.x * 0.6
	draw_string(_font, Vector2(20, 34), "YOUR CAMOS  -  unboxed from crates: green goes on 3 guns, blue on 2, Epic and up on 1", HORIZONTAL_ALIGNMENT_LEFT, left_w, 17, UiSkin.TEXT_DIM)
	var fx := 20.0
	for f: Array in FILTERS:
		var r := Rect2(Vector2(fx, 48), Vector2(108, 32))
		var tier_id := String(f[0])
		UiSkin.pill(self, _font, r, String(f[1]), _filter == tier_id, r.has_point(_mouse), 14)
		_hits.append([r, func() -> void: _filter = tier_id; _scroll = 0.0, "filter " + (tier_id if tier_id != "" else "all")])
		fx += 114.0
	var shown := _shown()
	if shown.is_empty():
		draw_string(_font, Vector2(20, 140), "No camos yet. Open a crate (Cases tab): its second reel rolls a camo." if items.is_empty() else "No camos of this tier.", HORIZONTAL_ALIGNMENT_LEFT, left_w, 18, UiSkin.TEXT_DIM)
	var cols := maxi(int((left_w - 20.0) / (CARD.x + 12.0)), 1)
	var area := Rect2(Vector2(20, 96), Vector2(left_w - 20.0, size.y - 110.0))
	for n in shown.size():
		var i: int = shown[n]
		var item: Dictionary = items[i]
		var look := CamoSkin.look_of(String(item["id"]))
		var r := Rect2(area.position + Vector2(float(n % cols) * (CARD.x + 12.0), float(floori(float(n) / float(cols))) * (CARD.y + 12.0) - _scroll), CARD)
		if r.end.y < area.position.y or r.position.y > area.end.y:
			continue
		var tint := TierStyle.color(gun_db, String(look["tier"]), _t)
		var chosen := i == _picked
		UiSkin.panel(self, r, Color(0.07, 0.07, 0.1, 0.97), Color(tint, 0.95 if chosen or r.has_point(_mouse) else 0.45), 10)
		var pic := CamoIcons.swatch({"id": String(item["id"]), "wear": float(item["wear"]), "seed": int(item["seed"])})
		if pic != null:
			draw_texture_rect(pic, Rect2(r.position + Vector2(8, 6), Vector2(r.size.x - 16.0, 104)), false)
		draw_rect(Rect2(Vector2(r.position.x + 1.0, r.position.y + 112.0), Vector2(r.size.x - 2.0, 4.0)), tint)
		draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 134.0), String(look["name"]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 15, tint)
		draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 152.0), "%s  #%d" % [CamoSkin.wear_name(float(item["wear"])), int(item["seed"])], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 12, UiSkin.TEXT_DIM)
		draw_string(_font, Vector2(r.position.x + 10.0, r.position.y + 168.0), "%d use%s left" % [int(item["uses"]), "" if int(item["uses"]) == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 12, UiSkin.TEXT)
		var index := i
		_hits.append([r, func() -> void: _picked = index if _picked != index else -1, "pick %d" % n])
	_guns(Rect2(Vector2(left_w + 10.0, 30), Vector2(size.x - left_w - 30.0, size.y - 44.0)))


# The right side: your rolled guns to put the chosen camo on.
func _guns(area: Rect2) -> void:
	UiSkin.panel(self, area, Color(0.05, 0.05, 0.08, 0.95), UiSkin.EDGE, 12)
	if _picked < 0 or inventory == null:
		draw_string(_font, Vector2(area.position.x, area.get_center().y), "Pick a camo, then the gun it goes on.", HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 17, UiSkin.TEXT_DIM)
		return
	var item: Dictionary = locker.get("items")[_picked]
	var look := CamoSkin.look_of(String(item["id"]))
	draw_string(_font, Vector2(area.position.x + 16.0, area.position.y + 30.0), "Put %s on:" % String(look["name"]), HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 32.0, 18, TierStyle.color(gun_db, String(look["tier"]), _t))
	var rows: Array = []  # [where, gun]
	for h in int(inventory.get("holster_count")):
		var g: Dictionary = inventory.call("holster_gun", h)
		if not g.is_empty():
			rows.append([{"holster": h}, g])
	for s in int(inventory.get("slot_count")):
		var g: Dictionary = inventory.call("gun_at", s)
		if not g.is_empty():
			rows.append([{"slot": s}, g])
	if rows.is_empty():
		draw_string(_font, Vector2(area.position.x, area.get_center().y), "You carry no rolled guns.", HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 16, UiSkin.TEXT_DIM)
	var y := area.position.y + 48.0 - _gun_scroll
	for row: Array in rows:
		var r := Rect2(Vector2(area.position.x + 12.0, y), Vector2(area.size.x - 24.0, 64.0))
		y += 70.0
		if r.end.y < area.position.y + 40.0 or r.position.y > area.end.y:
			continue
		var gun: Dictionary = row[1]
		var tint := TierStyle.color(gun_db, String(gun["tier"]), _t)
		UiSkin.panel(self, r, Color(0.09, 0.09, 0.12), Color(tint, 0.9 if r.has_point(_mouse) else 0.35), 8)
		ItemIcons.draw_gun(self, gun, Rect2(r.position + Vector2(6, 4), Vector2(110, 56)), tint)
		draw_string(_font, Vector2(r.position.x + 124.0, r.position.y + 26.0), GunStats.display_name(gun_db, gun), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 130.0, 15, tint)
		var wearing := "no camo"
		if gun.get("camo") is Dictionary:
			wearing = "wears %s (replaced)" % String(CamoSkin.look_of(String(gun["camo"].get("id", ""))).get("name", "?"))
		var where_text := ("holster %d" % (int(row[0]["holster"]) + 1)) if (row[0] as Dictionary).has("holster") else "backpack"
		draw_string(_font, Vector2(r.position.x + 124.0, r.position.y + 48.0), "%s  -  %s" % [where_text, wearing], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 130.0, 12, UiSkin.TEXT_DIM)
		var where: Dictionary = row[0]
		var index := _picked
		_hits.append([r, func() -> void: apply_requested.emit(index, where), "gun %s %d" % ["holster" if where.has("holster") else "slot", int(where.values()[0])]])
