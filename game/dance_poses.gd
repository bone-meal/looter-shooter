# Purpose: the 8 looping dance emotes as pure pose functions (time -> joint rotations) for any model built by BodyBuilder. Original moves with generic names.
# Dependencies: none (works on the Character > Torso/Head/ArmL/ArmR, LegL, LegR hierarchy).
extends RefCounted

const DANCES := [
	{"id": "hip_sway", "name": "Hip Sway"},
	{"id": "wave_arms", "name": "Wave Arms"},
	{"id": "point_groove", "name": "Point Groove"},
	{"id": "step_slide", "name": "Step Slide"},
	{"id": "bounce", "name": "Bounce"},
	{"id": "robot", "name": "Robot"},
	{"id": "shoulder_pop", "name": "Shoulder Pop"},
	{"id": "spin_clap", "name": "Spin Clap"},
]


static func has(id: String) -> bool:
	for d: Dictionary in DANCES:
		if d["id"] == id:
			return true
	return false


static func id_at(index: int) -> String:
	return String(DANCES[clampi(index, 0, DANCES.size() - 1)]["id"])


# Puts the model into the pose of dance `id` at time `t` seconds.
static func apply(model: Node3D, id: String, t: float, base_yaw := 0.0) -> void:
	if model.has_method("head_anchor"):  # a rigged body: stand still underneath; its handle nodes take the dance pose
		model.call("animate", 0.0, false)
	var torso: Node3D = model.get_node("Torso")
	var head: Node3D = torso.get_node("Head")
	var arm_l: Node3D = torso.get_node("ArmL")
	var arm_r: Node3D = torso.get_node("ArmR")
	var leg_l: Node3D = model.get_node("LegL")
	var leg_r: Node3D = model.get_node("LegR")
	reset(model, base_yaw)
	var s := sin(t * 6.0)
	var c := cos(t * 6.0)
	match id:
		"hip_sway":
			torso.rotation_degrees.z = s * 9.0
			torso.rotation_degrees.y = c * 10.0
			arm_l.rotation_degrees = Vector3(20.0, 0.0, -35.0 + s * 12.0)
			arm_r.rotation_degrees = Vector3(20.0, 0.0, 35.0 + s * 12.0)
			leg_l.rotation_degrees.z = s * 6.0
			leg_r.rotation_degrees.z = s * 6.0
		"wave_arms":
			arm_l.rotation_degrees = Vector3(170.0, 0.0, -20.0 + sin(t * 6.0) * 30.0)
			arm_r.rotation_degrees = Vector3(170.0, 0.0, 20.0 + sin(t * 6.0 + PI) * 30.0)
			torso.rotation_degrees.z = s * 5.0
			head.rotation_degrees.z = -s * 8.0
		"point_groove":
			var beat := signf(s)
			arm_r.rotation_degrees = Vector3(150.0, 0.0, 15.0 if beat > 0.0 else 40.0)
			arm_l.rotation_degrees = Vector3(30.0, 0.0, -20.0)
			torso.rotation_degrees.z = beat * 6.0
			leg_l.rotation_degrees.x = -absf(s) * 18.0
			head.rotation_degrees.y = beat * 15.0
		"step_slide":
			leg_l.rotation_degrees.z = maxf(0.0, s) * 25.0
			leg_r.rotation_degrees.z = maxf(0.0, -s) * -25.0
			torso.rotation_degrees.z = s * 7.0
			arm_l.rotation_degrees = Vector3(50.0 + c * 25.0, 0.0, -10.0)
			arm_r.rotation_degrees = Vector3(50.0 - c * 25.0, 0.0, 10.0)
		"bounce":
			var b := absf(sin(t * 7.0))
			model.position.y = b * 0.12
			arm_l.rotation_degrees = Vector3(0.0, 0.0, -30.0 - b * 50.0)
			arm_r.rotation_degrees = Vector3(0.0, 0.0, 30.0 + b * 50.0)
			leg_l.rotation_degrees.x = -b * 12.0
			leg_r.rotation_degrees.x = b * 12.0
			head.rotation_degrees.x = b * 10.0
		"robot":
			var step := floorf(t * 4.0)
			var jerk := fmod(step, 4.0)
			arm_l.rotation_degrees = Vector3(90.0, 0.0, -90.0 if jerk < 2.0 else -30.0)
			arm_r.rotation_degrees = Vector3(90.0 if jerk < 2.0 else 0.0, 0.0, 90.0 if jerk >= 2.0 else 30.0)
			head.rotation_degrees.y = (-30.0 if jerk < 2.0 else 30.0)
			torso.rotation_degrees.y = (-15.0 if jerk < 2.0 else 15.0)
			leg_l.rotation_degrees.x = (-10.0 if jerk < 2.0 else 10.0)
		"shoulder_pop":
			arm_l.rotation_degrees = Vector3(10.0, 0.0, -10.0 - maxf(0.0, s) * 40.0)
			arm_r.rotation_degrees = Vector3(10.0, 0.0, 10.0 + maxf(0.0, -s) * 40.0)
			torso.rotation_degrees.y = s * 18.0
			head.rotation_degrees.y = -s * 18.0
			leg_l.rotation_degrees.x = -absf(c) * 8.0
		"spin_clap":
			model.rotation.y = base_yaw + deg_to_rad(fmod(t * 160.0, 360.0))
			var clap := 0.5 + 0.5 * sin(t * 12.0)
			arm_l.rotation_degrees = Vector3(80.0, 0.0, -10.0 - clap * 40.0)
			arm_r.rotation_degrees = Vector3(80.0, 0.0, 10.0 + clap * 40.0)
			leg_l.rotation_degrees.x = s * 14.0
			leg_r.rotation_degrees.x = -s * 14.0


# Back to the neutral standing pose.
static func reset(model: Node3D, base_yaw := 0.0) -> void:
	model.position.y = 0.0
	model.rotation.y = base_yaw
	var torso: Node3D = model.get_node("Torso")
	torso.rotation_degrees = Vector3.ZERO
	for path: String in ["Head", "ArmL", "ArmR"]:
		(torso.get_node(path) as Node3D).rotation_degrees = Vector3.ZERO
	for path: String in ["LegL", "LegR"]:
		(model.get_node(path) as Node3D).rotation_degrees = Vector3.ZERO
