# Purpose: a gun's SKINS MENU (polish1 D5a part 3, DECISIONS_SKINS: C on the gun's hover card opens it, BO2-style, a
# clever and distinct UI): the GUNSMITH bench. Left, the tier LADDER (Pony at the top) with the rail filled as far as
# this gun has climbed and what opens each rung; middle, the gun itself on a turntable (drag to turn) wearing whatever
# camo is under the mouse; right, the chosen rung's challenge camos as tiles (earned / under way with a progress bar /
# locked); below, the challenge and its progress, and YOUR LOCKER (unboxed camos that can go on this gun, one use).
# APPLY puts the chosen camo on, REMOVE takes it off; replacing an unboxed camo asks twice (it is gone once replaced).
# Draws and asks only: the session applies it. Real game UI (game/ui_skin.gd).
# Dependencies: game/ui_skin.gd, game/camo_skin.gd, game/camo_icons.gd, game/tier_style.gd, game/weapon_models.gd,
# game/gun_parts_view.gd, core/gun_stats.gd, core/camo_challenges.gd (set `chal`), core/camo_locker.gd (set `locker`),
# core/gun_db.gd (set `gun_db`).
extends Control

const UiSkin = preload("res://game/ui_skin.gd")
const CamoSkin = preload("res://game/camo_skin.gd")
const CamoIcons = preload("res://game/camo_icons.gd")
const TierStyle = preload("res://game/tier_style.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const GunPartsView = preload("res://game/gun_parts_view.gd")
const GunStats = preload("res://core/gun_stats.gd")
const CamoChallenges = preload("res://core/camo_challenges.gd")

signal apply_challenge(id: String)  # an earned challenge camo goes on the gun
signal apply_locker(index: int)  # an unboxed camo (locker index) goes on the gun (one use)
signal remove_camo
signal closed

const LADDER := ["pony", "gold", "purple", "blue", "green"]  # top to bottom
const TIER_NAMES := {"green": "Uncommon", "blue": "Rare", "purple": "Epic", "gold": "Legendary", "pony": "Pony"}
const VIEW := Vector2i(720, 400)
const DESIGN := Vector2(1280, 720)  # laid out at this size, scaled to the window (never smaller than it fits)

var chal: RefCounted
var locker: RefCounted
var gun_db: RefCounted
var watch: Control  # the window it lies over: closes with it
var gun: Dictionary = {}  # the gun itself (the session's own dictionary: changes show at once)

var _tier := "green"
var _sel := {}  # {"chal": id} or {"locker": index}
var _hover := {}
var _confirm := ""  # "apply" / "remove" after a first click that would replace an unboxed camo
var _hits: Array = []
var _mouse := Vector2(-1, -1)
var _font: Font = ThemeDB.fallback_font
var _t := 0.0
var _locker_scroll := 0.0
var _grid_scroll := 0.0
var _drag := false
var _turn := 0.0
var _turn_speed := 0.35
var _view: SubViewport
var _pivot: Node3D
var _model: Node3D
var _shown_key := ""
var _mat: ShaderMaterial
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_view = SubViewport.new()
	_view.size = VIEW
	_view.transparent_bg = true
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_DISABLED
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.light_energy = 1.3
	_view.add_child(light)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-20, 210, 0)
	back.light_energy = 0.45
	_view.add_child(back)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.56, 0.6)
	_view.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.15
	cam.position = Vector3(0, 0.32, 3)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	cam.current = true
	_view.add_child(cam)
	_pivot = Node3D.new()
	_view.add_child(_pivot)
	_prewarm.call_deferred()


# (polish1 item 143) The bench's first opening froze the game for about 1.4 s on his PC (its view drawing for the first
# time: the GPU sets up everything a gun in that view needs). Drawn once while the game loads instead, with a camo'd rifle.
func _prewarm() -> void:
	var model := WeaponModels.build("ak47")
	_pivot.add_child(model)
	var looks: Array = CamoSkin.cfg().get("camos", [])
	if not looks.is_empty():
		CamoSkin.dress(model, {"body": "ak47", "camo": {"id": String((looks[0] as Dictionary)["id"]), "wear": 0.1, "seed": 1}})
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(model):
		model.queue_free()



func open(the_gun: Dictionary) -> void:
	gun = the_gun
	_sel = {}
	_hover = {}
	_confirm = ""
	_shown_key = ""
	_tier = "green"
	for t: String in LADDER:  # start on the highest open rung
		if chal.call("is_open", gun, t):
			_tier = t
			break
	visible = true
	_fit()
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	queue_redraw()


# Scales the bench to the window: laid out at least DESIGN wide / tall, then shrunk to fit.
func _fit() -> void:
	var vp := get_viewport_rect().size
	var k := minf(minf(vp.x / DESIGN.x, vp.y / DESIGN.y), 1.0) if vp.x < DESIGN.x or vp.y < DESIGN.y else 1.0
	scale = Vector2(k, k)
	position = Vector2.ZERO
	size = vp / k


func close() -> void:
	if not visible:
		return
	visible = false
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if _model != null:
		_model.queue_free()
		_model = null
	_shown_key = ""
	closed.emit()


# The gun changed (a camo went on / came off): show it fresh.
func refresh() -> void:
	_shown_key = ""
	_confirm = ""
	if _sel.has("locker") and int(_sel["locker"]) >= (locker.get("items") as Array).size():
		_sel = {}
	_pulse = 1.0
	queue_redraw()


func is_open() -> bool:
	return visible


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("gun_skins") or event.is_action_pressed("inventory"):
		close()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	var m := event as InputEventMouseMotion
	if m != null:
		_mouse = m.position
		if _drag:
			_turn += m.relative.x * 0.012
	var b := event as InputEventMouseButton
	if b == null:
		return
	if b.button_index == MOUSE_BUTTON_LEFT and not b.pressed:
		_drag = false
	if not b.pressed:
		return
	if b.button_index == MOUSE_BUTTON_WHEEL_UP or b.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		var step := -70.0 if b.button_index == MOUSE_BUTTON_WHEEL_UP else 70.0
		if _locker_rect().has_point(b.position):
			_locker_scroll = maxf(_locker_scroll + step, 0.0)
		elif _grid_rect().has_point(b.position):
			_grid_scroll = maxf(_grid_scroll + step, 0.0)
		accept_event()
	elif b.button_index == MOUSE_BUTTON_LEFT:
		for hit: Array in _hits:
			if (hit[0] as Rect2).has_point(b.position):
				(hit[1] as Callable).call()
				accept_event()
				return
		if _view_rect().has_point(b.position):
			_drag = true
		accept_event()


# Checks: "tier <id>", "tile n" (n-th camo of the rung), "locker n", "apply", "remove", "close".
func press(key: String) -> bool:
	if key == "close":
		close()
		return true
	for hit: Array in _hits:
		if String(hit[2]) == key:
			(hit[1] as Callable).call()
			return true
	return false


func _process(delta: float) -> void:
	if not visible:
		return
	if watch != null and not watch.visible:
		close()
		return
	_fit()
	_t += delta
	_pulse = maxf(_pulse - delta * 0.7, 0.0)
	if not _drag:
		_turn += delta * _turn_speed
	_show_model()
	if _pivot != null:
		_pivot.rotation = Vector3(0.0, _turn, 0.0)
	if _mat != null:
		CamoSkin.react(_mat, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, _pulse)
	queue_redraw()


# The camo the turntable shows now: under the mouse, else the chosen one, else what the gun wears.
func _preview_camo() -> Dictionary:
	var pick := _hover if not _hover.is_empty() else _sel
	if pick.has("chal"):
		return CamoChallenges.camo_for(gun, String(pick["chal"]))
	if pick.has("locker"):
		var items: Array = locker.get("items")
		var i := int(pick["locker"])
		if i < items.size():
			var it: Dictionary = items[i]
			return {"id": String(it["id"]), "wear": float(it["wear"]), "seed": int(it["seed"]), "challenge": false}
	return gun.get("camo", {}) if gun.get("camo") is Dictionary else {}


func _show_model() -> void:
	var camo := _preview_camo()
	var key := "%s|%s" % [CamoIcons.key_of(gun), JSON.stringify(camo)]
	if key == _shown_key:
		return
	_shown_key = key
	if _model != null:
		_model.free()
	_model = WeaponModels.build(String(gun.get("body", "ak47")))
	_pivot.add_child(_model)
	if gun_db != null and not (gun.get("parts", {}) as Dictionary).is_empty():
		GunPartsView.apply(_model, gun, gun_db)
	var dressed := gun.duplicate()
	if camo.is_empty():
		dressed.erase("camo")
	else:
		dressed["camo"] = camo
	_mat = CamoSkin.dress(_model, dressed)
	_model.rotation_degrees = Vector3(0, 90, 0)
	_model.position = Vector3.ZERO
	var box := AABB()
	var first := true
	for found in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := found as MeshInstance3D
		var bb := _model.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	var span := maxf(maxf(box.size.z, box.size.x), box.size.y * 1.8)
	var total := 1.55 / maxf(span, 0.001)
	_model.scale = Vector3.ONE * total
	_model.position = -(Basis(Vector3.UP, PI * 0.5) * (box.get_center() * total))


# ---------------------------------------------------------------- layout
func _ladder_rect() -> Rect2:
	return Rect2(Vector2(20, 92), Vector2(230, size.y - 186))


func _view_rect() -> Rect2:
	var x := 266.0
	return Rect2(Vector2(x, 92), Vector2(size.x * 0.6 - x, (size.y - 186.0) * 0.64))


func _info_rect() -> Rect2:
	var v := _view_rect()
	return Rect2(Vector2(v.position.x, v.end.y + 10.0), Vector2(v.size.x, size.y - 94.0 - v.end.y - 10.0))


func _grid_rect() -> Rect2:
	var x := size.x * 0.6 + 16.0
	return Rect2(Vector2(x, 92), Vector2(size.x - x - 20.0, (size.y - 186.0) * 0.64))


func _locker_rect() -> Rect2:
	var g := _grid_rect()
	return Rect2(Vector2(g.position.x, g.end.y + 10.0), Vector2(g.size.x, size.y - 94.0 - g.end.y - 10.0))


# ---------------------------------------------------------------- drawing
func _draw() -> void:
	_hits.clear()
	_hover = {}
	if gun.is_empty() or chal == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.035, 0.99))
	for i in 24:  # the bench's blueprint grid
		var gx := float(i) * size.x / 24.0
		draw_line(Vector2(gx, 80), Vector2(gx, size.y - 84), Color(0.4, 0.6, 1.0, 0.035), 1.0)
	_header()
	_ladder()
	_grid()
	_locker_strip()
	_turntable()
	_info()
	_footer()


func _header() -> void:
	draw_string(_font, Vector2(22, 44), "GUNSMITH", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, UiSkin.ACCENT)
	var gun_name := GunStats.display_name(gun_db, gun)
	draw_string(_font, Vector2(196, 42), gun_name, HORIZONTAL_ALIGNMENT_LEFT, size.x * 0.5, 18, TierStyle.color(gun_db, String(gun.get("tier", "")), _t))
	var done := int(chal.call("mastery", gun))
	var all := int(chal.call("total"))
	var mr := Rect2(Vector2(size.x - 360.0, 22), Vector2(340, 40))
	draw_string(_font, Vector2(mr.position.x, mr.position.y + 12.0), "CAMO MASTERY", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiSkin.TEXT_DIM)
	draw_string(_font, Vector2(mr.position.x, mr.position.y + 12.0), "%d / %d" % [done, all], HORIZONTAL_ALIGNMENT_RIGHT, mr.size.x, 14, UiSkin.TEXT)
	var x := mr.position.x
	var seg := mr.size.x / float(maxi(all, 1))
	for i in all:  # one notch per camo, coloured by its tier once earned
		var tier := _tier_at(i)
		var c := TierStyle.color(gun_db, tier, _t) if i < done else Color(1, 1, 1, 0.08)
		draw_rect(Rect2(Vector2(x + float(i) * seg, mr.position.y + 22.0), Vector2(maxf(seg - 1.0, 1.0), 12.0)), c)
	draw_line(Vector2(20, 76), Vector2(size.x - 20.0, 76), Color(UiSkin.ACCENT, 0.35), 1.0)


# The tier of the n-th camo in ladder order bottom up (for the mastery notches).
func _tier_at(n: int) -> String:
	var seen := 0
	for i in range(LADDER.size() - 1, -1, -1):
		var count := (chal.call("ids_of", LADDER[i]) as Array).size()
		if n < seen + count:
			return String(LADDER[i])
		seen += count
	return "pony"


func _ladder() -> void:
	var area := _ladder_rect()
	var rung_h := (area.size.y - 8.0 * float(LADDER.size() - 1)) / float(LADDER.size())
	var rail_x := area.position.x + 14.0
	draw_line(Vector2(rail_x, area.position.y + rung_h * 0.5), Vector2(rail_x, area.end.y - rung_h * 0.5), Color(1, 1, 1, 0.12), 4.0)
	for i in LADDER.size():
		var tier: String = LADDER[i]
		var r := Rect2(Vector2(area.position.x + 30.0, area.position.y + float(i) * (rung_h + 8.0)), Vector2(area.size.x - 30.0, rung_h))
		var is_on := bool(chal.call("is_open", gun, tier))
		var tint := TierStyle.color(gun_db, tier, _t)
		var ids: Array = chal.call("ids_of", tier)
		var have := int(chal.call("done_in", gun, tier))
		var chosen := tier == _tier
		var hot := r.has_point(_mouse)
		UiSkin.panel(self, r, Color(tint, 0.16) if chosen else Color(0.06, 0.065, 0.09, 0.96), Color(tint, 0.95 if chosen or hot else (0.5 if is_on else 0.18)), 10)
		var node := Vector2(rail_x, r.get_center().y)  # the rung's knot on the rail
		draw_line(node, Vector2(r.position.x, node.y), Color(tint, 0.6 if is_on else 0.15), 2.0)
		draw_circle(node, 9.0, Color(0.05, 0.05, 0.07))
		draw_circle(node, 7.0, Color(tint, 1.0 if is_on else 0.25))
		if have >= ids.size() and not ids.is_empty():
			draw_string(_font, node + Vector2(-5, 5), "*", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.05, 0.05, 0.07))
		draw_string(_font, r.position + Vector2(12, 26), String(TIER_NAMES.get(tier, tier)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24.0, 18, tint if is_on else Color(tint, 0.45))
		draw_string(_font, r.position + Vector2(12, 46), "%d / %d earned" % [have, ids.size()], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24.0, 13, UiSkin.TEXT if is_on else UiSkin.TEXT_DIM)
		UiSkin.bar(self, Rect2(r.position + Vector2(12, 54), Vector2(r.size.x - 24.0, 6)), float(have) / float(maxi(ids.size(), 1)), tint)
		if not is_on:
			var need: Array = chal.call("opens_after", tier)
			var below := String(need[0])
			_padlock(Vector2(r.end.x - 22.0, r.position.y + 20.0), Color(1, 1, 1, 0.5))
			if rung_h > 78.0:
				draw_string(_font, r.position + Vector2(12, 76), "Earn %d %s (%d / %d)" % [int(need[1]), String(TIER_NAMES.get(below, below)), int(chal.call("done_in", gun, below)), int(need[1])], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24.0, 12, UiSkin.TEXT_DIM)
		var t_id := tier
		_hits.append([r, func() -> void: _tier = t_id; _grid_scroll = 0.0, "tier " + tier])


func _padlock(at: Vector2, c: Color) -> void:
	draw_arc(at + Vector2(0, -3), 5.0, PI, TAU, 10, c, 2.0)
	draw_rect(Rect2(at + Vector2(-7, -3), Vector2(14, 11)), c)


func _grid() -> void:
	var area := _grid_rect()
	UiSkin.panel(self, area, Color(0.045, 0.05, 0.07, 0.96), UiSkin.EDGE, 12)
	var tint := TierStyle.color(gun_db, _tier, _t)
	var is_on := bool(chal.call("is_open", gun, _tier))
	draw_string(_font, area.position + Vector2(14, 26), "%s CHALLENGES" % String(TIER_NAMES.get(_tier, _tier)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 28.0, 15, tint)
	if not is_on:
		draw_string(_font, area.position + Vector2(14, 26), "LOCKED", HORIZONTAL_ALIGNMENT_RIGHT, area.size.x - 28.0, 13, UiSkin.TEXT_DIM)
	var ids: Array = chal.call("ids_of", _tier)
	var inner := Rect2(area.position + Vector2(10, 38), area.size - Vector2(20, 46))
	var cols := 3  # the fewest columns that show the whole rung without scrolling
	var tw := 0.0
	var th := 0.0
	while true:
		tw = (inner.size.x - 8.0 * float(cols - 1)) / float(cols)
		th = tw * 0.78
		if float(ceili(float(ids.size()) / float(cols))) * (th + 8.0) <= inner.size.y + 8.0 or cols >= 8:
			break
		cols += 1
	var wearing := String((gun.get("camo", {}) as Dictionary).get("id", "")) if gun.get("camo") is Dictionary else ""
	var wearing_ch := bool((gun.get("camo", {}) as Dictionary).get("challenge", false)) if gun.get("camo") is Dictionary else false
	for n in ids.size():
		var id := String(ids[n])
		var r := Rect2(inner.position + Vector2(float(n % cols) * (tw + 8.0), float(floori(float(n) / float(cols))) * (th + 8.0) - _grid_scroll), Vector2(tw, th))
		if r.position.y < inner.position.y - 2.0 or r.end.y > inner.end.y + 2.0:
			continue
		var earned := bool(chal.call("done", gun, id))
		var hot := r.has_point(_mouse)
		var chosen := String(_sel.get("chal", "")) == id
		UiSkin.panel(self, r, Color(0.07, 0.075, 0.1, 0.98), Color(tint, 0.95 if chosen or hot else (0.55 if earned else 0.15)), 8)
		var pic := CamoIcons.swatch({"id": id, "wear": 0.0, "seed": 7, "challenge": true}, self)
		if pic != null:
			draw_texture_rect(pic, Rect2(r.position + Vector2(4, 2), Vector2(r.size.x - 8.0, r.size.y - 26.0)), false, Color(1, 1, 1, 1.0 if earned or is_on else 0.35))
		var look := CamoSkin.look_of(id)
		draw_string(_font, Vector2(r.position.x + 6.0, r.end.y - 12.0), String(look.get("name", id)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 12.0, 11, tint if earned else UiSkin.TEXT_DIM)
		var need := int((chal.call("challenge", id) as Dictionary).get("n", 1))
		UiSkin.bar(self, Rect2(Vector2(r.position.x + 6.0, r.end.y - 7.0), Vector2(r.size.x - 12.0, 3.0)), float(chal.call("progress", gun, id)) / float(maxi(need, 1)), tint)
		if not is_on:
			_padlock(r.position + Vector2(r.size.x - 14.0, 16.0), Color(1, 1, 1, 0.55))
		elif earned:
			draw_circle(r.position + Vector2(r.size.x - 14.0, 14.0), 8.0, tint)
			draw_string(_font, r.position + Vector2(r.size.x - 19.0, 19.0), "v", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.05, 0.05, 0.07))
		if wearing == id and wearing_ch:
			draw_string(_font, r.position + Vector2(6, 16), "ON GUN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiSkin.ACCENT)
		if hot:
			_hover = {"chal": id}
		_hits.append([r, func() -> void: _sel = {"chal": id}; _confirm = "", "tile %d" % n])


func _locker_strip() -> void:
	var area := _locker_rect()
	UiSkin.panel(self, area, Color(0.045, 0.05, 0.07, 0.96), UiSkin.EDGE, 12)
	draw_string(_font, area.position + Vector2(14, 24), "YOUR LOCKER  -  unboxed camos (one use each on this gun)", HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 28.0, 13, UiSkin.TEXT_DIM)
	var items: Array = locker.get("items")
	if items.is_empty():
		draw_string(_font, area.position + Vector2(14, area.size.y * 0.6), "No unboxed camos. Crates roll one with every gun.", HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 28.0, 13, UiSkin.TEXT_DIM)
		return
	var th := area.size.y - 44.0
	var tw := th * 1.25
	var n := 0
	for i: int in locker.call("order"):
		var it: Dictionary = items[i]
		var r := Rect2(area.position + Vector2(10.0 + float(n) * (tw + 8.0) - _locker_scroll, 34), Vector2(tw, th))
		n += 1
		if r.position.x < area.position.x + 4.0 or r.end.x > area.end.x - 4.0:
			continue
		var look := CamoSkin.look_of(String(it["id"]))
		var tint := TierStyle.color(gun_db, String(look.get("tier", "green")), _t)
		var chosen := int(_sel.get("locker", -1)) == i
		var hot := r.has_point(_mouse)
		UiSkin.panel(self, r, Color(0.07, 0.075, 0.1, 0.98), Color(tint, 0.95 if chosen or hot else 0.4), 8)
		var pic := CamoIcons.swatch({"id": String(it["id"]), "wear": float(it["wear"]), "seed": int(it["seed"])}, self)
		if pic != null:
			draw_texture_rect(pic, Rect2(r.position + Vector2(3, 2), Vector2(r.size.x - 6.0, r.size.y - 22.0)), false)
		draw_string(_font, Vector2(r.position.x + 5.0, r.end.y - 6.0), "%s x%d" % [String(look.get("name", "")), int(it["uses"])], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10.0, 10, tint)
		if hot:
			_hover = {"locker": i}
		var index := i
		_hits.append([r, func() -> void: _sel = {"locker": index}; _confirm = "", "locker %d" % (n - 1)])


func _turntable() -> void:
	var r := _view_rect()
	UiSkin.panel(self, r, Color(0.035, 0.04, 0.055, 0.98), Color(UiSkin.ACCENT, 0.25), 14)
	var floor_c := r.position + Vector2(r.size.x * 0.5, r.size.y * 0.86)
	for i in 4:  # the turntable plate
		draw_arc(floor_c, r.size.x * (0.14 + 0.07 * float(i)), 0.0, TAU, 48, Color(0.5, 0.7, 1.0, 0.07 - 0.012 * float(i)), 1.5)
	var tex := _view.get_texture()
	var fit := minf(r.size.x / float(VIEW.x), r.size.y / float(VIEW.y))
	var vs := Vector2(VIEW) * fit
	draw_texture_rect(tex, Rect2(r.get_center() - vs * 0.5, vs), false)
	draw_string(_font, r.position + Vector2(14, r.size.y - 12.0), "drag to turn", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UiSkin.TEXT_DIM, 0.7))


func _info() -> void:
	var r := _info_rect()
	UiSkin.panel(self, r, Color(0.05, 0.055, 0.075, 0.97), UiSkin.EDGE, 12)
	var camo := _preview_camo()
	if camo.is_empty():
		draw_string(_font, r.position + Vector2(16, 34), "NO CAMO", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiSkin.TEXT_DIM)
		draw_string(_font, r.position + Vector2(16, 60), "Pick a challenge camo on the right or an unboxed camo from your locker.", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 14, UiSkin.TEXT_DIM)
		return
	var id := String(camo["id"])
	var look := CamoSkin.look_of(id)
	var tier := String(look.get("tier", "green"))
	var tint := TierStyle.color(gun_db, tier, _t)
	draw_string(_font, r.position + Vector2(16, 36), String(look.get("name", id)).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 24, tint)
	var pick := _hover if not _hover.is_empty() else _sel
	if pick.has("chal") or (pick.is_empty() and bool(camo.get("challenge", false))):
		var need := int((chal.call("challenge", id) as Dictionary).get("n", 1))
		var have := int(chal.call("progress", gun, id))
		var earned := bool(chal.call("done", gun, id))
		var is_on := bool(chal.call("is_open", gun, tier))
		var state := "EARNED" if earned else ("UNDER WAY" if is_on else "LOCKED")
		draw_string(_font, r.position + Vector2(16, 36), "%s CHALLENGE  -  %s" % [String(TIER_NAMES.get(tier, tier)).to_upper(), state], HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 32.0, 13, UiSkin.GOOD if earned else (UiSkin.TEXT if is_on else UiSkin.TEXT_DIM))
		draw_string(_font, r.position + Vector2(16, 64), String(chal.call("text", id)) + " with this gun", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 16, UiSkin.TEXT)
		UiSkin.bar(self, Rect2(r.position + Vector2(16, 76), Vector2(r.size.x - 120.0, 10)), float(have) / float(maxi(need, 1)), tint)
		draw_string(_font, Vector2(r.end.x - 96.0, r.position.y + 87.0), "%d / %d" % [have, need], HORIZONTAL_ALIGNMENT_RIGHT, 80, 14, UiSkin.TEXT)
		if not is_on:
			var below: Array = chal.call("opens_after", tier)
			draw_string(_font, r.position + Vector2(16, 110), "Opens after %d %s camos on this gun." % [int(below[1]), String(TIER_NAMES.get(String(below[0]), ""))], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 13, UiSkin.TEXT_DIM)
		else:
			draw_string(_font, r.position + Vector2(16, 110), "Challenge camos are this gun's own: Factory New, a stronger look than the unboxed one, they stay on it if it is traded.", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 12, UiSkin.TEXT_DIM)
	else:
		draw_string(_font, r.position + Vector2(16, 36), "UNBOXED  -  %s" % String(TIER_NAMES.get(tier, tier)).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 32.0, 13, UiSkin.TEXT)
		draw_string(_font, r.position + Vector2(16, 64), "%s, pattern %d" % [CamoSkin.wear_name(float(camo.get("wear", 0.0))), int(camo.get("seed", 1))], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 16, UiSkin.TEXT)
		if pick.has("locker"):
			var it: Dictionary = (locker.get("items") as Array)[int(pick["locker"])]
			draw_string(_font, r.position + Vector2(16, 90), "%d use%s left: putting it on this gun uses one." % [int(it["uses"]), "" if int(it["uses"]) == 1 else "s"], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 13, UiSkin.TEXT_DIM)
		else:
			draw_string(_font, r.position + Vector2(16, 90), "On this gun now.", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 32.0, 13, UiSkin.TEXT_DIM)


func _wears_unboxed() -> bool:
	return gun.get("camo") is Dictionary and not bool((gun["camo"] as Dictionary).get("challenge", false))


func _can_apply() -> bool:
	if _sel.has("chal"):
		var id := String(_sel["chal"])
		var on: Dictionary = gun.get("camo", {}) if gun.get("camo") is Dictionary else {}
		return bool(chal.call("done", gun, id)) and not (String(on.get("id", "")) == id and bool(on.get("challenge", false)))
	return _sel.has("locker")


func _footer() -> void:
	var y := size.y - 66.0
	var apply_r := Rect2(Vector2(size.x * 0.6 - 236.0, y), Vector2(236, 46))
	var remove_r := Rect2(Vector2(size.x * 0.6 + 16.0, y), Vector2(180, 46))
	var close_r := Rect2(Vector2(size.x - 200.0, y), Vector2(180, 46))
	var can := _can_apply()
	UiSkin.pill(self, _font, apply_r, "CLICK AGAIN TO REPLACE" if _confirm == "apply" else "APPLY", can, can and apply_r.has_point(_mouse), 17)
	var has_camo := gun.get("camo") is Dictionary
	UiSkin.pill(self, _font, remove_r, "CLICK AGAIN" if _confirm == "remove" else "REMOVE CAMO", false, has_camo and remove_r.has_point(_mouse), 15)
	UiSkin.pill(self, _font, close_r, "CLOSE  [Esc]", false, close_r.has_point(_mouse), 15)
	if _confirm != "":
		var old := CamoSkin.look_of(String((gun.get("camo", {}) as Dictionary).get("id", "")))
		draw_string(_font, Vector2(20, y + 28.0), "%s is unboxed: once replaced it is gone." % String(old.get("name", "The camo")), HORIZONTAL_ALIGNMENT_LEFT, apply_r.position.x - 40.0, 14, UiSkin.BAD)
	else:
		draw_string(_font, Vector2(20, y + 28.0), "Kills with this gun count on its open challenges.", HORIZONTAL_ALIGNMENT_LEFT, apply_r.position.x - 40.0, 13, UiSkin.TEXT_DIM)
	_hits.append([apply_r, _apply_pressed, "apply"])
	_hits.append([remove_r, _remove_pressed, "remove"])
	_hits.append([close_r, close, "close"])


func _apply_pressed() -> void:
	if not _can_apply():
		return
	if _wears_unboxed() and _confirm != "apply":
		_confirm = "apply"
		return
	_confirm = ""
	if _sel.has("chal"):
		apply_challenge.emit(String(_sel["chal"]))
	else:
		apply_locker.emit(int(_sel["locker"]))
		_sel = {}


func _remove_pressed() -> void:
	if not gun.get("camo") is Dictionary:
		return
	if _wears_unboxed() and _confirm != "remove":
		_confirm = "remove"
		return
	_confirm = ""
	remove_camo.emit()
