# Purpose: LIGHTHOUSE IN A BOTTLE's red-text behaviour (diary/DESIGN_UNIQUES.md, region 7 chase gun): a tiny lighthouse
# in a corked bottle on the rocket launcher. While it is in hand its beam sweeps round the holder (game/lighthouse_beam.gd):
# enemies it passes burn, teammates it passes heal (each teammate's own machine shows the beam and heals him: data
# "beam": true makes game/unique_attach.gd give other players' copies a beam).
# Numbers in data/gun_uniques.json lighthouse "cfg".
# Dependencies: game/lighthouse_beam.gd; the holder's explosives (enemy source) and weapon.
extends Node3D

const Beam = preload("res://game/lighthouse_beam.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _beam: Node3D


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	if gimmick == null:
		return
	_beam = make_beam(gimmick, _cfg, true)
	_beam.set("explosives", _player.get("explosives"))
	_beam.set("damage_per_second", float(_player.get("weapon").damage) * float(_cfg.get("burn_share", 0.1)))


func stop() -> void:
	if _beam != null and is_instance_valid(_beam):
		_beam.queue_free()
	_beam = null


func on_inspect() -> void:
	pass


func beam() -> Node3D:
	return _beam


static func make_beam(gimmick: Node3D, cfg: Dictionary, owned: bool) -> Node3D:
	var b := Beam.new()
	b.owned = owned
	b.reach = float(cfg.get("reach", 12.0))
	b.sweep_seconds = float(cfg.get("sweep_seconds", 3.0))
	b.burn_seconds = float(cfg.get("burn_seconds", 3.0))
	b.heal_share = float(cfg.get("heal_share", 0.04))
	gimmick.add_child(b)
	return b
