# Purpose: how the creatures hunting one target fight TOGETHER, as pure rules (no nodes, no rendering): who goes
# in, who waits in a ring for its turn, who takes the sides and the back, where the shooters stand, who hangs back
# because the target just used the element it fears. One call plans one squad: it reads each Member and writes that
# member's goal (where to walk), attack (may it strike now) and mode (a word for logs and tests).
# Numbers: data/fantasy/squad.json. Played by game/squad_command.gd. Written for the fantasy world first; nothing
# here knows about it, so the gun-side enemies can use it later.
# Dependencies: none.
extends RefCounted


# One creature of a squad.
class Member:
	extends RefCounted
	# told to the planner
	var pos := Vector2.ZERO
	var role := "swarm"  # "front" | "flank" | "swarm" | "ranged" | "air"
	var reach := 1.5  # how far its attack reaches
	var prefer := 0.0  # the distance a shooter likes to keep
	var weak := ""  # element letters, as in data/fantasy/enemies.json
	var strong := ""
	var hp := 1.0  # share of its health left
	# answered by the planner
	var goal := Vector2.ZERO
	var attack := true
	var mode := ""  # "press" | "circle" | "shoot" | "orbit" | "back"
	var _score := 0.0
	var _angle := 0.0


# Whom they are after.
class Target:
	extends RefCounted
	var pos := Vector2.ZERO
	var facing := Vector2(0, -1)
	var busy := false  # holding a ward or gathering a spell
	var hp := 1.0
	var letters := ""  # the elements it cast a moment ago


static func _dir(angle: float) -> Vector2:
	return Vector2(cos(angle), sin(angle))


# Plans one squad. `base` = the bearing (radians, from the target) the squad came from: the front stands there, the
# rest is placed relative to it. `hazards` = Vector3(x, z, radius) of ground nobody should stand on. `clock` = seconds.
static func plan(cfg: Dictionary, members: Array, target: Target, base: float, hazards: Array, clock: float) -> void:
	var melee: Array = []
	var shooters: Array = []
	var healthy := 0
	var unafraid := 0  # melee creatures that will not hang back: the front, and whoever does not fear what the target just cast
	for m: Member in members:
		if m.hp >= float(cfg["retreat_hp"]):
			healthy += 1
		if m.role == "ranged":
			shooters.append(m)
		else:
			melee.append(m)
			if m.role == "front" or not wary(m, target):
				unafraid += 1
	# --- whose turn it is to strike ---
	var turns := int(cfg["engaged_melee_low"]) if target.busy or target.hp < float(cfg["low_hp"]) else int(cfg["engaged_melee"])
	var shift := int(clock / float(cfg["token_seconds"]))
	for i in melee.size():
		var m: Member = melee[i]
		var away := m.pos - target.pos
		m._score = away.length() + float((i + shift) % maxi(melee.size(), 1)) * 6.0  # the queue moves on by itself
		if m.role == "front":
			m._score -= 1000.0  # the front never waits
		if wary(m, target):
			m._score += 60.0
		elif bold(m, target):
			m._score -= 25.0
		if target.busy and away.dot(target.facing) < 0.0:
			m._score -= 40.0  # at its back while it is busy: go
	# --- where everybody stands (in the order given, which does not change from one plan to the next, so nobody
	# is sent from one side to the other because the queue moved on) ---
	var fronts := 0
	var left := 0
	var right := 0
	var flyers := 0
	var side_step := deg_to_rad(float(cfg["side_step_deg"]))
	for m: Member in melee:
		var away := m.pos - target.pos
		var angle := base
		match m.role:
			"front":
				angle = base + deg_to_rad(float(cfg["front_spread_deg"])) * float((fronts + 1) >> 1) * (1.0 if fronts % 2 == 1 else -1.0)
				fronts += 1
			"air":
				angle = base + PI + deg_to_rad(float(cfg["air_turn_deg"])) * clock * (1.0 if flyers % 2 == 0 else -1.0) + float(flyers) * 1.9
				flyers += 1
			_:
				var open := deg_to_rad(float(cfg["flank_angle_deg"] if m.role == "flank" else cfg["swarm_angle_deg"]))
				var side := _dir(base).cross(away)  # which side of the squad's line it is on already
				if (side > 0.0 and left > right) or (side <= 0.0 and right > left) or absf(side) < 0.3:
					side = 1.0 if left <= right else -1.0  # that side is the fuller one: take the other (a pincer)
				if side > 0.0:
					angle = base + open + side_step * float(left)
					left += 1
				else:
					angle = base - open - side_step * float(right)
					right += 1
		m._angle = angle
	melee.sort_custom(func(a: Member, b: Member) -> bool: return a._score < b._score)
	for i in melee.size():
		var m: Member = melee[i]
		var angle := m._angle
		var wounded := m.hp < float(cfg["retreat_hp"]) and m.role != "front" and healthy >= 2
		var ring := float(cfg["air_ring"]) if m.role == "air" else float(cfg["circle_range"])
		if wounded:
			m.mode = "back"
			m.attack = false
			m.goal = target.pos + _dir(angle) * (ring + float(cfg["retreat_m"]))
		elif i < turns and not (wary(m, target) and m.role != "front" and unafraid > 0):  # the fearful give their turn to the others; if all fear it, they come anyway
			m.mode = "press"
			m.attack = true
			m.goal = target.pos + _dir(angle) * maxf(m.reach * 0.7, 0.8)
		else:
			m.mode = "orbit" if m.role == "air" else "circle"
			m.attack = false
			m.goal = target.pos + _dir(angle) * (ring + (float(cfg["fear_back_m"]) if wary(m, target) else 0.0))
	var arc := deg_to_rad(float(cfg["ranged_arc_deg"]))
	for i in shooters.size():
		var m: Member = shooters[i]
		var angle := base + arc * ((float(i) + 0.5) / float(shooters.size()) - 0.5)
		var wounded := m.hp < float(cfg["retreat_hp"]) and healthy >= 2
		m.mode = "back" if wounded else "shoot"
		m.attack = true  # a shooter shoots whenever it has a shot; what the squad decides is where from
		m.goal = target.pos + _dir(angle) * (m.prefer + (float(cfg["fear_back_m"]) if wary(m, target) else 0.0) + (float(cfg["retreat_m"]) if wounded else 0.0))
	# --- nobody is sent to stand in fire ---
	var pad := float(cfg["hazard_pad"])
	for m: Member in members:
		for h: Vector3 in hazards:
			var off := m.goal - Vector2(h.x, h.y)
			if off.length() < h.z + pad:
				m.goal = Vector2(h.x, h.y) + (off.normalized() if off.length() > 0.05 else _dir(base)) * (h.z + pad)


# The target just used the element this creature is weak to.
static func wary(m: Member, target: Target) -> bool:
	return m.weak != "" and target.letters.contains(m.weak)


# The target just used the element this creature shrugs off (and not the one it fears).
static func bold(m: Member, target: Target) -> bool:
	return m.strong != "" and target.letters.contains(m.strong) and not wary(m, target)
