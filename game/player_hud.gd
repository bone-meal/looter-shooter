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

var player: CharacterBody3D
var wave_text := ""
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


# Full black, then fades out over about a second (used after teleporting).
func play_fade() -> void:
	_fade = 1.0


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta * 2.0, 0.0)
	_fade = maxf(_fade - delta, 0.0)
	_notice_time = maxf(_notice_time - delta, 0.0)
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
	var shift := _draw_round(view)  # the round takes the corner; the health ring moves over
	_draw_health(Vector2(MARGIN + shift + RING_RADIUS + 8.0, view.y - MARGIN - RING_RADIUS - 8.0))
	_draw_status(Vector2(MARGIN + shift, view.y - MARGIN - RING_RADIUS * 2.0 - 40.0))
	_draw_weapons(view)
	_draw_points(view)
	_draw_top(view)


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
	if player.guns_locked:  # the fantasy world: no guns there, so no holster bar and no gun box
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
