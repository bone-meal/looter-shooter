# Purpose: the crate opening screen (polish1 item 72, "exactly like CS:GO"): the crate in the middle of the screen
# with OPEN; on OPEN the lid lifts off in a burst of the crate's light, a reel of possible guns slides in and spins
# past a gold centre line with a tick per gun, slows and stops on the winner; the winner is shown with its rarity
# chime, then Open another / Done. Draws and asks only: the session takes the crate, rolls the guns and pays out.
# Dependencies: game/ui_skin.gd, game/item_icons.gd, game/tier_style.gd, game/tier_sound.gd, core/gun_db.gd + core/gun_stats.gd
# (names), assets/ui/cases/<id>[_body|_lid].png (tools/blender/crates.py).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const ItemIcons = preload("res://game/item_icons.gd")
const TierStyle = preload("res://game/tier_style.gd")
const TierSound = preload("res://game/tier_sound.gd")
const GunStats = preload("res://core/gun_stats.gd")

signal open_pressed(crate_id: String)  # take one crate and roll: the session answers with spin()
signal landed(crate_id: String)  # the reel stopped: the winner is the player's now
signal again(crate_id: String)  # Open another (same kind)
signal closed

const TILE := Vector2(210, 156)
const GAP := 10.0
const SPIN_SECONDS := 6.5
const LID_SECONDS := 0.7
const PICTURES := "res://assets/ui/cases/"
const CTILE := Vector2(180, 112)  # (polish1 D5a) the camo reel's tiles
const CamoSkin = preload("res://game/camo_skin.gd")
const CamoIcons = preload("res://game/camo_icons.gd")

var gun_db: RefCounted
var sounds: Node  # game/fantasy_sounds.gd: "hub_tick" per gun passing the line
var left := 0  # how many more crates of this kind the player has (for Open another)

var _crate: Dictionary = {}
var _reel: Array = []  # gun dicts
var _win := 0
var _camos: Array = []  # (polish1 D5a) the second reel: camo items {id, wear, seed, uses}
var _camo_win := 0
var _camo_stop := 0.0
var _phase := ""  # "case" | "lid" | "spin" | "won"
var _t := 0.0
var _stop := 0.0  # where the reel stops (pixels from its start to the centre line)
var _ticked := -1
var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _pics := {}  # name -> Texture2D
var _chime := AudioStreamPlayer.new()
var _font: Font = ThemeDB.fallback_font
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_chime)
	set_process(false)
	_rng.randomize()


# Shows the crate with OPEN. crate = an entry of data/gun_loot.json "vendor".
func show_case(crate: Dictionary, count: int) -> void:
	_crate = crate
	left = count
	_phase = "case"
	_t = 0.0
	visible = true
	set_process(true)


# The session took the crate and rolled: `reel` guns, the winner at `win`.
func spin(reel: Array, win: int, camos: Array = [], camo_win: int = 0) -> void:
	_reel = reel
	_win = win
	_camos = camos
	_camo_win = camo_win
	_camo_stop = float(camo_win) * (CTILE.x + GAP) + CTILE.x * _rng.randf_range(0.12, 0.88)
	_phase = "lid"
	_t = 0.0
	_ticked = -1
	_stop = float(win) * (TILE.x + GAP) + TILE.x * _rng.randf_range(0.12, 0.88)  # lands somewhere inside the winner's tile


func winner() -> Dictionary:
	return _reel[_win] if _win < _reel.size() else {}


func camo_winner() -> Dictionary:
	return _camos[_camo_win] if _camo_win < _camos.size() else {}


func close() -> void:
	if _phase == "lid" or _phase == "spin":
		return  # it is turning: no walking away now
	visible = false
	set_process(false)
	closed.emit()


func is_spinning() -> bool:
	return _phase == "lid" or _phase == "spin"


# Checks: press a control by key ("open", "again", "done", "skip": the spin at its end at once).
func press(key: String) -> bool:
	if key == "skip" and is_spinning():
		_phase = "spin"
		_t = SPIN_SECONDS
		return true
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = (event as InputEventMouseMotion).position
	var b := event as InputEventMouseButton
	if b != null and b.pressed and b.button_index == MOUSE_BUTTON_LEFT:
		for hit: Array in _hits:
			if (hit[0] as Rect2).has_point(b.position):
				(hit[1] as Callable).call()
				break
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	if _phase == "lid" and _t >= LID_SECONDS:
		_phase = "spin"
		_t = 0.0
	elif _phase == "spin":
		var at := _offset()
		var passing := floori((at + TILE.x * 0.5) / (TILE.x + GAP))
		if passing != _ticked:
			_ticked = passing
			if sounds != null:
				sounds.call("play", "hub_tick")
		if _t >= SPIN_SECONDS:
			_phase = "won"
			_t = 0.0
			var tier := String(winner().get("tier", "grey"))
			_chime.stream = TierSound.chime(maxi(ItemIcons.TIER_ORDER.find(tier), 0))
			_chime.play()
			landed.emit(String(_crate.get("id", "")))
	queue_redraw()


# How far the reel has run: fast at first, easing out to a stop on the winner (CS:GO's long slow end).
func _offset() -> float:
	var k := clampf(_t / SPIN_SECONDS, 0.0, 1.0)
	return _stop * (1.0 - pow(1.0 - k, 4.0))


func _pic(file: String) -> Texture2D:
	if not _pics.has(file):
		var path := PICTURES + file + ".png"
		_pics[file] = load(path) if ResourceLoader.exists(path) else null
	return _pics[file]


func _button(r: Rect2, label: String, key: String, act: Callable, big: bool = false) -> void:
	UiSkin.pill(self, _font, r, label, big, r.has_point(_mouse), 26 if big else 17)
	_hits.append([r, act, key])


func _draw() -> void:
	_hits.clear()
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color(0.01, 0.01, 0.02, 0.88))
	var colour := Color(String(_crate.get("color", "#ffd060")))
	var id := String(_crate.get("id", "bronze"))
	var mid := view * 0.5
	var title_y := mid.y - (270.0 if (_phase == "case" or _phase == "lid") else 160.0)
	draw_string(_font, Vector2(0, title_y), String(_crate.get("name", "Crate")).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, view.x, 40, colour.lightened(0.2))
	if _phase == "case" or _phase == "lid":
		var lift := clampf(_t / LID_SECONDS, 0.0, 1.0) if _phase == "lid" else 0.0
		var box := Rect2(mid - Vector2(210, 220), Vector2(420, 420))
		var pulse := 0.5 + 0.5 * sin(_t * 2.5)
		_burst(mid, colour, 0.25 + 0.15 * pulse + lift * 1.2, 260.0 + lift * 300.0)
		if lift <= 0.0:
			var whole := _pic(id)
			if whole != null:
				draw_texture_rect(whole, box, false)
		else:
			var body := _pic(id + "_body")
			var lid := _pic(id + "_lid")
			if body != null:
				draw_texture_rect(body, box, false)
			if lid != null:
				draw_texture_rect(lid, Rect2(box.position + Vector2(lift * 40.0, -lift * 220.0), box.size), false, Color(1, 1, 1, 1.0 - lift))
		if _phase == "case":
			draw_string(_font, Vector2(0, box.end.y + 20.0), "%d in your cases" % left, HORIZONTAL_ALIGNMENT_CENTER, view.x, 18, UiSkin.TEXT_DIM)
			_button(Rect2(Vector2(mid.x - 160.0, box.end.y + 44.0), Vector2(320, 62)), "OPEN", "open", func() -> void: open_pressed.emit(id), true)
			_button(Rect2(Vector2(mid.x - 90.0, box.end.y + 122.0), Vector2(180, 42)), "Back", "done", close)
		return
	var two := not _camos.is_empty()
	_reel_band(mid - Vector2(0, 120.0 if two else 0.0), view)
	if two:
		_camo_band(mid + Vector2(0, 70.0), view)
	if _phase == "won":
		var gun := winner()
		var tier := String(gun.get("tier", "grey"))
		var tint := TierStyle.color(gun_db, tier, _t)
		var gun_name := GunStats.display_name(gun_db, gun)
		var y := mid.y + TILE.y * 0.5 + 70.0
		if two:  # the camo's name under its reel, the gun's under the camo
			var camo := camo_winner()
			var look := CamoSkin.look_of(String(camo.get("id", "")))
			var ctint := TierStyle.color(gun_db, String(look.get("tier", "green")), _t)
			y = mid.y + 70.0 + CTILE.y * 0.5 + 44.0
			draw_string(_font, Vector2(0, y), "%s camo  -  %s  (%s, pattern %d, %d use%s)" % [String(look.get("name", "")), String(gun_db.tier(String(look.get("tier", "green")))["name"]), CamoSkin.wear_name(float(camo.get("wear", 0.0))), int(camo.get("seed", 1)), int(camo.get("uses", 1)), "" if int(camo.get("uses", 1)) == 1 else "s"],
				HORIZONTAL_ALIGNMENT_CENTER, view.x, 22, ctint)
			y += 30.0
		draw_string(_font, Vector2(0, y), String(gun_db.tier(tier)["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, view.x, 30, tint)
		draw_string_outline(_font, Vector2(0, y + 44.0), gun_name, HORIZONTAL_ALIGNMENT_CENTER, view.x, 30, 6, Color(0, 0, 0, 0.8))
		draw_string(_font, Vector2(0, y + 44.0), gun_name, HORIZONTAL_ALIGNMENT_CENTER, view.x, 30, Color.WHITE)
		if left > 0:
			_button(Rect2(Vector2(mid.x - 330.0, y + 80.0), Vector2(320, 56)), "Open another (%d left)" % left, "again", func() -> void: again.emit(id), true)
		_button(Rect2(Vector2(mid.x + (10.0 if left > 0 else -160.0), y + 80.0), Vector2(320 if left > 0 else 320, 56)), "Done", "done", close, left <= 0)


# The light behind the crate: a soft disc and slowly turning rays in the crate's colour.
func _burst(at: Vector2, colour: Color, strength: float, radius: float) -> void:
	for i in 12:
		var a := float(i) * TAU / 12.0 + _t * 0.3
		var w := 0.09
		draw_colored_polygon(PackedVector2Array([at, at + Vector2.from_angle(a - w) * radius, at + Vector2.from_angle(a + w) * radius]),
			Color(colour, 0.08 * strength))
	for k in 6:
		draw_circle(at, radius * (0.25 + 0.12 * float(k)), Color(colour, 0.05 * strength))


# The reel: tiles of guns running right to left past the centre line, edges fading out.
func _reel_band(mid: Vector2, view: Vector2) -> void:
	var band := Rect2(Vector2(0, mid.y - TILE.y * 0.5 - 18.0), Vector2(view.x, TILE.y + 36.0))
	draw_rect(band, Color(0.04, 0.04, 0.06, 0.95))
	draw_line(band.position, Vector2(band.end.x, band.position.y), Color(UiSkin.ACCENT, 0.4), 2.0)
	draw_line(Vector2(0, band.end.y), band.end, Color(UiSkin.ACCENT, 0.4), 2.0)
	var run := _stop if _phase == "won" else _offset()
	var start := mid.x - run  # x of the reel's first tile
	for i in _reel.size():
		var x := start + float(i) * (TILE.x + GAP)
		if x > view.x or x + TILE.x < 0.0:
			continue
		_tile(Rect2(Vector2(x, mid.y - TILE.y * 0.5), TILE), _reel[i], _phase == "won" and i == _win)
	var shade := 260.0  # the ends fade into the dark
	draw_polygon(PackedVector2Array([band.position, band.position + Vector2(shade, 0), Vector2(shade, band.end.y), Vector2(0, band.end.y)]),
		PackedColorArray([Color(0, 0, 0, 0.95), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.95)]))
	draw_polygon(PackedVector2Array([Vector2(view.x - shade, band.position.y), Vector2(view.x, band.position.y), band.end, Vector2(view.x - shade, band.end.y)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.95), Color(0, 0, 0, 0.95), Color(0, 0, 0, 0)]))
	draw_line(Vector2(mid.x, band.position.y - 10.0), Vector2(mid.x, band.end.y + 10.0), UiSkin.ACCENT, 3.0)
	draw_colored_polygon(PackedVector2Array([Vector2(mid.x - 10, band.position.y - 12), Vector2(mid.x + 10, band.position.y - 12), Vector2(mid.x, band.position.y + 2)]), UiSkin.ACCENT)
	draw_colored_polygon(PackedVector2Array([Vector2(mid.x - 10, band.end.y + 12), Vector2(mid.x + 10, band.end.y + 12), Vector2(mid.x, band.end.y - 2)]), UiSkin.ACCENT)


# (polish1 D5a) The camo reel under the gun reel: swatches (the camo on a rifle) running the same way, stopping at the
# same moment on the camo that was rolled.
func _camo_band(mid: Vector2, view: Vector2) -> void:
	var band := Rect2(Vector2(0, mid.y - CTILE.y * 0.5 - 14.0), Vector2(view.x, CTILE.y + 28.0))
	draw_rect(band, Color(0.04, 0.04, 0.06, 0.95))
	draw_line(band.position, Vector2(band.end.x, band.position.y), Color(UiSkin.ACCENT, 0.3), 2.0)
	draw_line(Vector2(0, band.end.y), band.end, Color(UiSkin.ACCENT, 0.3), 2.0)
	var k := clampf(_t / SPIN_SECONDS, 0.0, 1.0) if _phase == "spin" else (1.0 if _phase == "won" else 0.0)
	var run := _camo_stop * (1.0 - pow(1.0 - k, 4.0))
	var start := mid.x - run
	for i in _camos.size():
		var x := start + float(i) * (CTILE.x + GAP)
		if x > view.x or x + CTILE.x < 0.0:
			continue
		var r := Rect2(Vector2(x, mid.y - CTILE.y * 0.5), CTILE)
		var camo: Dictionary = _camos[i]
		var look := CamoSkin.look_of(String(camo.get("id", "")))
		var tint := TierStyle.color(gun_db, String(look.get("tier", "green")), _t)
		var won := _phase == "won" and i == _camo_win
		draw_style_box(UiSkin._box(Color(0.09, 0.09, 0.12), Color(tint, 0.95 if won else 0.5), 8, 3 if won else 1), r)
		var pic := CamoIcons.swatch({"id": String(camo.get("id", "")), "wear": float(camo.get("wear", 0.0)) if i == _camo_win else 0.05, "seed": int(camo.get("seed", 1)) if i == _camo_win else 7}, self)  # (one picture per camo kind for the rest of the reel)
		if pic != null:
			draw_texture_rect(pic, Rect2(r.position + Vector2(8, 4), Vector2(r.size.x - 16.0, r.size.y - 30.0)), false)
		draw_rect(Rect2(Vector2(r.position.x, r.end.y - 6.0), Vector2(r.size.x, 6.0)), tint)
		draw_string(_font, Vector2(r.position.x + 8.0, r.end.y - 12.0), String(look.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16.0, 13, UiSkin.TEXT)
	var shade := 260.0
	draw_polygon(PackedVector2Array([band.position, band.position + Vector2(shade, 0), Vector2(shade, band.end.y), Vector2(0, band.end.y)]),
		PackedColorArray([Color(0, 0, 0, 0.95), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0.95)]))
	draw_polygon(PackedVector2Array([Vector2(view.x - shade, band.position.y), Vector2(view.x, band.position.y), band.end, Vector2(view.x - shade, band.end.y)]),
		PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.95), Color(0, 0, 0, 0.95), Color(0, 0, 0, 0)]))
	draw_line(Vector2(mid.x, band.position.y - 8.0), Vector2(mid.x, band.end.y + 8.0), UiSkin.ACCENT, 3.0)


func _tile(r: Rect2, gun: Dictionary, won: bool) -> void:
	var tier := String(gun.get("tier", "grey"))
	var tint := TierStyle.color(gun_db, tier, _t)
	draw_style_box(UiSkin._box(Color(0.09, 0.09, 0.12), Color(tint, 0.95 if won else 0.5), 8, 3 if won else 1), r)
	ItemIcons.plate(self, r.grow(-6.0), gun_db, tier, _t)
	ItemIcons.draw(self, String(gun.get("body", "")), Rect2(r.position + Vector2(14, 16), Vector2(r.size.x - 28.0, r.size.y - 60.0)), Color.WHITE)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - 8.0), Vector2(r.size.x, 8.0)), tint)
	var label := String((gun_db.get("bodies") as Dictionary).get(String(gun.get("body", "")), {}).get("name", ""))
	draw_string(_font, Vector2(r.position.x + 10.0, r.end.y - 18.0), label, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20.0, 15, UiSkin.TEXT)
