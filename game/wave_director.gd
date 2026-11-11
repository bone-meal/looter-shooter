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
var _drops_cfg: Dictionary  # data/drops.json
var _rng := RandomNumberGenerator.new()
var _active := false  # waves wait until start() (the player enters the colosseum)


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


# Begins the waves; the first wave timer starts now.
func start() -> void:
	_active = true


# True once every wave has been beaten.
func is_cleared() -> bool:
	return _waves.cleared


# Back to the pre-start state with fresh waves (after the player leaves the arena).
func reset() -> void:
	_active = false
	_waves = WaveState.new(_waves_data)
	var keep: Array = []
	for e in _enemies:
		if e == _boss and boss_handler.is_valid():
			keep.append(e)  # the shared boss belongs to the whole party, not to our arena run
		elif is_instance_valid(e):
			e.queue_free()
	_enemies = keep
	_alive = keep.size()
	_boss = null


# Seconds after the arena is cleared before it starts over at round 1.
func reset_delay() -> float:
	return float(_waves_data["reset_after_clear_seconds"])


func enemy_count() -> int:
	return _alive


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
	return _waves.status(_alive) if _active else ""


func _physics_process(_delta: float) -> void:
	if not _active:
		return
	var id := _waves.update(Time.get_ticks_msec() / 1000.0, _alive)
	if id != "":
		_spawn(id)


func _spawn(id: String) -> void:
	if id == "boss" and boss_handler.is_valid():
		_alive += 1  # the shared boss counts as alive until it dies (or is found already dead)
		boss_handler.call(self)
		return
	var enemy := Enemy.new()
	var stats: Dictionary = _enemy_stats[id]
	var affix := DropRules.roll_elite(_drops_cfg, _rng, id, _waves.wave_number())
	if not affix.is_empty():
		stats = DropRules.apply_affix(stats, affix)
		enemy.elite = String(affix["name"])
	enemy.configure(id, stats, _player, _pool, _blood)
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
	if id == "boss":
		_boss = enemy


# Skeletons (not the boss) get an element with the configured chance, picked by weight. Returns "" for none.
func _roll_element(id: String) -> String:
	if id == "boss" or randf() > float(_elements["chance"]):
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
	_alive = maxi(_alive - 1, 0)
	_enemies.erase(enemy)
	var wave := int(enemy.get_meta("tier")) if enemy.has_meta("tier") else _waves.wave_number()  # Omaha enemies carry their district tier
	killed.emit((enemy as Node3D).global_position, String(enemy.enemy_id), String(enemy.elite), wave)


# Omaha: spawns one enemy with ready-made stats at a world position (see game/omaha_spawner.gd). Returns it.
func spawn_custom(id: String, stats: Dictionary, pos: Vector3, affix: Dictionary = {}) -> Enemy:
	var enemy := Enemy.new()
	if not affix.is_empty():
		stats = DropRules.apply_affix(stats, affix)
		enemy.elite = String(affix["name"])
	enemy.configure(id, stats, _player, _pool, _blood)
	if not id.begins_with("boss"):
		var element := _roll_element(id)
		if element != "":
			enemy.element = element
			var t: Array = _elements["elements"][element]["tint"]
			enemy.element_tint = Color(t[0], t[1], t[2])
	enemy.position = pos
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	_enemies.append(enemy)
	_alive += 1
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
	_alive = maxi(_alive - 1, 0)
	if enemy == _boss:
		_boss = null


# --- shared boss (online, see game/net_boss.gd) ---

func boss_spawn_position() -> Vector3:
	return _gates[0] + Vector3(0.0, 0.0, 0.0)


# Builds the one shared boss: the real one on the host, a puppet elsewhere. It is not part of our waves until attach_boss().
func create_shared_boss(as_puppet: bool, pos: Vector3) -> Enemy:
	var boss := Enemy.new()
	boss.configure("boss", _enemy_stats["boss"], _player, _pool, _blood)
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
