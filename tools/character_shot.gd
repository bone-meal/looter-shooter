# Purpose: developer check for the rigged characters. Stands one character per outfit on the island in the realistic
# look, each held in a different animation pose, and saves pictures (tools/shots/character_<view>.jpg, with _fwd on
# Forward+) plus draw calls and frame time (tools/character_shot.log / character_shot_fwd.log). Runs on Compatibility,
# then starts itself again on Forward+. Run scene tools/character_shot.tscn after pack_fetch and anim_bake.
# The back row is built and driven the way the game does it (appearance -> RiggedBody.build -> animate), with a held
# pistol and a cigarette placed like game/remote_player.gd places them (hand anchor, head anchor).
# Two staff members are built like the casino builds them (game/npc_body.gd) and one character holds a dance pose.
# Dependencies: game/rigged_body.gd, game/npc_body.gd, game/dance_poses.gd, game/appearance_data.gd, game/weapon_models.gd, game/cigarette_model.gd, game/render_style.gd, game/island.gd, game/renderer_switch.gd.
extends Node3D

const RenderStyle = preload("res://game/render_style.gd")
const Island = preload("res://game/island.gd")
const RendererSwitch = preload("res://game/renderer_switch.gd")
const RiggedBody = preload("res://game/rigged_body.gd")
const AppearanceData = preload("res://game/appearance_data.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const CigaretteModel = preload("res://game/cigarette_model.gd")
const DancePoses = preload("res://game/dance_poses.gd")
const NpcBody = preload("res://game/npc_body.gd")
const PartyPeople = preload("res://game/party_people.gd")

const SCENE := "res://tools/character_shot.tscn"
const C := Vector3(500, 0, 0)  # island centre
# Front row, held in one clip pose: [look, clip, time in the clip, x offset]
const CAST := [
	[{"body": "female", "outfit": "peasant", "hair": "long", "skin_color": "#8d5524", "hair_color": "#2b1d14"}, "Idle", 0.5, -2.7],
	[{"body": "female", "outfit": "ranger", "hair": "buns", "skin_color": "#f7d0b5", "hair_color": "#b5651d"}, "Pistol_Aim_Neutral", 0.2, -0.9],
	[{"body": "male", "outfit": "peasant", "hair": "long", "skin_color": "#f1c27d", "hair_color": "#d8c690"}, "Walk", 0.35, 0.9],
	[{"body": "male", "outfit": "ranger", "hair": "buzzed", "skin_color": "#4a2c17", "hair_color": "#1a1a1a"}, "Dance", 1.0, 2.7],
]
# Back row, driven like the game drives them (RiggedBody.build + animate): [appearance, move 0..1, holding, emote, x offset]
const GAME_CAST := [
	[{"gender": "female", "rig_outfit": "peasant_wasteland", "rig_hair": "buns", "skin": 4, "hair_color": "#7a1f1f"}, 0.0, true, "", -2.7],
	[{"gender": "male", "rig_outfit": "peasant", "rig_hair": "buzzed", "skin": 1, "hair_color": "#3b2a1a"}, 1.0, true, "", -0.9],
	[{"gender": "female", "rig_outfit": "ranger_wasteland", "rig_hair": "long", "skin": 7, "hair_color": "#111111"}, 0.4, false, "", 0.9],
	[{"gender": "male", "rig_outfit": "ranger", "rig_hair": "none", "skin": 9, "hair_color": "#111111"}, 0.0, false, "robot", 2.7],
]
# [name, eye, look-at]
const VIEWS := [
	["group", C + Vector3(0, 1.5, 4.6), C + Vector3(0, 0.95, 0)],
	["faces", C + Vector3(-1.8, 1.62, 1.9), C + Vector3(-1.8, 1.5, 0)],
	["side", C + Vector3(5.2, 1.4, 1.6), C + Vector3(0, 1.0, 0)],
	["game", C + Vector3(1.3, 1.5, -0.2), C + Vector3(1.3, 1.0, -3.0)],
	["hands", C + Vector3(-2.3, 1.45, -2.2), C + Vector3(-1.4, 1.35, -3.3)],
	["hands_run", C + Vector3(1.6, 1.3, -2.0), C + Vector3(0.4, 1.15, -3.3)],
	["smoke", C + Vector3(-1.15, 1.6, -2.3), C + Vector3(-1.4, 1.58, -3.0)],
	["npc", C + Vector3(-0.4, 1.5, 8.6), C + Vector3(-0.4, 1.05, 6.0)],
	["npc_close", C + Vector3(-0.5, 1.75, 7.2), C + Vector3(-0.3, 1.5, 6.0)],
	["dance", C + Vector3(4.0, 1.4, -0.4), C + Vector3(4.0, 1.0, -3.0)],
	["club", C + Vector3(-3.0, 1.5, 9.2), C + Vector3(-3.0, 1.0, 6.0)],
	["sliders", C + Vector3(3.7, 1.3, 8.6), C + Vector3(3.7, 1.0, 6.0)],
]

var _lines := PackedStringArray()
var _driven: Array = []  # [body, move, holding, dance id]
var _t := 0.0


func _ready() -> void:
	var forward := RendererSwitch.is_forward()
	var suffix := "_fwd" if forward else ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var env := Environment.new()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var style := RenderStyle.new()
	style.env = env
	style.sun = sun
	add_child(style)
	Island.build(self)
	_lines.append("renderer=%s adapter=%s" % ["forward_plus" if forward else "compatibility", RenderingServer.get_video_adapter_name()])
	for member: Array in CAST:
		var body := RiggedBody.new()
		add_child(body)
		body.position = C + Vector3(float(member[3]), 0.0, 0.0)
		body.rotation.y = PI  # bodies face -Z; turn them to the camera
		var built := body.setup(member[0])
		body.hold(String(member[1]), float(member[2]))
		_lines.append("built %s %s = %s" % [member[0]["body"], member[0]["outfit"], str(built)])
	for member: Array in GAME_CAST:
		var body := RiggedBody.build(AppearanceData.db().sanitize(member[0]))
		if body == null:
			_lines.append("RiggedBody.build returned null")
			continue
		add_child(body)
		body.position = C + Vector3(float(member[4]) + 1.3, 0.0, -3.0)
		body.rotation.y = PI
		_driven.append([body, float(member[1]), bool(member[2]), String(member[3])])
		if bool(member[2]):
			var gun := WeaponModels.build("pistol_basic" if _driven.size() == 1 else "ak47")
			gun.position = Vector3.ZERO
			(body.call("hand_anchor") as Node3D).add_child(gun)  # as game/remote_player.gd does
			body.call("support", gun.get_node_or_null("Support"))
		if _driven.size() == 1:
			var cigarette := CigaretteModel.build()
			cigarette.position = Vector3(0.035, 0.05, -0.098)
			cigarette.rotation_degrees.x = 10.0
			(body.call("head_anchor") as Node3D).add_child(cigarette)
	# Staff as the casino builds them (game/npc_body.gd): a dealer with her arms out, and the lifeguard seen from behind.
	var dealer := NpcBody.build({"gender": "female", "height": 1.0, "skin": 2, "hair": "twin_buns", "hair_color": "#e86aa0", "face": "happy", "outfit": "casino_pink"})
	add_child(dealer)
	dealer.position = C + Vector3(-1.2, 0.0, 6.0)
	dealer.rotation.y = PI
	(dealer.get_node("Torso/ArmL") as Node3D).rotation = Vector3(0.75, 0.0, 0.15)
	(dealer.get_node("Torso/ArmR") as Node3D).rotation = Vector3(1.3, 0.0, -0.15)
	(dealer.get_node("Torso/Head") as Node3D).rotation.y = 0.5
	var guard := NpcBody.build({"gender": "female", "height": 1.0, "skin": 2, "hair": "ponytail", "hair_color": "#e8c36a", "face": "happy", "outfit": "lifeguard"})
	add_child(guard)
	guard.position = C + Vector3(0.4, 0.0, 6.0)
	guard.rotation.y = PI * 0.2
	_driven.append([dealer, 0.0, false, ""])
	_driven.append([guard, 0.0, false, ""])
	# Club people as game/club_island.gd makes them, moved by the club's own animation code.
	var party := PartyPeople.new()
	add_child(party)
	var roles := [["dancer", false], ["performer", true], ["dj", false], ["sitter", false]]
	for i in roles.size():
		var person := PartyPeople.build(PartyPeople.TILE_COLORS[i], Color(0.15, 0.15, 0.3), Color.html("#c68642"), Color.html(["#2b1d14", "#e86aa0", "#d8c690", "#111111"][i]), bool(roles[i][1]))
		add_child(person)
		person.position = C + Vector3(-4.6 + i * 1.1, 0.0, 6.0)
		person.rotation.y = PI
		party.add_person(person, String(roles[i][0]), 0.4 + i)
	# The same woman at the low and the high end of the weight / chest / glutes sliders, seen from the side.
	for i in 2:
		var shaped := RiggedBody.build(AppearanceData.db().sanitize({"gender": "female", "rig_outfit": "peasant", "skin": 3, "weight": [0.8, 1.4][i], "bust": [0.0, 1.0][i], "glutes": [0.0, 1.0][i]}))
		add_child(shaped)
		shaped.position = C + Vector3(3.2 + i * 1.0, 0.0, 6.0)
		shaped.rotation.y = PI * 0.5
		_driven.append([shaped, 0.0, false, ""])
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	style.apply("high", "realistic")
	var only := ""  # user argument --views=a,b renders just those views
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--views="):
			only = "," + arg.trim_prefix("--views=") + ","
	for view: Array in VIEWS:
		if only != "" and not only.contains("," + String(view[0]) + ","):
			continue
		cam.position = view[1]
		cam.look_at(view[2], Vector3.UP)
		await _frames(40 if forward else 12)
		var started := Time.get_ticks_usec()
		await _frames(10)
		var ms := float(Time.get_ticks_usec() - started) / 10000.0
		get_viewport().get_texture().get_image().save_jpg("res://tools/shots/character_%s%s.jpg" % [view[0], suffix], 0.9)
		_lines.append("%s draws=%d tris=%d frame_ms=%.2f" % [view[0],
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)), ms])
	for entry: Array in _driven:
		var skeleton: Skeleton3D = (entry[0] as Node3D).call("skeleton")
		var hand := (entry[0] as Node3D).global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand_r"))
		_lines.append("hand_r in body space: at %s x %s y %s z %s" % [str(hand.origin.snapped(Vector3.ONE * 0.001)), str(hand.basis.x.snapped(Vector3.ONE * 0.01)), str(hand.basis.y.snapped(Vector3.ONE * 0.01)), str(hand.basis.z.snapped(Vector3.ONE * 0.01))])
	_lines.append("CHARACTER_SHOT_DONE")
	var f := FileAccess.open("res://tools/character_shot%s.log" % suffix, FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	if not forward and not OS.get_cmdline_user_args().has("--compat-only") and RendererSwitch.relaunch_if_needed("forward_plus", get_tree(), SCENE):
		return
	get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	for entry: Array in _driven:
		if String(entry[3]) != "":
			DancePoses.apply(entry[0] as Node3D, String(entry[3]), 0.9, PI)  # one fixed moment of the dance, facing the camera
		else:
			(entry[0] as Node3D).call("animate", float(entry[1]), bool(entry[2]))


func _frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
