# Purpose: gun drops lying in the world: each is a floating gun model with a tier-coloured light beam, a name tag and a chime. Capped, despawns over time, animates the rainbow/pony colours.
# Dependencies: game/weapon_models.gd, game/tier_style.gd, game/tier_sound.gd, core/gun_db.gd, core/gun_stats.gd. Config: data/drops.json (cap, despawn times, pickup range).
extends Node3D

const WeaponModels = preload("res://game/weapon_models.gd")
const GunPartsView = preload("res://game/gun_parts_view.gd")
const TierStyle = preload("res://game/tier_style.gd")
const TierSound = preload("res://game/tier_sound.gd")
const SoundBoard = preload("res://game/sound_board.gd")
const GunStats = preload("res://core/gun_stats.gd")
const PonySkin = preload("res://game/pony_skin.gd")

var gun_db: RefCounted
var cfg: Dictionary

var _drops: Array[Dictionary] = []  # {"node", "gun", "beam_mat", "label", "age", "ttl", "animated", "tier"}


func setup(db: RefCounted, drops_cfg: Dictionary) -> void:
	gun_db = db
	cfg = drops_cfg


func count() -> int:
	return _drops.size()


# Drops `gun` at `pos` (world position on the floor). The oldest drop goes when the cap is reached.
# shared = the host's number of a gun a PLAYER dropped online (game/net_drops.gd; 0 = this machine's own drop):
# such a drop stays until the host says it is gone (`remove_shared`), whatever its age or `clear`.
func spawn(gun: Dictionary, pos: Vector3, shared: int = 0) -> void:
	while _drops.size() >= int(cfg["max_world_drops"]):
		_remove(0)
	var tier_id := String(gun["tier"])
	var ti: int = gun_db.tier_index(tier_id)
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1, 1, 1, 0.4)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.07 + 0.015 * float(ti)
	beam_mesh.bottom_radius = beam_mesh.top_radius
	beam_mesh.height = 10.0 + float(ti)
	beam_mesh.radial_segments = 8
	beam_mesh.rings = 1
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.material_override = mat
	beam.position.y = beam_mesh.height * 0.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(beam)
	var model := WeaponModels.build(String(gun["body"]))
	GunPartsView.apply(model, gun, gun_db)
	model.position = Vector3.ZERO
	model.scale = Vector3.ONE * 2.6
	model.rotation_degrees.y = 90.0
	if String(gun_db.tier(tier_id).get("skin", "")) == "pony":
		PonySkin.apply(model, true)
	var holder := Node3D.new()
	holder.position.y = 0.9
	holder.add_child(model)
	node.add_child(holder)
	var label := Label3D.new()
	label.text = GunStats.display_name(gun_db, gun)
	var fancy := TierStyle.tag_font(gun_db, String(gun["tier"]))
	if fancy != null:  # a pony drop: its whole name tag in the pony face
		label.font = fancy
	label.font_size = 40
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.position.y = 2.0
	label.visibility_range_end = 30.0
	node.add_child(label)
	var player := AudioStreamPlayer3D.new()
	player.stream = TierSound.chime(ti)
	player.unit_size = 10.0 + float(ti) * 3.0
	player.volume_db = -6.0 + float(ti)
	node.add_child(player)
	if SoundBoard.allow("chime_" + tier_id):  # the Sounds page of the settings can mute each tier's chime
		player.play()
		SoundBoard.heard("chime_" + tier_id)
	var ttl := float(cfg["despawn_seconds_gold_up"]) if ti >= gun_db.tier_index("gold") else float(cfg["despawn_seconds"])
	_drops.append({"node": node, "gun": gun, "beam_mat": mat, "label": label, "holder": holder, "age": 0.0, "ttl": INF if shared != 0 else ttl, "animated": TierStyle.animated(gun_db, tier_id), "tier": tier_id, "shared": shared})
	_tint(_drops[_drops.size() - 1], 0.0)


# Drops an item (a piece of armour) at `pos`: a small box turning under a beam of its colour, with its name.
# Its entry has "item" = the id (and an empty "gun"); the session picks it up by that.
func spawn_item(id: String, title: String, color: Color, pos: Vector3, amount := 1) -> void:
	while _drops.size() >= int(cfg["max_world_drops"]):
		_remove(0)
	var node := Node3D.new()
	node.position = pos
	add_child(node)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.4)
	var beam_mesh := CylinderMesh.new()
	beam_mesh.top_radius = 0.1
	beam_mesh.bottom_radius = 0.1
	beam_mesh.height = 12.0
	beam_mesh.radial_segments = 8
	beam_mesh.rings = 1
	var beam := MeshInstance3D.new()
	beam.mesh = beam_mesh
	beam.material_override = mat
	beam.position.y = 6.0
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(beam)
	var solid := StandardMaterial3D.new()
	solid.albedo_color = color
	var box := BoxMesh.new()
	box.size = Vector3(0.42, 0.42, 0.42)
	var piece := MeshInstance3D.new()
	piece.mesh = box
	piece.material_override = solid
	var holder := Node3D.new()
	holder.position.y = 0.9
	holder.add_child(piece)
	node.add_child(holder)
	var label := Label3D.new()
	label.text = title if amount <= 1 else "%s x%d" % [title, amount]
	label.modulate = color
	label.font_size = 40
	label.pixel_size = 0.0045
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.outline_size = 10
	label.position.y = 2.0
	label.visibility_range_end = 30.0
	node.add_child(label)
	_drops.append({"node": node, "gun": {}, "item": id, "count": amount, "beam_mat": mat, "label": label, "holder": holder, "age": 0.0, "ttl": float(cfg["despawn_seconds_gold_up"]), "animated": false, "tier": "", "shared": 0})


# The closest drop within pickup range of `pos`, or {} (the dictionary is the live entry: pass it to take()).
func nearest(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := float(cfg["pickup_range"])
	for d in _drops:
		var dist: float = (d["node"] as Node3D).global_position.distance_to(pos)
		if dist <= best_d:
			best_d = dist
			best = d
	return best


# Removes the drop and returns its gun.
func take(drop: Dictionary) -> Dictionary:
	var gun: Dictionary = drop["gun"]
	_remove(_drops.find(drop))
	return gun


func has_shared(shared: int) -> bool:
	for d in _drops:
		if int(d["shared"]) == shared:
			return true
	return false


func remove_shared(shared: int) -> void:
	for i in _drops.size():
		if int(_drops[i]["shared"]) == shared:
			_remove(i)
			return


# This machine's own drops go; guns other players can still pick up stay.
func clear() -> void:
	for i in range(_drops.size() - 1, -1, -1):
		if int(_drops[i]["shared"]) == 0:
			_remove(i)


func _remove(i: int) -> void:
	if i < 0 or i >= _drops.size():
		return
	(_drops[i]["node"] as Node3D).queue_free()
	_drops.remove_at(i)


func _tint(d: Dictionary, t: float) -> void:
	var c := TierStyle.color(gun_db, String(d["tier"]), t)
	(d["beam_mat"] as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 0.4)
	(d["label"] as Label3D).modulate = c


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var i := _drops.size() - 1
	while i >= 0:
		var d := _drops[i]
		d["age"] = float(d["age"]) + delta
		if float(d["age"]) > float(d["ttl"]):
			_remove(i)
		else:
			var holder: Node3D = d["holder"]
			holder.rotation.y += delta * 1.5
			holder.position.y = 0.9 + sin(t * 2.0 + float(i)) * 0.08
			if bool(d["animated"]):
				_tint(d, t)
		i -= 1
