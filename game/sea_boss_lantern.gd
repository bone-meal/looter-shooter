# Purpose: the Lantern Queen's own ARENA MECHANICS on top of the super boss fight (sea step 13 R2d, design approved in
# diary/DESIGN_BOSSES.md): the Root Crown's FOG (thick in phase 1, thinner for each lit brazier), the pitch BRAZIERS'
# light circles (an OmniLight per lit one; the HOST puts each out after its burn_s and tells the fight whether she is
# EXPOSED in a circle: core/sea/boss_rules.gd `exposed`), the LURE PULL (each player on his own machine: keep her lure
# in view too long and you are walked toward the pool), and the SPORE CLOUDS where her pods land (standing in one
# blinds: a green veil over this player's screen). Does nothing for a boss without a "lantern" block.
# Online: the host's `exposed` rides in the fight's message (game/sea_boss.gd to_net / from_net); the braziers' lit
# state is the dungeon's own (game/sea_dungeons.gd tell_dungeons); clouds come from the lobbed balls every machine shows.
# Dependencies: core/sea/lantern_rules.gd, game/sea_boss.gd (parent: boss_cfg, boss_id, enemy, rules, _arena, state),
# game/sea_dungeons.gd (where, _env, _dirty), core/sea/dungeon_rules.gd (lit, put_out), game/fx_kit.gd, the player (shove).
extends Node

const LanternRules = preload("res://core/sea/lantern_rules.gd")
const FxKit = preload("res://game/fx_kit.gd")

var fight: Node  # game/sea_boss.gd
var rules := LanternRules.new()
var exposed := false
var lit_n := 0
# dev / checks
var pulls := 0
var blinds := 0
var burnouts := 0
var _dungeons: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _lights := {}  # brazier char -> OmniLight3D
var _saved_env := {}  # the dungeons' environment before we changed it
var _blind := 0.0
var _blind_full := 1.0
var _veil: ColorRect = null
var _was_pulled := false


func setup(boss_fight: Node, dungeons: Node3D, sea: Node3D, player: CharacterBody3D) -> void:
	fight = boss_fight
	_dungeons = dungeons
	_sea = sea
	_player = player
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_veil = ColorRect.new()
	_veil.color = Color(0.55, 0.72, 0.32, 0.0)
	_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_veil.visible = false
	layer.add_child(_veil)


func cfg() -> Dictionary:
	if fight == null or String(fight.get("boss_id")) == "":
		return {}
	return (fight.call("boss_cfg", String(fight.get("boss_id"))) as Dictionary).get("lantern", {})


func active() -> bool:
	return not cfg().is_empty()


# The fight (or its puppet) was made: lights for the braziers, fresh rules.
func begin() -> void:
	clear()
	if not active():
		return
	rules.setup(cfg())
	var arena: Node3D = fight.call("_arena")
	if arena == null:
		return
	var r: RefCounted = arena.get("rules")
	var col: Array = cfg().get("light_color", [1.0, 0.6, 0.3])
	for ch: String in (r.get("things") as Dictionary):
		if String(r.get("things")[ch]["kind"]) != "brazier":
			continue
		var light := OmniLight3D.new()
		light.light_color = Color(float(col[0]), float(col[1]), float(col[2]))
		light.omni_range = float(cfg().get("light_r", 7.0)) * 1.35
		light.light_energy = 2.2
		light.shadow_enabled = false
		light.position = (r.call("at_of", r.call("cell_of_thing", ch)) as Vector3) + Vector3(0.0, 2.2, 0.0)
		light.visible = false
		arena.add_child(light)
		_lights[ch] = light


func clear() -> void:
	for ch: String in _lights:
		if is_instance_valid(_lights[ch]):
			(_lights[ch] as Node).queue_free()
	_lights.clear()
	rules.setup({})
	exposed = false
	lit_n = 0
	_blind = 0.0
	_was_pulled = false
	_restore_env()


# Host, each frame of the fight: braziers burn out, and is she in a lit circle?
func host_tick(_delta: float) -> void:
	if not active():
		return
	var arena: Node3D = fight.call("_arena")
	var enemy: Node3D = fight.get("enemy")
	if arena == null or enemy == null:
		return
	var r: RefCounted = arena.get("rules")
	var lit_now := {}
	for ch: String in (r.get("state")["lit"] as Dictionary):
		if bool(r.get("state")["lit"][ch]):
			lit_now[ch] = float(r.get("things")[ch].get("burn_s", 0.0))
	var out: Array = rules.burnt_out(lit_now, float(fight.get("rules").get("fight_t")))
	for ch: String in out:
		if bool(r.call("put_out", ch)):
			burnouts += 1
			arena.call("refresh", false)
			_dungeons.set("_dirty", true)
			fight.call("_tell_notice", "A brazier gutters out")
	exposed = rules.exposed(enemy.position, _lit_points(r))
	fight.get("rules").set("exposed", exposed)


func _lit_points(r: RefCounted) -> Array:
	var out: Array = []
	for ch: String in (r.get("state")["lit"] as Dictionary):
		if bool(r.get("state")["lit"][ch]):
			out.append(r.call("at_of", r.call("cell_of_thing", ch)))
	return out


# A lobbed ball landed (every machine): a spore pod leaves its cloud.
func add_cloud(at: Vector3, cloud: Dictionary) -> void:
	if not active() or cloud.is_empty():
		return
	rules.add_cloud(at, float(cloud.get("radius", 2.5)), float(cloud.get("cloud_s", 4.0)), float(cloud.get("blind_s", 3.0)))
	var arena: Node3D = fight.call("_arena")
	if arena != null:
		FxKit.burst(arena, arena.to_global(at + Vector3(0.0, 0.8, 0.0)), Color(0.72, 0.95, 0.42), 60, float(cloud.get("cloud_s", 4.0)), 0.4, float(cloud.get("radius", 2.5)) * 0.8, 0.3)


func _process(delta: float) -> void:
	var arena: Node3D = fight.call("_arena") if fight != null else null
	var here := arena != null and active() and String(_dungeons.get("where")) == String(fight.call("_arena_id"))
	if not here:
		_restore_env()
		_veil.visible = false
		_blind = 0.0
		return
	var r: RefCounted = arena.get("rules")
	lit_n = 0
	for ch: String in _lights:
		var on := bool(r.get("state")["lit"].get(ch, false))
		(_lights[ch] as OmniLight3D).visible = on
		lit_n += 1 if on else 0
	_set_env(rules.fog(int(fight.get("phase")), lit_n))
	var local := arena.to_local(_player.global_position)
	# the lure pull (only while he is up in the fight)
	var fighting := String(fight.get("state")) == "fight" and String(fight.call("state_of", int(_dungeons.call("_my_id")))) == "up"
	var bulb := _bulb()
	var cam := get_viewport().get_camera_3d()
	if fighting and bulb != null and cam != null:
		var pulled := rules.watch_lure(cam.global_position, -cam.global_transform.basis.z, bulb.global_position, true, delta)
		if pulled:
			var b: Dictionary = fight.call("boss_cfg", String(fight.get("boss_id")))
			var pool := arena.to_global(Vector3(float(b["home"][0]), 0.0, float(b["home"][1])))
			_player.call("shove", rules.pull_toward(_player.global_position, pool))
			if not _was_pulled:
				pulls += 1
				_sea.emit_signal("notice", String((cfg().get("lure", {}) as Dictionary).get("notice", "The light pulls at you")))
		_was_pulled = pulled
	else:
		rules.hold = 0.0
		_was_pulled = false
	# spore clouds
	var blind := rules.cloud_step(local, delta)
	if blind > 0.0 and _blind <= 0.0:
		blinds += 1
	if blind > _blind:
		_blind = blind
		_blind_full = blind
	_blind = maxf(_blind - delta, 0.0)
	_veil.visible = _blind > 0.0
	_veil.color.a = clampf(_blind / maxf(_blind_full, 0.01), 0.0, 1.0) * 0.78


# Her lure bulb, while it is whole (a broken one is hidden).
func _bulb() -> Node3D:
	var enemy: Node3D = fight.get("enemy")
	if enemy == null or not is_instance_valid(enemy):
		return null
	var model: Node3D = enemy.get("_model")
	var bulb := model.find_child("LureBulb", true, false) as Node3D if model != null else null
	return bulb if bulb != null and bulb.is_visible_in_tree() else null


func _set_env(density: float) -> void:
	var env: Environment = _dungeons.get("_env")
	if env == null:
		return
	if _saved_env.is_empty():
		_saved_env = {"density": env.fog_density, "color": env.fog_light_color}
	env.fog_density = density
	var c: Array = cfg().get("fog_color", [0.1, 0.12, 0.09])
	env.fog_light_color = Color(float(c[0]), float(c[1]), float(c[2]))


func _restore_env() -> void:
	if _saved_env.is_empty() or _dungeons == null:
		return
	var env: Environment = _dungeons.get("_env")
	if env != null:
		env.fog_density = float(_saved_env["density"])
		env.fog_light_color = _saved_env["color"]
	_saved_env = {}


# Online: what the clients need from the host.
func to_net() -> Array:
	return [exposed]


func from_net(got: Array) -> void:
	if got.size() >= 1:
		exposed = bool(got[0])
		fight.get("rules").set("exposed", exposed)


func status() -> String:
	return "lantern: exposed %s, lit %d, fog %.3f, lure hold %.1f pulls %d, clouds %d blinds %d (veil %.1f), burnouts %d" % [str(exposed), lit_n, rules.fog(int(fight.get("phase")), lit_n) if active() else 0.0, rules.hold, pulls, rules.clouds.size(), blinds, _blind, burnouts]
