# Purpose: the sea tools' held models and their moves (sea step 9b; director: "only tool or gun seen in hand, needs
# animations, other players should see other tools"): one place that builds a tool for a hand (first person, the
# own body in third person, other players' bodies) and plays its moves on it with tweens, the same on every machine:
#   draw (comes up into the hand), use (each tool its own: the hook kicks and its head flies, the bell swings and
#   rings, the gauntlet punches and its coal flares, the anchor winds up and is thrown, the glider's wings unfold,
#   the pearl is held up and glows, the compass is held up and its needle spins), and put_away.
# Dependencies: assets/models/sea/tools/*.gltf (tools/blender/sea_tools.py), data/sea/tools.json, game/fx_kit.gd.
extends RefCounted

const FxKit = preload("res://game/fx_kit.gd")
const MODEL := "res://assets/models/sea/tools/%s.gltf"

static var _cfg := {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/tools.json"))
	return _cfg


# The tool's model in a holder node (the holder carries the moves; the model keeps its own offset in the hand).
static func build(tool: String) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Tool_" + tool
	holder.set_meta("tool", tool)
	var t: Dictionary = cfg()["tools"].get(tool, {})
	var path := MODEL % String(t.get("model", "tl_" + tool))
	var model: Node3D
	if ResourceLoader.exists(path):
		model = (load(path) as PackedScene).instantiate() as Node3D
	else:
		model = MeshInstance3D.new()
		(model as MeshInstance3D).mesh = BoxMesh.new()
		model.scale = Vector3.ONE * 0.08
	model.name = "Model"
	holder.add_child(model)
	for m: Node in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if tool == "glider":  # carried folded until it opens
		_wings(holder, 0.0)
	return holder


static func part(holder: Node3D, name: String) -> Node3D:
	return holder.find_child(name, true, false) as Node3D


static func _wings(holder: Node3D, open: float) -> void:
	var l := part(holder, "WingL")
	var r := part(holder, "WingR")
	if l != null:
		l.rotation.z = lerpf(-1.35, 0.0, open)
	if r != null:
		r.rotation.z = lerpf(1.35, 0.0, open)


# Comes up into the hand from below.
static func draw(holder: Node3D) -> void:
	var model := part(holder, "Model")
	if model == null:
		return
	model.position = Vector3(0.0, -0.25, 0.05)
	model.rotation = Vector3(-0.6, 0.0, 0.0)
	var tw := holder.create_tween().set_parallel(true).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(model, "position", Vector3.ZERO, 0.28)
	tw.tween_property(model, "rotation", Vector3.ZERO, 0.28)


# Its own move for a use. `target` (world, optional): where the hook flies, where the bolt goes.
static func use(holder: Node3D, target: Vector3 = Vector3.INF) -> void:
	var tool := String(holder.get_meta("tool", ""))
	var model := part(holder, "Model")
	if model == null or not holder.is_inside_tree():
		return
	var tw := holder.create_tween()
	match tool:
		"grapple":  # a kick back; the hook head flies out (to the ring when known) and is wound back in
			tw.tween_property(model, "position", Vector3(0.0, 0.03, 0.08), 0.06)
			tw.tween_property(model, "position", Vector3.ZERO, 0.25)
			var hook := part(holder, "Hook")
			if hook != null:
				var home := hook.position
				var out := holder.create_tween()
				if target.is_finite():
					out.tween_property(hook, "global_position", target, 0.3)
					out.tween_interval(0.9)
				else:
					out.tween_property(hook, "position", home + Vector3(0.0, 0.0, -6.0), 0.25)
				out.tween_property(hook, "position", home, 0.35)
		"bell":  # swung side to side three times; the clapper strikes
			for k in 3:
				tw.tween_property(model, "rotation", Vector3(0.0, 0.0, 0.55), 0.12)
				tw.tween_property(model, "rotation", Vector3(0.0, 0.0, -0.55), 0.16)
			tw.tween_property(model, "rotation", Vector3.ZERO, 0.12)
			var clapper := part(holder, "Clapper")
			if clapper != null:
				var c := holder.create_tween()
				for k in 3:
					c.tween_property(clapper, "rotation", Vector3(0.0, 0.0, -0.9), 0.12)
					c.tween_property(clapper, "rotation", Vector3(0.0, 0.0, 0.9), 0.16)
				c.tween_property(clapper, "rotation", Vector3.ZERO, 0.12)
			FxKit.burst(holder, holder.global_position, Color(0.75, 0.9, 1.0), 20, 1.2, 0.18, 2.5, 0.0)
		"gauntlet":  # a punch forward; the coal flares
			tw.tween_property(model, "position", Vector3(0.0, 0.04, -0.22), 0.08)
			tw.tween_property(model, "position", Vector3.ZERO, 0.22)
			var ember := part(holder, "Ember")
			if ember != null:
				var e := holder.create_tween()
				e.tween_property(ember, "scale", Vector3.ONE * 2.2, 0.08)
				e.tween_property(ember, "scale", Vector3.ONE, 0.4)
				FxKit.burst(holder, ember.global_position, Color(1.0, 0.55, 0.15), 18, 0.4, 0.06, 2.0, 1.0)
		"anchor":  # wound up over the shoulder, thrown (gone for a moment), back in the hand
			tw.tween_property(model, "rotation", Vector3(0.9, 0.0, 0.0), 0.15)
			tw.tween_property(model, "rotation", Vector3(-1.1, 0.0, 0.0), 0.1)
			tw.tween_callback(func() -> void: model.visible = false)
			tw.tween_property(model, "rotation", Vector3.ZERO, 0.01)
			tw.tween_interval(0.35)
			tw.tween_callback(func() -> void: model.visible = true)
			tw.tween_property(model, "position", Vector3(0.0, -0.2, 0.0), 0.01)
			tw.tween_property(model, "position", Vector3.ZERO, 0.2)
		"glider":  # the wings unfold
			tw.tween_method(func(k: float) -> void: _wings(holder, k), 0.0, 1.0, 0.35)
		"pearl":  # held up to the eye; it glows
			tw.tween_property(model, "position", Vector3(-0.1, 0.12, -0.05), 0.2)
			tw.tween_interval(0.6)
			tw.tween_property(model, "position", Vector3.ZERO, 0.25)
			var pearl := part(holder, "Pearl")
			if pearl != null:
				var p := holder.create_tween()
				p.tween_property(pearl, "scale", Vector3.ONE * 1.5, 0.25)
				p.tween_property(pearl, "scale", Vector3.ONE, 0.6)
				FxKit.burst(holder, pearl.global_position, Color(0.7, 0.95, 1.0), 26, 1.0, 0.05, 1.2, 0.5)
		"compass":  # held up flat before the eye; the needle spins and settles
			tw.tween_property(model, "position", Vector3(-0.08, 0.1, -0.02), 0.2)
			tw.tween_property(model, "rotation", Vector3(0.9, 0.0, 0.0), 0.15)
			var needle := part(holder, "Needle")
			if needle != null:
				var n := holder.create_tween()
				n.tween_property(needle, "rotation:y", needle.rotation.y + TAU * 3.0, 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
				if target.is_finite():
					n.tween_callback(func() -> void:
						if is_instance_valid(needle):
							needle.global_rotation.y = atan2(-(target - needle.global_position).x, -(target - needle.global_position).z))
			tw.tween_interval(1.6)
			tw.tween_property(model, "rotation", Vector3.ZERO, 0.2)
			tw.tween_property(model, "position", Vector3.ZERO, 0.2)


# Wings open (gliding) or folded, without a move (other players' bodies follow it from the held string).
static func set_open(holder: Node3D, open: bool) -> void:
	if String(holder.get_meta("tool", "")) == "glider":
		_wings(holder, 1.0 if open else 0.0)
