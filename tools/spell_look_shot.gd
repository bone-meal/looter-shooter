# Purpose: developer check of how spells LOOK. Casts a list of element sequences one after another in an empty field,
# seen over the caster's shoulder, and saves one picture of each in flight into tools/shots/spell_<n>_<sequence>.png, so the shapes,
# colours and sizes of the substances can be compared side by side. Writes tools/spell_look_shot.log.
# Run scene tools/spell_look_shot.tscn.
# Dependencies: core/fantasy_data.gd, core/spell_book.gd, game/spell_effects.gd.
extends Node3D

const FantasyData = preload("res://core/fantasy_data.gd")
const SpellBook = preload("res://core/spell_book.gd")
const SpellEffects = preload("res://game/spell_effects.gd")

# first letter = the form (W jet, F bolt, E eruption, A wave), all letters together = the substance
const CASTS := ["W", "WWW", "WF", "WA", "WE", "WFA", "F", "FFF", "FA", "FE", "FW", "E", "EEE", "EW", "EF", "EFA", "A", "AAA", "AE", "AW", "AEW", "WFEA", "AWAAWAWWA", "FEFEEFFEF", "G", "GGG", "GW", "AG", "FG", "GAGAG", "GGAGGEGG"]


class Stand extends Node3D:
	func view_origin() -> Vector3:
		return global_position + Vector3(0, 1.6, 0)
	func view_forward() -> Vector3:
		return Vector3(1, -0.12, 0).normalized()
	func enemy_list() -> Array:
		return []


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.26, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	shape.shape = plane
	ground.add_child(shape)
	add_child(ground)
	var floor_mesh := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(200, 200)
	floor_mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.24, 0.14)
	floor_mesh.material_override = mat
	add_child(floor_mesh)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(-1.4, 2.0, 0.9)  # just behind the caster's shoulder, as the player sees it
	camera.look_at(Vector3(9.0, 0.5, 0.0))
	camera.current = true
	var stand := Stand.new()
	add_child(stand)
	var effects := SpellEffects.new()
	effects.source = stand
	effects.caster = stand
	add_child(effects)
	var book := SpellBook.new(FantasyData.load_all()["spells"])
	var lines := PackedStringArray()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	for i in CASTS.size():
		var spell := book.resolve(String(CASTS[i]))
		if spell.is_empty():
			lines.append("%s: no spell" % CASTS[i])
			continue
		effects.cast(spell, stand.view_origin(), stand.view_forward(), stand.view_origin() + Vector3(0.8, 0, 0), 10.0, 0.0, true)
		var wait := 0.3 if String(spell["kind"]) in ["jet", "bolt", "wave"] else 0.55
		if String(spell.get("secret", "")) != "":
			wait = 1.6
		await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://tools/shots/spell_%02d_%s.png" % [i, CASTS[i]])
		lines.append("%s -> %s (%s, look %s) draws=%d" % [CASTS[i], spell["name"], spell["kind"], str(spell.get("look", {}).get("shape", "?")), int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
		await get_tree().create_timer(1.6 if wait < 1.0 else 6.0).timeout  # let it fade before the next
		effects.clear()
	lines.append("DONE")
	var f := FileAccess.open("res://tools/spell_look_shot.log", FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	get_tree().quit()
