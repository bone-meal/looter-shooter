# Purpose: one-off tool. Downloads Omaha OpenStreetMap data (Overpass API) into data/omaha/raw/*.json.
# Run on the machine with internet: scene tools/omaha_fetch.tscn. Dependencies: none (HTTPRequest only).
# Data (c) OpenStreetMap contributors, ODbL.
extends Node

const BBOX := "41.12,-96.30,41.40,-95.85" # south,west,north,east
const SERVERS := ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter"]
const OUT_DIR := "res://data/omaha/raw/"

var _jobs := {
	"roads_major": 'way["highway"~"^(motorway|trunk|primary|secondary|tertiary|motorway_link|trunk_link|primary_link)$"]',
	"roads_minor": 'way["highway"~"^(residential|unclassified|living_street)$"]',
	"rail": 'way["railway"="rail"]',
	"water": 'way["natural"="water"];way["waterway"~"^(river|stream|canal)$"]',
	"parks": 'way["leisure"~"^(park|golf_course|pitch|stadium)$"]',
	"landmarks": 'way["building"]["name"];way["tourism"~"^(attraction|museum|zoo|aquarium)$"];way["amenity"~"^(hospital|university|townhall)$"]',
	"river_rel": 'relation["natural"="water"]',
	"towers": 'way["building"]["height"~"^([3-9][0-9]|[0-9]{3})"];way["building"]["building:levels"~"^([8-9]|[1-9][0-9])"]',
}
const ONLY: Array = ["river_rel"] # empty = all layers
var _names: Array = []
var _idx := 0
var _srv := 0
var _http: HTTPRequest


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_names = ONLY if not ONLY.is_empty() else _jobs.keys()
	_http = HTTPRequest.new()
	_http.timeout = 180.0
	add_child(_http)
	_http.request_completed.connect(_done)
	_next()


func _next() -> void:
	if _idx >= _names.size():
		print("OMAHA_FETCH_DONE")
		get_tree().quit()
		return
	var tail := "out geom(%s);" % BBOX if _names[_idx] == "river_rel" else "out tags geom;"
	var q := "[out:json][timeout:150][bbox:%s];(%s;);%s" % [BBOX, _jobs[_names[_idx]], tail]
	var body := "data=" + q.uri_encode()
	_http.download_file = ProjectSettings.globalize_path(OUT_DIR + _names[_idx] + ".json")
	var err := _http.request(SERVERS[_srv], ["Content-Type: application/x-www-form-urlencoded"], HTTPClient.METHOD_POST, body)
	print("OMAHA_FETCH start ", _names[_idx], " err=", err)


func _done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	var path := ProjectSettings.globalize_path(OUT_DIR + _names[_idx] + ".json")
	var size := FileAccess.get_file_as_bytes(path).size() if FileAccess.file_exists(path) else 0
	print("OMAHA_FETCH ", _names[_idx], " result=", result, " http=", code, " bytes=", size)
	if code == 200 and size > 100:
		_idx += 1
	else:
		_srv += 1
		if _srv >= SERVERS.size():
			_srv = 0
			_idx += 1 # give up on this layer
			print("OMAHA_FETCH gave up on layer")
	_next()
