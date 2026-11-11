# Purpose: the bunny-girl lifeguard NPC on the spawn island: stands at the shore fishing (rod, line, bobbing bobber, now and then a tug). Pressing E near her opens the customization menu.
# Dependencies: game/npc_chatter.gd (name plate, speech), game/npc_body.gd (rigged body with her accessories, or the old code-built body), game/island.gd (CENTER), game/body_parts.gd.
extends Node3D

const NpcBody = preload("res://game/npc_body.gd")
const P = preload("res://game/body_parts.gd")
const Island = preload("res://game/island.gd")
const NpcChatter = preload("res://game/npc_chatter.gd")

const POS := Island.CENTER + Vector3(7.5, 0.0, 7.0)  # on the sand, facing the sea
const LOOK := {
	"gender": "female", "height": 1.0, "weight": 0.95, "bust": 0.4, "glutes": 0.4, "skin": 2,
	"hair": "ponytail", "hair_color": "#e8c36a", "face": "happy", "outfit": "lifeguard",
}
const WATER_Y := -0.3

var _rod: Node3D
var _tip: Node3D
var _line: MeshInstance3D
var _bobber: MeshInstance3D
var _model: Node3D
var _t := 0.0


func _ready() -> void:
	_model = NpcBody.build(LOOK)
	add_child(_model)
	var arm_r: Node3D = _model.get_node("Torso/ArmR")
	var arm_l: Node3D = _model.get_node("Torso/ArmL")
	arm_r.rotation_degrees = Vector3(72.0, 0.0, -8.0)
	arm_l.rotation_degrees = Vector3(55.0, 0.0, 12.0)
	var rod_mat := P.mat(Color(0.35, 0.22, 0.1))
	_rod = P.pivot(self, "Rod", Vector3(0.2, 1.12, -0.42))
	_rod.rotation_degrees.x = -58.0
	P.cyl(_rod, 0.004, 0.014, 2.0, Vector3(0, 1.0, 0), rod_mat)
	P.ball(_rod, 0.025, Vector3(0, 0.1, 0), P.mat(Color(0.8, 0.8, 0.85)))  # reel
	_tip = P.pivot(_rod, "Tip", Vector3(0, 2.0, 0))
	_bobber = P.ball(self, 0.055, Vector3(0.3, WATER_Y, -6.5), P.mat(Color(0.95, 0.2, 0.2)))
	P.ball(_bobber, 0.056, Vector3(0, -0.02, 0), P.mat(Color(0.97, 0.97, 0.97)), Vector3(1.0, 0.5, 1.0))
	_line = P.box(self, Vector3(0.006, 0.006, 1.0), Vector3.ZERO, P.mat(Color(0.9, 0.9, 0.9)))
	NpcChatter.new().setup(_model, "lifeguard")


func _process(delta: float) -> void:
	_t += delta
	var tug := maxf(0.0, sin(_t * 0.7 - 1.0) - 0.93) * 14.0  # a short tug every ~9 seconds
	_rod.rotation_degrees.x = -58.0 + sin(_t * 1.3) * 1.2 + tug * 12.0
	_bobber.position.y = WATER_Y + sin(_t * 2.1) * 0.018 - tug * 0.07
	_model.get_node("Torso").rotation_degrees.z = sin(_t * 0.6) * 1.2
	var a := _tip.global_position
	var b := _bobber.global_position
	var dist := a.distance_to(b)
	if dist > 0.01:
		_line.global_position = (a + b) * 0.5
		_line.look_at(b, Vector3.UP)
		(_line.mesh as BoxMesh).size = Vector3(0.006, 0.006, dist)
