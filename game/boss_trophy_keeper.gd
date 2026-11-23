# Purpose: the player's boss TROPHIES in play (polish1 E4, items 131 / 133): keeps the locker (owned + worn, saved
# "boss_trophies"), puts the worn pieces into the look (appearance "boss_trophies": everyone online sees them), answers
# the Trophies tab, and pays a boss kill: the boss's own trophy the first time this player beats it (phantom or not),
# and from a phantom a rare ghost trophy or a spectral piece (chances in data/fantasy/enemies.json "phantom").
# Every machine pays its own player (like drops). Returns the lines the vanquished banner shows.
# Dependencies: core/boss_trophy_locker.gd, game/appearance_data.gd (trophies()), game/boss_trophy_tab.gd; the session
# hands in the player, HUD, chat, sounds and the save / look callables.
extends RefCounted

const AppearanceData = preload("res://game/appearance_data.gd")
const BossTrophyLocker = preload("res://core/boss_trophy_locker.gd")

var locker := BossTrophyLocker.new(AppearanceData.trophies())
var tab: Control
var player: Node3D
var hud: Node
var chat: Node
var sounds: Node
var who := Callable()  # func() -> the player's name
var save := Callable()  # the session's save_profile
var look_out := Callable()  # func(look): the look goes to the lobby

var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


# The look with the worn trophies (the customizer and saves keep them on).
func dressed(look: Dictionary) -> Dictionary:
	var out := look.duplicate()
	if locker.worn.is_empty():
		out.erase("boss_trophies")
	else:
		out["boss_trophies"] = locker.worn.duplicate()
	return out


func restore(saved: Variant) -> void:
	locker.from_dict(saved)
	_apply()


func to_dict() -> Dictionary:
	return locker.to_dict()


# The tab's button: on if off, off if on.
func toggle(id: String) -> void:
	if locker.is_worn(id):
		locker.take_off(id)
		hud.call("notice", "Took off the %s" % locker.db.call("name_of", id))
	elif locker.wear(id):
		hud.call("notice", "Wearing the %s" % locker.db.call("name_of", id))
	else:
		return
	_apply()
	if sounds != null:
		sounds.call("play", "upgrade_done")
	_done()


# A piece comes to this player: kept, told in chat. True when new.
func earn(id: String, why: String) -> bool:
	if not locker.add(id):
		return false
	var called := String(locker.db.call("name_of", id))
	if chat != null:
		chat.call("add_line", "%s won the %s%s!" % [String(who.call()) if who.is_valid() else "You", called, (" " + why) if why != "" else ""], Color(1.0, 0.82, 0.3))
	_done()
	return true


# A boss this player helped beat (every machine pays its own player). `phantom` = it was the boss's echo; `odds` =
# enemies.json phantom {ghost_trophy, spectral}. Returns banner lines for what was won.
func on_boss(boss: String, phantom: bool, odds: Dictionary) -> Array:
	var lines: Array = []
	var own := String(locker.db.call("for_boss", boss))
	if own != "" and earn(own, ""):  # the first win over this great creature, whichever form it took
		lines.append("Trophy: %s  (wear it from the Trophies tab of your player card)" % locker.db.call("name_of", own))
	if not phantom:
		return lines
	var ghost := String(locker.db.call("ghost_of", boss))
	if ghost != "" and not locker.has(ghost) and _rng.randf() < float(odds.get("ghost_trophy", 0.0)) and earn(ghost, "from a phantom"):
		lines.append("Ghost trophy: %s" % locker.db.call("name_of", ghost))
	var missing: Array = []
	for id: String in locker.db.call("set_pieces", "spectral"):
		if not locker.has(id):
			missing.append(id)
	if not missing.is_empty() and _rng.randf() < float(odds.get("spectral", 0.0)):
		var piece := String(missing[_rng.randi() % missing.size()])
		if earn(piece, "from a phantom"):
			lines.append("Spectral piece: %s" % locker.db.call("name_of", piece))
	return lines


func _apply() -> void:
	if player == null:
		return
	var look: Dictionary = dressed(player.get("appearance"))
	if look != player.get("appearance"):
		player.call("set_appearance", look)
		if look_out.is_valid():
			look_out.call(player.get("appearance"))


func _done() -> void:
	if tab != null:
		tab.call("refresh")
	if save.is_valid():
		save.call()
