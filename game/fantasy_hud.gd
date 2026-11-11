# Purpose: the fantasy world's always-on HUD: a row of round skill medallions in the top left (level in the middle,
# a ring that fills towards the next level), experience and item lines that rise and fade, a card with the tracked
# quests in the top right, the bar while gathering, and the boss's name, health and the name of the attack it is
# about to make. Hidden outside that world. Drawn in the shared look of game/fantasy_style.gd.
# Dependencies: game/fantasy_world.gd (skills, quests, toast and boss_move signals), game/fantasy_work.gd (progress),
# game/fantasy_spawner.gd (boss_awake), game/input_setup.gd, game/fantasy_style.gd.
extends Control

const InputSetup = preload("res://game/input_setup.gd")
const Style = preload("res://game/fantasy_style.gd")
const IconArt = preload("res://game/icon_art.gd")
const PanelQuests = preload("res://game/panel_quests.gd")

const MEDAL := 17.0  # radius of a skill medallion
const MOVE_SECONDS := 2.4
const TOAST_SECONDS := 2.2
const MAX_TOASTS := 8
const TRACKED := 3

var world: Node3D
var work: Node
var spawner: Node
var settings: RefCounted

var _toasts: Array = []  # {"text", "color", "left"}
var _since_draw := 0.0
var _move := ""  # the boss attack being announced
var _move_color := Color.WHITE
var _move_left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.connect("toast", _on_toast)
	world.connect("boss_move", func(text: String, color: Color) -> void:
		_move = text
		_move_color = color
		_move_left = MOVE_SECONDS)


func _on_toast(text: String, color: Color) -> void:
	if _toasts.size() >= MAX_TOASTS:
		_toasts.pop_front()
	_toasts.append({"text": text, "color": color, "left": TOAST_SECONDS})


func _process(delta: float) -> void:
	visible = bool(world.get("inside"))
	if not visible:
		return
	for i in range(_toasts.size() - 1, -1, -1):
		_toasts[i]["left"] = float(_toasts[i]["left"]) - delta
		if float(_toasts[i]["left"]) <= 0.0:
			_toasts.remove_at(i)
	_move_left = maxf(_move_left - delta, 0.0)
	_since_draw += delta
	if _since_draw >= 0.1 or not _toasts.is_empty() or _move_left > 0.0 or float(work.call("progress")) >= 0.0:  # ten redraws a second is enough unless something moves
		_since_draw = 0.0
		queue_redraw()


func _draw() -> void:
	_draw_skills()
	_draw_toasts()
	_draw_quests()
	_draw_work()
	_draw_boss()


func _draw_skills() -> void:
	var ids: Array = world.skills.ids()
	var step := MEDAL * 2.0 + 8.0
	for i in ids.size():
		var id := String(ids[i])
		var tint: Array = world.skilling["skills"][id]["color"]
		var color := Color(tint[0], tint[1], tint[2])
		var center := Vector2(14.0 + MEDAL + float(i) * step, 52.0 + MEDAL)
		draw_circle(center, MEDAL, Style.INK)
		draw_arc(center, MEDAL - 1.5, 0.0, TAU, 32, Style.GOLD_DIM, 1.0, true)
		var share := float(world.skills.progress(id))
		if share > 0.0:
			draw_arc(center, MEDAL - 1.5, -PI * 0.5, -PI * 0.5 + TAU * share, 32, color, 3.0, true)
		IconArt.draw(self, String(world.skilling["skills"][id]["icon"]), Rect2(center - Vector2(11.0, 11.0), Vector2(22.0, 22.0)), color)
		Style.text(self, center + Vector2(-MEDAL - 4.0, MEDAL + 13.0), str(int(world.skills.level(id))), 12, Style.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, MEDAL * 2.0 + 8.0)
	var x := 16.0  # the three keys, each with the sign of what it opens
	for hint: Array in [["skills", "bag"], ["quests", "scroll"], ["map", "map"]]:
		var label := InputSetup.label(settings, String(hint[0]))
		IconArt.draw(self, String(hint[1]), Rect2(x, 52.0 + MEDAL * 2.0 + 20.0, 18.0, 18.0), Style.GOLD)
		Style.text(self, Vector2(x + 22.0, 52.0 + MEDAL * 2.0 + 34.0), label, 13, Color(Style.PARCHMENT, 0.8))
		x += 34.0 + Style.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x


func _draw_toasts() -> void:
	for i in _toasts.size():
		var entry: Dictionary = _toasts[i]
		var age := 1.0 - float(entry["left"]) / TOAST_SECONDS
		var color: Color = entry["color"]
		Style.text(self, Vector2(18.0, 290.0 - float(_toasts.size() - 1 - i) * 21.0 - age * 22.0), String(entry["text"]), 16, Color(color, 1.0 - age * age))


func _draw_quests() -> void:
	var ids: Array = []
	for id: String in world.quests.active:
		if ids.size() < TRACKED:
			ids.append(id)
	var first_steps: bool = ids.is_empty() and int(world.quests.done.size()) == 0
	if ids.is_empty() and not first_steps:
		return
	var width := 360.0
	var card := Rect2(size.x - width - 16.0, 132.0, width, 18.0 + 62.0 * float(maxi(ids.size(), 1)))
	Style.frame(self, card, Style.INK_SOFT)
	var y := card.position.y + 24.0
	if first_steps:
		Style.paragraph(self, Vector2(card.position.x + 14.0, y + 4.0), String(world.call("first_hint")), 14, Style.GOLD, width - 28.0)
		return
	for i in ids.size():
		var quest: Dictionary = world.quests.quest(ids[i])
		IconArt.draw(self, String(PanelQuests.STEP_SHAPES.get(String(world.quests.step(ids[i]).get("type", "")), "dots")), Rect2(card.position.x + 12.0, y - 15.0, 18.0, 18.0), Style.GOLD)
		Style.text(self, Vector2(card.position.x + 36.0, y), String(quest["name"]), 16, Style.GOLD, HORIZONTAL_ALIGNMENT_LEFT, width - 50.0)
		Style.paragraph(self, Vector2(card.position.x + 14.0, y + 19.0), String(world.quests.step_text(ids[i])), 13, Style.PARCHMENT, width - 28.0)
		if i < ids.size() - 1:
			Style.rule(self, Vector2(card.position.x + 40.0, y + 44.0), Vector2(card.end.x - 40.0, y + 44.0))
		y += 62.0


func _draw_work() -> void:
	var share := float(work.call("progress"))
	if share < 0.0:
		return
	var bar := Rect2(size.x * 0.5 - 120.0, size.y * 0.62, 240.0, 12.0)
	Style.bar(self, bar, share, Style.GOLD)
	Style.text(self, bar.position + Vector2(0, -8), String(work.call("working_on")), 15, Style.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x)


func _draw_boss() -> void:
	var boss: Dictionary = spawner.call("boss_awake")
	if boss.is_empty():
		return
	var bar := Rect2(size.x * 0.5 - 270.0, 96.0, 540.0, 14.0)
	Style.text(self, bar.position + Vector2(0, -9), String(boss["name"]).to_upper(), 19, Style.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, bar.size.x)
	Style.bar(self, bar, float(boss["ratio"]), Color(0.66, 0.16, 0.14))
	if _move_left > 0.0:  # the attack it is winding up, in the colour of its warning on the ground
		var fade := minf(_move_left / 0.6, 1.0)
		Style.text(self, bar.position + Vector2(0, 40.0), _move, 22, Color(_move_color.lerp(Color.WHITE, 0.25), fade), HORIZONTAL_ALIGNMENT_CENTER, bar.size.x)
