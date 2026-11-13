# Purpose: spawns enemy waves at the colosseum gates (rules in core/wave_state.gd) and owns the projectile pool and blood effects.
# Dependencies: core/wave_state.gd, core/data_store.gd, game/enemy.gd, game/projectile_pool.gd, game/blood_effects.gd.
extends Node3D

const WaveState = preload("res://core/wave_state.gd")
const DataStore = preload("res://core/data_store.gd")
const Enemy = preload("res://game/enemy.gd")
const ProjectilePool = preload("res://game/projectile_pool.gd")
const BloodEffects = preload("res://game/blood_effects.gd")
const DropRules = preload("res://core/drop_rules.gd")

signal killed(where: Vector3, enemy_id: String, elite: String, wave: int)  # an enemy died here (the session rolls loot)

var _waves: WaveState
var _enemy_stats: Dictionary
var _gates: Array[Vector3]
var _player: Node3D
var _pool := ProjectilePool.new()
var _blood := BloodEffects.new()
var _enemies: Array = []
var _alive := 0
var _next_gate := 0
var _boss: Enemy
var _waves_data: Dictionary
var _elements: Dictionary  # data/elements.json
var boss_handler: Callable  # online: called instead of spawning the boss locally (see game/net_boss.gd)
var sounds: Node  # the game's sound player (enemy attack sounds), set by game/game_session.gd
var _drops_cfg: Dictionary  # data/drops.json
var _rng := RandomNumberGenerator.new()
var _active := false  # waves wait until start() (the player enters the colosseum)
var last_killed: Node  # the enemy whose death `killed` is being emitted for (its metas say where it belonged)
var wave_stats := Callable()  # func(stats: Dictionary, wave: int) -> Dictionary: an arena enemy's numbers in that wave (core/colosseum_rules.gd; unset = as in the data)
var wave_list := Callable()  # func(waves: Array, count: int) -> Array: the waves of a run (core/colosseum_rules.gd `run_waves`; unset = the data's first `count`)
var run_fx := {}  # the run's effects, handed to every arena enemy (set by the session before start())
var _shared_out := false  # the shared boss of this run is in (a second "boss" of a wave is our own)


# Call before add_child.
func setup(player: Node3D, gates: Array[Vector3]) -> void:
	_player = player
	_gates = gates
	_enemy_stats = DataStore.load_json("res://data/enemies.json")["enemies"]
	_waves_data = DataStore.load_json("res://data/waves.json")
	_elements = DataStore.load_json("res://data/elements.json")
	_drops_cfg = DataStore.load_json("res://data/drops.json")
	_rng.randomize()
	_waves = WaveState.new(_waves_data)
	add_child(_pool)
	add_child(_blood)


# Begins a run of the first `waves` waves (0 = all); the first wave timer starts now.
func start(waves: int = 0) -> void:
	var run := _waves_data.duplicate()
	var count := waves if waves > 0 else (_waves_data["waves"] as Array).size()
	run["waves"] = wave_list.call(_waves_data["waves"], count) if wave_list.is_valid() else (_waves_data["waves"] as Array).slice(0, count)
	run["wave_delay"] = float(run_fx.get("wave_delay", _waves_data["wave_delay"]))
	_waves = WaveState.new(run)
	_shared_out = false
	_active = true


# More enemies for the wave being fought (a modifier's late pack). They come in like the rest of the wave.
func send_in(ids: Array[String]) -> void:
	_waves.add(ids)


# True once every wave has been beaten.
func is_cleared() -> bool:
	return _waves.cleared


# Back to the pre-start state with fresh waves (after the player leaves the arena).
func reset() -> void:
	_active = false
	_waves = WaveState.new(_waves_data)
	var keep: Array = []
	var shared := 0
	for e in _enemies:
		if e == _boss and boss_handler.is_valid():
			keep.append(e)  # the shared boss belongs to the whole party, not to our arena run
			shared += 1
		elif is_instance_valid(e) and (e as Node).has_meta("island"):
			keep.append(e)  # the island's rounds go on for whoever is there (game/island_rounds.gd)
		elif is_instance_valid(e):
			e.queue_free()
	_enemies = keep
	_alive = shared
	_boss = null


# Admin command /wave: this run goes on with wave `number`; the wave's enemies still alive are taken away.
func skip_to(number: int) -> void:
	for enemy: Node in _enemies.duplicate():
		if is_instance_valid(enemy) and not enemy.has_meta("placed"):
			despawn(enemy)
	_alive = 0
	_waves.skip_to(number)


# How many waves the data has, and the wave a kind of enemy first comes in (0 = never).
func waves_in_data() -> int:
	return (_waves_data["waves"] as Array).size()


func first_wave_of(id: String) -> int:
	var list: Array = _waves_data["waves"]
	for i in list.size():
		if (list[i] as Dictionary).has(id):
			return i + 1
	return 0


# An arena enemy's numbers in a wave.
func _in_wave(id: String, wave: int) -> Dictionary:
	var stats: Dictionary = _enemy_stats[id]
	return wave_stats.call(stats, wave) if wave_stats.is_valid() else stats


# Everything alive that this director holds: its own waves' enemies and those placed from outside (spawn_custom).
func enemy_count() -> int:
	return _enemies.size()


func enemy_list() -> Array:
	return _enemies


func projectile_count() -> int:
	return _pool.active_count()


# Boss health 0..1, or -1 when no boss is alive.
func boss_ratio() -> float:
	if is_instance_valid(_boss):
		return _boss.health.hp / _boss.health.max_hp
	return -1.0


func status_text() -> String:
	return _waves.status() if _active else ""


# The wave being fought and how many there are (0, 0 while the waves are not running).
func wave_number() -> int:
	return _waves.wave_number() if _active and not _waves.cleared else 0


func wave_count() -> int:
	return _waves.wave_count() if _active else 0


# Enemies left in this wave, -1 while the waves are not running.
func enemies_left() -> int:
	return _waves.left(_alive) if _active and not _waves.cleared else -1


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	var id := _waves.update(Time.get_ticks_msec() / 1000.0, _alive)
	if id != "":
		_spawn(id)


func _spawn(id: String) -> void:
	if id == "boss" and boss_handler.is_valid() and not _shared_out:  # only the clockwork bear is shared online; the wasteland bosses (and a twin of the bear) are each player's own
		_shared_out = true
		_alive += 1  # the shared boss counts as alive until it dies (or is found already dead)
		boss_handler.call(self)
		return
	var enemy := Enemy.new()
	var stats := _in_wave(id, _waves.wave_number())  # every wave is tougher than the one before
	var affix := DropRules.roll_elite(_drops_cfg, _rng, id, _waves.wave_number())
	if affix.is_empty() and run_fx.has("all_elite") and not id.begins_with("boss"):  # All Elite: a trait for everybody, without an elite's drop
		var traits: Array = _drops_cfg["elite"]["affixes"]
		affix = traits[_rng.randi_range(0, traits.size() - 1)]
		enemy.set_meta("forced_elite", true)
	if not affix.is_empty():
		stats = DropRules.apply_affix(stats, affix)
		enemy.elite = String(affix["name"])
	enemy.configure(id, stats, _player, _pool, _blood)
	enemy.set_run_fx(run_fx)
	enemy.sounds = sounds
	var element := _roll_element(id)
	if element != "":
		enemy.element = element
		var t: Array = _elements["elements"][element]["tint"]
		enemy.element_tint = Color(t[0], t[1], t[2])
	var gate := _gates[_next_gate % _gates.size()]
	_next_gate += 1
	enemy.position = gate + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	_enemies.append(enemy)
	_alive += 1
	if id.begins_with("boss"):  # its health shows as the bar at the top
		_boss = enemy


# Skeletons (not the boss) get an element with the configured chance, picked by weight. Returns "" for none.
func _roll_element(id: String) -> String:
	if id.begins_with("boss") or randf() > float(_elements["chance"]):
		return ""
	var total := 0.0
	for e in _elements["elements"]:
		total += float(_elements["elements"][e]["weight"])
	var pick := randf() * total
	for e in _elements["elements"]:
		pick -= float(_elements["elements"][e]["weight"])
		if pick <= 0.0:
			return e
	return ""


func _on_enemy_died(enemy: Node) -> void:
	if not enemy.has_meta("placed"):
		_alive = maxi(_alive - 1, 0)
	_enemies.erase(enemy)
	last_killed = enemy
	var wave := int(enemy.get_meta("tier")) if enemy.has_meta("tier") else _waves.wave_number()  # fantasy creatures carry their own level
	killed.emit((enemy as Node3D).global_position, String(enemy.enemy_id), String(enemy.elite), wave)


# Spawns one enemy with ready-made stats at a world position (game/fantasy_spawner.gd, /spawn). Returns it.
func spawn_custom(id: String, stats: Dictionary, pos: Vector3, affix: Dictionary = {}) -> Enemy:
	var enemy := Enemy.new()
	if not affix.is_empty():
		stats = DropRules.apply_affix(stats, affix)
		enemy.elite = String(affix["name"])
	enemy.configure(id, stats, _player, _pool, _blood)
	enemy.sounds = sounds
	if not id.begins_with("boss"):
		var element := _roll_element(id)
		if element != "":
			enemy.element = element
			var t: Array = _elements["elements"][element]["tint"]
			enemy.element_tint = Color(t[0], t[1], t[2])
	enemy.position = pos
	enemy.set_meta("placed", true)  # not one of the arena's waves: they neither wait for it nor count it
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	_enemies.append(enemy)
	if id.begins_with("boss"):
		_boss = enemy
	return enemy


# Removes an enemy without it counting as a kill (it wandered too far away).
func despawn(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	forget(enemy)
	enemy.queue_free()


# Takes an enemy off the list without removing its body and without a kill (it falls on its own: game/enemy.gd fall).
func forget(enemy: Node) -> void:
	_enemies.erase(enemy)
	if not enemy.has_meta("placed"):
		_alive = maxi(_alive - 1, 0)
	if enemy == _boss:
		_boss = null


# --- shared boss (online, see game/net_boss.gd) ---

func boss_spawn_position() -> Vector3:
	return _gates[0] + Vector3(0.0, 0.0, 0.0)


# Builds the one shared boss: the real one on the host, a puppet elsewhere. It is not part of our waves until attach_boss().
func create_shared_boss(as_puppet: bool, pos: Vector3) -> Enemy:
	var boss := Enemy.new()
	boss.configure("boss", _in_wave("boss", first_wave_of("boss")), _player, _pool, _blood)
	boss.sounds = sounds
	boss.puppet = as_puppet
	boss.position = pos
	boss.net_pos = pos
	add_child(boss)
	return boss


# Our boss wave joins the shared boss's fight.
func attach_boss(boss: Enemy) -> void:
	_boss = boss
	_enemies.append(boss)
	if not boss.died.is_connected(_on_enemy_died):
		boss.died.connect(_on_enemy_died)


# The shared boss was killed moments ago: our boss wave counts it as beaten.
func boss_already_dead() -> void:
	_alive = maxi(_alive - 1, 0)
