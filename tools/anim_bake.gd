# Purpose: developer tool. Copies the wanted clips of the CC0 animation libraries onto each character skeleton listed in
# data/characters.json and saves one AnimationLibrary per skeleton (assets/anim/<skeleton>.res). The libraries were made
# on mannequins with other bone names and other rest poses, so every frame is retargeted: each bone takes the source
# bone's turn away from the shared T-pose, measured in skeleton space; the hips also take the source hip position scaled
# to the target's leg length. Clips stay in place (no root motion). Log: tools/anim_bake.log.
# Run scene tools/anim_bake.tscn after tools/pack_fetch.tscn. Dependencies: data/characters.json, the unpacked packs.
extends Node

const DATA_PATH := "res://data/characters.json"
const LOG_PATH := "res://tools/anim_bake.log"

var _data := {}
var _lines := PackedStringArray()


func _ready() -> void:
	_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/anim"))
	var skeletons: Dictionary = _data["skeletons"]
	for id: String in skeletons:
		var entry: Dictionary = skeletons[id]
		_bake_skeleton(id, String(_data["packs"]) + String(entry["model"]), String(entry["library"]))
	_lines.append("ANIM_BAKE_DONE")
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	get_tree().quit()


func _bake_skeleton(id: String, model_path: String, library_path: String) -> void:
	var target_root := _open(model_path)
	if target_root == null:
		_lines.append("FAILED %s: cannot load %s" % [id, model_path])
		return
	var target := _find_skeleton(target_root)
	var track_base := String(target_root.get_path_to(target)) + ":"
	var library := AnimationLibrary.new()
	for source: Dictionary in _data["animation_sources"]:
		var source_root := _open(String(_data["packs"]) + String(source["model"]))
		if source_root == null:
			_lines.append("FAILED %s: cannot load %s" % [id, source["model"]])
			continue
		var from := _find_skeleton(source_root)
		var player := source_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var match_of := PackedInt32Array()  # target bone -> source bone (-1 = none)
		for b in target.get_bone_count():
			match_of.append(from.find_bone(_source_name(target.get_bone_name(b), String(source["bones"]))))
		var reference: Animation = null
		if player.has_animation(String(source.get("reference_clip", ""))):
			reference = player.get_animation(String(source["reference_clip"]))
		var from_reference := _pose(from, reference, 0.0)
		for clip_name: String in source["clips"]:
			if not player.has_animation(clip_name):
				_lines.append("MISSING %s in %s" % [clip_name, source["model"]])
				continue
			var baked := _bake_clip(player.get_animation(clip_name), from, from_reference, target, match_of, track_base)
			library.add_animation(clip_name, baked)
		source_root.free()
	var error := ResourceSaver.save(library, library_path, ResourceSaver.FLAG_COMPRESS)
	_lines.append("%s: %d clips -> %s (save code %d, track base %s)" % [id, library.get_animation_list().size(), library_path, error, track_base])
	target_root.free()


func _bake_clip(clip: Animation, from: Skeleton3D, from_reference: Array, target: Skeleton3D, match_of: PackedInt32Array, track_base: String) -> Animation:
	var fps := float(_data.get("bake_fps", 30))
	var baked := Animation.new()
	baked.length = clip.length
	baked.loop_mode = clip.loop_mode
	baked.step = 1.0 / fps
	var hips := target.find_bone("pelvis")
	var rotation_track := PackedInt32Array()
	for b in target.get_bone_count():
		var track := -1
		if match_of[b] >= 0:
			track = baked.add_track(Animation.TYPE_ROTATION_3D)
			baked.track_set_path(track, track_base + target.get_bone_name(b))
		rotation_track.append(track)
	var hips_track := baked.add_track(Animation.TYPE_POSITION_3D)
	baked.track_set_path(hips_track, track_base + "pelvis")
	var leg_scale := 1.0
	var from_hips := match_of[hips]
	var from_hips_at: Vector3 = (from_reference[from_hips] as Transform3D).origin
	var target_hips_at := target.get_bone_global_rest(hips).origin
	if from_hips_at.y > 0.01:
		leg_scale = target_hips_at.y / from_hips_at.y
	var frames := int(ceil(clip.length * fps)) + 1
	var world: Array = []
	world.resize(target.get_bone_count())
	for frame in frames:
		var time := minf(float(frame) / fps, clip.length)
		var from_world := _pose(from, clip, time)
		for b in target.get_bone_count():
			var parent := target.get_bone_parent(b)
			var parent_world := Transform3D.IDENTITY
			if parent >= 0:
				parent_world = world[parent]
			var rest := target.get_bone_rest(b)
			var turned := parent_world.basis * rest.basis.orthonormalized()
			var s := match_of[b]
			if s >= 0:
				var now: Transform3D = from_world[s]
				var was: Transform3D = from_reference[s]
				turned = now.basis.orthonormalized() * was.basis.orthonormalized().inverse() * target.get_bone_global_rest(b).basis.orthonormalized()
			var at := parent_world * rest.origin
			if b == hips:
				var moved: Vector3 = (from_world[s] as Transform3D).origin
				at = Vector3(target_hips_at.x + (moved.x - from_hips_at.x) * leg_scale, moved.y * leg_scale, target_hips_at.z + (moved.z - from_hips_at.z) * leg_scale)
				baked.position_track_insert_key(hips_track, time, parent_world.affine_inverse() * at)
			world[b] = Transform3D(turned, at)
			if rotation_track[b] >= 0:
				baked.rotation_track_insert_key(rotation_track[b], time, (parent_world.basis.inverse() * turned).get_rotation_quaternion())
	baked.optimize()
	return baked


# Skeleton-space transform of every bone of a skeleton at one moment of a clip (rest pose where the clip has no track).
func _pose(skeleton: Skeleton3D, clip: Animation, time: float) -> Array:
	var local: Array = []
	for b in skeleton.get_bone_count():
		local.append(skeleton.get_bone_rest(b))
	if clip != null:
		for track in clip.get_track_count():
			var path := String(clip.track_get_path(track))
			var bone := skeleton.find_bone(path.get_slice(":", 1))
			if bone < 0:
				continue
			var current: Transform3D = local[bone]
			if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				local[bone] = Transform3D(Basis(clip.rotation_track_interpolate(track, time)).scaled(current.basis.get_scale()), current.origin)
			elif clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
				local[bone] = Transform3D(current.basis, clip.position_track_interpolate(track, time))
	var world: Array = []
	for b in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(b)
		var here: Transform3D = local[b]
		if parent >= 0:
			var above: Transform3D = world[parent]
			here = above * here
		world.append(here)
	return world


# Name of the library bone that drives a character bone ("" = none). "same": identical names. "rigify": the Blender
# Rigify names of the first library (table "rigify_bones": pelvis -> DEF-hips, upperarm_l -> DEF-upper_arm.L,
# index_01_l -> DEF-f_index.01.L).
func _source_name(bone: String, naming: String) -> String:
	if naming == "same" or bone == "root":
		return bone
	var table: Dictionary = _data["rigify_bones"]
	if table.has(bone):
		return String(table[bone])
	if not (bone.ends_with("_l") or bone.ends_with("_r")):
		return ""
	var side := ".L" if bone.ends_with("_l") else ".R"
	var stem := bone.left(bone.length() - 2)
	if table.has(stem):
		return String(table[stem]) + side
	var parts := stem.split("_")
	if parts.size() == 2 and table.has(parts[0]):
		return "%s.%s%s" % [table[parts[0]], parts[1], side]
	return ""


func _open(path: String) -> Node:
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
