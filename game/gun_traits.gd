# Purpose: what the held gun's TRAITS do (locked 2026-11-14, diary/DECISIONS_SEA.md; data/gun_traits.json): the big
# build-defining effects above the small buffs, and the pony-only traits of the pony families (data/pony_families.json). The player calls these hooks from its shot, hit, kill, damage and
# swap code; `traits` is the held gun's {id: value} (core/gun_stats.gd final_stats "traits").
# Dependencies: the player (game/player.gd: weapon, health, skills, explosives, allies_close).
extends RefCounted

const OVERCHARGE_EVERY := 5
const RICOCHET_RANGE := 10.0
const LAST_STAND_AT := 0.25
const LAST_STAND_REST := 30.0
const EXECUTE_AT := 0.25
const MOMENTUM_STEP := 2.0
const STORM_EVERY := 4  # Storm Hoof: every 4th hit
const STATIC_RANGE := 6.0
const STATIC_SECONDS := 4.0
const MOON_RANGE := 20.0
const ECLIPSE_MAX := 3
const TIDE_EVERY := 8  # Tidal Surge: every 8th shot
const TIDE_RADIUS := 5.0
const UNDERTOW_PULL := 6.0
const GLITTER_RADIUS := 2.5
const PRISM_SECONDS := 2.0
const PRISM_MAX := 5
const COMET_RANGE := 15.0
const GRAVITY_PULL := 5.0

var player: Node
var _shots := 0
var _streak := 0
var _swap_shots := 0
var _stand_until := 0.0
var _stand_ready_at := 0.0
var _charged := false  # this shot is an Overcharge shot
var _hits := 0  # Storm Hoof counts hits
var _eclipse := 0  # Eclipse: kills stored for the next shot
var _eclipse_spend := false  # this shot carries the stored kills
var _tide := false  # this shot is a Tidal Surge shot
var _prism := {}  # Prism Mane: enemy -> engine time it was last hit


func on_swapped(traits: Dictionary, mag: int) -> void:
	_swap_shots = mag if traits.has("quick_change") else 0
	_streak = 0


# A trigger pull: counts toward Overcharge; true = Last Stand is on and the round comes back.
func on_shot(traits: Dictionary, now: float) -> bool:
	_shots += 1
	_charged = traits.has("overcharge") and _shots % OVERCHARGE_EVERY == 0
	_tide = traits.has("tidal_surge") and _shots % TIDE_EVERY == 0
	_eclipse_spend = traits.has("eclipse") and _eclipse > 0
	return traits.has("last_stand") and now < _stand_until


# One pellet's damage multiplier from the traits.
func damage_mult(traits: Dictionary, target: Node) -> float:
	if traits.is_empty():
		return 1.0
	var mult := 1.0
	if _charged:
		mult *= 1.0 + float(traits["overcharge"]) / 100.0
	if traits.has("pack_hunter"):
		mult *= 1.0 + float(traits["pack_hunter"]) * float(int(player.get("allies_close"))) / 100.0
	if _swap_shots > 0:
		mult *= 1.0 + float(traits["quick_change"]) / 100.0
	if traits.has("executioner") and target.get("health") != null and float(target.health.hp) < float(target.health.max_hp) * EXECUTE_AT:
		mult *= 1.0 + float(traits["executioner"]) / 100.0
	if traits.has("momentum"):
		mult *= 1.0 + minf(float(_streak) * MOMENTUM_STEP, float(traits["momentum"])) / 100.0
	if traits.has("twin_shot") and randf() * 100.0 < float(traits["twin_shot"]):
		mult *= 2.0
	if traits.has("moonlit") and (target as Node3D).global_position.distance_to((player as Node3D).global_position) > MOON_RANGE:
		mult *= 1.0 + float(traits["moonlit"]) / 100.0
	if _eclipse_spend:
		mult *= 1.0 + float(traits["eclipse"]) * float(_eclipse) / 100.0
	if traits.has("prism_mane"):
		mult *= 1.0 + float(traits["prism_mane"]) * float(mini(_prism_count(), PRISM_MAX)) / 100.0
	return mult


# After the shot's pellets: Momentum keeps counting or starts over, Quick Change spends one round.
func after_shot(hit_something: bool) -> void:
	_streak = _streak + 1 if hit_something else 0
	_swap_shots = maxi(_swap_shots - 1, 0)
	if _eclipse_spend:
		_eclipse = 0  # Eclipse: the stored kills went into this shot
		_eclipse_spend = false


func on_hit(traits: Dictionary, target: Node, point: Vector3, dealt: float) -> void:
	var blasts: Node = player.get("explosives")
	if traits.has("ricochet"):
		var other: Node = _nearest_other(target, point)
		if other != null:
			other.on_hit(dealt * float(traits["ricochet"]) / 100.0, other.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	if traits.has("tempest") and randf() * 100.0 < float(traits["tempest"]):
		if target.has_method("apply_burn"):
			target.apply_burn(dealt * 0.4, 3.0)
		if blasts != null:
			blasts.blast(point, 4.0, dealt * 0.4, false)
	if _charged and blasts != null:
		blasts.blast(point, 3.0, dealt * 0.5)
	_pony_hit(traits, target, point, dealt, blasts)


# The pony-only traits that act on a hit (data/pony_families.json).
func _pony_hit(traits: Dictionary, target: Node, point: Vector3, dealt: float, blasts: Node) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if traits.has("storm_hoof"):
		_hits += 1
		if _hits % STORM_EVERY == 0:
			target.on_hit(dealt * float(traits["storm_hoof"]) / 100.0, point, Vector3.UP)
			if blasts != null:
				blasts.show_flash(point + Vector3(0, 0.5, 0), 1.2)
	if traits.has("cinder_trail") and target.has_method("apply_burn"):
		target.apply_burn(dealt * float(traits["cinder_trail"]) / 100.0, 3.0)
	if traits.has("undertow"):
		var back: Vector3 = ((player as Node3D).global_position - (target as Node3D).global_position) * Vector3(1, 0, 1)
		if back.length() > 2.0 and target.has_method("push"):
			target.push(back.normalized() * UNDERTOW_PULL)
		if target.has_method("apply_slow"):
			target.apply_slow(float(traits["undertow"]) / 100.0, 2.0)
	if _tide and blasts != null:
		blasts.blast(point, TIDE_RADIUS, dealt * float(traits["tidal_surge"]) / 100.0)
		_tide = false  # one wave per shot, however many pellets land
	if traits.has("glitter_bomb") and blasts != null and randf() * 100.0 < float(traits["glitter_bomb"]):
		for k in 3:
			var angle := TAU * float(k) / 3.0 + now
			blasts.blast(point + Vector3(cos(angle), 0.0, sin(angle)) * GLITTER_RADIUS, GLITTER_RADIUS, dealt * 0.5)
	if traits.has("prism_mane"):
		_prism[target] = now
	if traits.has("gravity_mane"):
		var reach := float(traits["gravity_mane"])
		for e: Node in _enemies():
			if e == target or not is_instance_valid(e) or e.health.is_dead() or not e.has_method("push"):
				continue
			var to: Vector3 = ((target as Node3D).global_position - (e as Node3D).global_position) * Vector3(1, 0, 1)
			if to.length() <= reach and to.length() > 0.8:
				e.push(to.normalized() * GRAVITY_PULL)


func on_kill(traits: Dictionary, point: Vector3, dealt: float, now: float, victim: Node = null) -> void:
	var blasts: Node = player.get("explosives")
	if traits.has("static_mane"):
		for e: Node in _enemies():
			if is_instance_valid(e) and not e.health.is_dead() and (e as Node3D).global_position.distance_to(point) <= STATIC_RANGE and e.has_method("apply_vulnerable"):
				e.apply_vulnerable(1.0 + float(traits["static_mane"]) / 100.0, STATIC_SECONDS)
	if traits.has("firestorm_mane") and blasts != null and victim != null and victim.has_method("is_burning") and victim.is_burning():
		blasts.blast(point, 4.0, dealt * float(traits["firestorm_mane"]) / 100.0)
	if traits.has("eclipse"):
		_eclipse = mini(_eclipse + 1, ECLIPSE_MAX)
	if traits.has("comet_tail"):
		var other: Node = _nearest_other(victim, point, COMET_RANGE)
		if other != null:
			var spot: Vector3 = (other as Node3D).global_position
			other.on_hit(dealt * float(traits["comet_tail"]) / 100.0, spot + Vector3(0, 1.0, 0), Vector3.UP)
			if blasts != null:
				blasts.show_flash(spot, 1.5)
	if traits.has("chain_reaction") and blasts != null:
		blasts.blast(point, 4.0, dealt * float(traits["chain_reaction"]) / 100.0)
	if traits.has("blood_tide"):
		player.health.heal(float(player.health.max_hp) * float(traits["blood_tide"]) / 100.0)
		var w: Variant = player.get("weapon")
		if w != null:
			w.ammo = mini(int(w.ammo) + ceili(float(w.mag_size) / 3.0), int(w.mag_size))
	if traits.has("skill_surge") and player.get("skills") != null:
		player.skills.reduce_all(float(traits["skill_surge"]), now)


# After the player was hurt: Last Stand starts when health drops below a quarter (once every 30 s).
func on_hurt(traits: Dictionary, now: float) -> void:
	if not traits.has("last_stand") or now < _stand_ready_at:
		return
	if float(player.health.hp) > 0.0 and float(player.health.hp) < float(player.health.max_hp) * LAST_STAND_AT:
		_stand_until = now + float(traits["last_stand"])
		_stand_ready_at = now + LAST_STAND_REST


# How many different enemies were hit in the last PRISM_SECONDS (Prism Mane); older ones are forgotten.
func _prism_count() -> int:
	var now := Time.get_ticks_msec() / 1000.0
	for e: Variant in _prism.keys():
		if not is_instance_valid(e) or now - float(_prism[e]) > PRISM_SECONDS:
			_prism.erase(e)
	return _prism.size()


# The living enemies (through the player's explosives' source: game/wave_director.gd), [] when there is none.
func _enemies() -> Array:
	var blasts: Node = player.get("explosives")
	if blasts == null or blasts.get("source") == null:
		return []
	return blasts.source.enemy_list()


func _nearest_other(from: Node, point: Vector3, reach: float = RICOCHET_RANGE) -> Node:
	var best: Node = null
	var best_d := reach
	for e: Node in _enemies():
		if e == from or not is_instance_valid(e) or e.health.is_dead():
			continue
		var d: float = (e as Node3D).global_position.distance_to(point)
		if d <= best_d:
			best_d = d
			best = e
	return best
