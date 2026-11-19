# Purpose: the SUPER BOSS BAR at the top of the screen while a sea boss fight goes on in the arena we stand in (sea
# step 10): the boss's name and title, its health with the phase marks on the bar, the phase's name, and what is
# happening now (shell cracked, stunned, enraged); our own Dread underneath when we carry any. Game UI (game/ui_skin.gd).
# Dependencies: game/ui_skin.gd, game/sea_boss.gd (fight: read every frame), the player (dread).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const W := 620.0

var fight: Node
var player: Node
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font


func _process(_delta: float) -> void:
	var on := fight != null and is_instance_valid(fight) and String(fight.get("boss_id")) != "" and String(fight.get("state")) in ["fight", "won"] and _here()
	if visible != on:
		visible = on
	if on:
		queue_redraw()


func _here() -> bool:
	var dungeons: Node = fight.get_parent()
	var b: Dictionary = fight.call("boss_cfg", String(fight.get("boss_id")))
	return not b.is_empty() and String(dungeons.get("where")) == String(b["arena"])


func _draw() -> void:
	var b: Dictionary = fight.call("boss_cfg", String(fight.get("boss_id")))
	if b.is_empty():
		return
	var view := get_viewport_rect().size
	var x := (view.x - W) * 0.5
	var r := Rect2(x - 16.0, 70.0, W + 32.0, 92.0)
	UiSkin.panel(self, r, UiSkin.INK_DEEP)
	draw_string(_font, Vector2(x, 96.0), String(b["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, W * 0.6, 22, UiSkin.ACCENT)
	draw_string(_font, Vector2(x, 96.0), String(b["title"]), HORIZONTAL_ALIGNMENT_RIGHT, W, 14, UiSkin.TEXT_DIM)
	var share := float(fight.get("hp_share"))
	var bar := Rect2(x, 106.0, W, 16.0)
	UiSkin.bar(self, bar, share, Color(0.86, 0.3, 0.22))
	var phases: Array = b["phases"]
	for p: Dictionary in phases:  # where each next phase begins
		var u := float(p["until"])
		if u > 0.0:
			draw_rect(Rect2(x + W * u - 1.0, 104.0, 2.0, 20.0), UiSkin.TEXT)
	var ph := clampi(int(fight.get("phase")), 0, phases.size() - 1)
	var line := "Phase %d: %s" % [ph + 1, String(phases[ph]["name"])]
	var flags := PackedStringArray()
	if bool(fight.get("cracked")):
		flags.append("SHELL CRACKED")
	if bool(fight.get("stunned")):
		flags.append("STUNNED")
	if bool((fight.get("rules") as RefCounted).get("enraged")):
		flags.append("ENRAGED")
	if String(fight.get("state")) == "won":
		line = "Beaten"
	draw_string(_font, Vector2(x, 144.0), line, HORIZONTAL_ALIGNMENT_LEFT, W * 0.6, 15, UiSkin.TEXT)
	draw_string(_font, Vector2(x, 144.0), "  ".join(flags), HORIZONTAL_ALIGNMENT_RIGHT, W, 15, UiSkin.BAD if flags.size() > 0 else UiSkin.TEXT_DIM)
	var dread := int(player.get("dread")) if player != null else 0
	if dread > 0:
		draw_string(_font, Vector2(x, 182.0), "Dread %d: less health and damage until you rest at a port" % dread, HORIZONTAL_ALIGNMENT_CENTER, W, 14, UiSkin.BAD)
