# Purpose: pictures of guns wearing their camo (polish1 D5a: "inventory and trade-window icons show the camo"): renders
# a gun body with its parts and camo side-on in a small off-screen viewport, one job at a time, and keeps the picture
# (by body + parts + camo). Until a picture is ready the plain icon is drawn. Also a camo's own swatch picture (the
# camo on a rifle) for the crate's camo reel and the CAMOS tab. One instance lives in the session (`instance`).
# Also skinned knives' pictures (polish1 D5b).
# Dependencies: game/weapon_models.gd, game/gun_parts_view.gd, game/camo_skin.gd, game/knife_models.gd, game/knife_skin.gd.
extends Node

const WeaponModels = preload("res://game/weapon_models.gd")
const GunPartsView = preload("res://game/gun_parts_view.gd")
const CamoSkin = preload("res://game/camo_skin.gd")
const KnifeModels = preload("res://game/knife_models.gd")
const KnifeSkin = preload("res://game/knife_skin.gd")

const SIZE := Vector2i(320, 180)
const MOST := 160  # pictures kept

static var instance: Node = null

var gun_db: RefCounted
var _done := {}  # key -> ImageTexture
var _order: Array = []  # keys, oldest first
var _queue: Array = []  # [key, gun]
var _view: SubViewport
var _stage: Node3D
var _busy := ""
var _wait := 0
var _askers: Array = []  # weakrefs of canvases that drew a plain icon while waiting; redrawn when a picture is ready


func _ready() -> void:
	instance = self
	_view = SubViewport.new()
	_view.size = SIZE
	_view.transparent_bg = true
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 35, 0)
	light.light_energy = 1.4
	_view.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	_view.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.0
	cam.position = Vector3(0, 0, 3)
	cam.current = true
	_view.add_child(cam)
	_stage = Node3D.new()
	_view.add_child(_stage)


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func key_of(gun: Dictionary) -> String:
	if gun.get("knife") is Dictionary:  # (polish1 D5b) a skinned knife: its look (not its kills)
		var k: Dictionary = gun["knife"]
		return "knife|%s|%s|%d|%.2f" % [String(k.get("type", "")), String(k.get("finish", "")), int(k.get("pattern", 0)), float(k.get("wear", 0.0))]
	return "%s|%s|%s" % [String(gun.get("body", "")), JSON.stringify(gun.get("parts", {})), JSON.stringify(gun.get("camo", {}))]


# The picture of `gun` wearing its camo, or null while it is being made (asks for it; `asker` is redrawn when it is ready).
static func picture(gun: Dictionary, asker: CanvasItem = null) -> Texture2D:
	if instance == null or not gun.get("camo") is Dictionary:
		return null
	return instance.call("_want", gun, asker)


# (polish1 D5b) A skinned knife's picture (its type with its finish), or null while it is being made.
static func knife(item: Dictionary, asker: CanvasItem = null) -> Texture2D:
	if instance == null or item.is_empty():
		return null
	return instance.call("_want", {"knife": item}, asker)


# A camo's swatch: the camo on a rifle.
static func swatch(camo: Dictionary, asker: CanvasItem = null) -> Texture2D:
	return picture({"body": "ak47", "parts": {}, "camo": camo}, asker)


func _want(gun: Dictionary, asker: CanvasItem) -> Texture2D:
	var key := key_of(gun)
	if _done.has(key):
		return _done[key]
	if asker != null:
		_askers.append(weakref(asker))
	for job: Array in _queue:
		if String(job[0]) == key:
			return null
	if _busy != key:
		_queue.append([key, gun.duplicate(true)])
	return null


func _process(_delta: float) -> void:
	if _busy != "":
		_wait -= 1
		if _wait > 0:
			return
		var image := _view.get_texture().get_image()
		_done[_busy] = ImageTexture.create_from_image(image)
		_order.append(_busy)
		if _order.size() > MOST:
			_done.erase(_order.pop_front())
		_busy = ""
		for child in _stage.get_children():
			child.queue_free()
		_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		for ref: WeakRef in _askers:
			var c := ref.get_ref() as CanvasItem
			if c != null:
				c.queue_redraw()
		_askers.clear()
		return
	if _queue.is_empty():
		return
	var job: Array = _queue.pop_front()
	var gun: Dictionary = job[1]
	var model: Node3D
	if gun.get("knife") is Dictionary:
		model = KnifeModels.build(String((gun["knife"] as Dictionary).get("type", "combat")))
		_stage.add_child(model)
		KnifeSkin.apply(model, gun["knife"])
	else:
		model = WeaponModels.build(String(gun.get("body", "ak47")))
		_stage.add_child(model)
		if gun_db != null and not (gun.get("parts", {}) as Dictionary).is_empty():
			GunPartsView.apply(model, gun, gun_db)
		CamoSkin.dress(model, gun)
	var fx := model.get_node_or_null("CamoFx")
	if fx != null:
		fx.free()
	model.rotation_degrees = Vector3(0, 90, 0)
	model.position = Vector3.ZERO
	# fit it: centre its box and scale to the frame
	var box := AABB()
	var first := true
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var m := found as MeshInstance3D
		var b := model.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var span := maxf(box.size.z, box.size.y * 1.8)
	var s0 := model.scale.x
	var total := 1.7 / maxf(span, 0.001)  # model units -> picture units
	model.scale = Vector3.ONE * total
	model.position = -(Basis(Vector3.UP, PI * 0.5) * (box.get_center() * total))
	if s0 <= 0.0:
		model.scale = Vector3.ONE
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_busy = String(job[0])
	_wait = 3
