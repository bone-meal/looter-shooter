# Purpose: one ship at sea (sea step 5a) as a thing in the world: a moving solid you can walk on (hull from the deck
# down, bulwarks, mast; built from the same data/sea/ships.json numbers as its model), its model (dressed with the
# fantasy materials), and its pose: riding the sea's waves (heave, pitch, roll from the surface under bow, stern
# and both sides, plus the wind's lean), with the sail furled or set, the yard braced, the pennant flying down-wind,
# the wheel turned with the rudder, the anchor shown raised or let go and the oars swept while rowing. Its state
# (position, heading, speed, stage) is core/sea/ship_rules.gd's, in sea coordinates; game/sea_ships.gd steps it.
# Dependencies: core/sea/ship_rules.gd, core/sea/sea_waves.gd (passed in), game/fantasy_models.gd (materials).
extends AnimatableBody3D

const FantasyModels = preload("res://game/fantasy_models.gd")

var state: Dictionary  # core/sea/ship_rules.gd state (sea coordinates)
var spec: Dictionary  # data/sea/ships.json ships[id]
var rules: RefCounted  # core/sea/ship_rules.gd

var _parts := {}  # model node name -> Node3D
var _yards: Array = []  # one per mast
var _sails: Array = []
var _jibs: Array = []  # head sails (no yard)
var _heave := 0.0
var _pitch := 0.0
var _roll := 0.0
var _sail_shown := 0.0
var _wheel := 0.0
var _oars_t := 0.0
var _wind_flutter := 0.0
var _swift_on := false
var _swift_parts: Array = []  # [sail mesh, its layers] hidden while the swift sail is set, and the swift sails shown
var lower := 0.0  # metres she sits lower than the waves carry her (water in the hold, sinking: game/sea_hull.gd)
var list_deg := 0.0  # degrees she lists to port (flooding, sinking)


func setup(ship_rules: RefCounted, ship_state: Dictionary) -> void:
	rules = ship_rules
	state = ship_state
	spec = rules.call("spec", String(state["ship"]))
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	_build_solid()
	_build_model()


# --- the solid you walk on ---

func _build_solid() -> void:
	var deck := float(spec["deck"])
	var draft := float(spec["draft"])
	var bul := float(spec["bulwark"])
	var outline: Array = spec["outline"]
	var points := PackedVector3Array()
	for station: Array in outline:
		var hw := maxf(float(station[1]), 0.05)
		var z := float(station[0])
		for side: float in [1.0, -1.0]:
			points.append(Vector3(side * hw, deck, z))
			points.append(Vector3(side * hw * 0.6, -draft, z))
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	_add_shape(hull, Transform3D.IDENTITY)
	for i in range(1, outline.size()):  # the bulwarks: a thin wall along every stretch of the rail, both sides
		var a: Array = outline[i - 1]
		var b: Array = outline[i]
		for side: float in [1.0, -1.0]:
			var p0 := Vector2(side * (maxf(float(a[1]), 0.08) - 0.07), float(a[0]))
			var p1 := Vector2(side * (maxf(float(b[1]), 0.08) - 0.07), float(b[0]))
			var box := BoxShape3D.new()
			box.size = Vector3(0.14, maxf(bul, 0.05), p0.distance_to(p1) + 0.1)
			var mid := (p0 + p1) * 0.5
			_add_shape(box, Transform3D(Basis(Vector3.UP, atan2(p1.x - p0.x, p1.y - p0.y)), Vector3(mid.x, deck + bul * 0.5, mid.y)))
	var stern: Array = outline[0]
	var transom := BoxShape3D.new()
	transom.size = Vector3(float(stern[1]) * 2.0, maxf(bul, 0.05), 0.14)
	_add_shape(transom, Transform3D(Basis.IDENTITY, Vector3(0.0, deck + bul * 0.5, float(stern[0]) - 0.07)))
	for level: Dictionary in spec.get("levels", []):  # raised decks you walk up to, and the stairs
		var z0 := float(level["from"])
		var z1 := float(level["to"])
		var hw := minf(float(rules.call("half_width", String(state["ship"]), z0)), float(rules.call("half_width", String(state["ship"]), z1)))
		hw = maxf(hw, float(rules.call("half_width", String(state["ship"]), (z0 + z1) * 0.5)) * 0.9) - 0.15
		var raised := BoxShape3D.new()
		raised.size = Vector3(hw * 2.0, float(level["height"]), z1 - z0)
		_add_shape(raised, Transform3D(Basis.IDENTITY, Vector3(0.0, deck + float(level["height"]) * 0.5, (z0 + z1) * 0.5)))
		for stair: Dictionary in level["stairs"]:
			var run := float(stair["high"]) - float(stair["low"])
			var ramp := BoxShape3D.new()
			ramp.size = Vector3(1.0, 0.1, sqrt(run * run + pow(float(level["height"]), 2.0)))
			var slope := -atan2(float(level["height"]), absf(run)) * signf(run)  # the +z end rises when the stairs climb towards +z
			_add_shape(ramp, Transform3D(Basis(Vector3.RIGHT, slope), Vector3(float(stair["x"]), deck + float(level["height"]) * 0.5 - 0.05, (float(stair["low"]) + float(stair["high"])) * 0.5)))
	for spot: Array in spec["masts"]:
		var mast := CylinderShape3D.new()
		mast.radius = 0.18
		mast.height = float(spot[1])
		_add_shape(mast, Transform3D(Basis.IDENTITY, Vector3(0.0, deck + mast.height * 0.5, float(spot[0]))))


func _add_shape(shape: Shape3D, at: Transform3D) -> void:
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.transform = at
	add_child(holder)


# --- the model ---

func _build_model() -> void:
	var path := String(spec["model"])
	if not ResourceLoader.exists(path):
		var stand_in := MeshInstance3D.new()  # not imported yet: a plain hull-sized box
		var box := BoxMesh.new()
		box.size = Vector3(float(spec["outline"][2][1]) * 2.0, float(spec["deck"]) + float(spec["draft"]), absf(float(spec["outline"][0][0]) - float(spec["outline"].back()[0])))
		stand_in.mesh = box
		stand_in.position.y = (float(spec["deck"]) - float(spec["draft"])) * 0.5
		add_child(stand_in)
		return
	var model := (load(path) as PackedScene).instantiate() as Node3D
	add_child(model)
	for found in model.find_children("*", "MeshInstance3D", true, false):
		FantasyModels.dress((found as MeshInstance3D).mesh)
	for i in (spec["masts"] as Array).size():  # one yard + sail per mast: Yard / Sail, Yard2 / Sail2 ...
		var suffix := "" if i == 0 else str(i + 1)
		for part: String in ["Yard", "Sail"]:
			var node := model.find_child(part + suffix, true, false) as Node3D
			if node != null:
				(_yards if part == "Yard" else _sails).append(node)
	for jib in model.find_children("Jib*", "", true, false):  # head sails on the bowsprit set and furl with the rest
		_jibs.append(jib)
	for part: String in ["Yard", "Sail", "Pennant", "Wheel", "Anchor", "AnchorRope", "OarsL", "OarsR"]:
		var node := model.find_child(part, true, false) as Node3D
		if node != null:
			_parts[part] = node


# --- a pirate's look (sea step 8): dark sails, a black pennant and a black flag at the masthead ---

var _flag: MeshInstance3D = null
static var _flag_tex: ImageTexture


func dress_foe(sails: Color) -> void:
	if _flag != null:
		return
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = sails
	cloth.roughness = 0.95
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	for sail: Node in _sails + _jibs:
		for found: MeshInstance3D in _meshes(sail):
			found.material_override = cloth
	if _parts.has("Pennant"):
		var black := StandardMaterial3D.new()
		black.albedo_color = Color(0.05, 0.05, 0.05)
		black.cull_mode = BaseMaterial3D.CULL_DISABLED
		for found: MeshInstance3D in _meshes(_parts["Pennant"]):
			found.material_override = black
	var mast: Array = (spec["masts"] as Array)[0]
	_flag = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.8, 1.2)
	quad.center_offset = Vector3(0.9, 0.0, 0.0)  # hoisted by its left edge
	_flag.mesh = quad
	var art := StandardMaterial3D.new()
	art.albedo_texture = _jolly()
	art.cull_mode = BaseMaterial3D.CULL_DISABLED
	art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	_flag.material_override = art
	_flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flag.position = Vector3(0.0, float(spec["deck"]) + float(mast[1]) + 0.9, float(mast[0]))
	add_child(_flag)


# She strikes her colours (sea step 8b: her crew is beaten): the black flag comes down the mast and is gone.
func strike_colours() -> void:
	if _flag == null or not _flag.visible:
		return
	var tween := create_tween()
	tween.tween_property(_flag, "position:y", float(spec["deck"]) + 1.2, 3.0).set_ease(Tween.EASE_IN)
	tween.tween_callback(_flag.hide)


static func _meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for found in node.find_children("*", "MeshInstance3D", true, false):
		out.append(found)
	return out


# Our own pirate flag, drawn once: a white skull over two crossed cutlasses on black.
static func _jolly() -> ImageTexture:
	if _flag_tex != null:
		return _flag_tex
	var w := 96
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var c := Color(0.04, 0.04, 0.05)
			var p := Vector2(x - 48, y - 26)
			if Vector2(p.x, p.y * 1.1).length() < 13.0 and y < 34:
				c = Color(0.93, 0.92, 0.86)  # the skull's dome
			if absf(p.x) < 8.0 and y >= 30 and y < 40:
				c = Color(0.93, 0.92, 0.86)  # the jaw
			for eye: float in [-5.0, 5.0]:
				if Vector2(p.x - eye, p.y - 1.0).length() < 3.2:
					c = Color(0.04, 0.04, 0.05)
			if y >= 36 and y < 40 and int(x) % 3 == 0 and absf(p.x) < 7.0:
				c = Color(0.04, 0.04, 0.05)  # teeth
			for s: float in [1.0, -1.0]:  # two cutlasses crossed under the skull, blade up
				var along := (p.x * s + (p.y - 30.0)) / sqrt(2.0)
				var off := (p.x * s - (p.y - 30.0)) / sqrt(2.0)
				if along > -20.0 and along < 18.0 and absf(off) < 1.8 + (0.8 if along > 10.0 else 0.0):
					c = Color(0.85, 0.85, 0.88) if along > -12.0 else Color(0.6, 0.45, 0.2)
			img.set_pixel(x, y, c)
	_flag_tex = ImageTexture.create_from_image(img)
	return _flag_tex


# --- each frame ---

# Puts the ship where its state says, riding the waves. waves: core/sea/sea_waves.gd; t = the sea clock; swell in m.
func pose(waves: RefCounted, t: float, swell: float, wind: float, wind_dir: float, delta: float) -> void:
	var yaw := float(state["yaw"])
	var x := float(state["x"])
	var z := float(state["z"])
	var bow := Vector2(-sin(yaw), -cos(yaw))
	var starboard := Vector2(cos(yaw), -sin(yaw))
	var length := absf(float(spec["outline"][0][0]) - float(spec["outline"].back()[0])) * 0.42
	var beam := float(spec["outline"][2][1]) * 0.9
	var h_bow := float(waves.call("height_at", x + bow.x * length, z + bow.y * length, t, swell))
	var h_stern := float(waves.call("height_at", x - bow.x * length, z - bow.y * length, t, swell))
	var h_star := float(waves.call("height_at", x + starboard.x * beam, z + starboard.y * beam, t, swell))
	var h_port := float(waves.call("height_at", x - starboard.x * beam, z - starboard.y * beam, t, swell))
	var tilt: Dictionary = spec["tilt"]
	var pitch := clampf(atan2(h_bow - h_stern, length * 2.0), -deg_to_rad(float(tilt["pitch_max"])), deg_to_rad(float(tilt["pitch_max"])))
	var roll := clampf(atan2(h_port - h_star, beam * 2.0), -deg_to_rad(float(tilt["roll_max"])), deg_to_rad(float(tilt["roll_max"])))
	roll += deg_to_rad(float(rules.call("heel", state, wind, wind_dir)))
	var k := 1.0 - exp(-float(tilt["follow"]) * delta) if delta > 0.0 else 1.0
	_heave = lerpf(_heave, (h_bow + h_stern + h_star + h_port) * 0.25, k)
	_pitch = lerpf(_pitch, pitch, k)
	_roll = lerpf(_roll, roll, k)
	var turn := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, _pitch) * Basis(Vector3.BACK, -_roll - deg_to_rad(list_deg))
	transform = Transform3D(turn, Vector3(x, _heave - lower, z))
	_animate(wind, wind_dir, delta)


func _animate(wind: float, wind_dir: float, delta: float) -> void:
	var stage: Dictionary = rules.call("stage", state)
	var anchored := bool(state["anchored"])
	_sail_shown = move_toward(_sail_shown, float(stage["sail"]), delta * 0.6)
	for sail: Node3D in _sails:
		sail.scale = Vector3(1.0, lerpf(0.07, 1.0, _sail_shown), 1.0 + 0.15 * (1.0 - _sail_shown))
	for jib: Node3D in _jibs:
		jib.scale = Vector3.ONE * lerpf(0.05, 1.0, _sail_shown)
	var swift := bool(stage.get("swift", false))
	if swift != _swift_on:
		_show_swift(swift)
	var to := Basis(Vector3.UP, float(state["yaw"])).inverse() * Vector3(cos(wind_dir), 0.0, sin(wind_dir))  # down-wind, ship space
	var across := atan2(-to.x, -to.z)  # where the wind blows to, from the bow (0 = dead ahead)
	for yard: Node3D in _yards:  # braced round so the wind fills the sail
		yard.rotation.y = lerp_angle(yard.rotation.y, clampf(across * 0.45, -0.7, 0.7), delta * 1.5)
	if _flag != null:  # a pirate's flag streams down-wind
		_flag.rotation = Vector3(0.0, atan2(to.x, to.z) - PI * 0.5 + sin(_wind_flutter * 1.3) * 0.15, 0.0)
	if _parts.has("Pennant"):
		_wind_flutter += delta * (4.0 + wind * 8.0)
		(_parts["Pennant"] as Node3D).rotation = Vector3(0.0, atan2(to.x, to.z) + sin(_wind_flutter) * 0.12 * (0.3 + wind), sin(_wind_flutter * 1.7) * 0.15)
	_wheel = lerpf(_wheel, float(state["rudder"]) * 2.4, minf(delta * 5.0, 1.0))
	if _parts.has("Wheel"):
		if String(spec.get("steer", "wheel")) == "tiller":  # a tiller or steering oar swings the other way to the turn
			(_parts["Wheel"] as Node3D).rotation.y = _wheel * 0.22
		else:
			(_parts["Wheel"] as Node3D).rotation.z = -_wheel
	if _parts.has("Anchor"):
		(_parts["Anchor"] as Node3D).visible = not anchored
	if _parts.has("AnchorRope"):
		(_parts["AnchorRope"] as Node3D).visible = anchored
	var rowing := not anchored and absf(float(stage["oars"])) > 0.0
	_oars_t += delta * (2.2 if rowing else 0.0)
	for side: String in ["OarsL", "OarsR"]:
		if _parts.has(side):
			var oars := _parts[side] as Node3D
			oars.visible = rowing
			oars.rotation.y = sin(_oars_t * signf(float(stage["oars"]) + 0.001)) * 0.32 * (1.0 if side == "OarsR" else -1.0)


const SWIFT_MODEL := "res://assets/models/sea/swift_sail.gltf"


# The swift sail (sea step 5e; director: "needs new model"): every sail of hers is covered by the crimson-and-cream
# swift sail (assets/models/sea/swift_sail.gltf, tools/blender/sea_swift_sail.py) stretched to its size, her own
# cloth and head sails hidden; back to her own sails when the stage is left. Made the first time it is set.
func _show_swift(on: bool) -> void:
	_swift_on = on
	if on and _swift_parts.is_empty() and ResourceLoader.exists(SWIFT_MODEL):
		for sail: Node3D in _sails:
			var meshes: Array = []
			if sail is MeshInstance3D:
				meshes.append(sail)
			for found in sail.find_children("*", "MeshInstance3D", true, false):
				meshes.append(found)
			if meshes.is_empty():
				continue
			var box := AABB()
			var first := true
			for mesh: MeshInstance3D in meshes:
				var into := sail.global_transform.affine_inverse() * mesh.global_transform
				var part := into * mesh.get_aabb()
				box = part if first else box.merge(part)
				first = false
				_swift_parts.append([mesh, mesh.layers])
			var cover := (load(SWIFT_MODEL) as PackedScene).instantiate() as Node3D
			for found in cover.find_children("*", "MeshInstance3D", true, false):
				var piece := found as MeshInstance3D
				FantasyModels.dress(piece.mesh)
				for i in piece.mesh.get_surface_count():
					var mat := piece.mesh.surface_get_material(i)
					if mat is BaseMaterial3D:
						var both := (mat as BaseMaterial3D).duplicate() as BaseMaterial3D
						both.cull_mode = BaseMaterial3D.CULL_DISABLED  # seen from the deck and from the sea
						piece.set_surface_override_material(i, both)
			sail.add_child(cover)
			var size := box.size
			var fore_aft := size.x < size.z  # a gaff / lateen / batten sail lies along her, a square sail across
			var wide := size.z if fore_aft else size.x
			var deep := clampf(minf(wide, size.y) * 0.25, 0.4, 2.0)
			var turn := Basis(Vector3.UP, -PI * 0.5) if fore_aft else Basis.IDENTITY  # bellying out to leeward / forward
			cover.transform = Transform3D(turn * Basis.from_scale(Vector3(wide * 0.5, size.y * 0.5, deep)), box.get_center())
			_swift_parts.append([cover, -1])
	for pair: Array in _swift_parts:
		var node := pair[0] as Node3D
		if int(pair[1]) < 0:
			node.visible = on
		else:
			(node as MeshInstance3D).layers = 0 if on else int(pair[1])
	for jib: Node3D in _jibs:
		jib.visible = not on


# Ship space -> scene, and a deck spot (data [x, z]) as a scene position at deck height.
func deck_spot(spot: Array, up: float = 0.0) -> Vector3:
	return global_transform * Vector3(float(spot[0]), float(rules.call("deck_height", String(state["ship"]), float(spot[1]))) + up, float(spot[1]))
