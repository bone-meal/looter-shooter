# Purpose: casino/club staff: BodyBuilder characters (original clothed bunny-girl uniform from data/outfits.json casino_* outfits) with simple jobs: walk a loop with pauses (waitress), stand and deal (dealer), stand idle (bartender), or dance. Animation uses game/body_motion.gd and game/dance_poses.gd.
# Dependencies: game/npc_body.gd (rigged body with the staff accessories, or the old code-built body), game/body_motion.gd, game/dance_poses.gd, game/npc_chatter.gd (optional personality by npc id).
extends Node3D

const NpcBody = preload("res://game/npc_body.gd")
const BodyMotion = preload("res://game/body_motion.gd")
const DancePoses = preload("res://game/dance_poses.gd")
const NpcChatter = preload("res://game/npc_chatter.gd")

const WALK_SPEED := 0.9
const PAUSE := 2.5
const MARGIN := 0.45  # how far walkers keep from an obstacle edge

var _staff: Array[Dictionary] = []
var _t := 0.0
var _obstacles: Array = []  # Rect2 in crew-local x/z (x, z = position; size = full width/depth), already grown by MARGIN


# A staff look. hair/face ids come from data/appearance.json and data/expressions.json.
static func look(outfit: String, hair: String, hair_color: String, face: String, skin: int, height: float = 1.0) -> Dictionary:
	return {
		"gender": "female", "height": height, "weight": 0.95, "bust": 0.3, "glutes": 0.3, "skin": skin,
		"hair": hair, "hair_color": hair_color, "face": face, "outfit": outfit,
	}


# role: "idle", "deal", "dance" (arg = dance id) or "walk" (arg = Array of Vector3 points, crew-local). npc_id (data/npcs.json) gives her a name, speech and a head that follows the camera.
func add(role: String, the_look: Dictionary, pos: Vector3, yaw_deg: float, arg: Variant = null, npc_id: String = "") -> Node3D:
	var model := NpcBody.build(the_look)
	model.position = pos
	model.rotation_degrees.y = yaw_deg
	add_child(model)
	if npc_id != "":
		NpcChatter.new().setup(model, npc_id)
	_staff.append({"model": model, "role": role, "arg": arg, "phase": float(_staff.size()) * 1.7, "leg": 0, "wait": 0.0, "pos": pos})
	return model


# Walkers never enter this box (tables, machines, kiosks). `center` is crew-local; half sizes are meters.
func add_obstacle(center: Vector3, half_x: float, half_z: float) -> void:
	_obstacles.append(Rect2(center.x - half_x - MARGIN, center.z - half_z - MARGIN, (half_x + MARGIN) * 2.0, (half_z + MARGIN) * 2.0))


# Moves a walker out of any obstacle it is inside, through the nearest edge.
func _push_out(model: Node3D) -> void:
	for rect: Rect2 in _obstacles:
		var p := Vector2(model.position.x, model.position.z)
		if not rect.has_point(p):
			continue
		var left := p.x - rect.position.x
		var right := rect.end.x - p.x
		var top := p.y - rect.position.y
		var bottom := rect.end.y - p.y
		var least := minf(minf(left, right), minf(top, bottom))
		if least == left:
			model.position.x = rect.position.x
		elif least == right:
			model.position.x = rect.end.x
		elif least == top:
			model.position.z = rect.position.y
		else:
			model.position.z = rect.end.y


# Dealer and others can be asked to make the "deal" flick right now (cards going out).
func deal_flick(model: Node3D) -> void:
	for s in _staff:
		if s["model"] == model:
			s["flick"] = 0.7


func _process(delta: float) -> void:
	_t += delta
	for s in _staff:
		var model: Node3D = s["model"]
		var phase: float = s["phase"]
		match String(s["role"]):
			"idle":
				BodyMotion.animate(model, 0.0, 0.0, _t + phase, false)
			"deal":
				BodyMotion.animate(model, 0.0, 0.0, _t + phase, false)
				var flick := float(s.get("flick", 0.0))
				if flick > 0.0:
					s["flick"] = maxf(flick - delta, 0.0)
				var arm_r: Node3D = model.get_node("Torso/ArmR")
				var arm_l: Node3D = model.get_node("Torso/ArmL")
				arm_l.rotation = Vector3(0.75 + sin(_t * 1.1 + phase) * 0.03, 0.0, 0.15)
				arm_r.rotation = Vector3(0.75 + sin(clampf(flick / 0.7, 0.0, 1.0) * PI) * 0.55, 0.0, -0.15)
			"dance":
				DancePoses.apply(model, String(s["arg"]), _t + phase)
			"walk":
				_walk(s, model, delta)


func _walk(s: Dictionary, model: Node3D, delta: float) -> void:
	var points: Array = s["arg"]
	var wait: float = s["wait"]
	if wait > 0.0:
		s["wait"] = wait - delta
		BodyMotion.animate(model, 0.0, 0.0, _t + float(s["phase"]), false)
		return
	var target: Vector3 = points[int(s["leg"])]
	var to := target - model.position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.1:
		s["leg"] = (int(s["leg"]) + 1) % points.size()
		s["wait"] = PAUSE
		return
	var step := minf(WALK_SPEED * delta, dist)
	model.position += to / dist * step
	_push_out(model)
	# face the walking direction (model front is -Z)
	var want := atan2(-to.x, -to.z)
	model.rotation.y = lerp_angle(model.rotation.y, want, minf(delta * 6.0, 1.0))
	s["phase"] = float(s["phase"]) + delta * 6.5
	BodyMotion.animate(model, 1.0, float(s["phase"]), _t, false)
