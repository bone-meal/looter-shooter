# Purpose: the card table's screen: deck pick, mulligan, both leaders, both rows of creatures, your hand, hero power,
# End Turn, the turn timer with its fuse, a match log, a big hover view with keyword help, the "Concede?" prompt and the
# result. Collects clicks into intents only; game/tcg/card_table.gd runs the match. With a 3D table view
# (game/tcg/table_view.gd, step 12) the felt turns see-through, the card rows stay but are invisible, and the mouse is
# asked of the 3D view (which face is under it); hold Alt to look around.
# Dependencies: game/tcg/card_face.gd, core/tcg/card_text.gd, core/tcg/match_state.gd (read only, handed in), game/chip_art.gd.
extends Control

const CardFace = preload("res://game/tcg/card_face.gd")
const CardText = preload("res://core/tcg/card_text.gd")
const ChipArt = preload("res://game/chip_art.gd")

signal deck_chosen(deck_id: String)
signal mulligan_chosen(indices: Array)
signal intent(move: Dictionary)  # same shape as core/tcg/ai_player.gd next_move
signal again
signal leave

const HERO := -10
const HAND_SIZE := Vector2(118, 166)
const MAT_SIZE := Vector2(104, 146)
const ZOOM_SIZE := Vector2(250, 350)
const LOG_LINES := 8
const BASE_HEIGHT := 648.0
const C_USE := Color(0.3, 1.0, 0.35)
const C_PICK := Color(1.0, 0.85, 0.2)
const C_CHOSEN := Color(1, 1, 1)
const C_REDRAW := Color(1.0, 0.3, 0.3)

var _m: RefCounted  # the match
var _me := 0
var _who: Array = ["You", "Dealer"]
var _mode := ""  # "", "play", "attack", "power": waiting for a target
var _arg := -1  # hand index or attacker uid
var _valid: Array = []
var _redraw: Array = []
var _prize := 0
var _log: PackedStringArray = []
var _foe_bar := Button.new()
var _my_bar := Button.new()
var _power := Button.new()
var _end := Button.new()
var _hint := Label.new()
var _turn := Label.new()
var _fuse := ProgressBar.new()
var _log_label := Label.new()
var _foe_row := HBoxContainer.new()
var _my_row := HBoxContainer.new()
var _hand_row := HBoxContainer.new()
var _zoom: Control = CardFace.new()
var _zoom_help := Label.new()
var _pick := PanelContainer.new()
var _pick_box := VBoxContainer.new()
var _center := PanelContainer.new()
var _center_text := Label.new()
var _center_buttons := HBoxContainer.new()
var view3d: Node3D  # game/tcg/table_view.gd, or null for the flat 2D table
var _felt: ColorRect
var _hovered: Variant = null  # the face under the mouse in 3D


func _ready() -> void:
	visible = false
	_fit()
	get_viewport().size_changed.connect(_fit)
	var felt := ColorRect.new()
	felt.color = Color(0.06, 0.2, 0.16, 0.97)
	felt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	felt.gui_input.connect(_on_felt_input)
	add_child(felt)
	_felt = felt
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 16
	v.offset_right = -290
	v.offset_top = 8
	v.offset_bottom = -8
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	for b: Button in [_foe_bar, _my_bar]:
		b.custom_minimum_size = Vector2(0, 40)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_leader.bind(b))
	v.add_child(_foe_bar)
	for row: HBoxContainer in [_foe_row, _my_row]:
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.custom_minimum_size = Vector2(0, MAT_SIZE.y)
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_foe_row)
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 12)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(mid)
	_turn.add_theme_font_size_override("font_size", 20)
	_turn.custom_minimum_size = Vector2(230, 0)
	mid.add_child(_turn)
	_fuse.custom_minimum_size = Vector2(160, 14)
	_fuse.show_percentage = false
	_fuse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_child(_fuse)
	_hint.add_theme_font_size_override("font_size", 17)
	_hint.add_theme_color_override("font_color", C_PICK)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(_hint)
	_end.text = "END TURN"
	_end.custom_minimum_size = Vector2(150, 40)
	_end.add_theme_font_size_override("font_size", 18)
	_end.pressed.connect(func() -> void: _cancel(); intent.emit({"do": "end"}))
	mid.add_child(_end)
	v.add_child(_my_row)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	v.add_child(bar)
	_my_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_my_bar)
	_power.custom_minimum_size = Vector2(360, 40)
	_power.add_theme_font_size_override("font_size", 16)
	_power.pressed.connect(_on_power)
	bar.add_child(_power)
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.custom_minimum_size = Vector2(0, HAND_SIZE.y)
	_hand_row.add_theme_constant_override("separation", 6)
	_hand_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_hand_row)
	# right column: hover view + log
	var side := VBoxContainer.new()
	side.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	side.offset_left = -278
	side.offset_right = -12
	side.offset_top = 12
	side.offset_bottom = -12
	side.add_theme_constant_override("separation", 8)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(side)
	_zoom.custom_minimum_size = ZOOM_SIZE
	_zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zoom.visible = false
	side.add_child(_zoom)
	_zoom_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zoom_help.add_theme_font_size_override("font_size", 15)
	side.add_child(_zoom_help)
	_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_label.add_theme_font_size_override("font_size", 15)
	_log_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	_log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	side.add_child(_log_label)
	# centre panels: deck pick, and mulligan / concede / result
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.08, 0.95)
	back.set_corner_radius_all(10)
	back.set_content_margin_all(18)
	back.border_color = Color(1.0, 0.8, 0.3)
	back.set_border_width_all(2)
	for p: PanelContainer in [_pick, _center]:
		p.add_theme_stylebox_override("panel", back)
		p.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		p.grow_horizontal = Control.GROW_DIRECTION_BOTH
		p.grow_vertical = Control.GROW_DIRECTION_BOTH
		p.visible = false
		add_child(p)
	_pick_box.add_theme_constant_override("separation", 10)
	_pick.add_child(_pick_box)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	_center.add_child(cv)
	_center_text.add_theme_font_size_override("font_size", 22)
	_center_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cv.add_child(_center_text)
	_center_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_center_buttons.add_theme_constant_override("separation", 12)
	cv.add_child(_center_buttons)


# The game's UI is in window pixels; the table is laid out for a 648-pixel-high window and scaled up from there, so
# cards stay readable at 1080p and above.
func _fit() -> void:
	var view := get_viewport_rect().size
	var k := clampf(view.y / BASE_HEIGHT, 1.0, 4.0)
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	scale = Vector2(k, k)
	size = view / k


# ---- what the table shows ----

# The deck choice before a match. choices = [{"key", "label"}]; picking one emits deck_chosen(key). note = a line under
# the title (e.g. "Yours to keep, with 3 packs").
func open_pick(heading: String, note: String, choices: Array) -> void:
	visible = true
	_m = null
	_log = []
	_redraw = []
	_log_label.text = ""
	_center.visible = false
	for n in _pick_box.get_children():
		n.queue_free()
	var title := Label.new()
	title.text = heading
	title.add_theme_font_size_override("font_size", 24)
	_pick_box.add_child(title)
	if note != "":
		var line := Label.new()
		line.text = note
		_pick_box.add_child(line)
	var info := Label.new()
	info.text = "A win against the House Dealer pays %d chips." % _prize
	_pick_box.add_child(ChipArt.row(info))
	for choice: Dictionary in choices:
		var key := String(choice["key"])
		var b := Button.new()
		b.text = String(choice["label"])
		b.custom_minimum_size = Vector2(460, 48)
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(func() -> void: _pick.visible = false; deck_chosen.emit(key))
		_pick_box.add_child(b)
	var out := Button.new()
	out.text = "Leave the table"
	out.pressed.connect(func() -> void: leave.emit())
	_pick_box.add_child(out)
	_pick.visible = true
	_set_rows_visible(false)


func set_prize(chips: int) -> void:
	_prize = chips


# Redraws everything from the match. me = the side this screen plays; who = the two names.
func show_match(m: RefCounted, me: int, who: Array) -> void:
	_m = m
	_me = me
	_who = who
	_pick.visible = false
	_set_rows_visible(true)
	var sides: Array = m.get("sides")
	var mine: Dictionary = sides[me]
	var foe: Dictionary = sides[1 - me]
	var leaders: Dictionary = m.get("db").get("leaders")
	var my_turn: bool = m.get("phase") == "play" and int(m.get("current")) == me
	_foe_bar.text = "%s  -  %s     Health %d/%d     Mana %d/%d     Deck %d     Hand %d%s" % [who[1 - me], leaders[String(foe["leader"])]["name"], int(foe["hp"]), int(foe["max_hp"]), int(foe["mana"]), int(foe["crystals"]), (foe["deck"] as Array).size(), (foe["hand"] as Array).size(), "     Tells %d" % (foe["traps"] as Array).size() if not (foe["traps"] as Array).is_empty() else ""]
	_my_bar.text = "%s  -  %s     Health %d/%d     Mana %d/%d     Deck %d%s" % [who[me], leaders[String(mine["leader"])]["name"], int(mine["hp"]), int(mine["max_hp"]), int(mine["mana"]), int(mine["crystals"]), (mine["deck"] as Array).size(), "     Tells %d" % (mine["traps"] as Array).size() if not (mine["traps"] as Array).is_empty() else ""]
	var p: Dictionary = m.call("power_of", me)
	_power.text = "%s (%d): %s%s" % [p.get("name", "Power"), int(m.get("rules")["power_cost"]), CardText.of(m.get("db"), {"effects": p.get("effects", [])}), "  - used" if bool(mine["power_used"]) else ""]
	_power.disabled = not my_turn or bool(mine["power_used"]) or int(mine["mana"]) < int(m.get("rules")["power_cost"])
	_end.disabled = not my_turn
	_fill_row(_foe_row, foe["board"], MAT_SIZE, false)
	_fill_row(_my_row, mine["board"], MAT_SIZE, false)
	_fill_row(_hand_row, mine["hand"], HAND_SIZE, true)
	if m.get("phase") == "mulligan" and not bool(mine["ready"]):
		_ask("Mulligan: click the cards you want to send back (once).", [["Confirm", func() -> void: _center.visible = false; mulligan_chosen.emit(_redraw.duplicate())]])
	elif m.get("phase") == "mulligan":
		_ask("Waiting for %s..." % who[1 - me], [])
	elif _center_text.text.begins_with("Mulligan") or _center_text.text.begins_with("Waiting"):
		_center.visible = false
	if m.get("phase") != "play" or not my_turn:
		_cancel_quiet()
	_turn.text = ("Your turn" if my_turn else "%s's turn" % who[int(m.get("current"))]) if m.get("phase") == "play" else ""
	_mark_all()
	if view3d != null and not view3d.visible:
		view3d.call("enter")


func add_log(lines: PackedStringArray) -> void:
	for l in lines:
		if l != "":
			_log.append(l)
	while _log.size() > LOG_LINES:
		_log.remove_at(0)
	_log_label.text = "\n".join(_log)


# seconds left of the turn; the bar only shows (as a burning fuse) in the last `fuse` seconds.
func set_timer(left: float, fuse: float, mine: bool) -> void:
	_fuse.visible = mine and left <= fuse
	_fuse.max_value = fuse
	_fuse.value = left
	if mine and _m != null and _m.get("phase") == "play":
		_turn.text = "Your turn  %d s" % ceili(left)


func ask_concede(on: bool) -> void:
	if on:
		_ask("Concede?  Esc again = concede and lose.", [["Keep playing", func() -> void: _center.visible = false]])
	else:
		_center.visible = false


func asking_concede() -> bool:
	return _center.visible and _center_text.text.begins_with("Concede")


func show_result(text: String) -> void:
	_cancel_quiet()
	_ask(text, [["Play again", func() -> void: again.emit()], ["Leave the table", func() -> void: leave.emit()]])


func flash(why: String) -> void:
	_hint.text = why.capitalize() + "."


func close() -> void:
	visible = false
	if view3d != null:
		view3d.call("leave")
	_center.visible = false
	_pick.visible = false
	_m = null


# ---- clicks ----

func _on_card(face: Control, right: bool) -> void:
	if _m == null:
		return
	if right:
		_cancel()
		return
	var in_hand: bool = face.get_parent() == _hand_row
	var mine: Dictionary = _m.get("sides")[_me]
	if _m.get("phase") == "mulligan":
		if in_hand and not bool(mine["ready"]) and String(face.get("id")) != String(_m.get("rules")["lucky_card"]):
			var i := int(face.get("slot"))
			if _redraw.has(i):
				_redraw.erase(i)
			else:
				_redraw.append(i)
			_mark_all()
		return
	var code: int = int(face.get("slot")) if not in_hand else -999
	if _mode != "" and _valid.has(code):
		_fire(code)
		return
	if in_hand:
		_start_play(int(face.get("slot")))
	elif face.get_parent() == _my_row:
		var hits: Array = _m.call("attack_targets", _me, code)
		if hits.is_empty():
			_cancel()
			flash("it cannot attack now")
			return
		_begin("attack", code, hits, "Pick what it attacks (right click = cancel).")


func _on_leader(b: Button) -> void:
	if _m == null or _mode == "":
		return
	var code := HERO - (1 - _me) if b == _foe_bar else HERO - _me
	if _valid.has(code):
		_fire(code)


func _on_power() -> void:
	var effects: Array = (_m.call("power_of", _me) as Dictionary).get("effects", [])
	var pick: String = _m.get("db").pick_of(effects)
	if pick == "":
		intent.emit({"do": "power"})
		return
	_begin("power", -1, _m.call("targets_for", _me, pick), "Pick a target for the power (right click = cancel).")


func _start_play(index: int) -> void:
	if not bool(_m.call("can_play", _me, index)):
		_cancel()
		flash("not enough mana" if int(_m.get("db").card(String(_m.get("sides")[_me]["hand"][index]))["cost"]) > int(_m.get("sides")[_me]["mana"]) else "cannot play that now")
		return
	var c: Dictionary = _m.get("db").card(String(_m.get("sides")[_me]["hand"][index]))
	var pick: String = _m.get("db").pick_of(c.get("effects", []))
	var choices: Array = _m.call("targets_for", _me, pick) if pick != "" else []
	if choices.is_empty():
		intent.emit({"do": "play", "index": index})
		return
	_begin("play", index, choices, "Pick a target for %s (right click = cancel)." % c["name"])


func _begin(mode: String, arg: int, valid: Array, hint: String) -> void:
	_mode = mode
	_arg = arg
	_valid = valid
	_hint.text = hint
	_mark_all()


func _fire(code: int) -> void:
	var move := {}
	match _mode:
		"play":
			move = {"do": "play", "index": _arg, "target": code}
		"attack":
			move = {"do": "attack", "uid": _arg, "target": code}
		"power":
			move = {"do": "power", "target": code}
	_cancel()
	intent.emit(move)


func _cancel() -> void:
	_cancel_quiet()
	_mark_all()


func _cancel_quiet() -> void:
	_mode = ""
	_arg = -1
	_valid = []
	_hint.text = ""


func _on_felt_input(event: InputEvent) -> void:
	if view3d != null and view3d.visible:
		_felt_3d(event)
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed:
		_cancel()


# The 3D table: the mouse asks the view what is under it; clicks go where a click on that 2D face would go.
func _felt_3d(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.is_key_pressed(KEY_ALT):
		view3d.call("free_look", motion.relative)
		return
	var under: Variant = view3d.call("pick", get_viewport().get_mouse_position())
	if motion != null:
		if under != _hovered:
			if _hovered is Control:
				_on_hover(_hovered, false)
			_hovered = under
			if under is Control:
				_on_hover(under, true)
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or not (click.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]):
		return
	if under is Control:
		_on_card(under, click.button_index == MOUSE_BUTTON_RIGHT)
	elif under is Dictionary and bool((under as Dictionary).get("leader", false)) and click.button_index == MOUSE_BUTTON_LEFT:
		var code := HERO - (_me if int(under["side"]) == 0 else 1 - _me)
		if _mode != "" and _valid.has(code):
			_fire(code)
		else:
			_cancel()
	else:
		_cancel()


func _on_hover(face: Control, on: bool) -> void:
	_zoom.visible = on and not bool(face.get("back"))
	_zoom_help.text = ""
	if not _zoom.visible:
		return
	(_zoom as CardFace).show_card(face.get("db"), String(face.get("id")), face.get("creature"))
	var lines: PackedStringArray = []
	var c: Dictionary = (face.get("db") as RefCounted).call("card", String(face.get("id")))
	for row: Array in CardText.keyword_help(face.get("db"), c):
		lines.append("%s: %s" % [row[0], row[1]])
	_zoom_help.text = "\n".join(lines)


# ---- drawing helpers ----

func _fill_row(row: HBoxContainer, list: Array, card_size: Vector2, hand: bool) -> void:
	while row.get_child_count() < list.size():
		var face: Control = CardFace.new()
		face.custom_minimum_size = card_size
		face.pressed.connect(_on_card)
		face.hovered.connect(_on_hover)
		row.add_child(face)
	while row.get_child_count() > list.size():
		var gone := row.get_child(row.get_child_count() - 1)
		row.remove_child(gone)
		gone.queue_free()
	for i in list.size():
		var face: CardFace = row.get_child(i)
		if hand:
			face.slot = i
			face.show_card(_m.get("db"), String(list[i]))
		else:
			var c: Dictionary = list[i]
			face.slot = int(c["uid"])
			face.show_card(_m.get("db"), String(c["card"]), c)


func _mark_all() -> void:
	if _m == null:
		return
	var phase: String = _m.get("phase")
	var my_turn: bool = phase == "play" and int(_m.get("current")) == _me
	for face: CardFace in _hand_row.get_children():
		var col := Color(0, 0, 0, 0)
		if phase == "mulligan":
			col = C_REDRAW if _redraw.has(face.slot) else col
		elif _mode == "play" and _arg == face.slot:
			col = C_CHOSEN
		elif my_turn and _mode == "" and bool(_m.call("can_play", _me, face.slot)):
			col = C_USE
		face.mark(col)
	for row: HBoxContainer in [_my_row, _foe_row]:
		for face: CardFace in row.get_children():
			var col := Color(0, 0, 0, 0)
			if _mode != "" and _valid.has(face.slot):
				col = C_PICK
			elif _mode == "attack" and _arg == face.slot:
				col = C_CHOSEN
			elif my_turn and _mode == "" and row == _my_row and not (_m.call("attack_targets", _me, face.slot) as Array).is_empty():
				col = C_USE
			face.mark(col)
	_foe_bar.modulate = C_PICK if _mode != "" and _valid.has(HERO - (1 - _me)) else Color.WHITE
	_my_bar.modulate = C_PICK if _mode != "" and _valid.has(HERO - _me) else Color.WHITE
	_show_3d()


# Hands the 3D view what the rows hold (after every change of cards or outlines).
func _show_3d() -> void:
	var on := view3d != null and _m != null
	_felt.color.a = 0.0 if on else 0.97
	for row: Control in [_foe_row, _my_row, _hand_row]:
		row.modulate.a = 0.0 if on else 1.0
		for face: Control in row.get_children():  # unseen faces must not catch the mouse
			face.mouse_filter = Control.MOUSE_FILTER_IGNORE if on else Control.MOUSE_FILTER_STOP
	if not on:
		return
	var sides: Array = _m.get("sides")
	view3d.call("show_cards", _hand_row.get_children(), _my_row.get_children(), _foe_row.get_children(), (sides[1 - _me]["hand"] as Array).size(),
		[String(sides[_me]["leader"]), String(sides[1 - _me]["leader"])], [(sides[_me]["deck"] as Array).size(), (sides[1 - _me]["deck"] as Array).size()])


func _set_rows_visible(on: bool) -> void:
	for n: Control in [_foe_bar, _my_bar, _power, _end, _foe_row, _my_row, _hand_row, _turn]:
		n.visible = on
	if not on:
		_fuse.visible = false


func _ask(text: String, buttons: Array) -> void:
	_center_text.text = text
	for n in _center_buttons.get_children():
		n.queue_free()
	for pair: Array in buttons:
		var b := Button.new()
		b.text = String(pair[0])
		b.custom_minimum_size = Vector2(170, 44)
		b.pressed.connect(pair[1])
		_center_buttons.add_child(b)
	_center.visible = true
