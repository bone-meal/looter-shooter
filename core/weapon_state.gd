# Purpose: pure ammo, fire-rate and reload rules for one weapon. No nodes, no rendering. Optional rules from the
# weapon's data: reload_each (one round per reload_time, a shot interrupts it: lever-action), fan.tap_rate (a fresh
# trigger press may fire at this faster rate: revolver), overheat {per_shot, cool_per_second} (heat 0..1; at 1 it
# will not fire until cooled to 0: flamethrower).
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
const COOL_DELAY := 0.35  # seconds without a shot before an overheating gun starts to cool

var rate_mult := 1.0  # the fire rate is multiplied by this (gun skill Bullet Storm, core/skill_self.gd)
var reload_each := false
var heat := 0.0  # 0..1 for guns that overheat
var overheated := false
var fanned_shot := false  # the last shot was a fanned tap (faster than the held rate): the player widens its spread

var _tap_interval := 0.0  # 0 = no fanning
var _heat_per_shot := 0.0
var _cool_per_second := 0.0
var last_shot := -10.0  # when the last shot left (the gun's moving parts follow it: game/gun_actions.gd)
var _heat_at := 0.0

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
	reload_each = bool(stats.get("reload_each", false))
	var fan: Dictionary = stats.get("fan", {})
	_tap_interval = 1.0 / float(fan["tap_rate"]) if fan.has("tap_rate") else 0.0
	var hot: Dictionary = stats.get("overheat", {})
	_heat_per_shot = float(hot.get("per_shot", 0.0))
	_cool_per_second = float(hot.get("cool_per_second", 0.0))


func is_reloading() -> bool:
	return _reload_done_time >= 0.0


# 0 when not reloading, otherwise how far through the reload we are (0..1).
func reload_fraction(now: float) -> float:
	if not is_reloading():
		return 0.0
	return clampf(1.0 - (_reload_done_time - now) / _reload_time, 0.0, 1.0)


func update(now: float) -> void:
	if _heat_per_shot > 0.0:  # cooling since the last look, once the trigger has rested a moment
		if now - last_shot > COOL_DELAY or overheated:
			heat = maxf(heat - _cool_per_second * maxf(now - maxf(_heat_at, last_shot + (0.0 if overheated else COOL_DELAY)), 0.0), 0.0)
		_heat_at = now
		if heat <= 0.0:
			overheated = false
	if is_reloading() and now >= _reload_done_time:
		if reload_each:  # one round in, then the next if there is room and spare
			ammo += 1 if pool == null else int(pool.take(weapon_id, 1))
			_reload_done_time = now + _reload_time if ammo < mag_size and spare() > 0 else -1.0
			return
		ammo += (mag_size - ammo) if pool == null else int(pool.take(weapon_id, mag_size - ammo))
		_reload_done_time = -1.0


# Rounds left to reload from (a large number when reloads cost nothing).
func spare() -> int:
	return 999999 if pool == null else int(pool.left(weapon_id))


# Returns true if a shot was fired (ammo spent, cooldown started). `tapped` = the trigger was pressed just now (a gun
# that fans may then fire sooner than its held rate).
func try_fire(now: float, tapped: bool = false) -> bool:
	update(now)
	if is_reloading() and reload_each and ammo > 0:
		_reload_done_time = -1.0  # a shot interrupts a round-by-round reload
	var ready_at := _next_fire_time
	if tapped and _tap_interval > 0.0:
		ready_at = minf(ready_at, last_shot + _tap_interval / maxf(rate_mult, 0.1))
	if is_reloading() or ammo <= 0 or now < ready_at or overheated:
		return false
	fanned_shot = now < _next_fire_time  # only a tap gets here before the held rate allows
	ammo -= 1
	_next_fire_time = now + _fire_interval / maxf(rate_mult, 0.1)
	last_shot = now
	if _heat_per_shot > 0.0:
		heat = minf(heat + _heat_per_shot, 1.0)
		overheated = heat >= 1.0
	return true


# Fills the magazine at once from the spare rounds (gun skill Full Clip). Returns the rounds put in.
func refill() -> int:
	var need := mag_size - ammo
	var got := need if pool == null else int(pool.take(weapon_id, need))
	ammo += got
	_reload_done_time = -1.0
	return got


# Putting the gun away stops a reload: the magazine stays as it was.
func cancel_reload() -> void:
	_reload_done_time = -1.0


func start_reload(now: float) -> void:
	if is_reloading() or ammo >= mag_size or spare() <= 0:
		return
	_reload_done_time = now + _reload_time
