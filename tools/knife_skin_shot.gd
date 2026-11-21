# Purpose: developer pictures of the skinned knives (polish1 D5b): every finish of data/knife_skins.json on a knife
# (types taken in turn), side on, with its name, tier and family; or (--chase) every family's chase / gem patterns next
# to a plain one. Saves res://tools/shots/knife_skins_<page>.jpg. Run with a window (rendering needed).
# Flags after --: --chase, --type <id> (one type for all), --page n (8 a picture, larger, tilted to the light).
# Dependencies: game/knife_models.gd, game/knife_skin.gd.
extends Node3D

const KnifeModels = preload("res://game/knife_models.gd")
const KnifeSkin = preload("res://game/knife_skin.gd")

const TYPES := ["bayonet", "karambit", "bowie", "flip", "butterfly", "kukri", "falchion", "combat", "gut", "stiletto", "trench", "hunting", "push"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() and FileAccess.file_exists("res://tools/knife_shot_args.txt"):  # (run from the editor / MCP: the flags from a file)
		args = PackedStringArray(FileAccess.get_file_as_string("res://tools/knife_shot_args.txt").strip_edges().split(" ", false))
	get_window().size = Vector2i(1600, 900)
	var chase := args.has("--chase")
	var one_type := String(args[args.find("--type") + 1]) if args.has("--type") else ""
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.56, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 200, 0)
	fill.light_energy = 0.5
	add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	camera.current = true
	var rules := KnifeSkin.rules()
	var entries: Array = []  # [item, label]
	if chase:
		for fam_id: String in (rules.cfg["families"] as Dictionary):
			var fin_id := ""
			for f: Dictionary in rules.cfg["finishes"]:
				if String(f["family"]) == fam_id:
					fin_id = String(f["id"])
					break
			var seen := {}
			for pat in 1000:
				var it := {"finish": fin_id, "type": "", "pattern": pat, "wear": 0.05, "strength": 1.0, "kills": 0}
				var look := rules.pattern_look(it)
				var name_l := String(look["name"])
				if not seen.has(name_l) and (int(look["variant"]) > 0 or seen.is_empty() or int(look["phase"]) > 0):
					seen[name_l] = true
					entries.append([it, "%s  %s  #%d" % [String(rules.family(it)["name"]), name_l if name_l != "" else "(plain)", pat]])
	elif args.has("--chases"):  # every chase pattern each finish can roll, on a knife, at a pattern number that really rolls it
		var pick_types := ["bowie", "karambit", "kukri", "bayonet", "falchion", "butterfly", "flip", "gut"]
		var n_c := 0
		for f: Dictionary in rules.cfg["finishes"]:
			var firsts := {}
			var counts := {}
			for pat in 1000:
				var lk := rules.pattern_look({"finish": String(f["id"]), "pattern": pat})
				if int(lk["variant"]) > 0:
					counts[lk["name"]] = int(counts.get(lk["name"], 0)) + 1
					if not firsts.has(lk["name"]):
						firsts[lk["name"]] = pat
			for nm: String in firsts:
				entries.append([{"finish": String(f["id"]), "type": String(pick_types[n_c % pick_types.size()]), "pattern": int(firsts[nm]), "wear": 0.03, "strength": 1.0, "kills": 0},
					"%s  %s  #%d  (%d in 1000)" % [String(f["name"]), nm, int(firsts[nm]), int(counts[nm])]])
				n_c += 1
	elif args.has("--ids"):  # "--ids a,b,c": each finish on two knives, two pattern numbers
		var pick_types := ["bowie", "karambit", "kukri", "bayonet", "butterfly", "falchion"]
		var n_i := 0
		for fid: String in String(args[args.find("--ids") + 1]).split(","):
			var fd := rules.finish(fid)
			for k_i in (1 if args.has("--once") else 2):
				entries.append([{"finish": fid, "type": String(pick_types[(n_i * 2 + k_i) % pick_types.size()]), "pattern": 137 + k_i * 401, "wear": 0.06, "strength": 1.0, "kills": 0}, "%s  [%s]  #%d" % [String(fd.get("name", fid)), String(fd.get("tier", "")), 137 + k_i * 401]])
			n_i += 1
	else:
		for f: Dictionary in rules.cfg["finishes"]:
			entries.append([{"finish": String(f["id"]), "type": "", "pattern": 321, "wear": 0.08, "strength": 1.0, "kills": 0}, "%s  [%s]  %s" % [String(f["name"]), String(f["tier"]), String(rules.cfg["families"][String(f["family"])]["name"])]])
	var page := int(args[args.find("--page") + 1]) if args.has("--page") else -1  # 8 a page, larger
	if page >= 0 and not args.has("--hero"):
		entries = entries.slice(page * 8, page * 8 + 8)
	var hero := args.has("--hero")  # one big knife a row, 4 rows
	if hero:
		entries = entries.slice(maxi(page, 0) * 4, maxi(page, 0) * 4 + 4)
		page = maxi(page, 0)
	var cols := 1 if hero else (2 if page >= 0 else 4)
	var cell := Vector2(0.3, 0.105) if hero else (Vector2(0.4, 0.14) if page >= 0 else Vector2(0.34, 0.15))
	for i in entries.size():
		var item: Dictionary = entries[i][0]
		var type_id := one_type if one_type != "" else (String(item["type"]) if String(item.get("type", "")) != "" else String(TYPES[i % TYPES.size()]))
		var knife := KnifeModels.build(type_id)
		knife.rotation.y = -PI * 0.5
		knife.rotation.x = -0.35 if page >= 0 else 0.0  # (tilted toward the light: polish and reflections show)
		knife.position = Vector3(float(i % cols) * cell.x, -float(floori(float(i) / float(cols))) * cell.y, 0.0)
		add_child(knife)
		KnifeSkin.apply(knife, item)
		var label := Label3D.new()
		label.text = String(entries[i][1])
		label.pixel_size = 0.0004
		label.font_size = 32
		label.position = knife.position + (Vector3(-0.13, 0.0, 0.01) if hero else Vector3(0.02, -0.055, 0.01))
		if hero:
			label.pixel_size = 0.00012
		add_child(label)
	var rows := ceili(float(entries.size()) / float(cols))
	var middle := Vector3((cols - 1) * cell.x * 0.5 + 0.03, -(rows - 1) * cell.y * 0.5 - 0.01, 0.0)
	camera.size = maxf(rows * cell.y + 0.06, ((cols - 1) * cell.x + 0.36) * 9.0 / 16.0)
	if page >= 0:
		camera.size = maxf(rows * cell.y + 0.03, (cell.x * float(cols) + 0.02) * 9.0 / 16.0)
	if hero:
		camera.size = rows * cell.y + 0.01
		middle.x = 0.06
	camera.position = middle + Vector3(0, 0.12, 1.5)
	camera.look_at(middle)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tools/shots"))
	for _i in 5:
		await RenderingServer.frame_post_draw
	var shot_name := "knife_skins_%s%s.jpg" % ["chase" if chase else "all", "" if page < 0 else "_%d" % page]
	get_viewport().get_texture().get_image().save_jpg("res://tools/shots/" + shot_name, 0.92)
	if args.has("--next") and page >= 0 and page < 6:  # "--next": go on to the next page in the same run
		var more := FileAccess.open("res://tools/knife_shot_args.txt", FileAccess.WRITE)
		more.store_string(" ".join(args).replace("--page %d" % page, "--page %d" % (page + 1)))
		more.close()
		get_tree().reload_current_scene()
		return
	print("KNIFE_SKIN_SHOT_DONE %d" % entries.size())
	get_tree().quit()
