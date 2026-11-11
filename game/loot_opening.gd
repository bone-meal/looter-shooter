# Purpose: the little show of a container being searched: a chest, crate or barrel lifts its lid (the model's "Lid"
# part), a cupboard swings its doors ("DoorL", "DoorR"), anything without such parts gives a short shake; then it
# shuts again. Only what the searching player sees: nothing here decides loot.
# Dependencies: none (works on any model placed as a scene of its own; the parts are found by name).
extends RefCounted

const OPEN_S := 0.35
const HELD_S := 1.8


static func play(thing: Node3D) -> void:
	if thing == null or not is_instance_valid(thing) or thing.has_meta("opening"):
		return
	thing.set_meta("opening", true)
	var tween := thing.create_tween()
	var lid := thing.find_child("Lid", true, false) as Node3D
	var left := thing.find_child("DoorL", true, false) as Node3D
	var right := thing.find_child("DoorR", true, false) as Node3D
	if lid != null:  # hinged along the back edge (a model's front is its -z side)
		var shut := lid.rotation.x
		tween.tween_property(lid, "rotation:x", shut + 1.25, OPEN_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_interval(HELD_S)
		tween.tween_property(lid, "rotation:x", shut, OPEN_S)
	elif left != null and right != null:  # each door hinged at its outer edge
		tween.tween_property(left, "rotation:y", left.rotation.y + 1.9, OPEN_S).set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(right, "rotation:y", right.rotation.y - 1.9, OPEN_S).set_trans(Tween.TRANS_SINE)
		tween.tween_interval(HELD_S)
		tween.tween_property(left, "rotation:y", left.rotation.y, OPEN_S)
		tween.parallel().tween_property(right, "rotation:y", right.rotation.y, OPEN_S)
	else:
		var rest := thing.scale
		tween.tween_property(thing, "scale", rest * Vector3(1.07, 0.9, 1.07), 0.09)
		tween.tween_property(thing, "scale", rest, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: thing.remove_meta("opening"))
