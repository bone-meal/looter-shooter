# Purpose: developer check + render of the gun skill effects on stand-in enemies: Nova Burst, Chain Lightning, Frost Pulse, Gravity Well, Swarm Drones. Writes tools/skill_check.log and tools/shots/skill_*.png, then quits. Run scene tools/skill_check.tscn (takes about 15 s).
# Dependencies: game/skill_effects.gd, core/skill_state.gd, core/gun_db.gd, core/health_state.gd, core/data_store.gd.
extends Node3D

const SkillEffects = preload("res://game/skill_effects.gd")
const SkillState = preload("res://core/skill_state.gd")
const GunDb = preload("res://core/gun_db.gd")
const HealthState = preload("res://core/health_state.gd")
const DataStore = preload("res://core/data_store.gd")

const EVENTS := [
	[0.5, "nova"], [0.62, "shot_nova"], [1.0, "report_nova"],
	[1.5, "chain"], [1.6, "shot_chain"], [2.0, "report_chain"],
	[2.5, "frost"], [2.65, "shot_frost"], [3.0, "report_frost"],
	[3.5, "well"], [4.6, "shot_well"], [5.0, "report_pull"], [9.2, "report_well_end"],
	[9.5, "drones"], [11.0, "shot_drones"], [13.0, "report_drones"],
	[13.5, "finish"],
]


# Stand-in for game/enemy.gd: records what skills do to it.
class Dummy extends Node3D:
	var enemy_id := "chaser"
	var health := HealthState.new(100000.0)
	var dmg := 0.0
	var pushes := 0
	var last_push := Vector3.ZERO
	var frozen := false
	var vuln := 1.0

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
		pass

	func reset() -> void:
		dmg = 0.0
		pushes = 0
		frozen = false
		vuln = 1.0


class Crowd extends RefCounted:
	var list: Array = []

	func enemy_list() -> Array:
		return list


var _db: GunDb
var _fx: Node3D
var _crowd := Crowd.new()
var _dummies: Array[Dummy] = []
var _player: Node3D
var _t := 0.0
var _next := 0
var _log: PackedStringArray = []


func _ready() -> void:
	get_window().size = Vector2i(1152, 648)
	_db = GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"))
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.06, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.9)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mesh.mesh = pm
	add_child(floor_mesh)
	_player = Node3D.new()
	add_child(_player)
	for i in 12:
		var d := Dummy.new()
		var angle := deg_to_rad(-40.0 + float(i) * 7.0)
		var dist := 3.0 + float(i)
		d.position = Vector3(sin(angle) * dist, 0.0, -cos(angle) * dist)
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.7, 1.8, 0.7)
		body.mesh = box
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(0.85, 0.25, 0.25)
		body.material_override = paint
		body.position.y = 0.9
		d.add_child(body)
		add_child(d)
		_dummies.append(d)
		_crowd.list.append(d)
	_fx = SkillEffects.new()
	_fx.source = _crowd
	_fx.follow = _player
	add_child(_fx)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 9.0, 9.0)
	add_child(cam)
	cam.look_at(Vector3(0.0, 0.5, -6.0), Vector3.UP)
	cam.current = true


func _process(delta: float) -> void:
	_t += delta
	while _next < EVENTS.size() and _t >= float(EVENTS[_next][0]):
		_run(String(EVENTS[_next][1]))
		_next += 1


func _entry(id: String) -> Dictionary:
	return {"id": id, "q": 1.0}


func _cast(id: String, aim: Vector3 = Vector3(0, 0, -8)) -> void:
	for d in _dummies:
		d.reset()
	_fx.cast(_db, _entry(id), 10.0, Vector3.ZERO, Vector3(0, 1.6, 0), Vector3(0, 0, -1), aim)


func _count(pred: Callable) -> int:
	var n := 0
	for d in _dummies:
		if pred.call(d):
			n += 1
	return n


func _run(what: String) -> void:
	match what:
		"nova":
			_cast("nova_burst")
		"chain":
			_cast("chain_lightning")
		"frost":
			_cast("frost_pulse")
		"well":
			_cast("gravity_well")
		"drones":
			_cast("swarm_drones")
		"report_nova":
			var radius := SkillState.value(_db, _entry("nova_burst"), "radius")
			var inside := _count(func(d: Dummy) -> bool: return d.global_position.length() <= radius)
			var hit := _count(func(d: Dummy) -> bool: return d.dmg > 0.0)
			var pushed := _count(func(d: Dummy) -> bool: return d.pushes > 0)
			_log.append("nova (radius %.1f): enemies inside %d, damaged %d, pushed %d, damage each %.1f (expected 10 x damage mult)" % [radius, inside, hit, pushed, _dummies[0].dmg])
			_log.append("  nova ok: %s" % (inside == hit and inside == pushed and inside > 0))
		"report_chain":
			var hit := _count(func(d: Dummy) -> bool: return d.dmg > 0.0)
			var vuln := _count(func(d: Dummy) -> bool: return d.vuln > 1.0)
			_log.append("chain lightning: enemies hit %d (jumps+1 = %d), marked vulnerable %d, first %.1f, last hit %.1f" % [hit, roundi(SkillState.value(_db, _entry("chain_lightning"), "jumps")) + 1, vuln, _dummies[_first_hit()].dmg, _last_dmg()])
			_log.append("  chain ok: %s" % (hit > 3 and hit == vuln))
		"report_frost":
			var radius := SkillState.value(_db, _entry("frost_pulse"), "radius")
			var inside := _count(func(d: Dummy) -> bool: return d.global_position.length() <= radius)
			var frozen := _count(func(d: Dummy) -> bool: return d.frozen)
			var vuln := _count(func(d: Dummy) -> bool: return d.vuln > 1.0)
			_log.append("frost pulse (radius %.1f): inside %d, frozen %d, vulnerable %d (x%.2f)" % [radius, inside, frozen, vuln, _dummies[0].vuln])
			_log.append("  frost ok: %s" % (inside == frozen and inside == vuln and inside > 0))
		"report_pull":
			var pulled := 0
			for d in _dummies:
				var toward := Vector3(0, 0, -8) - d.global_position
				toward.y = 0.0
				if d.pushes > 0 and d.last_push.dot(toward) > 0.0:
					pulled += 1
			_log.append("gravity well after 1.5 s: enemies pulled toward the orb %d, wells active %d" % [pulled, _fx.active_wells()])
			_log.append("  pull ok: %s" % (pulled > 0 and _fx.active_wells() == 1))
		"report_well_end":
			_log.append("gravity well ended (5 s): wells active %d" % _fx.active_wells())
			_log.append("  well end ok: %s" % (_fx.active_wells() == 0))
		"report_drones":
			var total := 0.0
			for d in _dummies:
				total += d.dmg
			_log.append("swarm drones after 3.5 s: drones %d, total damage %.1f" % [_fx.drone_count(), total])
			_log.append("  drones ok: %s" % (_fx.drone_count() == 4 and total > 0.0))
		"finish":
			var f := FileAccess.open("res://tools/skill_check.log", FileAccess.WRITE)
			f.store_string("\n".join(_log))
			f.close()
			get_tree().quit()
		_:
			if what.begins_with("shot_"):
				get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://tools/shots/skill_%s.png" % what.substr(5)))


func _first_hit() -> int:
	for i in _dummies.size():
		if _dummies[i].dmg > 0.0:
			return i
	return 0


func _last_dmg() -> float:
	var last := 0.0
	for d in _dummies:
		if d.dmg > 0.0:
			last = d.dmg
	return last
