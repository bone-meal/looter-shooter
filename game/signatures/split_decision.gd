# Purpose: SPLIT DECISION's red-text behaviour (diary/DESIGN_UNIQUES.md, Vault chase gun): two barrel shrouds under the
# rifle, one fire and one ice, and a coin spinning on top (node "Coin") that picks each shot. A FIRE shot sets its target
# burning, an ICE shot slows it; an enemy hit by both within both_within seconds SHATTERS (shatter x gun damage,
# "SHATTER", shards on every machine via game/net_chase.gd "shatter"). Others see the coin's face (held_suffix "f" /
# "i"; game/unique_attach.gd show_extra).
# Numbers in data/gun_uniques.json split_decision "cfg".
# Dependencies: the holder's weapon, damage numbers; the split_barrels gimmick ("Coin").
extends Node3D

const FxKit = preload("res://game/fx_kit.gd")

var _player: Node3D
var _cfg: Dictionary = {}
var _coin: Node3D
var fire := true  # what the next shot is
var _spin := 0.0
var shatters := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_coin = gimmick.find_child("Coin", true, false) as Node3D if gimmick != null else null
	fire = randf() < 0.5
	show_coin(_coin, fire)


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


# After each shot the coin is flipped for the next one.
func on_fired() -> void:
	fire = randf() < 0.5
	_spin = 0.25


func held_suffix() -> String:
	return "f" if fire else "i"


func on_target_hit(target: Node, at: Vector3, _amount: float, killed: bool) -> void:
	if killed:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var dmg := float(_player.get("weapon").damage)
	if fire:
		if target.has_method("apply_burn"):
			target.call("apply_burn", dmg * float(_cfg.get("burn_share", 0.4)), float(_cfg.get("burn_seconds", 3.0)))
		target.set_meta("split_fire", now)
	else:
		if target.has_method("apply_slow"):
			target.call("apply_slow", float(_cfg.get("slow", 0.5)), float(_cfg.get("slow_seconds", 2.0)))
		target.set_meta("split_ice", now)
	var within := float(_cfg.get("both_within", 4.0))
	if now - float(target.get_meta("split_fire", -99.0)) <= within and now - float(target.get_meta("split_ice", -99.0)) <= within:
		target.remove_meta("split_fire")
		target.remove_meta("split_ice")
		var dealt := dmg * float(_cfg.get("shatter", 10.0))
		target.call("on_hit", dealt, at, Vector3.UP)
		shatters += 1
		var numbers: Variant = _player.get("damage_numbers")
		if numbers != null and (numbers as Object).has_method("say"):
			numbers.call("say", at + Vector3(0, 0.4, 0), "SHATTER", Color(0.75, 0.9, 1.0))
		shards(_player.get_parent(), at)
		var link: Node = get_tree().get_first_node_in_group("net_chase")
		if link != null:
			link.call("send", "shatter", -1, at, 0, at)


func _process(delta: float) -> void:
	if _coin == null or not is_instance_valid(_coin):
		return
	if _spin > 0.0:
		_spin -= delta
		_coin.rotation.x += delta * 40.0
	else:
		show_coin(_coin, fire)


# The coin settles red (fire) or blue (ice) toward the shooter (also another player's copy).
static func show_coin(coin: Node3D, is_fire: bool) -> void:
	if coin != null and is_instance_valid(coin):
		coin.rotation.x = PI if is_fire else 0.0


# Ice and ember shards bursting from a shattered enemy (a picture).
static func shards(world: Node, at: Vector3) -> void:
	if world == null:
		return
	FxKit.burst(world, at, Color(0.8, 0.93, 1.0), 14, 0.6, 0.18, 4.0)  # frost and sparks
	for k in 10:  # modelled ice and ember splinters (game/fx_kit.gd shard)
		var bit: Node3D = FxKit.shape("shard")
		if bit == null:
			return
		FxKit.paint(bit, FxKit.glow(Color(0.65, 0.88, 1.0) if k % 2 == 0 else Color(1.0, 0.5, 0.15)))
		world.add_child(bit)
		bit.global_position = at
		bit.rotation = Vector3(randf() * TAU, randf() * TAU, 0.0)
		bit.scale = Vector3.ONE * randf_range(2.5, 4.0)
		var away := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized() * randf_range(1.0, 2.2)
		var tween := bit.create_tween()
		tween.tween_property(bit, "global_position", at + away, 0.35).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(bit, "scale", Vector3.ONE * 0.05, 0.45)
		tween.parallel().tween_property(bit, "rotation", bit.rotation + Vector3(randf_range(3, 8), randf_range(3, 8), 0), 0.45)
		tween.tween_callback(bit.queue_free)
