# Purpose: developer check / showcase of the 29 chase guns: each built as it drops (core/gun_gen.gd unique: its parts,
# pony skin, its gimmick model), laid side-on with its LEFT side (where the gimmicks sit) to the camera and framed
# alone in a plain studio light. Saves tools/shots/unique_<id>.jpg and tools/unique_shot.log.
# Dependencies: core/gun_db.gd, core/gun_gen.gd, game/weapon_models.gd, game/gun_parts_view.gd, game/pony_skin.gd,
# game/unique_attach.gd.
extends Node3D

const GunDb = preload("res://core/gun_db.gd")
const GunGen = preload("res://core/gun_gen.gd")
const WeaponModels = preload("res://game/weapon_models.gd")
const GunPartsView = preload("res://game/gun_parts_view.gd")
const PonySkin = preload("res://game/pony_skin.gd")
const UniqueAttach = preload("res://game/unique_attach.gd")

const GROUPS := [
	["mixtape", "fish_story", "beach_ball_bombardier", "croak", "swamp_gas", "keepers_lantern"],
	["grillmaster", "volcano_sauce", "hot_potato", "penguin_rescue", "brain_freeze", "avalanche_control"],
	["weathervane", "kite_flyer", "chip_thief", "clam_shell", "angler_light", "flush"],
	["spaghetti", "lighthouse", "carbon_copy", "time_card", "loan_shark", "wanted_poster"],
	["key_ring", "treasure_map", "golden_goose", "split_decision", "message_bottle"],
]


func _json(shot_name: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % shot_name))


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.22, 0.26)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.55, 0.6)
	env.ambient_light_energy = 0.9
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -20, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var db := GunDb.new(_json("gun_loot"), _json("gun_parts"), _json("manufacturers"), _json("weapons"), _json("skills"), _json("gun_uniques"))
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	var lines := PackedStringArray()
	for g in GROUPS.size():
		for i in (GROUPS[g] as Array).size():
			var id: String = GROUPS[g][i]
			var gun := GunGen.unique(db, id, 40)
			var model := WeaponModels.build(String(gun.get("body", "")))
			add_child(model)
			GunPartsView.apply(model, gun, db)
			var family := String(gun.get("family", ""))
			PonySkin.apply(model, String(db.tier(String(gun.get("tier", ""))).get("skin", "")) == "pony", family, db.family_def(family))
			var piece := UniqueAttach.apply(model, gun, db)
			model.rotation.y = PI / 2  # side-on, barrel to the left: its left side (the gimmicks) to the camera
			await get_tree().process_frame
			var box := AABB()
			var first := true
			for mesh in model.find_children("*", "GeometryInstance3D", true, false):
				if not (mesh as VisualInstance3D).is_visible_in_tree():
					continue
				var b := (mesh as VisualInstance3D).global_transform * (mesh as VisualInstance3D).get_aabb()
				box = b if first else box.merge(b)
				first = false
			var mid := box.get_center()
			var reach := maxf(box.size.x / 1.78, box.size.y) * 0.5 / tan(deg_to_rad(cam.fov * 0.5)) * 1.25
			cam.position = mid + Vector3(0.0, box.size.y * 0.15, reach + box.size.z * 0.5)
			cam.look_at(mid, Vector3.UP)
			for _f in 8:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_jpg("res://tools/shots/unique_%s.jpg" % id, 0.92)
			model.queue_free()
			lines.append("%s gimmick=%s body=%s" % [id, str(piece != null), String(gun.get("body", ""))])
	lines.append("UNIQUE_SHOT_DONE")
	var f := FileAccess.open("res://tools/unique_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
