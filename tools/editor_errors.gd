# Purpose: developer tool. Opens the project in a second, headless Godot EDITOR (as the director's editor does when it
# starts), lets it scan and quit, and writes what it complained about to tools/editor_errors.log: every different
# ERROR / WARNING line with how often it came (numbers and uid:// ids blanked so that like lines count together), then
# the first lines in full. For "the editor shows N errors" reports. The raw output is tools/editor_errors_raw.log.
# Dependencies: none.
extends Node


func _ready() -> void:
	var raw := ProjectSettings.globalize_path("res://tools/editor_errors_raw.log")
	var started := Time.get_ticks_msec()
	var pid := OS.create_process(OS.get_executable_path(), PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--editor", "--quit", "--log-file", raw]))
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() - started < 300000:
		await get_tree().create_timer(1.0).timeout
	var counts := {}
	var first := PackedStringArray()
	var blank := RegEx.new()
	blank.compile("uid://[a-z0-9]+|[0-9]+")
	var text := FileAccess.get_file_as_string(raw)
	var lines := text.split("\n")
	for i in lines.size():
		var line := lines[i].strip_edges()
		if not (line.begins_with("ERROR") or line.begins_with("WARNING") or line.begins_with("SCRIPT ERROR")):
			continue
		var kind := blank.sub(line, "#", true).left(150)
		counts[kind] = int(counts.get(kind, 0)) + 1
		if first.size() < 60:
			first.append(line.left(260) + ("   | " + lines[i + 1].strip_edges().left(160) if i + 1 < lines.size() else ""))
	var kinds := counts.keys()
	kinds.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	var out := PackedStringArray(["editor pid %d ran %.0f s, %d lines of output, %d kinds of complaint" % [pid, float(Time.get_ticks_msec() - started) / 1000.0, lines.size(), kinds.size()]])
	for kind: String in kinds:
		out.append("%4d x %s" % [int(counts[kind]), kind])
	out.append("--- the first ones in full")
	out.append_array(first)
	out.append("EDITOR_ERRORS_DONE")
	var file := FileAccess.open("res://tools/editor_errors.log", FileAccess.WRITE)
	file.store_string("\n".join(out) + "\n")
	file.close()
	get_tree().quit()
