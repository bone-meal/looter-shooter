# Purpose: ANGLER LIGHT's red-text behaviour (diary/DESIGN_UNIQUES.md, region 6 chase gun): an anglerfish lure hangs
# from the pistol, its bulb glowing with a small light (game/unique_attach.gd lights it for data "angler": true, on
# every machine). Enemies near drift toward the light, into your sights: every drift_every seconds each living,
# non-boss enemy within reach is nudged toward the lure (a puppet's nudge goes to the host, game/enemy.gd push).
# Numbers in data/gun_uniques.json angler_light "cfg".
# Dependencies: the holder's explosives (enemy source); the "Lure" node of the angler_lure model.
extends Node3D

var _player: Node3D
var _cfg: Dictionary = {}
var _lure: Node3D
var _next := 0.0
var nudged := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_lure = gimmick.find_child("Lure", true, false) as Node3D if gimmick != null else null


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


func _process(_delta: float) -> void:
	if _lure != null and is_instance_valid(_lure):
		_lure.rotation.x = sin(Time.get_ticks_msec() * 0.003) * 0.25  # the bulb sways
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next or _player == null:
		return
	_next = now + float(_cfg.get("drift_every", 0.5))
	drift()


# One nudge of every enemy in reach toward the light.
func drift() -> void:
	var light := _lure.global_position if _lure != null and is_instance_valid(_lure) and _lure.is_inside_tree() else _player.global_position
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	if source == null:
		return
	for enemy: Node3D in source.call("enemy_list"):
		if not is_instance_valid(enemy) or enemy.health.is_dead() or String(enemy.get("enemy_id")).begins_with("boss"):
			continue
		var flat := Vector3(light.x - enemy.global_position.x, 0.0, light.z - enemy.global_position.z)
		var d := flat.length()
		if d > float(_cfg.get("reach", 14.0)) or d < float(_cfg.get("stop_at", 3.0)):
			continue
		enemy.call("push", flat.normalized() * float(_cfg.get("drift", 3.0)))
		nudged += 1
