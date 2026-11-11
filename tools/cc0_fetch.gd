# Purpose: one-off developer tool. Downloads CC0 assets from Poly Haven (PBR textures, HDRI skies, glTF models) listed in
# tools/cc0_jobs.json into res://assets/cc0/, writes texture .import files (VRAM compressed, mipmaps, normal-map flag) and
# tools/cc0_fetch.log. The job "index" dumps the catalogue into tools/cc0_index/ so assets can be chosen.
# Run on the machine with internet: scene tools/cc0_fetch.tscn. Dependencies: none (HTTPRequest only).
# Every Poly Haven asset is CC0; name and authors are kept per asset in asset_info.json and listed in assets/cc0/CREDITS.md.
extends Node

const API := "https://api.polyhaven.com"
const JOBS_PATH := "res://tools/cc0_jobs.json"
const OUT_DIR := "res://assets/cc0/"
const INDEX_DIR := "res://tools/cc0_index/"
const LOG_PATH := "res://tools/cc0_fetch.log"
const MAP_NAMES := {"Diffuse": "diff", "nor_gl": "nor", "arm": "arm", "Displacement": "disp", "Rough": "rough", "AO": "ao"}

var _headers := PackedStringArray(["User-Agent: looter-shooter-dev-fetch/1.0 (Godot HTTPRequest; one-off asset download)"])
var _queue: Array = []  # steps: {kind: index|info|files|get, ...}
var _step: Dictionary = {}
var _http: HTTPRequest
var _lines := PackedStringArray()
var _failed := 0


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOBS_PATH))
	if not (parsed is Dictionary):
		_note("jobs file missing or invalid: " + JOBS_PATH)
		_finish()
		return
	var jobs: Dictionary = parsed
	for t: Variant in jobs.get("index", []):
		_queue.append({"kind": "index", "type": String(t)})
	for kind: String in ["textures", "hdris", "models"]:
		for entry: Variant in jobs.get(kind, []):
			if entry is Dictionary:
				_queue.append({"kind": "info", "type": kind, "job": entry})
				_queue.append({"kind": "files", "type": kind, "job": entry})
	_http = HTTPRequest.new()
	_http.timeout = 300.0
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_done)
	_next()


func _next() -> void:
	if _queue.is_empty():
		_finish()
		return
	_step = _queue.pop_front()
	var url := ""
	_http.download_file = ""
	match String(_step["kind"]):
		"index":
			url = "%s/assets?t=%s" % [API, _step["type"]]
		"info":
			url = "%s/info/%s" % [API, _job_id()]
		"files":
			url = "%s/files/%s" % [API, _job_id()]
		"get":
			var path := String(_step["path"])
			if _step.has("map") or path.get_extension() == "hdr":
				_write_import(path, String(_step.get("map", "")) == "nor_gl")
			if _size(path) > 0:
				_note("have " + path)
				_next.call_deferred()
				return
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
			_http.download_file = ProjectSettings.globalize_path(path)
			url = String(_step["url"])
	var err := _http.request(url, _headers)
	if err != OK:
		_note("request error %d for %s" % [err, url])
		_failed += 1
		_next.call_deferred()


func _on_done(result: int, code: int, _response_headers: PackedStringArray, body: PackedByteArray) -> void:
	var kind := String(_step["kind"])
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_note("FAILED %s result=%d http=%d %s" % [kind, result, code, str(_step.get("url", _step.get("job", "")))])
		_failed += 1
		if kind == "get":
			DirAccess.remove_absolute(_http.download_file)
		_next()
		return
	match kind:
		"index":
			_save(INDEX_DIR + String(_step["type"]) + ".json", body)
			_note("index %s bytes=%d" % [_step["type"], body.size()])
		"info":
			_save(_asset_dir() + "asset_info.json", body)
		"files":
			_plan_downloads(body)
		"get":
			var path := String(_step["path"])
			_note("got %s bytes=%d" % [path, _size(path)])
	_next()


# Turns the file list of one asset into download steps (put at the front of the queue).
func _plan_downloads(body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		_note("FAILED files list not JSON for " + _job_id())
		_failed += 1
		return
	var files: Dictionary = parsed
	var job: Dictionary = _step["job"]
	var id := _job_id()
	var dir := _asset_dir()
	match String(_step["type"]):
		"textures":
			for res: Variant in job.get("res", ["1k"]):
				for map_key: Variant in job.get("maps", ["Diffuse", "nor_gl", "arm"]):
					var entry := _dig(files, [map_key, res, "jpg"])
					if entry.is_empty():
						entry = _dig(files, [map_key, res, "png"])
					if entry.is_empty():
						_note("FAILED no %s %s for %s" % [map_key, res, id])
						_failed += 1
						continue
					var url := String(entry["url"])
					var short := String(MAP_NAMES.get(map_key, map_key))
					var path := "%s%s_%s_%s.%s" % [dir, id, short, res, url.get_extension()]
					_queue.push_front({"kind": "get", "url": url, "path": path, "map": String(map_key)})
		"hdris":
			var res := String(job.get("res", "2k"))
			var entry := _dig(files, ["hdri", res, "hdr"])
			if entry.is_empty():
				_note("FAILED no hdr %s for %s" % [res, id])
				_failed += 1
				return
			_queue.push_front({"kind": "get", "url": String(entry["url"]), "path": "%s%s_%s.hdr" % [dir, id, res]})
		"models":
			var res := String(job.get("res", "1k"))
			var entry := _dig(files, ["gltf", res, "gltf"])
			if entry.is_empty():
				_note("FAILED no gltf %s for %s" % [res, id])
				_failed += 1
				return
			var url := String(entry["url"])
			_queue.push_front({"kind": "get", "url": url, "path": dir + url.get_file()})
			var include: Dictionary = entry.get("include", {})
			for rel: Variant in include:
				var inc: Dictionary = include[rel]
				_queue.push_front({"kind": "get", "url": String(inc["url"]), "path": dir + String(rel)})


func _dig(d: Dictionary, keys: Array) -> Dictionary:
	var cur: Variant = d
	for k: Variant in keys:
		if not (cur is Dictionary) or not (cur as Dictionary).has(k):
			return {}
		cur = (cur as Dictionary)[k]
	if cur is Dictionary:
		return cur
	return {}


# Written before the image arrives so the editor imports it with these settings the first time it sees it.
func _write_import(path: String, is_normal: bool) -> void:
	var import_path := path + ".import"
	if FileAccess.file_exists(import_path):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var text := "[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\n\n[params]\n\ncompress/mode=2\ncompress/normal_map=%d\nmipmaps/generate=true\n" % (1 if is_normal else 2)
	var f := FileAccess.open(import_path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _job_id() -> String:
	var job: Dictionary = _step["job"]
	return String(job["id"])


func _asset_dir() -> String:
	return "%s%s/%s/" % [OUT_DIR, _step["type"], _job_id()]


func _save(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()


func _size(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


func _note(line: String) -> void:
	print("CC0_FETCH ", line)
	_lines.append(line)


func _finish() -> void:
	_note("CC0_FETCH_DONE failed=%d" % _failed)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines))
		f.close()
	get_tree().quit()
