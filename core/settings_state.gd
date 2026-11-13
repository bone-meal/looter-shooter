# Purpose: pure player settings (defaults, limits, to/from dictionary). No nodes, no rendering, no file access.
# Dependencies: none. Saved and applied by game/settings_io.gd.
extends RefCounted

const MOUSE_SENS_MIN := 0.0005
const MOUSE_SENS_MAX := 0.01
const FOV_MIN := 60.0
const FOV_MAX := 110.0
const MAX_FPS_CHOICES := [0, 30, 60, 120, 144, 240]  # 0 = unlimited
const GRAPHICS_IDS := ["potato", "low", "medium", "high", "ultimate"]  # must match data/graphics.json
const SHADER_IDS := ["off", "toon", "vivid", "cinematic", "ultimate", "realistic"]
const RENDERER_IDS := ["compatibility", "forward_plus"]  # forward_plus needs a Vulkan/D3D12 card (GTX 1080 class)

var mouse_sens := 0.0025
var fov := 75.0
var vsync := true
var fullscreen := false
var max_fps := 0
var show_debug := false
var graphics := "medium"
var shaders := "realistic"
var renderer := "compatibility"  # applied at the next start (game/renderer_switch.gd)
var picks := {}  # the player's own choices over the graphics preset: option id -> choice id (data/graphics.json "options"); missing = "preset"
var bindings := {}  # action -> up to three codes ["key:87", "mouse:4"]; missing = the default (see game/input_setup.gd)
var dev_commands := true  # chat commands such as /give (game/admin_commands.gd). Director 2026-11-10: ON IN RELEASE BUILDS TOO for now (was: debug builds only)
var volume := 1.0  # master volume 0..1
var muted_sounds: Array = []  # sound ids switched off on the Sounds page (data/sound_list.json, game/sound_board.gd)
var crosshair := {}  # the player's crosshair (Settings > Crosshair): field id -> number + "name"; {} = the first preset. Cleaned by core/crosshair_style.gd where used


func to_dict() -> Dictionary:
	return {
		"mouse_sens": mouse_sens,
		"fov": fov,
		"vsync": vsync,
		"fullscreen": fullscreen,
		"max_fps": max_fps,
		"show_debug": show_debug,
		"graphics": graphics,
		"shaders": shaders,
		"renderer": renderer,
		"picks": picks,
		"bindings": bindings,
		"dev_commands": dev_commands,
		"volume": volume,
		"muted_sounds": muted_sounds,
		"crosshair": crosshair,
	}


func from_dict(d: Dictionary) -> void:
	mouse_sens = float(d.get("mouse_sens", mouse_sens))
	fov = float(d.get("fov", fov))
	vsync = bool(d.get("vsync", vsync))
	fullscreen = bool(d.get("fullscreen", fullscreen))
	max_fps = int(d.get("max_fps", max_fps))
	show_debug = bool(d.get("show_debug", show_debug))
	graphics = String(d.get("graphics", graphics))
	shaders = String(d.get("shaders", shaders))
	renderer = String(d.get("renderer", renderer))
	dev_commands = true  # on everywhere for now (director 2026-11-10); a saved "off" from an older build is ignored
	volume = clampf(float(d.get("volume", volume)), 0.0, 1.0)
	var quiet: Variant = d.get("muted_sounds", [])
	muted_sounds = (quiet as Array).duplicate() if quiet is Array else []
	var aim: Variant = d.get("crosshair", {})
	crosshair = (aim as Dictionary).duplicate() if aim is Dictionary else {}
	var picked: Variant = d.get("picks", {})
	picks = {}
	if picked is Dictionary:
		for option in picked:
			picks[String(option)] = String(picked[option])  # an id the data no longer has falls back to "preset" where it is used
	var saved = d.get("bindings", {})
	if saved is Dictionary:
		bindings = {}
		for action in saved:
			if saved[action] is String:  # settings written before a control could take three
				bindings[String(action)] = [saved[action]]
			elif saved[action] is Array:
				var kept: Array = []
				for code: Variant in saved[action]:
					if code is String and kept.size() < 3 and not kept.has(code):
						kept.append(code)
				bindings[String(action)] = kept
	clamp_values()


func clamp_values() -> void:
	mouse_sens = clampf(mouse_sens, MOUSE_SENS_MIN, MOUSE_SENS_MAX)
	fov = clampf(fov, FOV_MIN, FOV_MAX)
	if max_fps not in MAX_FPS_CHOICES:
		max_fps = 0
	if graphics not in GRAPHICS_IDS:
		graphics = "medium"
	if shaders not in SHADER_IDS:
		shaders = "realistic"
	if renderer not in RENDERER_IDS:
		renderer = "compatibility"
