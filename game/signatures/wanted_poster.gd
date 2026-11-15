# Purpose: WANTED POSTER's red-text behaviour (diary/DESIGN_UNIQUES.md, raid chase gun): a poster pinned to the sniper's
# stock shows one enemy (Label3D on the "Poster" marker). That enemy is marked over its head ("WANTED", seen through
# walls) for the holder and every teammate (game/net_chase.gd "wanted" / "wanted_off": each machine marks the enemy
# nearest that spot). Killing it with this gun pays a bounty: chips (the session's wallet) and every skill cooldown
# refreshed; a new face goes up after new_after seconds. If someone else gets it, a new one is picked.
# Numbers in data/gun_uniques.json wanted_poster "cfg".
# Dependencies: the holder's explosives (enemy source), skills, damage numbers; the session (group "game_session",
# wallet) for chips.
extends Node3D

const MARK := "wanted_mark"

var _player: Node3D
var _cfg: Dictionary = {}
var _label: Label3D
var _wanted: Node3D
var _next_pick := 0.0
var bounties := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_label = poster_label(gimmick)
	_write()


func stop() -> void:
	_unmark(true)


func on_inspect() -> void:
	pass


func wanted() -> Node3D:
	return _wanted if _wanted != null and is_instance_valid(_wanted) else null


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if wanted() != null and wanted().health.is_dead():
		_unmark(true)
		_next_pick = now + float(_cfg.get("new_after", 3.0))
	if wanted() == null and now >= _next_pick:
		_next_pick = now + 1.0
		pick()


# Puts a new face on the poster: a random living enemy in reach.
func pick() -> void:
	var source: Variant = _player.get("explosives").get("source") if _player.get("explosives") != null else null
	if source == null:
		return
	var choices: Array = []
	for enemy: Node3D in source.call("enemy_list"):
		if is_instance_valid(enemy) and not enemy.health.is_dead() and enemy.global_position.distance_to(_player.global_position) <= float(_cfg.get("reach", 60.0)):
			choices.append(enemy)
	if choices.is_empty():
		return
	_wanted = choices[randi() % choices.size()]
	mark(_wanted)
	_write()
	_tell("wanted", _wanted.global_position)


func on_target_hit(target: Node, at: Vector3, _amount: float, killed: bool) -> void:
	if not killed or target != wanted():
		return
	bounties += 1
	var chips := int(_cfg.get("chips", 50))
	var session: Node = get_tree().get_first_node_in_group("game_session")
	if session != null and session.has_method("wallet"):
		session.call("wallet").call("add", chips)
	var skills: Variant = _player.get("skills")
	if skills != null:
		skills.call("reduce_all", 9999.0, Time.get_ticks_msec() / 1000.0)
	var numbers: Variant = _player.get("damage_numbers")
	if numbers != null and (numbers as Object).has_method("say"):
		numbers.call("say", at + Vector3(0, 0.5, 0), "BOUNTY +%d" % chips, Color(1.0, 0.85, 0.3))
	_unmark(true)
	_next_pick = Time.get_ticks_msec() / 1000.0 + float(_cfg.get("new_after", 3.0))


func _unmark(tell: bool) -> void:
	if wanted() != null:
		unmark(wanted())
		if tell:
			_tell("wanted_off", wanted().global_position)
	_wanted = null
	_write()


func _write() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	var who := String(wanted().get("enemy_id")).capitalize() if wanted() != null else "???"
	_label.text = "WANTED\n%s\n%d CHIPS" % [who, int(_cfg.get("chips", 50))]


func _tell(kind: String, at: Vector3) -> void:
	var link: Node = get_tree().get_first_node_in_group("net_chase")
	if link != null:
		link.call("send", kind, -1, at, 0, at)


# The red WANTED sign over an enemy's head (seen through walls); also on other machines.
static func mark(enemy: Node3D) -> void:
	if enemy == null or enemy.has_node(MARK):
		return
	var sign := Label3D.new()
	sign.name = MARK
	sign.text = "WANTED"
	sign.font_size = 48
	sign.pixel_size = 0.01
	sign.outline_size = 12
	sign.modulate = Color(1.0, 0.25, 0.2)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign.no_depth_test = true
	sign.fixed_size = false
	sign.position = Vector3(0, 2.6, 0)
	enemy.add_child(sign)


static func unmark(enemy: Node3D) -> void:
	if enemy != null and enemy.has_node(MARK):
		enemy.get_node(MARK).queue_free()


static func poster_label(piece: Node3D) -> Label3D:
	var spot := piece.find_child("Poster", true, false) as Node3D if piece != null else null
	if spot == null:
		return null
	var label := Label3D.new()
	label.font_size = 64
	label.pixel_size = 0.00017
	label.outline_size = 0
	label.modulate = Color(0.25, 0.12, 0.05)
	label.rotation_degrees = Vector3(0, -90, 0)
	label.shaded = false
	label.double_sided = false
	spot.add_child(label)
	return label
