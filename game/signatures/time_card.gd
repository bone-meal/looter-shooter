# Purpose: TIME CARD's red-text behaviour (diary/DESIGN_UNIQUES.md, raid chase gun): a punch clock on the machine gun's
# stock. The INSPECT key clocks you in (and out). Clocked in, damage grows the longer you go without being hit: after
# each "after" in data cfg "pay" the next rate (time and a half, then double, then something worse); a hit DOCKS YOUR
# PAY (back to the start, still clocked in). The clock face shows it (Label3D on the "Face" marker) and others see it
# (held_suffix "o" = out, "t0".."t3" = the rate; game/unique_attach.gd show_extra).
# Numbers in data/gun_uniques.json time_card "cfg".
# Dependencies: the holder's `damaged` signal; the punch_clock gimmick ("Face").
extends Node3D

var _player: Node3D
var _cfg: Dictionary = {}
var _label: Label3D
var _in := false
var _clock := 0.0
var _docked := 0.0
var docks := 0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})
	if _player.has_signal("damaged") and not _player.is_connected("damaged", docked):
		_player.connect("damaged", docked)


func start(gimmick: Node3D) -> void:
	_label = face_label(gimmick)
	_show()


func stop() -> void:
	if _player != null and _player.has_signal("damaged") and _player.is_connected("damaged", docked):
		_player.disconnect("damaged", docked)


func on_inspect() -> void:
	_in = not _in
	_clock = 0.0
	_show()


func clocked_in() -> bool:
	return _in


# A hit docks the pay: back to the start of the shift.
func docked(_a: Variant = null, _b: Variant = null) -> void:
	if not _in:
		return
	_clock = 0.0
	_docked = 1.0
	docks += 1
	_show()


func rate() -> int:
	var r := 0
	var pay: Array = _cfg.get("pay", [])
	for k in pay.size():
		if _clock >= float((pay[k] as Dictionary).get("after", 0.0)):
			r = k
	return r


func damage_mult() -> float:
	var pay: Array = _cfg.get("pay", [])
	return float((pay[rate()] as Dictionary).get("mult", 1.0)) if _in and not pay.is_empty() else 1.0


func held_suffix() -> String:
	return "t%d" % rate() if _in else "o"


func _process(delta: float) -> void:
	if _in:
		_clock += delta
	_docked = maxf(0.0, _docked - delta)
	_show()


func _show() -> void:
	if _label == null or not is_instance_valid(_label):
		return
	if not _in:
		_label.text = "OUT"
	elif _docked > 0.0:
		_label.text = "DOCKED"
	else:
		_label.text = "IN %d:%02d\nx%s" % [floori(_clock / 60.0), int(_clock) % 60, str(damage_mult())]


# The words on a clock face (also another player's copy).
static func face_label(piece: Node3D) -> Label3D:
	var face := piece.find_child("Face", true, false) as Node3D if piece != null else null
	if face == null:
		return null
	var label := face.get_node_or_null("Words") as Label3D
	if label == null:
		label = Label3D.new()
		label.name = "Words"
		label.font_size = 64
		label.pixel_size = 0.00016
		label.outline_size = 0
		label.modulate = Color(0.1, 0.1, 0.12)
		label.rotation_degrees = Vector3(0, -90, 0)  # the face looks to the gun's left
		label.shaded = false
		label.double_sided = false
		face.add_child(label)
	return label
