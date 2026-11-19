# Purpose: the SEA QUEST LOG (sea step 13e, LOCKED: an own sea quest page, apart from Aurelind's), real game UI
# (game/ui_skin.gd): every sea quest as a card: title, the person and where they will work, what to do now with the
# way and distance to it (also marked on the chart, key M); done quests below, dimmed. L / Esc closes.
# Dependencies: game/ui_skin.gd, game/sea_quests.gd (set as `quests`: rules, the sea world, the player).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const SIZE := Vector2(860, 560)
const CARD := 104.0
const DIRS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]

var quests: Node3D  # game/sea_quests.gd
var _font: Font = ThemeDB.fallback_font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	visible = true
	queue_redraw()


func close() -> void:
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("quests")):
		quests.call("close_window")
		get_viewport().set_input_as_handled()


func _draw() -> void:
	if quests == null:
		return
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0, 0, 0, 0.5))
	var r := Rect2((view - SIZE) * 0.5, SIZE)
	UiSkin.panel(self, r)
	draw_string(_font, r.position + Vector2(28, 42), "SEA QUESTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, UiSkin.TEXT)
	var rules: RefCounted = quests.get("rules")
	var sea: Node3D = quests.get("_sea")
	var me: Vector3 = sea.call("local_of", (quests.get("_player") as Node3D).global_position)
	var order: Array = (rules.call("quests") as Array).duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(rules.call("done", String(a["id"]))) < int(rules.call("done", String(b["id"]))))
	var y := r.position.y + 64.0
	for q: Dictionary in order:
		var id := String(q["id"])
		var done: bool = rules.call("done", id)
		var card := Rect2(Vector2(r.position.x + 24.0, y), Vector2(r.size.x - 48.0, CARD - 10.0))
		UiSkin.slot(self, card, UiSkin.ACCENT if not done else Color(0, 0, 0, 0), false, "")
		var dim := UiSkin.TEXT_DIM if done else UiSkin.TEXT
		draw_string(_font, card.position + Vector2(16, 28), String(rules.call("word", id, "title")), HORIZONTAL_ALIGNMENT_LEFT, -1, 19, UiSkin.ACCENT if not done else dim)
		var steps := (q["steps"] as Array).size()
		draw_string(_font, Vector2(card.end.x - 150.0, card.position.y + 28.0), "done" if done else "step %d of %d" % [int(rules.call("step_of", id)) + 1, steps], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.TEXT_DIM)
		draw_string(_font, card.position + Vector2(16, 52), "%s  -  will run the %s" % [String(rules.call("word", id, "person")), String(rules.call("word", id, "trade")).to_lower()], HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 32.0, 14, UiSkin.TEXT_DIM)
		draw_string(_font, card.position + Vector2(16, 76), String(rules.call("goal", id)), HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 220.0, 15, dim)
		if not done:
			var to: Vector2 = (rules.call("where", id) as Vector2) - Vector2(me.x, me.z)
			var dir := String(DIRS[posmod(roundi((atan2(to.x, -to.y) / TAU) * 8.0), 8)])
			draw_string(_font, Vector2(card.end.x - 190.0, card.position.y + 76.0), "%s, %d m" % [dir, roundi(to.length())], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UiSkin.ACCENT)
		y += CARD
	var by := r.end.y - 40.0
	var kx := r.end.x - 260.0
	kx += UiSkin.key_cap(self, _font, Vector2(kx, by), "M") + 6.0
	draw_string(_font, Vector2(kx, by + 15.0), "Chart", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	kx += 60.0
	kx += UiSkin.key_cap(self, _font, Vector2(kx, by), "L / Esc") + 6.0
	draw_string(_font, Vector2(kx, by + 15.0), "Close", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
