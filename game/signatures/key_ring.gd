# Purpose: KEY RING's red-text behaviour (diary/DESIGN_UNIQUES.md, Vault chase gun): a jangling ring of keys hangs from
# the pistol. Every kill adds a key (nodes "Key1".."Key9" of the key_ring model show how many, up to 9). With enough
# keys (open_cost), shooting anything locked (a node in group "locked" with on_hit and unlock()) opens it and spends
# them. The jingle is loud: every jingle_every seconds, enemies within jingle_reach (+ per key) turn on the holder
# (set_target). Others see the keys (held_suffix "k0".."k9"). Nothing in the game is locked yet: chests and doors of
# the sea world (step 9) are to join group "locked".
# Numbers in data/gun_uniques.json key_ring "cfg".
# Dependencies: the holder's explosives (enemy source); the key_ring gimmick.
extends Node3D

var _player: Node3D
var _cfg: Dictionary = {}
var _gimmick: Node3D
var keys := 0
var opened := 0
var drawn := 0
var _next_jingle := 0.0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_gimmick = gimmick
	show_keys(_gimmick, keys)


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


func on_target_hit(target: Node, _at: Vector3, _amount: float, killed: bool) -> void:
	if target.is_in_group("locked") and keys >= int(_cfg.get("open_cost", 5)) and target.has_method("unlock"):
		target.call("unlock")
		keys -= int(_cfg.get("open_cost", 5))
		opened += 1
	elif killed:
		keys = mini(9, keys + 1)
	show_keys(_gimmick, keys)


func held_suffix() -> String:
	return "k%d" % keys


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if keys <= 0 or now < _next_jingle or _player == null:
		return
	_next_jingle = now + float(_cfg.get("jingle_every", 3.0))
	jingle()


# The keys rattle: enemies in earshot come for the holder.
func jingle() -> void:
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	if source == null:
		return
	var reach := float(_cfg.get("jingle_reach", 10.0)) + float(keys) * float(_cfg.get("reach_per_key", 2.0))
	for enemy: Node3D in source.call("enemy_list"):
		if is_instance_valid(enemy) and not enemy.health.is_dead() and enemy.global_position.distance_to(_player.global_position) <= reach and enemy.has_method("set_target"):
			enemy.call("set_target", _player)
			drawn += 1


static func show_keys(piece: Node3D, count: int) -> void:
	if piece == null or not is_instance_valid(piece):
		return
	for k in 9:
		var key := piece.find_child("Key%d" % (k + 1), true, false) as Node3D
		if key != null:
			key.visible = k < count
