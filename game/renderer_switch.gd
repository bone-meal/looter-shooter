# Purpose: the project default is the Compatibility renderer (runs on the Intel HD 620 laptop and the 2016 MacBook).
# A machine that picked Forward+ in settings is started again once, at launch, with the Forward+ renderer; if its
# graphics driver cannot do it the engine falls back to Compatibility and the game simply continues.
# The second copy is started as its own process: the engine's restart-on-exit does nothing when the game was started
# from the editor (F5), which looked like a crash. From the editor the new window is therefore not attached to the
# editor's debugger and Output panel.
# Dependencies: none. Called first thing by game/main.gd (and by render check scenes with their own scene path).
extends RefCounted

const MARK := "--renderer-relaunched"


static func is_forward() -> bool:
	return RenderingServer.get_rendering_device() != null


# wanted: "compatibility" or "forward_plus". scene: res:// path to start again in ("" = the main scene).
# Returns true when the game is quitting to start again; the caller should stop setting itself up.
static func relaunch_if_needed(wanted: String, tree: SceneTree, scene: String) -> bool:
	var want_forward := wanted == "forward_plus"
	if want_forward == is_forward() or OS.get_cmdline_user_args().has(MARK):
		return false
	var args := PackedStringArray()
	if not OS.has_feature("template"):
		args.append_array(["--path", ProjectSettings.globalize_path("res://")])  # development run: tell the engine where the project is
	if scene != "":
		args.append(scene)
	args.append_array(["--rendering-method", "forward_plus" if want_forward else "gl_compatibility"])
	if not want_forward:
		args.append_array(["--rendering-driver", "opengl3"])
	args.append_array(["--", MARK])
	if OS.create_process(OS.get_executable_path(), args) < 0:
		return false  # could not start a second copy: keep playing on the current renderer
	tree.quit()
	return true
