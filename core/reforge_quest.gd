# Purpose: the Re-forge's quest (polish1 D4e, item 38): three maritime pieces powered in any order wake the Re-forge.
# The lighthouse needs its lens found (it lies at one of several spots, picked per run) and fitted; the foghorn is
# cranked; the tide wheel is set turning and the party kills enough enemies near it before it stops. Pure rules: the
# session asks, this answers. Online the host keeps it and sends `to_dict` to everyone.
# Dependencies: none. Config: data/reforge_quest.json.
extends RefCounted

var cfg: Dictionary
var lens_at := 0  # which of cfg.lens_spots holds the lens this run
var lens_found := false
var done := {}  # piece id -> true once powered
var turning_until := -1.0  # the tide wheel: when its turn runs out (-1 = still)
var kills := 0  # kills near the turning wheel


func _init(config: Dictionary) -> void:
	cfg = config


func reset(pick: int) -> void:
	lens_at = posmod(pick, maxi((cfg["lens_spots"] as Array).size(), 1))
	lens_found = false
	done = {}
	turning_until = -1.0
	kills = 0


func piece(id: String) -> Dictionary:
	for p: Dictionary in cfg["pieces"]:
		if String(p["id"]) == id:
			return p
	return {}


func done_count() -> int:
	return done.size()


func awake() -> bool:
	return done.size() >= (cfg["pieces"] as Array).size()


func turning(now: float) -> bool:
	return turning_until >= 0.0 and now < turning_until


# Pieces not powered yet, by name ("the Lighthouse, the Tide Wheel").
func missing_names() -> String:
	var names := PackedStringArray()
	for p: Dictionary in cfg["pieces"]:
		if not done.has(String(p["id"])):
			names.append(String(p["name"]))
	return ", ".join(names)


# Someone touched the lens: true when that is news.
func find_lens() -> bool:
	if lens_found:
		return false
	lens_found = true
	return true


# Fit the lens / finish the crank: true when the piece is now powered.
func power(id: String, power_on: bool) -> bool:
	var p := piece(id)
	if p.is_empty() or done.has(id) or not power_on:
		return false
	if String(p["kind"]) == "lens" and not lens_found:
		return false
	if String(p["kind"]) == "ritual":
		return false  # only kills finish the wheel
	done[id] = true
	return true


# Set the tide wheel turning: true when it starts.
func start_turning(now: float, power_on: bool) -> bool:
	var p := _ritual()
	if p.is_empty() or done.has(String(p["id"])) or not power_on or turning(now):
		return false
	turning_until = now + float(p["seconds"])
	kills = 0
	return true


# A kill at `spot` (metres from Island.CENTER) with the wheel at `wheel`: "" nothing, "kill" counted, "done" finished.
func killed_at(spot: Vector2, wheel: Vector2, now: float) -> String:
	var p := _ritual()
	if p.is_empty() or not turning(now) or spot.distance_to(wheel) > float(p["radius"]):
		return ""
	kills += 1
	if kills < int(p["kills"]):
		return "kill"
	done[String(p["id"])] = true
	turning_until = -1.0
	return "done"


# Every frame on the host: true once when the wheel's turn ran out unfinished.
func stopped(now: float) -> bool:
	if turning_until >= 0.0 and now >= turning_until:
		turning_until = -1.0
		kills = 0
		return true
	return false


func _ritual() -> Dictionary:
	for p: Dictionary in cfg["pieces"]:
		if String(p["kind"]) == "ritual":
			return p
	return {}


# For the wire. Times go as seconds left so the machines' clocks need not agree.
func to_dict(now: float) -> Dictionary:
	return {"lens_at": lens_at, "lens": lens_found, "done": done.keys(), "left": maxf(turning_until - now, 0.0) if turning_until >= 0.0 else -1.0, "kills": kills}


func from_dict(state: Dictionary, now: float) -> void:
	lens_at = int(state.get("lens_at", lens_at))
	lens_found = bool(state.get("lens", false))
	done = {}
	for id: Variant in state.get("done", []):
		if id is String and not piece(id).is_empty():
			done[id] = true
	var left := float(state.get("left", -1.0))
	turning_until = now + left if left > 0.0 else -1.0
	kills = int(state.get("kills", 0))
