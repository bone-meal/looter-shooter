# Purpose: the spell box in the bottom right of the HUD while a staff spell is being built: one round socket per
# element the staff can hold, filled in the order the elements were added with that element's own sign (drop, flame,
# stone, gust), the name of what the sequence makes so far in the spell's colour, the four element keys with their
# signs, and the mana bar (shown whenever the staff is out). Drawn in the shared look of game/fantasy_style.gd.
# Dependencies: game/staff_caster.gd (sequence, signals), game/fantasy_world.gd (mana, slots, spells),
# game/input_setup.gd, game/fantasy_style.gd.
extends Control

const InputSetup = preload("res://game/input_setup.gd")
const Style = preload("res://game/fantasy_style.gd")

const CELL := 34.0
const GAP := 5.0
const PER_ROW := 6

var caster: Node3D
var world: Node3D
var settings: RefCounted

var _flash := 0.0
var _named := "?"  # the sequence the spell below was worked out for
var _spell := {}
var _flash_color := Color.WHITE


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	caster.connect("sequence_changed", func(_sequence: String) -> void: queue_redraw())
	caster.connect("refused", _on_refused)


func _on_refused(why: String) -> void:
	_flash = 0.35
	_flash_color = Color(0.4, 0.6, 1.0) if why == "mana" else Color(1.0, 0.4, 0.3)


func _process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	visible = bool(caster.call("staff_out"))
	if visible:
		queue_redraw()


func _draw() -> void:
	var slots := int(world.call("slots"))
	var rows := ceili(float(slots) / float(PER_ROW))
	var width := float(mini(slots, PER_ROW)) * (CELL + GAP) + GAP + 8.0
	var right := size.x - 16.0
	var bottom := size.y - 60.0
	var elements: Dictionary = world.spells.data["elements"]
	# mana
	var bar := Rect2(right - 230.0, bottom + 10.0, 230.0, 12.0)
	Style.bar(self, bar, float(world.get("mana")) / maxf(float(world.call("max_mana")), 1.0), Color(0.27, 0.48, 0.86))
	Style.text(self, bar.position + Vector2(0, 28), "Mana  %d / %d" % [int(world.get("mana")), int(world.call("max_mana"))], 13, Style.FADED)
	var ready := float(world.combat.dodge_ready())  # the thin line over the mana bar: the dodge step coming back
	draw_rect(Rect2(right - 230.0, bottom + 5.0, 230.0 * ready, 3.0), Style.GOLD_DIM if ready < 1.0 else Style.PARCHMENT)
	if not bool(caster.get("channelling")):
		Style.text(self, Vector2(right - 460.0, bottom - 18.0), "Hold %s: gather a spell   tap: staff strike" % InputSetup.label(settings, "shoot"), 13, Style.FADED, HORIZONTAL_ALIGNMENT_RIGHT, 460.0)
		Style.text(self, Vector2(right - 460.0, bottom - 2.0), "Hold %s: ward   %s: dodge step" % [InputSetup.label(settings, "aim"), InputSetup.label(settings, "dodge")], 13, Style.FADED, HORIZONTAL_ALIGNMENT_RIGHT, 460.0)
		return
	var sequence := String(caster.get("sequence"))
	var box := Rect2(right - width, bottom - float(rows) * (CELL + GAP) - GAP - 8.0, width, float(rows) * (CELL + GAP) + GAP + 8.0)
	Style.frame(self, box)
	if _flash > 0.0:
		draw_rect(box, Color(_flash_color, _flash * 2.0), false, 3.0)
	for i in slots:
		var center := box.position + Vector2(4.0 + GAP + float(i % PER_ROW) * (CELL + GAP) + CELL * 0.5, 4.0 + GAP + float(i / PER_ROW) * (CELL + GAP) + CELL * 0.5)
		if i < sequence.length():
			var c: Array = elements[sequence[i]]["color"]
			Style.element_sign(self, sequence[i], center, CELL * 0.5, Color(c[0], c[1], c[2]))
		else:
			draw_circle(center, CELL * 0.5 - 1.0, Color(1, 1, 1, 0.05))
			draw_arc(center, CELL * 0.5 - 1.0, 0.0, TAU, 24, Style.GOLD_DIM, 1.0, true)
	# what it makes so far
	if sequence != _named:  # only work the spell out again when the sequence changes
		_named = sequence
		_spell = world.spells.resolve(sequence)
	var spell := _spell
	var title := "..." if spell.is_empty() else String(spell["name"])
	var tint := Style.PARCHMENT
	if not spell.is_empty():
		var sc: Array = spell["color"]
		tint = Color(sc[0], sc[1], sc[2]).lerp(Color.WHITE, 0.3)
	Style.text(self, Vector2(box.position.x - 300.0, box.position.y - 12.0), title, 22, tint, HORIZONTAL_ALIGNMENT_RIGHT, 300.0 + width)
	# the four keys, each with its element's sign
	var x := right
	var letters: Array = elements.keys()
	for k in range(letters.size() - 1, -1, -1):
		var letter := String(letters[k])
		var c: Array = elements[letter]["color"]
		var label := InputSetup.label(settings, String(elements[letter]["action"]))
		var wide := Style.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		Style.text(self, Vector2(x - wide, box.position.y - 42.0), label, 13, Style.PARCHMENT)
		Style.element_sign(self, letter, Vector2(x - wide - 15.0, box.position.y - 46.0), 9.0, Color(c[0], c[1], c[2]))
		x -= wide + 44.0
