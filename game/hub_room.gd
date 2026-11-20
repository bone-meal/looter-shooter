# Purpose: builds the safe hub at game start (locked: diary/DECISIONS_HUB.md) at data/hub.json "center": the
# library hall, the checkerboard stage with its pillars, the sandstone pedestal and its big red button (pushed in once
# for good), candle chandeliers, the cold moon window, the endless spiral stair turning slowly behind the arch, the
# Aurelind painting's place, the trophy room next door (game/trophy_room.gd), and solid floor and walls to walk in. Its own light only: warm candles and one cold moon
# beam, no shadows (the session darkens the sky light while the player stands inside: game/game_session.gd hub_dark).
# Dependencies: game/fantasy_models.gd (models made by tools/blender/hub_room.py), data/hub.json (set `cfg` before
# add_child).
extends Node3D

const FantasyModels = preload("res://game/fantasy_models.gd")
const TrophyRoom = preload("res://game/trophy_room.gd")
const BeachTable = preload("res://game/tcg/beach_table.gd")

const CANDLE := Color(1.0, 0.7, 0.4)
const MOON := Color(0.55, 0.68, 1.0)
const CHANDELIERS := [Vector3(-12.0, 10.6, -5.0), Vector3(12.0, 10.6, -5.0), Vector3(-12.0, 10.6, 7.0), Vector3(12.0, 10.6, 7.0)]
const STAIR_AT := Vector3(0.0, 0.0, -21.0)  # the spiral's middle, behind the arch in the back wall
const STAIR_RISE := 4.2  # one turn of tools/blender/hub_room.py stair
const STAIR_TURNS := 22
const STAIR_SPIN := 0.06  # radians a second
const BUTTON_TOP := 1.45  # the pedestal's gold top
const BUTTON_DOWN := 0.15
const GLOBES := [Vector2(-6.0, 9.0), Vector2(14.0, -6.0)]  # (x, z) of the globe stands in tools/blender/hub_room.py
const GLOBE_SPIN := 0.12  # radians a second
const GLOBE_MAP := "res://assets/ui/hub_globe_map.png"  # tools/paint_globe_map.py
const FRIEZE := "res://assets/ui/hub_frieze.png"  # tools/paint_frieze.py: 4 faces stacked, each 1.3 x 0.812 m
const COBWEB := "res://assets/ui/hub_cobweb.png"  # tools/paint_cobweb.py: one corner web, its anchor top left

var cfg: Dictionary
var trophies: TrophyRoom  # the room behind the left doorway (game/trophy_room.gd)
var card_tables: Array = []  # two card tables for players (the card game's own table, game/tcg/player_table.gd runs them)
var _button: Node3D
var _spiral: Node3D
var _pressed := false
var _push := 0.0
var _globes: Array = []  # the turning balls (polish1 item 12)


func _ready() -> void:
	var c: Array = cfg["center"]
	position = Vector3(float(c[0]), float(c[1]), float(c[2]))
	for id: String in ["hub_hall", "hub_stage"]:
		_model(id, Vector3.ZERO)
	var p: Array = cfg["pedestal"]
	var at := Vector3(float(p[0]), 0.0, float(p[1]))
	_model("hub_pedestal", at)
	_frieze(at)
	_button = _model("hub_button", at + Vector3(0.0, BUTTON_TOP, 0.0))
	for spot: Vector3 in CHANDELIERS:
		_model("hub_chandelier", spot)
		_light(spot + Vector3(0.0, 0.2, 0.0), CANDLE, 2.2, 20.0)
	_light(Vector3(0.0, 4.0, -11.0), CANDLE, 0.8, 10.0)  # over the stage
	_light(Vector3(0.0, 5.5, 1.5), CANDLE, 0.7, 9.0)  # over the pedestal
	_moon()
	_make_globes()
	_cobwebs()
	_stair()
	_solids()
	for spot: Array in cfg["tables"]:
		var table := BeachTable.new()
		table.indoor = true
		table.position = Vector3(float(spot[0]), 0.0, float(spot[1]))
		table.rotation_degrees.y = 90.0  # the long side toward the hall's middle
		add_child(table)
		card_tables.append(table)
	trophies = TrophyRoom.new()
	trophies.cfg = cfg
	add_child(trophies)


func _model(id: String, at: Vector3) -> Node3D:
	var made := FantasyModels.scene(id)
	if made == null:
		push_warning("hub model missing: " + id)
		made = Node3D.new()
	made.position = at
	add_child(made)
	return made


func _light(at: Vector3, color: Color, energy: float, reach: float) -> void:
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = color
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	add_child(lamp)


# The high round window in the right wall: cold glass and one beam of moonlight across the hall.
func _moon() -> void:
	var hw := float(cfg["size"][0]) * 0.5
	var glass := MeshInstance3D.new()  # (polish1 item 11) a starry night outside: a picture made once, round like the window
	var pane := QuadMesh.new()
	pane.size = Vector2(3.1, 3.1)
	var night := StandardMaterial3D.new()
	night.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	night.albedo_texture = _night_sky()
	night.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	night.alpha_scissor_threshold = 0.5
	pane.material = night
	glass.mesh = pane
	glass.position = Vector3(hw - 0.08, 9.5, -8.0)
	glass.rotation.y = -PI * 0.5  # facing into the hall
	add_child(glass)
	var beam := SpotLight3D.new()
	beam.position = Vector3(hw - 0.6, 9.5, -8.0)
	beam.light_color = MOON
	beam.light_energy = 2.2
	beam.spot_range = 40.0
	beam.spot_angle = 22.0
	beam.shadow_enabled = false
	add_child(beam)
	beam.look_at(global_position + Vector3(4.0, 0.0, -3.0), Vector3.UP)


# A picture from assets/ui (imported for the 2D screen, so without mipmaps) with mipmaps made once, so thin lines on a 3D
# surface fade with distance instead of sparkling.
static func _mipmapped(path: String) -> Texture2D:
	var picture := load(path) as Texture2D
	var img := picture.get_image() if picture != null else null
	if img == null or img.is_compressed():
		return picture
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# (polish1 item 9) The pedestal's carved story: the four faces of tools/paint_frieze.py's picture laid just in front of
# the pedestal's dressed faces (behind its raised band lines), read round clockwise from the front. One draw.
func _frieze(at: Vector3) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)]
	for i in faces.size():
		var n: Vector3 = faces[i]
		var right := Vector3(n.z, 0.0, -n.x)  # the viewer's right, facing this side
		var mid := at + n * 0.713
		var v0 := float(i) / 4.0
		var v1 := float(i + 1) / 4.0
		var corners := [[mid - right * 0.65 + Vector3.UP * 1.222, Vector2(0, v0)], [mid + right * 0.65 + Vector3.UP * 1.222, Vector2(1, v0)],
			[mid + right * 0.65 + Vector3.UP * 0.41, Vector2(1, v1)], [mid - right * 0.65 + Vector3.UP * 0.41, Vector2(0, v1)]]
		for k: int in [0, 1, 2, 0, 2, 3]:
			tool.set_normal(n)
			tool.set_uv(corners[k][1])
			tool.add_vertex(corners[k][0])
	var cut := StandardMaterial3D.new()
	cut.albedo_texture = _mipmapped(FRIEZE)
	cut.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cut.roughness = 0.9
	tool.set_material(cut)
	var shown := MeshInstance3D.new()
	shown.mesh = tool.commit()
	add_child(shown)


# (polish1 item 15) Cobwebs strung across the trophy room doorway's top corners, both sides of the wall
# (tools/paint_cobweb.py).
func _cobwebs() -> void:
	var hw := float(cfg["size"][0]) * 0.5
	var door: Array = cfg["door"]
	var z0 := float(door[1]) - 1.5
	var z1 := float(door[1]) + 1.5
	var top := 4.0
	var web := StandardMaterial3D.new()
	web.albedo_texture = _mipmapped(COBWEB)
	web.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	web.cull_mode = BaseMaterial3D.CULL_DISABLED
	web.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # thin threads catch the candlelight
	web.albedo_color = Color(0.85, 0.82, 0.76, 0.9)
	for face_x: float in [-hw - 0.06, -hw - 0.94]:  # the hall side and the trophy room side of the 1 m wall
		for spot: Array in [[z0, 1.0, 1.25 if face_x > -hw - 0.5 else 0.8], [z1, -1.0, 1.0 if face_x > -hw - 0.5 else 1.35]]:  # [corner z, toward the middle, size]
			var size := float(spot[2])
			var quad := QuadMesh.new()
			quad.size = Vector2(size, size)
			quad.material = web
			var piece := MeshInstance3D.new()
			piece.mesh = quad
			piece.position = Vector3(face_x, top - size * 0.5, float(spot[0]) + float(spot[1]) * size * 0.5)
			piece.rotation.y = PI * 0.5  # facing along x; the picture's left then lies toward +z
			piece.scale.x = -float(spot[1])  # so the web's anchor sits in its own corner
			add_child(piece)


# (polish1 item 12) Two antique globes on the wooden stands of the hall model: the old map (tools/paint_globe_map.py) on
# a ball tilted like the earth's axis, turning slowly inside a brass meridian ring.
func _make_globes() -> void:
	var map := _mipmapped(GLOBE_MAP)
	var paper := StandardMaterial3D.new()
	paper.albedo_texture = map
	paper.roughness = 0.55
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.8, 0.6, 0.25)
	brass.metallic = 0.15
	brass.roughness = 0.35
	var ball := SphereMesh.new()
	ball.radius = 0.42
	ball.height = 0.84
	ball.radial_segments = 32
	ball.rings = 16
	ball.material = paper
	var ring := TorusMesh.new()
	ring.inner_radius = 0.455
	ring.outer_radius = 0.485
	ring.rings = 32
	ring.ring_segments = 6
	ring.material = brass
	for spot: Vector2 in GLOBES:
		var tilt := Node3D.new()
		tilt.position = Vector3(spot.x, 1.4, spot.y)
		tilt.rotation.z = deg_to_rad(23.4)
		add_child(tilt)
		var globe := MeshInstance3D.new()
		globe.mesh = ball
		globe.rotation.y = randf() * TAU
		tilt.add_child(globe)
		_globes.append(globe)
		var meridian := MeshInstance3D.new()
		meridian.mesh = ring
		meridian.rotation.x = PI * 0.5  # upright, round the axis
		tilt.add_child(meridian)


# (polish1 item 11) The night seen through the moon window: deep blue to black, a milky band, stars of every size (a
# few with a soft halo), a bright moon with its grey seas, a thin cloud across. Round: outside the circle is see-through.
static func _night_sky() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1916
	var c := float(n) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(float(x) - c, float(y) - c).length()
			if d > c:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var sky := Color(0.06, 0.09, 0.22).lerp(Color(0.16, 0.24, 0.46), float(y) / float(n))  # lighter toward the horizon
			var band := exp(-pow((float(x) - float(y) * 0.7 - 40.0) / 34.0, 2.0)) * 0.12  # the milky way, slanting
			sky += Color(band, band, band * 1.3)
			var cloud := maxf(0.0, sin(float(x) * 0.045 + 1.3) * 0.5 + sin(float(x) * 0.11) * 0.25) * exp(-pow((float(y) - 170.0) / 14.0, 2.0)) * 0.22
			sky = sky.lerp(Color(0.32, 0.36, 0.46), cloud)
			img.set_pixel(x, y, Color(sky, 1.0))
	for i in 420:  # stars: most faint and tiny, some bright with a halo
		var sx := rng.randi_range(4, n - 5)
		var sy := rng.randi_range(4, n - 40)
		if Vector2(float(sx) - c, float(sy) - c).length() > c - 3.0:
			continue
		var b := pow(rng.randf(), 2.0)
		var tint := Color(0.85, 0.9, 1.0).lerp(Color(1.0, 0.9, 0.75), rng.randf())
		img.set_pixel(sx, sy, img.get_pixel(sx, sy).lerp(tint, 0.35 + b * 0.65))
		if b > 0.55:
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				img.set_pixel(sx + o.x, sy + o.y, img.get_pixel(sx + o.x, sy + o.y).lerp(tint, b * 0.4))
	var moon := Vector2(170.0, 78.0)
	for y in range(30, 128):
		for x in range(122, 220):
			var md := Vector2(float(x), float(y)).distance_to(moon)
			if md < 30.0:
				var sea := sin(float(x) * 0.35) * sin(float(y) * 0.3) > 0.45 or Vector2(float(x) - 162.0, float(y) - 70.0).length() < 8.0
				img.set_pixel(x, y, Color(0.93, 0.94, 0.88) if not sea else Color(0.74, 0.76, 0.74))
			elif md < 48.0:  # its glow
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(0.6, 0.68, 0.85), (48.0 - md) / 18.0 * 0.45))
	return ImageTexture.create_from_image(img)


# One turn of the stair, many times over, up and down into the dark; the whole column turns slowly. One draw for all
# turns of each material (a MultiMesh).
func _stair() -> void:
	var turn := FantasyModels.mesh("hub_stair")
	if turn == null:
		return
	turn = FantasyModels.moving(turn)  # (polish1 item 13) the texture turns with the stair
	_spiral = Node3D.new()
	_spiral.position = STAIR_AT
	add_child(_spiral)
	var many := MultiMesh.new()
	many.transform_format = MultiMesh.TRANSFORM_3D
	many.mesh = turn
	many.instance_count = STAIR_TURNS
	for i in STAIR_TURNS:
		many.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, (float(i) - STAIR_TURNS * 0.5) * STAIR_RISE, 0.0)))
	var shown := MultiMeshInstance3D.new()
	shown.multimesh = many
	shown.custom_aabb = AABB(Vector3(-3.0, -STAIR_TURNS * STAIR_RISE * 0.5, -3.0), Vector3(6.0, STAIR_TURNS * STAIR_RISE, 6.0))
	_spiral.add_child(shown)
	var lamp := OmniLight3D.new()  # a faint glow down the shaft so the turning stair reads through the arch
	lamp.light_color = MOON
	lamp.light_energy = 0.6
	lamp.omni_range = 4.5  # stays off the hall's mesh (8 lights per object on Compatibility)
	lamp.shadow_enabled = false
	lamp.position = Vector3(0.0, 4.0, 0.0)
	_spiral.add_child(lamp)


# What stops a player: the floor, the walls (the bookcases' fronts), the arch closed (the stair is only seen), the
# stage, the pedestal, the pillars, the reading tables and globes.
func _solids() -> void:
	var hw := float(cfg["size"][0]) * 0.5
	var hd := float(cfg["size"][1]) * 0.5
	var h := float(cfg["height"])
	var shelf := 0.45
	var door: Array = cfg["door"]
	var dz0 := float(door[1]) - 1.5
	var dz1 := float(door[1]) + 1.5
	_solid(Vector3(hw * 2.0 + 2.0, 1.0, hd * 2.0 + 2.0), Vector3(0.0, -0.5, 0.0))
	_solid(Vector3(1.0, h, hd * 2.0), Vector3(hw - shelf + 0.5, h * 0.5, 0.0))
	_solid(Vector3(hw * 2.0, h, 1.0), Vector3(0.0, h * 0.5, hd - shelf + 0.5))
	_solid(Vector3(hw * 2.0, h, 1.0), Vector3(0.0, h * 0.5, -hd + shelf - 0.5))
	_solid(Vector3(1.0, h, dz0 + hd), Vector3(-hw + shelf - 0.5, h * 0.5, (dz0 - hd) * 0.5))  # left wall, both sides of the doorway
	_solid(Vector3(1.0, h, hd - dz1), Vector3(-hw + shelf - 0.5, h * 0.5, (dz1 + hd) * 0.5))
	_solid(Vector3(1.0, h - 4.0, 3.0), Vector3(-hw + shelf - 0.5, 4.0 + (h - 4.0) * 0.5, float(door[1])))
	var s: Array = cfg["stage"]
	var top := float(cfg["stage_height"])
	_solid(Vector3(float(s[2]) - float(s[0]), top, float(s[3]) - float(s[1])), Vector3((float(s[0]) + float(s[2])) * 0.5, top * 0.5, (float(s[1]) + float(s[3])) * 0.5))
	_solid(Vector3(10.0, 0.3, 0.35), Vector3(0.0, 0.15, float(s[3]) + 0.17))
	_solid(Vector3(10.0, 0.15, 0.35), Vector3(0.0, 0.075, float(s[3]) + 0.52))
	var p: Array = cfg["pedestal"]
	_solid(Vector3(1.9, BUTTON_TOP, 1.9), Vector3(float(p[0]), BUTTON_TOP * 0.5, float(p[1])))
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(1.6, 11.0, 1.6), Vector3(side * 8.9, 5.5, -11.5))
	for t: Vector2 in [Vector2(-8.0, 6.0), Vector2(8.0, 6.0), Vector2(10.0, -2.0)]:  # reading tables (tools/blender/hub_room.py)
		_solid(Vector3(3.2, 0.86, 1.2), Vector3(t.x, 0.43, t.y))
	for g: Vector2 in [Vector2(-6.0, 9.0), Vector2(14.0, -6.0)]:
		_solid(Vector3(0.8, 1.9, 0.8), Vector3(g.x, 0.95, g.y))


func _solid(size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)


# The big red button goes down with a clunk and stays down (the session plays the sound).
func press() -> void:
	_pressed = true


func is_pressed() -> bool:
	return _pressed


# The Aurelind painting on the right wall, facing into the hall (world position and turn, for Island.build_painting).
func painting_spot() -> Array:
	var at: Array = cfg["painting"]
	return [position + Vector3(float(at[0]), 0.0, float(at[1])), -PI * 0.5]


func spawn(index: int) -> Vector3:
	var list: Array = cfg["spawns"]
	var at: Array = list[index % list.size()]
	return position + Vector3(float(at[0]), 0.1, float(at[1]))


func _process(delta: float) -> void:
	if _spiral != null:
		_spiral.rotation.y = wrapf(_spiral.rotation.y + STAIR_SPIN * delta, 0.0, TAU)
	for ball: Node3D in _globes:
		ball.rotate_object_local(Vector3.UP, GLOBE_SPIN * delta)
	if _pressed and _push < 1.0 and _button != null:
		_push = minf(_push + delta * 8.0, 1.0)
		_button.position.y = BUTTON_TOP - BUTTON_DOWN * _push
