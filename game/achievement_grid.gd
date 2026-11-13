# Purpose: the Achievements tab of the player card as a grid of icons: each achievement shows its reward emblem
# (bright with a gold edge when unlocked, dimmed with a progress bar when not); hovering one shows what it asks,
# how far it is, and what it gives.
# Dependencies: core/progress_state.gd (passed to build), game/emblem_art.gd.
extends RefCounted

const EmblemArt = preload("res://game/emblem_art.gd")
const STEP := 70.0  # one icon plus the gap: the grid fits as many columns as the width allows
const UNLOCKED_EDGE := Color(1.0, 0.82, 0.3)


# One achievement icon. Its tooltip is the whole story of that achievement.
class Tile extends Control:
	var def := {}  # its reward emblem (data/achievements.json "emblems"); empty = a plain star
	var done := false
	var ratio := 0.0  # progress toward the goal, 0..1

	func _init() -> void:
		custom_minimum_size = Vector2(64, 70)
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var box := Rect2(Vector2(2, 2), Vector2(60, 60))
		draw_rect(box, Color(0.14, 0.16, 0.22) if done else Color(0.09, 0.1, 0.13))
		draw_rect(box, UNLOCKED_EDGE if done else Color(1, 1, 1, 0.12), false, 2.0 if done else 1.0)
		if def.is_empty():
			EmblemArt.draw(self, "star", box.get_center(), 22.0, Color(0.85, 0.85, 0.9), Color(0.4, 0.4, 0.45))
		else:
			EmblemArt.draw_def(self, def, box.get_center(), 24.0)
		if not done:
			draw_rect(box.grow(-1.0), Color(0.03, 0.03, 0.05, 0.62))
			draw_rect(Rect2(Vector2(4, 65), Vector2(56, 4)), Color(1, 1, 1, 0.12))
			draw_rect(Rect2(Vector2(4, 65), Vector2(56.0 * ratio, 4)), Color(0.45, 0.8, 1.0))

	func _make_custom_tooltip(for_text: String) -> Object:
		var label := Label.new()
		label.text = for_text
		label.add_theme_font_size_override("font_size", 16)
		return label


# The whole tab: a line with the count, then the icons (they scroll).
static func build(progress: RefCounted) -> Control:
	var defs: Dictionary = progress.achievement_defs()
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	var summary := Label.new()
	summary.add_theme_font_size_override("font_size", 16)
	page.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 16
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	scroll.resized.connect(func() -> void: grid.columns = maxi(4, floori((scroll.size.x - 14.0) / STEP)))
	var count := 0
	for id: String in defs:
		var a: Dictionary = defs[id]
		var tile := Tile.new()
		tile.done = progress.unlocked.has(id)
		var have := mini(int(progress.progress_of(a)), int(a["goal"]))
		tile.ratio = float(have) / maxf(float(a["goal"]), 1.0)
		if String(a["emblem"]) != "":
			tile.def = progress.emblem_def(String(a["emblem"]))
		tile.tooltip_text = _story(progress, a, tile.done, have)
		grid.add_child(tile)
		if tile.done:
			count += 1
	summary.text = "%d of %d unlocked  (hover an icon to see what it asks and gives)" % [count, defs.size()]
	return page


# The tooltip: name, done or not, what it asks, how far, the rewards.
static func _story(progress: RefCounted, a: Dictionary, done: bool, have: int) -> String:
	var lines: Array[String] = [String(a["name"]) + ("   UNLOCKED" if done else "   locked")]
	lines.append(("Earned by: " if done else "To earn: ") + String(a["desc"]))
	lines.append("Progress: %s / %s" % [_n(have), _n(int(a["goal"]))])
	if String(a["emblem"]) != "":
		lines.append("Emblem: %s" % String(progress.emblem_def(String(a["emblem"]))["name"]))
	if String(a["title"]) != "":
		lines.append("Title: %s" % progress.title_name(String(a["title"])))
	return "\n".join(lines)


static func _n(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	while text.length() > 3:
		out = "," + text.right(3) + out
		text = text.left(text.length() - 3)
	return ("-" if value < 0 else "") + text + out
