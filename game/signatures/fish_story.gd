# Purpose: FISH STORY's red-text behaviour (diary/DESIGN_UNIQUES.md, region 1 chase gun): every kill's damage number
# is told bigger than it was, with a fisherman's line over it; the brass tag on the gun keeps the biggest real hit
# ever made with it (the gun's own "record", saved with it and shown on the tag and the card); beating the record
# gives a short boast (more damage). Numbers in data/gun_uniques.json fish_story "cfg".
# Dependencies: game/unique_attach.gd (show_record), game/damage_numbers.gd (say) through the player.
extends Node3D

const UniqueAttach = preload("res://game/unique_attach.gd")

const TELL_COLOR := Color(0.55, 0.85, 1.0)
const RECORD_COLOR := Color(1.0, 0.8, 0.3)

var _player: Node3D
var _gun: Dictionary = {}  # the inventory's own gun dictionary: its "record" is written here and saved with it
var _cfg: Dictionary = {}
var _gimmick: Node3D
var _boast_until := 0.0


# Before start: who holds it, the gun itself and its unique's data.
func bind(player: Node3D, gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_gun = gun
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_gimmick = gimmick
	_boast_until = 0.0


func stop() -> void:
	_boast_until = 0.0


func on_inspect() -> void:
	pass  # the inspect move (data/inspect.json "unique:fish_story") turns the tag toward you; nothing else to do


# One shot's damage on one enemy: returns the number to show. A kill is told bigger; a new biggest hit is kept.
func on_hit_total(at: Vector3, amount: float, killed: bool) -> float:
	var best := int(_gun.get("record", 0))
	if roundi(amount) > best:
		_gun["record"] = roundi(amount)
		_boast_until = _now() + float(_cfg.get("boast_seconds", 10.0))
		if _gimmick != null and is_instance_valid(_gimmick):
			UniqueAttach.show_record(_gimmick, roundi(amount))
		_say(at, "NEW RECORD", RECORD_COLOR)
	if not killed:
		return amount
	var words: Array = _cfg.get("tell_words", ["IT WAS THIS BIG"])
	if not words.is_empty() and int(_gun.get("record", 0)) == best:  # (a record says so itself)
		_say(at, String(words[randi() % words.size()]), TELL_COLOR)
	return amount * randf_range(float(_cfg.get("tell_min", 1.5)), float(_cfg.get("tell_max", 3.0)))


# Damage multiplier while boasting about a new record.
func damage_mult() -> float:
	return 1.0 + float(_cfg.get("boast_damage", 0.25)) if _now() < _boast_until else 1.0


func boasting() -> bool:
	return _now() < _boast_until


func _say(at: Vector3, words: String, color: Color) -> void:
	var numbers: Variant = _player.get("damage_numbers") if _player != null else null
	if numbers is Node:
		(numbers as Node).call("say", at, words, color)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
