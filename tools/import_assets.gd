# Purpose: developer tool. New or changed asset files (models, textures) are only usable after the Godot editor has
# imported them, and running a scene does not do that. This starts one headless import pass of the project as its own
# process, waits for it and writes tools/import_assets.log. Run scene tools/import_assets.tscn after copying assets in.
# Dependencies: none.
extends Node


func _ready() -> void:
	var started := Time.get_ticks_msec()
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--import"]))
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started < 600000:
		await get_tree().create_timer(1.0).timeout
	var f := FileAccess.open("res://tools/import_assets.log", FileAccess.WRITE)
	f.store_string("import pid %d finished=%s after %.0f s\nIMPORT_DONE" % [pid, str(not OS.is_process_running(pid)), float(Time.get_ticks_msec() - started) / 1000.0])
	f.close()
	get_tree().quit()
