# Purpose: pure ammo, fire-rate and reload rules for one weapon. No nodes, no rendering.
# Dependencies: core/ammo_pools.gd (optional `pool`: a reload takes its rounds from there). Stats come from
# data/weapons.json (see tools/validate_data.gd).
extends RefCounted

var weapon_id: String
var damage: float
var spread: float
var mag_size: int
var ammo: int
var pellets := 1  # hitscan rays per shot (shotguns)
var projectile := {}  # non-empty for rocket/grenade launchers (see game/explosives.gd)
var pool: RefCounted  # core/ammo_pools.gd: spare rounds for this weapon's body (null = reloads cost nothing)

var _fire_interval: float
var _reload_time: float
var _next_fire_time := 0.0
var _reload_done_time := -1.0


func _init(id: String, stats: Dictionary) -> void:
	weapon_id = id
	damage = float(stats["damage"])
	spread = float(stats["spread"])
	mag_size = int(stats["mag_size"])
	pellets = int(stats.get("pellets", 1))
	projectile = stats.get("projectile", {})
	ammo = mag_size
	_fire_interval = 1.0 / float(stats["fire_rate"])
	_reload_time = float(stats["reload_time"])


func is_reloading() -> bool:
	return _reload_done_time >= 0.0


# 0 when not reloading, otherwise how far through the reload we are (0..1).
func reload_fraction(now: float) -> float:
	if not is_reloading():
		return 0.0
	return clampf(1.0 - (_reload_done_time - now) / _reload_time, 0.0, 1.0)


func update(now: float) -> void:
	if is_reloading() and now >= _reload_done_time:
		ammo += (mag_size - ammo) if pool == null else int(pool.take(weapon_id, mag_size - ammo))
		_reload_done_time = -1.0


# Rounds left to reload from (a large number when reloads cost nothing).
func spare() -> int:
	return 999999 if pool == null else int(pool.left(weapon_id))


# Returns true if a shot was fired (ammo spent, cooldown started).
func try_fire(now: float) -> bool:
	update(now)
	if is_reloading() or ammo <= 0 or now < _next_fire_time:
		return false
	ammo -= 1
	_next_fire_time = now + _fire_interval
	return true


# Putting the gun away stops a reload: the magazine stays as it was.
func cancel_reload() -> void:
	_reload_done_time = -1.0


func start_reload(now: float) -> void:
	if is_reloading() or ammo >= mag_size or spare() <= 0:
		return
	_reload_done_time = now + _reload_time
