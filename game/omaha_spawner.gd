# Purpose: fills the Omaha wasteland with enemies: district mixes and danger tiers, groups that appear near the player and fade away
#   far behind, and five boss lairs. All numbers are data (data/omaha/districts.json, enemies.json).
# Dependencies: core/omaha_geo.gd, core/drop_rules.gd, core/data_store.gd, game/wave_director.gd (spawn_custom/despawn), game/omaha_world.gd (to_world, blocked).
extends Node

const DataStore = preload("res://core/data_store.gd")
const OmahaGeo = preload("res://core/omaha_geo.gd")
const DropRules = preload("res://core/drop_rules.gd")

signal notice(text: String)  # district entered, boss nearby / defeated (the session shows it)

var active := false
var current_name := ""
var current_tier := 1

var _director: Node3D
var _player: Node3D
var _world: Node3D
var _drops_cfg: Dictionary
var _enemies: Dictionary
var _spawn_cfg: Dictionary
var _hp_per_tier := 0.25
var _dmg_per_tier := 0.15
var _districts: Array = []
var _default: Dictionary = {}
var _bosses: Array = []  # {"def", "id", "name", "pos": Vector2, "enemy", "respawn_at"}
var _rng := RandomNumberGenerator.new()
var _timer := 0.0
var _acc := 0.0
var _district_id := ""


func setup(director: Node3D, player: Node3D, world: Node3D, drops_cfg: Dictionary) -> void:
	_director = director
	_player = player
	_world = world
	_drops_cfg = drops_cfg
	_rng.randomize()
	var e := DataStore.load_json("res://data/omaha/enemies.json")
	_enemies = e["enemies"]
	_spawn_cfg = e["spawn"]
	_hp_per_tier = float(e["tier_hp_per_tier"])
	_dmg_per_tier = float(e["tier_damage_per_tier"])
	var d := DataStore.load_json("res://data/omaha/districts.json")
	var scale := float(world.map["scale"])
	var olat := float(world.map["origin_lat"])
	var olon := float(world.map["origin_lon"])
	_default = d["default"]
	for def: Dictionary in d["districts"]:
		var entry := def.duplicate(true)
		entry["pos"] = OmahaGeo.to_xz(float(def["lat"]), float(def["lon"]), olat, olon, scale)
		entry["radius"] = float(def["radius_m"]) / scale
		_districts.append(entry)
		if def.has("boss"):
			var b: Dictionary = def["boss"]
			_bosses.append({"id": b["id"], "name": b["name"], "pos": OmahaGeo.to_xz(float(b["lat"]), float(b["lon"]), olat, olon, scale), "tier": int(def["tier"]), "enemy": null, "respawn_at": 0.0})
	_director.killed.connect(_on_killed)


func start() -> void:
	active = true
	_district_id = ""
	for b in _bosses:
		b["enemy"] = null
		b["respawn_at"] = 0.0


func stop() -> void:
	active = false


func district_at_player() -> Dictionary:
	var d := OmahaGeo.district_at(_world.to_map(_player.global_position), _districts)
	return d if not d.is_empty() else _default


func _process(delta: float) -> void:
	if not active:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var here := district_at_player()
	current_name = String(here.get("name", "The Outskirts"))
	current_tier = int(here.get("tier", 2))
	if String(here["id"]) != _district_id:
		_district_id = String(here["id"])
		notice.emit("%s  (danger %d)" % [current_name, current_tier] if not here.get("safe", false) else "%s  (safe)" % current_name)
	_despawn_far()
	_boss_tick()
	if bool(here.get("safe", false)):
		return
	_acc += float(_spawn_cfg["per_second"]) * 0.5
	var cap := int(_spawn_cfg["max_alive"])
	while _acc >= 1.0:
		_acc -= 1.0
		if _count() < cap:
			_spawn_group()


func _count() -> int:
	var n := 0
	for e in _director.enemy_list():
		if is_instance_valid(e) and e.has_meta("omaha") and not String(e.enemy_id).begins_with("boss_"):
			n += 1
	return n


func _despawn_far() -> void:
	var far := float(_spawn_cfg["despawn_dist"])
	for e in _director.enemy_list().duplicate():
		if not is_instance_valid(e) or not e.has_meta("omaha") or String(e.enemy_id).begins_with("boss_"):
			continue
		if (e as Node3D).global_position.distance_to(_player.global_position) > far:
			_director.despawn(e)


func _spawn_group() -> void:
	var center := Vector2.ZERO
	var ok := false
	var pm: Vector2 = _world.to_map(_player.global_position)
	for _try in 8:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(float(_spawn_cfg["min_dist"]), float(_spawn_cfg["max_dist"]))
		center = pm + Vector2(cos(ang), sin(ang)) * dist
		if not _world.blocked(center, 2.0):
			ok = true
			break
	if not ok:
		return
	var district := OmahaGeo.district_at(center, _districts)
	if district.is_empty():
		district = _default
	if bool(district.get("safe", false)):
		return
	var mix: Dictionary = district["mix"]
	var tier := int(district["tier"])
	var n := _rng.randi_range(1, int(_spawn_cfg["group_max"]))
	for i in n:
		var id := _pick(mix)
		if id == "":
			return
		var at := center + Vector2(_rng.randf_range(-3.0, 3.0), _rng.randf_range(-3.0, 3.0))
		if _world.blocked(at, 1.2):
			continue
		_spawn(id, at, tier, true)


func _pick(mix: Dictionary) -> String:
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	var r := _rng.randf() * total
	for k in mix:
		r -= float(mix[k])
		if r <= 0.0:
			return String(k)
	return ""


func _spawn(id: String, xz: Vector2, tier: int, may_be_elite: bool) -> Node3D:
	var stats: Dictionary = (_enemies[id] as Dictionary).duplicate(true)
	stats["max_hp"] = float(stats["max_hp"]) * (1.0 + _hp_per_tier * float(tier - 1))
	stats["damage"] = float(stats["damage"]) * (1.0 + _dmg_per_tier * float(tier - 1))
	var affix: Dictionary = {}
	if may_be_elite:
		affix = DropRules.roll_elite(_drops_cfg, _rng, id, tier)
	var e: Node3D = _director.spawn_custom(id, stats, _world.to_world(xz) + Vector3(0.0, 0.2, 0.0), affix)
	e.set_meta("omaha", true)
	e.set_meta("tier", tier)
	return e


# ---------- bosses ----------

func _boss_tick() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var trigger := float(_spawn_cfg["boss_trigger_m"])
	var leash := float(_spawn_cfg["boss_leash_m"])
	var pm: Vector2 = _world.to_map(_player.global_position)
	for b in _bosses:
		var alive: bool = is_instance_valid(b["enemy"])
		var d: float = pm.distance_to(b["pos"])
		if alive and d > leash:
			_director.despawn(b["enemy"])  # it goes back to sleep while nobody is near
			b["enemy"] = null
			alive = false
		if not alive and now >= float(b["respawn_at"]) and d < trigger:
			var spot: Vector2 = _free_spot(b["pos"])
			b["enemy"] = _spawn(String(b["id"]), spot, int(b["tier"]), false)
			notice.emit("BOSS NEARBY: %s" % String(b["name"]))


func _free_spot(xz: Vector2) -> Vector2:
	for r in [0.0, 6.0, 12.0, 20.0, 30.0]:
		for k in 8:
			var p: Vector2 = xz + Vector2.RIGHT.rotated(float(k) * TAU / 8.0) * r
			if not _world.blocked(p, 3.0):
				return p
	return xz


func _on_killed(_where: Vector3, enemy_id: String, _elite: String, _wave: int) -> void:
	if not enemy_id.begins_with("boss_"):
		return
	for b in _bosses:
		if b["id"] == enemy_id:
			b["enemy"] = null
			b["respawn_at"] = Time.get_ticks_msec() / 1000.0 + float(_spawn_cfg["boss_respawn_s"])
			notice.emit("%s DEFEATED" % String(b["name"]).to_upper())
