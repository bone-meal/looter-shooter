# Purpose: developer check used to match the realistic look between the two renderers. Builds the island and colosseum,
# then tries a grid of lighting numbers (Compatibility: fog density; Forward+: exposure, sky energy, saturation) and writes
# the average colour of sky, ground and far wall for each into tools/look_probe_<renderer>.log, so the Forward+ numbers
# closest to the Compatibility picture can be picked. Runs on Compatibility first, then starts itself again on Forward+.
# Run scene tools/look_probe.tscn. Dependencies: game/render_style.gd, game/island.gd, game/colosseum.gd, game/renderer_switch.gd.
extends Node3D

const RenderStyle = preload("res://game/render_style.gd")
const Island = preload("res://game/island.gd")
const Colosseum = preload("res://game/colosseum.gd")
const RendererSwitch = preload("res://game/renderer_switch.gd")

const SCENE := "res://tools/look_probe.tscn"
const C := Vector3(500, 0, 0)  # island centre
const VIEWS := [
	["island_spawn", C + Vector3(0, 1.7, 4), C + Vector3(0, 2.2, -8)],
	["arena_wide", Vector3(-30, 1.7, -4), Vector3(10, 4, 2)],
]
# Screen areas averaged for the log: [name, x0, y0, x1, y1] as fractions of the picture.
const AREAS := [["sky", 0.02, 0.02, 0.12, 0.09], ["ground", 0.3, 0.86, 0.6, 0.98], ["far", 0.45, 0.52, 0.55, 0.56]]
# Forward+ trials (sky deepen 1, a light volumetric haze): exposure x sky energy x saturation.
const EXPOSURE := [1.4, 1.6, 1.8, 2.0]
const SKY_ENERGY := [1.5, 1.2, 1.0]
const SATURATION := [1.0, 1.12]
const HAZE := 0.001
# Compatibility: the distance fog density whose picture is the target.
const FOG := [0.0018]

var _lines := PackedStringArray()


func _ready() -> void:
	var forward := RendererSwitch.is_forward()
	var renderer := "fwd" if forward else "compat"
	var env := Environment.new()
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var style := RenderStyle.new()
	style.env = env
	style.sun = sun
	add_child(style)
	Colosseum.build(self)
	Island.build(self)
	var cam := Camera3D.new()
	cam.fov = 75.0
	add_child(cam)
	cam.current = true
	_lines.append("renderer=%s adapter=%s" % [renderer, RenderingServer.get_video_adapter_name()])
	style.apply("high", "realistic")
	if forward:
		var sky_material := env.sky.sky_material as ShaderMaterial
		sky_material.set_shader_parameter("deepen", 1.0)
		env.volumetric_fog_density = HAZE
		for exposure: float in EXPOSURE:
			for sky_energy: float in SKY_ENERGY:
				for saturation: float in SATURATION:
					sky_material.set_shader_parameter("energy", sky_energy)
					env.tonemap_exposure = exposure
					env.adjustment_saturation = saturation
					await _measure(cam, "e=%.2f k=%.1f s=%.2f" % [exposure, sky_energy, saturation])
	else:
		for fog: float in FOG:
			env.fog_density = fog
			await _measure(cam, "fog=%.4f" % fog)
	_lines.append("LOOK_PROBE_DONE")
	var f := FileAccess.open("res://tools/look_probe_%s.log" % renderer, FileAccess.WRITE)
	f.store_string("\n".join(_lines))
	f.close()
	if not forward and RendererSwitch.relaunch_if_needed("forward_plus", get_tree(), SCENE):
		return
	get_tree().quit()


func _measure(cam: Camera3D, label: String) -> void:
	for view: Array in VIEWS:
		cam.position = view[1]
		cam.look_at(view[2], Vector3.UP)
		await _frames(45)
		var image := get_viewport().get_texture().get_image()
		var line := "%s %s" % [label, view[0]]
		for area: Array in AREAS:
			line += "  %s=%s" % [area[0], _average(image, area)]
		_lines.append(line)


# Average colour of one screen area, as "r,g,b" in 0..1.
func _average(image: Image, area: Array) -> String:
	var w := image.get_width()
	var h := image.get_height()
	var sum := Vector3.ZERO
	var count := 0
	for y in range(int(float(area[2]) * h), int(float(area[4]) * h), 3):
		for x in range(int(float(area[1]) * w), int(float(area[3]) * w), 3):
			var c := image.get_pixel(x, y)
			sum += Vector3(c.r, c.g, c.b)
			count += 1
	var mean := sum / float(maxi(count, 1))
	return "%.3f,%.3f,%.3f" % [mean.x, mean.y, mean.z]


func _frames(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw
