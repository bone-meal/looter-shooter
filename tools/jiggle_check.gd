# Purpose: developer check for body jiggle: builds a character, moves it (walk, stop, jump), logs peak offsets of the soft parts (must stay bounded and settle). Writes tools/jiggle_check.log and quits. Run scene tools/jiggle_check.tscn.
# Dependencies: game/body_builder.gd, game/appearance_data.gd, game/body_jiggle.gd.
extends Node3D

const BodyBuilder = preload("res://game/body_builder.gd")
const AppearanceData = preload("res://game/appearance_data.gd")

var _model: Node3D
var _soft: Array[MeshInstance3D] = []
var _rest: Array[Vector3] = []
var _t := 0.0
var _peak := 0.0
var _peak_after_stop := 0.0
var _log := ""


func _ready() -> void:
	var look: Dictionary = AppearanceData.db().default_for("female")
	look["bust"] = 1.0
	look["glutes"] = 1.0
	_model = BodyBuilder.build(look)
	add_child(_model)
	var torso := _model.get_node("Torso")
	for child in torso.get_children():
		if child is MeshInstance3D and child.has_meta("soft"):
			_soft.append(child)
			_rest.append(child.position)
	_log += "soft parts: %d, driver: %s\n" % [_soft.size(), str(_model.get_node_or_null("Jiggle") != null)]


func _offset() -> float:
	var m := 0.0
	for i in _soft.size():
		m = maxf(m, (_soft[i].position - _rest[i]).length())
	return m


func _process(delta: float) -> void:
	_t += delta
	if _t < 1.0:
		_model.position.x += 3.0 * delta  # walk
		_peak = maxf(_peak, _offset())
	elif _t < 1.2:
		_model.position.y += 4.0 * delta  # jump up
		_peak = maxf(_peak, _offset())
	elif _t < 1.4:
		_model.position.y = maxf(0.0, _model.position.y - 4.0 * delta)
		_peak = maxf(_peak, _offset())
	elif _t < 3.5:
		_peak_after_stop = _offset()
	else:
		_log += "peak offset while moving: %.4f m\nresidual after settling: %.5f m\n" % [_peak, _peak_after_stop]
		var ok := _soft.size() >= 2 and _peak > 0.002 and _peak <= 0.15 and _peak_after_stop < 0.002
		_log += "RESULT: %s\n" % ("ok" if ok else "FAIL")
		var f := FileAccess.open("res://tools/jiggle_check.log", FileAccess.WRITE)
		f.store_string(_log)
		f.close()
		get_tree().quit()
