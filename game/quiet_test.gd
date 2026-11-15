# Purpose: a developer test copy of the game that must not disturb the director at his PC (director 2026-11-15:
# "when you do testing like that it grabs my mouse"). Started with the user argument --quiet-test (by
# tools/game_boot_check.gd and tools/net_pair_check.gd): its window never takes the focus and the mouse is never
# captured, and it stays a small window; gameplay that waits for a captured mouse (shooting, aiming) asks active() instead.
# Dependencies: none.
extends Node

const SIZE := Vector2i(640, 360)  # a small window in the corner, whatever the settings say

static var _known := false
static var _on := false


static func active() -> bool:
	if not _known:
		_on = OS.get_cmdline_user_args().has("--quiet-test")
		_known = true
	return _on


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:  # the player's settings may ask for fullscreen
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if DisplayServer.window_get_size() != SIZE:
		DisplayServer.window_set_size(SIZE)
		DisplayServer.window_set_position(Vector2i.ZERO)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.mouse_mode == Input.MOUSE_MODE_CONFINED or Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # whatever the game asked for, the mouse stays the director's
