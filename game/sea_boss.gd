# Purpose: a SEA SUPER BOSS FIGHT (sea step 10, LOCKED in DECISIONS_SEA.md / diary/DESIGN_BOSSES.md) in its arena
# dungeon behind a temple's sealed door. THE OFFERING: a player who carries the boss's offering lays it at the sealed
# door ([F]); the host opens the door for ONE attempt (saved in the host's world). Players go through into the arena;
# the fight starts a few seconds after the first comes in. The HOST runs the boss: it walks, faces and picks attacks
# by phase (core/sea/boss_rules.gd), warns (game/boss_strikes.gd marks), strikes (arc, ring wave you jump, charge,
# burrow under a player, lobbed spouts, leap), hurts the players its blows reach, sends adds, raises the arena's tide
# by phase (the arena's boss tide thing in data/sea/dungeons.json), opens its shell when the breakables go, sheds its
# shell in the last phase (the bell left in the pool: hooking its clapper with the Grapple Hook stuns it), enrages.
# DOWNED: a player out of health in the fight lies down; a teammate holding [F] by him helps him up (the host checks);
# nobody in time = OUT (Dread +1), lying there until the fight ends. Everyone down / out = WIPE: everyone in the arena
# wakes at the home port (Dread), the offering is spent, the boss is reset. Everyone gone = the attempt is spent too.
# WON: every player in the arena gets the boss's loot pool, its trophy and its plates on his own machine.
# Online: the host sends the boss (place, health, phase, move, marks, parts, downs) at 10 Hz (game/net_sea.gd);
# clients show a puppet, their hits go to the host (body, weak points, breakables), downs / revives / the offering
# are asks the host decides.
# Dependencies: data/sea/bosses.json, data/enemies.json, core/sea/boss_rules.gd, core/sea/threat_rules.gd,
# core/loot_pool.gd, core/item_level.gd, game/boss_part.gd, game/boss_strikes.gd, game/wave_director.gd (adopt),
# game/sea_dungeons.gd (parent: spaces, where, crews, boss_tide), game/sea_crews.gd (adds), the sea world, the player.
extends Node

const BossRules = preload("res://core/sea/boss_rules.gd")
const Threat = preload("res://core/sea/threat_rules.gd")
const LootPool = preload("res://core/loot_pool.gd")
const ItemLevel = preload("res://core/item_level.gd")
const BossPart = preload("res://game/boss_part.gd")
const BossStrikes = preload("res://game/boss_strikes.gd")
const GunStats = preload("res://core/gun_stats.gd")
const FxKit = preload("res://game/fx_kit.gd")
const SeaBossLantern = preload("res://game/sea_boss_lantern.gd")

var cfg: Dictionary  # data/sea/bosses.json
var director: Node
var card: RefCounted
var rules := BossRules.new()
var boss_id := ""  # the boss of the fight going on / shown ("" = none)
var enemy: Node3D = null
var open := {}  # host world: boss id -> true while an offering has opened its door for one attempt
var beaten := {}  # host world: boss id -> times beaten
var state := ""  # "" | wait | fight | won  (clients: from the host)
var mode := "idle"  # idle | windup | strike | recover | stunned
var attack := ""
var targets: Array = []  # arena-local points of the move going on
var ring_r := -1.0
var rear := 0.0  # 0 flat .. 1 reared up (-0.3 flopped, stunned)
var toll := 0.0  # the bell's swing after a toll (1 -> 0)
var tide := -1  # the arena's tide step shown
var shed := false
var cracked := false
var stunned := false
var phase := 0
var hp_share := 1.0
var downs := {}  # clients: peer -> state, from the host
# dev / checks
var fights := 0
var wins := 0
var wipes := 0
var blows := 0  # player hits landed by the boss's moves
var tolls := 0
var broke := 0
var last := ""
var rewarded := ""  # what the last win gave this player
var lantern: Node = null  # game/sea_boss_lantern.gd: the Lantern Queen's fog, braziers, lure pull, spore clouds (sea step 13 R2d)
var _dungeons: Node3D
var _sea: Node3D
var _player: CharacterBody3D
var _stats := {}
var _rng := RandomNumberGenerator.new()
var _strikes: BossStrikes = null
var _parts := {}  # part id -> BossPart
var _bell_ring: Node3D = null  # the hook ring on the shed bell's clapper
var _shell: Node3D = null  # the shell node (left in the pool once shed)
var _region_mult := 1.0
var _t := 0.0  # time left in this mode
var _t_total := 1.0
var _gap := 3.0
var _hits_left := 0
var _hit_set := {}  # bodies already hit by this move
var _charge_left := 0.0
var _charge_dir := Vector3.FORWARD
var _leap_from := Vector3.ZERO
var _leap_t := 0.0
var _landings: Array = []  # [[point, time left]] of lobbed balls (host)
var _adds_t := 8.0
var _adds: Array = []  # sea_crews ids of the adds
var _wait_t := 0.0
var _won_t := 0.0
var _send_t := 0.0
var _pending := 0.0  # client: body hits to pass to the host
var _was_mode := "idle"
var _said_enrage := false
var _downs_t := 0.0


func setup(dungeons: Node3D, sea: Node3D, player: CharacterBody3D) -> void:
	_dungeons = dungeons
	_sea = sea
	_player = player
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/bosses.json"))
	_stats = (JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json")) as Dictionary)["enemies"]
	_rng.randomize()
	lantern = SeaBossLantern.new()
	lantern.name = "Lantern"
	add_child(lantern)
	lantern.call("setup", self, dungeons, sea, player)


func boss_cfg(id: String) -> Dictionary:
	return cfg["bosses"].get(id, {})


func _net() -> Node:
	return _dungeons.call("_net")


func _host() -> bool:
	return bool(_dungeons.call("_host"))


func _my_id() -> int:
	return int(_dungeons.call("_my_id"))


func _arena() -> Node3D:
	return null if boss_id == "" else (_dungeons.get("spaces") as Dictionary).get(String(boss_cfg(boss_id)["arena"]))


func _arena_id() -> String:
	return "" if boss_id == "" else String(boss_cfg(boss_id)["arena"])


# The boss whose arena this dungeon is ("" = none).
func boss_of_arena(dungeon: String) -> String:
	for id: String in cfg["bosses"]:
		if String(cfg["bosses"][id]["arena"]) == dungeon:
			return id
	return ""


# --- the sealed door: the offering ---

func offering_name(id: String) -> String:
	var skills: Variant = _sea.get("skills")
	var item := String(boss_cfg(id)["offering"])
	return String((skills as Node).get("bag").call("item_name", item)) if skills != null else item


func _carries_offering(id: String) -> bool:
	var skills: Variant = _sea.get("skills")
	return skills != null and int((skills as Node).get("bag").call("count", String(boss_cfg(id)["offering"]))) > 0


# What [F] at a boss's sealed door says.
func door_words(id: String) -> String:
	if boss_cfg(id).is_empty():
		return "Sealed fast"
	var arena_name := String((_dungeons.get("cfg") as Dictionary)["dungeons"][boss_cfg(id)["arena"]]["name"])
	if bool(open.get(id, false)):
		return "Go into %s" % arena_name
	if _carries_offering(id):
		return String(boss_cfg(id).get("offer_words", "Lay the %s at the sealed door")) % offering_name(id)
	return String(boss_cfg(id).get("sealed_words", "Sealed. Something vast turns over behind it (it needs a %s)")) % offering_name(id)


# [F] at the sealed door: go in (open), or lay the offering (the host opens the door; we give it up on its yes).
func use_door(id: String) -> void:
	if bool(open.get(id, false)):
		_go_in(id)
		return
	if not _carries_offering(id):
		_sea.emit_signal("notice", door_words(id))
		return
	_dungeons.call("act", "@")


# Host: a player laid the offering at this temple's boss door.
func host_offer(peer: int, id: String) -> bool:
	if state == "won":  # (the last fight's beaten boss still lying there: cleared now)
		_clear_boss()
	if boss_cfg(id).is_empty() or bool(open.get(id, false)) or state != "":
		return false
	open[id] = true
	last = "%s offered by %d" % [id, peer]
	if peer == _my_id():
		offered()
	else:
		var net := _net()
		if net != null:
			net.call("tell_boss_offered", peer)
	_sea.emit_signal("notice", "The sealed door grinds open")
	return true


# The host took our offering: it is given up.
func offered() -> void:
	var skills: Variant = _sea.get("skills")
	for id: String in cfg["bosses"]:
		if skills != null and _carries_offering(id):
			((skills as Node).get("bag") as RefCounted).call("remove", String(boss_cfg(id)["offering"]), 1)
			_sea.emit_signal("notice", String(boss_cfg(id).get("offered_words", "The %s burns down on the altar")) % offering_name(id))
			return


func _go_in(id: String) -> void:
	var arena := String(boss_cfg(id)["arena"])
	var came: Dictionary = _dungeons.get("_came_from")
	came[arena] = [_sea.call("local_of", _player.global_position), float(_player.call("look_yaw"))]
	_dungeons.call("enter", arena)


# --- every frame ---

func _process(delta: float) -> void:
	if _sea == null or not bool(_sea.call("running")) or delta <= 0.0:
		return
	if enemy != null and not is_instance_valid(enemy):
		enemy = null
	toll = move_toward(toll, 0.0, delta * 0.6)
	if _host():
		_host_run(delta)
	elif enemy != null and _pending > 0.0:
		var net := _net()
		if net != null:
			net.call("request_boss_hit", _pending)
		_pending = 0.0
	_pose(delta)
	_show_marks()
	_downs_t -= delta
	if _downs_t <= 0.0:
		_downs_t = 0.5
		_show_downs()


# Other players lying in the fight are shown lying (game/remote_player.gd set_down).
func _show_downs() -> void:
	var net := _net()
	if net == null or not bool(net.call("active")) or boss_id == "":
		return
	var session_net: Node = net.get("net")
	for peer: int in session_net.get("roster"):
		if peer == _my_id():
			continue
		var body: Node3D = session_net.call("player_node", peer)
		if body != null and body.has_method("set_down"):
			body.call("set_down", state_of(peer) != "up")


func _host_run(delta: float) -> void:
	if state == "":
		for id: String in open:
			if bool(open[id]) and not _present(id).is_empty():
				boss_id = id
				state = "wait"
				_wait_t = float(boss_cfg(id)["start_delay"])
				last = "%s: they came in" % id
		return
	var present := _present(boss_id)
	if state == "wait":
		_wait_t -= delta
		if present.is_empty():
			_end(false, false)
		elif _wait_t <= 0.0:
			_start(maxi(present.size(), _party_size()))
		return
	if state == "won":
		_won_t -= delta
		if _won_t <= 0.0:
			_clear_boss()
		return
	if present.is_empty():  # everyone left: the attempt is spent
		last = "everyone left"
		_end(false, false)
		return
	for peer: int in rules.downs.keys():  # a downed player who left the session
		if not (int(peer) in present):
			rules.downs.erase(peer)
	if rules.wiped(present):
		_end(false, true)
		return
	if enemy == null or bool(enemy.get("health").call("is_dead")):
		return
	if rules.tick(delta):
		_set_tide(rules.tide_step)
	if rules.enraged and not _said_enrage:
		_said_enrage = true
		_tell_notice(String(boss_cfg(boss_id)["enrage"]["notice"]))
	var hp: RefCounted = enemy.get("health")
	hp_share = float(hp.get("hp")) / maxf(float(hp.get("max_hp")), 1.0)
	if rules.advance(hp_share):
		_new_phase()
	phase = rules.phase
	shed = rules.shed()
	cracked = rules.cracked()
	stunned = rules.stunned()
	lantern.call("host_tick", delta)  # (the Lantern Queen: braziers burn out, is she exposed in a lit circle)
	enemy.call("guard", rules.body_share(), 0.5)  # the armoured shell (an open shell, the shed phase, a stun, exposed: all of it)
	_show_parts()
	_adds_t -= delta
	var every := float(rules.phase_cfg().get("adds_every", 0.0))
	if every > 0.0 and _adds_t <= 0.0:
		_adds_t = every
		_spawn_adds()
	_drive(delta)
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.1
		var net := _net()
		if net != null and bool(net.call("active")):
			net.call("tell_boss", to_net())


# The party in the session (health and adds scale to it, also for those who come in after the start).
func _party_size() -> int:
	var net := _net()
	if net == null or not bool(net.call("active")):
		return 1
	return clampi(((net.get("net") as Node).get("roster") as Dictionary).size(), 1, 6)


# Peers standing in this boss's arena (the host itself as its own id).
func _present(id: String) -> Array:
	var out: Array = []
	var arena := String(boss_cfg(id)["arena"])
	if String(_dungeons.get("where")) == arena:
		out.append(_my_id())
	var net := _net()
	if net != null and bool(net.call("active")):
		var all: Dictionary = (net.get("net") as Node).call("positions")
		for peer: int in all:
			if peer != _my_id() and String(_dungeons.call("dungeon_at", _sea.call("local_of", all[peer]))) == arena:
				out.append(peer)
	return out


# [[peer, body node, arena-local position], ...] of the players in the arena.
func _bodies() -> Array:
	var out: Array = []
	var arena := _arena()
	if arena == null:
		return out
	var net := _net()
	for peer: int in _present(boss_id):
		var body: Node3D = _player if peer == _my_id() else ((net.get("net") as Node).call("player_node", peer) as Node3D if net != null else null)
		if body != null and is_instance_valid(body):
			out.append([peer, body, arena.to_local(body.global_position)])
	return out


func _ground(local: Vector3) -> float:
	var r: RefCounted = _arena().get("rules")
	return float(r.call("height_of", r.call("cell_of", local)))


func _tide_y() -> float:
	var r: RefCounted = _arena().get("rules")
	return float(r.call("flood_level", String(boss_cfg(boss_id)["tide_thing"])))


# --- starting, phases, ending ---

func _start(party: int) -> void:
	var b := boss_cfg(boss_id)
	var region := int(b.get("region", 1))
	var encounters: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/encounters.json"))
	_region_mult = Threat.player_mult(encounters["threat"], region)
	rules.setup(b, cfg, party, _region_mult)
	_make(false)
	enemy.get("health").set("max_hp", rules.max_hp)
	enemy.get("health").set("hp", rules.max_hp)
	enemy.set_meta("tier", 12 + 4 * (region - 1))
	state = "fight"
	mode = "idle"
	_gap = 2.5
	_adds_t = 8.0
	_said_enrage = false
	_set_tide(rules.tide_step)
	fights += 1
	_tell_notice(String(b["notice"]))
	last = "%s fight began (%d players, %.0f hp)" % [boss_id, party, rules.max_hp]


func _make(puppet: bool) -> void:
	var b := boss_cfg(boss_id)
	var stats: Dictionary = (_stats[String(b["enemy"])] as Dictionary).duplicate()
	enemy = director.call("adopt", String(b["enemy"]), stats)
	enemy.set("puppet", puppet)
	enemy.set_meta("boss_fight", boss_id)
	var arena := _arena()
	arena.add_child(enemy)
	enemy.set_physics_process(puppet)
	enemy.position = Vector3(float(b["home"][0]), -0.8, float(b["home"][1]))
	enemy.rotation.y = PI  # (solid: players cannot walk through it; it keeps its distance and stops when it rams)
	var model: Node3D = enemy.get("_model")
	if model != null:
		model.scale = Vector3.ONE * float(b.get("model_scale", 1.0))
		_shell = model.find_child("Shell", true, false) as Node3D
	_parts.clear()
	for p: Dictionary in b["parts"]:
		var node := model.find_child(String(p["node"]), true, false) as Node3D if model != null else null
		if node == null:
			continue
		var part := BossPart.new()
		part.fight = self
		part.target = enemy
		part.part_id = String(p["id"])
		part.radius = float(p["radius"])
		node.add_child(part)
		_player.add_collision_exception_with(part)
		_parts[String(p["id"])] = part
		if String(p["kind"]) == "breakable":
			_show_part(String(p["id"]), true, false)
	enemy.died.connect(_on_died)
	if puppet:
		enemy.set_meta("host_pays", true)
		enemy.connect("puppet_hit", func(damage: float) -> void: _pending += damage)
	if _strikes == null or not is_instance_valid(_strikes):
		_strikes = BossStrikes.new()
	if _strikes.get_parent() != arena:
		if _strikes.get_parent() != null:
			_strikes.get_parent().remove_child(_strikes)
		arena.add_child(_strikes)
	if not _strikes.landed.is_connected(_on_landed):
		_strikes.landed.connect(_on_landed)
	shed = false
	lantern.call("begin")


func _new_phase() -> void:
	var pc := rules.phase_cfg()
	_set_tide(rules.tide_step)
	_adds_t = 8.0
	mode = "idle"
	_gap = 2.0
	if pc.has("notice"):
		_tell_notice(String(pc["notice"]))
	if rules.shed():
		_shed_shell()
	last = "phase %d: %s" % [rules.phase + 1, String(pc["name"])]


# The shell is left standing in the pool; its bell's clapper becomes a hook ring (every machine does this).
func _shed_shell() -> void:
	shed = true
	if _shell == null or not is_instance_valid(_shell) or _arena() == null:
		return
	var b := boss_cfg(boss_id)
	var keep := _shell.global_transform
	_shell.get_parent().remove_child(_shell)
	_arena().add_child(_shell)
	_shell.global_transform = keep
	_shell.position = Vector3(float(b["home"][0]), -1.0, float(b["home"][1]))  # it stays standing in the pool, leaning as it was
	var clapper := _shell.find_child("Clapper", true, false) as Node3D
	if clapper != null:
		_bell_ring = Node3D.new()
		_bell_ring.add_to_group("hook_ring")
		_bell_ring.set_meta("toll", boss_id)
		clapper.add_child(_bell_ring)
		_bell_ring.position = Vector3(0.0, -1.6, 0.0)
	_shed_solids()
	_burst(_shell.global_position + Vector3(0.0, 1.0, 0.0), Color(0.75, 0.85, 0.9), 50, 1.2)


func _burst(at: Vector3, color: Color, n: int, life: float) -> void:
	FxKit.burst(_arena(), at, color, n, life, 0.3, 5.0, -5.0)


# Its body box once the tower is off: only the crab (data "shed_size"); the tower left in the pool is solid itself.
func _shed_solids() -> void:
	var b := boss_cfg(boss_id)
	for c: Node in enemy.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var sz: Array = b.get("shed_size", [5.0, 2.6, 6.0])
			((c as CollisionShape3D).shape as BoxShape3D).size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
			(c as CollisionShape3D).position.y = float(sz[1]) * 0.5
	if _shell == null or not is_instance_valid(_shell):
		return
	var t: Dictionary = b.get("shell_solid", {})
	if t.is_empty():
		return
	var solid := StaticBody3D.new()
	solid.add_to_group("boss_shell")  # (the Grapple Hook sees through it to the bell's clapper: game/sea_tools.gd)
	solid.collision_layer = 1
	solid.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var sz2: Array = t["size"]
	box.size = Vector3(float(sz2[0]), float(sz2[1]), float(sz2[2]))
	shape.shape = box
	var at: Array = t["at"]
	shape.position = Vector3(float(at[0]), float(at[1]), float(at[2]))
	shape.rotation_degrees = Vector3(float(t["lean_deg"]), 0.0, 0.0)
	solid.add_child(shape)
	_shell.add_child(solid)


func _spawn_adds() -> void:
	var b := boss_cfg(boss_id)
	var spots: Array = b["adds_at"]
	var r: RefCounted = _arena().get("rules")
	var i := 0
	_adds = _adds.filter(func(m: int) -> bool: return (_crews().get("men") as Dictionary).has(m))
	for kind: String in rules.adds_now():
		if _adds.size() >= 8:
			break
		var c: Array = spots[i % spots.size()]
		var at: Vector3 = r.call("at_of", Vector2i(int(c[0]), int(c[1])))
		var n := int(_crews().call("dungeon_spawn", kind, _arena(), at, int(b.get("region", 1))))
		if n >= 0:
			_adds.append(n)
		i += 1


func _crews() -> Node:
	return _dungeons.call("_crews")


# The fight ends: won (the boss fell) or lost (everyone down / out: wipe = they wake at the port; or everyone left).
func _end(won: bool, wipe: bool) -> void:
	var id := boss_id
	open.erase(id)
	_crews().call("dungeon_clear", _adds)
	_adds.clear()
	if id != "":
		_set_tide(-1)
	if won:
		beaten[id] = int(beaten.get(id, 0)) + 1
		wins += 1
		state = "won"
		_won_t = 10.0
		var net := _net()
		if net != null and bool(net.call("active")):
			net.call("tell_boss_end", id, "won")
		ended(id, "won")
	else:
		if wipe:
			wipes += 1
			var net := _net()
			if net != null and bool(net.call("active")):
				net.call("tell_boss_end", id, "wipe")
			ended(id, "wipe")
		_clear_boss()
	rules.downs.clear()
	(_dungeons as Node).set("_dirty", true)
	last = "%s %s" % [id, "won" if won else ("wipe" if wipe else "reset")]


func _clear_boss() -> void:
	if enemy != null and is_instance_valid(enemy):
		director.call("forget", enemy)
		enemy.queue_free()
	enemy = null
	if _shell != null and is_instance_valid(_shell) and _shell.get_parent() == _arena():
		_shell.queue_free()
	_shell = null
	_bell_ring = null
	_parts.clear()
	if _strikes != null and is_instance_valid(_strikes):
		_strikes.clear()
	if lantern != null:
		lantern.call("clear")
	state = ""
	mode = "idle"
	attack = ""
	shed = false
	boss_id = ""
	downs.clear()


# The old host left mid-fight and this machine hosts now (sea step 12): the boss pulls back to full strength and comes
# again for whoever is in the arena; the offering is NOT spent (the door stays open); the downs are forgiven.
func adopt_as_host() -> bool:
	if state != "wait" and state != "fight":
		return false
	var id := boss_id
	_crews().call("dungeon_clear", _adds)
	_adds.clear()
	_set_tide(-1)
	_clear_boss()
	rules.downs.clear()
	open[id] = true
	(_dungeons as Node).set("_dirty", true)
	last = "%s: host changed, fight begins again" % id
	return true


# On every machine: the fight ended for the players in that arena.
func ended(id: String, how: String) -> void:
	var b := boss_cfg(id)
	if b.is_empty():
		return
	var arena := String(b["arena"])
	var s := get_tree().get_first_node_in_group("game_session")
	var here := String(_dungeons.get("where")) == arena
	if how == "won":
		if here:  # (everyone in the arena, standing, down or out: the whole team's kill)
			_reward(id)
			if s != null and s.has_method("boss_kill_xp"):
				s.call("boss_kill_xp")
		_sea.emit_signal("notice", String(b["won_notice"]))
		if s != null and s.has_method("boss_over"):
			s.call("boss_over", false)
	elif how == "wipe":
		if here and s != null and s.has_method("boss_over"):
			s.call("boss_over", true)
	if not _host():
		_clear_boss()


# The boss fell: its loot pool, trophy and plates into this player's bags (each player rolls his own).
func _reward(id: String) -> void:
	var b := boss_cfg(id)
	var said := PackedStringArray()
	var db: RefCounted = _player.get("gun_db")
	var band := ItemLevel.region_band(int(b.get("region", 1)))
	for gun: Dictionary in LootPool.roll(db, _rng, String(b["loot_pool"]), Threat.loot_level(band.y), 1.0 + Threat.ng_luck()):  # (NG+: levels, luck)
		if (_player.get("inventory") as RefCounted).call("add_gun", gun):
			said.append(GunStats.display_name(db, gun))
	_player.call("refresh_held")
	var skills: Variant = _sea.get("skills")
	if skills != null:
		var bag: RefCounted = (skills as Node).get("bag")
		(skills as Node).call("give", String(b["trophy"]), 1)
		said.append(String(bag.call("item_name", String(b["trophy"]))))
		var plates: Dictionary = b["plates"]
		var n := _rng.randi_range(int(plates["n"][0]), int(plates["n"][1]))
		(skills as Node).call("give", String(plates["item"]), n)
		said.append("%d %s" % [n, String(bag.call("item_name", String(plates["item"])))])
	last = "reward: " + ", ".join(said)
	rewarded = ", ".join(said)
	_sea.emit_signal("notice", "Boss loot: " + ", ".join(said))
	var s := get_tree().get_first_node_in_group("game_session")
	if s != null and s.has_method("save_profile"):
		s.call("save_profile")


func _on_died(_e: Node) -> void:
	if _host() and state == "fight":
		_end(true, false)


func _set_tide(step: int) -> void:
	tide = step
	var arena := _arena_id()
	if arena != "":
		_dungeons.call("boss_tide", arena, String(boss_cfg(boss_id)["tide_thing"]), step)


func _tell_notice(text: String) -> void:
	_sea.emit_signal("notice", text)
	var net := _net()
	if net != null and bool(net.call("active")):
		net.call("tell_boss_notice", text)


# --- the host drives the boss ---

func _nearest_up(from: Vector3, floor_only: bool) -> Array:
	var best: Array = []
	var best_d := INF
	for b: Array in _bodies():
		if rules.state_of(int(b[0])) != "up":
			continue
		var local: Vector3 = b[2]
		if floor_only and _ground(local) > 1.0:
			continue
		var d := Vector2(local.x - from.x, local.z - from.z).length()
		if d < best_d:
			best_d = d
			best = b
	return best


func _drive(delta: float) -> void:
	var b := boss_cfg(boss_id)
	var pos := enemy.position
	var home := Vector3(float(b["home"][0]), 0.0, float(b["home"][1]))
	var speed := float(b["speed"]) * rules.speed_mult()
	var in_pool := bool(rules.phase_cfg().get("in_pool", false))
	var anchor := bool(rules.phase_cfg().get("anchor", false))  # (stays at home and only turns: the Queen on her island)
	var goal := _swim_point(home)
	var target := _nearest_up(pos, false)
	var a := rules.attack_cfg(attack)
	if rules.stunned():
		if mode != "stunned":
			mode = "stunned"
			attack = ""
			_strikes.clear()
		rear = move_toward(rear, -0.3, delta * 2.0)
		return
	if mode == "stunned":
		mode = "idle"
		_gap = 1.0
	var y_goal := (-1.4 if in_pool else (-0.8 if _in_pit(pos) else 0.0))
	match mode:
		"idle":
			rear = move_toward(rear, 0.0, delta * 2.0)
			if not target.is_empty():
				var to: Vector3 = (target[2] as Vector3) - pos
				to.y = 0.0
				_face(to, delta, 2.5)
				if in_pool or anchor:
					pos = pos.move_toward(Vector3(goal.x, pos.y, goal.z), speed * delta)
				elif to.length() > float(b["keep_m"]):
					pos += to.normalized() * minf(speed * delta, to.length() - float(b["keep_m"]))
			_gap -= delta
			if _gap <= 0.0 and not target.is_empty():
				_begin(rules.pick_attack(_rng), target)
		"windup":
			_t -= delta
			rear = move_toward(rear, 1.0 if bool(a.get("rear", false)) else 0.2, delta * 2.5)
			if String(a.get("shape", "")) == "under":
				y_goal = -4.0
			elif not target.is_empty() and String(a.get("shape", "")) in ["arc", "charge"] and _t > _t_total * 0.5:
				var to2: Vector3 = (target[2] as Vector3) - pos
				to2.y = 0.0
				_face(to2, delta, 4.0)  # tracks its quarry in the first half of the warning, then commits
			if _t <= 0.0:
				pos = _strike(a, pos)
		"strike":
			pos = _strike_run(a, pos, delta)
		"recover":
			rear = move_toward(rear, 0.0, delta * 1.5)
			_t -= delta
			if _t <= 0.0:
				mode = "idle"
				_gap = float(a.get("gap", 2.5)) / maxf(rules.speed_mult(), 0.5)
				attack = ""
	if mode != "strike" or String(a.get("shape", "")) != "leap":
		pos.y = move_toward(pos.y, y_goal if mode != "strike" else pos.y, 3.0 * delta)
	var flat := Vector3(pos.x - home.x, 0.0, pos.z - home.z)
	if flat.length() > float(b["arena_r"]):
		flat = flat.normalized() * float(b["arena_r"])
		pos = Vector3(home.x + flat.x, pos.y, home.z + flat.z)
	enemy.position = pos


# Where she swims to in the pool: home, or round it on the phase's circle (circle m, once round in circle_s).
func _swim_point(home: Vector3) -> Vector3:
	var pc := rules.phase_cfg()
	var r := float(pc.get("circle", 0.0))
	if r <= 0.0:
		return home
	var ang := rules.fight_t * TAU / maxf(float(pc.get("circle_s", 30.0)), 1.0)
	return home + Vector3(cos(ang) * r, 0.0, sin(ang) * r)


func _in_pit(local: Vector3) -> bool:
	var r: RefCounted = _arena().get("rules")
	return String(r.call("char_at", r.call("cell_of", local))) == "="


func _face(to: Vector3, delta: float, rate: float) -> void:
	if to.length() > 0.05:
		enemy.rotation.y = lerp_angle(enemy.rotation.y, atan2(-to.x, -to.z), 1.0 - exp(-rate * delta))


func _forward() -> Vector3:
	return Vector3(-sin(enemy.rotation.y), 0.0, -cos(enemy.rotation.y))


func _begin(id: String, target: Array) -> void:
	var a := rules.attack_cfg(id)
	if a.is_empty():
		_gap = 1.0
		return
	targets = []
	var shape := String(a["shape"])
	match shape:
		"under":
			var t := _nearest_up(enemy.position, true)
			if t.is_empty():  # everyone is up on the pillars: something else
				_gap = 0.5
				return
			var spot: Vector3 = t[2]
			targets = [Vector3(spot.x, 0.0, spot.z)]
		"lob":
			var bodies := _bodies().filter(func(b: Array) -> bool: return rules.state_of(int(b[0])) == "up")
			for i in int(a["count"]):
				if bodies.is_empty():
					break
				var b2: Array = bodies[i % bodies.size()]
				var at: Vector3 = b2[2]
				var jitter := Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5)) if i >= bodies.size() else Vector3.ZERO
				targets.append(Vector3(at.x, _ground(at), at.z) + jitter)
		"leap":
			var spot2: Vector3 = target[2]
			targets = [Vector3(spot2.x, _ground(spot2), spot2.z)]
		"line":  # (the Queen's root lash) along the walkway the target stands on: across the line from home to him
			var spot3: Vector3 = target[2]
			var c := Vector3(float(boss_cfg(boss_id)["home"][0]), 0.0, float(boss_cfg(boss_id)["home"][1]))
			var out := Vector3(spot3.x - c.x, 0.0, spot3.z - c.z)
			var along := Vector3(-out.z, 0.0, out.x).normalized() if out.length() > 0.1 else Vector3.RIGHT
			var mid := Vector3(spot3.x, _ground(spot3), spot3.z)
			var half := float(a["length"]) * 0.5
			targets = [mid - along * half, mid + along * half]
	attack = id
	mode = "windup"
	_t = float(a["windup"])
	_t_total = _t
	_hits_left = int(a.get("hits", 1))
	last = "winding up " + id


func _strike(a: Dictionary, pos: Vector3) -> Vector3:
	_hit_set = {}
	var dmg := float(a["damage"]) * _region_mult * rules.damage_mult()
	match String(a["shape"]):
		"arc":
			_hit_arc(pos, float(a["reach"]), float(a["deg"]), dmg)
			_hits_left -= 1
			if _hits_left > 0:
				_t = 0.35
				_t_total = 0.35
				return pos
			_recover(a)
		"ring":
			ring_r = 0.0
			mode = "strike"
			toll = 1.0
		"charge":
			_charge_left = float(a["length"])
			_charge_dir = _forward()
			mode = "strike"
		"under":
			pos = Vector3((targets[0] as Vector3).x, 0.0, (targets[0] as Vector3).z)
			_hit_circle(targets[0], float(a["radius"]), dmg, false)
			rear = 1.0
			_recover(a)
		"lob":
			_landings = []
			for t: Vector3 in targets:
				_landings.append([t, float(a["flight"])])
			_strikes.lob(pos + Vector3(0.0, 3.0, 0.0), targets, float(a["flight"]), float(a["radius"]), _lob_color(a), _lob_cloud(a))
			mode = "strike"
		"line":
			if targets.size() >= 2:
				_hit_line(targets[0], targets[1], float(a["width"]), dmg)
			_recover(a)
		"leap":
			_leap_from = pos
			_leap_t = 0.0
			mode = "strike"
	return pos


func _strike_run(a: Dictionary, pos: Vector3, delta: float) -> Vector3:
	var dmg := float(a["damage"]) * _region_mult * rules.damage_mult()
	match String(a["shape"]):
		"ring":
			ring_r += float(a["speed"]) * delta
			for b: Array in _bodies():
				var local: Vector3 = b[2]
				var d := Vector2(local.x - pos.x, local.z - pos.z).length()
				var ground := _ground(local)
				if absf(d - ring_r) < float(a["width"]) * 0.5 and ground < 1.0 and local.y - ground < float(a["jump_h"]):
					_hit_body(b, dmg)
			if ring_r > float(a["max_r"]):
				ring_r = -1.0
				_recover(a)
		"charge":
			var step := float(a["speed"]) * rules.speed_mult() * delta
			var next := pos + _charge_dir * step
			var home := Vector3(float(boss_cfg(boss_id)["home"][0]), 0.0, float(boss_cfg(boss_id)["home"][1]))
			if Vector2(next.x - home.x, next.z - home.z).length() > float(boss_cfg(boss_id)["arena_r"]):
				_charge_left = 0.0  # hits the wall
			else:
				pos = next
				_charge_left -= step
			var front := pos + _charge_dir * 5.0  # (its claws: it stops before its body reaches the player)
			for b: Array in _bodies():
				var local: Vector3 = b[2]
				if Vector2(local.x - front.x, local.z - front.z).length() < float(a["width"]) * 0.5 + 0.6 and absf(local.y - pos.y) < 2.5 and not _hit_set.has(b[1]):
					_hit_body(b, dmg)
					_charge_left = 0.0  # rammed: it stops there
			if _charge_left <= 0.0:
				_recover(a)
		"lob":
			var left: Array = []
			for l: Array in _landings:
				l[1] = float(l[1]) - delta
				if float(l[1]) <= 0.0:
					_hit_set = {}
					_hit_circle(l[0], float(a["radius"]), dmg, true)
				else:
					left.append(l)
			_landings = left
			if _landings.is_empty():
				_recover(a)
		"leap":
			_leap_t += delta
			var k := clampf(_leap_t / float(a["flight"]), 0.0, 1.0)
			var to: Vector3 = targets[0]
			pos = _leap_from.lerp(Vector3(to.x, 0.0, to.z), k) + Vector3(0.0, sin(k * PI) * 6.0, 0.0)
			if k >= 1.0:
				_hit_circle(to, float(a["radius"]), dmg, false)
				_burst(_arena().to_global(to + Vector3(0.0, 0.3, 0.0)), Color(0.7, 0.8, 0.85), 40, 1.0)
				_recover(a)
	return pos


func _recover(a: Dictionary) -> void:
	mode = "recover"
	_t = float(a.get("recover", 1.0))


func _hit_arc(pos: Vector3, reach: float, deg: float, dmg: float) -> void:
	var fwd := _forward()
	for b: Array in _bodies():
		var local: Vector3 = b[2]
		var v := Vector3(local.x - pos.x, 0.0, local.z - pos.z)
		if v.length() <= reach and absf(local.y - maxf(pos.y, 0.0)) < 2.5 and (v.length() < 1.0 or rad_to_deg(fwd.angle_to(v.normalized())) <= deg * 0.5):
			_hit_body(b, dmg)


func _hit_line(from: Vector3, to: Vector3, width: float, dmg: float) -> void:
	var seg := Vector2(to.x - from.x, to.z - from.z)
	for b: Array in _bodies():
		var local: Vector3 = b[2]
		var rel := Vector2(local.x - from.x, local.z - from.z)
		var k := clampf(rel.dot(seg) / maxf(seg.length_squared(), 0.01), 0.0, 1.0)
		if (rel - seg * k).length() <= width * 0.5 + 0.4 and absf(local.y - from.y) < 2.2:
			_hit_body(b, dmg)


# A lobbed ball's colour (the attack's "color", else water) and the spore cloud it leaves ({} = none).
func _lob_color(a: Dictionary) -> Color:
	var c: Array = a.get("color", [])
	return Color(float(c[0]), float(c[1]), float(c[2]), 0.8) if c.size() >= 3 else Color(0.55, 0.85, 1.0, 0.75)


func _lob_cloud(a: Dictionary) -> Dictionary:
	if not a.has("cloud_s"):
		return {}
	return {"radius": float(a["radius"]), "cloud_s": float(a["cloud_s"]), "blind_s": float(a.get("blind_s", 3.0))}


func _on_landed(at: Vector3, cloud: Dictionary) -> void:
	lantern.call("add_cloud", at, cloud)


func _hit_circle(at: Vector3, radius: float, dmg: float, any_height: bool) -> void:
	for b: Array in _bodies():
		var local: Vector3 = b[2]
		if Vector2(local.x - at.x, local.z - at.z).length() <= radius and (any_height or absf(local.y - at.y) < 2.2):
			_hit_body(b, dmg)


func _hit_body(b: Array, dmg: float) -> void:
	var body: Node3D = b[1]
	if _hit_set.has(body) or rules.state_of(int(b[0])) != "up":
		return
	_hit_set[body] = true
	body.call("take_damage", dmg, "physical")
	blows += 1


# --- hits on its parts (game/boss_part.gd) ---

func part_hit(id: String, damage: float) -> void:
	if enemy == null or not is_instance_valid(enemy) or not is_finite(damage) or damage <= 0.0:
		return
	var p := rules.part_cfg(id) if boss_id != "" else {}
	if p.is_empty():
		return
	if String(p["kind"]) == "weak":  # passes the armour: the boss's guard would cut it, so it is raised by as much
		enemy.call("on_hit", damage * float(p.get("share", 1.0)) / maxf(_body_share_now(), 0.01))
		return
	if not _host():
		var net := _net()
		if net != null:
			net.call("request_boss_part", id, damage)
		return
	host_part(id, damage)


func host_part(id: String, damage: float) -> void:
	if state != "fight":
		return
	var got := rules.hit_part(id, minf(damage, 5000.0))
	if got != "":
		broke += 1
		_show_part(id, false, false)
	if got == "crack":
		_tell_notice(String(rules.phase_cfg().get("crack_notice", "The shell cracks open! Hit it now!")))


func _body_share_now() -> float:
	if _host():
		return rules.body_share()
	if shed or cracked or stunned:
		return 1.0
	var ph: Array = boss_cfg(boss_id)["phases"]
	return float(ph[clampi(phase, 0, ph.size() - 1)].get("armour", 1.0))


# The parts' looks and hit boxes: a breakable stays on till broken (or the shell is shed) and is hittable only in its
# phase (where two phases' breakables share a node, this phase's decides); a "lit" weak point is live only while she
# is exposed (core/sea/boss_rules.gd weak_live). `broken` = the broken breakables (the host's own, or from its message).
func _show_parts(broken: Array = []) -> void:
	var now := rules.breakables()
	var host := _host()
	for id: String in _parts:
		var p: Dictionary = rules.part_cfg(id)
		if String(p.get("kind", "")) == "weak":
			(_parts[id] as BossPart).set_live(rules.weak_live(id))
		elif not (id in now):
			_show_part(id, not rules.shed() and not (rules.broken(id) if host else id in broken), false)
	for id: String in now:
		var gone := rules.broken(id) if host else id in broken
		_show_part(id, not gone, not gone and rules.regrow_at < 0.0)


func _show_part(id: String, shown: bool, live: bool) -> void:
	var part: BossPart = _parts.get(id)
	if part == null or not is_instance_valid(part):
		return
	part.set_live(live and shown)
	var node := part.get_parent() as Node3D
	if node != null:
		node.visible = shown


# --- the bell (the Grapple Hook on the shed shell's clapper) ---

func host_toll(peer: int) -> bool:
	if state != "fight" or not rules.try_stun():
		return false
	tolls += 1
	toll = 1.0
	_tell_notice("The bell tolls! It reels!")
	last = "stunned by %d's toll" % peer
	return true


# --- downed players ---

func fighting_here() -> bool:
	return state in ["wait", "fight"] and boss_id != "" and String(_dungeons.get("where")) == _arena_id()


func downs_cfg() -> Dictionary:
	return cfg["downs"]


func state_of(peer: int) -> String:
	return rules.state_of(peer) if _host() else String(downs.get(peer, "up"))


func down_peers() -> Array:
	return (rules.downs if _host() else downs).keys()


func report(s: String) -> void:
	if _host():
		host_down(_my_id(), s)
	else:
		var net := _net()
		if net != null:
			net.call("request_boss_down", s)


func host_down(peer: int, s: String) -> void:
	if state != "fight" and state != "wait":
		return
	rules.set_state(peer, s)
	last = "%d is %s" % [peer, s]


func ask_revive(target: int) -> void:
	if _host():
		host_revive(_my_id(), target)
	else:
		var net := _net()
		if net != null:
			net.call("request_boss_revive", target)


func host_revive(by: int, target: int) -> void:
	if by == target or rules.state_of(target) != "down" or rules.state_of(by) != "up":
		return
	var helper: Array = []
	var fallen: Array = []
	for b: Array in _bodies():
		if int(b[0]) == by:
			helper = b
		elif int(b[0]) == target:
			fallen = b
	if helper.is_empty() or fallen.is_empty() or (helper[2] as Vector3).distance_to(fallen[2]) > float(cfg["downs"]["reach"]) + 2.5:
		return
	rules.set_state(target, "up")
	var share := float(cfg["downs"]["health"])
	var s := get_tree().get_first_node_in_group("game_session")
	if target == _my_id():
		if s != null:
			s.call("_on_revived", share)
	else:
		var net := _net()
		if net != null:
			net.call("tell_boss_revived", target, share)
	if by == _my_id() and s != null:
		s.call("_on_gave_revive")
	last = "%d helped %d up" % [by, target]


# --- pose and marks (every machine) ---

func _pose(delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var model: Node3D = enemy.get("_model")
	if model == null:
		return
	model.rotation.x = lerpf(model.rotation.x, rear * 0.35, 1.0 - exp(-8.0 * delta))
	var t := Time.get_ticks_msec() / 1000.0
	if String(boss_cfg(boss_id).get("pose", "crab")) == "angler":
		_pose_angler(model, delta, t)
		return
	var moving := mode == "idle" or (mode == "strike" and attack == "scuttle")
	for i in 3:
		for side: String in ["L", "R"]:
			var leg := model.find_child("Leg%s%d" % [side, i + 1], true, false) as Node3D
			if leg != null:
				leg.rotation.x = sin(t * (9.0 if moving else 2.0) + float(i) * 1.7 + (PI if side == "R" else 0.0)) * (0.25 if moving else 0.05)
	for side: String in ["L", "R"]:
		var claw := model.find_child("Claw" + side, true, false) as Node3D
		if claw != null:
			claw.rotation.x = -rear * 0.6 + (sin(t * 1.3) * 0.05)
	var bell_root := _shell if _shell != null and is_instance_valid(_shell) else model
	var bell := bell_root.find_child("Bell", true, false) as Node3D
	if bell != null:
		bell.rotation.z = sin(t * 7.0) * 0.35 * toll
	if stunned or mode == "stunned":
		model.rotation.z = sin(t * 12.0) * 0.06


# The Lantern Queen: the jaw gapes while she winds up and strikes, the fin-legs paddle, the tail sways, the lure bobs.
func _pose_angler(model: Node3D, delta: float, t: float) -> void:
	var k := 1.0 - exp(-6.0 * delta)
	var jaw := model.find_child("Jaw", true, false) as Node3D
	if jaw != null:
		var gape := 0.5 if mode in ["windup", "strike"] else (0.25 if stunned or mode == "stunned" else 0.06 + sin(t * 0.7) * 0.04)
		jaw.rotation.x = lerpf(jaw.rotation.x, -gape, k)
	var moving := mode == "idle" or mode == "strike"
	for i in 2:
		for side: String in ["L", "R"]:
			var f := model.find_child("Fin%s%d" % [side, i + 1], true, false) as Node3D
			if f != null:
				f.rotation.x = sin(t * (4.0 if moving else 1.2) + float(i) * 1.9 + (PI if side == "R" else 0.0)) * (0.3 if moving else 0.06)
	var tail := model.find_child("Tail", true, false) as Node3D
	if tail != null:
		tail.rotation.y = sin(t * (2.6 if moving else 0.9)) * (0.35 if moving else 0.12)
	var stalk := model.find_child("LureStalk", true, false) as Node3D
	if stalk != null:
		stalk.rotation.x = sin(t * 0.9) * 0.07 + (0.12 if mode == "windup" else 0.0)
	if stunned or mode == "stunned":
		model.rotation.z = sin(t * 9.0) * 0.05


func _show_marks() -> void:
	if _strikes == null or not is_instance_valid(_strikes) or enemy == null or not is_instance_valid(enemy) or boss_id == "":
		return
	if _was_mode != mode and mode == "strike" and not _host() and String(rules.attack_cfg(attack).get("shape", "")) == "lob":
		var a := rules.attack_cfg(attack)
		_strikes.lob(enemy.position + Vector3(0.0, 3.0, 0.0), targets, float(a["flight"]), float(a["radius"]), _lob_color(a), _lob_cloud(a))
	_was_mode = mode
	var progress := 0.0
	if mode == "windup":
		progress = clampf(1.0 - _t / maxf(_t_total, 0.01), 0.0, 1.0)
	var floor_y := maxf(0.0, _tide_y() if _arena() != null else 0.0)
	_strikes.show_move(rules.attack_cfg(attack) if attack != "" else {}, mode, progress, enemy.position, enemy.rotation.y, targets, ring_r, floor_y)


# --- online ---

func to_net() -> Array:
	if enemy == null or not is_instance_valid(enemy):
		return [boss_id, state]
	var p := enemy.position
	var pts: Array = []
	for t: Vector3 in targets:
		pts.append_array([snappedf(t.x, 0.01), snappedf(t.y, 0.01), snappedf(t.z, 0.01)])
	var broken: Array = []
	for id: String in _parts:
		if rules.broken(id):
			broken.append(id)
	var dn: Array = []
	for peer: int in rules.downs:
		dn.append_array([peer, String(rules.downs[peer])])
	var progress := clampf(1.0 - _t / maxf(_t_total, 0.01), 0.0, 1.0) if mode == "windup" else 0.0
	return [boss_id, state, snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(enemy.rotation.y, 0.01), snappedf(hp_share, 0.001), phase, mode, attack, snappedf(progress, 0.01), pts, snappedf(ring_r, 0.01), shed, cracked, stunned, broken, dn, snappedf(rear, 0.01), snappedf(toll, 0.01), rules.enraged, lantern.call("to_net")]


# Client: the host's boss.
func from_net(got: Array) -> void:
	if got.size() < 2:
		return
	var id := String(got[0])
	if id != "" and boss_cfg(id).is_empty():
		return
	if got.size() < 21 or id == "":
		if enemy != null:
			_clear_boss()
		state = String(got[1]).left(8) if got.size() >= 2 else ""
		return
	if enemy == null or boss_id != id:
		if enemy != null:
			_clear_boss()
		boss_id = id
		if _arena() == null or not bool(_arena().get("built")):
			boss_id = ""
			return
		rules.setup(boss_cfg(id), cfg, 1, 1.0)
		_make(true)
	state = String(got[1]).left(8)
	var at := Vector3(float(got[2]), float(got[3]), float(got[4]))
	if not at.is_finite():
		return
	enemy.set("net_pos", at)
	enemy.set("net_yaw", float(got[5]))
	hp_share = clampf(float(got[6]), 0.0, 1.0)
	var hp: RefCounted = enemy.get("health")
	hp.set("hp", hp_share * float(hp.get("max_hp")))
	phase = clampi(int(got[7]), 0, 9)
	rules.phase = clampi(phase, 0, (boss_cfg(id)["phases"] as Array).size() - 1)
	mode = String(got[8]).left(10)
	attack = String(got[9]).left(16)
	var progress := clampf(float(got[10]), 0.0, 1.0)
	_t_total = 1.0
	_t = 1.0 - progress
	targets = []
	var pts: Array = got[11]
	for i in range(0, mini(pts.size(), 24) - 2, 3):
		targets.append(Vector3(float(pts[i]), float(pts[i + 1]), float(pts[i + 2])))
	ring_r = float(got[12])
	if bool(got[13]) and not shed:
		_shed_shell()
	cracked = bool(got[14])
	stunned = bool(got[15])
	if got.size() > 21 and got[21] is Array:  # (the Lantern Queen: exposed in a lit circle)
		lantern.call("from_net", got[21])
	_show_parts(got[16] as Array)
	downs.clear()
	var dn: Array = got[17]
	for i in range(0, mini(dn.size(), 24) - 1, 2):
		if String(dn[i + 1]) in ["down", "out"]:
			downs[int(dn[i])] = String(dn[i + 1])
	rear = clampf(float(got[18]), -0.5, 1.0)
	toll = maxf(toll, clampf(float(got[19]), 0.0, 1.0))
	rules.enraged = bool(got[20])


func host_hit(damage: float, _from: int) -> void:
	if enemy == null or not is_finite(damage) or damage <= 0.0 or state != "fight":
		return
	var before := String(card.get("blow")) if card != null else ""
	if card != null:
		card.set("blow", "other")
	enemy.call("on_hit", minf(damage, 20000.0))
	if card != null:
		card.set("blow", before)


# --- the host's world (saved with the dungeons) ---

func world_dict() -> Dictionary:
	return {"open": open.duplicate(), "beaten": beaten.duplicate()}


func load_world(saved: Variant) -> void:
	if not saved is Dictionary:
		return
	open = {}
	beaten = {}
	for id: String in cfg["bosses"]:
		if bool(((saved as Dictionary).get("open", {}) as Dictionary).get(id, false)):
			open[id] = true
		beaten[id] = int(((saved as Dictionary).get("beaten", {}) as Dictionary).get(id, 0))


func status() -> String:
	var hp := ""
	if enemy != null and is_instance_valid(enemy):
		var h: RefCounted = enemy.get("health")
		hp = "%.0f/%.0f" % [float(h.get("hp")), float(h.get("max_hp"))]
	return "boss '%s' %s hp %s phase %d mode %s attack '%s' tide %d shed %s cracked %s stunned %s enraged %s; open %s beaten %s; downs %s; fights %d wins %d wipes %d blows %d tolls %d broke %d; last '%s'; got '%s'" % [boss_id, state, hp, phase + 1, mode, attack, tide, str(shed), str(cracked), str(stunned), str(rules.enraged), str(open), str(beaten), str(rules.downs if _host() else downs), fights, wins, wipes, blows, tolls, broke, last, rewarded] + (("; " + String(lantern.call("status"))) if lantern != null and bool(lantern.call("active")) else "")
