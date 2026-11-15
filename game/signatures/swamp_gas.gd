# Purpose: SWAMP GAS's red-text behaviour (diary/DESIGN_UNIQUES.md, region 2 chase gun): a jar of swamp water strapped
# to the shotgun bubbles; every shot burps a cloud of gas where the shot went (a few metres out, or short of a wall);
# any fire sets the clouds off in a chain (game/swamp_gas.gd). The clouds stay in the world after the gun is put away.
# Dependencies: game/swamp_gas.gd; the holder's explosives and weapon; the jar's "Bubbles" node on the gimmick.
extends Node3D

const SwampGas = preload("res://game/swamp_gas.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _bubbles: Node3D
var _bubbles_base := Vector3.ZERO
var _t := 0.0
var _query := PhysicsRayQueryParameters3D.new()


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_bubbles = gimmick.find_child("Bubbles", true, false) as Node3D if gimmick != null else null
	if _bubbles != null:
		_bubbles_base = _bubbles.position


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


# After a shot from `origin` along `dir`: the gun burps a cloud where the shot went.
func after_shot(origin: Vector3, dir: Vector3) -> void:
	var reach := float(_cfg.get("cloud_reach", 5.0))
	_query.from = origin
	_query.to = origin + dir * reach
	_query.exclude = [(_player as CollisionObject3D).get_rid()] if _player is CollisionObject3D else []
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(_query)
	var at: Vector3 = (hit.position as Vector3) - dir * 0.6 if not hit.is_empty() else origin + dir * reach
	var gas := pool()
	if gas != null:
		gas.puff(at, _cfg, float(_player.get("weapon").damage))


func pool() -> SwampGas:
	var found := get_tree().get_first_node_in_group("swamp_gas") as SwampGas
	if found == null and _player != null and _player.get_parent() != null:
		found = SwampGas.new()
		found.name = "SwampGas"
		_player.get_parent().add_child(found)
	if found != null:
		found.explosives = _player.get("explosives")
	return found


func _process(delta: float) -> void:
	_t += delta
	if _bubbles != null and is_instance_valid(_bubbles):  # the swamp water bubbles in its jar
		_bubbles.position = _bubbles_base + Vector3(0.0, fmod(_t * 0.012, 0.004), sin(_t * 1.7) * 0.004)
