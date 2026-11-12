# Purpose: pure rules of the shelters: where each hut stands, its door and three windows, how many boards every
# window still has, what an enemy does about a prey that is inside (walk to the nearest window, tear a board at a
# time, climb in) or outside while it is itself inside (leave by the door), and what nailing boards back pays.
# No nodes, no rendering.
# Dependencies: none. Data: data/archipelago.json (shelters, windows), handed over by core/archipelago.gd positions.
# All positions are metres (x, z) from the spawn island's middle. A hut's own frame: the door is in its +z wall.
extends RefCounted

const HALF := Vector2(3.5, 2.75)  # half the hut's outside size (x, z)
const DOOR := 1.4  # width of the doorway
const WINDOW := 1.6  # width of a window
const STAND := 1.0  # an enemy stands this far outside a window; it lands this far inside
const STEP_OUT := 1.6  # an enemy leaving by the door is set down this far outside it
const AT_SPOT := 1.4  # "at the window" / "at the door" = within this many metres of the spot

var cfg: Dictionary  # data "windows"
var huts: Array = []  # {"at": Vector2, "yaw": float}
var windows: Array = []  # {"hut": int, "mid": Vector2 (in the wall), "out": Vector2, "in": Vector2, "yaw": the way its outside faces}
var doors: Array = []  # one per hut: {"in": Vector2 (just inside the doorway), "step": Vector2 (just outside it)}
var boards := PackedInt32Array()  # per window

var _tear_at := PackedFloat32Array()  # per window: when the next board can come off
var _climb_at := PackedFloat32Array()  # per window: when the next enemy can climb through
var _leave_at := PackedFloat32Array()  # per hut: when the next enemy can step out of the door
var _nail_at := PackedFloat32Array()  # per window: when the next board can be nailed back
var _paid := 0  # boards paid for this round


# places = [{"at": Vector2 (the hut's middle), "yaw": the way its door faces (0 = +z)}]
func _init(config: Dictionary, places: Array) -> void:
	cfg = config
	for place: Dictionary in places:
		var hut := huts.size()
		var at: Vector2 = place["at"]
		var yaw := float(place["yaw"])
		huts.append({"at": at, "yaw": yaw})
		doors.append({"step": at + _turn(Vector2(0.0, HALF.y + STEP_OUT), yaw), "in": at + _turn(Vector2(0.0, HALF.y - STAND), yaw)})
		for wall: Array in [[Vector2(0.0, -HALF.y), Vector2(0.0, -1.0)], [Vector2(-HALF.x, 0.0), Vector2(-1.0, 0.0)], [Vector2(HALF.x, 0.0), Vector2(1.0, 0.0)]]:
			var mid: Vector2 = wall[0]
			var out: Vector2 = wall[1]
			var facing := _turn(out, yaw)
			windows.append({"hut": hut, "mid": at + _turn(mid, yaw), "out": at + _turn(mid + out * STAND, yaw), "in": at + _turn(mid - out * STAND, yaw), "yaw": atan2(facing.x, facing.y)})
	boards.resize(windows.size())
	boards.fill(full())
	_tear_at.resize(windows.size())
	_climb_at.resize(windows.size())
	_nail_at.resize(windows.size())
	_leave_at.resize(huts.size())


# A hut-frame offset turned the hut's way.
static func _turn(local: Vector2, yaw: float) -> Vector2:
	return Vector2(local.x * cos(yaw) + local.y * sin(yaw), -local.x * sin(yaw) + local.y * cos(yaw))


# A spot in a hut's own frame.
func to_hut(hut: int, x: float, z: float) -> Vector2:
	var off := Vector2(x, z) - (huts[hut]["at"] as Vector2)
	var yaw := float(huts[hut]["yaw"])
	return Vector2(off.x * cos(yaw) - off.y * sin(yaw), off.x * sin(yaw) + off.y * cos(yaw))


func full() -> int:
	return int(cfg["boards"])


# The hut a spot is inside of, -1 = out in the open.
func hut_of(x: float, z: float) -> int:
	for hut in huts.size():
		var local := to_hut(hut, x, z)
		if absf(local.x) < HALF.x and absf(local.y) < HALF.y:
			return hut
	return -1


# The window of `hut` nearest to a spot outside it.
func window_for(hut: int, x: float, z: float) -> int:
	var best := -1
	var best_d := INF
	for i in windows.size():
		if int(windows[i]["hut"]) == hut and Vector2(x, z).distance_to(windows[i]["out"]) < best_d:
			best_d = Vector2(x, z).distance_to(windows[i]["out"])
			best = i
	return best


# The window a player at a spot can nail boards to (inside or outside the hut), -1 = none near.
func window_near(x: float, z: float) -> int:
	for i in windows.size():
		if Vector2(x, z).distance_to(windows[i]["mid"]) <= float(cfg["reach"]):
			return i
	return -1


# What an enemy at (x, z) does about a prey at (px, pz) right now:
# {} = go straight at it; {"goal": Vector2} = walk there instead; {"hop": Vector2} = it climbs through a window or
# steps out of the door and is there now; "tore": window = it tore a board off that window this moment. `near` = how close to a spot counts as being at
# it (an enemy stops about its own reach short of where it walks to). `room` false = the hut is full: nobody climbs in.
func guide(x: float, z: float, px: float, pz: float, now: float, near: float = AT_SPOT, room: bool = true) -> Dictionary:
	var mine := hut_of(x, z)
	var theirs := hut_of(px, pz)
	if mine == theirs:
		return {}
	if mine >= 0:  # we are inside, the prey is not (or sits in another hut): to the door, and out of it one at a time
		var door: Dictionary = doors[mine]  # (set down outside like one climbing in: the big ones do not fit the doorway)
		if Vector2(x, z).distance_to(door["in"]) < near and now >= _leave_at[mine]:
			_leave_at[mine] = now + float(cfg["climb_seconds"])
			return {"hop": door["step"]}
		return {"goal": door["in"]}
	var window := window_for(theirs, x, z)
	var spot: Vector2 = windows[window]["out"]
	if Vector2(x, z).distance_to(spot) > near:
		return {"goal": spot}
	if boards[window] > 0:
		if now >= _tear_at[window]:
			if now - _tear_at[window] > float(cfg["tear_seconds"]):  # nobody was at it: the first board holds a full tear_seconds
				_tear_at[window] = now + float(cfg["tear_seconds"])
				return {"goal": spot}
			_tear_at[window] = now + float(cfg["tear_seconds"])
			boards[window] -= 1
			_climb_at[window] = now + float(cfg["climb_seconds"])  # the last board gone: a moment before the first one is through
			return {"goal": spot, "tore": window}
		return {"goal": spot}
	if room and now >= _climb_at[window]:
		_climb_at[window] = now + float(cfg["climb_seconds"])
		return {"hop": windows[window]["in"]}
	return {"goal": spot}


# A player nails a board back onto a window. Returns -1 when nothing happened (full, or too soon after the last
# one), else the points it paid (0 once this round's paid boards are used up).
func nail(window: int, now: float) -> int:
	if window < 0 or window >= boards.size() or boards[window] >= full() or now < _nail_at[window]:
		return -1
	_nail_at[window] = now + float(cfg["repair_seconds"])
	boards[window] += 1
	_tear_at[window] = maxf(_tear_at[window], now + float(cfg["tear_seconds"]))  # a fresh board holds a moment
	if _paid >= int(cfg["paid_per_round"]):
		return 0
	_paid += 1
	return int(cfg["repair_points"])


# The carpenter power-up, a new run: every window whole again.
func board_all() -> void:
	boards.fill(full())


func new_round() -> void:
	_paid = 0


# What the host says a window has (as a client).
func set_boards(window: int, count: int) -> void:
	if window >= 0 and window < boards.size():
		boards[window] = clampi(count, 0, full())
