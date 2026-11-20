# Purpose: the board at the colosseum painting (polish1 C4, real game UI: game/ui_skin.gd). Three ticket cards sell
# their run: sample guns on their tier plates under beams of the tiers the run can give, with vague hints of how
# likely each is (core/colosseum_rules.gd ticket_odds, no numbers). Two ROTATING BANNER tickets (core/colosseum_banners.gd,
# the same two for everyone, new ones every 15 minutes) are shown like the shop's decks: an icon window, a title, a
# line and their boosts. Modifier pills (a banner's own are ticked and locked), Go in, Run it again (the last run
# bought here once more) and Back. Draws and asks only: the session pays and starts the run.
# Dependencies: game/ui_skin.gd, game/item_icons.gd, game/icon_art.gd, game/tier_style.gd, core/colosseum_rules.gd,
# core/colosseum_banners.gd, core/gun_db.gd. `open(points)` shows it; signals chosen / closed.
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const ItemIcons = preload("res://game/item_icons.gd")
const IconArt = preload("res://game/icon_art.gd")
const TierStyle = preload("res://game/tier_style.gd")

signal chosen(ticket: int, modifiers: PackedStringArray, banner: String)
signal closed

const SIZE := Vector2(1500, 1000)
const HOVER_HINT := "Point at a modifier to see what it does."
const GOLD := Color(1.0, 0.8, 0.35)

var rules: RefCounted  # core/colosseum_rules.gd, set before add_child
var banners: RefCounted  # core/colosseum_banners.gd
var gun_db: RefCounted  # core/gun_db.gd: tier colours and names, makers, guns
var tier_name := Callable()  # func(tier id) -> String

var _points := 0
var _ticket := 0
var _banner := ""  # the chosen banner's id ("" = a plain ticket)
var _ticked := PackedStringArray()
var _last: Array = []  # [ticket, modifiers, banner] of the last run bought here
var _hits: Array = []  # [Rect2, Callable, key, hint] rebuilt every draw
var _mouse := Vector2(-1, -1)
var _about := HOVER_HINT
var _font: Font = ThemeDB.fallback_font
var _t := 0.0


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)


# Shows the board for a player with that many points.
func open(points: int) -> void:
	_points = points
	visible = true
	set_process(true)
	_check_banner()
	queue_redraw()


func close() -> void:
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()  # beams shimmer, the countdown runs


# The ids of the ticked modifiers (a chosen banner's own included).
func picked() -> PackedStringArray:
	var entry := _banner_entry()
	return _ticked if entry.is_empty() else (banners.call("run_mods", entry, _ticked) as PackedStringArray)


# Test scripts: choose a ticket (or banner id) and tick modifiers as a player would.
func choose(ticket: int, modifiers: PackedStringArray, banner: String = "") -> void:
	_ticket = clampi(ticket, 0, int(rules.call("ticket_count")) - 1)
	_ticked = modifiers.duplicate()
	_banner = banner
	_check_banner()
	queue_redraw()


# Test scripts: press the control whose key starts with `text` ("go", "again", "back", "ticket 1", "banner 0", "mod id").
func press(text: String) -> bool:
	for hit: Array in _hits:
		if String(hit[2]).begins_with(text):
			(hit[1] as Callable).call()
			queue_redraw()
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
	var b := event as InputEventMouseButton
	if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		for hit: Array in _hits:
			if (hit[0] as Rect2).has_point(b.position):
				(hit[1] as Callable).call()
				break
		accept_event()


func _banner_entry() -> Dictionary:
	return {} if _banner == "" else (banners.call("find", _banner) as Dictionary)


func _now() -> float:
	return Time.get_unix_time_from_system()


func _check_banner() -> void:  # a banner that rotated off the board while it was open is dropped
	if _banner != "" and not bool(banners.call("is_live", _banner, _now())):
		_banner = ""


func _ticket_for(waves: int) -> int:
	for i in int(rules.call("ticket_count")):
		if int((rules.call("ticket", i) as Dictionary)["waves"]) == waves:
			return i
	return 0


func _named(tier: String) -> String:
	return String(tier_name.call(tier)) if tier_name.is_valid() else tier


func _hit(r: Rect2, act: Callable, key: String, hint: String = "") -> bool:
	_hits.append([r, act, key, hint])
	return r.has_point(_mouse)


func _draw() -> void:
	if rules == null:
		return
	_hits.clear()
	_check_banner()
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.02, 0.015, 0.01, 0.75))
	var r := Rect2((view - SIZE) * 0.5, SIZE)
	UiSkin.panel(self, r)
	var x0 := r.position.x + 24.0
	var w := r.size.x - 48.0
	draw_string(_font, r.position + Vector2(24, 50), "THE COLOSSEUM", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, UiSkin.TEXT)
	draw_string(_font, Vector2(x0, r.position.y + 48), "You have %d points" % _points, HORIZONTAL_ALIGNMENT_RIGHT, w, 18, GOLD)
	var y := UiSkin.header(self, _font, Vector2(x0, r.position.y + 70), w, "TICKETS", "every run ends on a boss and a reward chest")
	var cw := (w - 2 * 24.0) / 3.0
	for i in int(rules.call("ticket_count")):
		_ticket_card(Rect2(x0 + float(i) * (cw + 24.0), y, cw, 290.0), i)
	y += 304.0
	var left := int(banners.call("seconds_left", _now()))
	y = UiSkin.header(self, _font, Vector2(x0, y), w, "BANNERS", "new ones in %d:%02d, the same for the whole party" % [floori(left / 60.0), left % 60])
	var pair: Array = banners.call("live", _now())
	var bw := (w - 24.0) / 2.0
	for i in pair.size():
		_banner_card(Rect2(x0 + float(i) * (bw + 24.0), y, bw, 140.0), pair[i], i)
	y += 154.0
	y = UiSkin.header(self, _font, Vector2(x0, y), w, "MODIFIERS", "each makes the run harder and the loot better")
	_about = HOVER_HINT
	var mods: Array = rules.call("modifiers")
	var locked: Array = _banner_entry().get("mods", [])
	var mw := (w - 4 * 12.0) / 5.0
	for i in mods.size():
		var mod: Dictionary = mods[i]
		var id := String(mod["id"])
		var cell := Rect2(x0 + float(i % 5) * (mw + 12.0), y + float(floori(i / 5.0)) * 40.0, mw, 32.0)
		var on := _ticked.has(id) or locked.has(id)
		var label := "%s%s  +%d%%" % ["(banner) " if locked.has(id) else "", String(mod["name"]), roundi(float(mod["loot"]) * 100.0)]
		var over := _hit(cell, (func() -> void: pass) if locked.has(id) else _toggle.bind(id), "mod " + id)
		UiSkin.pill(self, _font, cell, label, on, over, 14)
		if over:
			_about = "%s: %s" % [String(mod["name"]), String(mod["desc"])]
	y += ceilf(float(mods.size()) / 5.0) * 40.0 + 6.0
	draw_string(_font, Vector2(x0, y + 18.0), _about, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Color(0.95, 0.85, 0.6))
	var entry: Dictionary = rules.call("ticket", _ticket)
	var price := int(entry["price"])
	var chosen_mods := picked()
	var summary := "%s: %d waves" % [String(_banner_entry().get("title", entry["name"])), int(entry["waves"])]
	if not chosen_mods.is_empty():
		summary += ", %d modifiers, loot chances x%.2f" % [chosen_mods.size(), float(rules.call("loot_mult", chosen_mods))]
	draw_string(_font, Vector2(x0, y + 48.0), summary, HORIZONTAL_ALIGNMENT_CENTER, w, 17, UiSkin.TEXT)
	var by := r.end.y - 70.0
	var go := Rect2(r.get_center().x - 170.0, by, 340.0, 48.0)
	var can := _points >= price
	var over_go := _hit(go, func() -> void: _buy(_ticket, chosen_mods, _banner), "go") if can else go.has_point(_mouse)
	UiSkin.pill(self, _font, go, "Go in  (%d points)" % price if can else "Go in: %d points needed" % price, can, over_go, 19)
	var again := Rect2(go.position.x - 420.0, by + 4.0, 390.0, 40.0)
	if not _last.is_empty():
		var over_again := _hit(again, func() -> void: _buy(int(_last[0]), _last[1], String(_last[2])), "again")
		UiSkin.pill(self, _font, again, "Run it again: " + _last_name(), false, over_again, 15)
	var back := Rect2(go.end.x + 30.0, by + 4.0, 200.0, 40.0)
	UiSkin.pill(self, _font, back, "Back", false, _hit(back, func() -> void: closed.emit(), "back"), 15)


func _buy(ticket: int, mods: PackedStringArray, banner: String) -> void:
	_last = [ticket, mods, banner]
	chosen.emit(ticket, mods, banner)


func _last_name() -> String:
	var banner := String(_last[2])
	if banner != "" and bool(banners.call("is_live", banner, _now())):
		return String((banners.call("find", banner) as Dictionary)["title"])
	var plain := String((rules.call("ticket", int(_last[0])) as Dictionary)["name"])
	var mods: PackedStringArray = _last[1]
	return plain + ("" if mods.is_empty() else " + %d mods" % mods.size()) + (" (banner gone)" if banner != "" else "")


func _toggle(id: String) -> void:
	if _ticked.has(id):
		_ticked.remove_at(_ticked.find(id))
	else:
		_ticked.append(id)


func _pick_ticket(i: int) -> void:
	_ticket = i
	_banner = ""


func _pick_banner(id: String, waves: int) -> void:
	_banner = id
	_ticket = _ticket_for(waves)


# A ticket card: beams of its tiers rising behind three sample guns, its name and price, then the hints.
func _ticket_card(card: Rect2, i: int) -> void:
	var entry: Dictionary = rules.call("ticket", i)
	var waves := int(entry["waves"])
	var odds: Array = rules.call("ticket_odds", waves)
	var over := _hit(card, _pick_ticket.bind(i), "ticket %d" % i)
	var chosen_here := _banner == "" and _ticket == i
	UiSkin.panel(self, card, UiSkin.INK_DEEP, Color(GOLD, 0.95) if chosen_here else (Color(1, 1, 1, 0.5) if over else UiSkin.EDGE), 12)
	var stage := Rect2(card.position + Vector2(14, 14), Vector2(card.size.x - 28.0, 120.0))
	var samples: Array = (rules.get("cfg") as Dictionary).get("board", {}).get("samples", [])
	var guns: Array = samples[i] if i < samples.size() else ["pistol_basic", "smg", "revolver"]
	var gw := (stage.size.x - 2 * 10.0) / 3.0
	for g in 3:
		var tier := String(odds[clampi(odds.size() - 3 + g, 0, odds.size() - 1)]["tier"])  # the best three it can give
		var plate := Rect2(stage.position.x + float(g) * (gw + 10.0), stage.end.y - 62.0, gw, 62.0)
		var tint := TierStyle.color(gun_db, tier, _t + float(g))
		var tall := 40.0 + 18.0 * float(odds.find_custom(func(e: Dictionary) -> bool: return String(e["tier"]) == tier))  # rarer, taller
		var beam := Rect2(plate.get_center().x - 10.0, plate.position.y - tall, 20.0, tall + 20.0)
		var top := Color(tint, 0.0)
		var low := Color(tint, 0.55 + 0.1 * sin(_t * 3.0 + float(g)))
		draw_polygon(PackedVector2Array([beam.position, Vector2(beam.end.x, beam.position.y), beam.end, Vector2(beam.position.x, beam.end.y)]), PackedColorArray([top, top, low, low]))
		ItemIcons.plate(self, plate, gun_db, tier, _t)
		ItemIcons.draw(self, String(guns[g % guns.size()]), plate.grow(-8.0), Color.WHITE)
	var ty := stage.end.y + 34.0
	draw_string(_font, Vector2(card.position.x + 16.0, ty), String(entry["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiSkin.TEXT)
	draw_string(_font, Vector2(card.position.x, ty), "%d points  " % int(entry["price"]), HORIZONTAL_ALIGNMENT_RIGHT, card.size.x - 4.0, 17, GOLD if _points >= int(entry["price"]) else UiSkin.BAD)
	var ly := ty + 26.0
	for k in range(odds.size() - 1, -1, -1):  # best first
		var e: Dictionary = odds[k]
		var tint := TierStyle.color(gun_db, String(e["tier"]), _t)
		draw_circle(Vector2(card.position.x + 22.0, ly - 5.0), 5.0, tint)
		var label := _named(String(e["tier"]))
		draw_string(_font, Vector2(card.position.x + 34.0, ly), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, tint)
		draw_string(_font, Vector2(card.position.x + 40.0 + _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x, ly), String(e["word"]), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 60.0, 15, UiSkin.TEXT_DIM)
		ly += 22.0


# A banner card, like the shop's decks: its icon in a coloured window with a gold rim, the title, its line, and what
# it boosts; it lifts and glows under the mouse.
func _banner_card(card: Rect2, banner: Dictionary, i: int) -> void:
	var id := String(banner["id"])
	var colour := Color(String(banner.get("color", "#ffd060")))
	var over := _hit(card, _pick_banner.bind(id, int(banner["waves"])), "banner %d" % i)
	var lifted := card.grow(4.0) if over else card
	var chosen_here := _banner == id
	UiSkin.panel(self, lifted, Color(colour.darkened(0.82), 0.98), Color(GOLD, 0.95) if chosen_here else (Color(colour, 0.9) if over else Color(colour, 0.4)), 16)
	var window := Rect2(lifted.position + Vector2(12, 12), Vector2(lifted.size.y - 24.0, lifted.size.y - 24.0))
	var deep := colour.darkened(0.5)
	draw_polygon(PackedVector2Array([window.position, Vector2(window.end.x, window.position.y), window.end, Vector2(window.position.x, window.end.y)]), PackedColorArray([colour, colour, deep, deep]))
	IconArt.draw(self, String(banner.get("icon", "star")), window.grow(-18.0), Color(1, 1, 1))
	UiSkin.outline(self, window, GOLD, 10, 3)
	var tx := window.end.x + 18.0
	var tw := lifted.end.x - tx - 14.0
	draw_string_outline(_font, Vector2(tx, lifted.position.y + 40.0), String(banner["title"]), HORIZONTAL_ALIGNMENT_LEFT, tw, 24, 5, Color(0, 0, 0, 0.8))
	draw_string(_font, Vector2(tx, lifted.position.y + 40.0), String(banner["title"]), HORIZONTAL_ALIGNMENT_LEFT, tw, 24, Color.WHITE)
	draw_multiline_string(_font, Vector2(tx, lifted.position.y + 64.0), String(banner.get("line", "")), HORIZONTAL_ALIGNMENT_LEFT, tw, 15, 2, UiSkin.TEXT_DIM)
	var price := int((rules.call("ticket", _ticket_for(int(banner["waves"]))) as Dictionary)["price"])
	var tags := PackedStringArray(["%d waves" % int(banner["waves"])])
	for mod: String in banner.get("mods", []):
		tags.append(String((rules.call("modifier", mod) as Dictionary).get("name", mod)))
	tags.append_array(_boost_tags(banner))
	draw_string(_font, Vector2(tx, lifted.end.y - 16.0), "  ·  ".join(tags), HORIZONTAL_ALIGNMENT_LEFT, tw - 130.0, 14, colour.lightened(0.45))
	draw_string(_font, Vector2(tx, lifted.end.y - 16.0), "%d points" % price, HORIZONTAL_ALIGNMENT_RIGHT, tw, 17, GOLD if _points >= price else UiSkin.BAD)


# What a banner boosts, in words for its card.
func _boost_tags(banner: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var boosts: Dictionary = banner.get("boost", {})
	if boosts.has("maker"):
		out.append("mostly %s guns" % String((gun_db.get("makers") as Dictionary).get(String(boosts["maker"]), {}).get("name", boosts["maker"])))
	if boosts.has("body"):
		out.append("mostly %ss" % String((gun_db.get("bodies") as Dictionary).get(String(boosts["body"]), {}).get("name", boosts["body"])))
	for key: String in ["luck", "armour", "treasure", "pony"]:
		if boosts.has(key):
			out.append("%s x%s" % [{"luck": "luck", "armour": "armour", "treasure": "treasure", "pony": "pony"}[key], str(snappedf(float(boosts[key]), 0.01))])
	if boosts.has("chest_guns"):
		out.append("+%d gun in the chest" % int(boosts["chest_guns"]))
	return out
