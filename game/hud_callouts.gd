# Purpose: the HUD's STYLED CALL-OUTS (polish1 B1; rule: no plain yellow call-out text anywhere): the round call-out
# in red chalk toward the top (item 51), the level-up banner saying what is new on the player card (item 54), the
# power-up taken (a medallion with its icon), and achievement cards that slide in from the top with their emblem and
# what they unlock (item 44, Steam-like). game/player_hud.gd owns one, ticks it and lets it draw.
# Dependencies: game/chalk_marks.gd, game/emblem_art.gd, game/icon_art.gd, game/ui_skin.gd, assets/fonts/LilitaOne.ttf,
# assets/fonts/Chewy-Regular.ttf.
extends RefCounted

const ChalkMarks = preload("res://game/chalk_marks.gd")
const EmblemArt = preload("res://game/emblem_art.gd")
const IconArt = preload("res://game/icon_art.gd")
const UiSkin = preload("res://game/ui_skin.gd")

const CHALK := Color(0.78, 0.07, 0.05, 0.95)
const GOLD := Color(1.0, 0.8, 0.32)
const BANNER_S := 3.2  # a banner's time on screen
const CARD_S := 5.0  # an achievement card's time on screen
const CARD := Vector2(440.0, 92.0)
const SLIDE_S := 0.35
const NUMBER_H := 92.0  # the chalk number's height (the same as the round counter: game/chalk_marks.gd keeps one size)

var _chunky: Font = load("res://assets/fonts/LilitaOne.ttf")
var _chalky: Font = load("res://assets/fonts/Chewy-Regular.ttf")
var _banner := {}  # {"kind": "round"|"level"|"power", ...; "t": seconds shown}
var _queue: Array = []  # banners waiting their turn
var _cards: Array = []  # achievement cards on screen (oldest first): {"name", "desc", "emblem", "unlocks", "t"}


# "ROUND 9" in red chalk with a line under it ("something big is wading in").
func round_call(number: int, line: String) -> void:
	_show({"kind": "round", "number": number, "line": line})


# The round is over ("ROUND 9 SURVIVED").
func round_done(number: int) -> void:
	_show({"kind": "round", "number": number, "line": "survived"})


# LEVEL UP: the level and what is new on the player card (each a short line), with the P hint.
func level_up(level: int, news: Array, key: String) -> void:
	_show({"kind": "level", "level": level, "news": news, "key": key})


# A power-up taken: its icon in a medallion of its colour and its name.
func power(text: String, color: Color, icon: String) -> void:
	_show({"kind": "power", "text": text.to_upper(), "color": color, "icon": icon}, true)


# An achievement card: name, description, its emblem (a def of data/achievements.json "emblems") and what it unlocks.
func achievement(achievement_name: String, desc: String, emblem: Dictionary, unlocks: String) -> void:
	_cards.append({"name": achievement_name, "desc": desc, "emblem": emblem, "unlocks": unlocks, "t": -0.4 * float(_cards.size())})


func _show(banner: Dictionary, now := false) -> void:
	banner["t"] = 0.0
	if _banner.is_empty() or now:
		_banner = banner
	elif _queue.size() < 4:
		_queue.append(banner)


func tick(delta: float) -> void:
	if not _banner.is_empty():
		_banner["t"] = float(_banner["t"]) + delta
		if float(_banner["t"]) >= BANNER_S:
			_banner = _queue.pop_front() if not _queue.is_empty() else {}
	for i in range(_cards.size() - 1, -1, -1):
		_cards[i]["t"] = float(_cards[i]["t"]) + delta
		if float(_cards[i]["t"]) >= CARD_S:
			_cards.remove_at(i)


func busy() -> bool:
	return not _banner.is_empty() or not _cards.is_empty()


func draw(ci: CanvasItem, view: Vector2) -> void:
	if not _banner.is_empty():
		var t := float(_banner["t"])
		var a := clampf(t / 0.2, 0.0, 1.0) * clampf((BANNER_S - t) / 0.5, 0.0, 1.0)
		var grow := 1.0 + 0.25 * maxf(0.0, 1.0 - t / 0.25)  # it lands with a little thump
		match String(_banner["kind"]):
			"round":
				_draw_round(ci, view, a, grow)
			"level":
				_draw_level(ci, view, a, grow)
			"power":
				_draw_power(ci, view, a, grow)
	var y := 18.0
	for card: Dictionary in _cards:
		var t := float(card["t"])
		if t < 0.0:
			continue
		var slide := clampf(t / SLIDE_S, 0.0, 1.0) * clampf((CARD_S - t) / SLIDE_S, 0.0, 1.0)
		var top := lerpf(-CARD.y - 10.0, y, ease(slide, -2.0))
		_draw_card(ci, Rect2(Vector2((view.x - CARD.x) * 0.5, top), CARD), card)
		y += (CARD.y + 8.0) * slide


# Red chalk across the top: ROUND, the number in chalk strokes, the line under it smaller.
func _draw_round(ci: CanvasItem, view: Vector2, a: float, grow: float) -> void:
	var color := Color(CHALK, CHALK.a * a)
	var word := "ROUND"
	var size := int(64.0 * grow)
	var word_w := _chalky.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var digits := str(int(_banner["number"])).length()
	var num_w := NUMBER_H * (ChalkMarks.DIGIT_W + 0.14) * float(digits)
	var left := (view.x - word_w - 24.0 - num_w) * 0.5
	var top := maxf(view.y * 0.1, 168.0)  # (polish1 item 151) under the power-up icons along the top (game/player_hud.gd, down to ~y 160)
	_chalk_text(ci, Vector2(left, top + NUMBER_H * 0.82), word, size, color)
	ChalkMarks.number(ci, Vector2(left + word_w + 24.0, top), int(_banner["number"]), NUMBER_H, color)
	var line := String(_banner["line"])
	if line != "":
		var line_size := int(34.0 * grow)
		_chalk_text(ci, Vector2((view.x - _chalky.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, line_size).x) * 0.5, top + NUMBER_H + 44.0), line, line_size, color)


# Chalk lettering: the word rubbed on three times, slightly apart, with a pale dusting.
func _chalk_text(ci: CanvasItem, at: Vector2, text: String, size: int, color: Color) -> void:
	ci.draw_string_outline(_chalky, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, 0.35 * color.a))
	ci.draw_string(_chalky, at + Vector2(1.6, -1.2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, color.a * 0.4))
	ci.draw_string(_chalky, at + Vector2(-1.5, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color, color.a * 0.4))
	ci.draw_string(_chalky, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


# A gold-edged ribbon: LEVEL n, what is new, "[P] player card".
func _draw_level(ci: CanvasItem, view: Vector2, a: float, grow: float) -> void:
	var news: Array = _banner["news"]
	var w := 520.0
	var h := 112.0 + 26.0 * float(news.size())
	var r := Rect2(Vector2((view.x - w) * 0.5, view.y * 0.12), Vector2(w, h))
	ci.draw_rect(r.grow(4.0), Color(GOLD, 0.35 * a))
	ci.draw_rect(r, Color(0.06, 0.05, 0.03, 0.9 * a))
	ci.draw_rect(r, Color(GOLD, a), false, 2.0)
	var big := int(46.0 * grow)
	var title := "LEVEL %d" % int(_banner["level"])
	ci.draw_string_outline(_chunky, Vector2(r.position.x, r.position.y + 58.0), title, HORIZONTAL_ALIGNMENT_CENTER, w, big, 8, Color(0, 0, 0, 0.8 * a))
	ci.draw_string(_chunky, Vector2(r.position.x, r.position.y + 58.0), title, HORIZONTAL_ALIGNMENT_CENTER, w, big, Color(GOLD, a))
	var y := r.position.y + 88.0
	for line: String in news:
		IconArt.draw(ci, "star", Rect2(Vector2(r.position.x + 40.0, y - 16.0), Vector2(20.0, 20.0)), GOLD, a)
		ci.draw_string(_chunky, Vector2(r.position.x + 68.0, y), line, HORIZONTAL_ALIGNMENT_LEFT, w - 90.0, 19, Color(UiSkin.TEXT, a))
		y += 26.0
	var hint := "Press %s for your player card" % String(_banner["key"])
	ci.draw_string(_chunky, Vector2(r.position.x, r.end.y - 14.0), hint, HORIZONTAL_ALIGNMENT_CENTER, w, 16, Color(UiSkin.TEXT_DIM, a))


# A medallion of the power-up's colour with its icon, the name beside it in chunky letters.
func _draw_power(ci: CanvasItem, view: Vector2, a: float, grow: float) -> void:
	var color: Color = _banner["color"]
	var text := String(_banner["text"])
	var size := int(50.0 * grow)
	var text_w := _chunky.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var radius := 40.0 * grow
	var left := (view.x - radius * 2.0 - 18.0 - text_w) * 0.5
	var c := Vector2(left + radius, view.y * 0.24)
	ci.draw_circle(c, radius + 4.0, Color(0, 0, 0, 0.6 * a))
	ci.draw_circle(c, radius, Color(color.darkened(0.55), 0.95 * a))
	ci.draw_arc(c, radius, 0.0, TAU, 40, Color(color, a), 4.0, true)
	IconArt.draw(ci, String(_banner["icon"]), Rect2(c - Vector2(radius, radius) * 0.62, Vector2(radius, radius) * 1.24), color.lightened(0.3), a)
	var at := Vector2(c.x + radius + 18.0, c.y + size * 0.35)
	ci.draw_string_outline(_chunky, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 9, Color(0, 0, 0, 0.8 * a))
	ci.draw_string(_chunky, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(color.lightened(0.2), a))


# Steam-like: dark card, the emblem on the left, ACHIEVEMENT UNLOCKED, its name, then what it gives.
func _draw_card(ci: CanvasItem, r: Rect2, card: Dictionary) -> void:
	UiSkin.panel(ci, r, UiSkin.INK, Color(GOLD, 0.7), 10)
	var emblem: Dictionary = card["emblem"]
	var c := r.position + Vector2(r.size.y * 0.5, r.size.y * 0.5)
	if emblem.is_empty():
		EmblemArt.draw(ci, "star", c, 30.0, Color(0.85, 0.85, 0.9), Color(0.4, 0.4, 0.45))
	else:
		EmblemArt.draw_def(ci, emblem, c, 32.0)
	var x := r.position.x + r.size.y + 6.0
	var w := r.size.x - r.size.y - 16.0
	ci.draw_string(_chunky, Vector2(x, r.position.y + 24.0), "ACHIEVEMENT UNLOCKED", HORIZONTAL_ALIGNMENT_LEFT, w, 14, GOLD)
	ci.draw_string(_chunky, Vector2(x, r.position.y + 50.0), String(card["name"]), HORIZONTAL_ALIGNMENT_LEFT, w, 22, UiSkin.TEXT)
	var under := String(card["unlocks"]) if String(card["unlocks"]) != "" else String(card["desc"])
	ci.draw_string(_chunky, Vector2(x, r.position.y + 74.0), under, HORIZONTAL_ALIGNMENT_LEFT, w, 15, UiSkin.TEXT_DIM)
