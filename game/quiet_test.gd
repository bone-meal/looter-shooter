# Purpose: a developer test copy of the game that must not disturb the director at his PC (director 2026-11-15:
# "when you do testing like that it grabs my mouse"). Started with the user argument --quiet-test (by
# tools/game_boot_check.gd and tools/net_pair_check.gd): its window never takes the focus and the mouse is never
# captured; gameplay that waits for a captured mouse (shooting, aiming) asks active() instead.
# Dependencies: none.
extends Node

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
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.mouse_mode == Input.MOUSE_MODE_CONFINED or Input.mouse_mode == Input.MOUSE_MODE_CONFINED_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE  # whatever the game asked for, the mouse stays the director's
