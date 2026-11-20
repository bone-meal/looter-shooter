# Purpose: a new player's first start (no user://settings.cfg yet, polish1 item 2): a weak built-in GPU (Intel HD / UHD /
# Iris, a small Radeon, a software renderer) starts on Compatibility with the low preset; every other machine starts on
# Forward+ with the realistic lighting. Runs once: the choice is saved, the player changes it in Settings after that.
# Dependencies: game/settings_io.gd (PATH, save). Called by game/main.gd before the renderer switch; the game always
# starts first on the project's Compatibility renderer, where the adapter name is known.
extends RefCounted

const SettingsIO = preload("res://game/settings_io.gd")

const WEAK := ["intel", "llvmpipe", "softpipe", "swiftshader", "basic render", "radeon(tm) graphics", "radeon graphics", "radeon vega"]


static func is_first_run() -> bool:
	return not FileAccess.file_exists(SettingsIO.PATH)


static func weak_gpu() -> bool:
	var adapter := (RenderingServer.get_video_adapter_name() + " " + RenderingServer.get_video_adapter_vendor()).to_lower()
	for word: String in WEAK:
		if adapter.contains(word):
			return true
	return false


# Picks and saves the start settings. Returns what was picked (for the log).
static func pick(settings: RefCounted) -> String:
	if weak_gpu():
		settings.renderer = "compatibility"
		settings.graphics = "low"
	else:
		settings.renderer = "forward_plus"
	settings.shaders = "realistic"
	SettingsIO.save(settings)
	return "%s / %s on %s" % [settings.renderer, settings.graphics, RenderingServer.get_video_adapter_name()]
