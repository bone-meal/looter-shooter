# Purpose: pure rules for gun skills (the Q/E abilities): rolling a gun's skills, reading their rolled numbers, cooldowns, checking skills on a gun. No nodes, no rendering.
# Dependencies: core/gun_db.gd (skills + tier data). A skill on a gun is {"id", "q"}; q 0..1 interpolates every number between its worst and best value in data/skills.json.
extends RefCounted

var _ready_at := {}  # cooldown key -> engine time the skill is usable again


# The rolled number `param` of a gun's skill entry ({"id", "q"}).
static func value(db: RefCounted, entry: Dictionary, param: String) -> float:
	var def: Dictionary = db.skill_def(String(entry["id"]))
	var range_: Array = def["params"][param]
	return lerpf(float(range_[0]), float(range_[1]), float(entry["q"]))


# Cooldown in seconds: the skill's rolled cooldown times the tier multiplier (pony is shorter).
static func cooldown(db: RefCounted, entry: Dictionary, tier_id: String) -> float:
	var def: Dictionary = db.skill_def(String(entry["id"]))
	var cd: Array = def["cooldown"]
	return lerpf(float(cd[0]), float(cd[1]), float(entry["q"])) * float(db.tier(tier_id).get("skill_cd", 1.0))


# Description with the rolled numbers filled in ("{radius}" becomes 7.5).
static func describe(db: RefCounted, entry: Dictionary) -> String:
	var def: Dictionary = db.skill_def(String(entry["id"]))
	var text := String(def["desc"])
	var params: Dictionary = def["params"]
	for p: String in params:
		var v := value(db, entry, p)
		text = text.replace("{%s}" % p, String.num(v, 0 if absf(v - roundf(v)) < 0.05 or v >= 10.0 else (2 if v < 1.0 else 1)))
	return text


# Rolls the skills of a new gun of this tier: distinct ids, quality in the tier's skill_quality band.
static func roll(db: RefCounted, rng: RandomNumberGenerator, tier_id: String) -> Array:
	var tier: Dictionary = db.tier(tier_id)
	var out: Array = []
	var pool: Array = db.skills.keys()
	var lo: float = float(tier["skill_quality"][0])
	var hi: float = float(tier["skill_quality"][1])
	for _n in mini(int(tier["skills"]), pool.size()):
		var id := String(pool[rng.randi_range(0, pool.size() - 1)])
		pool.erase(id)
		out.append({"id": id, "q": snappedf(rng.randf_range(lo, hi), 0.001)})
	return out


# "" when the skills list is legal for this tier, otherwise a short reason.
static func check(db: RefCounted, tier_id: String, skills: Variant, eps: float) -> String:
	if not (skills is Array):
		return "bad skills"
	var list: Array = skills
	var tier: Dictionary = db.tier(tier_id)
	if list.size() != mini(int(tier["skills"]), db.skills.size()):
		return "wrong number of skills"
	var lo: float = float(tier["skill_quality"][0]) - eps
	var hi: float = float(tier["skill_quality"][1]) + eps
	var seen: Array[String] = []
	for s: Variant in list:
		if not (s is Dictionary):
			return "bad skill"
		var sd: Dictionary = s
		var id := String(sd.get("id", ""))
		if not db.skills.has(id) or seen.has(id):
			return "unknown or repeated skill"
		seen.append(id)
		var q: float = float(sd.get("q", -1.0))
		if q < lo or q > hi:
			return "skill out of tier range"
	return ""


func is_ready(key: String, now: float) -> bool:
	return now >= float(_ready_at.get(key, 0.0))


func remaining(key: String, now: float) -> float:
	return maxf(float(_ready_at.get(key, 0.0)) - now, 0.0)


func start(key: String, now: float, seconds: float) -> void:
	_ready_at[key] = now + seconds


# Takes `seconds` off every running cooldown (kills with the Cooldown Siphon buff).
func reduce_all(seconds: float, now: float) -> void:
	for key: String in _ready_at:
		if float(_ready_at[key]) > now:
			_ready_at[key] = maxf(float(_ready_at[key]) - seconds, now)


func refund(key: String) -> void:
	_ready_at.erase(key)
