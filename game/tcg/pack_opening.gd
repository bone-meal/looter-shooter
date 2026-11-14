# Purpose: opening card packs (locked step 11), over the whole screen from the Binder: the unopened packs stand one in
# front of the other (front pack largest); drag across the top of the front pack to tear it (the tear follows the
# mouse, letting go early snaps it back; a god pack tears gold); the cards rise out of the pack with their backs to
# the camera, two are tucked to the back, then each click turns the front card over, lowest rarity first, highest last,
# with its rarity glow and chime (a legendary shakes and glows longer first); turned cards line up below, "NEW" on
# cards not owned before. "Open all" (after the first pack opened by hand this session) opens the rest at once and
# shows what came out. Cards count once the tear is finished (saved at once through `changed`). A pack's rare play mat
# (data/tcg/mats.json) is named in the title.
# Drawn in a 1152 x 648 stage scaled to the window height.
# Dependencies: core/tcg/pack_open.gd, game/tcg/card_face.gd, game/tcg/pack_sound.gd, game/sound_board.gd,
# assets/tcg/pack.png; db (core/tcg/card_db.gd), owned (core/tcg/collection.gd), cfg (data/tcg/packs.json) handed in.
extends Control

const PackOpen = preload("res://core/tcg/pack_open.gd")
const CardFace = preload("res://game/tcg/card_face.gd")
const PackSound = preload("res://game/tcg/pack_sound.gd")
const SoundBoard = preload("res://game/sound_board.gd")
const TcgStats = preload("res://core/tcg/tcg_stats.gd")

signal changed  # cards joined the collection: save
signal closed

const W := 1152.0
const H := 648.0
const GLOW := {"common": Color(0.55, 0.95, 0.5), "rare": Color(0.35, 0.6, 1.0), "epic": Color(0.78, 0.4, 1.0), "legendary": Color(1.0, 0.62, 0.12)}
const BUILD_UP := {"common": 0.12, "rare": 0.3, "epic": 0.65, "legendary": 1.5}
const STACK := Vector2(180, 252)
const STACK_AT := Vector2(576, 225)  # centre of the card stack
const ROW := Vector2(118, 165)
const ROW_TOP := 398.0
const PACK := Vector2(214, 346)
const PACK_AT := Vector2(576, 300)
const TEAR_BAND := 0.13  # the strip that tears off: top part of the pack picture
const GOLD := Color(1.0, 0.82, 0.3)

static var opened_one := false  # "Open all" shows once a pack was opened by hand this session

var db: RefCounted
var owned: RefCounted
var cfg: Dictionary
var stats: RefCounted  # the combat record (core/stat_book.gd): packs, god packs and foils count for achievements
var mats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/tcg/mats.json"))

var _rng := RandomNumberGenerator.new()
var _stage := Control.new()
var _pack_tex: Texture2D
var _state := ""  # "stack", "rise", "flip", "done", "all"
var _rolled := {}  # the front pack, rolled when its tear began (taken back if it is never finished)
var _cards: Array = []  # the open pack's cards in stack order (front first)
var _stack: Array = []  # their faces, front first
var _row: Array = []  # turned faces, in turning order
var _busy := false
var _tear := 0.0
var _drag_from := -1.0
var _fly := 0.0  # the torn strip flying away 0..1
var _drop := 0.0  # the empty pack sliding away 0..1
var _glow := 0.0
var _glow_color := Color.WHITE
var _sound := AudioStreamPlayer.new()
var _title := Label.new()
var _hint := Label.new()
var _buttons := HBoxContainer.new()
var _big: Control  # a turned card shown big under the mouse
var _summary := ScrollContainer.new()
var _summary_grid := GridContainer.new()


func _ready() -> void:
	top_level = true
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	_rng.randomize()
	_pack_tex = CardFace.texture("res://assets/tcg/pack.png")
	add_child(_sound)
	add_child(_stage)
	_stage.size = Vector2(W, H)
	_stage.clip_contents = false
	_stage.draw.connect(_draw_stage)
	_stage.gui_input.connect(_stage_input)
	for l: Label in [_title, _hint]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.size = Vector2(W, 40)
		l.add_theme_font_override("font", CardFace.font("title"))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(l)
	_title.position = Vector2(0, 14)
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", GOLD)
	_hint.position = Vector2(0, 356)
	_hint.add_theme_font_size_override("font_size", 18)
	_buttons.position = Vector2(0, 590)
	_buttons.size = Vector2(W, 40)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 14)
	_stage.add_child(_buttons)
	_summary.position = Vector2(76, 110)
	_summary.size = Vector2(1000, 470)
	_summary.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_summary.visible = false
	_summary_grid.columns = 8
	_summary_grid.add_theme_constant_override("h_separation", 12)
	_summary_grid.add_theme_constant_override("v_separation", 12)
	_summary.add_child(_summary_grid)
	_stage.add_child(_summary)
	_big = CardFace.new()
	_big.visible = false
	_big.size = Vector2(230, 322)
	_big.z_index = 200
	_stage.add_child(_big)
	_big.mouse_filter = Control.MOUSE_FILTER_IGNORE


func open(card_db: RefCounted, collection: RefCounted, pack_cfg: Dictionary) -> void:
	db = card_db
	owned = collection
	cfg = pack_cfg
	visible = true
	_fit()
	_show_stack()


func is_open() -> bool:
	return visible


# Leaves (also when the menu around it closes): a pack rolled but not torn is put back as it was.
func close() -> void:
	if not visible:
		return
	PackOpen.undo(owned, _rolled)
	_rolled = {}
	_clear_faces()
	visible = false
	closed.emit()


func _fit() -> void:
	var view := get_viewport_rect().size
	position = Vector2.ZERO
	size = view
	var k := view.y / H
	_stage.scale = Vector2(k, k)
	_stage.position = Vector2((view.x - W * k) * 0.5, 0.0)


func _left() -> int:
	return owned.pack_count()


# ---- the stack of unopened packs ----

func _show_stack() -> void:
	_clear_faces()
	_summary.visible = false
	_state = "stack"
	_tear = 0.0
	_fly = 0.0
	_drop = 0.0
	_glow = 0.0
	_title.text = "%d PACK%s TO OPEN" % [_left(), "" if _left() == 1 else "S"]
	_hint.text = "Drag across the top of the pack to tear it open"
	_hint.position.y = 520
	_set_buttons([["Back to binder", close]] + ([["Open all (%d)" % _left(), _open_all]] if opened_one and _left() > 1 else []))
	_stage.queue_redraw()


func _front_rect() -> Rect2:
	return Rect2(PACK_AT - PACK * 0.5 + Vector2(0, _drop * 420.0), PACK)


func _stage_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if _state == "stack" and not _busy:
			var r := _front_rect()
			var band := Rect2(r.position - Vector2(30, 30), Vector2(r.size.x + 60, r.size.y * 0.28 + 30))
			if mb.pressed and band.has_point(mb.position):
				if _rolled.is_empty():
					_rolled = PackOpen.roll(db, owned, cfg, _rng, mats)
				_drag_from = mb.position.x
			elif not mb.pressed and _drag_from >= 0.0:
				_drag_from = -1.0
				if _tear < 1.0:  # let go early: it snaps back
					create_tween().tween_method(func(v: float) -> void:
						_tear = v
						_stage.queue_redraw(), _tear, 0.0, 0.2)
		elif _state == "flip" and mb.pressed:
			_turn_next()
	elif event is InputEventMouseMotion and _state == "stack" and _drag_from >= 0.0 and not _busy:
		_tear = clampf(absf((event as InputEventMouseMotion).position.x - _drag_from) / (PACK.x * 0.85), 0.0, 1.0)
		_stage.queue_redraw()
		if _tear >= 1.0:
			_drag_from = -1.0
			_torn()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and _state == "flip" and ((event as InputEventKey).keycode == KEY_SPACE or (event as InputEventKey).keycode == KEY_ENTER):
		_turn_next()
		get_viewport().set_input_as_handled()


# ---- tear, rise, tuck ----

func _torn() -> void:
	_busy = true
	_play(PackSound.tear(), "card_tear")
	var got := PackOpen.commit(owned, _rolled)
	var god := bool(_rolled.get("god", false))
	TcgStats.pack(stats, got, god, String(_rolled.get("kind", "standard")))
	var mat := String(_rolled.get("mat", ""))
	_rolled = {}
	opened_one = true
	changed.emit()
	# the two best are tucked to the back, so the stack turns over lowest first
	var n := got.size()
	_cards = got.slice(n - 2) + got.slice(0, n - 2)
	_title.text = "GOD PACK!" if god else ""
	if mat != "":
		var news := "NEW PLAY MAT: %s!" % String(mats["mats"][mat]["name"]).to_upper()
		_title.text = (_title.text + "  " + news) if god else news
	_hint.text = ""
	_set_buttons([])
	_state = "rise"
	var t := create_tween()
	t.tween_method(func(v: float) -> void:
		_fly = v
		_stage.queue_redraw(), 0.0, 1.0, 0.35)
	t.tween_callback(_rise)


func _rise() -> void:
	var start := _front_rect().get_center() - STACK * 0.5
	for i in _cards.size():
		var face := CardFace.new()
		_stage.add_child(face)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.size = STACK
		face.pivot_offset = STACK * 0.5
		face.position = start
		face.show_back()
		face.z_index = 100 - i
		_stack.append(face)
	var t := create_tween().set_parallel(true)
	for i in _stack.size():
		var face: Control = _stack[i]
		t.tween_property(face, "position", _stack_spot(i), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.04 * i)
	t.tween_method(func(v: float) -> void:
		_drop = v
		_stage.queue_redraw(), 0.0, 1.0, 0.5)
	t.chain().tween_interval(0.15)
	t.chain().tween_callback(_tuck.bind(2))


func _stack_spot(i: int) -> Vector2:
	return STACK_AT - STACK * 0.5 + Vector2(i * 3.0, -i * 3.0)


# The front card dips out and goes round to the back, `left` times.
func _tuck(left: int) -> void:
	if left <= 0 or _stack.size() < 3:
		_ready_to_turn()
		return
	var face: Control = _stack.pop_front()
	_stack.append(face)
	var t := create_tween()
	t.tween_property(face, "position:y", face.position.y + STACK.y * 0.75, 0.16).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		for i in _stack.size():
			(_stack[i] as Control).z_index = 100 - i)
	t.set_parallel(true)
	for i in _stack.size():
		t.tween_property(_stack[i], "position", _stack_spot(i), 0.2).set_ease(Tween.EASE_OUT)
	t.chain().tween_callback(_tuck.bind(left - 1))


func _ready_to_turn() -> void:
	_busy = false
	_state = "flip"
	_hint.text = "Click to turn the next card"
	_hint.position.y = 356
	_stage.queue_redraw()  # the empty pack is gone now


# ---- turning the cards ----

func _turn_next() -> void:
	if _busy or _stack.is_empty():
		return
	_busy = true
	var face: Control = _stack.pop_front()
	var card: Dictionary = _cards[_row.size()]
	var rarity := String(card["rarity"])
	_glow_color = GLOW.get(rarity, Color.WHITE)
	if String(card["finish"]) != "":
		_glow_color = Color(1, 0.6, 1) if String(card["finish"]) == "pony" else Color(0.6, 1, 1)
	var wait: float = BUILD_UP.get(rarity, 0.2)
	var home := face.position
	var t := create_tween()
	t.tween_method(func(v: float) -> void:  # build-up: shake and a growing glow
		_glow = v * 0.6
		face.position = home + Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * v * (6.0 if rarity == "legendary" else 3.0)
		_stage.queue_redraw(), 0.0, 1.0, wait)
	t.tween_callback(func() -> void: face.position = home)
	t.tween_property(face, "scale:x", 0.0, 0.1)
	t.tween_callback(func() -> void:
		face.show_card(db, String(card["id"]))
		if String(card["finish"]) != "":
			face.set_finish(String(card["finish"]))
		_play(PackSound.reveal(rarity, String(card["finish"])), PackSound.id_of(rarity, String(card["finish"]))))
	t.tween_property(face, "scale:x", 1.0, 0.12)
	t.parallel().tween_method(func(v: float) -> void:
		_glow = v
		_stage.queue_redraw(), 1.0, 0.0, 0.9 if rarity == "legendary" else 0.6)
	t.tween_interval(0.25 if rarity in ["epic", "legendary"] else 0.05)
	t.tween_callback(_to_row.bind(face, card))


func _to_row(face: Control, card: Dictionary) -> void:
	var n := _cards.size()
	var gap := 10.0
	var width := n * ROW.x + (n - 1) * gap
	var i := _row.size()
	_row.append(face)
	var spot := Vector2((W - width) * 0.5 + i * (ROW.x + gap), ROW_TOP)
	face.z_index = 0
	var t := create_tween().set_parallel(true)
	t.tween_property(face, "position", spot, 0.3).set_ease(Tween.EASE_OUT)
	t.tween_property(face, "size", ROW, 0.3)
	t.chain().tween_callback(func() -> void:
		face.pivot_offset = ROW * 0.5
		if face.finish != "":
			face.set_finish(face.finish)  # the shine is made for the face's size
		face.mouse_filter = Control.MOUSE_FILTER_STOP
		face.hovered.connect(_hover.bind(card))
		if bool(card["new"]):
			_new_tag(face)
		_busy = false
		if _stack.is_empty():
			_done())


func _new_tag(face: Control) -> void:
	var tag := Label.new()
	tag.text = "NEW"
	tag.add_theme_font_override("font", CardFace.font("number"))
	tag.add_theme_font_size_override("font_size", 18)
	tag.add_theme_color_override("font_color", Color(1, 0.95, 0.4))
	tag.add_theme_color_override("font_outline_color", Color(0.4, 0.1, 0))
	tag.add_theme_constant_override("outline_size", 6)
	tag.position = Vector2(ROW.x - 44, -14)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(tag)


func _hover(face: Control, on: bool, card: Dictionary) -> void:
	_big.visible = on and _state in ["done", "all"]
	if _big.visible:
		_big.show_card(db, String(card["id"]))
		var at := face.position + Vector2(face.size.x * 0.5 - _big.size.x * 0.5, -_big.size.y - 8)
		_big.position = Vector2(clampf(at.x, 0, W - _big.size.x), maxf(at.y, 0))


func _done() -> void:
	_state = "done"
	_hint.text = ""
	var rows: Array = []
	if _left() > 0:
		rows.append(["Next pack (%d left)" % _left(), _show_stack])
		if _left() > 1:
			rows.append(["Open all (%d)" % _left(), _open_all])
	rows.append(["Back to binder", close])
	_set_buttons(rows)


# ---- open all ----

func _open_all() -> void:
	_clear_faces()
	var got := PackOpen.open_all(db, owned, cfg, _rng, mats)
	for roll: Dictionary in got["rolls"]:
		TcgStats.pack(stats, roll["cards"], bool(roll["god"]), String(roll["kind"]))
	changed.emit()
	_state = "all"
	_hint.text = ""
	var counts := {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
	var best := {}  # id -> {"card", "n"} for rare and better
	var news := 0
	for c: Dictionary in got["cards"]:
		counts[String(c["rarity"])] = int(counts.get(String(c["rarity"]), 0)) + 1
		if bool(c["new"]):
			news += 1
		if String(c["rarity"]) != "common" or String(c["finish"]) != "":
			var key := "%s|%s" % [c["id"], c["finish"]]
			if not best.has(key):
				best[key] = {"card": c, "n": 0}
			best[key]["n"] = int(best[key]["n"]) + 1
	_title.text = "%d PACKS OPENED%s" % [int(got["packs"]), "  -  %d GOD PACK%s!" % [int(got["gods"]), "" if int(got["gods"]) == 1 else "S"] if int(got["gods"]) > 0 else ""]
	_hint.position.y = 62
	_hint.text = "%d legendary  -  %d epic  -  %d rare  -  %d common  -  %d new" % [counts["legendary"], counts["epic"], counts["rare"], counts["common"], news]
	for m: Variant in got["mats"]:
		_hint.text += "  -  NEW MAT: %s" % mats["mats"][String(m)]["name"]
	var order: Array = best.values()
	var rank := {"legendary": 0, "epic": 1, "rare": 2, "common": 3}
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(rank[a["card"]["rarity"]]) < int(rank[b["card"]["rarity"]]))
	for entry: Dictionary in order.slice(0, 48):  # a box can hold hundreds: the best 48 as cards, the rest in the counts above
		var c: Dictionary = entry["card"]
		var face := CardFace.new()
		face.custom_minimum_size = Vector2(110, 154)
		_summary_grid.add_child(face)
		face.show_card(db, String(c["id"]))
		face.size = Vector2(110, 154)
		if String(c["finish"]) != "":
			face.set_finish(String(c["finish"]))
		face.mark(GLOW.get(String(c["rarity"]), Color.WHITE))
		face.hovered.connect(_hover_summary.bind(c))
		if int(entry["n"]) > 1:
			var many := Label.new()
			many.text = "x%d" % int(entry["n"])
			many.position = Vector2(80, 128)
			face.add_child(many)
		if bool(c["new"]):
			_new_tag(face)
	_summary.visible = true
	_set_buttons([["Back to binder", close]])
	_stage.queue_redraw()


func _hover_summary(face: Control, on: bool, card: Dictionary) -> void:
	_big.visible = on
	if on:
		_big.show_card(db, String(card["id"]))
		var at := _summary.position + face.position - Vector2(0, _summary.scroll_vertical)
		_big.position = Vector2(clampf(at.x + face.size.x + 10 if at.x < W * 0.5 else at.x - _big.size.x - 10, 0, W - _big.size.x), clampf(at.y - 60, 0, H - _big.size.y))


# ---- dev steps (tools/dev_boot.gd "!tcg packs ..."): the drag done for us ----

func dev_step(what: String) -> void:
	match what:
		"half", "tear":
			if _state != "stack" or _left() <= 0:
				return
			if _rolled.is_empty():
				_rolled = PackOpen.roll(db, owned, cfg, _rng, mats)
			_tear = 0.5 if what == "half" else 1.0
			_stage.queue_redraw()
			if what == "tear":
				_torn()
		"turn":
			_turn_next()
		"all":
			_open_all()


# ---- helpers ----

func _clear_faces() -> void:
	for face: Control in _stack + _row:
		face.queue_free()
	_stack = []
	_row = []
	_cards = []
	for child in _summary_grid.get_children():
		_summary_grid.remove_child(child)
		child.queue_free()
	_big.visible = false
	_busy = false


func _set_buttons(rows: Array) -> void:
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for row: Array in rows:
		var b := Button.new()
		b.text = String(row[0])
		b.custom_minimum_size = Vector2(190, 38)
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(row[1])
		_buttons.add_child(b)


func _play(stream: AudioStream, id: String) -> void:
	if SoundBoard.allow(id):
		_sound.stream = stream
		_sound.play()
		SoundBoard.heard(id)


func _draw_stage() -> void:
	# velvet and a soft spotlight
	_stage.draw_rect(Rect2(-W, 0, W * 3, H), Color(0.06, 0.03, 0.08))
	for i in 6:
		var r := 520.0 - i * 80.0
		_stage.draw_circle(Vector2(W * 0.5, 250), r, Color(0.35, 0.12, 0.4, 0.06))
	if _glow > 0.0 and _state == "flip":
		var c := STACK_AT
		for i in 8:
			_stage.draw_circle(c, (90.0 + i * 26.0) * (0.6 + _glow * 0.6), Color(_glow_color, 0.08 * _glow))
		for i in 12:  # rays
			var a := i * TAU / 12.0 + _glow
			_stage.draw_line(c, c + Vector2(cos(a), sin(a)) * 330.0 * _glow, Color(_glow_color, 0.25 * _glow), 6.0)
	if _state not in ["stack", "rise"] or _pack_tex == null:
		return
	var tsize := _pack_tex.get_size()
	var behind := mini(_left() - (1 if _state == "stack" else 0), 4)
	for i in range(behind, 0, -1):  # the packs waiting behind, smaller and darker
		var s := PACK * (1.0 - 0.07 * i)
		var r := Rect2(PACK_AT - s * 0.5 + Vector2(i * 34.0, -i * 22.0), s)
		_stage.draw_texture_rect(_pack_tex, r, false, Color(1, 1, 1, 1).darkened(0.18 * i))
	if _state == "stack" and _left() <= 0:
		return
	var front := _front_rect()
	var fade := Color(1, 1, 1, 1.0 - _drop)
	var band := TEAR_BAND * front.size.y
	var tear_y := front.position.y + band
	var src_band := TEAR_BAND * tsize.y
	_stage.draw_texture_rect_region(_pack_tex, Rect2(front.position.x, tear_y, front.size.x, front.size.y - band), Rect2(0, src_band, tsize.x, tsize.y - src_band), fade)
	var p := _tear if _fly <= 0.0 else 1.0
	if _fly < 1.0:
		var cut := front.position.x + p * front.size.x
		if p < 1.0:  # the part of the strip still on
			_stage.draw_texture_rect_region(_pack_tex, Rect2(cut, front.position.y, front.size.x * (1.0 - p), band), Rect2(tsize.x * p, 0, tsize.x * (1.0 - p), src_band))
		if p > 0.0:  # the torn part lifts away from the cut
			_stage.draw_set_transform(Vector2(cut, tear_y) + Vector2(-_fly * 80.0, -_fly * 260.0), -0.55 * p - _fly * 1.2)
			_stage.draw_texture_rect_region(_pack_tex, Rect2(-p * front.size.x, -band, p * front.size.x, band), Rect2(0, 0, tsize.x * p, src_band), Color(1, 1, 1, 1.0 - _fly))
			_stage.draw_set_transform(Vector2.ZERO)
		var god := bool(_rolled.get("god", false))
		var line := PackedVector2Array()
		var steps := int(p * 24.0) + 1
		for k in steps + 1:
			var x := front.position.x + front.size.x * p * float(k) / float(steps)
			line.append(Vector2(x, tear_y + (3.0 if k % 2 == 0 else -3.0)))
		if p > 0.0 and line.size() > 1:
			if god:
				_stage.draw_polyline(line, Color(GOLD, 0.35), 10.0)
			_stage.draw_polyline(line, GOLD if god else Color(1, 1, 1, 0.9), 2.5)
