# Purpose: polish1 item 40: the skiff building itself at the slipway once its last part is in: piece after piece
# (hull, floor boards, thwarts, tiller, mast, sail) flies in from above, lands with a little bounce and a knock, then
# the finished boat takes over. Only the skiff (not the switch or the shield). Each machine plays its own.
# Dependencies: game/boat_model.gd (pieces()). Set `at` / `yaw` (the boat's place and heading), `sounds` (the session's
# sound player, may be null) before add_child; `finished` fires when the boat may be shown.
extends Node3D

const BoatModel = preload("res://game/boat_model.gd")

const GAP := 0.42  # seconds between pieces
const DROP := 0.5  # seconds a piece takes to land
const HIGH := 4.5  # metres above its place a piece starts

signal finished

var at := Vector3.ZERO
var yaw := 0.0
var sounds: Node = null
var _pieces: Array = []  # MeshInstance3D in building order
var _landed := 0
var _t := 0.0


func _ready() -> void:
	position = at
	rotation.y = yaw
	for part: Array in BoatModel.pieces():
		var piece := MeshInstance3D.new()
		piece.mesh = part[1]
		piece.visible = false
		add_child(piece)
		_pieces.append(piece)


func _process(delta: float) -> void:
	_t += delta
	for i in _pieces.size():
		var piece := _pieces[i] as MeshInstance3D
		var local := _t - float(i) * GAP
		if local < 0.0:
			continue
		piece.visible = true
		var u := clampf(local / DROP, 0.0, 1.0)
		var fall := 1.0 - u * u  # speeds up as it falls
		var bounce := sin(clampf((local - DROP) / 0.25, 0.0, 1.0) * PI) * 0.12 if local > DROP else 0.0
		piece.position = Vector3(0.0, HIGH * fall + bounce, 0.0)
		piece.rotation = Vector3(0.0, (1.0 - u) * 0.8 * (1.0 if i % 2 == 0 else -1.0), (1.0 - u) * 0.3)
		piece.scale = Vector3.ONE * lerpf(0.6, 1.0, u)
		if u >= 1.0 and i >= _landed:
			_landed = i + 1
			if sounds != null:
				sounds.call("play", "part_take")
	if _t >= float(_pieces.size() - 1) * GAP + DROP + 0.5:
		if sounds != null:
			sounds.call("play", "build_done")
		finished.emit()
		queue_free()
