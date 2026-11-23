# Purpose: developer check of the gun camos (polish1 D5a): every camo of one tier of data/camos.json on rifles (AK,
# M16, sniper, pistol, shotgun in turn, each with a full set of parts), unboxed row above its CHALLENGE version, in a
# neutral light, saved to res://tools/shots/camos_<tier>.jpg (+ _2 for a second still of the moving ones). User
# arguments: --tier=green|blue|purple|gold|pony, --wear=0.1.
# Dependencies: game/camo_skin.gd, game/weapon_models.gd, game/gun_parts_view.gd, core/gun_db.gd, core/data_store.gd.
extends Node3D

const CamoSkin = preload("res://game/camo_skin.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const GunPartsView = preload("res://game/gun_parts_view.gd")
const GunDb = preload("res://core/gun_db.gd")
const DataStore = preload("res://core/data_store.gd")

const BODIES := ["ak47", "m16", "sniper_basic", "pistol_basic", "shotgun_double", "smg", "m60"]

var _tier := "green"
var _wear := 0.1
var _page := 0
var _big := false  # --big: four camos a picture, large, unboxed only (--ch: their challenge versions)
var _ch := false
var _ids: PackedStringArray = []
var _args: PackedStringArray = []
var _gap := 1.2  # --gap=<s>: seconds between the --ids stills


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() and FileAccess.file_exists("res://tools/camo_shot_args.txt"):  # (run from the editor / a tool without arguments)
		args = FileAccess.get_file_as_string("res://tools/camo_shot_args.txt").strip_edges().split(" ", false)
	_args = args
	for arg in args:
		if arg.begins_with("--tier="):
			_tier = arg.trim_prefix("--tier=")
		elif arg == "--big":
			_big = true
		elif arg == "--ch":
			_ch = true
		elif arg.begins_with("--page="):
			_page = int(arg.trim_prefix("--page="))
		elif arg.begins_with("--ids="):  # (polish1 item 145) "--ids=galaxy,living_coral,void_serpent": just those, big
			_ids = arg.trim_prefix("--ids=").split(",")
			_big = true
		elif arg.begins_with("--gap="):
			_gap = float(arg.trim_prefix("--gap="))
		elif arg.begins_with("--wear="):
			_wear = float(arg.trim_prefix("--wear="))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.21, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.light_energy = 1.6
	add_child(sun)
	var cfg: Dictionary = DataStore.load_json("res://data/camos.json")
	var db := GunDb.new(DataStore.load_json("res://data/gun_loot.json"), DataStore.load_json("res://data/gun_parts.json"), DataStore.load_json("res://data/manufacturers.json"), DataStore.load_json("res://data/weapons.json"), DataStore.load_json("res://data/skills.json"), DataStore.load_json("res://data/gun_uniques.json"))
	if "--measure" in _args:
		await _measure(cfg)
		get_tree().quit()
		return
	if not _ids.is_empty():
		await _one_by_one(cfg, db)
		get_tree().quit()
		return
	var rows: Array = []
	for look: Dictionary in cfg["camos"]:
		if (_ids.is_empty() and String(look["tier"]) == _tier) or String(look["id"]) in _ids:
			rows.append(look)
	var per := 4 if _big else 6
	rows = rows.slice(_page * per, _page * per + per)
	var cols := 2 if _big else 3
	var x0 := -float(cols - 1) * 1.3
	for i in rows.size():
		var look: Dictionary = rows[i]
		var col := i % cols
		var row := floori(float(i) / float(cols))
		for challenge in (1 if _big else 2):
			var body: String = BODIES[i % BODIES.size()]
			var model := WeaponModels.build(body)
			add_child(model)
			var gun := {"body": body, "parts": {}}
			for slot: String in db.slots:
				var kinds: Array = (db.parts[slot] as Dictionary).keys()
				if not kinds.is_empty():
					gun["parts"][slot] = {"kind": kinds[(i + slot.length()) % kinds.size()], "maker": db.makers.keys()[i % db.makers.size()]}
			GunPartsView.apply(model, gun, db)
			CamoSkin.apply(model, {"wear": _wear, "seed": 7 + i, "challenge": challenge == 1 or _ch}, look)  # (at its hold scale)
			model.rotation_degrees = Vector3(0, 90, 0)
			var s := 1.0 / maxf(model.scale.x, 0.01)
			model.scale *= s
			model.position = Vector3(x0 + col * 2.6, 2.0 - row * 1.5 - challenge * 0.62, 0) if not _big else Vector3(-1.15 + col * 2.3, 2.2 - row * 1.25, 0)
			if challenge == 0:
				var tag := Label3D.new()
				tag.text = String(look["name"])
				tag.font_size = 28
				tag.pixel_size = 0.004
				tag.position = Vector3(x0 + col * 2.6, 2.4 - row * 1.5, 0) if not _big else Vector3(-1.15 + col * 2.3, 2.75 - row * 1.25, 0)
				add_child(tag)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.45, 4.6) if not _big else Vector3(0, 1.6, 2.7)
	cam.fov = 45.0
	add_child(cam)
	cam.current = true
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("res://tools/shots/camos_%s_%s%d.jpg" % [_tier, ("bigch" if _ch else "big") if _big else "p", _page], 0.9)
	await get_tree().create_timer(1.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg("res://tools/shots/camos_%s_%s%d_b.jpg" % [_tier, ("bigch" if _ch else "big") if _big else "p", _page], 0.9)
	get_tree().quit()


# (polish1 item 145) "--ids=a,b": each camo alone on an AK filling the picture, side-on, three stills 1.2 s apart
# (moving camos), saved to tools/shots/camo_<id>_<n>.jpg; "--inspect" holds the inspect value at 1.
func _one_by_one(cfg: Dictionary, _db: RefCounted) -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.02, 1.5)
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	for look: Dictionary in cfg["camos"]:
		if not String(look["id"]) in _ids:
			continue
		var model := WeaponModels.build("ak47")
		add_child(model)
		var mat := CamoSkin.apply(model, {"wear": _wear, "seed": 7, "challenge": _ch}, look)
		model.rotation_degrees = Vector3(0, 90, 0)
		model.scale *= 1.6 / maxf(model.scale.x, 0.01)
		model.position = Vector3(0.05, -0.05, 0)
		for n in 4:
			if mat != null and "--inspect" in _args:
				CamoSkin.react(mat, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0)
			await get_tree().create_timer(_gap).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("res://tools/shots/camo_%s%s_%d.jpg" % [String(look["id"]), "_ch" if _ch else "", n], 0.9)
		model.queue_free()


# (polish1 item 145) "--measure [--ids=a,b]": GPU time of the whole picture with an AK filling it, plain and in each
# camo (average of 90 frames after a settle), into tools/shots/camo_measure.txt. GPU time only: a busy CPU does not
# change it (another program on the GPU does).
func _measure(cfg: Dictionary) -> void:
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	var cam := Camera3D.new()
	cam.position = Vector3(0.25, 0.02, 0.75)
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	var lines: PackedStringArray = []
	var ids: Array = [""]
	for look: Dictionary in cfg["camos"]:
		if _ids.is_empty() or String(look["id"]) in _ids:
			ids.append(look)
	for entry: Variant in ids:
		var model := WeaponModels.build("ak47")
		add_child(model)
		if entry is Dictionary:
			CamoSkin.apply(model, {"wear": 0.1, "seed": 7, "challenge": false}, entry)
		model.rotation_degrees = Vector3(0, 90, 0)
		model.scale *= 1.6 / maxf(model.scale.x, 0.01)
		for i in 30:
			await RenderingServer.frame_post_draw
		var total := 0.0
		for i in 90:
			await RenderingServer.frame_post_draw
			total += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		lines.append("%s %.2f ms GPU" % [String((entry as Dictionary)["id"]) if entry is Dictionary else "plain", total / 90.0])
		model.queue_free()
		await RenderingServer.frame_post_draw
	var f := FileAccess.open("res://tools/shots/camo_measure.txt", FileAccess.WRITE)
	f.store_string("renderer %s, window %s\n%s\n" % [RenderingServer.get_current_rendering_method(), str(get_viewport().get_visible_rect().size), "\n".join(lines)])
	f.close()
