# Purpose: inside the home port's GALLERY (sea step 7b-4; locked: bought paintings are PORTALS to the colosseum, the
# island and Aurelind, extremely expensive; players and gear pass, ore and bars do not; director 2026-11-17: real
# interiors, and each place gets a RETURN PAINTING of the port once its painting is bought). Each level gives one more
# wall (1, 2, 3): an empty gilded frame with a brass plaque (name and price) until the painting is bought at the
# gallery's window, then the picture. Walking up to a bought painting offers the trip (game/game_session.gd
# gallery_travel). The paintings belong to the host's world (sea_town world_dict "paintings").
# Dependencies: game/painting_art.gd, data/sea/town.json "paintings", markers Paint_<slot>_<yaw> and Lamp_<n> in the
# gallery's models (tools/blender/sea_town.py).
extends Node3D

const PaintingArt = preload("res://game/painting_art.gd")

const REACH := 2.2  # m from a painting's face to step in

var town: Node3D  # game/sea_town.gd
var bought: Array = []  # painting ids (the host's world, saved)
var _model: Node3D
var _cfg: Dictionary
var _frames: Array = []  # [painting id, Node3D frame, MeshInstance3D canvas, Label3D plaque]
var _lamps: Array = []
var _textures := {}


# The painting ids in wall order (slot 0 = the back wall).
func order() -> Array:
	var list: Array = (_cfg.get("order", []) as Array) if not _cfg.is_empty() else []
	return list


func info(id: String) -> Dictionary:
	return (town.get("rules").get("cfg") as Dictionary).get("paintings", {}).get(id, {})


func texture(id: String) -> Texture2D:
	if not _textures.has(id):
		match id:
			"arena":
				_textures[id] = PaintingArt.texture()
			"island":
				_textures[id] = PaintingArt.island_texture()
			"aurelind":
				_textures[id] = PaintingArt.wheat_texture()
			_:
				_textures[id] = PaintingArt.port_texture()
	return _textures[id]


# The gallery's model was put up (a new level): hang its frames.
func fit(model: Node3D, level: int, cfg: Dictionary) -> void:
	_cfg = cfg
	_model = model
	_frames.clear()
	_lamps.clear()
	if model == null or level < 1:
		return
	var list := order()
	for found in model.find_children("Paint_*", "", true, false):
		var bits := String(found.name).split("_")
		var slot := int(bits[1])
		if slot >= list.size():
			continue
		var frame := Node3D.new()
		frame.rotation.y = deg_to_rad(float(bits[2]))
		var sizes: Array = cfg.get("size_by_level", [1.0])
		frame.scale = Vector3.ONE * float(sizes[clampi(level - 1, 0, sizes.size() - 1)])  # bigger canvases in the grander galleries
		(found as Node3D).add_child(frame)
		_frames.append(_hang(frame, String(list[slot])))
	for k in range(1, 9):
		var spot := model.find_child("Lamp_%d" % k, true, false) as Node3D
		if spot == null:
			break
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.88, 0.7)
		lamp.light_energy = float(cfg.get("lamp_energy", 1.5))
		lamp.omni_range = float(cfg.get("lamp_range", 9.0))
		lamp.shadow_enabled = false
		lamp.visible = false
		spot.add_child(lamp)
		_lamps.append(lamp)
	show_bought()


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


# A gilded frame (outer 2.9 x 2.1 m) on the wall, facing into the room (+z of `frame`), a canvas and a brass plaque.
func _hang(frame: Node3D, id: String) -> Array:
	var gold := _mat(Color(0.8, 0.62, 0.26))
	gold.metallic = 0.55
	gold.roughness = 0.3
	for bar: Array in [[Vector3(2.9, 0.16, 0.12), Vector3(0, 0.97, 0.06)], [Vector3(2.9, 0.16, 0.12), Vector3(0, -0.97, 0.06)],
			[Vector3(0.16, 2.1, 0.12), Vector3(-1.37, 0, 0.06)], [Vector3(0.16, 2.1, 0.12), Vector3(1.37, 0, 0.06)]]:
		var mesh := BoxMesh.new()
		mesh.size = bar[0]
		var piece := MeshInstance3D.new()
		piece.mesh = mesh
		piece.material_override = gold
		piece.position = bar[1]
		frame.add_child(piece)
	var canvas := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 1.8)
	canvas.mesh = quad
	canvas.position = Vector3(0, 0, 0.03)
	frame.add_child(canvas)
	var plaque_back := MeshInstance3D.new()
	var plate := BoxMesh.new()
	plate.size = Vector3(0.9, 0.22, 0.02)
	plaque_back.mesh = plate
	plaque_back.material_override = gold
	plaque_back.position = Vector3(0, -1.2, 0.02)
	frame.add_child(plaque_back)
	var plaque := Label3D.new()
	plaque.font_size = 20
	plaque.pixel_size = 0.0018
	plaque.outline_size = 0
	plaque.modulate = Color(0.18, 0.1, 0.03)
	plaque.position = Vector3(0, -1.2, 0.035)
	frame.add_child(plaque)
	return [id, frame, canvas, plaque]


# Bought paintings show their picture (unshaded, like the island's); the others an empty dark canvas and a price.
func show_bought() -> void:
	for f: Array in _frames:
		var id := String(f[0])
		var have := bought.has(id)
		var art := StandardMaterial3D.new()
		if have:
			art.albedo_texture = texture(id)
			art.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			art.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		else:
			art.albedo_color = Color(0.16, 0.13, 0.1)
		(f[2] as MeshInstance3D).material_override = art
		var p := info(id)
		(f[3] as Label3D).text = String(p.get("name", id)) + ("" if have else "\n%d doubloons" % int(p.get("doubloons", 0)))


func _process(_delta: float) -> void:
	if _model == null or not is_instance_valid(_model):
		return
	var player: Node3D = town.get("_player")
	var near := player.global_position.distance_to(_model.global_position) < float(_cfg.get("lamps_within", 8.0))
	for lamp: OmniLight3D in _lamps:
		lamp.visible = near


# The painting whose face the player stands before: [id, bought]; [] when none.
func painting_near(at: Vector3) -> Array:
	for f: Array in _frames:
		var frame: Node3D = f[1]
		var front := frame.global_position + frame.global_basis.z.normalized() * 1.0
		if Vector2(at.x - front.x, at.z - front.z).length() <= REACH and absf(at.y - frame.global_position.y) < 2.5:
			return [String(f[0]), bought.has(String(f[0]))]
	return []


# Where a player coming home through a return painting arrives: 2 m in front of that painting, facing out of it.
func arrival(id: String) -> Array:
	for f: Array in _frames:
		if String(f[0]) == id:
			var frame: Node3D = f[1]
			var out := frame.global_basis.z.normalized()
			var at := frame.global_position + out * 2.0
			at.y = frame.global_position.y - 1.5
			return [at, frame.global_position + out * 4.0]
	return []
