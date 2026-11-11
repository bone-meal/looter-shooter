# Purpose: one-off developer tool. Gets CC0 asset packs that ship as zip files (character bodies, outfits, animation
# libraries) into res://assets/cc0/packs/<pack id>/. For each job in tools/pack_jobs.json it finds the zip link on the
# pack's web page and downloads it into assets/cc0/_zips/; zips a person dropped into that folder by hand are used as
# they are. The wanted file types of every zip are unpacked (one flat folder per zip folder, textures get import
# settings with a size limit) and listed in tools/pack_fetch.log. "bundle_path" also writes them all into one zip.
# Run on the machine with internet: scene tools/pack_fetch.tscn. Dependencies: none (HTTPRequest + ZIPReader).
extends Node

const JOBS_PATH := "res://tools/pack_jobs.json"
const ZIP_DIR := "res://assets/cc0/_zips/"
const OUT_DIR := "res://assets/cc0/packs/"
const LOG_PATH := "res://tools/pack_fetch.log"
const LAYOUT_MARK := "layout_flat.txt"

var _headers := PackedStringArray(["User-Agent: looter-shooter-dev-fetch/1.0 (Godot HTTPRequest; one-off asset download)"])
var _queue: Array = []  # download jobs still to do
var _job: Dictionary = {}
var _stage := ""  # "page" or "zip"
var _http: HTTPRequest
var _keep: Array = []  # lower-case file extensions to unpack
var _skip: Array = []  # lower-case path fragments never unpacked
var _size_limit := 2048  # longest side of an unpacked texture after import
var _bundle_path := ""  # when set, all unpacked files are also written into this one zip
var _lines := PackedStringArray()
var _failed := 0


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOBS_PATH))
	if not (parsed is Dictionary):
		_note("jobs file missing or invalid: " + JOBS_PATH)
		_finish()
		return
	var jobs: Dictionary = parsed
	_keep = jobs.get("unpack_extensions", [])
	_skip = jobs.get("skip_paths_containing", [])
	_size_limit = int(jobs.get("texture_size_limit", 2048))
	_bundle_path = String(jobs.get("bundle_path", ""))
	for entry: Variant in jobs.get("downloads", []):
		if entry is Dictionary:
			_queue.append(entry)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ZIP_DIR))
	_http = HTTPRequest.new()
	_http.timeout = 600.0
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_done)
	_next()


func _next() -> void:
	if _queue.is_empty():
		_unpack_all()
		if _bundle_path != "":
			_bundle(_bundle_path)
		_finish()
		return
	_job = _queue.pop_front()
	if FileAccess.file_exists(_zip_path()):
		_note("have " + _zip_path())
		_next.call_deferred()
		return
	_stage = "page"
	_http.download_file = ""
	_request(String(_job["page"]))


func _request(url: String) -> void:
	var err := _http.request(url, _headers)
	if err != OK:
		_note("FAILED request error %d for %s" % [err, url])
		_failed += 1
		_next.call_deferred()


func _on_done(result: int, code: int, _response_headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_note("FAILED %s %s result=%d http=%d" % [_stage, _job.get("id", ""), result, code])
		_failed += 1
		if _stage == "zip":
			DirAccess.remove_absolute(_http.download_file)
		_next()
		return
	if _stage == "page":
		var url := _zip_link(body.get_string_from_utf8(), String(_job.get("match", "")))
		if url == "":
			_note("FAILED no zip link containing '%s' on %s" % [_job.get("match", ""), _job["page"]])
			_failed += 1
			_next()
			return
		_note("link %s" % url)
		_stage = "zip"
		_http.download_file = ProjectSettings.globalize_path(_zip_path())
		_request(url)
		return
	_note("got %s bytes=%d" % [_zip_path(), _size(_zip_path())])
	_next()


# First link on the page that ends in .zip and contains the wanted text.
func _zip_link(html: String, wanted: String) -> String:
	var finder := RegEx.new()
	finder.compile("href=\"([^\"]+\\.zip)\"")
	for found: RegExMatch in finder.search_all(html):
		var url := found.get_string(1)
		if wanted == "" or url.to_lower().contains(wanted.to_lower()):
			return url
	return ""


func _zip_path() -> String:
	return "%s%s.zip" % [ZIP_DIR, _job["id"]]


func _unpack_all() -> void:
	var names := DirAccess.get_files_at(ZIP_DIR)
	for file_name: String in names:
		if file_name.get_extension().to_lower() == "zip" and not file_name.begins_with("_"):  # "_packs_bundle.zip" is this tool's own output
			_unpack(ZIP_DIR + file_name, OUT_DIR + _pack_id(file_name) + "/")


# "Universal Base Characters[Standard].zip" -> "universal_base_characters_standard"
func _pack_id(file_name: String) -> String:
	var id := ""
	for ch: String in file_name.get_basename().to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			id += ch
		elif not id.ends_with("_"):
			id += "_"
	return id.trim_suffix("_")


# "Pack[Standard]/Exports/glTF (Godot)/A.gltf" -> "exports_gltf_godot/A.gltf": the zip's top folder is dropped and the
# folders below it become one short folder, so files that sit together stay together (a .gltf finds its .bin and
# textures) and paths stay short enough for every tool.
func _flat(inner: String) -> String:
	var parts := inner.split("/", false)
	var file_name := parts[parts.size() - 1]
	if parts.size() <= 2:
		return file_name
	var folders := PackedStringArray()
	for i in range(1, parts.size() - 1):
		folders.append(_pack_id(parts[i] + ".x"))
	return "_".join(folders) + "/" + file_name


# Deletes one unpacked pack folder (only ever a folder inside OUT_DIR).
func _remove_tree(dir: String) -> void:
	if not dir.begins_with(OUT_DIR) or dir.length() <= OUT_DIR.length() or not DirAccess.dir_exists_absolute(dir):
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir + sub + "/")
	for file_name: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + file_name)
	DirAccess.remove_absolute(dir)


# One zip with every unpacked file (each texture once), so the packs can be copied to another dev machine in one go.
func _bundle(path: String) -> void:
	var packer := ZIPPacker.new()
	if packer.open(path) != OK:
		_note("FAILED cannot write " + path)
		_failed += 1
		return
	var seen := {}
	var count := _bundle_dir(packer, OUT_DIR, seen)
	packer.close()
	_note("bundle %s files=%d bytes=%d" % [path, count, _size(path)])


func _bundle_dir(packer: ZIPPacker, dir: String, seen: Dictionary) -> int:
	var count := 0
	for file_name: String in DirAccess.get_files_at(dir):
		if file_name.get_extension() == "import":
			continue
		var bytes := FileAccess.get_file_as_bytes(dir + file_name)
		var key := "%s:%d" % [file_name, bytes.size()]
		if file_name.get_extension() == "png" and seen.has(key):
			continue
		seen[key] = true
		packer.start_file((dir + file_name).trim_prefix("res://"))
		packer.write_file(bytes)
		packer.close_file()
		count += 1
	for sub: String in DirAccess.get_directories_at(dir):
		count += _bundle_dir(packer, dir + sub + "/", seen)
	return count


func _unpack(zip_path: String, out_dir: String) -> void:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		_note("FAILED cannot open " + zip_path)
		_failed += 1
		return
	var written := 0
	var kept_bytes := 0
	_note("zip %s -> %s" % [zip_path, out_dir])
	if not FileAccess.file_exists(out_dir + LAYOUT_MARK):
		_remove_tree(out_dir)  # an earlier run unpacked this pack with the zip's own deep folders
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		var mark := FileAccess.open(out_dir + LAYOUT_MARK, FileAccess.WRITE)
		mark.store_string("Unpacked by tools/pack_fetch.tscn: one flat folder per folder of the zip.\n")
		mark.close()
	for inner: String in reader.get_files():
		if inner.ends_with("/"):
			continue
		var wanted := _keep.has(inner.get_extension().to_lower())
		var lower := inner.to_lower()
		for fragment: Variant in _skip:
			if lower.contains(String(fragment)):
				wanted = false
		var target := out_dir + _flat(inner)
		if not wanted:
			continue
		if inner.get_extension().to_lower() == "png":
			_write_import(target)
		if FileAccess.file_exists(target):
			_note("  have %s" % inner)
			continue
		var bytes := reader.read_file(inner)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
		var f := FileAccess.open(target, FileAccess.WRITE)
		if f == null:
			_note("  FAILED write %s" % target)
			_failed += 1
			continue
		f.store_buffer(bytes)
		f.close()
		written += 1
		kept_bytes += bytes.size()
		_note("  file %s bytes=%d" % [_flat(inner), bytes.size()])
	reader.close()
	_note("unpacked %d files, %d bytes from %s" % [written, kept_bytes, zip_path.get_file()])


# Import settings for a pack texture: VRAM compressed, mipmaps, and shrunk to the size limit (the packs ship 4k maps,
# far too heavy for the low-end machines). Rewritten whenever the file does not carry the wanted limit yet.
func _write_import(path: String) -> void:
	var limit_line := "process/size_limit=%d" % _size_limit
	var import_path := path + ".import"
	if FileAccess.get_file_as_string(import_path).contains(limit_line):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var is_normal := path.get_file().to_lower().contains("normal")
	var text := "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\ncompress/mode=2\ncompress/normal_map=%d\nmipmaps/generate=true\n%s\n" % [1 if is_normal else 2, limit_line]
	var f := FileAccess.open(import_path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


func _note(line: String) -> void:
	print("PACK_FETCH ", line)
	_lines.append(line)


func _finish() -> void:
	_note("PACK_FETCH_DONE failed=%d" % _failed)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit()
