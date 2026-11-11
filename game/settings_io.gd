# Purpose: saves/loads settings to user://settings.cfg and applies the display ones (vsync, fullscreen, fps cap) and the sound ones (master volume, muted sounds).
# Dependencies: core/settings_state.gd.
extends RefCounted

const SoundBoard = preload("res://game/sound_board.gd")

const PATH := "user://settings.cfg"
const SECTION := "settings"


static func load_into(settings: RefCounted) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var d := {}
	for key in cfg.get_section_keys(SECTION):
		d[key] = cfg.get_value(SECTION, key)
	settings.from_dict(d)


static func save(settings: RefCounted) -> void:
	var cfg := ConfigFile.new()
	var d: Dictionary = settings.to_dict()
	for key in d:
		cfg.set_value(SECTION, key, d[key])
	cfg.save(PATH)


static func apply_display(settings: RefCounted) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	Engine.max_fps = settings.max_fps
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.volume), 0.0001)))  # master volume
	AudioServer.set_bus_mute(0, float(settings.volume) <= 0.0)
	SoundBoard.set_muted(settings.muted_sounds)
