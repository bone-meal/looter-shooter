# Purpose: the carried skinned knife's POWER as rules (polish1 D5b part 2, diary/DESIGN_KNIVES.md): one power per
# finish, its numbers from data/knife_skins.json powers.<id>.p scaled by the knife's level and roll. Keeps the power's
# timers, counters and cooldowns, and answers each event with a list of ACTIONS for game/knife_powers.gd to carry out
# ({"do": "heal", "share": 0.07} ...): a knife hit (slash / stab), a knife kill, damage coming in, a blow that would put
# us down. Also the running bonuses the player reads every frame (speed, fire rate, luck, damage taken). Pure rules.
# Dependencies: core/knife_skins.gd (rules object passed in).
extends RefCounted

var rules: RefCounted
var power := ""  # power id of the carried knife ("" = none)
var p: Dictionary = {}  # its numbers
var scale := 0.0  # level x roll
var _cool := {}  # action -> time it is ready again
var _until := {}  # buff -> time it ends
var _value := {}  # buff -> its size
var _count := 0  # kills or hits toward an "every n" power
var _combo: Array = []  # times of recent slashes (The Bite)
var _stacks := 0  # Loot Chaser stacks
var _laugh_kills := 0  # Last Laugh: kills since it was spent (it starts charged)
var _laugh_ready := true


func _init(knife_rules: RefCounted) -> void:
	rules = knife_rules


# The carried knife changed ({} = none).
func carry(item: Dictionary) -> void:
	var pw: Dictionary = {} if item.is_empty() else rules.call("power", item)
	power = String(rules.call("finish", String(item.get("finish", ""))).get("power", "")) if not item.is_empty() else ""
	p = pw.get("p", {})
	scale = 0.0 if item.is_empty() else float(rules.call("power_scale", item))
	_until.clear()
	_value.clear()
	_count = 0
	_combo.clear()
	_stacks = 0


func n() -> float:
	return float(p.get("n", 0.0)) * scale


func _off_cool(action: String, now: float) -> bool:
	return now >= float(_cool.get(action, 0.0))


func _cooldown(action: String, now: float) -> void:
	_cool[action] = now + float(p.get("cooldown", 0.0))


func _buff(name: String, value: float, seconds: float, now: float) -> void:
	_until[name] = now + seconds
	_value[name] = value


func buff(name: String, now: float) -> float:
	return float(_value.get(name, 0.0)) if now < float(_until.get(name, 0.0)) else 0.0


func cooldown_left(now: float) -> float:
	var most := 0.0
	for a: String in _cool:
		most = maxf(most, float(_cool[a]) - now)
	return most


# A knife blow landed. kind = "slash" / "stab"; elite / boss of the target.
func on_hit(kind: String, elite: bool, boss: bool, now: float) -> Array:
	var out: Array = []
	match power:
		"spark_shower":
			if kind == "stab":
				out.append({"do": "burn_area", "radius": float(p["radius"]), "dps": float(p["dps"]) * scale, "seconds": float(p["seconds"])})
		"meltdown":
			if kind == "stab" and _off_cool("meltdown", now):
				_cooldown("meltdown", now)
				out.append({"do": "delayed_blast", "delay": float(p["delay"]), "radius": float(p["radius"]), "damage": float(p["damage"]) * scale * (float(p["boss"]) if boss else 1.0)})
		"anvil_drop":
			if kind == "stab" and _off_cool("anvil_drop", now):
				_cooldown("anvil_drop", now)
				out.append({"do": "slam", "radius": float(p["radius"]), "stun": float(p["stun"]), "push": float(p["push"])})
		"living_metal":
			if kind == "stab":
				out.append({"do": "pool", "seconds": float(p["seconds"]), "length": float(p["length"])})
		"salt_wound":
			if kind == "slash":
				out.append({"do": "vulnerable", "mult": 1.0 + n() / 100.0, "seconds": float(p["seconds"])})
		"refraction":
			_buff("miss", n() / 100.0, float(p["seconds"]), now)
		"drag_down":
			if kind == "stab":
				out.append({"do": "freeze", "seconds": float(p["elite"]) if (elite or boss) else float(p["seconds"])})
		"the_bite":
			if kind == "slash":
				_combo.append(now)
				while not _combo.is_empty() and now - float(_combo[0]) > float(p["window"]):
					_combo.pop_front()
				if _combo.size() >= int(p["combo"]) and _off_cool("the_bite", now):
					_combo.clear()
					_cooldown("the_bite", now)
					out.append({"do": "bite", "length": float(p["length"]), "damage": float(p["damage"]) * scale})
		"venom":
			if kind == "slash":
				out.append({"do": "venom", "dps": float(p["dps"]) * scale, "seconds": float(p["seconds"]), "stacks": int(p["stacks"])})
		"lightning":
			_count += 1
			if _count >= int(p["every"]):
				_count = 0
				out.append({"do": "cast", "skill": "chain_lightning"})
		"snowman":
			if kind == "stab" and _off_cool("snowman", now):
				_cooldown("snowman", now)
				out.append({"do": "snowman", "freeze": float(p["boss_freeze"]) if boss else float(p["freeze"]), "nose": float(p["boss_nose"]) if boss else float(p["nose"]), "mult": 1.0 + (float(p["vulnerable"]) - 1.0) * clampf(scale, 0.0, 1.2)})
	return out


# A kill with the knife (paid). rng for chance powers.
func on_kill(now: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if power == "last_laugh" and not _laugh_ready:
		_laugh_kills += 1
		if _laugh_kills >= int(p["recharge"]):
			_laugh_ready = true
			out.append({"do": "notice", "text": "LAST LAUGH READY"})
	match power:
		"whetstone":
			out.append({"do": "refill_mag", "share": n() / 100.0})
		"second_breath":
			out.append({"do": "heal", "share": n() / 100.0})
		"hardened":
			_buff("guard", n() / 100.0, float(p["seconds"]), now)
		"living_metal":
			out.append({"do": "ignite_next", "reach": float(p["ignite"])})
		"undertow":
			out.append({"do": "pull_loot", "radius": n()})
		"party_ammo":
			_count += 1
			if _count >= int(p["every"]):
				_count = 0
				out.append({"do": "party_ammo", "share": n() / 100.0, "reach": float(p["reach"])})
		"deep_light":
			if _off_cool("deep_light", now):
				_cooldown("deep_light", now)
				out.append({"do": "cast", "skill": "decoy_hologram"})
		"regrowth":
			_buff("regen", n() / 100.0, float(p["seconds"]), now)
		"northern_step":
			_buff("speed", n() / 100.0, float(p["seconds"]), now)
			out.append({"do": "reset_dodge"})
		"loot_chaser":
			_stacks = mini(_stacks + 1, int(p["stacks"])) if now < float(_until.get("luck", 0.0)) else 1
			_buff("luck", n() / 100.0 * float(_stacks), float(p["seconds"]), now)
		"party_revive":
			if _off_cool("party_revive", now):
				out.append({"do": "revive_near", "reach": float(p["reach"]), "share": n() / 100.0, "then_cool": float(p["cooldown"])})
		"spirit_pack":
			if _off_cool("spirit_pack", now):
				_cooldown("spirit_pack", now)
				out.append({"do": "cast", "skill": "swarm_drones"})
		"sugar_rush":
			_buff("rate", n() / 100.0, float(p["seconds"]), now)
		"lucky_stub":
			if rng.randf() * 100.0 < n():
				var c: Array = p["chips"]
				out.append({"do": "chips", "chips": rng.randi_range(int(c[0]), int(c[1])), "ticket": rng.randf() < 0.3})
		"party_popper":
			out.append({"do": "blind", "radius": float(p["radius"]), "seconds": float(p["blind"])})
		"club_lights":
			out.append({"do": "marks", "radius": float(p["radius"]), "seconds": float(p["seconds"])})
		"slot_roll":
			out.append({"do": "slot", "symbol": _spin(rng)})
	return out


func _spin(rng: RandomNumberGenerator) -> String:
	var w: Dictionary = p.get("weights", {})
	var total := 0.0
	for k: String in w:
		total += float(w[k])
	var at := rng.randf() * total
	for k: String in w:
		at -= float(w[k])
		if at <= 0.0:
			return k
	return "cherries"


# Party Revive found nobody to help up: no cooldown spent.
func revive_used(now: float, seconds: float) -> void:
	_cool["party_revive"] = now + seconds


# Damage about to be taken: Hardened takes a share off, Refraction makes some blows miss.
func incoming(amount: float, now: float, roll: float) -> float:
	if now < float(_until.get("untouchable", 0.0)):
		return 0.0
	if roll < buff("miss", now):
		return 0.0
	return amount * (1.0 - buff("guard", now))


# Last Laugh: a blow would put us down. True = we stay up (at 1 health, untouchable a while); then it recharges.
func would_down(now: float) -> bool:
	if power != "last_laugh" or not _laugh_ready:
		return false
	_laugh_ready = false
	_laugh_kills = 0
	_until["untouchable"] = now + float(p["untouchable"])
	return true


func laugh_ready() -> bool:
	return power == "last_laugh" and _laugh_ready


func speed_mult(now: float) -> float:
	return 1.0 + buff("speed", now)


func rate_mult(now: float) -> float:
	return 1.0 + buff("rate", now)


func luck_pct(now: float) -> float:
	return buff("luck", now) * 100.0


func regen_share(now: float) -> float:
	return buff("regen", now)
