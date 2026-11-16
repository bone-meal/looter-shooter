# Purpose: the sea chart as pure rules (sea step 6; director "c" = BOTH: fog of war that clears round where you sail,
# AND a grid of squares, a square COMPLETE when every island in it is explored; found or bought charts reveal secrets).
# The sea (core/sea/sea_map.gd width x height) is cut into squares of `square` m (data/sea/chart.json) named A1..;
# fog is a bit grid of `fog_cell` m cells cleared within `reveal` m of the player; an island is EXPLORED once he has
# been within `explore_share` of its radius of its middle; a square with no island is complete once `open_sea_share`
# of its fog is cleared. Pins: up to `pins` marks he sets. Secrets: ids of charts read (their marks show).
# Saved with the character (to_dict / from_dict: the fog as base64 of its bits). Each player has his own chart.
# Dependencies: none (data/sea/chart.json, the map size and the island list passed in).
extends RefCounted

var cfg: Dictionary
var width := 18000.0
var height := 18000.0
var cols := 9  # squares across
var rows := 9
var fog_w := 180  # fog cells across
var fog_h := 180
var fog := PackedByteArray()  # one byte per 8 cells, row by row: bit set = cleared
var explored := {}  # island id -> true
var pins: Array = []  # Vector2 sea positions
var secrets := {}  # chart id -> true (read)
var islands: Array = []  # {"id", "pos": Vector2, "radius"} from data/sea/islands.json
var changed := false  # set when the fog or the explored list changed (the window redraws)


func _init(chart_cfg: Dictionary, map_width: float, map_height: float, island_list: Array) -> void:
	cfg = chart_cfg
	width = map_width
	height = map_height
	cols = maxi(1, roundi(width / float(cfg["square"])))
	rows = maxi(1, roundi(height / float(cfg["square"])))
	fog_w = maxi(1, ceili(width / float(cfg["fog_cell"])))
	fog_h = maxi(1, ceili(height / float(cfg["fog_cell"])))
	fog.resize(ceili(fog_w * fog_h / 8.0))
	fog.fill(0)
	for island: Dictionary in island_list:
		islands.append({"id": String(island["id"]), "pos": Vector2(float(island["pos"][0]), float(island["pos"][1])), "radius": float(island["radius"])})


# --- fog ---

func _cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x + width * 0.5) / float(cfg["fog_cell"])), floori((z + height * 0.5) / float(cfg["fog_cell"])))


func cleared(cx: int, cz: int) -> bool:
	if cx < 0 or cz < 0 or cx >= fog_w or cz >= fog_h:
		return false
	var i := cz * fog_w + cx
	return (fog[i >> 3] & (1 << (i & 7))) != 0


func cleared_at(x: float, z: float) -> bool:
	var c := _cell_of(x, z)
	return cleared(c.x, c.y)


# The player is at sea position (x, z): clears the fog round him, marks islands he reached. Returns true on news.
func visit(x: float, z: float) -> bool:
	var news := false
	var reach := float(cfg["reveal"])
	var step := float(cfg["fog_cell"])
	var lo := _cell_of(x - reach, z - reach)
	var hi := _cell_of(x + reach, z + reach)
	for cz in range(maxi(lo.y, 0), mini(hi.y, fog_h - 1) + 1):
		for cx in range(maxi(lo.x, 0), mini(hi.x, fog_w - 1) + 1):
			var mid := Vector2((cx + 0.5) * step - width * 0.5, (cz + 0.5) * step - height * 0.5)
			if mid.distance_to(Vector2(x, z)) <= reach and not cleared(cx, cz):
				var i := cz * fog_w + cx
				fog[i >> 3] = fog[i >> 3] | (1 << (i & 7))
				news = true
	for island: Dictionary in islands:
		if not explored.has(island["id"]) and (island["pos"] as Vector2).distance_to(Vector2(x, z)) <= float(island["radius"]) * float(cfg["explore_share"]) + float(cfg["explore_extra"]):
			explored[island["id"]] = true
			news = true
	if news:
		changed = true
	return news


# --- squares ---

func square_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(floori((x + width * 0.5) / width * cols), 0, cols - 1), clampi(floori((z + height * 0.5) / height * rows), 0, rows - 1))


func square_name(sq: Vector2i) -> String:
	return "%s%d" % [char(65 + sq.x), sq.y + 1]


func square_rect(sq: Vector2i) -> Rect2:  # in sea metres (x, z)
	var w := width / cols
	var h := height / rows
	return Rect2(Vector2(sq.x * w - width * 0.5, sq.y * h - height * 0.5), Vector2(w, h))


func islands_in(sq: Vector2i) -> Array:
	var out: Array = []
	for island: Dictionary in islands:
		var p: Vector2 = island["pos"]
		if square_of(p.x, p.y) == sq:
			out.append(island)
	return out


func cleared_share(sq: Vector2i) -> float:
	var r := square_rect(sq)
	var a := _cell_of(r.position.x, r.position.y)
	var b := _cell_of(r.end.x - 1.0, r.end.y - 1.0)
	var total := 0
	var open := 0
	for cz in range(a.y, b.y + 1):
		for cx in range(a.x, b.x + 1):
			total += 1
			if cleared(cx, cz):
				open += 1
	return float(open) / float(maxi(total, 1))


# [explored islands, islands] of a square; a square without islands counts its cleared sea instead.
func progress(sq: Vector2i) -> Vector2i:
	var list := islands_in(sq)
	var done := 0
	for island: Dictionary in list:
		if explored.has(island["id"]):
			done += 1
	return Vector2i(done, list.size())


func complete(sq: Vector2i) -> bool:
	var p := progress(sq)
	if p.y == 0:
		return cleared_share(sq) >= float(cfg["open_sea_share"])
	return p.x >= p.y


func complete_count() -> int:
	var n := 0
	for r in rows:
		for c in cols:
			if complete(Vector2i(c, r)):
				n += 1
	return n


# Squares he has been into (any fog cleared) that are not complete yet: the tracker of unfinished places.
func unfinished() -> Array:
	var out: Array = []
	for r in rows:
		for c in cols:
			var sq := Vector2i(c, r)
			if not complete(sq) and cleared_share(sq) > 0.0:
				out.append(sq)
	return out


# --- pins and secrets ---

func toggle_pin(at: Vector2) -> void:
	for i in pins.size():
		if (pins[i] as Vector2).distance_to(at) <= float(cfg["pin_reach"]):
			pins.remove_at(i)
			changed = true
			return
	if pins.size() < int(cfg["pins"]) and at.is_finite():
		pins.append(at)
		changed = true


func read_secret(chart_id: String) -> bool:
	if secrets.has(chart_id):
		return false
	secrets[chart_id] = true
	changed = true
	return true


# --- saving ---

func to_dict() -> Dictionary:
	var pin_list: Array = []
	for p: Vector2 in pins:
		pin_list.append([snappedf(p.x, 1.0), snappedf(p.y, 1.0)])
	return {"v": 1, "w": fog_w, "h": fog_h, "fog": Marshalls.raw_to_base64(fog.compress(FileAccess.COMPRESSION_DEFLATE)), "size": fog.size(), "explored": explored.keys(), "pins": pin_list, "secrets": secrets.keys()}


func from_dict(saved: Variant) -> void:
	if not saved is Dictionary:
		return
	var d: Dictionary = saved
	if int(d.get("w", 0)) == fog_w and int(d.get("h", 0)) == fog_h and d.get("fog") is String:  # a fog of another size is dropped
		var raw := Marshalls.base64_to_raw(String(d["fog"])).decompress(int(d.get("size", 0)), FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == fog.size():
			fog = raw
	explored = {}
	for id: Variant in d.get("explored", []):
		if islands.any(func(i: Dictionary) -> bool: return i["id"] == str(id)):
			explored[str(id)] = true
	pins = []
	for p: Variant in d.get("pins", []):
		if p is Array and (p as Array).size() == 2 and pins.size() < int(cfg["pins"]):
			var at := Vector2(float(p[0]), float(p[1]))
			if at.is_finite():
				pins.append(at)
	secrets = {}
	for id: Variant in d.get("secrets", []):
		secrets[str(id)] = true
	changed = true
