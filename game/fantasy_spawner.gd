# Purpose: the creatures of the fantasy world: keeps a few of the current region's enemies around the players, removes
# the ones left far behind, wakes each region's boss when someone walks into its arena, keeps the two desert tribes
# fighting each other on their battlefield, keeps a few wild animals roaming (Hunting: data/fantasy/world.json animals),
# and pays out a kill (Magic experience, or Hunting for an animal, drops, quest progress). Nothing is
# gated: a boss is simply far stronger than its region, so the quests that level you up are the practical way to it.
# Creatures move by the world's own walker (around houses, trees and deep water) and never spawn inside something.
# Online this runs on the host only (game/net_fantasy.gd).
# Dependencies: game/wave_director.gd (spawn_custom, despawn, forget, enemy_list, killed), game/fantasy_world.gd
# (terrain, layout, walk_world, data["enemies"]), game/boss_moves.gd (through the world).
extends Node

signal notice(text: String)
signal spawned(enemy: Node3D)  # online: the host tells the other machines
signal slain(enemy_id: String, where: Vector3)  # paid out on every machine
signal boss_woke(enemy: Node3D, moves: Array)  # its special attacks start (game/boss_moves.gd)
signal armed(enemy: Node3D, moves: Array)  # an ordinary creature with an attack of its own appeared (game/boss_moves.gd)

const WALKS := {"land": 0, "swim": 1, "fly": 2}  # game/fantasy_world.gd WALK_*

var active := false
var targets: Callable  # returns the bodies of everyone in the world (online); empty = just the local player

var _world: Node3D
var _director: Node3D
var _player: Node3D
var _enemies: Dictionary
var _cfg: Dictionary
var _tribes: Dictionary  # data "tribes": the battlefield, the camps, how many warriors a side
var _field := Vector2.ZERO
var _camps := {}  # banner -> Vector2
var _zones := {}  # (polish1 item 111) Vector2i zone -> {"left": creatures before it falls quiet, "quiet_until": engine time}
var _bosses: Array = []  # {"id", "place", "pos": Vector2, "enemy", "respawn_at"}
var _warriors: Array[Node3D] = []
var _fill_at := {}  # banner -> engine time the next fallen warrior is replaced
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _acc := 0.0
var _acc_animals := 0.0


func setup(fantasy_world: Node3D, director: Node3D, player: Node3D) -> void:
	_world = fantasy_world
	_director = director
	_player = player
	_rng.randomize()
	var data: Dictionary = _world.data["enemies"]
	_enemies = data["enemies"]
	_cfg = data["spawn"]
	_add_phantoms(data.get("phantom", {}))
	_tribes = data["tribes"]
	for place: Dictionary in _world.terrain.places:
		var at := Vector2(float(place["pos"][0]), float(place["pos"][1]))
		if place.has("boss"):
			_bosses.append({"id": String(place["boss"]), "place": String(place["id"]), "pos": at, "enemy": null, "respawn_at": 0.0})
		if String(place["id"]) == String(_tribes["field"]):
			_field = at
		for banner: String in _tribes["camps"]:
			if String(place["id"]) == String(_tribes["camps"][banner]):
				_camps[banner] = at
	_director.connect("killed", _on_killed)


func start() -> void:
	active = true
	for boss: Dictionary in _bosses:
		boss["enemy"] = null
	_warriors.clear()


func stop() -> void:
	active = false


# (polish1 E4, item 133) Each boss's ECHO "<boss>_phantom": the boss's model in the echo look (game/echo_look.gd),
# weaker, its own drops (game/boss_trophy_keeper.gd rolls them), "phantom_of" = the boss it echoes.
func _add_phantoms(cfg: Dictionary) -> void:
	if cfg.is_empty():
		return
	for id: String in _enemies.keys():
		var boss: Dictionary = _enemies[id]
		if not bool(boss.get("boss", false)) or bool(boss.get("phantom", false)):
			continue
		var echo := boss.duplicate(true)
		var called := String(boss.get("name", id))
		echo["name"] = String(cfg.get("name", "Echo of %s")) % (("the " + called.substr(4)) if called.begins_with("The ") else called)
		echo["max_hp"] = float(boss["max_hp"]) * float(cfg.get("hp", 1.0))
		echo["damage"] = float(boss["damage"]) * float(cfg.get("damage", 1.0))
		echo["xp"] = roundi(float(boss["xp"]) * float(cfg.get("xp", 1.0)))
		echo["drops"] = {}
		echo.erase("relic")
		echo["phantom"] = true
		echo["phantom_of"] = id
		_enemies[id + "_phantom"] = echo


# The form a boss wakes in: its echo once the lobby (this host) has beaten it.
func _form(boss_id: String) -> String:
	return boss_id + "_phantom" if _world.quests.slain.has(boss_id) and _enemies.has(boss_id + "_phantom") else boss_id


func stats_of(id: String) -> Dictionary:
	return _enemies.get(id, {})


# The living boss and its health 0..1 ({} = none awake).
func boss_awake() -> Dictionary:
	for boss: Dictionary in _bosses:
		if is_instance_valid(boss["enemy"]) and not (boss["enemy"] as Node3D).health.is_dead():
			var enemy: Node3D = boss["enemy"]
			return {"name": String((_enemies.get(String(enemy.get("enemy_id")), _enemies[boss["id"]]) as Dictionary)["name"]), "ratio": float(enemy.health.hp) / float(enemy.health.max_hp)}
	return {}


func _bodies() -> Array:
	var out: Array = targets.call() if targets.is_valid() else []
	if out.is_empty():
		out = [_player]
	return out


func bodies() -> Array:
	return _bodies()


func _process(delta: float) -> void:
	if not active:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var all := _bodies()
	for body: Node3D in all:
		var local: Vector3 = _world.local_of(body.global_position)
		_world.layout.prepare(local.x, local.z)  # creatures are about to walk here: houses and props must be known
	_despawn_far(all)
	_calm_tick(all)
	_boss_tick(all)
	_tribe_tick(all)
	_retarget(all)
	_acc += float(_cfg["per_second"]) * 0.5
	while _acc >= 1.0:
		_acc -= 1.0
		if _count() < int(_cfg["max_alive"]):
			_spawn_group(all[_rng.randi() % all.size()])
	_acc_animals += float(_cfg.get("animals_per_second", 0.0)) * 0.5
	while _acc_animals >= 1.0:
		_acc_animals -= 1.0
		if _count(true) < int(_cfg.get("animals_max", 0)):
			_spawn_animal(all[_rng.randi() % all.size()])


func _mine(enemy: Variant) -> bool:
	return is_instance_valid(enemy) and (enemy as Node).has_meta("fantasy")


func _roams(enemy: Variant) -> bool:
	return _mine(enemy) and not (enemy as Node).has_meta("fantasy_boss") and String((enemy as Node).get("feud")) == ""


# Roaming creatures, or (animals true) wild animals: they are counted apart, so the two never crowd each other out.
func _count(animals: bool = false) -> int:
	var n := 0
	for enemy in _director.call("enemy_list"):
		if _roams(enemy) and (enemy as Node).has_meta("animal") == animals:
			n += 1
	return n


# One of the region's wild animals (data/fantasy/world.json "animals") out in the open country, not in a town.
func _spawn_animal(near: Node3D) -> void:
	var local: Vector3 = _world.local_of(near.global_position)
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(float(_cfg.get("animal_min_dist", 30.0)), float(_cfg.get("animal_max_dist", 60.0)))
	var x := local.x + cos(a) * d
	var z := local.z + sin(a) * d
	for place: Dictionary in _world.terrain.places:
		if String(place["kind"]) != "arena" and Vector2(x - float(place["pos"][0]), z - float(place["pos"][1])).length() < float(place["flat"]) + 12.0:
			return
	var kinds: Dictionary = _world.terrain.region_at(x, z).get("animals", {})
	var total := 0.0
	for id: String in kinds:
		total += float(kinds[id])
	var pick := _rng.randf() * total
	for id: String in kinds:
		pick -= float(kinds[id])
		if pick <= 0.0:
			if _enemies.has(id) and _fits(id, x, z):
				_spawn(id, x, z, near)
			return


func _nearest(list: Array, at: Vector3) -> Node3D:
	var best: Node3D = list[0]
	for body: Node3D in list:
		if is_instance_valid(body) and body.global_position.distance_to(at) < best.global_position.distance_to(at):
			best = body
	return best


func _despawn_far(all: Array) -> void:
	var far := float(_cfg["despawn_dist"])
	for enemy in (_director.call("enemy_list") as Array).duplicate():
		if _roams(enemy):
			if _nearest(all, (enemy as Node3D).global_position).global_position.distance_to((enemy as Node3D).global_position) > far:
				_director.call("despawn", enemy)


# (polish1 item 111) Calm and give-up rules for the roaming creatures, twice a second: one that strays into a town /
# farm / village's calm ring, or whose nearest player is far above it (Magic level at least its level + ignore_gap:
# known for this machine's player; the others count as level 0), goes ALOOF (wanders, leaves players be until hurt);
# one whose nearest player is further than give_up_m gives the chase up (despawned).
func _calm_tick(all: Array) -> void:
	var give_up := float(_cfg.get("give_up_m", 45.0))
	var gap := int(_cfg.get("ignore_gap", 10))
	var calm_m := float(_cfg.get("calm_m", 20.0))
	for enemy in (_director.call("enemy_list") as Array).duplicate():
		if not _roams(enemy) or (enemy as Node).has_meta("animal"):
			continue
		var e: Node3D = enemy
		var near := _nearest(all, e.global_position)
		if near.global_position.distance_to(e.global_position) > give_up:
			_director.call("despawn", e)
			continue
		var level := int(_world.skills.level("magic")) if near == _player else 0
		var calm := level >= int(e.get_meta("tier", 1)) + gap
		if not calm:
			var local: Vector3 = _world.local_of(e.global_position)
			for place: Dictionary in _world.terrain.places:
				if String(place["kind"]) != "arena" and Vector2(local.x - float(place["pos"][0]), local.z - float(place["pos"][1])).length() < float(place["flat"]) + calm_m:
					calm = true
					break
		e.set("aloof", calm)


# (polish1 item 111) Zones of zone_m metres: each holds zone_pool creatures; every kill there takes one; an emptied zone
# stays QUIET (nothing spawns in it) for zone_quiet_s, then fills again. Spawning alone never empties a zone.
func _zone_of(x: float, z: float) -> Vector2i:
	var size := float(_cfg.get("zone_m", 120.0))
	return Vector2i(floori(x / size), floori(z / size))


func zone_quiet(x: float, z: float) -> bool:
	var key := _zone_of(x, z)
	return _zones.has(key) and float((_zones[key] as Dictionary).get("quiet_until", 0.0)) > Time.get_ticks_msec() / 1000.0


func _zone_kill(x: float, z: float) -> void:
	var key := _zone_of(x, z)
	var now := Time.get_ticks_msec() / 1000.0
	var zone: Dictionary = _zones.get(key, {"left": int(_cfg.get("zone_pool", 8)), "quiet_until": 0.0})
	if float(zone["quiet_until"]) > 0.0 and float(zone["quiet_until"]) <= now:  # quiet time over: full again
		zone = {"left": int(_cfg.get("zone_pool", 8)), "quiet_until": 0.0}
	zone["left"] = int(zone["left"]) - 1
	if int(zone["left"]) <= 0 and float(zone["quiet_until"]) <= now:
		zone["quiet_until"] = now + float(_cfg.get("zone_quiet_s", 300.0))
		notice.emit("This stretch of land falls quiet.")
	_zones[key] = zone


# (dev) the zone here: creatures left before it falls quiet, seconds of quiet left.
func zone_note(x: float, z: float) -> String:
	var zone: Dictionary = _zones.get(_zone_of(x, z), {"left": int(_cfg.get("zone_pool", 8)), "quiet_until": 0.0})
	return "zone %s: %d left, quiet %.0f s" % [str(_zone_of(x, z)), int(zone["left"]), maxf(float(zone["quiet_until"]) - Time.get_ticks_msec() / 1000.0, 0.0)]


# Each creature chases whoever is closest to it (tribe warriors choose in _tribe_tick).
func _retarget(all: Array) -> void:
	if all.size() < 2:
		return
	for enemy in _director.call("enemy_list"):
		if _mine(enemy) and String((enemy as Node).get("feud")) == "":
			(enemy as Node).call("set_target", _nearest(all, (enemy as Node3D).global_position))


func _spawn_group(near: Node3D) -> void:
	var local: Vector3 = _world.local_of(near.global_position)
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(float(_cfg["min_dist"]), float(_cfg["max_dist"]))
	var x := local.x + cos(a) * d
	var z := local.z + sin(a) * d
	for place: Dictionary in _world.terrain.places:  # towns, farms and camps are safe; arenas belong to their boss
		if Vector2(x - float(place["pos"][0]), z - float(place["pos"][1])).length() < float(place["flat"]) + float(_cfg["safe_radius"]) * (1.0 if String(place["kind"]) != "arena" else 0.2):
			return
	if zone_quiet(x, z):  # (polish1 item 111) a cleared stretch stays quiet a while
		return
	var kinds: Array = _world.terrain.region_at(x, z)["enemies"]
	if kinds.is_empty():
		return
	for i in _rng.randi_range(1, int(_cfg["group_max"])):
		var id := String(kinds[_rng.randi() % kinds.size()])
		var sx := x + _rng.randf_range(-3.0, 3.0)
		var sz := z + _rng.randf_range(-3.0, 3.0)
		if _fits(id, sx, sz):
			_spawn(id, sx, sz, near)


# A creature may stand here: not inside a house or a tree, and in water only if it swims or flies.
func _fits(id: String, x: float, z: float) -> bool:
	var stats: Dictionary = _enemies[id]
	var walks := String(stats.get("walks", "land"))
	if walks == "fly":
		return true
	var wet: bool = _world.terrain.water_at(x, z) != ""
	if wet:
		return walks == "swim" and _world.terrain.water_at(x, z) == "salt" and _world.terrain.height(x, z) > _world.terrain.sea - 2.5
	return not _world.layout.blocked(x, z, float(stats["size"][0]) * 0.5)


func _spawn(id: String, x: float, z: float, near: Node3D) -> Node3D:
	var stats: Dictionary = (_enemies[id] as Dictionary).duplicate(true)
	var enemy: Node3D = _director.call("spawn_custom", id, stats, _world.ground_world(x, z))
	enemy.set_meta("fantasy", true)
	enemy.set("walker", walker_for(stats))
	enemy.set_meta("tier", int(stats["level"]))
	if stats.has("temper"):  # a wild animal (Hunting): no squad, counted apart
		enemy.set_meta("animal", true)
	if bool(stats.get("boss", false)):
		enemy.set_meta("fantasy_boss", true)
	elif stats.has("moves"):
		armed.emit(enemy, stats["moves"])
	enemy.call("set_target", near)
	spawned.emit(enemy)
	return enemy


# How a creature with these stats moves over the land (also used when a puppet becomes ours: game/net_fantasy.gd).
func walker_for(stats: Dictionary) -> Callable:
	var walks := String(stats.get("walks", "land"))
	var hover := float(stats.get("hover", 1.4)) if walks == "fly" else 0.0
	return Callable(_world, "walk_world").bind(float(stats["size"][0]) * 0.5, int(WALKS[walks]), hover)


func _boss_tick(all: Array) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for boss: Dictionary in _bosses:
		var middle: Vector3 = _world.ground_world(boss["pos"].x, boss["pos"].y)
		var near := _nearest(all, middle)
		var d := Vector2(near.global_position.x - middle.x, near.global_position.z - middle.z).length()
		var alive: bool = is_instance_valid(boss["enemy"]) and not (boss["enemy"] as Node3D).health.is_dead()
		if alive and d > float(_cfg["boss_leash_m"]):
			_director.call("despawn", boss["enemy"])  # nobody is near: it goes back to sleep, healed
			boss["enemy"] = null
		elif not alive and now >= float(boss["respawn_at"]) and d < float(_cfg["boss_trigger_m"]):
			var form := _form(String(boss["id"]))
			boss["enemy"] = _spawn(form, boss["pos"].x, boss["pos"].y, near)
			var stats: Dictionary = _enemies[form]
			notice.emit("%s  (level %d)" % [String(stats["name"]).to_upper(), int(stats["level"])])
			boss_woke.emit(boss["enemy"], stats.get("moves", []))


# --- the desert tribes ---

# While someone is near the battlefield each banner keeps its warriors there. A warrior goes for the nearest warrior
# of the other banner, unless a player stands close: then the player is the enemy. Fallen warriors are replaced from
# their camp's side after a short while. Kills between warriors pay nobody.
func _tribe_tick(all: Array) -> void:
	if _camps.size() < 2:
		return
	var middle: Vector3 = _world.ground_world(_field.x, _field.y)
	var near := _nearest(all, middle)
	var awake := Vector2(near.global_position.x - middle.x, near.global_position.z - middle.z).length() < float(_tribes["wake_m"])
	for i in range(_warriors.size() - 1, -1, -1):
		if not is_instance_valid(_warriors[i]) or _warriors[i].health.is_dead():
			_warriors.remove_at(i)
		elif not awake:
			_director.call("despawn", _warriors[i])
			_warriors.remove_at(i)
	if not awake:
		return
	var now := Time.get_ticks_msec() / 1000.0
	for banner: String in _camps:
		var have := 0
		for w in _warriors:
			if String(w.get("feud")) == banner:
				have += 1
		if have < int(_tribes["per_side"]) and now >= float(_fill_at.get(banner, 0.0)):
			_fill_at[banner] = now + (float(_tribes["respawn_s"]) if have > 0 else 0.0)  # the first line-up arrives at once
			var toward: Vector2 = (_camps[banner] - _field).normalized()
			var side := Vector2(-toward.y, toward.x)
			var at: Vector2 = _field + toward * 22.0 + side * _rng.randf_range(-9.0, 9.0)
			var id := banner + "_warrior"
			if _enemies.has(id) and _fits(id, at.x, at.y):
				var warrior := _spawn(id, at.x, at.y, near)
				warrior.set("feud", banner)
				warrior.connect("felled", _on_felled)
				_warriors.append(warrior)
	var turn := float(_tribes["turn_on_player_m"])
	for w in _warriors:
		var body := _nearest(all, w.global_position)
		var foe: Node3D = body if body.global_position.distance_to(w.global_position) < turn or w.has_meta("provoked") else null
		if foe == null:
			for other in _warriors:
				if String(other.get("feud")) != String(w.get("feud")) and (foe == null or other.global_position.distance_to(w.global_position) < foe.global_position.distance_to(w.global_position)):
					foe = other
		if foe == null:
			foe = body
		w.call("set_target", foe)
		if w.health.hp < float(w.get_meta("seen_hp", w.health.max_hp)) and not w.has_meta("feud_hit"):
			w.set_meta("provoked", true)  # a player struck it: it stays on players until it falls
		w.set_meta("seen_hp", w.health.hp)
		w.remove_meta("feud_hit")


# A warrior killed by a warrior: off the list, no pay; its body falls by itself.
func _on_felled(enemy: Node) -> void:
	_director.call("forget", enemy)


# Host migration: a creature that was a puppet here is now ours to run (a boss keeps its place in the list).
func adopt(enemy: Node3D) -> void:
	for boss: Dictionary in _bosses:
		if String(boss["id"]) == String(enemy.get("enemy_id")):
			boss["enemy"] = enemy
			boss_woke.emit(enemy, _enemies[boss["id"]].get("moves", []))
	var banner := String(stats_of(String(enemy.get("enemy_id"))).get("tribe", ""))
	if banner != "":
		enemy.set("feud", banner)
		enemy.connect("felled", _on_felled)
		_warriors.append(enemy)


# Command /spawn, and a boss calling help: one creature at a spot of the map (local metres).
func spawn_local(id: String, x: float, z: float, near: Node3D) -> Node3D:
	if not _enemies.has(id):
		return null
	var free: Vector2 = _world.layout.push_out(x, z, float(_enemies[id]["size"][0]) * 0.5)
	return _spawn(id, free.x, free.y, near)


func spawn_at(id: String, body: Node3D) -> bool:
	var local: Vector3 = _world.local_of(body.global_position)
	return spawn_local(id, local.x + 4.0, local.z + 4.0, body) != null


func ids() -> Array:
	return _enemies.keys()


func _on_killed(where: Vector3, enemy_id: String, _elite: String, _wave: int) -> void:
	if not active or not _enemies.has(enemy_id):
		return
	for boss: Dictionary in _bosses:
		if String(boss["id"]) == String(_enemies[enemy_id].get("phantom_of", enemy_id)):  # the boss or its echo
			boss["enemy"] = null
			boss["respawn_at"] = Time.get_ticks_msec() / 1000.0 + float(_cfg["boss_respawn_s"])  # (polish1 E4) its fall is told by the vanquished page
	if not bool(_enemies[enemy_id].get("boss", false)) and not _enemies[enemy_id].has("temper") and not _enemies[enemy_id].has("tribe"):
		var at: Vector3 = _world.local_of(where)
		_zone_kill(at.x, at.z)
	var splits: Dictionary = _enemies[enemy_id].get("splits", {})
	if not splits.is_empty():  # it bursts into smaller ones
		var local: Vector3 = _world.local_of(where)
		for i in int(splits["count"]):
			var a := TAU * float(i) / float(splits["count"]) + _rng.randf()
			_spawn(String(splits["into"]), local.x + cos(a) * 1.2, local.z + sin(a) * 1.2, _nearest(_bodies(), where))
	slain.emit(enemy_id, where)


# What one kill pays this player (every party member rolls their own drops).
func pay(enemy_id: String) -> void:
	var stats: Dictionary = _enemies.get(enemy_id, {})
	if stats.is_empty():
		return
	var skill := String(stats.get("skill", "magic"))
	if skill != "magic" and int(_world.skills.level(skill)) < int(stats["level"]):  # an animal above your Hunting: a little experience, nothing to take
		_world.gain_xp(skill, roundi(float(stats["xp"]) * 0.25))
		notice.emit("Needs %s %d to dress the %s." % [_world.skills.skill_name(skill), int(stats["level"]), String(stats["name"]).to_lower()])
		return
	_world.gain_xp(skill, int(stats["xp"]))
	var extra := 1 if skill != "magic" and _rng.randf() < float(_world.perk(skill, "double")) else 0
	for item: String in stats.get("drops", {}):
		if _rng.randf() < float(stats["drops"][item]):
			_world.give(item, 1 + extra)
	if bool(stats.get("boss", false)):  # (polish1 E4) relic, trophies, the vanquished page
		_world.boss_paid(enemy_id, stats)
