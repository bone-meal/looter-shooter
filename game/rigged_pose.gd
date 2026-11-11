# Purpose: lets code written for the old code-built bodies pose a rigged body. The old bodies were six jointed parts
# (Torso with Head, ArmL, ArmR; LegL, LegR) that dances, the dealers, the lifeguard and the NPC head-turn rotate
# directly. A rigged body carries the same six nodes as invisible handles; every frame, after the animation clips, this
# modifier turns the matching bones by whatever those handles are turned (body space, on top of the clip pose).
# Dependencies: game/rigged_body.gd creates it as a child of the character's Skeleton3D and calls setup().
extends SkeletonModifier3D

# The club crowd (game/party_people.gd) used a second layout with everything under "Body" (Body with Head, ArmL, ArmR,
# LegL, LegR): those handles exist too. Moving "Body" or "Torso" up and down moves the hips (dance bounce).
# handle path under the body root -> [bone, rest position of the handle (roughly where that joint is on the body)]
const HANDLES := {
	"Body": ["pelvis", Vector3.ZERO],
	"Body/Head": ["neck_01", Vector3(0.0, 1.6, 0.0)],
	"Body/ArmL": ["upperarm_l", Vector3(-0.26, 1.4, 0.0)],
	"Body/ArmR": ["upperarm_r", Vector3(0.26, 1.4, 0.0)],
	"Body/LegL": ["thigh_l", Vector3(-0.1, 0.9, 0.0)],
	"Body/LegR": ["thigh_r", Vector3(0.1, 0.9, 0.0)],
	"Torso": ["spine_01", Vector3(0.0, 0.95, 0.0)],
	"Torso/Head": ["neck_01", Vector3(0.0, 0.55, 0.0)],
	"Torso/ArmL": ["upperarm_l", Vector3(-0.19, 0.45, 0.0)],
	"Torso/ArmR": ["upperarm_r", Vector3(0.19, 0.45, 0.0)],
	"LegL": ["thigh_l", Vector3(-0.09, 0.93, 0.0)],
	"LegR": ["thigh_r", Vector3(0.09, 0.93, 0.0)],
}

var _pairs: Array = []  # [handle Node3D, bone index, rest position, moves the bone too], parents before children
var _flip := Basis(Vector3.UP, PI)  # body space (faces -Z) <-> skeleton space (faces +Z); its own inverse


# Creates the handle nodes under `body` (the RiggedBody root).
func setup(body: Node3D, skeleton: Skeleton3D) -> void:
	for path: String in HANDLES:
		var entry: Array = HANDLES[path]
		var handle := Node3D.new()
		handle.name = path.get_file()
		handle.position = entry[1]
		var parent: Node = body if not path.contains("/") else body.get_node(path.get_base_dir())
		parent.add_child(handle)
		_pairs.append([handle, skeleton.find_bone(String(entry[0])), entry[1], not path.contains("/") and not path.begins_with("Leg")])


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for pair: Array in _pairs:
		var turn := (pair[0] as Node3D).basis
		var bone: int = pair[1]
		var shift := ((pair[0] as Node3D).position - (pair[2] as Vector3)) if bool(pair[3]) else Vector3.ZERO
		if bone < 0 or (turn.is_equal_approx(Basis.IDENTITY) and shift.is_zero_approx()):
			continue
		var pose := skeleton.get_bone_global_pose(bone)
		pose.basis = _flip * turn * _flip * pose.basis
		pose.origin += _flip * shift
		skeleton.set_bone_global_pose(bone, pose)
