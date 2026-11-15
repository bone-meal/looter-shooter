# Purpose: developer check of the 24 gun skills of sea step 1d on stand-in enemies (every world effect: areas,
# strikes, summons, slam, vacuum, lance, harpoon) and of the caster's own rules (core/skill_self.gd). Writes
# tools/skill_pass2_check.log ("SKILL_PASS2 problems=N" last), then quits. Run tools/skill_pass2_check.tscn
# (about 70 s: the effects run in real time).
# Dependencies: game/skill_effects.gd (+ zones / strikes / summons), core/skill_self.gd, core/skill_state.gd,
# core/gun_db.gd, core/health_state.gd.
extends Node3D

const SkillEffects = preload("res://game/skill_effects.gd")
const SkillState = preload("res://core/skill_state.gd")
const SkillSelf = preload("res://core/skill_self.gd")
const GunDb = preload("res://core/gun_db.gd")
const HealthState = preload("res://core/health_state.gd")

const AIM := Vector3(0, 0, -8)
const EYE := Vector3(0, 1.6, 0)
const AHEAD := Vector3(0, 0, -1)
const BASE := 10.0

# [seconds after the step starts, what]; each step resets the dummies when it starts
const STEPS := [
	["fire_trail_dash", 1.4], ["orbital_strike", 2.6], ["shockwave_slam", 0.3], ["vacuum_pulse", 0.3], ["time_bubble", 0.8],
	["rocket_barrage", 2.0], ["plague_cloud", 1.3], ["mirror_clone", 1.5], ["meteor_shower", 6.2], ["sticky_mines", 1.5],
	["sentry_turret", 1.5], ["thunder_totem", 2.0], ["inferno_ring", 1.2], ["storm_call", 1.6], ["spinning_blades", 2.0],
	["ice_lance", 0.3], ["harpoon_yank", 0.8], ["war_banner", 0.5], ["decoy_hologram", 1.5], ["decoy_end", 8.0],
]


class Dummy extends Node3D:
	var enemy_id := "chaser"
	var health := HealthState.new(100000.0)
	var dmg := 0.0
	var pushes := 0
	var last_push := Vector3.ZERO
	var frozen := false
	var vuln := 1.0
	var slowed := false
	var burned := false
	var target: Node3D = null

	func head_height() -> float:
		return 1.8

	func on_hit(d: float, _point: Vector3 = Vector3.ZERO, _normal: Vector3 = Vector3.UP) -> void:
		dmg += d
		health.take_damage(d)

	func push(v: Vector3) -> void:
		pushes += 1
		last_push = v

	func apply_freeze(_seconds: float) -> void:
		frozen = true

	func apply_vulnerable(mult: float, _seconds: float) -> void:
		vuln = mult

	func apply_slow(_amount: float, _seconds: float) -> void:
		slowed = true

	func apply_burn(_dps: float, _seconds: float) -> void:
		burned = true

	func set_target(t: Node3D) -> void:
		target = t

	func current_target() -> Node3D:
		return target

	func reset() -> void:
		dmg = 0.0
		pushes = 0
		frozen = false
		vuln = 1.0
		slowed = false
		burned = false


class Crowd extends RefCounted:
	var list: Array = []

	func enemy_list() -> Array:
		return list


var _db: GunDb
var _fx: Node3D
var _crowd := Crowd.new()
var _dummies: Array[Dummy] = []
var _player := Node3D.new()
var _step := -1
var _step_t := 0.0
var _log: PackedStringArray = []
var _problems := 0


func _ready() -> void:
	_db = GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	add_child(_player)
	for i in 12:  # a fan of stand-ins ahead, 3 to 14 m away
		var d := Dummy.new()
		var angle := deg_to_rad(-40.0 + float(i) * 7.0)
		var dist := 3.0 + float(i)
		d.position = Vector3(sin(angle) * dist, 0.0, -cos(angle) * dist)
		d.target = _player
		add_child(d)
		_dummies.append(d)
		_crowd.list.append(d)
	_fx = SkillEffects.new()
	_fx.source = _crowd
	_fx.follow = _player
	add_child(_fx)
	_self_rules()
	_check_data()
	_next()


func _json(shot_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % shot_name))


func _entry(id: String) -> Dictionary:
	return {"id": id, "q": 1.0}


func _expect(ok: bool, what: String) -> void:
	_log.append(("  ok: " if ok else "PROBLEM: ") + what)
	if not ok:
		_problems += 1


func _count(pred: Callable) -> int:
	var n := 0
	for d in _dummies:
		if pred.call(d):
			n += 1
	return n


func _next() -> void:
	_step += 1
	_step_t = 0.0
	if _step >= STEPS.size():
		_finish()
		return
	var id := String(STEPS[_step][0])
	if id != "decoy_end":
		for d in _dummies:
			d.reset()
	match id:
		"shockwave_slam":
			_fx.slam(_db, _entry(id), BASE, Vector3.ZERO)
		"decoy_end":
			pass
		_:
			_fx.cast(_db, _entry(id), BASE, Vector3.ZERO, EYE, AHEAD, AIM)


func _process(delta: float) -> void:
	if _step < 0 or _step >= STEPS.size():
		return
	_step_t += delta
	if _step_t >= float(STEPS[_step][1]):
		_report(String(STEPS[_step][0]))
		if String(STEPS[_step][0]) != "decoy_hologram":  # the decoy's end is the next step
			_fx.clear_all()
		_next()


func _inside(at: Vector3, radius: float) -> int:
	return _count(func(d: Dummy) -> bool: return d.global_position.distance_to(at) <= radius)


func _report(id: String) -> void:
	var e := _entry(id)
	var hit := _count(func(d: Dummy) -> bool: return d.dmg > 0.0)
	var total := 0.0
	for d in _dummies:
		total += d.dmg
	_log.append("%s: damaged %d, total %.1f" % [id, hit, total])
	match id:
		"fire_trail_dash":
			_expect(_count(func(d: Dummy) -> bool: return d.burned) > 0, "the burning path set someone on it alight")
		"orbital_strike":
			var r := SkillState.value(_db, e, "radius")
			_expect(hit == _inside(AIM, r) and hit > 0, "the beam hit everyone within %.0f m of the mark (%d)" % [r, _inside(AIM, r)])
			_expect(_fx.strikes.pending("orbital") == 0, "the strike is over")
		"shockwave_slam":
			var r := SkillState.value(_db, e, "radius")
			_expect(hit == _inside(Vector3.ZERO, r) and _count(func(d: Dummy) -> bool: return d.frozen) == hit and hit > 0, "slam: everyone within %.0f m hit and stunned" % r)
		"vacuum_pulse":
			var pulled := _count(func(d: Dummy) -> bool: return d.pushes > 0 and d.last_push.dot(-d.global_position) > 0.0)
			_expect(pulled > 0 and pulled == hit, "vacuum: those hit are dragged toward the caster (%d)" % pulled)
		"time_bubble":
			var r := SkillState.value(_db, e, "radius")
			_expect(_count(func(d: Dummy) -> bool: return d.slowed) == _inside(Vector3.ZERO, r), "bubble: everyone inside slowed")
		"rocket_barrage":
			_expect(hit == 12 and _fx.strikes.pending("rocket") == 0, "rockets: all 12 targets hit, none left flying")
		"plague_cloud":
			var r := SkillState.value(_db, e, "radius")
			_expect(hit > 0 and hit == _inside(AIM, r) and _count(func(d: Dummy) -> bool: return d.slowed) == hit, "cloud: everyone inside hurt and slowed")
		"mirror_clone":
			_expect(_fx.summons.active("clone") and total > 0.0, "the clone is up and shooting")
		"meteor_shower":
			_expect(hit > 0 and _fx.strikes.pending("meteor") == 0, "meteors landed, none left")
		"sticky_mines":
			_expect(hit > 0 and _fx.strikes.pending("mine") < roundi(SkillState.value(_db, e, "mines")), "a mine went off when someone came near")
		"sentry_turret":
			_expect(_fx.summons.active("turret") and total > 0.0, "the turret is up and shooting")
		"thunder_totem":
			_expect(hit > 0 and _count(func(d: Dummy) -> bool: return d.vuln > 1.0) > 0, "the totem strikes and shocks")
		"inferno_ring":
			var r := SkillState.value(_db, e, "radius")
			_expect(_count(func(d: Dummy) -> bool: return d.burned) == _inside(Vector3.ZERO, r) and _inside(Vector3.ZERO, r) > 0, "inferno: everyone inside alight")
		"storm_call":
			_expect(hit > 0, "lightning struck")
		"spinning_blades":
			_expect(_fx.summons.active("blades") and hit > 0, "the blades cut someone")
		"ice_lance":
			_expect(hit > 0 and _count(func(d: Dummy) -> bool: return d.frozen) == hit, "the lance hit the line and froze them (%d)" % hit)
		"harpoon_yank":
			var dragged := _count(func(d: Dummy) -> bool: return d.pushes > 0 and d.last_push.dot(-d.global_position) > 0.0)
			_expect(hit == 1 and dragged == 1 and _count(func(d: Dummy) -> bool: return d.frozen) == 1, "harpoon: one enemy hit, dragged in, stunned")
		"war_banner":
			_expect(_fx.near_banner(Vector3(1, 0, 1)) and not _fx.near_banner(Vector3(30, 0, 0)), "the banner's reach")
		"decoy_hologram":
			var drawn := _count(func(d: Dummy) -> bool: return d.target != _player)
			var reach := SkillState.value(_db, e, "reach")
			_expect(drawn > 0 and drawn == _inside(AIM, reach) and _fx.summons.lured() == drawn, "the decoy draws everyone within %.0f m (%d)" % [reach, drawn])
		"decoy_end":
			_expect(not _fx.summons.active("decoy") and _count(func(d: Dummy) -> bool: return d.target != _player) == 0, "the decoy is gone and everyone chases the player again")
			_expect(hit > 0, "the decoy burst")


# core/skill_self.gd: the caster's own effects, worked through by hand.
func _self_rules() -> void:
	var s := SkillSelf.new()
	s.start_storm(0.0, 5.0, 2.5)
	_expect(is_equal_approx(s.rate_mult(1.0), 2.5) and s.free_ammo(1.0) and s.rate_mult(6.0) == 1.0 and not s.free_ammo(6.0), "storm: fire rate and free rounds while it lasts")
	s.start_rush(0.0, 6.0, 40.0, 6.0)
	_expect(is_equal_approx(s.speed_mult(1.0), 1.4) and is_equal_approx(s.leech_pct(1.0), 6.0) and s.speed_mult(7.0) == 1.0, "rush: speed and leech")
	s.start_phase(0.0, 4.0, 3, 2.0)
	var shots: Array[float] = []
	for _n in 4:
		shots.append(s.damage_mult(1.0, false))
		s.on_shot(1.0)
	_expect(shots == [2.0, 2.0, 2.0, 1.0], "phase: three charged shots, then normal %s" % str(shots))
	s.start_clip(0.0, 8.0, 30.0)
	_expect(is_equal_approx(s.damage_mult(1.0, false), 1.3) and s.damage_mult(9.0, false) == 1.0, "full clip: +30 % for 8 s")
	s.start_shield(0.0, 8.0, 50.0)
	var through := s.incoming(30.0, 1.0, false)
	var through2 := s.incoming(30.0, 1.0, false)
	_expect(through == 0.0 and is_equal_approx(through2, 10.0) and s.shield_left(1.0) == 0.0, "overshield soaks 50 then lets the rest through (%.0f, %.0f)" % [through, through2])
	s.start_banner(0.0, 10.0, 20.0, 25.0)
	_expect(is_equal_approx(s.incoming(100.0, 1.0, true), 75.0) and is_equal_approx(s.incoming(100.0, 1.0, false), 100.0), "banner: 25 % less damage taken only near it")
	_expect(is_equal_approx(s.damage_mult(1.0, true), 1.3 * 1.2), "banner: +20 % damage near it (with full clip)")


# Every skill has its icon on the sheet, a colour, a cooldown pair, and the numbers its text names.
func _check_data() -> void:
	var icons: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/icons.json")) as Dictionary)["shapes"]
	var bad: Array[String] = []
	for id: String in _db.skills:
		var def: Dictionary = _db.skills[id]
		if not icons.has(String(def.get("icon", ""))) or (def.get("color", []) as Array).size() != 3 or (def["cooldown"] as Array).size() != 2:
			bad.append(id)
		var text := SkillState.describe(_db, _entry(id))
		if text.contains("{"):
			bad.append(id + " (text)")
	_expect(bad.is_empty() and _db.skills.size() == 30, "30 skills, each with icon, colour, cooldown and filled text %s" % str(bad))


func _finish() -> void:
	_log.append("SKILL_PASS2 problems=%d" % _problems)
	var f := FileAccess.open("res://tools/skill_pass2_check.log", FileAccess.WRITE)
	f.store_string("\n".join(_log) + "\n")
	f.close()
	print("\n".join(_log))
	get_tree().quit()
