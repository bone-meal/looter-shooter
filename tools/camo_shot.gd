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


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tier="):
			_tier = arg.trim_prefix("--tier=")
		elif arg == "--big":
			_big = true
		elif arg == "--ch":
			_ch = true
		elif arg.begins_with("--page="):
			_page = int(arg.trim_prefix("--page="))
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
	var rows: Array = []
	for look: Dictionary in cfg["camos"]:
		if String(look["tier"]) == _tier:
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
