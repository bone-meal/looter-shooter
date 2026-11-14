# Purpose: the card vending machine's shop window: big pictures to click instead of text. Top: the logo, your chips and
# your unopened packs. Row 1: one pack, a fan of 5, a fan of 10 and the box of 50, each with its price on a chip pill;
# they lift and glow under the mouse and bounce when bought, and a "+5 PACKS!" pops up. Row 2: the five starter decks,
# shown by their leader's picture. The published odds sit behind a small "Odds" button. Collects clicks only;
# game/tcg/card_shop.gd buys.
# Dependencies: game/chip_art.gd, game/tcg/card_face.gd (fonts), assets/tcg/pack.png, box.png, logo.png, art/<leader>.jpg.
extends Control

const ChipArt = preload("res://game/chip_art.gd")
const CardFace = preload("res://game/tcg/card_face.gd")

signal buy(item: String)
signal closed

const GOLD := Color(1.0, 0.82, 0.38)
const BASE_HEIGHT := 648.0


# One clickable picture with a name and a price pill; lifts under the mouse.
class Tile:
	extends Control
	signal clicked
	var picture: Texture2D
	var fan := 1  # how many packs to draw fanned out (pack tiles)
	var art_cover := false  # picture fills a rounded window (starter decks)
	var title := ""
	var title_size := 18  # one size for a whole row, so names line up
	var price := 0
	var _hover := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void: create_tween().tween_method(_set_hover, _hover, 1.0, 0.12))
		mouse_exited.connect(func() -> void: create_tween().tween_method(_set_hover, _hover, 0.0, 0.15))

	func _set_hover(v: float) -> void:
		_hover = v
		pivot_offset = size * 0.5
		scale = Vector2.ONE * (1.0 + 0.07 * v)
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			clicked.emit()
			accept_event()

	func bounce() -> void:
		var t := create_tween()
		t.tween_property(self, "scale", Vector2.ONE * 1.18, 0.08)
		t.tween_property(self, "scale", Vector2.ONE * (1.0 + 0.07 * _hover), 0.18).set_trans(Tween.TRANS_BACK)

	func _draw() -> void:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(1, 1, 1, 0.04 + 0.08 * _hover)
		glow.set_corner_radius_all(16)
		glow.shadow_color = Color(1.0, 0.5, 0.8, 0.55 * _hover)
		glow.shadow_size = int(18 * _hover)
		draw_style_box(glow, Rect2(Vector2.ZERO, size))
		var pic := Rect2(10, 8, size.x - 20, size.y - 84)
		if picture != null:
			if art_cover:
				var ts := picture.get_size()
				var fit := maxf(pic.size.x / ts.x, pic.size.y / ts.y)
				draw_texture_rect_region(picture, pic, Rect2((ts - pic.size / fit) * 0.5, pic.size / fit))
				var rim := StyleBoxFlat.new()
				rim.draw_center = false
				rim.border_color = GOLD
				rim.set_border_width_all(3)
				rim.set_corner_radius_all(10)
				draw_style_box(rim, pic)
			else:
				var ts2 := picture.get_size()
				var h := pic.size.y
				var w := h * ts2.x / ts2.y
				for i in fan:  # fanned packs, the front one last
					var off := float(i) - float(fan - 1) * 0.5
					var r := Rect2(pic.position.x + (pic.size.x - w) * 0.5 + off * minf(18.0, pic.size.x * 0.5 / maxf(fan, 1)), pic.position.y + absf(off) * 3.0, w, h)
					draw_set_transform(r.get_center(), off * 0.06, Vector2.ONE)
					draw_texture_rect(picture, Rect2(-r.size * 0.5, r.size), false)
				draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		var f := CardFace.font("title")
		var fs := title_size
		var tw := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var baseline := size.y - 48.0  # the name sits clear above the price pill
		draw_string_outline(f, Vector2((size.x - tw) * 0.5, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2((size.x - tw) * 0.5, baseline), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var pill := Rect2(size.x * 0.5 - 62, size.y - 34, 124, 28)
		var p := StyleBoxFlat.new()
		p.bg_color = Color(0.12, 0.02, 0.06)
		p.border_color = GOLD
		p.set_border_width_all(2)
		p.set_corner_radius_all(14)
		draw_style_box(p, pill)
		ChipArt.draw(self, pill.position + Vector2(16, 14), 10.0)
		var nf := CardFace.font("number")
		var txt := _thousands(price)
		draw_string(nf, pill.position + Vector2(32, 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, GOLD)

	static func _thousands(n: int) -> String:
		var s := str(n)
		return s if s.length() <= 3 else s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)


var _chips := Label.new()
var _packs := Label.new()
var _tiles: Dictionary = {}  # item -> Tile
var _odds := PanelContainer.new()
var _toast := Label.new()
var _panel := PanelContainer.new()


func _ready() -> void:
	visible = false
	_fit()
	get_viewport().size_changed.connect(_fit)


# Laid out for a 648-pixel-high window and scaled up (like the card table).
func _fit() -> void:
	var view := get_viewport_rect().size
	var k := clampf(view.y / BASE_HEIGHT, 1.0, 4.0)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	scale = Vector2(k, k)
	size = view / k


# cfg = data/tcg/packs.json; starters = data/tcg/starters.json "starters"; leaders = id -> {"name"}.
func setup(cfg: Dictionary, starters: Dictionary, leaders: Dictionary) -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.0, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.02, 0.08, 0.97)
	back.border_color = Color(1.0, 0.25, 0.65)
	back.set_border_width_all(4)
	back.set_corner_radius_all(22)
	back.shadow_color = Color(1.0, 0.2, 0.6, 0.5)
	back.shadow_size = 22
	back.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel", back)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	# header: logo + name, then chips and packs, then the close button
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	v.add_child(head)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/tcg/logo.png") if ResourceLoader.exists("res://assets/tcg/logo.png") else null
	logo.custom_minimum_size = Vector2(64, 64)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(logo)
	var name_label := Label.new()
	name_label.text = "CARD MACHINE"
	name_label.add_theme_font_override("font", CardFace.font("title"))
	name_label.add_theme_font_size_override("font_size", 30)
	name_label.add_theme_color_override("font_color", GOLD)
	name_label.add_theme_color_override("font_outline_color", Color(0.4, 0.0, 0.2))
	name_label.add_theme_constant_override("outline_size", 8)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)
	for l: Label in [_chips, _packs]:
		l.add_theme_font_override("font", CardFace.font("number"))
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_color_override("font_color", Color.WHITE)
	head.add_child(ChipArt.row(_chips))
	var pack_icon := TextureRect.new()
	pack_icon.texture = load("res://assets/tcg/pack.png") if ResourceLoader.exists("res://assets/tcg/pack.png") else null
	pack_icon.custom_minimum_size = Vector2(22, 36)
	pack_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pack_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(pack_icon)
	head.add_child(_packs)
	var odds_btn := Button.new()
	odds_btn.text = "Odds"
	odds_btn.pressed.connect(func() -> void: _odds.visible = not _odds.visible)
	head.add_child(odds_btn)
	var close_btn := Button.new()
	close_btn.text = "  X  "
	close_btn.pressed.connect(func() -> void: closed.emit())
	head.add_child(close_btn)
	# row 1: packs
	var pack_tex: Texture2D = load("res://assets/tcg/pack.png") if ResourceLoader.exists("res://assets/tcg/pack.png") else null
	var box_tex: Texture2D = load("res://assets/tcg/box.png") if ResourceLoader.exists("res://assets/tcg/box.png") else null
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 14)
	row1.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row1)
	var prices: Dictionary = cfg["prices"]
	for item: Array in [["single", "1 PACK", 1], ["bundle_5", "5 PACKS", 3], ["bundle_10", "10 PACKS", 5], ["box", "BOX OF 50", 1]]:
		var t := Tile.new()
		t.picture = box_tex if item[0] == "box" else pack_tex
		t.fan = int(item[2])
		t.title = String(item[1])
		t.price = int(prices[String(item[0])])
		t.custom_minimum_size = Vector2(170, 228)
		var id := String(item[0])
		t.clicked.connect(func() -> void: buy.emit(id))
		row1.add_child(t)
		_tiles[id] = t
	# row 2: starter decks by their leader
	var title2 := Label.new()
	title2.text = "STARTER DECKS"
	title2.add_theme_font_override("font", CardFace.font("title"))
	title2.add_theme_font_size_override("font_size", 20)
	title2.add_theme_color_override("font_color", GOLD)
	v.add_child(title2)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row2)
	var longest := 0.0
	for sid: String in starters:
		longest = maxf(longest, CardFace.font("title").get_string_size(String(starters[sid]["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x)
	var deck_size := 16 if longest <= 140.0 else int(16.0 * 140.0 / longest)
	for sid: String in starters:
		var d: Dictionary = starters[sid]
		var t := Tile.new()
		t.title_size = deck_size
		var path := "res://assets/tcg/art/%s.jpg" % d["leader"]
		t.picture = load(path) if ResourceLoader.exists(path) else null
		t.art_cover = true
		t.title = String(d["name"])
		t.price = int(prices["starter"])
		t.custom_minimum_size = Vector2(150, 166)
		var key := "starter:" + sid
		t.clicked.connect(func() -> void: buy.emit(key))
		row2.add_child(t)
		_tiles[key] = t
	# odds board (hidden until asked) and the pop-up after a buy
	_odds.visible = false
	_odds.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_odds.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_odds.offset_right = -20
	var ob := StyleBoxFlat.new()
	ob.bg_color = Color(0.05, 0.02, 0.05, 0.96)
	ob.border_color = GOLD
	ob.set_border_width_all(2)
	ob.set_corner_radius_all(12)
	ob.set_content_margin_all(14)
	_odds.add_theme_stylebox_override("panel", ob)
	var ol := Label.new()
	ol.text = _odds_text(cfg)
	ol.add_theme_font_size_override("font_size", 14)
	_odds.add_child(ol)
	add_child(_odds)
	_toast.add_theme_font_override("font", CardFace.font("title"))
	_toast.add_theme_font_size_override("font_size", 40)
	_toast.add_theme_color_override("font_color", GOLD)
	_toast.add_theme_color_override("font_outline_color", Color(0.45, 0.0, 0.2))
	_toast.add_theme_constant_override("outline_size", 12)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)


func open(chips: int, packs: int) -> void:
	visible = true
	_odds.visible = false
	refresh(chips, packs)


func refresh(chips: int, packs: int) -> void:
	_chips.text = Tile._thousands(chips)
	_packs.text = str(packs)


# A bought item bounces and its pop-up rises; a refusal shakes the panel and says why in the pop-up.
func show_bought(item: String, text: String) -> void:
	if _tiles.has(item):
		(_tiles[item] as Tile).bounce()
	_pop(text, GOLD)


func show_refused(text: String) -> void:
	_pop(text, Color(1.0, 0.45, 0.45))
	var t := create_tween()
	var x := _panel.position.x
	for i in 3:
		t.tween_property(_panel, "position:x", x + 8.0, 0.04)
		t.tween_property(_panel, "position:x", x - 8.0, 0.04)
	t.tween_property(_panel, "position:x", x, 0.04)


func _pop(text: String, color: Color) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.position.y = size.y * 0.5 - 20.0
	_toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_property(_toast, "position:y", size.y * 0.5 - 90.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(_toast, "modulate:a", 0.0, 0.9).set_delay(0.5)


static func _odds_text(cfg: Dictionary) -> String:
	var std: Dictionary = cfg["standard"]
	var lines: PackedStringArray = ["ODDS", ""]
	lines.append("Cards 1-%d" % (int(std["cards"]) - 1))
	for r: String in std["slot"]:
		lines.append("  %s  %s %%" % [r.capitalize(), str(std["slot"][r])])
	lines.append("Last card")
	for r: String in std["last"]:
		lines.append("  %s  %s %%" % [r.capitalize(), str(std["last"][r])])
	lines.append("Leader: like an epic")
	lines.append("Rainbow foil %s %%" % str(float(cfg["foil"]["rainbow"]) * 100.0))
	lines.append("Pony foil %s %%" % str(float(cfg["foil"]["pony"]) * 100.0))
	lines.append("Epic within %d packs" % int(cfg["pity"]["epic"]))
	lines.append("Legendary within %d" % int(cfg["pity"]["legendary"]))
	lines.append("God pack 1 in %d" % int(cfg["god"]["one_in"]))
	lines.append("Box: %d+ legendaries, %d+ epics" % [int(cfg["box"]["legendaries"]), int(cfg["box"]["epics"])])
	return "\n".join(lines)
