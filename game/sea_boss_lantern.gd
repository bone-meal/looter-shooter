# Purpose: the Lantern Queen's own ARENA MECHANICS on top of the super boss fight (sea step 13 R2d, design approved in
# diary/DESIGN_BOSSES.md): the Root Crown's FOG (thick in phase 1, thinner for each lit brazier), the pitch BRAZIERS'
# light circles (an OmniLight per lit one; the HOST puts each out after its burn_s and tells the fight whether she is
# EXPOSED in a circle: core/sea/boss_rules.gd `exposed`), the LURE PULL (each player on his own machine: keep her lure
# in view too long and you are walked toward the pool), and the SPORE CLOUDS where her pods land (standing in one
# blinds: a green veil over this player's screen). Phase 2 (FALSE LIGHTS): the fog ROLLS thick / thin, FALSE LURES
# rise round the pool (game/queen_false_lures.gd) while her real lure pulses out of step, the HOST sinks one walkway
# section after another (the arena's sink things: game/sea_dungeons.gd boss_tide), her WHIRLPOOL GULP pulls each
# player toward her on his own machine, and a player she SWALLOWS (host) is held inside her for hold_s (sooner if the
# others hurt her by free_dmg), then spat onto the walkway with heavy damage. Does nothing for a boss without a
# "lantern" block.
# Phase 3 (LIGHTS OUT): the hall goes DARK (the arena's light, lamp and fog turned down; the host puts out any lit
# brazier), she HUNTS BY LIGHT (host: `brightest` scores each player: muzzle flashes (game/net_fire.gd last_shot), the
# Keeper's Lantern or a flare gun in hand, the Ember Gauntlet in hand), her ROOT CAGES (game/queen_root_cages.gd) and
# her FLARE BURST (each machine: looking at her when it goes off blinds for blind_s). The enrage turns the fog total.
# Online: the host's [exposed, fight time, false lures, swallowed peers] ride in the fight's message (game/sea_boss.gd
# to_net / from_net index 21); the braziers' lit
# state is the dungeon's own (game/sea_dungeons.gd tell_dungeons); clouds come from the lobbed balls every machine shows.
# Dependencies: core/sea/lantern_rules.gd, game/queen_false_lures.gd, game/queen_root_cages.gd, game/net_fire.gd (last_shot), game/sea_boss.gd (parent: boss_cfg, boss_id, enemy, rules, _arena, state),
# game/sea_dungeons.gd (where, _env, _dirty), core/sea/dungeon_rules.gd (lit, put_out), game/fx_kit.gd, the player (shove).
extends Node

const LanternRules = preload("res://core/sea/lantern_rules.gd")
const FxKit = preload("res://game/fx_kit.gd")
const FalseLures = preload("res://game/queen_false_lures.gd")
const RootCages = preload("res://game/queen_root_cages.gd")

var fight: Node  # game/sea_boss.gd
var rules := LanternRules.new()
var exposed := false
var lit_n := 0
var fight_t := 0.0  # the fight's clock (clients: from the host, run on between messages)
var lures: Node  # game/queen_false_lures.gd
var cages: Node  # game/queen_root_cages.gd
var flares := 0  # dev / checks: flare bursts that blinded this player
var quarry := -1  # host: the peer she hunts by light now (-1 = nearest)
var swallowed := {}  # peer -> {t: seconds left, hp_at: her health when swallowed, dmg: release damage} (host); clients: peer -> true
var sunk := -1  # host: the walkway section under water now (-1 = none)
var gulps := 0
var exposed_s := 0.0  # host: seconds she has spent exposed (dev / checks)
var swallows := 0
var sinks := 0
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
var _sink_t := 0.0
var _sink_last := -1
var _held := false  # this player is inside her now
var _caged := false  # this player is in a root cage now
var _flare_was := false  # a flare burst was winding up last frame
var _blind_color := Color(0.55, 0.72, 0.32)
var _flare_a := {}  # the flare burst winding up (its numbers, kept for when it goes off)
var _rng := RandomNumberGenerator.new()


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
	lures = FalseLures.new()
	lures.name = "FalseLures"
	lures.set("lantern", self)
	add_child(lures)
	cages = RootCages.new()
	cages.name = "RootCages"
	cages.set("lantern", self)
	add_child(cages)
	_rng.randomize()


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
	_raise_all()
	if lures != null:
		lures.call("clear")
	if cages != null:
		cages.call("clear")
	swallowed.clear()
	quarry = -1
	_caged = false
	_flare_was = false
	sunk = -1
	_sink_t = 0.0
	_sink_last = -1
	_held = false
	fight_t = 0.0
	rules.setup({})
	exposed = false
	lit_n = 0
	_blind = 0.0
	_was_pulled = false
	_restore_env()


# Host, each frame of the fight: braziers burn out, and is she in a lit circle?
func host_tick(delta: float) -> void:
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
	exposed_s += delta if exposed else 0.0
	fight_t = float(fight.get("rules").get("fight_t"))
	var phase := int(fight.get("phase"))
	# false lures (their phase only)
	if phase == int(lures.call("phase")):
		if (lures.get("lures") as Array).is_empty():
			lures.call("host_begin", rules.false_count(int(fight.get("rules").get("players"))), _rng)
		lures.call("host_tick", fight_t)
	elif not (lures.get("lures") as Array).is_empty():
		lures.call("clear")
	_host_sink(delta, phase)
	_host_swallowed(delta)
	cages.call("host_tick", delta)
	if dark():  # she drank the light: no brazier burns now
		for ch: String in lit_now:
			if bool(r.call("put_out", ch)):
				arena.call("refresh", false)
				_dungeons.set("_dirty", true)


func _lit_points(r: RefCounted) -> Array:
	var out: Array = []
	for ch: String in (r.get("state")["lit"] as Dictionary):
		if bool(r.get("state")["lit"][ch]):
			out.append(r.call("at_of", r.call("cell_of_thing", ch)))
	return out


# Host: the sinking walkways (the "sink" block: one section of `things` under water for down_s, then up, every_s).
func _host_sink(delta: float, phase: int) -> void:
	var s: Dictionary = cfg().get("sink", {})
	if s.is_empty():
		return
	var things: Array = s["things"]
	if phase != int(s.get("phase", 1)) or bool(fight.get("rules").get("enraged")):
		if sunk >= 0:
			_set_sunk(-1)
		return
	_sink_t -= delta
	if _sink_t > 0.0:
		return
	if sunk >= 0:
		_sink_last = sunk
		_set_sunk(-1)
		_sink_t = float(s.get("every_s", 12.0)) - float(s.get("down_s", 8.0))
	else:
		_set_sunk(rules.next_sink(things.size(), _sink_last, _rng))
		_sink_t = float(s.get("down_s", 8.0))
		sinks += 1
		fight.call("_tell_notice", String(s.get("notice", "The roots heave: a walkway sinks!")))


func _set_sunk(i: int) -> void:
	var things: Array = (cfg().get("sink", {}) as Dictionary).get("things", [])
	if sunk >= 0 and sunk < things.size():
		_dungeons.call("boss_tide", String(fight.call("_arena_id")), String(things[sunk]), -1)
	sunk = i
	if i >= 0 and i < things.size():
		_dungeons.call("boss_tide", String(fight.call("_arena_id")), String(things[i]), 0)


# Host: every sunk section back up (the fight ended, another phase).
func _raise_all() -> void:
	if fight == null or not bool(fight.call("_host")) or String(fight.call("_arena_id")) == "" or not active():
		sunk = -1
		return
	_set_sunk(-1)


# Host: she swallowed this player (her whirlpool gulp, attack cfg a).
func swallow(peer: int, a: Dictionary) -> void:
	if swallowed.has(peer):
		return
	var enemy: Node3D = fight.get("enemy")
	swallowed[peer] = {"t": float(a.get("hold_s", 4.0)), "hp_at": float(enemy.get("health").get("hp")), "dmg": float(a["damage"]) * float(fight.get("_region_mult")) * float(fight.get("rules").call("damage_mult")), "free": float(a.get("free_dmg", 1500.0))}
	swallows += 1
	fight.call("_tell_notice", String(a.get("notice", "She swallows someone whole! Hit her to free them!")))


func is_swallowed(peer: int) -> bool:
	return swallowed.has(peer)


# Host: the swallowed are spat out after hold_s, or sooner when the others have hurt her by `free`.
func _host_swallowed(delta: float) -> void:
	var enemy: Node3D = fight.get("enemy")
	for peer: int in swallowed.keys():
		var s: Dictionary = swallowed[peer]
		s["t"] = float(s["t"]) - delta
		var hurt := float(s["hp_at"]) - float(enemy.get("health").get("hp"))
		if float(s["t"]) > 0.0 and hurt < float(s["free"]):
			continue
		swallowed.erase(peer)
		for b: Array in fight.call("_bodies"):
			if int(b[0]) == peer:
				(b[1] as Node3D).call("take_damage", float(s["dmg"]), "physical")
		fight.call("_tell_notice", "She spits them out!")


# Is it the dark phase now?
func dark() -> bool:
	return active() and int(fight.get("phase")) == int((cfg().get("dark", {}) as Dictionary).get("phase", 2))


# Host: in the dark phase the player who makes the most light ([peer, body, arena-local point]; [] = nobody / not dark).
func brightest() -> Array:
	if not dark():
		quarry = -1
		return []
	var enemy: Node3D = fight.get("enemy")
	var best: Array = []
	var best_score := -1.0
	for b: Array in fight.call("_bodies"):
		var peer := int(b[0])
		if String(fight.call("state_of", peer)) != "up" or swallowed.has(peer):
			continue
		var score := light_score(peer, b[1] as Node3D)
		var d := (b[2] as Vector3).distance_to(enemy.position) if enemy != null else 0.0
		score -= d * 0.001  # (a tie goes to the nearer)
		if score > best_score:
			best_score = score
			best = b
	quarry = int(best[0]) if not best.is_empty() else -1
	return best


# How much light a player makes: 1, + a shot within shot_s (muzzle flash), + a light in hand (the Keeper's Lantern, a
# flare gun, the Ember Gauntlet).
func light_score(peer: int, body: Node3D) -> float:
	var s: Dictionary = (cfg().get("dark", {}) as Dictionary).get("score", {})
	var score := 1.0
	var held := String(_player.call("held_id")) if body == _player else String(body.get("_held_shown"))
	if held.contains("keepers_lantern"):
		score += float(s.get("lantern", 4.0))
	if held.contains("flare"):
		score += float(s.get("flare", 4.0))
	if held.begins_with("tool:gauntlet"):
		score += float(s.get("gauntlet", 2.0))
	var net: Node = fight.call("_net")
	var fire: Node = (net.get("net") as Node).get_node_or_null("Fire") if net != null and net.get("net") != null else null
	if fire != null:
		var when := float((fire.get("last_shot") as Dictionary).get(peer, -100.0))
		if Time.get_ticks_msec() / 1000.0 - when <= float(s.get("shot_s", 1.5)):
			score += float(s.get("shot", 3.0))
	return score


# Host: her root cage closed on this player where he stands.
func cage(peer: int, at: Vector3) -> void:
	cages.call("host_cage", peer, at)
	fight.call("_tell_notice", "The roots close round someone: shoot or burn them free!")


# A hit on a root cage: the host breaks it; a client asks the host.
func cage_hit(id: String, damage: float) -> void:
	if bool(fight.call("_host")):
		cages.call("host_hit", int(id.trim_prefix("cage_")), damage)
	else:
		var net: Node = fight.call("_net")
		if net != null:
			net.call("request_boss_part", id, damage)


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
	if not bool(fight.call("_host")):
		fight_t += delta
	_set_env(float(cfg().get("enrage_fog", 0.3)) if bool(fight.get("rules").get("enraged")) else rules.fog(int(fight.get("phase")), lit_n, fight_t), dark())
	_watch_flare()
	var local := arena.to_local(_player.global_position)
	var phase := int(fight.get("phase"))
	lures.call("pulse", fight_t)
	var real := _bulb()
	if real != null:
		real.scale = Vector3.ONE * (rules.pulse(fight_t, true) if phase == int(lures.call("phase")) else 1.0)
	if _hold_me(arena):
		return
	_cage_me(arena)
	_gulp_pull(arena)
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
		_blind_color = Color(0.55, 0.72, 0.32)
	_blind = maxf(_blind - delta, 0.0)
	_veil.visible = _blind > 0.0
	_veil.color = Color(_blind_color.r, _blind_color.g, _blind_color.b, clampf(_blind / maxf(_blind_full, 0.01), 0.0, 1.0) * 0.78)


# This player inside her (swallowed): held in her belly under a dark veil; spat onto the walkway when let go.
func _hold_me(arena: Node3D) -> bool:
	var me := int(_dungeons.call("_my_id"))
	var inside := swallowed.has(me)
	var enemy: Node3D = fight.get("enemy")
	if inside and enemy != null and is_instance_valid(enemy):
		_held = true
		_player.call("teleport", enemy.global_position + Vector3(0.0, 1.2, 0.0), float(_player.call("look_yaw")))
		_veil.visible = true
		_veil.color = Color(0.18, 0.02, 0.03, 0.92)
		return true
	if _held:
		_held = false
		_veil.color = Color(0.55, 0.72, 0.32, 0.0)
		var b: Dictionary = fight.call("boss_cfg", String(fight.get("boss_id")))
		var home := Vector3(float(b["home"][0]), 0.0, float(b["home"][1]))
		var from := enemy.position if enemy != null and is_instance_valid(enemy) else home + Vector3(0.0, 0.0, 1.0)
		var out := Vector3(from.x - home.x, 0.0, from.z - home.z)
		out = out.normalized() if out.length() > 0.5 else Vector3(0.0, 0.0, 1.0)
		var spit := home + out * float(cfg().get("spit_m", 14.0))
		_player.call("teleport", arena.to_global(Vector3(spit.x, 0.6, spit.z)), float(_player.call("look_yaw")))
		_sea.emit_signal("notice", "Spat out!")
	return false


# This player in a root cage: held where the roots closed (he can still look and shoot).
func _cage_me(arena: Node3D) -> void:
	var me := int(_dungeons.call("_my_id"))
	if not bool(cages.call("is_caged", me)):
		_caged = false
		return
	var at: Vector3 = (cages.get("cages") as Dictionary)[me]["at"]
	var here := arena.to_local(_player.global_position)
	if not _caged:
		_caged = true
		_sea.emit_signal("notice", "Roots close round you! The others can shoot or burn you free")
	if Vector2(here.x - at.x, here.z - at.z).length() > 0.35:
		_player.call("teleport", arena.to_global(Vector3(at.x, maxf(here.y, at.y) + 0.05, at.z)), float(_player.call("look_yaw")))


# Her flare burst (every machine): when its windup ends, a player looking at her crown is blinded (white).
func _watch_flare() -> void:
	var a: Dictionary = fight.get("rules").call("attack_cfg", String(fight.get("attack")))
	var now := String(a.get("shape", "")) == "flare" and String(fight.get("mode")) == "windup"
	if _flare_was and not now and String(fight.get("mode")) != "stunned":
		_flash(_flare_cfg())
	if now:
		_flare_a = a
	_flare_was = now


func _flare_cfg() -> Dictionary:
	return _flare_a


func _flash(a: Dictionary) -> void:
	var enemy: Node3D = fight.get("enemy")
	var cam := get_viewport().get_camera_3d()
	if enemy == null or not is_instance_valid(enemy) or cam == null or a.is_empty():
		return
	if String(fight.call("state_of", int(_dungeons.call("_my_id")))) != "up" or swallowed.has(int(_dungeons.call("_my_id"))):
		return
	var model: Node3D = enemy.get("_model")
	var crown := model.find_child("Crown", true, false) as Node3D if model != null else null
	var at := crown.global_position if crown != null else enemy.global_position + Vector3(0.0, 4.0, 0.0)
	var to := at - cam.global_position
	if to.length() > float(a.get("reach_m", 45.0)) or rad_to_deg((-cam.global_transform.basis.z).angle_to(to.normalized())) > float(a.get("look_deg", 55.0)):
		return
	flares += 1
	_blind = float(a.get("blind_s", 3.0))
	_blind_full = _blind
	_blind_color = Color(1.0, 0.98, 0.85)


# Her whirlpool gulp: while it pulls, this player (up, within its radius) is drawn toward her.
func _gulp_pull(_arena: Node3D) -> void:
	if String(fight.get("mode")) != "strike" or String(fight.get("state")) != "fight":
		return
	var a: Dictionary = fight.get("rules").call("attack_cfg", String(fight.get("attack")))
	if String(a.get("shape", "")) != "gulp" or String(fight.call("state_of", int(_dungeons.call("_my_id")))) != "up":
		return
	var enemy: Node3D = fight.get("enemy")
	if enemy == null or not is_instance_valid(enemy):
		return
	var to := enemy.global_position - _player.global_position
	to.y = 0.0
	if to.length() <= float(a.get("radius", 20.0)) and to.length() > 1.0:
		_player.call("shove", to.normalized() * float(a.get("pull_mps", 3.0)))


# Her lure bulb, while it is whole (a broken one is hidden).
func _bulb() -> Node3D:
	var enemy: Node3D = fight.get("enemy")
	if enemy == null or not is_instance_valid(enemy):
		return null
	var model: Node3D = enemy.get("_model")
	var bulb := model.find_child("LureBulb", true, false) as Node3D if model != null else null
	return bulb if bulb != null and bulb.is_visible_in_tree() else null


func _set_env(density: float, is_dark: bool) -> void:
	var env: Environment = _dungeons.get("_env")
	var lamp: OmniLight3D = _dungeons.get("_lamp")
	if env == null:
		return
	if _saved_env.is_empty():
		_saved_env = {"density": env.fog_density, "color": env.fog_light_color, "ambient": env.ambient_light_energy, "lamp": lamp.light_energy if lamp != null else 1.0}
	env.fog_density = density
	var c: Array = cfg().get("fog_color", [0.1, 0.12, 0.09])
	var d: Dictionary = cfg().get("dark", {})
	env.fog_light_color = Color(0.0, 0.0, 0.0) if is_dark else Color(float(c[0]), float(c[1]), float(c[2]))
	env.ambient_light_energy = float(d.get("ambient", 0.03)) if is_dark else float(_saved_env["ambient"])
	if lamp != null:
		lamp.light_energy = float(_saved_env["lamp"]) * (float(d.get("lamp", 0.25)) if is_dark else 1.0)


func _restore_env() -> void:
	if _saved_env.is_empty() or _dungeons == null:
		return
	var env: Environment = _dungeons.get("_env")
	if env != null:
		env.fog_density = float(_saved_env["density"])
		env.fog_light_color = _saved_env["color"]
		env.ambient_light_energy = float(_saved_env["ambient"])
	var lamp: OmniLight3D = _dungeons.get("_lamp")
	if lamp != null:
		lamp.light_energy = float(_saved_env["lamp"])
	_saved_env = {}


# Online: what the clients need from the host.
func to_net() -> Array:
	return [exposed, snappedf(fight_t, 0.01), lures.call("to_net"), swallowed.keys(), cages.call("to_net")]


func from_net(got: Array) -> void:
	if got.size() >= 1:
		exposed = bool(got[0])
		fight.get("rules").set("exposed", exposed)
	if got.size() >= 4:
		if absf(float(got[1]) - fight_t) > 0.5:
			fight_t = float(got[1])
		if got[2] is Array:
			lures.call("from_net", got[2])
		swallowed.clear()
		if got[3] is Array:
			for peer: Variant in (got[3] as Array).slice(0, 6):
				swallowed[int(peer)] = true
	if got.size() >= 5 and got[4] is Array:
		cages.call("from_net", got[4])


# Client: hits on a false lure go to the host (game/net_sea.gd request_boss_part); the host: straight to the lures.
func false_hit(id: String, damage: float) -> void:
	if bool(fight.call("_host")):
		lures.call("host_hit", int(id.trim_prefix("false_")), damage, fight_t)
	else:
		var net: Node = fight.call("_net")
		if net != null:
			net.call("request_boss_part", id, damage)


func status() -> String:
	return "lantern: exposed %s (%.1f s), lit %d, fog %.3f, lure hold %.1f pulls %d, clouds %d blinds %d (veil %.1f), burnouts %d, false lures %s bursts %d, sunk %d sinks %d, gulps %d swallows %d swallowed %s held %s, dark %s quarry %d, cages %s made %d broken %d caged %s, flares %d" % [str(exposed), exposed_s, lit_n, rules.fog(int(fight.get("phase")), lit_n, fight_t) if active() else 0.0, rules.hold, pulls, rules.clouds.size(), blinds, _blind, burnouts, str(lures.call("to_net")), int(lures.get("bursts")), sunk, sinks, gulps, swallows, str(swallowed.keys()), str(_held), str(dark()) if active() else "false", quarry, str(cages.call("to_net")), int(cages.get("made")), int(cages.get("broken")), str(_caged), flares]
