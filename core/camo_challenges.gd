# Purpose: per-gun camo challenges (polish1 D5a part 3, DECISIONS_SKINS: challenges per single gun, BO3 ladder LOCKED
# 2026-11-21): which tiers are open on a gun, each open camo's progress, counting a kill made with the gun, the camos it
# has earned, the challenge camo put on it. Kept on the gun: "chal" {camo id: count} for camos under way, "chal_done"
# [camo ids] earned (both travel with the gun, also when it is traded). Pure rules.
# Dependencies: none (data/camo_challenges.json and data/camos.json passed in).
extends RefCounted

const MOST_IDS := 80  # (shape check) at most this many entries on a gun
const MOST_COUNT := 1000000

var cfg: Dictionary
var camos: Dictionary  # data/camos.json
var _tier_of := {}  # camo id -> tier
var _by_tier := {}  # tier -> [camo ids] in data order


func _init(challenges: Dictionary, camo_cfg: Dictionary) -> void:
	cfg = challenges
	camos = camo_cfg
	for row: Dictionary in camo_cfg.get("camos", []):
		var id := String(row["id"])
		if not (cfg.get("challenges", {}) as Dictionary).has(id):
			continue
		_tier_of[id] = String(row["tier"])
		if not _by_tier.has(row["tier"]):
			_by_tier[String(row["tier"])] = []
		(_by_tier[String(row["tier"])] as Array).append(id)


func tiers() -> Array:
	return (cfg.get("opens", {}) as Dictionary).keys()


func ids_of(tier: String) -> Array:
	return _by_tier.get(tier, [])


func challenge(id: String) -> Dictionary:
	return (cfg.get("challenges", {}) as Dictionary).get(id, {})


# "Get 40 headshot kills" for a camo's challenge.
func text(id: String) -> String:
	var c := challenge(id)
	var kind: Dictionary = (cfg.get("kinds", {}) as Dictionary).get(String(c.get("kind", "")), {})
	var m: float = float(kind.get("m", 0.0))
	return String(kind.get("text", "?")).replace("{n}", str(int(c.get("n", 0)))).replace("{m}", str(m) if m != floorf(m) else str(int(m)))


func done(gun: Dictionary, id: String) -> bool:
	return (gun.get("chal_done", []) as Array).has(id)


func progress(gun: Dictionary, id: String) -> int:
	if done(gun, id):
		return int(challenge(id).get("n", 0))
	return int((gun.get("chal", {}) as Dictionary).get(id, 0))


func done_in(gun: Dictionary, tier: String) -> int:
	var n := 0
	for id: String in ids_of(tier):
		if done(gun, id):
			n += 1
	return n


func is_open(gun: Dictionary, tier: String) -> bool:
	var rule: Dictionary = (cfg.get("opens", {}) as Dictionary).get(tier, {})
	if rule.is_empty():
		return false
	var after := String(rule.get("after", ""))
	if after == "":
		return true
	return is_open(gun, after) and done_in(gun, after) >= int(rule.get("need", 0))


# What a tier still needs to open on this gun: [tier below, done there, needed].
func opens_after(tier: String) -> Array:
	var rule: Dictionary = (cfg.get("opens", {}) as Dictionary).get(tier, {})
	return [String(rule.get("after", "")), int(rule.get("need", 0))]


func mastery(gun: Dictionary) -> int:
	return (gun.get("chal_done", []) as Array).size()


func total() -> int:
	return _tier_of.size()


# Which kinds a kill counts for. `kill`: head, elite, boss (bools), dist (m), aim, air (bools), health (0..1), since
# (s since this gun's last kill), streak (kills in a row without being hit, this one included), place ("island",
# "arena", "sea" or "").
func kinds_of(kill: Dictionary) -> Array:
	var k: Dictionary = cfg.get("kinds", {})
	var out := ["kills"]
	if bool(kill.get("head", false)):
		out.append("head")
	if bool(kill.get("elite", false)):
		out.append("elite")
	if bool(kill.get("boss", false)):
		out.append("boss")
	if float(kill.get("dist", 0.0)) >= float((k.get("long", {}) as Dictionary).get("m", 25.0)):
		out.append("long")
	if float(kill.get("dist", 99.0)) <= float((k.get("close", {}) as Dictionary).get("m", 4.0)):
		out.append("close")
	out.append("aim" if bool(kill.get("aim", false)) else "hip")
	if float(kill.get("since", 99.0)) <= float((k.get("multi", {}) as Dictionary).get("m", 1.5)):
		out.append("multi")
	if bool(kill.get("air", false)):
		out.append("air")
	if float(kill.get("health", 1.0)) * 100.0 < float((k.get("low", {}) as Dictionary).get("m", 35.0)):
		out.append("low")
	var streak := int(kill.get("streak", 0))
	if streak > 0 and streak % 5 == 0:
		out.append("streak")
	var place := String(kill.get("place", ""))
	if place in ["island", "arena", "sea"]:
		out.append(place)
	return out


# Counts a kill made with `gun` on every open camo it fits; returns the camo ids earned by it (in tier order).
func count(gun: Dictionary, kill: Dictionary) -> Array:
	var kinds := kinds_of(kill)
	var earned := []
	var under: Dictionary = gun.get("chal", {})
	var have: Array = gun.get("chal_done", [])
	for tier: String in tiers():
		if not is_open(gun, tier):
			continue
		for id: String in ids_of(tier):
			if have.has(id):
				continue
			var c := challenge(id)
			if not kinds.has(String(c.get("kind", ""))):
				continue
			var now := mini(int(under.get(id, 0)) + 1, MOST_COUNT)
			if now >= int(c.get("n", 1)):
				under.erase(id)
				have.append(id)
				earned.append(id)
			else:
				under[id] = now
	gun["chal"] = under
	gun["chal_done"] = have
	if under.is_empty():
		gun.erase("chal")
	if have.is_empty():
		gun.erase("chal_done")
	return earned


# The camo a gun wears for an earned challenge: Factory New, a pattern number of its own (from the gun), "challenge".
static func camo_for(gun: Dictionary, id: String) -> Dictionary:
	var seed_n := 1 + absi(hash([String(gun.get("body", "")), gun.get("rolls", {}), id])) % 1000
	return {"id": id, "wear": 0.0, "seed": seed_n, "challenge": true}


# Shape check of a gun's challenge fields for core/gun_gen.gd validate ("" = fine). Ids are not checked against the
# data here (core has no camo list): unknown ids simply never show.
static func check(gun: Dictionary) -> String:
	if gun.has("chal"):
		var under: Variant = gun["chal"]
		if not under is Dictionary or (under as Dictionary).size() > MOST_IDS:
			return "bad camo challenges"
		for key: Variant in under:
			var n: Variant = (under as Dictionary)[key]
			if not key is String or String(key).length() > 40 or not (n is int or n is float) or float(n) < 0.0 or float(n) > float(MOST_COUNT):
				return "bad camo challenge"
	if gun.has("chal_done"):
		var have: Variant = gun["chal_done"]
		if not have is Array or (have as Array).size() > MOST_IDS:
			return "bad camos earned"
		for id: Variant in have:
			if not id is String or String(id).length() > 40:
				return "bad camo earned"
	if gun.get("camo") is Dictionary and bool((gun["camo"] as Dictionary).get("challenge", false)) and not (gun.get("chal_done", []) as Array).has(String(gun["camo"].get("id", ""))):
		return "challenge camo not earned"
	return ""
