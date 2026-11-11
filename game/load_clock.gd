# Purpose: where start-up and loading time goes. `LoadClock.mark("what just finished")` notes the milliseconds since
# the previous mark; tools/dev_boot.gd writes the list into the boot log, so load times are measured on the real
# machines (GTX 1080, HD 620, MacBook) and not guessed.
# Dependencies: none.
extends RefCounted

static var marks := PackedStringArray()
static var _last := 0
static var on_mark: Callable  # set by game/loading_screen.gd while it is up: called at every mark (moves its bar)


static func mark(what: String) -> void:
	var now := Time.get_ticks_msec()
	marks.append("%s %d ms" % [what, now - _last])
	if on_mark.is_valid():
		on_mark.call()
		now = Time.get_ticks_msec()  # the loading picture's own frame is not charged to the next step
	_last = now
