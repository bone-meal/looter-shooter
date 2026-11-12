# Purpose: gives the fantasy world's creatures their orders (rules: core/squad_rules.gd, numbers:
# data/fantasy/squad.json): a few times a second every group of creatures hunting the same player is planned as one
# squad, and each creature is told where to walk and whether it may strike (game/enemy.gd order_goal / order_attack).
# Bosses and creatures busy with something else (a tribe's feud) keep their own heads. Host only: other machines'
# creatures are puppets. Towns, villages and the farm are SAFE (core/safe_places.gd): a creature inside one's border,
# or whose prey is, is sent back out and may not strike or use its special attack (game/enemy.gd `calm_until`).
# Dependencies: core/safe_places.gd, an enemy list (`source.enemy_list()`), game/fantasy_world.gd (combat.warding, caster.channelling,
# marks.hazards), game/enemy.gd.
extends Node

const SquadRules = preload("res://core/squad_rules.gd")
const SafePlaces = preload("res://core/safe_places.gd")

var cfg: Dictionary
var source: Node  # has enemy_list()
var safe := SafePlaces.new()  # set up by game/fantasy_world.gd once the land is known

var _world: Node3D
var _player: Node3D
var _due := 0.0
var _clock := 0.0
var _members := {}  # creature instance id -> SquadRules.Member (kept, so planning allocates nothing new)
var _squads := {}  # target instance id -> {"target": Node3D, "list": Array of Member, "bodies": Array of Node3D, "base": float, "seen": float}
var _target := SquadRules.Target.new()
var _hazards: Array = []
var _letters := ""  # the elements of the local player's latest casts
var _letters_until := 0.0


func setup(fantasy_world: Node3D, player: Node3D, numbers: Dictionary) -> void:
	_world = fantasy_world
	_player = player
	cfg = numbers


# The local player cast this (game/fantasy_world.gd): creatures weak to its elements think twice for a while.
func note_cast(sequence: String) -> void:
	_letters = sequence
	_letters_until = _clock + float(cfg["fear_seconds"])


func clear() -> void:
	_members.clear()
	_squads.clear()


# What a creature was last told, for the log: "role mode" (or "" when it has no orders).
func order_of(enemy: Node3D) -> String:
	var m: SquadRules.Member = _members.get(enemy.get_instance_id())
	return "" if m == null else "%s %s%s" % [m.role, m.mode, "" if m.attack else " (waits)"]


func _process(delta: float) -> void:
	_clock += delta
	_due -= delta
	var spawner: Node = _world.get("spawner")
	if _due > 0.0 or not bool(spawner.get("active")):  # online only the host runs creatures
		return
	_due = float(cfg["tick"])
	var players: Array = spawner.call("bodies")
	for key: int in _squads:
		(_squads[key]["list"] as Array).clear()
		(_squads[key]["bodies"] as Array).clear()
	var reach := float(cfg["radius"])
	var until := Time.get_ticks_msec() / 1000.0 + float(cfg["tick"]) * 2.5
	for enemy: Variant in source.call("enemy_list"):
		if not is_instance_valid(enemy):
			continue
		var body := enemy as Node3D
		if not body.has_meta("fantasy") or body.has_meta("fantasy_boss") or bool(body.get("puppet")):
			continue
		var prey: Variant = body.get("_target")
		if not is_instance_valid(prey) or not players.has(prey):
			continue  # nobody to hunt, or it is fighting another creature
		var hunted := prey as Node3D
		var here: Vector3 = _world.call("local_of", body.global_position)
		var there: Vector3 = _world.call("local_of", hunted.global_position)
		var back := safe.turn_back(Vector2(here.x, here.z), Vector2(there.x, there.z))
		if back.is_finite():  # a safe place is in the way: out it goes, and no blow, shot or special attack meanwhile
			body.set("order_goal", body.global_position + Vector3(back.x - here.x, 0.0, back.y - here.z))
			body.set("order_attack", false)
			body.set("order_until", until)
			body.set("calm_until", until)
			continue
		if body.global_position.distance_to(hunted.global_position) > reach:
			continue  # still far off: it just walks up
		var key := hunted.get_instance_id()
		if not _squads.has(key):
			_squads[key] = {"target": hunted, "list": [], "bodies": [], "base": 0.0, "seen": -99.0}
		var m: SquadRules.Member = _members.get(body.get_instance_id())
		if m == null:
			var stats: Dictionary = body.get("_stats")
			m = SquadRules.Member.new()
			m.role = String(stats.get("role", "ranged" if String(stats["attack_type"]) == "ranged" else "swarm"))
			m.reach = float(stats["attack_range"])
			m.prefer = float(stats.get("preferred_range", 0.0))
			m.weak = String(stats.get("weak", ""))
			m.strong = String(stats.get("strong", ""))
			_members[body.get_instance_id()] = m
		m.pos = Vector2(body.global_position.x, body.global_position.z)
		m.hp = float(body.get("health").hp) / maxf(float(body.get("health").max_hp), 1.0)
		(_squads[key]["list"] as Array).append(m)
		(_squads[key]["bodies"] as Array).append(body)
	_hazards.clear()
	_world.get("marks").call("hazards", _hazards)
	for key: int in _squads.keys():
		var squad: Dictionary = _squads[key]
		var list: Array = squad["list"]
		if list.is_empty() or not is_instance_valid(squad["target"]):
			_squads.erase(key)
			continue
		var hunted: Node3D = squad["target"]
		var forward: Vector3 = hunted.call("view_forward") if hunted.has_method("view_forward") else -hunted.global_transform.basis.z
		_target.pos = Vector2(hunted.global_position.x, hunted.global_position.z)
		_target.facing = Vector2(forward.x, forward.z).normalized()
		var mine := hunted == _player  # what the others are doing is not known on this machine
		_target.busy = mine and (bool(_world.get("combat").get("warding")) or bool(_world.get("caster").get("channelling")))
		var life: Variant = hunted.get("health")
		_target.hp = float(life.hp) / maxf(float(life.max_hp), 1.0) if life != null else 1.0
		_target.letters = _letters if mine and _clock < _letters_until else ""
		# the line the squad came from: fixed when it forms, then it follows the front creatures slowly
		var middle := Vector2.ZERO
		var fronts := 0
		var all := Vector2.ZERO
		for m: SquadRules.Member in list:
			all += m.pos
			if m.role == "front":
				middle += m.pos
				fronts += 1
		if _clock - float(squad["seen"]) > 3.0:
			squad["base"] = (all / float(list.size()) - _target.pos).angle()
		elif fronts > 0:
			squad["base"] = lerp_angle(float(squad["base"]), (middle / float(fronts) - _target.pos).angle(), 0.25)
		squad["seen"] = _clock
		SquadRules.plan(cfg, list, _target, float(squad["base"]), _hazards, _clock)
		var bodies: Array = squad["bodies"]
		for i in list.size():
			var m: SquadRules.Member = list[i]
			var body: Node3D = bodies[i]
			body.set("order_goal", Vector3(m.goal.x, 0.0, m.goal.y))
			body.set("order_attack", m.attack)
			body.set("order_until", until)
	if _members.size() > 64:  # forget the dead now and then
		for id: int in _members.keys():
			if not is_instance_id_valid(id):
				_members.erase(id)
