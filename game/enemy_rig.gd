# Purpose: (polish1 D2) the procedural animation of the reworked enemies: rigid parts on named pivots (Hips, Spine, Head,
# Jaw, ArmL / ForeL, ArmR / ForeR, LegL / ShinL, LegR / ShinR, plus any extra pivots a style's oscillators name, e.g. a
# crab's legs and claws) turned every frame from a STYLE in data/enemy_moves.json: the gait (stride, knees, arm swing,
# bob, sway, twist, lean, crouch, raised arms, limp, a jerky stepped walk, a lolling head), the idle (breathing, looking
# round, twitches), free oscillators, the attack (wind-up and strike poses for blows, aim and recoil poses for shots),
# the flinch of a hit and the way it dies (slump or crumble). Also picks the body's VARIANT: nodes named V1_..., V2_...
# in the model; one number is kept, the other numbers' nodes are hidden.
# No allocation per frame: the style is read once into arrays of (pivot index, angles).
# Dependencies: data/enemy_moves.json (handed in), the model's pivots. Used by game/enemy.gd.
extends RefCounted

const PIVOTS := ["Hips", "Spine", "Head", "Jaw", "ArmL", "ForeL", "ArmR", "ForeR", "LegL", "ShinL", "LegR", "ShinR"]
enum {HIPS, SPINE, HEAD, JAW, ARM_L, FORE_L, ARM_R, FORE_R, LEG_L, SHIN_L, LEG_R, SHIN_R}

var _nodes: Array[Node3D] = []  # PIVOTS first, then the oscillators' own pivots (node mode)
var _skel: Skeleton3D  # (game/rigid_skin.gd) the folded model: the same pivots are bones, turned instead of nodes
var _bones := PackedInt32Array()  # bone per pivot (-1 = the model has none)
var _rest: PackedVector3Array = PackedVector3Array()
var _rot: PackedVector3Array = PackedVector3Array()  # this frame's sum, per pivot
var _hips_y := 0.0
var _g := {}  # gait numbers
var _i := {}  # idle numbers
var _osc: Array = []  # [pivot index, axis 0..2, amplitude, phase offset, rate (0 = with the stride), with speed, spin]
var _poses := {}  # "wind" / "strike" / "aim" / "recoil" -> [[pivot index, Vector3 radians], ...]
var _death := "slump"
var _seed := 0.0
var _t := 0.0
var _recoil := 0.0
var _dying := -1.0
var _scatter: PackedVector3Array = PackedVector3Array()


static func rigged(model: Node3D) -> bool:
	return model.find_child("Hips", true, false) != null


func setup(model: Node3D, style: Dictionary, rng: RandomNumberGenerator) -> void:
	_seed = rng.randf() * 100.0
	_g = style.get("gait", {})
	_i = style.get("idle", {})
	_death = String(style.get("death", "slump"))
	var names: Array = PIVOTS.duplicate()
	for o: Dictionary in style.get("osc", []):
		if not names.has(String(o["node"])):
			names.append(String(o["node"]))
	for kind: String in ["wind", "strike", "aim", "recoil"]:
		for n: String in (style.get(kind, {}) as Dictionary):
			if not names.has(n):
				names.append(n)
	_skel = model.get_node_or_null("RigidSkin") as Skeleton3D
	for n: String in names:
		if _skel != null:
			var bone := _skel.find_bone(n)
			_bones.append(bone)
			_nodes.append(null)
			_rest.append(_skel.get_bone_rest(bone).basis.get_euler() if bone >= 0 else Vector3.ZERO)
		else:
			var node := model.find_child(n, true, false) as Node3D
			_nodes.append(node)
			_bones.append(-1)
			_rest.append(node.rotation if node != null else Vector3.ZERO)
		_rot.append(Vector3.ZERO)
		_scatter.append(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)))
	if _skel != null and _bones[HIPS] >= 0:
		_hips_y = _skel.get_bone_rest(_bones[HIPS]).origin.y
	elif _nodes[HIPS] != null:
		_hips_y = _nodes[HIPS].position.y
	for o: Dictionary in style.get("osc", []):
		_osc.append([names.find(String(o["node"])), ["x", "y", "z"].find(String(o.get("axis", "x"))), deg_to_rad(float(o.get("amp", 20.0))),
			deg_to_rad(float(o.get("phase", 0.0))), float(o.get("rate", 0.0)), bool(o.get("with_speed", true)), bool(o.get("spin", false))])
	for kind: String in ["wind", "strike", "aim", "recoil"]:
		var list: Array = []
		var src: Dictionary = style.get(kind, {})
		for n: String in src:
			var a: Array = src[n]
			list.append([names.find(n), Vector3(deg_to_rad(float(a[0])), deg_to_rad(float(a[1])), deg_to_rad(float(a[2])))])
		_poses[kind] = list
	_choose_variant(model, rng, int(style.get("variants", 0)))


# Keeps one of the model's variants (V1_..., V2_..., ...): `count` 0 = as many as the model has.
func _choose_variant(model: Node3D, rng: RandomNumberGenerator, count: int) -> void:
	if _skel != null:  # folded: a variant's bones not kept shrink to nothing
		var most_b := 0
		for b in _skel.get_bone_count():
			if _skel.get_bone_name(b).match("V?_*"):
				most_b = maxi(most_b, _skel.get_bone_name(b).substr(1, 1).to_int())
		if most_b == 0:
			return
		var keep_b := rng.randi_range(1, most_b if count <= 0 else mini(count, most_b))
		for b in _skel.get_bone_count():
			var bone_name := _skel.get_bone_name(b)
			if bone_name.match("V?_*") and bone_name.substr(1, 1).to_int() != keep_b:
				_skel.set_bone_pose_scale(b, Vector3.ZERO)
		return
	var found := model.find_children("V?_*", "Node3D", true, false)
	if found.is_empty():
		return
	var most := 0
	for node in found:
		most = maxi(most, String(node.name).substr(1, 1).to_int())
	var keep := rng.randi_range(1, most if count <= 0 else mini(count, most))
	for node in found:
		(node as Node3D).visible = String(node.name).substr(1, 1).to_int() == keep


func fired() -> void:
	_recoil = 1.0


func die() -> void:
	_dying = 0.0


func _add(i: int, v: Vector3) -> void:
	_rot[i] += v


# Angles (radians, about the pivot): x+ swings a hanging limb FORWARD and tips the torso / head BACK; a knee bends
# with shin x-; the left arm goes out with z-, the right with z+. One frame. speed = m/s over the ground, phase = the stride's angle, tell = 0..1 into a wind-up, lunge = 1..0 after a
# blow, swing = 1..0 of a quick blow without wind-up, flinch = 1..0 after a hit, ranged = it shoots.
func pose(delta: float, speed: float, phase: float, tell: float, lunge: float, swing: float, flinch: float, ranged: bool) -> void:
	_t += delta
	_recoil = move_toward(_recoil, 0.0, delta * 5.0)
	for k in _rot.size():
		_rot[k] = Vector3.ZERO
	var w := clampf(speed / maxf(float(_g.get("full_at", 3.0)), 0.1), 0.0, 1.0)
	phase *= float(_g.get("cadence", 1.0))  # steps per metre against the game's usual stride
	if float(_g.get("jerk", 0.0)) > 0.0:  # a stepped, rattling walk
		phase = lerpf(phase, roundf(phase / (PI / 4.0)) * (PI / 4.0), float(_g["jerk"]))
	var s := sin(phase)
	var c := cos(phase)
	var leg := deg_to_rad(float(_g.get("leg", 35.0))) * w
	var limp := float(_g.get("limp", 0.0))
	_add(LEG_L, Vector3(leg * s, 0, 0))
	_add(LEG_R, Vector3(-leg * s * (1.0 - limp), 0, 0))
	var knee := deg_to_rad(float(_g.get("knee", 45.0))) * w
	var crouch := deg_to_rad(float(_g.get("crouch", 0.0)))
	_add(SHIN_L, Vector3(-knee * maxf(c, 0.0) - crouch * 1.6, 0, 0))
	_add(SHIN_R, Vector3(-knee * maxf(-c, 0.0) * (1.0 - limp) - crouch * 1.6, 0, 0))
	_add(LEG_L, Vector3(crouch * 0.8, 0, 0))
	_add(LEG_R, Vector3(crouch * 0.8, 0, 0))
	var arm := deg_to_rad(float(_g.get("arm", 25.0))) * w
	var up := deg_to_rad(float(_g.get("arms_up", 0.0)))
	var elbow := deg_to_rad(float(_g.get("elbow", 15.0)))
	_add(ARM_L, Vector3(-arm * s + up, 0, -deg_to_rad(float(_g.get("arm_out", 6.0)))))  # +x = forward, -z = out for the left arm
	_add(ARM_R, Vector3(arm * s + up, 0, deg_to_rad(float(_g.get("arm_out", 6.0)))))
	_add(FORE_L, Vector3(elbow + arm * 0.4 * maxf(-s, 0.0), 0, 0))
	_add(FORE_R, Vector3(elbow + arm * 0.4 * maxf(s, 0.0), 0, 0))
	var lean := deg_to_rad(float(_g.get("lean", 8.0))) * w + crouch * 0.6
	_add(SPINE, Vector3(-lean, deg_to_rad(float(_g.get("twist", 6.0))) * s * w, deg_to_rad(float(_g.get("sway", 3.0))) * s * w + limp * 0.12 * s * w))
	var loll := deg_to_rad(float(_g.get("head_loll", 0.0)))
	_add(HEAD, Vector3(loll * sin(_t * 0.9 + _seed) + lean * 0.5, 0, loll * sin(_t * 0.6 + _seed * 2.0)))
	var hips_y := _hips_y + float(_g.get("bob", 0.04)) * w * absf(s) - crouch * 0.12
	if _skel != null and _bones[HIPS] >= 0:
		var at := _skel.get_bone_rest(_bones[HIPS]).origin
		_skel.set_bone_pose_position(_bones[HIPS], Vector3(at.x, hips_y, at.z))
	elif _nodes[HIPS] != null:
		_nodes[HIPS].position.y = hips_y
	# idle: breathing, looking round, twitches (fading as it walks)
	var still := 1.0 - w
	_add(SPINE, Vector3(deg_to_rad(float(_i.get("breath", 2.0))) * sin(_t * 1.8 + _seed) * still, 0, 0))
	_add(HEAD, Vector3(0, deg_to_rad(float(_i.get("look", 20.0))) * sin(_t * 0.45 + _seed) * still, 0))
	var twitch := float(_i.get("twitch", 0.0))
	if twitch > 0.0:
		var jolt := maxf(sin(_t * 7.3 + _seed) * sin(_t * 2.1), 0.0)
		_add(HEAD, Vector3(0, 0, deg_to_rad(25.0) * twitch * jolt * jolt * jolt))
	var jaw := deg_to_rad(float(_i.get("jaw", 0.0)))
	_add(JAW, Vector3(jaw * absf(sin(_t * float(_i.get("jaw_rate", 2.0)) + _seed)), 0, 0))
	for o: Array in _osc:
		var rate := float(o[4])
		var a := (_t * rate if rate > 0.0 else phase) + float(o[3])
		var amount := float(o[2]) * sin(a) * (w if bool(o[5]) else 1.0)
		if bool(o[6]):  # spin: turns on and on (`rate` turns a second; amp ignored)
			amount = fmod(_t * rate * TAU, TAU)
		var v := Vector3.ZERO
		v[int(o[1])] = amount
		_add(int(o[0]), v)
	# attack
	var wind := tell if tell > 0.0 else (clampf((swing - 0.5) * 2.0, 0.0, 1.0) if swing > 0.0 else 0.0)
	var strike := maxf(lunge, clampf(1.0 - swing * 2.0, 0.0, 1.0) if swing > 0.0 else 0.0)
	_blend("wind", wind * (1.0 - strike))
	_blend("strike", strike)
	if ranged:
		_blend("aim", 1.0 - 0.6 * w)
		_blend("recoil", _recoil)
	_add(SPINE, Vector3(deg_to_rad(20.0) * flinch, 0, 0))  # thrown back
	_add(HEAD, Vector3(deg_to_rad(18.0) * flinch, 0, 0))
	if _dying >= 0.0:  # slump: it goes limp; crumble: every piece turns its own way (bones falling apart)
		_dying += delta
		var f := clampf(_dying / 0.5, 0.0, 1.0)
		for k in _rot.size():
			_rot[k] = _rot[k].lerp(_scatter[k] * (1.4 if _death == "crumble" else 0.35), f)
		_add(ARM_L, Vector3(-0.3, 0, -0.35) * f)
		_add(ARM_R, Vector3(-0.3, 0, 0.35) * f)
	for k in _nodes.size():
		if _bones[k] >= 0:
			_skel.set_bone_pose_rotation(_bones[k], Quaternion.from_euler(_rest[k] + _rot[k]))
		elif _nodes[k] != null:
			_nodes[k].rotation = _rest[k] + _rot[k]


func _blend(pose_name: String, weight: float) -> void:
	if weight <= 0.0:
		return
	for entry: Array in _poses.get(pose_name, []):
		if int(entry[0]) >= 0:
			_add(int(entry[0]), (entry[1] as Vector3) * weight)
