# Purpose: one rigged, clothed character of the realistic look, built from data/characters.json: the outfit model brings
# the skeleton and the clothes; the head (cut from a base body), eyes, eyebrows and a hairstyle are attached to that
# skeleton; skin tone and hair colour are set; the clips baked for that skeleton by tools/anim_bake.tscn are blended by
# speed (idle / walk / run), with an arms-only weapon pose on top. Code written for the old code-built bodies (dances,
# dealer and lifeguard poses, NPC head-turn) keeps working through the handle nodes of game/rigged_pose.gd.
# There is no outfit-less character. An outfit may leave off pieces of its model, take pieces of the pack's other
# outfit, and wear pieces of our own: skinned ones sewn by tools/tailor.py and rigid ones (hats) from tools/blender/wear.py.
# The character faces -Z like every other body in the game.
# Use: RiggedBody.build(appearance) (null when the packs are not on this machine: callers then use game/body_builder.gd),
# then animate() every frame; head_anchor(), hand_anchor(), support(), grip(), attach(), tint_outfit(), third_person_hold(), hold() as needed.
# Dependencies: data/characters.json, assets/cc0/packs/ (tools/pack_fetch.tscn), assets/anim/*.res (tools/anim_bake.tscn),
# game/appearance_data.gd (skin tone list), game/fantasy_models.gd (materials and models of our own pieces).
extends Node3D

const AppearanceData = preload("res://game/appearance_data.gd")
const RiggedPose = preload("res://game/rigged_pose.gd")
const BodyShape = preload("res://game/body_shape.gd")
const RiggedJiggle = preload("res://game/rigged_jiggle.gd")
const FantasyModels = preload("res://game/fantasy_models.gd")

const DATA_PATH := "res://data/characters.json"

static var _data := {}
static var _available := -1  # -1 not checked yet, 0 packs missing, 1 ready
static var _head_meshes := {}  # body id -> ArrayMesh with only the head and neck triangles
static var _skin_materials := {}  # "body:tone" -> StandardMaterial3D
static var _merged := {}  # body kind + how its surfaces group by material -> {"mesh", "skin"} (merge_pieces); {} = could not be merged
static var _hair_materials := {}  # "texture:colour" -> StandardMaterial3D
static var _tinted_materials := {}  # "material id:colour" -> Material

var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _anchor: Node3D
var _hand: Node3D
var _reach: TwoBoneIK3D  # left arm reaching for a long gun's support point
var _reach_target: Node3D
var _grip: TwoBoneIK3D  # right arm reaching for the grip of a gun carried on the shoulder
var _grip_target: Node3D
var _handles: RiggedPose
var _hold_amount := 0.0
var _held_clip := ""  # hold() asked for before the body was in the scene; applied in _ready
var _held_time := 0.0
var _outfit_albedo: Texture2D  # the outfit's alternative colour texture, if it has one
var _kind := ""  # body | outfit | hairstyle: bodies of one kind are made of the same pieces (merge_pieces shares their mesh)


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_data = parsed
	return _data


# True when the character packs and the baked animations are in the project (they are large downloads, see CREDITS).
static func available() -> bool:
	if _available < 0:
		_available = 0
		var skeletons: Dictionary = data().get("skeletons", {})
		if not skeletons.is_empty():
			_available = 1
			for id: String in skeletons:
				var entry: Dictionary = skeletons[id]
				if not ResourceLoader.exists(String(data()["packs"]) + String(entry["model"])) or not ResourceLoader.exists(String(entry["library"])):
					_available = 0
	return _available == 1


# A character for a player appearance (core/appearance_db.gd: gender, rig_outfit, rig_hair, skin, hair_color, height,
# weight, bust, glutes). `soft` = give the clothes the body-slider shapes and jiggle (players); crowds and staff pass
# false: those shapes cost frame time on every body that has them.
static func build(appearance: Dictionary, soft := true) -> Node3D:
	if not available():
		return null
	var tones: Array = AppearanceData.db().skin_tones
	var body := new()
	var built := body.setup({
		"body": String(appearance.get("gender", "female")),
		"outfit": String(appearance.get("rig_outfit", "")),
		"hair": String(appearance.get("rig_hair", "")),
		"skin_color": String(tones[clampi(int(appearance.get("skin", 0)), 0, tones.size() - 1)]),
		"hair_color": String(appearance.get("hair_color", "#4a3324")),
		"height": float(appearance.get("height", 1.0)),
		"weight": float(appearance.get("weight", 1.0)),
		"bust": float(appearance.get("bust", 0.0)),
		"glutes": float(appearance.get("glutes", 0.0)),
		"soft": soft,
	})
	if not built:
		body.free()
		return null
	return body


# Builds the character for a look: {body, outfit, hair, skin_color, hair_color, height, weight, bust, glutes}. Unknown ids fall back to the
# "defaults" of the body. Returns false when a model is missing (nothing usable is built then).
func setup(look: Dictionary) -> bool:
	var d := data()
	var bodies: Dictionary = d["bodies"]
	var body_id := String(look.get("body", "female"))
	if not bodies.has(body_id):
		body_id = "female"
	var body: Dictionary = bodies[body_id]
	var defaults: Dictionary = (d["defaults"] as Dictionary)[body_id]
	var outfits: Dictionary = d["outfits"]
	var outfit_id := String(look.get("outfit", ""))
	if not outfits.has(outfit_id):
		outfit_id = String(defaults["rig_outfit"])
	var outfit: Dictionary = outfits[outfit_id]
	var packs := String(d["packs"])
	_model = _open(packs + String((outfit["models"] as Dictionary)[body_id])) as Node3D
	var donor := _open(packs + String(body["model"]))
	if _model == null or donor == null:
		return false
	_model.rotation.y = PI  # the packs face +Z, the game's bodies face -Z
	add_child(_model)
	_skeleton = _find_skeleton(_model)
	for fragment: String in outfit.get("hide", []):  # pieces of the model this outfit leaves off (hood down, no pauldrons)
		for child in _skeleton.get_children():
			if child is MeshInstance3D and String(child.name).contains(fragment):
				child.free()
	for file: String in (outfit.get("parts", {}) as Dictionary).get(body_id, []):  # pieces of the pack's other outfit
		_add_pieces(packs + file, false)
	var wear: Dictionary = d.get("wear", {})
	for id: String in outfit.get("wear", []):  # pieces sewn from the model's own surface (tools/tailor.py)
		var sewn := String((wear.get(id, {}) as Dictionary).get("sewn", ""))
		if sewn != "":
			_add_pieces(sewn % [String(outfit.get("base", "peasant")), body_id], true)
	var skin := _skin_material(body_id, body, Color.html(String(look.get("skin_color", d["skin_reference"]))))
	var shape: Dictionary = body.get("shape", {}) if bool(look.get("soft", false)) else {}
	var clothes: Array = []
	for child in _skeleton.get_children():
		var piece := child as MeshInstance3D
		if piece != null:
			if not shape.is_empty() and piece.mesh is ArrayMesh:  # body sliders live in the clothes
				piece.mesh = BodyShape.shaped(piece.mesh as ArrayMesh, shape)
				BodyShape.apply(piece, float(look.get("weight", 1.0)), float(look.get("bust", 0.0)), float(look.get("glutes", 0.0)), float(shape.get("neutral", 0.0)))
				clothes.append(piece)
			_reskin(piece, skin)
	if not clothes.is_empty():
		var jiggle := RiggedJiggle.new()
		add_child(jiggle)
		jiggle.setup(clothes, float(look.get("bust", 0.0)), float(look.get("glutes", 0.0)))
	if outfit.has("albedo"):
		var albedo := String(outfit["albedo"])
		_outfit_albedo = _texture(albedo if albedo.begins_with("res://") else packs + albedo)
		tint_outfit(Color.WHITE)
	var donor_skeleton := _find_skeleton(donor)
	var head := MeshInstance3D.new()
	head.name = "Head"
	var donor_body := donor_skeleton.get_node_or_null(String(body["body_mesh"])) as MeshInstance3D
	if donor_body != null:
		head.mesh = _head_mesh(body_id, body, donor_body, donor_skeleton)
		head.skin = _named_skin(donor_body.skin, donor_skeleton, true)
		head.material_override = skin
		_skeleton.add_child(head)
		head.skeleton = NodePath("..")  # a new MeshInstance3D has no skeleton path in Godot 4.6: without this it is not skinned
	_adopt(donor_skeleton.get_node_or_null("Eyes") as MeshInstance3D, null, donor_skeleton, true)
	donor.free()
	var hair_color := Color.html(String(look.get("hair_color", "#4a3324")))
	var brows: Dictionary = (d["eyebrows"] as Dictionary)[body_id]
	_add_head_piece(String(brows["model"]), String(brows["texture"]), hair_color)
	var styles: Dictionary = d["hair"]
	var hair_id := String(look.get("hair", ""))
	if not styles.has(hair_id):
		hair_id = String(defaults["rig_hair"])
	var under_hood: Dictionary = outfit.get("hood_hair", {})
	if under_hood.has(body_id) and hair_id != "none":
		hair_id = String(under_hood[body_id])
	var style: Dictionary = styles[hair_id]
	_kind = "%s|%s|%s" % [body_id, outfit_id, hair_id]
	var hair_models: Dictionary = style.get("models", {})
	if hair_models.has(body_id):
		_add_head_piece(String(hair_models[body_id]), String(style.get("texture", "1")), hair_color)
	_anchor = Node3D.new()
	var socket := BoneAttachment3D.new()
	_skeleton.add_child(socket)
	socket.bone_name = "Head"
	var at: Array = body.get("head_anchor", [0.0, 1.55, 0.0])
	_anchor.transform = _skeleton.get_bone_global_rest(_skeleton.find_bone("Head")).affine_inverse() * Transform3D(Basis(Vector3.UP, PI), Vector3(float(at[0]), float(at[1]), float(at[2])))
	socket.add_child(_anchor)
	for id: String in outfit.get("wear", []):  # rigid things on the head (tools/blender/wear.py)
		var thing: Dictionary = wear.get(id, {})
		var made := FantasyModels.scene(String(thing["model"])) if thing.has("model") else null
		if made != null:
			var lift: Array = thing.get("at", [0.0, 0.0, 0.0])
			made.position = Vector3(float(lift[0]), float(lift[1]), float(lift[2]))
			_anchor.add_child(made)
	_hand = Node3D.new()
	var palm := BoneAttachment3D.new()
	_skeleton.add_child(palm)
	palm.bone_name = "hand_r"
	var hand_grip: Array = (d["motion"] as Dictionary).get("hand_grip", [0.0, 0.09, 0.02])
	# the hand bone points along its +Y with +Z up; weapon models point along -Z with +Y up
	_hand.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3(float(hand_grip[0]), float(hand_grip[1]), float(hand_grip[2])))
	palm.add_child(_hand)
	_handles = RiggedPose.new()
	_skeleton.add_child(_handles)
	_handles.setup(self, _skeleton)
	_add_animation(String((d["skeletons"] as Dictionary)[String(body["skeleton"])]["library"]))
	scale = Vector3.ONE * clampf(float(look.get("height", 1.0)), 0.85, 1.15)
	visibility_changed.connect(_on_visibility_changed)
	return true


# Every frame while the character is shown: `move` 0..1 = speed fraction, `holding` = a weapon is out.
func animate(move: float, holding: bool) -> void:
	if _tree == null:
		return
	var motion: Dictionary = data()["motion"]
	var step := get_process_delta_time() / maxf(float(motion.get("blend_seconds", 0.2)), 0.01)
	_hold_amount = move_toward(_hold_amount, 1.0 if holding else 0.0, step)
	_tree.active = true
	_tree.set("parameters/move/blend_position", clampf(move, 0.0, 1.0))
	_tree.set("parameters/hold/blend_amount", _hold_amount)


# A node that follows a bone (bone space), for things worn on the body.
func attach(bone: String) -> Node3D:
	var socket := BoneAttachment3D.new()
	_skeleton.add_child(socket)
	socket.bone_name = bone
	return socket


# Tints the clothes (not the skin, hair or eyes): one shared copy of each clothing material per colour and colour texture.
func tint_outfit(color: Color) -> void:
	for child in _skeleton.get_children():
		var piece := child as MeshInstance3D
		if piece == null or piece.material_override != null or piece.skin == null or piece.has_meta("own_colours"):
			continue
		for surface in piece.mesh.get_surface_count():
			var material := piece.mesh.surface_get_material(surface) as BaseMaterial3D
			if material == null or material.resource_name.contains("Regular") or material.resource_name.contains("Superhero"):
				continue  # missing, or a bare-skin surface
			var key := "%d:%s:%d" % [material.get_instance_id(), color.to_html(false), _outfit_albedo.get_instance_id() if _outfit_albedo != null else 0]
			if not _tinted_materials.has(key):
				var tinted := material.duplicate() as BaseMaterial3D
				tinted.albedo_color = color
				if _outfit_albedo != null:
					tinted.albedo_texture = _outfit_albedo
				_tinted_materials[key] = tinted
			piece.set_surface_override_material(surface, _tinted_materials[key])


# Folds every skinned piece of the body into ONE mesh with one surface per material (round 5). A dressed body was
# 12-14 draw calls, again in every shadow split, and each piece was skinned on its own; merged it is one skinned mesh
# of about 4-6 surfaces. Bodies of the same kind and colours' grouping share the mesh (built once). Call it when the
# body is complete and tinted: `tint_outfit` does nothing afterwards. Bodies with shape sliders (their pieces carry
# blend shapes and jiggle) and anything unusual are left as they are.
func merge_pieces() -> void:
	var pieces: Array[MeshInstance3D] = []
	for child in _skeleton.get_children():
		var piece := child as MeshInstance3D
		if piece != null and piece.mesh != null and piece.skin != null:
			if piece.mesh.get_blend_shape_count() > 0:
				return
			pieces.append(piece)
	if pieces.size() < 2:
		return
	var materials: Array[Material] = []
	var groups := PackedInt32Array()  # for every surface of every piece, in order: which merged surface it joins
	for piece in pieces:
		for surface in piece.mesh.get_surface_count():
			var material := piece.get_active_material(surface)
			var group := materials.find(material)
			if group < 0:
				group = materials.size()
				materials.append(material)
			groups.append(group)
	var key := "%s:%s" % [_kind, str(groups)]
	if not _merged.has(key):
		_merged[key] = _merge(pieces, groups, materials.size())
	var made: Dictionary = _merged[key]
	if made.is_empty():
		return
	var whole := MeshInstance3D.new()
	whole.name = "Merged"
	whole.mesh = made["mesh"]
	whole.skin = made["skin"]
	_skeleton.add_child(whole)
	whole.skeleton = NodePath("..")
	for group in materials.size():
		whole.set_surface_override_material(group, materials[group])
	for piece in pieces:
		piece.free()


# The pieces as one mesh (a surface per group) and one skin, or {} when they cannot be joined. Every piece has its own
# skin, so its vertices' bone numbers are renumbered to the joint skin (same bone with another bind pose = another bind).
static func _merge(pieces: Array[MeshInstance3D], groups: PackedInt32Array, count: int) -> Dictionary:
	var skin := Skin.new()
	var binds := {}
	var verts: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var tangents: Array[PackedFloat32Array] = []
	var uvs: Array[PackedVector2Array] = []
	var colours: Array[PackedColorArray] = []
	var bones: Array[PackedInt32Array] = []
	var weights: Array[PackedFloat32Array] = []
	var indices: Array[PackedInt32Array] = []
	var coloured := PackedByteArray()
	coloured.resize(count)
	for group in count:
		verts.append(PackedVector3Array())
		normals.append(PackedVector3Array())
		tangents.append(PackedFloat32Array())
		uvs.append(PackedVector2Array())
		colours.append(PackedColorArray())
		bones.append(PackedInt32Array())
		weights.append(PackedFloat32Array())
		indices.append(PackedInt32Array())
	var slot := 0
	for piece in pieces:
		var renumber := PackedInt32Array()
		for bind in piece.skin.get_bind_count():
			var bind_key := "%s %s" % [piece.skin.get_bind_name(bind), var_to_str(piece.skin.get_bind_pose(bind))]
			if not binds.has(bind_key):
				binds[bind_key] = skin.get_bind_count()
				skin.add_named_bind(piece.skin.get_bind_name(bind), piece.skin.get_bind_pose(bind))
			renumber.append(int(binds[bind_key]))
		var moved := not piece.transform.is_equal_approx(Transform3D.IDENTITY)
		for surface in piece.mesh.get_surface_count():
			var group := groups[slot]
			slot += 1
			var arrays := piece.mesh.surface_get_arrays(surface)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var many := v.size()
			if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null or many == 0:
				return {}
			var b: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var w: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if b.size() != many * 4:
				return {}  # eight weights a vertex: not something these packs have
			for i in b.size():
				b[i] = renumber[b[i]] if b[i] < renumber.size() else 0
			var n := PackedVector3Array()
			if arrays[Mesh.ARRAY_NORMAL] != null:
				n = arrays[Mesh.ARRAY_NORMAL]
			else:
				n.resize(many)
				n.fill(Vector3.UP)
			if moved:
				for i in many:
					v[i] = piece.transform * v[i]
					n[i] = (piece.transform.basis * n[i]).normalized()
			var t := PackedFloat32Array()
			if arrays[Mesh.ARRAY_TANGENT] != null:
				t = arrays[Mesh.ARRAY_TANGENT]
			else:
				t.resize(many * 4)
				for i in many:
					t[i * 4] = 1.0
					t[i * 4 + 3] = 1.0
			var uv := PackedVector2Array()
			if arrays[Mesh.ARRAY_TEX_UV] != null:
				uv = arrays[Mesh.ARRAY_TEX_UV]
			else:
				uv.resize(many)
			var c := PackedColorArray()
			if arrays[Mesh.ARRAY_COLOR] != null:
				c = arrays[Mesh.ARRAY_COLOR]
				coloured[group] = 1
			else:
				c.resize(many)
				c.fill(Color.WHITE)
			var first := verts[group].size()
			var index := PackedInt32Array()
			if arrays[Mesh.ARRAY_INDEX] != null:
				index = arrays[Mesh.ARRAY_INDEX]
				for i in index.size():
					index[i] += first
			else:
				index.resize(many)
				for i in many:
					index[i] = first + i
			verts[group].append_array(v)
			normals[group].append_array(n)
			tangents[group].append_array(t)
			uvs[group].append_array(uv)
			colours[group].append_array(c)
			bones[group].append_array(b)
			weights[group].append_array(w)
			indices[group].append_array(index)
	var draft := ImporterMesh.new()  # as the importer does it, so the merged body gets distance levels like its pieces had
	for group in count:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts[group]
		arrays[Mesh.ARRAY_NORMAL] = normals[group]
		arrays[Mesh.ARRAY_TANGENT] = tangents[group]
		arrays[Mesh.ARRAY_TEX_UV] = uvs[group]
		if coloured[group] == 1:
			arrays[Mesh.ARRAY_COLOR] = colours[group]
		arrays[Mesh.ARRAY_BONES] = bones[group]
		arrays[Mesh.ARRAY_WEIGHTS] = weights[group]
		arrays[Mesh.ARRAY_INDEX] = indices[group]
		draft.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	draft.generate_lods(25.0, 60.0, [])
	return {"mesh": draft.get_mesh(), "skin": skin}


# A point that follows the head: face items (cigarette) placed here use the same offsets as on the old code-built head.
func head_anchor() -> Node3D:
	return _anchor


# A point in the right hand, turned so a weapon model placed on it points where the hand points.
func hand_anchor() -> Node3D:
	return _hand


# Two-handed hold for long guns: the left hand reaches `target` (the "Support" point of a weapon model). Null = let go.
func support(target: Node3D) -> void:
	if target == _reach_target:
		return
	_reach_target = target
	if _reach == null:
		if target == null:
			return
		_reach = TwoBoneIK3D.new()
		_skeleton.add_child(_reach)  # after the pose handles, so it has the last word on the left arm
		_reach.set_setting_count(1)
		_reach.set_root_bone_name(0, "upperarm_l")
		_reach.set_middle_bone_name(0, "lowerarm_l")
		_reach.set_end_bone_name(0, "hand_l")
	_reach.active = target != null
	if target != null:
		_reach.set_target_node(0, _reach.get_path_to(target))


# A gun carried on the shoulder (launchers) is not in the hand of the weapon pose: the right hand reaches `target`
# (the weapon model's "Grip" point) instead. Null = back to the pose.
func grip(target: Node3D) -> void:
	if target == _grip_target:
		return
	_grip_target = target
	if _grip == null:
		if target == null:
			return
		_grip = TwoBoneIK3D.new()
		_skeleton.add_child(_grip)
		_grip.set_setting_count(1)
		_grip.set_root_bone_name(0, "upperarm_r")
		_grip.set_middle_bone_name(0, "lowerarm_r")
		_grip.set_end_bone_name(0, "hand_r")
	_grip.active = target != null
	if target != null:
		_grip.set_target_node(0, _grip.get_path_to(target))


# Where the local player's own weapon (which hangs from the camera) sits in third person to meet the hands of the weapon pose.
func third_person_hold() -> Vector3:
	var at: Array = (data()["motion"] as Dictionary).get("third_person_hold", [0.12, -0.2, -0.45])
	return Vector3(float(at[0]), float(at[1]), float(at[2]))


# Stops the body in the pose it has (no animation, so no skinning work) until animate() is called again:
# for people too far away to see them breathe.
func still() -> void:
	if _tree != null:
		_tree.active = false


# Shows one moment of a clip and holds it (for still pictures and previews); stops the blended motion.
func hold(clip: String, time: float) -> void:
	_held_clip = clip
	_held_time = time
	if _player != null and _player.is_inside_tree() and _player.has_animation(clip):
		if _tree != null:
			_tree.active = false
		_player.play(clip)
		_player.seek(time, true)
		_player.pause()


func _ready() -> void:
	if _held_clip != "":
		hold(_held_clip, _held_time)


func skeleton() -> Skeleton3D:
	return _skeleton


func _on_visibility_changed() -> void:
	var shown := is_visible_in_tree()
	if _tree != null and not shown:
		_tree.active = false  # animate() switches it on again
	if _handles != null:
		_handles.active = shown  # a hidden body costs nothing per frame
	if _reach != null:
		_reach.active = shown and _reach_target != null


# AnimationPlayer with the baked clips plus the blend tree: (idle..walk..run by speed) -> arms-only weapon pose.
func _add_animation(library_path: String) -> void:
	_player = AnimationPlayer.new()
	_player.name = "AnimationPlayer"
	_model.add_child(_player)
	if not ResourceLoader.exists(library_path):
		return
	_player.add_animation_library("", load(library_path) as AnimationLibrary)
	var motion: Dictionary = data()["motion"]
	var graph := AnimationNodeBlendTree.new()
	var move := AnimationNodeBlendSpace1D.new()
	move.min_space = 0.0
	move.max_space = 1.0
	move.sync = true
	move.add_blend_point(_clip(String(motion["idle"])), 0.0)
	move.add_blend_point(_clip(String(motion["walk"])), float(motion["walk_at"]))
	move.add_blend_point(_clip(String(motion["run"])), 1.0)
	graph.add_node("move", move)
	graph.add_node("aim", _clip(String(motion["hold"])))
	var hold_mix := AnimationNodeBlend2.new()
	hold_mix.filter_enabled = true
	var base := String(_model.get_path_to(_skeleton)) + ":"
	var upper: Array = motion["upper_body"]
	for bone in _skeleton.get_bone_count():
		var bone_name := _skeleton.get_bone_name(bone)
		for stem: String in upper:
			if bone_name.begins_with(stem):
				hold_mix.set_filter_path(NodePath(base + bone_name), true)
	graph.add_node("hold", hold_mix)
	graph.connect_node("hold", 0, "move")
	graph.connect_node("hold", 1, "aim")
	graph.connect_node("output", 0, "hold")
	_tree = AnimationTree.new()
	_tree.tree_root = graph
	_model.add_child(_tree)
	_tree.anim_player = NodePath("../AnimationPlayer")
	_tree.active = false


func _clip(clip_name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip_name
	return node


# Eyebrows or a hairstyle: a model from the hair folder that follows the head bone.
func _add_head_piece(model_file: String, texture_id: String, color: Color) -> void:
	var scene := _open(String(data()["packs"]) + String(data()["hair_folder"]) + model_file)
	if scene == null:
		return
	var from := _find_skeleton(scene)
	for child in from.get_children():
		_adopt(child as MeshInstance3D, _hair_material(texture_id, color), from, false)
	scene.free()


# Puts on every skinned piece of another model that stands on the same skeleton. `ours` = sewn by tools/tailor.py:
# its surfaces are named after what they are made of and take the fantasy props' materials. Such pieces keep their
# own colours when the outfit is tinted or given another colour texture.
func _add_pieces(path: String, ours: bool) -> void:
	var scene := _open(path)
	if scene == null:
		return
	var from := _find_skeleton(scene)
	for child in from.get_children() if from != null else []:
		var piece := child as MeshInstance3D
		if piece == null:
			continue
		if ours:
			FantasyModels.dress(piece.mesh)
		_adopt(piece, null, from, false)
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		piece.set_meta("own_colours", true)
	scene.free()


# Moves a skinned mesh from another model's skeleton onto this character's skeleton (same bone names).
func _adopt(piece: MeshInstance3D, material: Material, from: Skeleton3D, fit: bool) -> void:
	if piece == null:
		return
	piece.skin = _named_skin(piece.skin, from, fit)
	piece.owner = null
	piece.get_parent().remove_child(piece)
	_skeleton.add_child(piece)
	piece.skeleton = NodePath("..")
	piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if material == null else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if material != null:
		piece.material_override = material


# A copy of a skin that finds its bones by name on this skeleton. `fit` = bind to THIS skeleton's rest pose, so the piece
# stays exactly where it was modelled (head and eyes of the same body). Without it the piece keeps its own bind and
# follows the head bone, which also puts a hairstyle modelled on the other body's head at the right height.
func _named_skin(original: Skin, from: Skeleton3D, fit: bool) -> Skin:
	var named := Skin.new()
	for bind in original.get_bind_count():
		var bone_name := String(original.get_bind_name(bind))
		if bone_name == "" and original.get_bind_bone(bind) >= 0:
			bone_name = from.get_bone_name(original.get_bind_bone(bind))
		var bone := _skeleton.find_bone(bone_name)
		var pose := original.get_bind_pose(bind)
		if fit and bone >= 0:
			pose = _skeleton.get_bone_global_rest(bone).affine_inverse()
		named.add_named_bind(bone_name, pose)
	return named


# Outfit meshes show bare skin on some surfaces (hands, forearms): those take the chosen skin tone.
func _reskin(piece: MeshInstance3D, skin: Material) -> void:
	for surface in piece.mesh.get_surface_count():
		var material := piece.mesh.surface_get_material(surface)
		if material != null and (material.resource_name.contains("Regular") or material.resource_name.contains("Superhero")):
			piece.set_surface_override_material(surface, skin)


# The body's skin texture tinted toward the chosen tone ("skin_reference" in the data is the tone that leaves it as is).
static func _skin_material(body_id: String, body: Dictionary, tone: Color) -> StandardMaterial3D:
	var key := body_id + ":" + tone.to_html(false)
	if not _skin_materials.has(key):
		var packs := String(data()["packs"])
		var reference := Color.html(String(data()["skin_reference"]))
		var material := StandardMaterial3D.new()
		material.albedo_texture = _texture(packs + String(body["skin"]))
		material.albedo_color = Color(minf(tone.r / reference.r, 1.25), minf(tone.g / reference.g, 1.25), minf(tone.b / reference.b, 1.25))
		material.normal_enabled = true
		material.normal_texture = _texture(packs + String(body["normal"]))
		material.roughness_texture = _texture(packs + String(body["roughness"]))
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		_skin_materials[key] = material
	return _skin_materials[key]


static func _hair_material(texture_id: String, color: Color) -> StandardMaterial3D:
	var key := texture_id + ":" + color.to_html(false)
	if not _hair_materials.has(key):
		var textures: Dictionary = data()["hair_textures"]
		var material := StandardMaterial3D.new()
		material.albedo_texture = _texture(String(data()["packs"]) + String(textures.get(texture_id, "")))
		material.albedo_color = color
		material.roughness = 0.6
		material.cull_mode = BaseMaterial3D.CULL_DISABLED  # hair cards are single-sided sheets
		_hair_materials[key] = material
	return _hair_materials[key]


# The head and neck of a base body: the body mesh with only the triangles whose corners all hang on the head bones.
static func _head_mesh(body_id: String, body: Dictionary, donor_body: MeshInstance3D, donor_skeleton: Skeleton3D) -> ArrayMesh:
	if _head_meshes.has(body_id):
		return _head_meshes[body_id]
	var wanted: Array = body.get("head_bones", ["Head"])
	var is_head := {}  # skin bind index -> true
	var skin := donor_body.skin
	for bind in skin.get_bind_count():
		var bone_name := String(skin.get_bind_name(bind))
		if bone_name == "" and skin.get_bind_bone(bind) >= 0:
			bone_name = donor_skeleton.get_bone_name(skin.get_bind_bone(bind))
		if wanted.has(bone_name):
			is_head[bind] = true
	var arrays := donor_body.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var per_vertex := int(float(bones.size()) / float(maxi(vertices.size(), 1)))
	var on_head := PackedByteArray()
	on_head.resize(vertices.size())
	for v in vertices.size():
		var share := 0.0
		for k in per_vertex:
			if is_head.has(bones[v * per_vertex + k]):
				share += weights[v * per_vertex + k]
		on_head[v] = 1 if share >= 0.5 else 0
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var kept := PackedInt32Array()
	for i in range(0, indices.size() - 2, 3):
		if on_head[indices[i]] + on_head[indices[i + 1]] + on_head[indices[i + 2]] == 3:
			kept.append_array([indices[i], indices[i + 1], indices[i + 2]])
	arrays[Mesh.ARRAY_INDEX] = kept
	for extra in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
		arrays[extra] = null  # unused extra vertex data; its storage format is not kept by surface_get_arrays
	var flags := Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS if per_vertex == 8 else 0
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	_head_meshes[body_id] = mesh
	return mesh


static func _texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func _open(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	return scene.instantiate()


static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null
