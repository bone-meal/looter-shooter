# Purpose: the pictures of the card table's HUD (the director: "needs more icon and flare ... like the examples"):
# a leader badge (round portrait in a gold ring of the faction colour, a red health drop, the name on a ribbon, a row of
# blue mana crystals, deck and hand icons with their counts), the hero power as a round button with its cost gem, and a
# big END TURN gem button that glows on your turn and burns a fuse in the last seconds. Drawn controls only; the table
# screen (game/tcg/table_screen.gd) feeds them numbers and gets their presses.
# Dependencies: game/tcg/card_face.gd (fonts, faction colours, textures).
extends RefCounted

const CardFace = preload("res://game/tcg/card_face.gd")

const GOLD := Color(1.0, 0.82, 0.35)


# A leader: portrait, health, name, mana crystals, deck and hand. Press = pick it as a target.
class LeaderBadge extends Control:
	signal pressed
	var art: Texture2D
	var faction := Color.GRAY
	var title := ""
	var hp := 20
	var max_hp := 20
	var mana := 0
	var crystals := 0
	var deck := 0
	var hand := -1  # -1 = not shown (your own hand is on the table)
	var traps := 0
	var target := false  # glows: can be picked now
	var hit := 0.0  # flashes red when health drops

	func _init() -> void:
		size = Vector2(300, 92)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()

	func set_hp(v: int) -> void:
		if v < hp:
			hit = 1.0
		hp = v

	func _process(delta: float) -> void:
		if hit > 0.0 or target:
			hit = maxf(hit - delta * 2.0, 0.0)
			queue_redraw()

	func _draw() -> void:
		var c := Vector2(46, 46)
		var back := StyleBoxFlat.new()  # a dark pill behind the words
		back.bg_color = Color(0.04, 0.03, 0.06, 0.78)
		back.set_corner_radius_all(30)
		draw_style_box(back, Rect2(30, 14, size.x - 30, 64))
		if target:
			var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 120.0)
			for i in 4:
				draw_circle(c, 46.0 + i * 4.0 + p * 3.0, Color(1.0, 0.85, 0.2, 0.12))
		draw_circle(c, 42, Color(0.05, 0.05, 0.08))
		if art != null:  # the leader's picture, cropped round by drawing it under a ring mask of segments
			var ts := art.get_size()
			var side := minf(ts.x, ts.y) * 0.7
			var src := Rect2((ts.x - side) * 0.5, (ts.y - side) * 0.35, side, side)
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 32:
				var a := TAU * i / 32.0
				var o := Vector2(cos(a), sin(a))
				pts.append(c + o * 38.0)
				uvs.append((src.position + (o * 0.5 + Vector2(0.5, 0.5)) * src.size) / ts)
			draw_colored_polygon(pts, Color.WHITE, uvs, art)
		if hit > 0.0:
			draw_circle(c, 38, Color(1, 0, 0, 0.5 * hit))
		LeaderBadgeArt.ring(self, c, faction)
		LeaderBadgeArt.drop(self, c + Vector2(28, 26), 15.0)
		LeaderBadgeArt.number(self, c + Vector2(28, 28), str(maxi(hp, 0)), 20, Color.WHITE if hp >= max_hp else Color(1.0, 0.75, 0.75))
		var f: Font = CardFace.font("title")
		draw_string_outline(f, Vector2(96, 36), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 104, 15, 4, Color.BLACK)
		draw_string(f, Vector2(96, 36), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 104, 15, GOLD)
		for i in 8:  # mana crystals
			var state := 2 if i < mana else (1 if i < crystals else 0)
			LeaderBadgeArt.crystal(self, Vector2(104 + i * 17, 54), 7.5, state)
		LeaderBadgeArt.number(self, Vector2(252, 54), "%d/%d" % [mana, crystals], 14, Color(0.75, 0.85, 1.0))
		# deck and hand icons
		var x := 104.0
		for pair: Array in [[deck, "deck"], [hand, "hand"], [traps, "tell"]]:
			if int(pair[0]) < 0 or (pair[1] == "tell" and int(pair[0]) == 0):
				continue
			LeaderBadgeArt.little_card(self, Vector2(x, 66), String(pair[1]))
			draw_string(CardFace.font("number"), Vector2(x + 16, 80), str(pair[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.9))
			x += 46.0


# A deck to pick at the table: its leader's picture, the deck's name and the leader's; lifts and glows under the mouse.
class DeckTile extends Control:
	signal pressed
	var art: Texture2D
	var title := ""
	var sub := ""
	var lit := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(170, 200)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void: create_tween().tween_property(self, "lit", 1.0, 0.12))
		mouse_exited.connect(func() -> void: create_tween().tween_property(self, "lit", 0.0, 0.12))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2(0, -8.0 * lit), size)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.1, 0.06, 0.1, 0.95)
		box.border_color = Color(1.0, 0.82, 0.35, 0.5 + 0.5 * lit)
		box.set_border_width_all(2 + int(2 * lit))
		box.set_corner_radius_all(14)
		box.shadow_color = Color(1.0, 0.8, 0.3, 0.45 * lit)
		box.shadow_size = int(16 * lit)
		draw_style_box(box, r)
		var pic := Rect2(r.position + Vector2(10, 10), Vector2(size.x - 20, size.y - 70))
		if art != null:
			var ts := art.get_size()
			var fit := maxf(pic.size.x / ts.x, pic.size.y / ts.y)
			draw_texture_rect_region(art, pic, Rect2((ts - pic.size / fit) * 0.5, pic.size / fit))
		draw_rect(pic, Color(1.0, 0.82, 0.35), false, 2.0)
		var f: Font = CardFace.font("title")
		for line: Array in [[title, 16, Color.WHITE, size.y - 38], [sub, 12, Color(1.0, 0.82, 0.35), size.y - 16]]:
			var px := int(line[1])
			var w := minf(f.get_string_size(String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, size.x - 12)
			draw_string_outline(f, r.position + Vector2((size.x - w) * 0.5, float(line[3])), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, px, 4, Color.BLACK)
			draw_string(f, r.position + Vector2((size.x - w) * 0.5, float(line[3])), String(line[0]), HORIZONTAL_ALIGNMENT_LEFT, size.x - 12, px, line[2])


# Shared drawing of the pieces: ring, health drop, numbers, mana crystals, little card icons.
class LeaderBadgeArt:
	static func ring(ci: CanvasItem, c: Vector2, faction: Color) -> void:
		ci.draw_arc(c, 40, 0, TAU, 48, faction.lightened(0.2), 5.0, true)
		ci.draw_arc(c, 43.5, 0, TAU, 48, Color(1.0, 0.82, 0.35), 2.5, true)
		ci.draw_arc(c, 37, 0, TAU, 48, Color(0.3, 0.2, 0.05), 1.5, true)

	static func drop(ci: CanvasItem, c: Vector2, r: float) -> void:
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			var s := 1.3 if absf(a - PI) > PI * 0.8 else 1.0  # a point on top
			pts.append(c + Vector2(sin(a) * r, -cos(a) * r * s))
		ci.draw_colored_polygon(pts, Color(0.85, 0.12, 0.12))
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 0.75, 0.6), 2.0, true)
		ci.draw_circle(c + Vector2(-r * 0.35, -r * 0.2), r * 0.22, Color(1, 1, 1, 0.35))

	static func number(ci: CanvasItem, at: Vector2, text: String, px: int, col: Color) -> void:
		var f: Font = CardFace.font("number")
		var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		ci.draw_string_outline(f, at - Vector2(w * 0.5, -px * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 6, Color(0, 0, 0, 0.85))
		ci.draw_string(f, at - Vector2(w * 0.5, -px * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

	static func crystal(ci: CanvasItem, c: Vector2, r: float, state: int) -> void:
		var pts := PackedVector2Array()
		for i in 6:
			pts.append(c + Vector2.from_angle(TAU * i / 6.0 + PI / 6.0) * r)
		if state == 2:
			ci.draw_colored_polygon(pts, Color(0.25, 0.55, 1.0))
			ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.25, Color(1, 1, 1, 0.5))
		elif state == 1:
			ci.draw_colored_polygon(pts, Color(0.1, 0.14, 0.25))
		ci.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.75, 0.85, 1.0, 0.9 if state > 0 else 0.35), 1.5, true)

	static func little_card(ci: CanvasItem, at: Vector2, kind: String) -> void:
		var col := Color(0.75, 0.12, 0.35) if kind != "tell" else Color(0.5, 0.2, 0.7)
		var n := 3 if kind == "hand" else 1
		for i in n:
			var r := Rect2(at + Vector2(i * 3, -i * 2), Vector2(11, 15))
			ci.draw_rect(r, col)
			ci.draw_rect(r, Color(1.0, 0.82, 0.35), false, 1.2)
		if kind == "tell":
			ci.draw_string(CardFace.font("number"), at + Vector2(2, 12), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


# The hero power: the leader's picture in a small round frame, its mana cost on a blue gem; grey when it cannot be used,
# turned face down (a gold logo coin) once used this turn. Hover shows its words through `hovered`.
class PowerButton extends Control:
	signal pressed
	signal hovered(on: bool)
	var art: Texture2D
	var cost := 2
	var usable := false
	var used := false
	var lit := false

	func _init() -> void:
		size = Vector2(70, 70)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			lit = true
			hovered.emit(true)
			queue_redraw())
		mouse_exited.connect(func() -> void:
			lit = false
			hovered.emit(false)
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if usable and event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()

	func _process(_delta: float) -> void:
		if usable:
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		if usable:
			var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
			draw_circle(c, 33.0 + p * 3.0, Color(0.4, 1.0, 0.45, 0.3))
		draw_circle(c, 30, Color(0.05, 0.05, 0.08))
		if used:
			draw_circle(c, 26, Color(0.55, 0.4, 0.15))
			draw_arc(c, 18, 0, TAU, 24, Color(1.0, 0.82, 0.35), 2.0, true)
		elif art != null:
			var ts := art.get_size()
			var side := minf(ts.x, ts.y) * 0.6
			var src := Rect2((ts.x - side) * 0.5, (ts.y - side) * 0.35, side, side)
			var pts := PackedVector2Array()
			var uvs := PackedVector2Array()
			for i in 28:
				var o := Vector2.from_angle(TAU * i / 28.0)
				pts.append(c + o * 26.0)
				uvs.append((src.position + (o * 0.5 + Vector2(0.5, 0.5)) * src.size) / ts)
			draw_colored_polygon(pts, Color.WHITE if usable else Color(0.45, 0.45, 0.5), uvs, art)
		draw_arc(c, 29, 0, TAU, 40, Color(1.0, 0.82, 0.35) if (usable or lit) else Color(0.6, 0.55, 0.4), 3.0, true)
		LeaderBadgeArt.crystal(self, c + Vector2(0, -29), 11.0, 2)
		LeaderBadgeArt.number(self, c + Vector2(0, -29), str(cost), 15, Color.WHITE)


# END TURN: a big gem button. Green-gold and pulsing on your turn, grey "ENEMY TURN" otherwise; in the last seconds a
# fuse burns along its bottom edge.
class EndButton extends Control:
	signal pressed
	var mine := false
	var fuse := -1.0  # 0..1 left of the fuse, -1 = no fuse
	var lit := false

	func _init() -> void:
		size = Vector2(150, 56)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_entered.connect(func() -> void:
			lit = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			lit = false
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		if mine and event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()

	func _process(_delta: float) -> void:
		if mine:
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(int(size.y * 0.5))
		var p := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 250.0) if mine else 0.0
		box.bg_color = Color(0.25, 0.6, 0.2).lerp(Color(0.95, 0.75, 0.2), p * 0.5) if mine else Color(0.22, 0.22, 0.26)
		box.border_color = Color(1.0, 0.85, 0.4) if mine else Color(0.45, 0.45, 0.5)
		box.set_border_width_all(4 if lit and mine else 3)
		if mine:
			box.shadow_color = Color(1.0, 0.85, 0.3, 0.35 + 0.25 * p)
			box.shadow_size = 12
		draw_style_box(box, r)
		draw_rect(Rect2(14, 6, size.x - 28, 6), Color(1, 1, 1, 0.18))  # gem shine
		var f: Font = CardFace.font("title")
		var word := "END TURN" if mine else "ENEMY TURN"
		var w := f.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string_outline(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + 7), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0, 0, 0, 0.6))
		draw_string(f, Vector2((size.x - w) * 0.5, size.y * 0.5 + 7), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE if mine else Color(0.75, 0.75, 0.8))
		if fuse >= 0.0:  # the fuse: rope from left, spark at its burning end
			var end_x := 12.0 + (size.x - 24.0) * fuse
			draw_line(Vector2(12, size.y + 6), Vector2(end_x, size.y + 6), Color(0.75, 0.6, 0.35), 3.0)
			for i in 6:
				var a := randf() * TAU
				draw_line(Vector2(end_x, size.y + 6), Vector2(end_x, size.y + 6) + Vector2.from_angle(a) * randf_range(3, 9), Color(1.0, 0.7, 0.2), 1.5)
			draw_circle(Vector2(end_x, size.y + 6), 4, Color(1.0, 0.9, 0.5))
