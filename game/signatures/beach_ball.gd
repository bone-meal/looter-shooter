# Purpose: BEACH BALL BOMBARDIER's red-text behaviour (diary/DESIGN_UNIQUES.md, region 1 chase gun): the launcher
# fires beach balls instead of grenades (game/beach_balls.gd: head bounces that hit, shoot one to pop it, walk into
# one to kick it, kicks make the pop bigger). The balls live in the world, so they keep flying after the gun is put away.
# Dependencies: game/beach_balls.gd; the holder's `explosives` (game/explosives.gd), `weapon` and aim_flat().
extends Node3D

const BeachBalls = preload("res://game/beach_balls.gd")

var _player: Node3D
var _cfg: Dictionary = {}


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(_gimmick: Node3D) -> void:
	pass


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


# Instead of a grenade: a beach ball from `origin` along `dir` (stats = the weapon's projectile block: its blast radius).
func fire_projectile(origin: Vector3, dir: Vector3, stats: Dictionary) -> void:
	var balls := pool()
	if balls == null:
		return
	balls.launch(origin, dir, _cfg, float(_player.get("weapon").damage), float(stats.get("splash_radius", 4.0)))


# The world's ball pool (made on first use, next to the player in the world).
func pool() -> BeachBalls:
	var found := get_tree().get_first_node_in_group("beach_balls") as BeachBalls
	if found == null and _player != null and _player.get_parent() != null:
		found = BeachBalls.new()
		found.name = "BeachBalls"
		_player.get_parent().add_child(found)
	if found != null:
		found.explosives = _player.get("explosives")
		found.kicker = _player
	return found
