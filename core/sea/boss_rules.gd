# Purpose: the RULES of a sea super boss fight (sea step 10, LOCKED in DECISIONS_SEA.md / diary/DESIGN_BOSSES.md):
# which phase a health share is in, health and adds scaled to the party, which attack comes next, how much of a hit
# gets through (armour, weak points, an open shell), breakable parts and the shell they crack, the stun, the enrage
# clock, who is down / out and when the party has wiped, and the DREAD a death leaves on a player. Pure: no nodes,
# no drawing, no network (game/sea_boss.gd runs it on the host).
# Dependencies: none (data/sea/bosses.json is passed in).
extends RefCounted

var cfg: Dictionary  # one boss of data/sea/bosses.json "bosses"
var all: Dictionary  # the whole file (downs, dread, party)
var players := 1
var max_hp := 1.0
var phase := 0
var fight_t := 0.0  # seconds since the fight began
var enraged := false
var parts := {}  # breakable part id -> hp left
var crack_until := -1.0  # fight time the cracked shell closes again
var regrow_at := -1.0  # fight time broken parts grow back after a crack (a phase's regrow_s; -1 = at once)
var exposed := false  # (the Lantern Queen) in a lit brazier's circle: the body takes all of a hit, "lit" weak parts are live
var stun_until := -1.0
var stun_ready := 0.0  # fight time the next stun may land
var tide_step := -1
var rise_t := 0.0
var downs := {}  # peer -> "down" | "out" (not listed = up)
var _last_attack := ""


func setup(boss: Dictionary, whole: Dictionary, party: int, region_mult: float) -> void:
	cfg = boss
	all = whole
	players = clampi(party, 1, 6)
	max_hp = party_hp(float(cfg["base_hp"]), players, float(all["party"]["hp_per_extra"])) * region_mult
	phase = 0
	fight_t = 0.0
	enraged = false
	crack_until = -1.0
	regrow_at = -1.0
	exposed = false
	stun_until = -1.0
	stun_ready = 0.0
	downs.clear()
	_last_attack = ""
	_grow_parts()
	tide_step = int(cfg["phases"][0].get("tide", -1))
	rise_t = 0.0


static func party_hp(base: float, party: int, per_extra: float) -> float:
	return base * (1.0 + per_extra * float(clampi(party, 1, 6) - 1))


static func adds_count(base_n: int, party: int, per_two: int) -> int:
	return base_n + per_two * floori(float(clampi(party, 1, 6) - 1) / 2.0)


func phase_cfg() -> Dictionary:
	return cfg["phases"][phase]


# The phase a health share (0..1) belongs to.
func phase_for(share: float) -> int:
	var ph: Array = cfg["phases"]
	for i in ph.size():
		if share > float(ph[i]["until"]):
			return i
	return ph.size() - 1


# Moves on to the phase this health share is in; true when it changed (never goes back).
func advance(share: float) -> bool:
	var want := phase_for(share)
	if want <= phase:
		return false
	phase = want
	var pc := phase_cfg()
	tide_step = int(pc.get("tide", -1))
	rise_t = 0.0
	crack_until = -1.0
	regrow_at = -1.0
	_grow_parts()
	return true


# Time passes in the fight; returns true when the tide step changed (rising phases, the enrage).
func tick(delta: float) -> bool:
	fight_t += delta
	var before := tide_step
	if not enraged and fight_t >= float(cfg["enrage_s"]):
		enraged = true
		tide_step = int(cfg["enrage"]["tide"])
	elif not enraged:
		var pc := phase_cfg()
		var top := int(pc.get("tide", -1)) + int(pc.get("rise", 0))
		if tide_step < top:
			rise_t += delta
			if rise_t >= float(pc.get("rise_s", 30.0)):
				rise_t = 0.0
				tide_step += 1
	if crack_until >= 0.0 and fight_t >= crack_until:  # the shell closes: the barnacles grow back (after regrow_s)
		crack_until = -1.0
		if float(phase_cfg().get("regrow_s", 0.0)) > 0.0:
			regrow_at = fight_t + float(phase_cfg()["regrow_s"])
		else:
			_grow_parts()
	if regrow_at >= 0.0 and fight_t >= regrow_at:
		regrow_at = -1.0
		_grow_parts()
	return tide_step != before


func shed() -> bool:
	return bool(phase_cfg().get("shed", false))


func cracked() -> bool:
	return crack_until >= 0.0 and fight_t < crack_until


func stunned() -> bool:
	return (stun_until >= 0.0 and fight_t < stun_until) or (cracked() and bool(phase_cfg().get("crack_stuns", false)))


# Share of a hit on the body itself that gets through now.
func body_share() -> float:
	if shed() or cracked() or stunned() or exposed:
		return 1.0
	return float(phase_cfg().get("armour", 1.0))


func part_cfg(id: String) -> Dictionary:
	for p: Dictionary in cfg["parts"]:
		if String(p["id"]) == id:
			return p
	return {}


# Share of a hit on a weak part that reaches the boss's health (a weak point ignores the armour).
func weak_share(id: String) -> float:
	var p := part_cfg(id)
	if p.is_empty() or String(p["kind"]) != "weak":
		return body_share()
	return float(p.get("share", 1.0))


# A weak part that can be hit now (one marked "lit" only while she is exposed).
func weak_live(id: String) -> bool:
	var p := part_cfg(id)
	return not p.is_empty() and String(p["kind"]) == "weak" and (not bool(p.get("lit", false)) or exposed)


# Breakable parts that count in this phase.
func breakables() -> Array:
	var out: Array = []
	for p: Dictionary in cfg["parts"]:
		if String(p["kind"]) == "breakable" and int(p.get("phase", 0)) == phase and not shed():
			out.append(String(p["id"]))
	return out


func _grow_parts() -> void:
	parts.clear()
	for p: Dictionary in cfg["parts"]:
		if String(p["kind"]) == "breakable":
			parts[String(p["id"])] = float(p["hp"])


func broken(id: String) -> bool:
	return parts.has(id) and float(parts[id]) <= 0.0


# Damage to a breakable part. Returns "" (nothing), "broke" (this part went) or "crack" (the last of the phase's
# went: the shell is open for crack_s).
func hit_part(id: String, damage: float) -> String:
	if not (id in breakables()) or cracked() or regrow_at >= 0.0 or not is_finite(damage) or damage <= 0.0 or broken(id):
		return ""
	parts[id] = float(parts[id]) - damage
	if float(parts[id]) > 0.0:
		return ""
	for other: String in breakables():
		if not broken(other):
			return "broke"
	crack_until = fight_t + float(phase_cfg().get("crack_s", 10.0))
	return "crack"


# The bell hooked: a stun when the shell is off and the last one has worn off long enough.
func try_stun() -> bool:
	if not shed() or fight_t < stun_ready:
		return false
	var s: Dictionary = cfg["stun"]
	stun_until = fight_t + float(s["seconds"])
	stun_ready = fight_t + float(s["cooldown"])
	return true


# The next attack of this phase (never the same one twice in a row when there is a choice).
func pick_attack(rng: RandomNumberGenerator) -> String:
	var list: Array = phase_cfg()["attacks"]
	if list.is_empty():
		return ""
	var choices := list.filter(func(a: Variant) -> bool: return String(a) != _last_attack) if list.size() > 1 else list
	_last_attack = String(choices[rng.randi() % choices.size()])
	return _last_attack


func attack_cfg(id: String) -> Dictionary:
	return cfg["attacks"].get(id, {})


# How fast / hard it is right now (shed phase, enrage).
func speed_mult() -> float:
	return float(phase_cfg().get("speed", 1.0)) * (float(cfg["enrage"]["speed"]) if enraged else 1.0)


func damage_mult() -> float:
	return float(phase_cfg().get("damage", 1.0)) * (float(cfg["enrage"]["damage"]) if enraged else 1.0)


func adds_now() -> Array:
	var base: Array = phase_cfg().get("adds", [])
	if base.is_empty():
		return []
	var n := adds_count(base.size(), players, int(all["party"]["adds_per_two"]))
	var out: Array = []
	for i in n:
		out.append(String(base[i % base.size()]))
	return out


# --- downed players ---

func state_of(peer: int) -> String:
	return String(downs.get(peer, "up"))


func set_state(peer: int, state: String) -> void:
	if state == "up":
		downs.erase(peer)
	elif state in ["down", "out"]:
		downs[peer] = state


# Everyone in the arena is down or out (nobody left to help): the party has wiped.
func wiped(present: Array) -> bool:
	if present.is_empty():
		return false
	for peer: int in present:
		if state_of(int(peer)) == "up":
			return false
	return true


# --- dread on a player (each death in a boss fight; a rest at a port clears it) ---

static func dread_health(stacks: int, dread: Dictionary) -> float:
	return maxf(1.0 - float(dread["health_per"]) * float(clampi(stacks, 0, int(dread["max"]))), 0.1)


static func dread_damage(stacks: int, dread: Dictionary) -> float:
	return maxf(1.0 - float(dread["damage_per"]) * float(clampi(stacks, 0, int(dread["max"]))), 0.1)
