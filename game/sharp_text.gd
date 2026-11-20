# Purpose: sharp text in screens laid out small and scaled up with Control.scale (the card game's table, pack opening
# and card machine, polish1 items 84 / 88): fonts are drawn at the viewport's oversampling, which knows the window's
# size but not a Control's own scale, so the words were stretched and blurry. While such a screen is shown the
# viewport draws fonts that much finer (Viewport.oversampling_override); when the last one hides it goes back to auto.
# Dependencies: none. A screen calls `hold(self, k)` when shown or resized and `release(self)` when hidden.
extends RefCounted

static var _held := {}  # screen instance id -> its scale k
static var _base := 0.0  # the viewport's own oversampling before the first hold


static func hold(screen: Control, k: float) -> void:
	var view := screen.get_viewport()
	if view == null:
		return
	if _held.is_empty():
		view.oversampling_override = 0.0
		_base = maxf(view.get_oversampling(), 1.0)
	_held[screen.get_instance_id()] = k
	view.oversampling_override = _base * float(_held.values().max())


static func release(screen: Control) -> void:
	if not _held.erase(screen.get_instance_id()):
		return
	var view := screen.get_viewport()
	if view == null:
		return
	view.oversampling_override = 0.0 if _held.is_empty() else _base * float(_held.values().max())
