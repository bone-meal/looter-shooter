# Purpose: the fantasy world's menu panel. Pages: Skills (levels and what each is for), Bag (use, eat, equip, light),
# Quests (open and finished, with their steps), Spells (the forms, every mix found so far and the long spells that
# were taught), and two pages that open on their own: a person's talk page (take quests) and a station's recipes.
# Looks: game/fantasy_style.gd (theme).
# Dependencies: game/fantasy_world.gd, game/fantasy_work.gd (recipes). Opened by game/fantasy_world.gd.
extends Control

signal closed

const FantasyStyle = preload("res://game/fantasy_style.gd")
const PAGES := ["Skills", "Bag", "Quests", "Spells"]

var world: Node3D
var work: Node

var _title := Label.new()
var _tabs := HBoxContainer.new()
var _list := ItemList.new()
var _text := RichTextLabel.new()
var _action := Button.new()
var _note := Label.new()
var _page := ""
var _rows: Array = []  # what each list row stands for
var _person := {}
var _station := ""
var _found := {}  # spell names cast so far this session -> sequence (the Spells page lists them)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var middle := CenterContainer.new()
	add_child(middle)
	middle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := PanelContainer.new()
	frame.theme = FantasyStyle.theme()
	frame.custom_minimum_size = Vector2(900, 540)
	middle.add_child(frame)
	var column := VBoxContainer.new()
	frame.add_child(column)
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", FantasyStyle.GOLD)
	column.add_theme_constant_override("separation", 10)
	column.add_child(_title)
	column.add_child(_tabs)
	for page: String in PAGES:
		var tab := Button.new()
		tab.text = page
		tab.pressed.connect(show_page.bind(page))
		_tabs.add_child(tab)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(close_panel)
	_tabs.add_child(close)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	_list.custom_minimum_size = Vector2(380, 380)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_selected)
	_list.item_activated.connect(func(_index: int) -> void: _on_action())
	row.add_child(_list)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	_text.bbcode_enabled = true
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size = Vector2(460, 320)
	side.add_child(_text)
	_action.pressed.connect(_on_action)
	side.add_child(_action)
	column.add_child(_note)


func is_open() -> bool:
	return visible


func open(page: String) -> void:
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show_page(page)


func open_talk(person: Dictionary) -> void:
	_person = person
	open("Talk")


func open_station(kind: String) -> void:
	_station = kind
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
		_found[String(spell["name"])] = sequence


func show_page(page: String) -> void:
	_page = page
	_list.clear()
	_rows.clear()
	_text.text = ""
	_note.text = ""
	_action.visible = false
	_tabs.visible = true
	match page:
		"Skills":
			_title.text = "Skills"
			for id: String in world.skills.ids():
				_add("%s   level %d" % [world.skills.skill_name(id), int(world.skills.level(id))], id)
		"Bag":
			_title.text = "Bag"
			for item: String in world.bag.items:
				var worn := ""
				for slot: String in world.bag.equipped:
					if String(world.bag.equipped[slot]) == item:
						worn = "   (in use)"
				_add("%s  x%d%s" % [world.bag.item_name(item), int(world.bag.count(item)), worn], item)
		"Quests":
			_title.text = "Quests   (chapter %d of 8)" % mini(int(world.quests.chapter()), 8)
			for id: String in world.quests.active:
				_add("> " + String(world.quests.quest(id)["name"]), id)
			for id: String in world.quests.done:
				_add("done: " + String(world.quests.quest(id)["name"]), id)
		"Spells":
			_title.text = "Spells   (%d elements per cast)" % int(world.slots())
			_add("How casting works", "how")
			for id: String in world.quests.secrets():
				_add("Long spell: " + String(world.spells.secret_for_id(id)["name"]), "secret:" + id)
			for found_name: String in _found:
				_add(found_name, "found:" + found_name)
		"Talk":
			_title.text = String(_person["name"])
			_text.text = String(_person["greet"])
			for id: String in world.quests.offers(String(_person["id"])):
				_add("! " + String(world.quests.quest(id)["name"]), id)
			for id: String in world.quests.active:
				if String(world.quests.quest(id)["giver"]) == String(_person["id"]):
					_add("> " + String(world.quests.quest(id)["name"]), id)
			if _rows.is_empty():
				_note.text = "Nothing more to ask of you for now."
		"Station":
			_title.text = String(_station).capitalize()
			for recipe: Dictionary in work.call("recipes", _station):
				var why := String(work.call("cannot_make", recipe))
				_add(("" if why == "" else "(x) ") + String(work.call("recipe_text", recipe)), recipe)
	if not _rows.is_empty():
		_list.select(0)
		_on_selected(0)


func _add(label: String, row: Variant) -> void:
	_list.add_item(label)
	_rows.append(row)


func _on_selected(index: int) -> void:
	var row: Variant = _rows[index]
	_action.visible = false
	match _page:
		"Skills":
			var id := String(row)
			var about: Dictionary = world.skilling["skills"][id]
			var level := int(world.skills.level(id))
			var lines := PackedStringArray(["[b]%s[/b]  level %d" % [about["name"], level], String(about["about"]), ""])
			if level < int(world.skills.max_level()):
				lines.append("Experience: %d  (next level at %d)" % [int(world.skills.xp.get(id, 0)), int(world.skills.xp_for(level + 1))])
			lines.append("")
			for node_id: String in world.skilling["nodes"]:
				var node: Dictionary = world.skilling["nodes"][node_id]
				if String(node["skill"]) == id:
					lines.append("%s level %d: %s" % ["[color=#8f8]" if level >= int(node["level"]) else "[color=#888]", int(node["level"]), node["name"]] + "[/color]")
			for recipe: Dictionary in world.skilling["recipes"]:
				if String(recipe["skill"]) == id:
					lines.append("%s level %d: %s" % ["[color=#8f8]" if level >= int(recipe["level"]) else "[color=#888]", int(recipe["level"]), work.call("recipe_text", recipe)] + "[/color]")
			_text.text = "\n".join(lines)
		"Bag":
			var item := String(row)
			var def: Dictionary = world.bag.def(item)
			var lines := PackedStringArray(["[b]%s[/b]" % def["name"], String(def["kind"]).capitalize()])
			for key: String in ["power", "slots", "mana", "hp", "armor", "regen", "tier", "heal"]:
				if def.has(key):
					lines.append("%s: %s" % [key, str(def[key])])
			_text.text = "\n".join(lines)
			var kind := String(def["kind"])
			_action.visible = kind in ["food", "potion", "staff", "robe", "tool"] or (world.skilling["fire"]["level"] as Dictionary).has(item)
			_action.text = "Eat or drink" if kind in ["food", "potion"] else ("Light a fire with it" if kind == "material" else "Use this one")
		"Quests", "Talk":
			var quest: Dictionary = world.quests.quest(String(row))
			var lines := PackedStringArray(["[b]%s[/b]" % quest["name"], String(quest["text"]), ""])
			if quest.has("level"):
				lines.append("Advised Magic level: %d" % int(quest["level"]))
			var at := int(world.quests.active[String(row)]["step"]) if world.quests.active.has(String(row)) else (999 if world.quests.is_done(String(row)) else -1)
			var steps: Array = quest["steps"]
			for i in steps.size():
				lines.append("%s %s" % ["[color=#8f8]done:[/color]" if i < at else ("[color=#fd6]now:[/color]" if i == at else "-"), steps[i]["text"]])
			_text.text = "\n".join(lines)
			_action.visible = _page == "Talk" and bool(world.quests.can_start(String(row)))
			_action.text = "Take this quest"
		"Spells":
			var key := String(row)
			if key == "how":
				_text.text = _how()
			elif key.begins_with("secret:"):
				var secret: Dictionary = world.spells.secret_for_id(key.trim_prefix("secret:"))
				_text.text = "[b]%s[/b]\n%s\n\n%s" % [secret["name"], secret["desc"], world.spells.spell_out(String(secret["sequence"]))]
			else:
				_text.text = "[b]%s[/b]\n%s" % [key.trim_prefix("found:"), world.spells.spell_out(String(_found[key.trim_prefix("found:")]))]
		"Station":
			var recipe: Dictionary = row
			_text.text = String(work.call("recipe_text", recipe)) + "\n\n" + String(work.call("cannot_make", recipe))
			_action.visible = true
			_action.text = "Make"


func _how() -> String:
	var lines := PackedStringArray(["Hold the cast key with the staff out, add elements, let go.", "", "[b]The first element decides the shape:[/b]"])
	for letter: String in world.spells.data["forms"]:
		var form: Dictionary = world.spells.data["forms"][letter]
		lines.append("%s first: %s, %s" % [world.spells.data["elements"][letter]["name"], form["name"], form["desc"]])
	lines.append("")
	lines.append("[b]The mix decides what it is made of[/b] (the order after the first does not matter):")
	for key: String in world.spells.data["substances"]:
		if key.length() > 1:
			lines.append("%s = %s" % [world.spells.spell_out(key).replace(", ", " + "), world.spells.data["substances"][key]["name"]])
	lines.append("")
	lines.append("[b]The amount decides the size.[/b] Long spells are exact sequences: people teach them as the story goes.")
	return "\n".join(lines)


func _on_action() -> void:
	var picked := _list.get_selected_items()
	if picked.is_empty() or not _action.visible:
		return
	var row: Variant = _rows[picked[0]]
	var said := ""
	match _page:
		"Bag":
			said = String(world.use_item(String(row)))
		"Talk":
			world.accept(String(row))
		"Station":
			said = String(work.call("make", row))
	var keep := picked[0]
	show_page(_page)
	_note.text = said
	if keep < _rows.size():
		_list.select(keep)
		_on_selected(keep)
