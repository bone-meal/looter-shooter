# Purpose: developer measurement: how long the engine alone takes to reach a first (empty) scene on this machine.
# Writes tools/empty_boot.log. Compare with the first LOAD TIMES line of a real start (tools/game_boot_check.tscn):
# the difference is what our own main scene and menu scripts cost. Run scene tools/empty_boot.tscn.
# Dependencies: none.
extends Node


func _ready() -> void:
	var out := FileAccess.open("res://tools/empty_boot.log", FileAccess.WRITE)
	out.store_string("empty scene ready %d ms after the program started (%s)" % [Time.get_ticks_msec(), RenderingServer.get_video_adapter_name()])
	out.close()
	get_tree().quit()
