# Purpose: CROAK's red-text behaviour (diary/DESIGN_UNIQUES.md, region 2 chase gun): a frog sits on the rifle's scope
# and blinks. While it rides along on the gun its holder can jump a second time in the air. Every 5th kill it leaps
# onto the nearest living enemy's head and croaks: that enemy is marked (+30 % damage taken) while the frog rides it;
# when the enemy dies (or after a while) the frog hops back onto the gun. Numbers in data/gun_uniques.json croak "cfg".
# Others see the frog leap and ride through game/net_chase.gd.
# Dependencies: assets/models/weapons/uniques/croak_frog.gltf (the leaping frog), the gun's gimmick with its "Lids"
# node (game/unique_attach.gd), the holder's explosives.source enemy_list() and damage_numbers.
extends Node3D

const FROG := "res://assets/models/weapons/uniques/croak_frog.gltf"
enum { ON_GUN, LEAPING, RIDING, COMING_BACK }

var _player: Node3D
var _cfg: Dictionary = {}
var _gimmick: Node3D  # the frog on the scope
var _lids: Node3D
var _frog: Node3D  # the frog that leaves the gun
var _state := ON_GUN
var _kills := 0
var _target: Node3D
var _t := 0.0  # seconds into the current leap / ride
var _from := Vector3.ZERO
var _next_blink := 2.0
var _blink_left := 0.0
var _mark_left := 0.0
var _tell_left := 0.0  # seconds to the next "where my frog is" for the other players (game/net_chase.gd)


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_gimmick = gimmick
	_lids = gimmick.find_child("Lids", true, false) as Node3D if gimmick != null else null
	if _lids != null:
		_lids.visible = false
	_state = ON_GUN
	_kills = 0


func stop() -> void:
	if _frog != null:
		_frog.queue_free()
		_frog = null
	if _state != ON_GUN:
		_tell("frog_off", Vector3.ZERO)
	_state = ON_GUN


func on_inspect() -> void:
	_blink_left = 0.6  # it gives you a long, slow blink


# Air jumps the holder may make now: one while the frog rides along on the gun.
func extra_jumps() -> int:
	return int(_cfg.get("air_jumps", 1)) if _state == ON_GUN else 0


func on_hit_total(at: Vector3, amount: float, killed: bool) -> float:
	if killed and _state == ON_GUN:
		_kills += 1
		if _kills >= int(_cfg.get("every", 5)):
			_leap(at)
	return amount


func frog_state() -> int:
	return _state


func marked() -> Node3D:
	return _target if _state == RIDING else null


func _process(delta: float) -> void:
	_blink(delta)
	if _state != ON_GUN and _frog != null:
		_tell_left -= delta
		if _tell_left <= 0.0:
			_tell_left = 0.2
			_tell("frog", _frog.global_position)
	match _state:
		LEAPING:
			_t += delta
			var flight := float(_cfg.get("leap_seconds", 0.45))
			if not _alive(_target):
				_come_back()
				return
			var head := _head_of(_target)
			var k := clampf(_t / flight, 0.0, 1.0)
			_frog.global_position = _from.lerp(head, k) + Vector3.UP * sin(k * PI) * float(_cfg.get("leap_height", 1.2))
			_face(_frog, head - _from)
			if k >= 1.0:
				_state = RIDING
				_t = 0.0
				_mark_left = 0.0
				_say(head, "CROAK")
		RIDING:
			_t += delta
			if not _alive(_target) or _t >= float(_cfg.get("ride_seconds", 20.0)):
				_come_back()
				return
			_frog.global_position = _head_of(_target)
			_mark_left -= delta
			if _mark_left <= 0.0 and _target.has_method("apply_vulnerable"):
				_target.call("apply_vulnerable", 1.0 + float(_cfg.get("mark", 0.3)), 1.5)
				_mark_left = 1.0
		COMING_BACK:
			_t += delta
			var back := float(_cfg.get("leap_seconds", 0.45))
			var home := _gimmick.global_position if _gimmick != null and is_instance_valid(_gimmick) else _player.global_position
			var k := clampf(_t / back, 0.0, 1.0)
			_frog.global_position = _from.lerp(home, k) + Vector3.UP * sin(k * PI) * 0.8
			if k >= 1.0:
				_frog.visible = false
				if _gimmick != null and is_instance_valid(_gimmick):
					_gimmick.visible = true
				_state = ON_GUN
				_kills = 0
				_tell("frog_off", Vector3.ZERO)


func _leap(near: Vector3) -> void:
	var best: Node3D = null
	var best_d := float(_cfg.get("reach", 40.0))
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	if source == null:
		return
	for enemy: Node3D in source.call("enemy_list"):
		if not _alive(enemy):
			continue
		var d := enemy.global_position.distance_to(near)
		if d < best_d:
			best = enemy
			best_d = d
	if best == null:
		return  # nobody to ride: it stays put and counts on
	_target = best
	_ensure_frog()
	_from = _gimmick.global_position if _gimmick != null and is_instance_valid(_gimmick) else _player.global_position
	_frog.global_position = _from
	_frog.visible = true
	if _gimmick != null and is_instance_valid(_gimmick):
		_gimmick.visible = false
	_state = LEAPING
	_t = 0.0


func _come_back() -> void:
	_target = null
	if _frog == null:
		_state = ON_GUN
		return
	_from = _frog.global_position
	_state = COMING_BACK
	_t = 0.0


func _ensure_frog() -> void:
	if _frog != null:
		return
	if ResourceLoader.exists(FROG):
		_frog = (load(FROG) as PackedScene).instantiate() as Node3D
	else:
		_frog = MeshInstance3D.new()
		(_frog as MeshInstance3D).mesh = SphereMesh.new()
		_frog.scale = Vector3.ONE * 0.03
	_frog.scale *= float(_cfg.get("frog_scale", 1.6))  # a touch bigger off the gun, so it reads on a head
	_player.get_parent().add_child(_frog)
	_frog.top_level = true


func _blink(delta: float) -> void:
	if _lids == null or not is_instance_valid(_lids):
		return
	if _blink_left > 0.0:
		_blink_left -= delta
		_lids.visible = true
		return
	_lids.visible = false
	_next_blink -= delta
	if _next_blink <= 0.0:
		_blink_left = 0.12
		_next_blink = randf_range(2.0, 5.0)


func _alive(enemy: Node3D) -> bool:
	return enemy != null and is_instance_valid(enemy) and enemy.is_inside_tree() and not enemy.health.is_dead()


func _head_of(enemy: Node3D) -> Vector3:
	return enemy.global_position + Vector3(0, float(enemy.call("head_height")) + 0.02, 0)


func _face(node: Node3D, dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	if flat.length_squared() > 0.0001:
		node.look_at(node.global_position - flat, Vector3.UP)  # the frog's front is +f, look_at aims -z


func _say(at: Vector3, words: String) -> void:
	var numbers: Variant = _player.get("damage_numbers")
	if numbers is Node:
		(numbers as Node).call("say", at, words, Color(0.45, 0.95, 0.35))



func _tell(kind: String, at: Vector3) -> void:
	var link: Node = get_tree().get_first_node_in_group("net_chase") if is_inside_tree() else null
	if link != null:
		link.call("send", kind, -1, at)
