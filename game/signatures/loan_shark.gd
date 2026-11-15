# Purpose: LOAN SHARK's red-text behaviour (diary/DESIGN_UNIQUES.md, raid chase gun): a small shark in a fishbowl under
# the pistol. The magazine never runs dry: a shot that empties it is refilled with a BORROWED round, and each borrowed
# round costs cost_share of max health, more as the debt grows (x (1 + debt / interest_every); it never takes the last
# point of health). The shark grows with the debt (node "Shark"); every kill pays back repay_per_kill rounds. Others
# see the shark's size (held_suffix "s0".."s9"; game/unique_attach.gd show_extra).
# Numbers in data/gun_uniques.json loan_shark "cfg".
# Dependencies: the holder's weapon (ammo) and health; the fishbowl gimmick ("Shark").
extends Node3D

var _player: Node3D
var _cfg: Dictionary = {}
var _shark: Node3D
var debt := 0
var borrowed := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_shark = gimmick.find_child("Shark", true, false) as Node3D if gimmick != null else null
	show_shark(_shark, debt, int(_cfg.get("full_size_at", 60)))


func stop() -> void:
	pass


func on_inspect() -> void:
	pass


# After every shot: an empty magazine gets a borrowed round.
func on_fired() -> void:
	var w: Variant = _player.get("weapon")
	if w == null or int(w.get("ammo")) > 0:
		return
	w.set("ammo", 1)
	debt += 1
	borrowed += 1
	var health: Variant = _player.get("health")
	if health != null:
		var cost := float(health.get("max_hp")) * float(_cfg.get("cost_share", 0.01)) * (1.0 + float(debt) / float(_cfg.get("interest_every", 25)))
		health.set("hp", maxf(1.0, float(health.get("hp")) - cost))
	show_shark(_shark, debt, int(_cfg.get("full_size_at", 60)))


func on_target_hit(_target: Node, _at: Vector3, _amount: float, killed: bool) -> void:
	if killed and debt > 0:
		debt = maxi(0, debt - int(_cfg.get("repay_per_kill", 5)))
		show_shark(_shark, debt, int(_cfg.get("full_size_at", 60)))


func held_suffix() -> String:
	return "s%d" % mini(9, int(float(debt) / float(int(_cfg.get("full_size_at", 60))) * 9.0 + 0.999)) if debt > 0 else "s0"


# The shark's size for a debt (also another player's copy: `debt` = the 0..9 step times full / 9).
static func show_shark(shark: Node3D, owed: int, full_at: int) -> void:
	if shark == null or not is_instance_valid(shark):
		return
	shark.scale = Vector3.ONE * (1.0 + clampf(float(owed) / float(maxi(full_at, 1)), 0.0, 1.0) * 1.4)
	shark.rotation.y = Time.get_ticks_msec() * 0.0015  # it circles the bowl
