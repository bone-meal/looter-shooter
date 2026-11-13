# Purpose: shows the islands' weather. It blends fog, the sky's colour and the sun from one round's weather to the
# next (core/weather_rules.gd says what a round's weather is), draws the rain as ONE MultiMesh whose drops fall and
# wrap round the camera inside the shader (no particles, nothing moved from script), and times lightning and thunder.
# It writes onto the look game/render_style.gd has set and gives the look's own values back when the weather is clear
# or the player is somewhere else; nothing is written while the weather stands still.
# Dependencies: core/weather_rules.gd, data/island_weather.json, game/render_style.gd (env, sun, has_photo_sky,
# set_sky_tint), game/fantasy_sounds.gd (set_region for the looping bed, play for thunder).
extends Node3D

const WeatherRules = preload("res://core/weather_rules.gd")

const APPLY_EVERY := 0.1  # seconds between writes of fog and sun while one weather turns into the next
const TINT_EVERY := 0.5  # the sky photo's tint re-lights the whole scene, so it moves in fewer steps
const BLENDED: Array[String] = ["weight", "density", "fog_color", "sky_tint", "sky_cover", "sun", "sun_color", "rain"]

const RAIN_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled, world_vertex_coords, depth_draw_never, shadows_disabled;
// Every instance is one drop. Its place in the box comes from the instance's own position; the shader lets it fall,
// wraps it round the camera and stretches the quad along the fall, facing the camera.
uniform vec3 box = vec3(26.0, 16.0, 26.0);
uniform vec3 fall = vec3(4.0, -24.0, 1.5);
uniform float streak = 0.8;
uniform float width = 0.014;
uniform float near_cut = 0.8;
uniform vec4 tint : source_color = vec4(0.8, 0.85, 0.9, 0.4);

void vertex() {
	vec3 seed = MODEL_MATRIX[3].xyz;
	vec3 eye = CAMERA_POSITION_WORLD;
	vec3 drop = mod(seed + fall * TIME - eye, box) - 0.5 * box + eye;
	vec3 along = normalize(fall);
	vec3 side = normalize(cross(along, drop - eye));
	float shown = step(near_cut, length((drop - eye).xz));  // none on the lens, none through a hut's roof
	VERTEX = drop + (along * (UV.y - 0.5) * streak + side * (UV.x - 0.5) * width) * shown;
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a * (1.0 - abs(UV.y - 0.5) * 2.0);
}
"""

var rules := WeatherRules.new()

var _style: Node  # game/render_style.gd
var _sounds: Node
var _env: Environment
var _sun: DirectionalLight3D
var _photo := false  # the look has the photo sky: the weather tints it; a plain look gets fog over its sky instead
# The look's own values, remembered each time the look is applied.
var _base_fog_on := false
var _base_density := 0.0
var _base_fog_color := Color.WHITE
var _base_sky_affect := 0.0
var _base_aerial := 0.0
var _base_sun := 1.0
var _base_sun_color := Color.WHITE
var _base_ambient := 1.0

var _shown: Dictionary = WeatherRules.CLEAR.duplicate()  # what is on screen now
var _from: Dictionary = WeatherRules.CLEAR.duplicate()
var _to: Dictionary = WeatherRules.CLEAR
var _blend := 1.0  # 0..1 of the way from _from to _to
var _blend_seconds := 1.0
var _on := false  # the player is on the islands
var _number := 0
var _kind := ""
var _apply_in := 0.0
var _tint_in := 0.0
var _tinted := false  # we changed the sky photo's tint
var _bed := ""
var _rain: MultiMeshInstance3D
var _rain_material := ShaderMaterial.new()
var _drops := -1
var _indoors := false
var _sun_now := 1.0  # the sun's energy under this weather, before a flash
var _flash := 1.0
var _flash_in := 5.0
var _flash_phase := 0
var _flash_clock := 0.0
var _thunder_in := -1.0


func setup(config: Dictionary, style: Node, sounds: Node) -> void:
	rules.setup(config)
	_style = style
	_sounds = sounds
	_env = style.get("env") as Environment
	_sun = style.get("sun") as DirectionalLight3D
	var rain: Dictionary = config["rain"]
	var shader := Shader.new()
	shader.code = RAIN_CODE
	_rain_material.shader = shader
	_rain_material.set_shader_parameter("box", _vec(rain["box"]))
	_rain_material.set_shader_parameter("fall", _vec(rain["fall"]))
	_rain_material.set_shader_parameter("streak", float(rain["streak"]))
	_rain_material.set_shader_parameter("width", float(rain["width"]))
	_rain_material.set_shader_parameter("near_cut", float(rain["near_cut"]))
	var color := Color.html(String(rain["color"]))
	color.a = float(rain["alpha"])
	_rain_material.set_shader_parameter("tint", color)
	_rain = MultiMeshInstance3D.new()
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.custom_aabb = AABB(Vector3(-20000.0, -2000.0, -20000.0), Vector3(40000.0, 4000.0, 40000.0))  # the drops are wherever the camera is
	_rain.visible = false
	add_child(_rain)


func _vec(list: Array) -> Vector3:
	return Vector3(float(list[0]), float(list[1]), float(list[2]))


# The look was applied (again): sky, fog and sun are the look's own. Remember them; the weather goes back over them
# at once when the player is on the islands, and is forgotten when he is not (Aurelind sets its own sky next).
func look_changed(tier: String, on_islands: bool) -> void:
	_photo = bool(_style.call("has_photo_sky"))
	_base_fog_on = _env.fog_enabled
	_base_density = _env.fog_density if _env.fog_enabled else 0.0
	_base_fog_color = _env.fog_light_color
	_base_sky_affect = _env.fog_sky_affect
	_base_aerial = _env.fog_aerial_perspective
	_base_sun = _sun.light_energy
	_base_sun_color = _sun.light_color
	_base_ambient = _env.ambient_light_energy
	_sun_now = _base_sun
	_build_rain(rules.drops_for(tier))
	if on_islands:
		_apply(true)
		return
	for key in BLENDED:
		_shown[key] = WeatherRules.CLEAR[key]
	_to = WeatherRules.CLEAR
	_blend = 1.0
	_on = false
	_show_rain()
	_set_bed("")
	if _tinted:
		_tinted = false
		_style.call("set_sky_tint", Color.WHITE)


func _build_rain(count: int) -> void:
	if count == _drops:
		return
	_drops = count
	var drops := MultiMesh.new()
	drops.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.material = _rain_material
	drops.mesh = quad
	drops.instance_count = count
	var box: Vector3 = _rain_material.get_shader_parameter("box")
	for i in count:
		drops.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(randf() * box.x, randf() * box.y, randf() * box.z)))
	drops.visible_instance_count = 0
	_rain.multimesh = drops
	_show_rain()


# Called every frame by the session: where the player is, the round and its kind while it is fought, and whether he
# stands in a hut. A new round, kind or place starts a blend toward that weather.
func update(delta: float, on_islands: bool, number: int, kind: String, indoors: bool) -> void:
	if on_islands != _on or number != _number or kind != _kind:
		var moved := on_islands != _on
		_on = on_islands
		_number = number
		_kind = kind
		for key in BLENDED:
			_from[key] = _shown[key]
		_to = rules.of_round(number, kind) if on_islands else WeatherRules.CLEAR
		_blend = 0.0
		_blend_seconds = float(rules.cfg["leave_seconds" if moved else "blend_seconds"])
		_apply_in = 0.0
		_set_bed(String(_to["bed"]))
	if _blend < 1.0:
		_blend = minf(_blend + delta / maxf(_blend_seconds, 0.01), 1.0)
		_apply_in -= delta
		if _apply_in <= 0.0 or _blend >= 1.0:
			_apply_in = APPLY_EVERY
			for key in BLENDED:
				_shown[key] = lerp(_from[key], _to[key], _blend)
			_apply(_blend >= 1.0)
	if indoors != _indoors:
		_indoors = indoors
		var rain: Dictionary = rules.cfg["rain"]
		_rain_material.set_shader_parameter("near_cut", float(rain["near_cut_indoors" if indoors else "near_cut"]))
	_lightning(delta)


# Writes what is shown onto the look's own values. With clear weather this gives exactly the look's own back.
func _apply(last_step: bool) -> void:
	var weight := float(_shown["weight"])
	var density := float(_shown["density"])
	var cover := float(_shown["sky_cover"])
	var dim := float(_shown["sun"])
	_env.fog_enabled = _base_fog_on or density > 0.0
	_env.fog_density = _base_density + density
	_env.fog_light_color = _base_fog_color.lerp(_shown["fog_color"], weight)
	_env.fog_sky_affect = lerpf(_base_sky_affect, 1.0, cover)
	_env.fog_aerial_perspective = _base_aerial * (1.0 - cover)  # under cover the fog has its own colour, not the sky's
	_sun_now = _base_sun * dim
	_sun.light_energy = _sun_now * _flash
	_sun.light_color = _base_sun_color * (_shown["sun_color"] as Color)
	if _photo:
		_tint_in -= APPLY_EVERY
		if last_step or _tint_in <= 0.0:
			_tint_in = TINT_EVERY
			_tinted = weight > 0.0
			_style.call("set_sky_tint", _shown["sky_tint"])
	else:
		_env.ambient_light_energy = _base_ambient * lerpf(1.0, dim, 0.6)  # a plain look has no sky light to dim
	_show_rain()


func _show_rain() -> void:
	var count := int(roundf(float(_drops) * float(_shown["rain"])))
	_rain.visible = count > 0
	if _rain.multimesh != null:
		_rain.multimesh.visible_instance_count = count


func _set_bed(id: String) -> void:
	if id == _bed:
		return
	_bed = id
	_sounds.call("set_region", id)


# In the rain: now and then the sun flickers bright (the flash) and the thunder follows.
func _lightning(delta: float) -> void:
	var cfg: Dictionary = rules.cfg["lightning"]
	if _thunder_in >= 0.0:
		_thunder_in -= delta
		if _thunder_in < 0.0:
			_sounds.call("play", String(cfg["sound"]))
	if _flash_phase > 0:
		_flash_clock -= delta
		if _flash_clock <= 0.0:
			_flash_phase -= 1
			_flash_clock = float(cfg["flash_seconds"])
			_flash = float(cfg["sun"]) if _flash_phase % 2 == 1 else 1.0
			_sun.light_energy = _sun_now * _flash
		return
	if not _on or float(_shown["rain"]) < 0.5:
		return
	_flash_in -= delta
	if _flash_in <= 0.0:
		_flash_in = randf_range(float(cfg["flash_every"][0]), float(cfg["flash_every"][1]))
		_flash_phase = int(cfg["flashes"]) * 2
		_flash_clock = 0.0
		_thunder_in = randf_range(float(cfg["thunder_after"][0]), float(cfg["thunder_after"][1]))


# For test scripts: what is on screen now, in one line.
func describe() -> String:
	return "stage %s blend %.2f fog %.4f cover %.2f sun %.2f rain %d of %d bed '%s' fog on %s" % [
		String(_to["stage"]), _blend, _env.fog_density, float(_shown["sky_cover"]), _sun.light_energy,
		_rain.multimesh.visible_instance_count if _rain.multimesh != null else 0, _drops, _bed, str(_env.fog_enabled)]
