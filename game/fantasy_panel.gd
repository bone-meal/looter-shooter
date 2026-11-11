# Purpose: the fantasy world's window: skills, bag, quests, spells (keys K and L), talking to someone and working at
# a station. It is drawn by hand in the shared look (game/fantasy_style.gd) and is built from icons: icon tabs along
# the top, a grid or cards on the left, one card on the right about whatever is picked. This file is the window itself
# (frame, tabs, mouse, scrolling, and the small drawing helpers the pages share); each page is its own file
# (game/panel_skills.gd, panel_bag.gd, panel_quests.gd, panel_spells.gd, panel_station.gd).
# Dependencies: game/fantasy_world.gd (bag, skills, quests, spells, use_item, accept), game/fantasy_work.gd
# (recipes, make), game/fantasy_style.gd, game/icon_art.gd.
extends Control

signal closed

const Style = preload("res://game/fantasy_style.gd")
const IconArt = preload("res://game/icon_art.gd")
const PanelSkills = preload("res://game/panel_skills.gd")
const PanelBag = preload("res://game/panel_bag.gd")
const PanelQuests = preload("res://game/panel_quests.gd")
const PanelSpells = preload("res://game/panel_spells.gd")
const PanelStation = preload("res://game/panel_station.gd")

const WINDOW := Vector2(990, 620)
const SIDE_WIDTH := 300.0
const TABS := [["Skills", "star"], ["Bag", "bag"], ["Quests", "scroll"], ["Spells", "book"]]

var world: Node3D
var work: Node
var picked := ""  # the key of whatever is picked on the page that is open
var person := {}  # who is being talked to
var station := ""  # which kind of station is open
var found := {}  # spell names cast so far this session -> sequence (the Spells page shows them)
var note := ""  # one line under the window: what the last click did
var scroll := 0.0
var mouse := Vector2(-1, -1)

var _page := ""
var _hots: Array = []  # what can be clicked, rebuilt at every draw: [Rect2, Callable]
var _tip := ""
var _reach := 0.0  # how far the page can be scrolled


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func is_open() -> bool:
	return visible


func open(page: String) -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_page(page)


func open_talk(who: Dictionary) -> void:
	person = who
	open("Talk")


func open_station(kind: String) -> void:
	station = kind
	open("Station")


func close_panel() -> void:
	if not visible:
		return
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


# The Spells page remembers what has been cast.
func note_cast(spell: Dictionary, sequence: String) -> void:
	if String(spell["secret"]) == "":
		found[String(spell["name"])] = sequence


func show_page(page: String) -> void:
	_page = page
	picked = ""
	note = ""
	scroll = 0.0
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()  # counts, levels and what can be made change while it is open


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse = (event as InputEventMouseMotion).position
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var button := event as InputEventMouseButton
		mouse = button.position
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll = maxf(scroll - 60.0, 0.0)
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll = minf(scroll + 60.0, _reach)
		elif button.button_index == MOUSE_BUTTON_LEFT:
			for i in range(_hots.size() - 1, -1, -1):
				if (_hots[i][0] as Rect2).has_point(mouse):
					var act: Callable = _hots[i][1]
					act.call()
					world.call("sound", "ui_click")
					break
		accept_event()
	queue_redraw()


func _draw() -> void:
	_hots.clear()
	_tip = ""
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.5))
	var frame := Rect2((size - WINDOW) * 0.5, WINDOW)
	Style.frame(self, frame, Color(Style.INK, 0.97))
	_draw_tabs(frame)
	var body := Rect2(frame.position + Vector2(18.0, 82.0), Vector2(WINDOW.x - SIDE_WIDTH - 50.0, WINDOW.y - 82.0 - 40.0))
	var side := Rect2(Vector2(body.end.x + 14.0, body.position.y), Vector2(SIDE_WIDTH, body.size.y))
	Style.frame(self, side, Color(0, 0, 0, 0.28))
	_reach = 0.0
	match _page:
		"Skills":
			PanelSkills.draw(self, body, side)
		"Bag":
			PanelBag.draw(self, body, side)
		"Quests":
			PanelQuests.draw(self, body, side, false)
		"Talk":
			PanelQuests.draw(self, body, side, true)
		"Spells":
			PanelSpells.draw(self, body, side)
		"Station":
			PanelStation.draw(self, body, side)
	scroll = minf(scroll, _reach)
	if _reach > 0.0:  # a thin bar at the right edge of the page shows where the view is
		var track := Rect2(body.end.x + 4.0, body.position.y, 3.0, body.size.y)
		draw_rect(track, Color(1, 1, 1, 0.06))
		var share := body.size.y / (body.size.y + _reach)
		draw_rect(Rect2(track.position.x, track.position.y + (scroll / _reach) * track.size.y * (1.0 - share), 3.0, track.size.y * share), Style.GOLD_DIM)
	Style.text(self, Vector2(frame.position.x + 22.0, frame.end.y - 14.0), note, 14, Style.GOLD)
	if _tip != "":
		var wide := Style.font().get_string_size(_tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 16.0
		var at := Vector2(minf(mouse.x + 14.0, size.x - wide - 4.0), mouse.y - 30.0)
		draw_rect(Rect2(at, Vector2(wide, 24.0)), Color(0.03, 0.02, 0.02, 0.95))
		draw_rect(Rect2(at, Vector2(wide, 24.0)), Style.GOLD_DIM, false, 1.0)
		Style.text(self, at + Vector2(8.0, 17.0), _tip, 14)


func _draw_tabs(frame: Rect2) -> void:
	var x := frame.position.x + 18.0
	var list := TABS.duplicate()
	if _page == "Talk":
		list.append([String(person.get("name", "")), "talk"])
	elif _page == "Station":
		list.append([String(world.data["text"].get("station", {}).get(station, {}).get("name", station.capitalize())), String(world.skilling["stations"][station]["icon"])])
	for i in list.size():
		var label := String(list[i][0])
		var wide := maxf(Style.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 70.0, 128.0)
		var tab := Rect2(x, frame.position.y + 16.0, wide, 50.0)
		var current: bool = (i < TABS.size() and label == _page) or i >= TABS.size()
		var over := hot(tab, show_page.bind(label)) if i < TABS.size() else false
		draw_rect(tab, Color(0.4, 0.31, 0.15, 0.55) if current else (Color(1, 1, 1, 0.06) if over else Color(0, 0, 0, 0.25)))
		draw_rect(Rect2(tab.position.x, tab.end.y - 3.0, tab.size.x, 3.0), Style.GOLD if current else Style.GOLD_DIM)
		IconArt.draw(self, String(list[i][1]), Rect2(tab.position + Vector2(8.0, 7.0), Vector2(36.0, 36.0)), Style.GOLD if current else Style.PARCHMENT)
		Style.text(self, tab.position + Vector2(52.0, 32.0), label, 18, Style.PARCHMENT if current else Style.FADED)
		x += wide + 8.0
	var shut := Rect2(frame.end.x - 54.0, frame.position.y + 20.0, 36.0, 36.0)
	var on_shut := hot(shut, close_panel, "Close")
	IconArt.draw(self, "cross", shut.grow(-6.0), Style.PARCHMENT if on_shut else Style.FADED)


# ---------------- what the pages draw with ----------------

# Makes `area` clickable. Returns true while the mouse is over it; `tip` is then shown beside the mouse.
func hot(area: Rect2, on_click: Callable, tip: String = "") -> bool:
	_hots.append([area, on_click])
	var over := area.has_point(mouse)
	if over and tip != "":
		_tip = tip
	return over


func pick(key: String) -> void:
	picked = key
	note = ""


# True if a row from `top` to `top + tall` lies wholly inside the page (rows cut by the edge are not drawn).
func shows(body: Rect2, top: float, tall: float) -> bool:
	return top >= body.position.y - 1.0 and top + tall <= body.end.y + 1.0


# The page says how tall everything on it was, so the wheel knows how far it may scroll.
func content(body: Rect2, bottom: float) -> void:
	_reach = maxf(bottom + scroll - body.end.y, 0.0)


# A square slot with an icon in it. `key` marks it as the picked one, `count` above 1 is written in the corner,
# `faded` shows something missing or locked, `mark` is a small second icon in the top right corner.
func cell(area: Rect2, shape: String, color: Color, key: String = "", on_click: Callable = Callable(), tip: String = "", count: int = 0, faded: bool = false, mark: String = "") -> void:
	var over := hot(area, on_click, tip) if on_click.is_valid() else (area.has_point(mouse) and tip != "")
	if over and tip != "":
		_tip = tip
	var chosen := key != "" and key == picked
	draw_rect(area, Color(0.4, 0.31, 0.15, 0.5) if chosen else Color(0, 0, 0, 0.38))
	draw_rect(area, Style.GOLD if chosen else (Style.PARCHMENT if over else Style.GOLD_DIM), false, 2.0 if chosen else 1.0)
	IconArt.draw(self, shape, area.grow(-5.0), color, 0.3 if faded else 1.0)
	if count > 1:
		Style.text(self, Vector2(area.position.x, area.end.y - 4.0), str(count), 13, Style.PARCHMENT, HORIZONTAL_ALIGNMENT_RIGHT, area.size.x - 4.0)
	if mark != "":
		IconArt.draw(self, mark, Rect2(area.end.x - 19.0, area.position.y + 1.0, 18.0, 18.0), Style.GOLD)


# The slot of an item of the bag: its own icon in its own colour, its name as the tip.
func item_cell(area: Rect2, item: String, key: String = "", on_click: Callable = Callable(), count: int = 0, faded: bool = false, mark: String = "") -> void:
	cell(area, item_shape(item), item_color(item), key, on_click, String(world.bag.item_name(item)), count, faded, mark)


func item_shape(item: String) -> String:
	return String(world.bag.def(item).get("icon", "empty"))


func item_color(item: String) -> Color:
	var c: Array = world.bag.def(item).get("color", [0.8, 0.8, 0.8])
	return Color(c[0], c[1], c[2])


# A small heading inside a page: an icon and a few words over a thin line. Returns where the next thing goes.
func heading(body: Rect2, top: float, shape: String, words: String) -> float:
	if shows(body, top, 26.0):
		IconArt.draw(self, shape, Rect2(body.position.x, top + 1.0, 20.0, 20.0), Style.GOLD)
		Style.text(self, Vector2(body.position.x + 26.0, top + 17.0), words, 15, Style.GOLD)
		draw_line(Vector2(body.position.x, top + 25.0), Vector2(body.end.x - 6.0, top + 25.0), Style.GOLD_DIM, 1.0)
	return top + 32.0


# The top of the card on the right: a large icon, a name and one line under it. Returns where the next row goes.
func card_head(side: Rect2, shape: String, color: Color, title: String, under: String) -> float:
	var art := Rect2(side.position + Vector2(14.0, 14.0), Vector2(76.0, 76.0))
	draw_rect(art, Color(0, 0, 0, 0.35))
	draw_rect(art, Style.GOLD_DIM, false, 1.0)
	IconArt.draw(self, shape, art.grow(-6.0), color)
	Style.paragraph(self, Vector2(art.end.x + 12.0, side.position.y + 36.0), title, 19, Style.PARCHMENT, side.size.x - 116.0, 2)
	Style.text(self, Vector2(art.end.x + 12.0, side.position.y + 84.0), under, 13, Style.FADED)
	return side.position.y + 106.0


# One row of the card on the right: a small icon and a few words. Returns where the next row goes.
func card_row(side: Rect2, top: float, shape: String, color: Color, words: String, tone: Color = Style.PARCHMENT) -> float:
	IconArt.draw(self, shape, Rect2(side.position.x + 16.0, top, 22.0, 22.0), color)
	Style.text(self, Vector2(side.position.x + 46.0, top + 17.0), words, 14, tone, HORIZONTAL_ALIGNMENT_LEFT, side.size.x - 58.0)
	return top + 28.0


# The one large button at the foot of the card on the right.
func card_button(side: Rect2, shape: String, words: String, on_click: Callable) -> void:
	var area := Rect2(side.position.x + 14.0, side.end.y - 58.0, side.size.x - 28.0, 44.0)
	var over := hot(area, on_click)
	draw_rect(area, Color(0.4, 0.31, 0.15, 0.95) if over else Color(0.22, 0.17, 0.1, 0.95))
	draw_rect(area, Style.GOLD, false, 1.0)
	IconArt.draw(self, shape, Rect2(area.position + Vector2(10.0, 7.0), Vector2(30.0, 30.0)), Style.GOLD)
	Style.text(self, area.position + Vector2(0.0, 28.0), words, 17, Style.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER, area.size.x)


# A spell sequence as a row of element signs. Returns how wide the row came out.
func signs(at: Vector2, sequence: String, radius: float) -> float:
	var elements: Dictionary = world.spells.data["elements"]
	for i in sequence.length():
		var c: Array = elements[sequence[i]]["color"]
		Style.element_sign(self, sequence[i], at + Vector2(radius + float(i) * (radius * 2.0 + 3.0), 0.0), radius, Color(c[0], c[1], c[2]))
	return float(sequence.length()) * (radius * 2.0 + 3.0)
