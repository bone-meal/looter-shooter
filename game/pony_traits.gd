# Purpose: what the PONY FAMILIES' own traits do (director 2026-11-14, diary/DECISIONS_SEA.md; data/pony_families.json,
# data/gun_traits.json with "family"). Each family plays its virtue and a use for the party:
#   Concordia Starweave (Magic)       Spellweave, Concord: gun skills hit harder and come round faster
#   Hearthgold Trueheart (Honesty)    Honest Work, Hearthfire: steady damage without crits, warmth after kills
#   Valor Skystreak (Loyalty)         Stand Fast, Skystreak: holds the front, rushes on after kills
#   Bellegrace Gemshine (Generosity)  Gemcut, Generous Spirit: crystal crits, rounds back into every gun
#   Kindlebloom Softwing (Kindness)   Soft Wing, Bloom: softer enemy blows, healing flowers
#   Merribelle Joyburst (Laughter)    Party Popper, Joyburst: laughing fits, a faster trigger
# Called by game/gun_traits.gd from the player's hooks; `traits` = the held gun's {id: value}.
# Dependencies: the player (game/player.gd: health, skills, allies_close, _last_crit, _ready_weapons, skill_fx,
# explosives), enemies' rally / apply_slow / apply_freeze (game/enemy.gd).
extends RefCounted

const SPELL_SHOTS := 6
const CONCORD_TEAM := 2.0  # Concord: twice the time off with a teammate near
const STAND_AT := 0.5
const SKY_SECONDS := 3.0
const SHARD_RADIUS := 2.5
const SHARD_SHARE := 0.3
const SOOTHE_SECONDS := 3.0
const BLOOM_SECONDS := 5.0
const BLOOM_RADIUS := 3.0
const POPPER_RADIUS := 4.0
const JOY_WINDOW := 3.0
const JOY_MAX := 5

var player: Node
var _spell_shots := 0  # Spellweave: charged shots left
var _sky_until := 0.0
var _sky_speed := 0.0
var _double_next := false  # Skystreak: the next shot deals double
var _double_now := false  # ... and this one is it
var _joy := 0
var _joy_until := 0.0


func on_swapped() -> void:
	_double_now = false


func on_skill_cast(traits: Dictionary) -> void:
	if traits.has("spellweave"):
		_spell_shots = SPELL_SHOTS


func on_shot(_traits: Dictionary, _now: float) -> void:
	_double_now = _double_next
	_double_next = false


func damage_mult(traits: Dictionary) -> float:
	var mult := 1.0
	if _spell_shots > 0:
		mult *= 1.0 + float(traits.get("spellweave", 0.0)) / 100.0
	if traits.has("honest_work"):
		mult *= 1.0 + float(traits["honest_work"]) / 100.0
	if _double_now:
		mult *= 2.0
	if traits.has("gemcut") and bool(player.get("_last_crit")):
		mult *= 1.0 + float(traits["gemcut"]) / 100.0
	return mult


func after_shot() -> void:
	_spell_shots = maxi(_spell_shots - 1, 0)
	_double_now = false


func on_hit(traits: Dictionary, target: Node, point: Vector3, dealt: float) -> void:
	if traits.has("gemcut") and bool(player.get("_last_crit")):
		var blasts: Node = player.get("explosives")
		if blasts != null:
			blasts.blast(point, SHARD_RADIUS, dealt * SHARD_SHARE)  # the crystal shards
	if traits.has("soft_wing"):
		var soft := 1.0 - float(traits["soft_wing"]) / 100.0
		if target.has_method("rally"):
			target.rally(1.0, soft, SOOTHE_SECONDS)  # its blows land softer (a war cry later overrides it)
		if target.has_method("apply_slow"):
			target.apply_slow(float(traits["soft_wing"]) / 200.0, SOOTHE_SECONDS)


func on_kill(traits: Dictionary, point: Vector3, now: float) -> void:
	if traits.has("concord") and player.get("skills") != null:
		var off := float(traits["concord"]) * (CONCORD_TEAM if int(player.get("allies_close")) > 0 else 1.0)
		player.skills.reduce_all(off, now)
	if traits.has("hearthfire"):
		player.health.heal(float(player.health.max_hp) * float(traits["hearthfire"]) / 100.0)
	if traits.has("skystreak"):
		_sky_until = now + SKY_SECONDS
		_sky_speed = float(traits["skystreak"])
		_double_next = true
	if traits.has("generous_spirit"):
		for w: Variant in player.get("_ready_weapons"):
			if w != null:
				w.ammo = mini(int(w.ammo) + ceili(float(w.mag_size) * float(traits["generous_spirit"]) / 100.0), int(w.mag_size))
	if traits.has("bloom") and player.get("skill_fx") != null:
		player.skill_fx.zones.bloom(point, BLOOM_RADIUS, BLOOM_SECONDS, float(player.health.max_hp) * float(traits["bloom"]) / 100.0)
	if traits.has("party_popper"):
		var blasts: Node = player.get("explosives")
		if blasts != null:
			blasts.show_flash(point + Vector3(0, 1.0, 0), POPPER_RADIUS * 0.6)
			for e: Node in _enemies(blasts):
				if is_instance_valid(e) and not e.health.is_dead() and not String(e.get("enemy_id")).begins_with("boss") and (e as Node3D).global_position.distance_to(point) <= POPPER_RADIUS:
					e.apply_freeze(float(traits["party_popper"]))  # a laughing fit
	if traits.has("joyburst"):
		_joy = mini(_joy + 1, JOY_MAX) if now < _joy_until else 1
		_joy_until = now + JOY_WINDOW


func taken_mult(traits: Dictionary) -> float:
	if traits.has("stand_fast") and float(player.health.hp) < float(player.health.max_hp) * STAND_AT:
		return 1.0 - float(traits["stand_fast"]) / 100.0
	return 1.0


func rate_mult(traits: Dictionary, now: float) -> float:
	if traits.has("joyburst") and now < _joy_until:
		return 1.0 + float(traits["joyburst"]) * float(_joy) / 100.0
	return 1.0


func speed_mult(now: float) -> float:
	return 1.0 + _sky_speed / 100.0 if now < _sky_until else 1.0


func _enemies(blasts: Node) -> Array:
	return blasts.source.enemy_list() if blasts.get("source") != null else []
