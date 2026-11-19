# Purpose: developer tool (sea step 13g). Bakes the collision of every whole (not chunk-streamed) island model into
# shape files (in pieces of about PIECE_FACES triangles), so the game loads them on the resource loader's thread instead of building them in one frame when a
# ship comes near (game/sea_islands.gd). Writes assets/models/sea/shapes/<model>/<n>.res and an index
# assets/models/sea/shapes/<model>.json ([node path, file, mesh vertex count]); a shape whose mesh has changed since
# (another vertex count) is not used and the game builds it as before. Run tools/bake_isle_shapes.tscn after an island
# model is made or changed (after tools/import_assets.tscn); log in tools/bake_isle_shapes.log.
# Dependencies: data/sea/islands.json, assets/models/sea/<model>.glb.
extends Node

const MODELS := "res://assets/models/sea/"
const SHAPES := "res://assets/models/sea/shapes/"
const PIECE_FACES := 5000  # about this many triangles a piece (one piece is attached a frame at most a few ms)


func _ready() -> void:
	var log_lines := PackedStringArray()
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sea/islands.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHAPES))
	for island: Dictionary in cfg["islands"]:
		var model := String(island["model"])
		var path := MODELS + model + ".glb"
		if not ResourceLoader.exists(path):
			continue
		var props_path := "res://data/sea/isles/%s.json" % String(island.get("props", ""))
		if island.has("props") and FileAccess.file_exists(props_path) and FileAccess.get_file_as_string(props_path).contains("\"chunks\""):
			log_lines.append("%s: chunk-streamed, skipped" % model)
			continue
		var made: Node3D = (load(path) as PackedScene).instantiate()
		add_child(made)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHAPES + model))
		var index: Array = []
		var n := 0
		for found in made.find_children("*", "MeshInstance3D", true, false):
			var mesh := found as MeshInstance3D
			if mesh.mesh == null:
				continue
			var faces := mesh.mesh.get_faces()
			for piece: PackedVector3Array in tiles(faces, PIECE_FACES):  # small pieces: each is attached in its own step
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(piece)
				var file := "%s%s/%d.res" % [SHAPES, model, n]
				var saved := ResourceSaver.save(shape, file, ResourceSaver.FLAG_COMPRESS)
				index.append([String(made.get_path_to(mesh)), file, vertices(mesh.mesh)])
				log_lines.append("%s: %s -> %s (%d faces, save %d)" % [model, String(made.get_path_to(mesh)), file, floori(piece.size() / 3.0), saved])
				n += 1
		var out := FileAccess.open(SHAPES + model + ".json", FileAccess.WRITE)
		out.store_string(JSON.stringify(index))
		out.close()
		made.free()
	var f := FileAccess.open("res://tools/bake_isle_shapes.log", FileAccess.WRITE)
	f.store_string("\n".join(log_lines) + "\nBAKE_DONE")
	f.close()
	get_tree().quit()


# The triangles split by a square grid over x / z (by each one's middle) into pieces of about `most` each.
static func tiles(faces: PackedVector3Array, most: int) -> Array:
	var count := floori(faces.size() / 3.0)
	var side := maxi(1, ceili(sqrt(float(count) / float(most))))
	var box := AABB(faces[0], Vector3.ZERO) if count > 0 else AABB()
	for v in faces:
		box = box.expand(v)
	var cells := {}
	for i in count:
		var mid := (faces[i * 3] + faces[i * 3 + 1] + faces[i * 3 + 2]) / 3.0
		var cx := clampi(floori((mid.x - box.position.x) / maxf(box.size.x, 0.001) * side), 0, side - 1)
		var cz := clampi(floori((mid.z - box.position.z) / maxf(box.size.z, 0.001) * side), 0, side - 1)
		var key := cx * side + cz
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append_array([faces[i * 3], faces[i * 3 + 1], faces[i * 3 + 2]])
	var out: Array = []
	for key: int in cells:
		out.append(PackedVector3Array(cells[key]))
	return out


# The mesh's vertex count over all surfaces: the check that a baked shape still belongs to it.
static func vertices(mesh: Mesh) -> int:
	var count := 0
	for i in mesh.get_surface_count():
		count += (mesh as ArrayMesh).surface_get_array_len(i) if mesh is ArrayMesh else 0
	return count
