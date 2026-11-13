# Purpose: the player HUD: health ring, the holster bar (ready guns and the knife), the gun in hand with the rounds in
# it and the spare rounds of its pool, reload bar, boss bar, damage flash, and the
# zombies-style parts: the round in red chalk (tallies up to 5, then a number), enemies left, and the points with their
# "+10" pop-ups (the rest of the party's points listed above ours).
# Dependencies: game/player.gd (read-only: health, weapons, slot), core/score_card.gd (read-only, via watch()),
# game/chalk_marks.gd. game/game_session.gd sets `player`, the round, `enemies_left`, `party`, `wave_text`, `boss_ratio`.
extends Control

const ChalkMarks = preload("res://game/chalk_marks.gd")
const KnifeModels = preload("res://game/knife_models.gd")
const Player = preload("res://game/player.gd")

const ItemIcons = preload("res://game/item_icons.gd")
const TierStyle = preload("res://game/tier_style.gd")
const InputSetup = preload("res://game/input_setup.gd")
const GunStats = preload("res://core/gun_stats.gd")

const GOOD := Color(0.3, 0.85, 0.4)
const WARN := Color(0.95, 0.8, 0.25)
const BAD := Color(0.95, 0.3, 0.3)
const BACK := Color(0, 0, 0, 0.5)
const WHITE := Color(1, 1, 1, 0.95)
const DIM := Color(1, 1, 1, 0.3)
const BOSS := Color(0.7, 0.35, 0.9)

const RING_RADIUS := 54.0
const RING_WIDTH := 10.0
const SLOT_W := 200.0
const SLOT_H := 62.0
const SLOT_GAP := 6.0
const SKILL_W := 150.0
const SKILL_H := 44.0
const MARGIN := 16.0
const FLASH_STRIPS := 8
const FLASH_STRIP_W := 14.0
const CHALK := Color(0.78, 0.07, 0.05, 0.95)
const POINTS := Color(1.0, 0.93, 0.7)
const TALLY_H := 72.0  # height of the round marks
const TALLY_W := 150.0  # room kept for them left of the health ring
const POPS := 8  # points pop-ups alive at once
const POP_TIME := 1.1
const CALL_TIME := 2.6  # seconds a power-up's name stays across the screen
const POWER_BOX := Vector2(176.0, 38.0)  # one running power-up above the holster bar

var player: CharacterBody3D
var wave_text := ""
var blind := false  # a colosseum modifier: no holster bar and no ammo counter
var quest_text := ""  # the main quest's tracker (top left; "" = hidden)
var course_text := ""  # the hop course's clock, stage and best time (top middle; "" = hidden)
var cigarette := -1.0  # 0..1 of the lit cigarette left (-1 = none worn): a thin bar under the health ring
var cigarette_warn := false  # nearly burnt out: the bar is red
var show_speed := false  # ground speed in Source units under the crosshair (on with the debug HUD)
var boss_ratio := -1.0
var notice_text := ""  # short pickup message, fades after a few seconds (see notice())
var level := 0  # player level (0 = hidden) and progress to the next
var xp_ratio := 0.0
var coins := -1  # casino coins; -1 = hidden
var prompt_text := ""  # interaction prompt shown near the crosshair, e.g. "[F] Enter"
var round_number := 0  # the island round or the colosseum wave being fought; 0 = hidden
var round_of := 0  # the colosseum: how many waves there are ("3 / 8"); 0 = endless rounds, shown as tallies
var enemies_left := -1  # -1 = hidden
var show_points := true  # off where the points game does not run (Aurelind)
var perks: RefCounted  # core/perk_state.gd: the perks carried, shown as a row of coloured tags
var powerups: RefCounted  # core/powerup_rules.gd: the running ones are shown with their time left
var power_now := 0.0  # the session's clock, for that time
var party: Array = []  # the other players' {"name", "points"}, set by the session a few times a second

var _flash := 0.0
var _notice_time := 0.0
var _fade := 0.0  # black screen amount, runs 1 -> 0 after play_fade()
var _font: Font = ThemeDB.fallback_font
var _score: RefCounted  # core/score_card.gd
var _pop_amount := PackedInt32Array()  # pop-up pool: what each shows (negative = spent) ...
var _pop_age := PackedFloat32Array()  # ... and for how long it has been flying (POP_TIME = free)
var _pop_next := 0
var _round_seen := 0
var _call_text := ""  # the power-up just taken, called out across the screen (see callout())
var _call_color := Color.WHITE
var _call_time := 0.0
var _white := 0.0  # white screen amount, runs 1 -> 0 after flash_white() (the nuke)
var _round_flash := 0.0  # a new round: its marks flash white for a moment


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pop_amount.resize(POPS)
	_pop_age.resize(POPS)
	_pop_age.fill(POP_TIME)


# Shows this score card's points; every gain and every purchase flies off the number as a pop-up.
func watch(card: RefCounted) -> void:
	_score = card
	card.earned.connect(_pop)
	card.spent.connect(func(amount: int) -> void: _pop(-amount))


func _pop(amount: int) -> void:
	_pop_amount[_pop_next] = amount
	_pop_age[_pop_next] = 0.0
	_pop_next = (_pop_next + 1) % POPS


# Called when the player takes damage.
func flash() -> void:
	_flash = 1.0


# Shows a message near the bottom of the screen for a few seconds.
func notice(text: String) -> void:
	notice_text = text
	_notice_time = 3.0


# A power-up was taken: its name across the screen for a moment.
func callout(text: String, color: Color) -> void:
	_call_text = text.to_upper()
	_call_color = color
	_call_time = CALL_TIME


# The nuke: the screen goes white and clears within a second.
func flash_white() -> void:
	_white = 1.0


# Full black, then fades out over about a second (used after teleporting).
func play_fade() -> void:
	_fade = 1.0


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.0, 0.0)
	_fade = maxf(_fade - delta, 0.0)
	_notice_time = maxf(_notice_time - delta, 0.0)
	_call_time = maxf(_call_time - delta, 0.0)
	_white = maxf(_white - delta * 1.3, 0.0)
	for i in POPS:
		_pop_age[i] = minf(_pop_age[i] + delta, POP_TIME)
	if round_number != _round_seen:
		_round_seen = round_number
		_round_flash = 1.0
	_round_flash = maxf(_round_flash - delta * 0.4, 0.0)
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var view := get_viewport_rect().size
	_draw_flash(view)
	if show_speed:
		draw_string(_font, Vector2(0, view.y * 0.5 + 64.0), "%d u/s" % player.speed_units(), HORIZONTAL_ALIGNMENT_CENTER, view.x, 16, Color(1, 1, 1, 0.75))
	if prompt_text != "":
		draw_string(_font, Vector2(0, view.y * 0.62), prompt_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, 22, WHITE)
	if _notice_time > 0.0:
		draw_string(_font, Vector2(0, view.y * 0.7), notice_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, 20, Color(1, 0.85, 0.5, minf(_notice_time, 1.0)))
	if _fade > 0.0:
		draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, _fade))
	if _white > 0.0:
		draw_rect(Rect2(Vector2.ZERO, view), Color(1.0, 0.96, 0.86, _white * 0.8))
	_draw_powers(view)
	var shift := _draw_round(view)  # the round takes the corner; the health ring moves over
	_draw_perks(view, shift)
	_draw_health(Vector2(MARGIN + shift + RING_RADIUS + 8.0, view.y - MARGIN - RING_RADIUS - 8.0))
	_draw_status(Vector2(MARGIN + shift, view.y - MARGIN - RING_RADIUS * 2.0 - 40.0))
	_draw_weapons(view)
	_draw_points(view)
	_draw_top(view)
	if course_text != "":
		_text(Vector2(0, 92.0), course_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, 24, Color(0.75, 0.95, 1.0))
	if quest_text != "":
		var lines := quest_text.split("\n")
		draw_string(_font, Vector2(MARGIN, 96.0), lines[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.6, 0.85, 1.0))
		if lines.size() > 1:
			draw_string(_font, Vector2(MARGIN, 116.0), lines[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.85, 1.0, 0.75))


# The round in the bottom left corner, in red chalk: tallies up to 5, then a number; the colosseum shows "3 / 8".
# "Enemies left" sits above it. Returns the width it takes (0 when no round is running).
func _draw_round(view: Vector2) -> float:
	if round_number <= 0:
		return 0.0
	var color := CHALK.lerp(Color.WHITE, _round_flash * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)))
	var o := Vector2(MARGIN + 6.0, view.y - MARGIN - TALLY_H)
	var w := 0.0
	if round_of > 0:
		w = ChalkMarks.number(self, o, round_number, TALLY_H, color)
		draw_string(_font, o + Vector2(w + 2.0, TALLY_H), "/ %d" % round_of, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(color, 0.85))
		w += 46.0
	elif round_number <= 5:
		w = ChalkMarks.tally(self, o, round_number, TALLY_H, color)
	else:
		w = ChalkMarks.number(self, o, round_number, TALLY_H, color)
	if enemies_left >= 0:
		_text(Vector2(MARGIN + 6.0, o.y - 14.0), "Enemies left  %d" % enemies_left, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, WHITE)
	return maxf(w + 20.0, TALLY_W)


# Our points above the held gun, the party's above ours, and the pop-ups flying off to the left.
func _draw_points(view: Vector2) -> void:
	if _score == null or not show_points:
		return
	var right := view.x - MARGIN
	var base := view.y - MARGIN - SLOT_H - 32.0
	var widest := _font.get_string_size("%d" % int(_score.points), HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
	for other: Dictionary in party:
		widest = maxf(widest, _font.get_string_size("%s   %d" % [other["name"], other["points"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
	var top := base - 30.0 if party.is_empty() else base - 40.0 - 20.0 * float(party.size() - 1) - 15.0
	draw_rect(Rect2(right - widest - 12.0, top, widest + 20.0, base - top + 10.0), Color(0.12, 0.12, 0.13, 0.42))  # a faint box behind our points and the party's
	_text(Vector2(right - 300.0, base), "%d" % int(_score.points), HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 34, POINTS)
	for i in party.size():
		var other: Dictionary = party[i]
		_text(Vector2(right - 300.0, base - 40.0 - 20.0 * i), "%s   %d" % [other["name"], other["points"]], HORIZONTAL_ALIGNMENT_RIGHT, 300.0, 15, Color(1, 1, 1, 0.85))
	for i in POPS:
		if _pop_age[i] >= POP_TIME:
			continue
		var t := _pop_age[i] / POP_TIME
		var amount := _pop_amount[i]
		var at := Vector2(right - 170.0 - 90.0 * t, base - 10.0 + (float(i % 4) - 1.5) * 26.0 * t)
		var tint := Color(1.0, 0.85, 0.2, 1.0 - t * t) if amount > 0 else Color(0.95, 0.3, 0.3, 1.0 - t * t)
		_text(at - Vector2(80.0, 0.0), ("+%d" if amount > 0 else "%d") % amount, HORIZONTAL_ALIGNMENT_RIGHT, 80.0, 22, tint)


# The power-up just taken, called out across the screen, and the ones still running in a row above the holster bar:
# name, seconds left and a bar that runs down; one about to end blinks.
func _draw_powers(view: Vector2) -> void:
	if _call_time > 0.0:
		_text(Vector2(0, view.y * 0.3), _call_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, 48, Color(_call_color.r, _call_color.g, _call_color.b, clampf(_call_time / 0.6, 0.0, 1.0)))
	if powerups == null:
		return
	var kinds: Array[String] = powerups.timed()
	var running := 0
	for kind in kinds:
		if bool(powerups.is_on(kind, power_now)):
			running += 1
	if running == 0:
		return
	var x := (view.x - (float(running) * (POWER_BOX.x + 8.0) - 8.0)) * 0.5
	var y := view.y - MARGIN - 44.0 - 12.0 - POWER_BOX.y
	for kind in kinds:
		if not bool(powerups.is_on(kind, power_now)):
			continue
		var left: float = powerups.left(kind, power_now)
		var color: Color = powerups.color_of(kind)
		if left < 5.0 and fmod(left * 3.0, 1.0) < 0.35:
			color.a = 0.35
		var r := Rect2(Vector2(x, y), POWER_BOX)
		draw_rect(r, BACK)
		draw_rect(Rect2(x, y + POWER_BOX.y - 5.0, POWER_BOX.x * clampf(left / float(powerups.seconds_of(kind)), 0.0, 1.0), 5.0), color)
		draw_rect(r, color, false, 2.0)
		draw_string(_font, Vector2(x + 8.0, y + 23.0), String(powerups.name_of(kind)), HORIZONTAL_ALIGNMENT_LEFT, POWER_BOX.x - 56.0, 15, color)
		draw_string(_font, Vector2(x + POWER_BOX.x - 50.0, y + 23.0), "%d s" % ceili(left), HORIZONTAL_ALIGNMENT_RIGHT, 42.0, 15, WHITE)
		x += POWER_BOX.x + 8.0


# The perks carried: a row of tags in each perk's colour with its initials, right of the health ring.
func _draw_perks(view: Vector2, shift: float) -> void:
	if perks == null:
		return
	var owned: Array = perks.get("owned")
	var x := MARGIN + shift + RING_RADIUS * 2.0 + 30.0
	var y := view.y - MARGIN - 34.0
	for id: String in owned:
		var tint: Color = perks.call("color_of", id)
		draw_rect(Rect2(x, y, 30.0, 30.0), tint)
		draw_rect(Rect2(x, y, 30.0, 30.0), BACK, false, 2.0)
		var words: PackedStringArray = String(perks.call("name_of", id)).split(" ")
		draw_string(_font, Vector2(x, y + 21.0), words[0].left(1) + (words[words.size() - 1].left(1) if words.size() > 1 else ""), HORIZONTAL_ALIGNMENT_CENTER, 30.0, 15, Color(0.05, 0.05, 0.06))
		x += 34.0


# Text with a dark edge, readable over sand and sky alike.
func _text(at: Vector2, text: String, align: HorizontalAlignment, width: float, size: int, color: Color) -> void:
	draw_string_outline(_font, at, text, align, width, size, 4, Color(0, 0, 0, 0.7 * color.a))
	draw_string(_font, at, text, align, width, size, color)


func _draw_flash(view: Vector2) -> void:
	if _flash <= 0.0:
		return
	for i in FLASH_STRIPS:
		var color := Color(0.8, 0.02, 0.02, _flash * 0.45 * (1.0 - float(i) / FLASH_STRIPS))
		var d := i * FLASH_STRIP_W
		draw_rect(Rect2(d, 0, FLASH_STRIP_W, view.y), color)
		draw_rect(Rect2(view.x - d - FLASH_STRIP_W, 0, FLASH_STRIP_W, view.y), color)
		draw_rect(Rect2(0, d, view.x, FLASH_STRIP_W), color)
		draw_rect(Rect2(0, view.y - d - FLASH_STRIP_W, view.x, FLASH_STRIP_W), color)


func _draw_health(c: Vector2) -> void:
	var ratio: float = clampf(player.health.hp / player.health.max_hp, 0.0, 1.0)
	var color := GOOD if ratio > 0.6 else (WARN if ratio > 0.3 else BAD)
	draw_circle(c, RING_RADIUS + RING_WIDTH * 0.5 + 2.0, BACK)
	draw_arc(c, RING_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.12), RING_WIDTH, true)
	if ratio > 0.0:
		draw_arc(c, RING_RADIUS, -PI * 0.5, -PI * 0.5 + TAU * ratio, 48, color, RING_WIDTH, true)
	draw_arc(c, RING_RADIUS - 11.0, 0.0, TAU, 48, DIM, 1.5, true)
	# heart icon
	draw_circle(c + Vector2(-6, -6), 7.0, color)
	draw_circle(c + Vector2(6, -6), 7.0, color)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-12.5, -3), c + Vector2(12.5, -3), c + Vector2(0, 14)]), color)
	draw_string(_font, c + Vector2(-30, 38), "%d" % ceilf(player.health.hp), HORIZONTAL_ALIGNMENT_CENTER, 60, 16, WHITE)
	if cigarette >= 0.0:  # the cigarette burning down: paper, a filter on the left, the ember at the burning end
		var bar := Rect2(c + Vector2(-RING_RADIUS, RING_RADIUS + RING_WIDTH * 0.5 + 5.0), Vector2(RING_RADIUS * 2.0, 5.0))
		draw_rect(bar.grow(1.0), BACK)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * 0.18, bar.size.y)), Color(0.85, 0.55, 0.2))
		var paper := (bar.size.x * 0.82) * cigarette
		draw_rect(Rect2(bar.position + Vector2(bar.size.x * 0.18, 0.0), Vector2(paper, bar.size.y)), BAD if cigarette_warn else Color(0.95, 0.93, 0.88))
		if cigarette > 0.0:
			draw_rect(Rect2(bar.position + Vector2(bar.size.x * 0.18 + paper - 3.0, 0.0), Vector2(3.0, bar.size.y)), Color(1.0, 0.45, 0.1))


# Armor summary and active elemental effects above the health ring.
func _draw_status(o: Vector2) -> void:
	draw_string(_font, o, "DEF %d   BLOCK %d%%" % [int(player.armor["defense"]), roundi(float(player.armor["block"]) * 100.0)], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WHITE)
	var x := 0.0
	for element in ["fire", "ice", "toxic"]:
		var left: float = player.status.remaining(element)
		if left > 0.0:
			_draw_status_icon(element, o + Vector2(x + 22.0, -64.0), left, float(player.status.full_seconds(element)))
			x += 56.0


# One status badge: dark disc, drawn symbol, shrinking timer ring, seconds left underneath.
func _draw_status_icon(element: String, c: Vector2, left: float, full: float) -> void:
	var col := {"fire": Color(1.0, 0.5, 0.15), "ice": Color(0.6, 0.85, 1.0), "toxic": Color(0.5, 0.95, 0.35)}[element] as Color
	draw_circle(c, 20.0, BACK)
	draw_arc(c, 20.0, -PI * 0.5, -PI * 0.5 + TAU * clampf(left / maxf(full, 0.01), 0.0, 1.0), 24, col, 3.0)
	match element:
		"fire":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -13), c + Vector2(8, -2), c + Vector2(9, 6), c + Vector2(4, 12), c + Vector2(-4, 12), c + Vector2(-9, 6), c + Vector2(-7, -3), c + Vector2(-3, 0)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0), c + Vector2(4, 7), c + Vector2(2, 11), c + Vector2(-2, 11), c + Vector2(-4, 7)]), Color(1.0, 0.9, 0.3))
		"ice":
			for i in 3:
				var d := Vector2.from_angle(i * PI / 3.0) * 12.0
				draw_line(c - d, c + d, col, 2.5)
			draw_circle(c, 3.0, WHITE)
		"toxic":
			draw_circle(c + Vector2(0, -2), 9.0, col)
			draw_rect(Rect2(c + Vector2(-5, 4), Vector2(10, 7)), col)
			draw_circle(c + Vector2(-3.5, -3), 2.6, Color(0.05, 0.1, 0.05))
			draw_circle(c + Vector2(3.5, -3), 2.6, Color(0.05, 0.1, 0.05))
			draw_line(c + Vector2(-2, 7), c + Vector2(-2, 11), Color(0.05, 0.1, 0.05), 1.5)
			draw_line(c + Vector2(2, 7), c + Vector2(2, 11), Color(0.05, 0.1, 0.05), 1.5)
	draw_string(_font, c + Vector2(-20, 34), "%.1fs" % left, HORIZONTAL_ALIGNMENT_CENTER, 40, 11, WHITE)


func _draw_weapons(view: Vector2) -> void:
	if player.guns_locked or blind:  # the fantasy world: no guns there, so no holster bar and no gun box
		return
	_draw_holsters(view)
	var now := Time.get_ticks_msec() / 1000.0
	var x := view.x - MARGIN - SLOT_W
	var top := view.y - MARGIN - SLOT_H
	var w = player.held_weapon()
	if w == null:
		if player.knife_out():  # the knife: its type's name where a gun shows its ammo
			draw_rect(Rect2(x, top, SLOT_W, SLOT_H), BACK)
			draw_rect(Rect2(x, top, SLOT_W, SLOT_H), WHITE, false, 2.0)
			draw_string(_font, Vector2(x + 8, top + 18), InputSetup.label(player.settings, "knife"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WHITE)
			ItemIcons.draw(self, "knife", Rect2(x + 24, top + 4, 100, 34), WHITE)
			draw_string(_font, Vector2(x + 8, top + 54), KnifeModels.db().name_of(player.knife), HORIZONTAL_ALIGNMENT_RIGHT, SLOT_W - 16.0, 15, WHITE)
		elif player.hand_index() == Player.SHIELD:  # the shield held up: its name and the hits it still takes
			draw_rect(Rect2(x, top, SLOT_W, SLOT_H), BACK)
			draw_rect(Rect2(x, top, SLOT_W, SLOT_H), WHITE, false, 2.0)
			draw_string(_font, Vector2(x + 8, top + 18), InputSetup.label(player.settings, "shield"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WHITE)
			draw_string(_font, Vector2(x + 8, top + 36), String(player.shield.cfg["name"]), HORIZONTAL_ALIGNMENT_RIGHT, SLOT_W - 16.0, 15, WHITE)
			draw_string(_font, Vector2(x + 8, top + 56), "%d / %d" % [player.shield.hits_left, player.shield.max_hits()], HORIZONTAL_ALIGNMENT_RIGHT, SLOT_W - 16.0, 18, WHITE)
		return
	draw_rect(Rect2(x, top, SLOT_W, SLOT_H), BACK)
	draw_rect(Rect2(x, top, SLOT_W, SLOT_H), WHITE, false, 2.0)
	draw_string(_font, Vector2(x + 8, top + 18), InputSetup.label(player.settings, "weapon_%d" % (player.hand_index() + 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WHITE)
	var gun: Dictionary = player.held_gun()
	var tint := WHITE
	if not gun.is_empty():
		tint = TierStyle.color(player.gun_db, String(gun["tier"]), now)
		draw_rect(Rect2(x, top, SLOT_W, SLOT_H), tint, false, 3.0)
		TierStyle.draw_name(self, _font, Vector2(x, top - 6), player.gun_db, String(gun["tier"]), GunStats.display_name(player.gun_db, gun), 14, tint, SLOT_W)
	ItemIcons.draw(self, w.weapon_id, Rect2(x + 24, top + 8, 100, 34), tint)
	var low: bool = w.ammo <= maxi(1, w.mag_size / 4)
	var spare: int = w.spare()
	var pip_w: float = 104.0 / w.mag_size
	for p in w.mag_size:
		var lit: bool = p < w.ammo
		var pip_color: Color = (BAD if low else WHITE) if lit else Color(1, 1, 1, 0.1)
		draw_rect(Rect2(x + 8 + p * pip_w, top + 44, maxf(pip_w - 2.0, 1.0), 10), pip_color)
	draw_string(_font, Vector2(x + 106, top + 54), "%d" % w.ammo, HORIZONTAL_ALIGNMENT_RIGHT, 44, 30, BAD if low else WHITE)
	draw_string(_font, Vector2(x + 153, top + 54), "/ %d" % spare, HORIZONTAL_ALIGNMENT_LEFT, 46, 14, BAD if spare <= 0 else WHITE)  # what is left in this gun body's pool
	if w.is_reloading():
		var frac: float = w.reload_fraction(now)
		draw_rect(Rect2(x + 4, top + 3, SLOT_W - 8, 5), Color(1, 1, 1, 0.15))
		draw_rect(Rect2(x + 4, top + 3, (SLOT_W - 8) * frac, 5), WARN)
	_draw_skills(x, top, tint)


# The held gun's Q/E skills, left of the weapon slot: key, name, cooldown fill and seconds left.
func _draw_skills(x: float, top: float, tint: Color) -> void:
	var count: int = player.skill_count()
	for i in count:
		var r := Rect2(x - (count - i) * (SKILL_W + 6.0), top + SLOT_H - SKILL_H, SKILL_W, SKILL_H)
		var left: float = player.skill_cooldown_left(i)
		var total: float = maxf(player.skill_cooldown_total(i), 0.01)
		draw_rect(r, BACK)
		if left > 0.0:
			draw_rect(Rect2(r.position.x, r.position.y, r.size.x * (1.0 - left / total), r.size.y), Color(1, 1, 1, 0.12))
		draw_rect(r, tint if left <= 0.0 else DIM, false, 2.0)
		draw_string(_font, r.position + Vector2(6, 17), InputSetup.label(player.settings, "skill_%d" % (i + 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, WHITE)
		draw_string(_font, r.position + Vector2(6, 36), player.skill_name(i), HORIZONTAL_ALIGNMENT_LEFT, SKILL_W - 12.0, 13, tint if left <= 0.0 else DIM)
		if left > 0.0:
			draw_string(_font, r.position + Vector2(SKILL_W - 46.0, 17), "%.1fs" % left, HORIZONTAL_ALIGNMENT_RIGHT, 40, 13, WARN)


# What is carried ready, in the order of its keys: gun 1, gun 2, the knife, then the guns of extra holsters. Each
# box shows its key, the gun (in its tier's colour) and the rounds in it; the one in hand is lit.
func _draw_holsters(view: Vector2) -> void:
	var inventory = player.inventory
	var count: int = inventory.holster_count
	var box := Vector2(84.0, 44.0)
	var x := (view.x - ((count + 1) * (box.x + 6.0) - 6.0)) * 0.5
	var y := view.y - MARGIN - box.y
	for place in count + 1:
		var holster := place if place < 2 else (Player.KNIFE if place == 2 else place - 1)
		if count < 2 and place == count:
			holster = Player.KNIFE
		var r := Rect2(x + place * (box.x + 6.0), y, box.x, box.y)
		var selected: bool = holster == player.hand_index()
		draw_rect(r, BACK)
		draw_rect(r, WHITE if selected else DIM, false, 2.0 if selected else 1.0)
		draw_string(_font, r.position + Vector2(4, 13), InputSetup.label(player.settings, "knife" if holster == Player.KNIFE else "weapon_%d" % (holster + 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WHITE if selected else DIM)
		if holster == Player.KNIFE:
			ItemIcons.draw(self, "knife", r.grow(-8), WHITE if selected else Color(1, 1, 1, 0.6))
			continue
		var body: String = inventory.holster_body(holster)
		if body == "":
			continue
		var tint := WHITE
		var gun: Dictionary = inventory.holster_gun(holster)
		if not gun.is_empty():
			tint = TierStyle.color(player.gun_db, String(gun["tier"]), Time.get_ticks_msec() / 1000.0)
			draw_rect(r, tint, false, 2.0)
		ItemIcons.draw(self, body, Rect2(r.position + Vector2(14, 4), Vector2(box.x - 20.0, box.y - 12.0)), tint)
		var rounds: int = inventory.loaded[holster]
		if rounds >= 0:
			draw_string(_font, r.end - Vector2(34, 4), str(rounds), HORIZONTAL_ALIGNMENT_RIGHT, 30, 12, BAD if rounds == 0 else WHITE)
	if player.shield.owned:  # the buildable shield: its key, and a plate that empties as it takes hits
		var slot := Rect2(x + (count + 1) * (box.x + 6.0), y, 56.0, box.y)
		var up: bool = player.hand_index() == Player.SHIELD
		draw_rect(slot, BACK)
		draw_rect(slot, WHITE if up else DIM, false, 2.0 if up else 1.0)
		draw_string(_font, slot.position + Vector2(4, 13), InputSetup.label(player.settings, "shield"), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, WHITE if up else DIM)
		var share := float(player.shield.hits_left) / maxf(float(player.shield.max_hits()), 1.0)
		var plate := Rect2(slot.position + Vector2(22, 8), Vector2(22, 30))
		draw_rect(Rect2(plate.position + Vector2(0, plate.size.y * (1.0 - share)), Vector2(plate.size.x, plate.size.y * share)), BAD if share <= 0.25 else WHITE)
		draw_rect(plate, WHITE, false, 1.0)


func _draw_top(view: Vector2) -> void:
	if coins >= 0:
		draw_circle(Vector2(view.x - 150.0, 26.0), 10.0, Color(1.0, 0.8, 0.25))
		draw_arc(Vector2(view.x - 150.0, 26.0), 6.0, 0.0, TAU, 16, Color(0.7, 0.5, 0.1), 2.0)
		draw_string(_font, Vector2(view.x - 134.0, 33.0), "%d" % coins, HORIZONTAL_ALIGNMENT_LEFT, 120, 20, WHITE)
	if level > 0:
		draw_string(_font, Vector2(view.x - 150.0, 62.0), "LV %d" % level, HORIZONTAL_ALIGNMENT_LEFT, 60, 16, WHITE)
		draw_rect(Rect2(view.x - 108.0, 52.0, 96.0, 8.0), BACK)
		draw_rect(Rect2(view.x - 106.0, 54.0, 92.0 * clampf(xp_ratio, 0.0, 1.0), 4.0), Color(0.45, 0.8, 1.0))
	draw_string(_font, Vector2(0, 30), wave_text, HORIZONTAL_ALIGNMENT_CENTER, view.x, 20, WHITE)
	if boss_ratio >= 0.0:
		var w := 360.0
		var x := (view.x - w) * 0.5
		draw_rect(Rect2(x - 2, 40, w + 4, 16), BACK)
		draw_rect(Rect2(x, 42, w * clampf(boss_ratio, 0.0, 1.0), 12), BOSS)
		# skull icon at the left end of the bar
		var c := Vector2(x - 18, 48)
		draw_circle(c + Vector2(0, -1), 7.0, BOSS)
		draw_rect(Rect2(c + Vector2(-4, 3), Vector2(8, 5)), BOSS)
		draw_circle(c + Vector2(-3, -1), 2.0, BACK)
		draw_circle(c + Vector2(3, -1), 2.0, BACK)
