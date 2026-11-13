# Purpose: runs the island's rounds on the machine that owns them (the only one when playing alone, else the host):
# sends the enemies core/round_rules.gd asks for out of the sea, keeps each one after the nearest player on the
# island, and puts them away with the clock held still while nobody is there. It decides nothing about points, loot
# or the HUD: the session listens to its signals.
# Dependencies: core/round_rules.gd, core/data_store.gd, core/archipelago.gd (`land`: where the shores are), game/island.gd (the islands' place in the world), game/wave_director.gd
# (`director`: builds the enemies, so bars, blasts and skills see them like any other). Data: data/island_rounds.json,
# data/enemies.json (the bosses).
extends Node

const RoundRules = preload("res://core/round_rules.gd")
const DataStore = preload("res://core/data_store.gd")
const Island = preload("res://game/island.gd")

signal spawned(enemy: Node3D)  # online: the host tells the others (game/net_rounds.gd)
signal round_started(number: int, kind: String)
signal round_ended(number: int, kind: String)

const RETARGET := 0.5  # seconds between two looks at who is nearest
const NEAR_SHORE := 0.6  # a swimmer comes up within this many radians of its prey's bearing
const LOST_BELOW := -14.0  # deeper than any sea bed: it fell out of the world
const FAR_LOOKS := 2  # looks in a row an enemy must be too far from everybody before it is put back into the sea

var rules: RoundRules
var director: Node3D
var bodies := Callable()  # func() -> Array of the players' bodies standing on the island (ours and, on the host, the others')
var land: RefCounted  # core/archipelago.gd: where the islands are and where an enemy can come out of the sea
var shelters: Node3D  # game/shelters.gd: where an enemy goes when its prey sits in a hut (null = there are none)
var one_blow := Callable()  # func() -> bool, handed to every enemy sent in (game/enemy.gd `one_blow`)
var active := true  # false on a machine that only watches (a client): the host runs the rounds

var _cfg: Dictionary
var _bosses: Dictionary  # data/enemies.json
var _rng := RandomNumberGenerator.new()
var _alive: Array = []  # this round's enemies, alive
var _retarget := 0.0
var _empty_since := -1.0  # when the last player left the island (-1 = somebody is there)


func _init() -> void:
	_cfg = DataStore.load_json("res://data/island_rounds.json")
	_bosses = DataStore.load_json("res://data/enemies.json")["enemies"]
	_rng.randomize()
	rules = RoundRules.new(_cfg, _rng)
	rules.round_started.connect(func(number: int, kind: String) -> void: round_started.emit(number, kind))
	rules.round_ended.connect(func(number: int, kind: String) -> void: round_ended.emit(number, kind))


func config() -> Dictionary:
	return _cfg


func alive() -> int:
	return _alive.size()


# An enemy's stats as it comes ashore in round `number` ({} for an id this game does not know): the host's enemies and
# the puppets other machines show are built from the same numbers.
func stats_of(id: String, number: int) -> Dictionary:
	var own: Dictionary = _cfg["enemies"]
	if own.has(id):
		return rules.stats_for(own[id], number, false)
	if _bosses.has(id) and (_cfg["boss"]["order"] as Array).has(id):
		return rules.stats_for(_bosses[id], number, true)
	return {}


# Enemies of the round still to beat (0 between rounds).
func left() -> int:
	return rules.left(_alive.size())


# Game over: everything alive is taken away and the rounds wait for the next run (which starts by itself as soon as
# somebody stands on the island).
func stop() -> void:
	for enemy: Variant in _alive:
		if is_instance_valid(enemy):
			director.call("despawn", enemy)
	_alive.clear()
	rules.stop()


# For testing (/round n): clears the island and starts round `number` in a few seconds.
func skip_to(number: int) -> void:
	for enemy: Variant in _alive:
		if is_instance_valid(enemy):
			director.call("despawn", enemy)
	_alive.clear()
	rules.skip_to(number, Time.get_ticks_msec() / 1000.0)


func _physics_process(delta: float) -> void:
	if not active or director == null or not bodies.is_valid():
		return
	var now := Time.get_ticks_msec() / 1000.0
	var here: Array = bodies.call()
	if here.is_empty():
		if _empty_since < 0.0:
			_empty_since = now
			_put_away()
		return
	if _empty_since >= 0.0:
		rules.delay(now - _empty_since)  # the clock stood still while nobody was here
		_empty_since = -1.0
	if not rules.running():
		rules.start(now)
	if not rules.fighting():
		rules.players = here.size()  # the next round is sized for whoever is here when it starts
	var id := rules.update(now, _alive.size())
	if id != "":
		_send_in(id, here)
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = RETARGET
		if shelters != null:
			shelters.call("look_begins")
		for enemy: Variant in _alive.duplicate():
			if not is_instance_valid(enemy):
				continue
			var prey := _nearest(here, (enemy as Node3D).global_position)
			(enemy as Node3D).call("set_target", shelters.call("guide", enemy, prey, now) if shelters != null else prey)
			# left behind on another island: back into the sea, to come out again where the players are (never a boss:
			# it would come back healed)
			var from: Vector3 = (enemy as Node3D).global_position - Island.CENTER
			var to := prey.global_position - Island.CENTER
			if from.y < LOST_BELOW or not bool(land.within(from.x, from.z)):  # pushed through the ground or off the sea bed: it comes out of the sea again (as it is)
				var again: Vector3 = land.sea_spot(int(land.island_near(to.x, to.z)), _rng)
				if again.is_finite():
					(enemy as Node3D).global_position = Island.CENTER + again + Vector3(0, 0.2, 0)
					(enemy as CharacterBody3D).velocity = Vector3.ZERO
				continue
			var lost := int((enemy as Node).get_meta("far", 0)) + 1 if bool(land.left_behind(from.x, from.z, to.x, to.z)) else 0
			(enemy as Node).set_meta("far", lost)
			if lost >= FAR_LOOKS and not String((enemy as Node).get("enemy_id")).begins_with("boss"):
				_alive.erase(enemy)
				rules.put_back([String((enemy as Node).get("enemy_id"))])
				director.call("despawn", enemy)


# Nobody is on the island: the living go back into the sea and come out again when somebody returns.
func _put_away() -> void:
	var ids: Array = []
	for enemy: Variant in _alive:
		if is_instance_valid(enemy):
			ids.append(String((enemy as Node).get("enemy_id")))
			director.call("despawn", enemy)
	_alive.clear()
	rules.put_back(ids)


func _send_in(id: String, here: Array) -> void:
	var base: Dictionary = _cfg["enemies"][id] if (_cfg["enemies"] as Dictionary).has(id) else _bosses[id]
	var stats := stats_of(id, rules.number)
	var prey: Node3D = here[_rng.randi() % here.size()]
	var at := prey.global_position - Island.CENTER
	var isle: int = land.island_near(at.x, at.z)
	var to_prey: Vector2 = Vector2(at.x, at.z) - (land.islands[isle]["at"] as Vector2)
	var bearing := atan2(to_prey.y, to_prey.x) if to_prey.length() > 2.0 else NAN  # out of the sea on the prey's side of the island
	var swims := String(base.get("comes", "")) == "nearest_shore"  # a swimmer: up out of the water right where its prey stands
	var spot: Vector3 = land.sea_spot(isle, _rng, bearing, NEAR_SHORE if swims else float(land.arc_of(isle)))
	if not spot.is_finite():
		rules.put_back([id])  # no room in the sea just now: it comes a moment later
		return
	var enemy: Node3D = director.call("spawn_custom", id, stats, Island.CENTER + spot + Vector3(0, 0.2, 0))
	enemy.set_meta("island", true)
	enemy.set_meta("tier", rules.number)
	enemy.set("one_blow", one_blow)
	enemy.call("set_target", prey)
	enemy.connect("died", _on_died)
	_alive.append(enemy)
	spawned.emit(enemy)


# Sends one enemy in at a given world spot, as strong as in round `number` (the main quest's boss). Like any
# enemy of the round it is host-run and shown to the others; it carries meta "quest_boss". Returns it.
func send_at(id: String, at: Vector3, number: int) -> Node3D:
	var enemy: Node3D = director.call("spawn_custom", id, stats_of(id, number), at)
	enemy.set_meta("island", true)
	enemy.set_meta("tier", number)
	enemy.set_meta("quest_boss", true)
	enemy.set("one_blow", one_blow)
	var here: Array = bodies.call() if bodies.is_valid() else []
	if not here.is_empty():
		enemy.call("set_target", _nearest(here, at))
	enemy.connect("died", _on_died)
	_alive.append(enemy)
	spawned.emit(enemy)
	return enemy


# The nuke: everything of the round that is ashore dies; a boss loses `boss_share` of its full health instead.
# Returns how many were hit.
func blast(boss_share: float) -> int:
	var hit := 0
	for enemy: Variant in _alive.duplicate():
		if not is_instance_valid(enemy):
			continue
		var all := float(enemy.health.max_hp)
		enemy.call("on_hit", all * boss_share if String(enemy.get("enemy_id")).begins_with("boss") else all * 100.0)
		hit += 1
	return hit


func _on_died(enemy: Node) -> void:
	_alive.erase(enemy)


func _nearest(here: Array, from: Vector3) -> Node3D:
	var best: Node3D = here[0]
	var best_d := INF
	for body: Node3D in here:
		var d := from.distance_squared_to(body.global_position)
		if d < best_d:
			best_d = d
			best = body
	return best
