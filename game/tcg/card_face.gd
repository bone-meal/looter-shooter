# Purpose: draws one card of "You got me Lobster?" as a Control: the card's art (assets/tcg/art/<id>.jpg), its faction
# frame and the layers over it (cost gem, attack and health badges, rarity gem, legendary crest; assets/tcg/frames/,
# placed by data/tcg/card_layout.json), then the words (name on the banner, rules text on the plaque, numbers, tribe)
# in the card fonts. Shows a card in the hand, a creature on the mat (live numbers: green when raised above the card,
# red when hurt; its current keywords) or the card back. An outline glow marks what can be used or picked. Rainbow and
# pony foils shine through game/tcg/card_shine.gd (set_finish). One _draw; textures are shared by every face.
# Dependencies: core/tcg/card_db.gd (handed in), core/tcg/card_text.gd, game/tcg/card_shine.gd, data/tcg/card_layout.json,
# assets/tcg/, assets/fonts/.
extends Control

const CardText = preload("res://core/tcg/card_text.gd")
const CardShine = preload("res://game/tcg/card_shine.gd")

signal pressed(face: Control, right: bool)
signal hovered(face: Control, on: bool)

const FACTION_COLORS := {
	"tide": Color(0.18, 0.42, 0.72), "waste": Color(0.66, 0.4, 0.18), "crypt": Color(0.42, 0.4, 0.5),
	"aurelind": Color(0.3, 0.58, 0.28), "club": Color(0.74, 0.22, 0.52), "neutral": Color(0.55, 0.5, 0.42),
}
const GREEN := Color(0.45, 1.0, 0.45)
const RED := Color(1.0, 0.35, 0.3)
const INK := Color(0.16, 0.1, 0.05)

static var _layout: Dictionary = {}
static var _tex: Dictionary = {}  # path -> Texture2D (or null when missing)
static var _fonts: Dictionary = {}

var db: RefCounted
var id := ""
var creature: Dictionary = {}  # a match_state creature when on the mat, {} for a card in the hand
var back := false  # face down
var outline := Color(0, 0, 0, 0)  # green = can be used, yellow = can be picked, white = chosen, red = marked to redraw
var slot := -1  # hand position or creature uid, for whoever listens
var finish := ""  # "", "rainbow" or "pony" (cosmetic foils)
var _glow := StyleBoxFlat.new()
var _art: Texture2D  # held by this face only: art leaves memory with the last face showing it (frames stay shared)
var _art_id := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void: hovered.emit(self, true))
	mouse_exited.connect(func() -> void: hovered.emit(self, false))
	_glow.draw_center = false
	_glow.set_corner_radius_all(10)
	_glow.shadow_size = 10
	if _layout.is_empty():
		_layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/card_layout.json"))


func show_card(card_db: RefCounted, card_id: String, live: Dictionary = {}) -> void:
	db = card_db
	id = card_id
	creature = live
	back = false
	queue_redraw()


func set_finish(which: String) -> void:
	finish = which
	material = CardShine.material(which, size) if which != "" else null
	queue_redraw()


func show_back() -> void:
	back = true
	queue_redraw()


func mark(color: Color) -> void:
	if color != outline:
		outline = color
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		pressed.emit(self, click.button_index == MOUSE_BUTTON_RIGHT)
		accept_event()


static func texture(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _tex[path]


# name: "title" (Cinzel bold), "body" (Alegreya), "italic" (Alegreya italic), "number" (Lilita One).
static func font(which: String) -> Font:
	if not _fonts.has(which):
		var file: String = {"title": "Cinzel", "body": "Alegreya", "italic": "Alegreya-Italic", "number": "LilitaOne"}[which]
		var base: Font = load("res://assets/fonts/%s.ttf" % file) if ResourceLoader.exists("res://assets/fonts/%s.ttf" % file) else ThemeDB.fallback_font
		if which in ["title", "body", "italic"]:
			var v := FontVariation.new()
			v.base_font = base
			v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700 if which == "title" else 500}
			_fonts[which] = v
		else:
			_fonts[which] = base
	return _fonts[which]


func _draw() -> void:
	var card_size: Array = _layout.get("size", [600, 840])
	var k := minf(size.x / float(card_size[0]), size.y / float(card_size[1]))
	if outline.a > 0.0:
		_glow.shadow_color = Color(outline, 0.85)
		_glow.border_color = outline
		_glow.set_border_width_all(maxi(2, int(4.0 * k * 3.0)))
		draw_style_box(_glow, Rect2(Vector2(-2, -2), size + Vector2(4, 4)))
	if back:
		_layer("back", k)
		return
	var c: Dictionary = db.card(id)
	var kind := "creature" if String(c["type"]) == "creature" else "spell"
	var boxes: Dictionary = _layout["boxes"]
	if _art_id != id:
		_art_id = id
		var path := "res://assets/tcg/art/%s.jpg" % id
		_art = load(path) if ResourceLoader.exists(path) else null
	var art := _art
	var art_box := _box(boxes["art"], k)
	if art != null:  # cover the window, keep the picture's shape
		var tsize := art.get_size()
		var fit := maxf(art_box.size.x / tsize.x, art_box.size.y / tsize.y)
		var src := Rect2((tsize - art_box.size / fit) * 0.5, art_box.size / fit)
		draw_texture_rect_region(art, art_box, src)
	else:
		draw_rect(art_box, Color(FACTION_COLORS.get(String(c["faction"]), Color.GRAY)).darkened(0.35))
	var hidden: bool = not creature.is_empty() and (creature["kw"] as Dictionary).has("hidden")
	if hidden:
		draw_rect(art_box, Color(0.05, 0.05, 0.1, 0.55))
	_layer("frame_%s_%s" % [c["faction"], kind], k)
	if String(c["rarity"]) == "legendary":
		_layer("crest", k)
	if String(c["rarity"]) != "token":
		_layer("gem_" + String(c["rarity"]), k)
	_layer("cost", k)
	if kind == "creature":
		_layer("attack", k)
		_layer("health", k)
	# words
	_centered(_box(boxes["name"], k), String(c.get("name", id)), font("title"), 30.0 * k, Color(1, 0.97, 0.9), 6.0 * k)
	_centered(_box(boxes["cost"], k), str(int(c["cost"])), font("number"), 64.0 * k, Color.WHITE, 10.0 * k)
	if kind == "creature":
		var atk := int(c["attack"])
		var hp := int(c["health"])
		var atk_col := Color.WHITE
		var hp_col := Color.WHITE
		if not creature.is_empty():
			atk_col = GREEN if int(creature["atk"]) > atk else (RED if int(creature["atk"]) < atk else Color.WHITE)
			hp_col = RED if int(creature["hp"]) < int(creature["max_hp"]) else (GREEN if int(creature["max_hp"]) > hp else Color.WHITE)
			atk = int(creature["atk"])
			hp = int(creature["hp"])
		_centered(_box(boxes["attack"], k), str(atk), font("number"), 60.0 * k, atk_col, 10.0 * k)
		_centered(_box(boxes["health"], k), str(hp), font("number"), 60.0 * k, hp_col, 10.0 * k)
	var tribe := String(c.get("tribe", "")).capitalize() if kind == "creature" else String(c["type"]).capitalize()
	_centered(_box(boxes["tribe"], k), tribe, font("title"), 20.0 * k, Color(1, 0.94, 0.8), 4.0 * k)
	var shown := c
	if not creature.is_empty():  # live keywords (given ones too, lost ones gone)
		shown = c.duplicate()
		shown["keywords"] = (creature["kw"] as Dictionary).keys()
	_rules(_box(boxes["text"], k), CardText.of(db, shown), String(c.get("flavor", "")), k)
	if not creature.is_empty() and (creature["kw"] as Dictionary).has("guard"):  # a Guard wears a silver shield ring
		draw_arc(art_box.get_center(), art_box.size.y * 0.55, 0, TAU, 48, Color(0.9, 0.92, 1.0, 0.7), 6.0 * k)


func _layer(layer: String, k: float) -> void:
	var tex := texture("res://assets/tcg/frames/%s.png" % layer)
	var at: Array = (_layout["layers"] as Dictionary).get(layer, [])
	if tex != null and not at.is_empty():
		draw_texture_rect(tex, Rect2(float(at[0]) * k, float(at[1]) * k, float(at[2]) * k, float(at[3]) * k), false)


func _box(b: Array, k: float) -> Rect2:
	return Rect2(float(b[0]) * k, float(b[1]) * k, float(b[2]) * k, float(b[3]) * k)


func _centered(box: Rect2, text: String, f: Font, px: float, color: Color, stroke: float) -> void:
	var fs := maxi(6, int(px))
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > box.size.x and fs > 6:  # long names shrink to fit the banner
		fs -= 1
		w = f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(box.position.x + (box.size.x - w) * 0.5, box.position.y + box.size.y * 0.5 + f.get_ascent(fs) * 0.5 - f.get_descent(fs) * 0.3)
	if stroke >= 1.0:
		draw_string_outline(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(stroke), Color(0, 0, 0, 0.9))
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


# Rules text centred on the plaque, the flavour line under it in italics; both shrink until they fit.
func _rules(box: Rect2, text: String, flavor: String, k: float) -> void:
	var body := font("body")
	var ital := font("italic")
	var fs := int(30.0 * k)
	while fs > 6:
		var h1 := body.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs).y if text != "" else 0.0
		var h2 := ital.get_multiline_string_size(flavor, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, int(fs * 0.8)).y if flavor != "" else 0.0
		if h1 + h2 + fs * 0.6 <= box.size.y:
			var top := box.position.y + (box.size.y - h1 - h2 - (fs * 0.6 if text != "" and flavor != "" else 0.0)) * 0.5
			if text != "":
				draw_multiline_string(body, Vector2(box.position.x, top + body.get_ascent(fs)), text, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs, -1, INK)
			if flavor != "":
				draw_multiline_string(ital, Vector2(box.position.x, top + h1 + (fs * 0.6 if text != "" else 0.0) + ital.get_ascent(int(fs * 0.8))), flavor, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, int(fs * 0.8), -1, Color(INK, 0.75))
			return
		fs -= 1
