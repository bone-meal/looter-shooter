# Purpose: TREASURE MAP's red-text behaviour (diary/DESIGN_UNIQUES.md, Vault chase gun): a rolled map is tied to the
# rifle. Every map_every seconds while it is in hand an X appears somewhere 15-40 m away on the ground
# (game/treasure_x.gd), seen by the whole party (game/net_chase.gd "treasure"). Standing on an X, the INSPECT key digs it
# up with the gun's stock: a rolled gun drops there (luck / lowest tier / item level in data cfg; this machine's loot
# field, like any drop) and the X is gone for everyone ("treasure_gone"). At most max_marks Xs at once.
# Numbers in data/gun_uniques.json treasure_map "cfg".
# Dependencies: game/treasure_x.gd, core/gun_gen.gd; the session (group "game_session": `_field` loot field).
extends Node3D

const TreasureX = preload("res://game/treasure_x.gd")
const GunGen = preload("res://core/gun_gen.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _gun: Dictionary = {}
var _next := 0.0
var _slot := 0
var dug := 0


func bind(player: Node3D, gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_gun = gun
	_cfg = def.get("cfg", {})
	_next = Time.get_ticks_msec() / 1000.0 + float(_cfg.get("map_every", 60.0))


func start(_gimmick: Node3D) -> void:
	pass


func stop() -> void:
	pass


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next and _player != null:
		_next = now + float(_cfg.get("map_every", 60.0))
		mark_new()


# A new X somewhere near on the ground.
func mark_new() -> Node3D:
	var space := _player.get_world_3d().direct_space_state
	for _try in 12:
		var a := randf() * TAU
		var d := randf_range(float(_cfg.get("near", 15.0)), float(_cfg.get("far", 40.0)))
		var top := _player.global_position + Vector3(cos(a) * d, 30.0, sin(a) * d)
		var query := PhysicsRayQueryParameters3D.create(top, top + Vector3(0, -60.0, 0), 1)
		var hit := space.intersect_ray(query)
		if hit.is_empty() or (hit.normal as Vector3).y < 0.7 or (hit.collider as Object).has_method("on_hit"):
			continue
		var mine := _mine()
		if mine.size() >= int(_cfg.get("max_marks", 3)):
			_remove(mine[0])
		_slot = (_slot + 1) % 64
		var x := place(_player.get_parent(), hit.position, 0, _slot)
		_tell("treasure", _slot, hit.position)
		return x
	return null


# Digs up an X under the holder: true if there was one.
func on_inspect() -> void:
	dig()


func dig() -> bool:
	for x: Node3D in _mine():
		if Vector2(x.global_position.x - _player.global_position.x, x.global_position.z - _player.global_position.z).length() <= float(_cfg.get("dig_reach", 2.5)):
			var at := x.global_position
			_remove(x)
			dug += 1
			var rng := RandomNumberGenerator.new()
			rng.randomize()
			var db: RefCounted = _player.get("gun_db")
			var loot := GunGen.generate(db, rng, float(_cfg.get("luck", 3.0)), "", "", String(_cfg.get("min_tier", "blue")), int(_gun.get("lvl", 1)))
			var session: Node = get_tree().get_first_node_in_group("game_session")
			var field: Variant = session.get("_field") if session != null else null
			if field != null and not loot.is_empty():
				field.call("spawn", loot, at + Vector3(0, 0.3, 0))
			var numbers: Variant = _player.get("damage_numbers")
			if numbers != null and (numbers as Object).has_method("say"):
				numbers.call("say", at + Vector3(0, 1.2, 0), "TREASURE!", Color(1.0, 0.85, 0.3))
			return true
	return false


func _mine() -> Array:
	var out: Array = []
	for x: Node in get_tree().get_nodes_in_group(TreasureX.GROUP):
		if int(x.get("owner_id")) == 0:
			out.append(x)
	return out


func _remove(x: Node3D) -> void:
	_tell("treasure_gone", int(x.get("slot")), x.global_position)
	x.queue_free()


func _tell(kind: String, slot: int, at: Vector3) -> void:
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", kind, slot, at, 0, at)


# An X in the world (ours: owner 0; another player's: his peer id).
static func place(world: Node, at: Vector3, owner: int, slot_no: int) -> Node3D:
	if world == null:
		return null
	var x := TreasureX.new()
	x.owner_id = owner
	x.slot = slot_no
	world.add_child(x)
	x.global_position = at
	return x
