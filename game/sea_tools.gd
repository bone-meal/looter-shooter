# Purpose: THE 7 TRAVERSAL TOOLS (sea step 9b, LOCKED list): which ones this player owns (saved in his profile, extra
# "sea_tools"; a dungeon chest with a `tool` gives it to every player inside), the chosen one ([T] uses it, [Y] picks
# the next) and what each does:
#   GRAPPLE HOOK: the hook flies to a hook ring in view within range, then hauls him there (player.tool_pull).
#   FOG BELL: in a dungeon the host shows its fog walkways for a while; at sea the fog thins for the ringer.
#   EMBER GAUNTLET: an ember bolt along the view; where it lands it burns a bramble / lights a brazier (host decides).
#   RIME ANCHOR: an ice slab on the water he looks at (a dungeon pool or the sea), solid for everyone, for a while.
#   GALE GLIDER: hold jump in the air: a slow glide on the way he looks; updraft vents lift him (player.glide_*).
#   TIDE PEARL: at a tide basin, turns the dungeon's tide (rafts rise or sink); carried, breath lasts longer.
#   WHORL COMPASS: shows the way to the nearest whorl door; close by, opens it.
# The tool in use is shown in the hand for a moment (its model, a small swing); the glider is worn while gliding.
# Online: dungeon changes go through the dungeons manager (host); ice slabs are told to everyone (net_sea tell_tool_fx).
# Dependencies: data/sea/tools.json, assets/models/sea/tools/*.gltf (tools/blender/sea_tools.py), the sea world
# (dungeons, swim, look, world_of, local_of, water_height, notice), game/player.gd (tool_pull, glide_*), game/fx_kit.gd,
# game/ui_skin.gd (the HUD line), game/net_sea.gd.
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")
const UiSkin = preload("res://game/ui_skin.gd")
const MODEL := "res://assets/models/sea/tools/%s.gltf"

var cfg: Dictionary
var owned: Array = []
var chosen := ""
var uses := {}  # dev / checks: tool -> times used
var last := ""
var hud := Control.new()
var _sea: Node3D
var _player: CharacterBody3D
var _held: Node3D = null
var _held_t := 0.0
var _pull_t := 0.0
var _hook_line: MeshInstance3D
var _hook_to := Vector3.INF
var _slabs: Array = []  # {"node", "until"}
var _bell_until := 0.0
var _cool := 0.0
var _wings: Node3D = null


func setup(sea: Node3D, player: CharacterBody3D, layer: CanvasLayer) -> void:
	_sea = sea
	_player = player
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/tools.json"))
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	_hook_line = MeshInstance3D.new()
	_hook_line.mesh = ImmediateMesh.new()
	_hook_line.material_override = FxKit.glow(Color(0.55, 0.45, 0.3, 1.0), false)
	_hook_line.top_level = true
	add_child(_hook_line)


# --- owning and choosing ---

func load_owned(saved: Variant) -> void:
	owned.clear()
	if saved is Array:
		for t: Variant in saved:
			if String(t) in cfg["order"] and not owned.has(String(t)):
				owned.append(String(t))
	_sort()
	chosen = String(owned[0]) if not owned.is_empty() else ""


func _sort() -> void:
	var order: Array = cfg["order"]
	owned.sort_custom(func(a: String, b: String) -> bool: return order.find(a) < order.find(b))


func has(tool: String) -> bool:
	return owned.has(tool)


func name_of(tool: String) -> String:
	return String(cfg["tools"].get(tool, {}).get("name", tool))


func give(tool: String) -> void:
	if not tool in cfg["order"] or owned.has(tool):
		return
	owned.append(tool)
	_sort()
	chosen = tool
	_sea.emit_signal("notice", "You got the %s! [T] uses it, [Y] picks another tool" % name_of(tool))
	var s := get_tree().get_first_node_in_group("game_session")
	if s != null:
		s.call("save_profile")
	hud.queue_redraw()


func next() -> void:
	if owned.is_empty():
		return
	chosen = String(owned[(owned.find(chosen) + 1) % owned.size()])
	hud.queue_redraw()


func _t(key: String, tool: String = "") -> float:
	return float(cfg["tools"][tool if tool != "" else chosen][key])


# --- using ---

func use() -> void:
	if chosen == "" or not bool(_sea.get("inside")):
		return
	uses[chosen] = int(uses.get(chosen, 0)) + 1
	match chosen:
		"grapple":
			_grapple()
		"bell":
			_ring_bell()
		"gauntlet":
			_ember()
		"anchor":
			_ice()
		"glider":
			_sea.emit_signal("notice", "Hold jump in the air to glide")
		"pearl":
			_pearl()
		"compass":
			_compass()


func _eye() -> Transform3D:
	var cam := get_viewport().get_camera_3d()
	return cam.global_transform if cam != null else _player.global_transform


func _dungeons() -> Node:
	return _sea.get("dungeons")


# Things of a kind in the dungeon this player is in: [[letter, world position of its middle at floor level], ...].
func _dungeon_things(kind: String) -> Array:
	var dm := _dungeons()
	var where := String(dm.get("where"))
	if where == "":
		return []
	var d: Node3D = dm.get("spaces")[where]
	var r: RefCounted = d.get("rules")
	var out: Array = []
	for ch: String in r.get("things"):
		var th: Dictionary = r.get("things")[ch]
		if String(th["kind"]) == kind:
			out.append([ch, _sea.call("world_of", (dm.call("space_of", where) as Vector3) + (r.call("at_of", r.call("cell_of_thing", ch)) as Vector3))])
	return out


# GRAPPLE HOOK: the ring nearest the middle of the view within range (and in sight).
func _grapple() -> void:
	var eye := _eye()
	var ahead := -eye.basis.z
	var best: Array = []
	var best_dot := cos(deg_to_rad(_t("cone_deg")))
	var candidates: Array = []
	for pair: Array in _dungeon_things("ring"):
		candidates.append([pair[1] + Vector3(0.0, 3.75, 0.0), pair[1]])
	for n: Node in get_tree().get_nodes_in_group("hook_ring"):
		candidates.append([(n as Node3D).global_position, (n as Node3D).global_position - Vector3(0.0, 3.75, 0.0)])
	for c: Array in candidates:
		var to: Vector3 = c[0] - eye.origin
		if to.length() > _t("range_m") or to.length() < 2.0:
			continue
		var dot := ahead.dot(to.normalized())
		if dot > best_dot and _clear(eye.origin, c[0]):
			best_dot = dot
			best = c
	_show_held("grapple", 0.9)
	if best.is_empty():
		last = "grapple: no ring in reach"
		_sea.emit_signal("notice", "No hook ring in reach")
		return
	var ring: Vector3 = best[0]
	var foot: Vector3 = best[1]
	var back := Vector3(_player.global_position.x - foot.x, 0.0, _player.global_position.z - foot.z).normalized()
	var land := foot + back * 1.3 + Vector3(0.0, 0.5, 0.0)
	_hook_to = ring
	_player.set("tool_pull_speed", _t("pull_speed"))
	_player.set("tool_pull", land)
	_pull_t = 3.0
	last = "grapple to %s" % str((_sea.call("local_of", land) as Vector3).snapped(Vector3.ONE * 0.1))


func _clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 1.2


# FOG BELL
func _ring_bell() -> void:
	_show_held("bell", 1.2)
	if String(_dungeons().get("where")) != "":
		_dungeons().call("act", "!")
		last = "bell rung in the dungeon"
	else:
		_bell_until = Time.get_ticks_msec() / 1000.0 + _t("reveal_s")
		last = "bell rung at sea"
	_sea.emit_signal("notice", "The Fog Bell rings out")


# EMBER GAUNTLET: a bolt along the view; at its end a bramble or brazier within 2.2 m takes the fire.
func _ember() -> void:
	if _cool > 0.0:
		return
	_cool = _t("cooldown_s")
	_show_held("gauntlet", 0.6)
	var eye := _eye()
	var from := eye.origin
	var to := from - eye.basis.z * _t("range_m")
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	q.exclude = [(_player as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit["position"] if not hit.is_empty() else to
	_bolt(from - eye.basis.z * 0.8 + Vector3(0.0, -0.25, 0.0), end)
	var aimed := ""
	var best := 2.2
	for kind: String in ["bramble", "brazier"]:
		for pair: Array in _dungeon_things(kind):
			var spot: Vector3 = pair[1]
			var d := Vector2(end.x - spot.x, end.z - spot.z).length()
			if d < best and end.y < spot.y + 3.6:
				best = d
				aimed = pair[0]
	last = "ember at %s" % (aimed if aimed != "" else "nothing")
	if aimed != "":
		_dungeons().call("act", aimed)


func _bolt(from: Vector3, to: Vector3) -> void:
	var ball := FxKit.particles(Color(1.0, 0.5, 0.15, 0.9), 24, 0.35, 0.25, 0.3, 30.0, 0.0, false, true)
	add_child(ball)
	ball.global_position = from
	var tw := create_tween()
	tw.tween_property(ball, "global_position", to, maxf(from.distance_to(to) / _t("bolt_speed", "gauntlet"), 0.05))
	tw.tween_callback(func() -> void:
		FxKit.burst(self, to, Color(1.0, 0.55, 0.2), 30, 0.6, 0.2, 5.0, -2.0)
		ball.emitting = false)
	tw.tween_interval(0.5)
	tw.tween_callback(ball.queue_free)


# RIME ANCHOR: where the view meets the water (a dungeon pit's or the sea's) within range: an ice slab.
func _ice() -> void:
	_show_held("anchor", 0.8)
	var eye := _eye()
	var ahead := -eye.basis.z
	var dm := _dungeons()
	var where := String(dm.get("where"))
	var water_y: float
	if where != "":
		water_y = (_sea.call("world_of", dm.call("space_of", where)) as Vector3).y - 0.7
	else:
		water_y = float(_sea.call("water_height", eye.origin))
	if ahead.y > -0.05:
		_sea.emit_signal("notice", "Look down at the water")
		return
	var t := (water_y - eye.origin.y) / ahead.y
	var spot := eye.origin + ahead * t
	if t < 0.0 or Vector2(spot.x - _player.global_position.x, spot.z - _player.global_position.z).length() > _t("range_m"):
		_sea.emit_signal("notice", "The water is too far")
		return
	var sea_at: Vector3 = _sea.call("local_of", spot)
	if where != "":  # in a dungeon: only over a pit, set in the middle of its cell, its top at floor level
		var d: Node3D = dm.get("spaces")[where]
		var r: RefCounted = d.get("rules")
		var local: Vector3 = sea_at - (dm.call("space_of", where) as Vector3)
		var cell: Vector2i = r.call("cell_of", local)
		if not String(r.call("terrain", cell)) in ["=", "_"]:
			_sea.emit_signal("notice", "That is not water")
			return
		sea_at = (dm.call("space_of", where) as Vector3) + (r.call("at_of", cell) as Vector3) + Vector3(0.0, -0.45, 0.0)
	else:
		sea_at.y = water_y - (_sea.call("world_of", Vector3.ZERO) as Vector3).y + 0.2
	add_slab(sea_at)
	var net := _net()
	if net != null:
		net.call("tell_tool_fx", "ice", sea_at)
	last = "ice at %s" % str(sea_at.snapped(Vector3.ONE * 0.1))


# An ice slab at a sea position (its middle), here: from this player or told by another.
func add_slab(sea_at: Vector3) -> void:
	while _slabs.size() >= int(_t("max", "anchor")) * 4:  # (a few players' slabs at once)
		(_slabs.pop_front()["node"] as Node).queue_free()
	var size := _t("size_m", "anchor")
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.8, size)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, 0.8, size)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.92, 1.0, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.emission_enabled = true
	mat.emission = Color(0.25, 0.45, 0.6)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
	body.position = sea_at  # (this node hangs under the sea root: sea coordinates)
	FxKit.burst(self, body.global_position + Vector3(0.0, 0.4, 0.0), Color(0.85, 0.95, 1.0), 40, 0.8, 0.25, 4.0, -3.0)
	_slabs.append({"node": body, "until": Time.get_ticks_msec() / 1000.0 + _t("life_s", "anchor")})


# TIDE PEARL
func _pearl() -> void:
	_show_held("pearl", 1.0)
	for pair: Array in _dungeon_things("basin"):
		if (pair[1] as Vector3).distance_to(_player.global_position) < _t("range_m") + 1.0:
			_dungeons().call("act", pair[0])
			last = "tide turned at %s" % pair[0]
			_sea.emit_signal("notice", "The Tide Pearl glows: the water turns")
			return
	last = "pearl: no basin"
	_sea.emit_signal("notice", "The Tide Pearl needs a tide basin")


# WHORL COMPASS
func _compass() -> void:
	_show_held("compass", 3.0)
	var best: Array = []
	var best_d := _t("point_m")
	var dm := _dungeons()
	var where := String(dm.get("where"))
	for pair: Array in _dungeon_things("door"):
		var th: Dictionary = (dm.get("spaces")[where] as Node3D).get("rules").get("things")[pair[0]]
		if String(th.get("open", "")) != "whorl" or bool((dm.get("spaces")[where] as Node3D).get("rules").call("door_open", pair[0])):
			continue
		var d := (pair[1] as Vector3).distance_to(_player.global_position)
		if d < best_d:
			best_d = d
			best = pair
	if best.is_empty():
		last = "compass: nothing"
		_sea.emit_signal("notice", "The needle spins: nothing hidden near")
		return
	if best_d < _t("range_m") + 1.5:
		dm.call("act", best[0])
		last = "whorl door %s opened" % best[0]
		_sea.emit_signal("notice", "The whorl turns: a hidden door opens")
		return
	var way: Vector3 = (best[1] as Vector3) - _player.global_position
	var dirs := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	last = "compass points %.0f m" % best_d
	_sea.emit_signal("notice", "The needle points %s, %d m" % [dirs[posmod(roundi((atan2(way.x, -way.z) / TAU) * 8.0), 8)], roundi(best_d)])
	if _held != null:
		var needle := _held.find_child("Needle", true, false) as Node3D
		if needle != null:
			needle.global_rotation.y = atan2(-way.x, -way.z)


func _net() -> Node:
	var net: Node = _dungeons().call("_net")
	return net if net != null and bool(net.call("active")) else null


# --- every frame ---

func _physics_process(delta: float) -> void:
	if _player == null or not bool(_sea.get("inside")):
		return
	_cool = maxf(_cool - delta, 0.0)
	var now := Time.get_ticks_msec() / 1000.0
	# the hook: hauled until he gets there
	if (_player.get("tool_pull") as Vector3).is_finite():
		_pull_t -= delta
		if (_player.get("tool_pull") as Vector3).distance_to(_player.global_position) < 0.9 or _pull_t <= 0.0:
			_player.set("tool_pull", Vector3.INF)
			_hook_to = Vector3.INF
	_draw_line()
	# the glider
	var gliding := has("glider") and not _player.is_on_floor() and Input.is_action_pressed("jump") and not bool(_player.get("swimming")) \
		and not (_player.get("tool_pull") as Vector3).is_finite() and float((_player.get("velocity") as Vector3).y) < 1.0 + _lift_here()
	_player.set("glide_fall", _t("fall_speed", "glider") if gliding else -1.0)
	_player.set("glide_speed", _t("speed", "glider"))
	_player.set("glide_lift", _lift_here() if gliding else 0.0)
	_wear_wings(gliding)
	# ice slabs melt
	for slab: Dictionary in _slabs.duplicate():
		if now > float(slab["until"]):
			FxKit.burst(self, (slab["node"] as Node3D).global_position, Color(0.85, 0.95, 1.0), 20, 0.6, 0.2, 2.0, -3.0)
			(slab["node"] as Node).queue_free()
			_slabs.erase(slab)
	# the bell's thin fog at sea; the pearl's breath
	(_sea.get("look") as RefCounted).set("fog_mult", _t("fog_mult", "bell") if now < _bell_until else 1.0)
	(_sea.get("swim") as Node).set("breath_mult", _t("breath_mult", "pearl") if has("pearl") else 1.0)
	# the tool in hand
	if _held != null:
		_held_t -= delta
		_held.rotation.x = sin(_held_t * 9.0) * 0.15
		if chosen == "bell":
			var clapper := _held.find_child("Clapper", true, false) as Node3D
			if clapper != null:
				clapper.rotation.z = sin(_held_t * 22.0) * 0.5
		if _held_t <= 0.0:
			_held.queue_free()
			_held = null


# An updraft vent under him in a dungeon: its lift while he is below lift_h over it.
func _lift_here() -> float:
	var dm := _dungeons()
	var where := String(dm.get("where"))
	if where == "":
		return 0.0
	var local: Vector3 = (_sea.call("local_of", _player.global_position) as Vector3) - (dm.call("space_of", where) as Vector3)
	var r: RefCounted = (dm.get("spaces")[where] as Node3D).get("rules")
	if String(r.call("terrain", r.call("cell_of", local))) == "u" and local.y < _t("lift_h", "glider"):
		return _t("lift", "glider")
	return 0.0


func _wear_wings(on: bool) -> void:
	if on and _wings == null:
		_wings = _model("glider")
		_player.add_child(_wings)
		_wings.position = Vector3(0.0, 1.35, 0.2)
	if _wings != null:
		_wings.visible = on


func _draw_line() -> void:
	var im := _hook_line.mesh as ImmediateMesh
	im.clear_surfaces()
	if not _hook_to.is_finite():
		return
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(_player.global_position + Vector3(0.0, 1.3, 0.0))
	im.surface_add_vertex(_hook_to)
	im.surface_end()


func _model(tool: String) -> Node3D:
	var path := MODEL % String(cfg["tools"][tool]["model"])
	if ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate() as Node3D
	var m := MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	m.scale = Vector3.ONE * 0.1
	return m


# The tool shown in the left of the view for a moment.
func _show_held(tool: String, seconds: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _held != null:
		_held.queue_free()
	_held = _model(tool)
	cam.add_child(_held)
	_held.position = Vector3(-0.22, -0.2, -0.45)
	_held.rotation = Vector3(0.0, 0.25, 0.0)
	_held_t = seconds


# --- the HUD line: the chosen tool and the keys ---

func _draw_hud() -> void:
	if owned.is_empty() or not bool(_sea.get("inside")) or chosen == "":
		return
	var font := ThemeDB.fallback_font
	var size := hud.get_viewport_rect().size
	var r := Rect2(size.x * 0.5 - 170.0, size.y - 128.0, 340.0, 34.0)
	UiSkin.panel(hud, r.grow(4.0))
	var x := UiSkin.key_cap(hud, font, r.position + Vector2(8.0, 6.0), "T")
	hud.draw_string(font, r.position + Vector2(x + 18.0, 23.0), name_of(chosen), HORIZONTAL_ALIGNMENT_LEFT, 200.0, 16, Color(1.0, 0.92, 0.75))
	if owned.size() > 1:
		var nx := r.position.x + r.size.x - 92.0
		UiSkin.key_cap(hud, font, Vector2(nx, r.position.y + 6.0), "Y")
		hud.draw_string(font, Vector2(nx + 30.0, r.position.y + 23.0), "next", HORIZONTAL_ALIGNMENT_LEFT, 60.0, 14, Color(0.85, 0.85, 0.85))


func _process(_delta: float) -> void:
	hud.visible = bool(_sea.get("inside")) and not owned.is_empty()
	if hud.visible:
		hud.queue_redraw()


func status() -> String:
	return "tools: owned %s, chosen %s, uses %s, pulling %s, gliding %s (lift %.1f), slabs %d, last '%s'" % [str(owned), chosen, str(uses), str((_player.get("tool_pull") as Vector3).is_finite()), str(float(_player.get("glide_fall")) >= 0.0), float(_player.get("glide_lift")), _slabs.size(), last]
