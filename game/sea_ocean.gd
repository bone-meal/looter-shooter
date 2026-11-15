# Purpose: the sea world's ocean (sea step 4): a square wave mesh that follows the camera (snapped to its own grid so
# the water does not swim) inside a flat ring that runs to the horizon. On Medium and up the mesh rolls with the
# waves of core/sea/sea_waves.gd (the same sum, so ships ride what is drawn) at the weather's swell, fading flat
# towards its edge; Potato and Low keep a flat sea with moving normals. Depth foam where the water meets land and
# white crests on high swells. Colours come from the region. Positions in the shader are sea coordinates (the
# floating origin is undone through sea_offset), so the waves never jump when the world shifts.
# Dependencies: core/sea/sea_waves.gd, data/sea/world.json waves.
extends Node3D

const SeaWaves = preload("res://core/sea/sea_waves.gd")

const CODE := """
shader_type spatial;
render_mode cull_back;

uniform vec3 shallow_color : source_color = vec3(0.3, 0.8, 0.75);
uniform vec3 deep_color : source_color = vec3(0.04, 0.3, 0.45);
uniform vec3 foam_color : source_color = vec3(0.95, 0.97, 1.0);
uniform sampler2D wave_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform float sea_time = 0.0;
uniform vec2 sea_offset = vec2(0.0);  // scene x,z -> sea x,z
uniform vec2 centre = vec2(0.0);  // the camera (scene x,z): waves fade flat towards the mesh's edge
uniform float fade_from = 120.0;
uniform float fade_to = 160.0;
uniform float swell = 0.5;
uniform float gloom = 0.0;  // 0 clear .. 1 darkest storm: greys and darkens the water with the sky
uniform vec4 w0;
uniform vec4 w1;
uniform vec4 w2;
uniform vec4 shares;
uniform float clarity = 6.0;
uniform float foam_width = 0.45;

varying vec2 sea_xz;
varying float lift;

float wave_sum(vec2 p, out vec2 slope) {
	float h = 0.0;
	slope = vec2(0.0);
	vec4 ws[3] = vec4[](w0, w1, w2);
	for (int i = 0; i < 3; i++) {
		float phase = dot(p, ws[i].xy) * ws[i].z - ws[i].w * sea_time;
		h += sin(phase) * shares[i];
		slope += cos(phase) * shares[i] * ws[i].z * ws[i].xy;
	}
	return h;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	sea_xz = world.xz + sea_offset;
	lift = 0.0;
#ifdef SWELL
	float fade = 1.0 - smoothstep(fade_from, fade_to, distance(world.xz, centre));
	vec2 slope;
	float h = wave_sum(sea_xz, slope) * swell * fade;
	VERTEX.y += h;
	lift = h / max(swell, 0.01);
	NORMAL = normalize(vec3(-slope.x * swell * fade, 1.0, -slope.y * swell * fade));
#endif
}

void fragment() {
	vec2 uv = sea_xz / 11.0;
	vec2 drift = vec2(sea_time * 0.035);
	vec3 n1 = texture(wave_normal, uv + drift * vec2(1.0, 0.35)).rgb;
	vec3 n2 = texture(wave_normal, uv * 2.3 - drift * vec2(0.4, 1.0)).rgb;
	NORMAL_MAP = mix(n1, n2, 0.5);
	NORMAL_MAP_DEPTH = 0.55;
	float raw = texture(depth_tex, SCREEN_UV).x;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw);
#endif
	vec4 behind = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	behind.xyz /= behind.w;
	float water_depth = max(VERTEX.z - behind.z, 0.0);
	float deep = clamp(water_depth / clarity, 0.0, 1.0);
	float shore = (1.0 - smoothstep(0.0, foam_width, water_depth)) * 0.8;
	float crest = smoothstep(0.55, 0.95, lift) * smoothstep(0.7, 1.6, swell) * 0.7;
	float foam = clamp(shore + crest * (0.6 + 0.4 * n1.r), 0.0, 1.0);
	vec3 water = mix(shallow_color, deep_color, deep);
	water = mix(water, vec3(dot(water, vec3(0.3, 0.5, 0.2))) * 0.45, gloom);
	ALBEDO = mix(water, foam_color * (1.0 - 0.3 * gloom), foam);
	ALPHA = clamp(0.45 + 0.55 * deep + foam, 0.0, 1.0);
	ROUGHNESS = mix(0.06, 0.6, foam);
	SPECULAR = 0.55;
}
"""

var waves: SeaWaves
var swell := 0.5  # metres, set by the sea world from the region and its weather
var gloom := 0.0  # 0..1, set by the sea world from the weather's light

var _near := MeshInstance3D.new()
var _far := MeshInstance3D.new()
var _material := ShaderMaterial.new()
var _step := 4.0  # metres between the near mesh's vertices
var _size := 320.0
var _moving := false
var _shaders := {}


func setup(cfg: Dictionary) -> void:
	waves = SeaWaves.new(cfg)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var normals := NoiseTexture2D.new()
	normals.width = 512
	normals.height = 512
	normals.seamless = true
	normals.as_normal_map = true
	normals.bump_strength = 5.0
	normals.generate_mipmaps = true
	normals.noise = noise
	_material.set_shader_parameter("wave_normal", normals)
	var list := waves.shader_waves()
	_material.set_shader_parameter("w0", list[0])
	_material.set_shader_parameter("w1", list[1])
	_material.set_shader_parameter("w2", list[2])
	_material.set_shader_parameter("shares", list[3])
	_near.material_override = _material
	_far.material_override = _material
	_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_near)
	add_child(_far)
	_far.mesh = _ring(0.0, float(cfg["far"]), 1)


# The graphics tier decides the mesh: [vertices across, metres across] (data waves.mesh); flat when not moving.
func set_detail(tier: String, cfg: Dictionary) -> void:
	_moving = (cfg["moving_tiers"] as Array).has(tier)
	var spec: Array = cfg["mesh"].get(tier, [24, 320])
	var across := int(spec[0]) if _moving else 8
	_size = float(spec[1])
	_step = _size / float(across)
	var plane := PlaneMesh.new()
	plane.size = Vector2(_size, _size)
	plane.subdivide_width = across - 1
	plane.subdivide_depth = across - 1
	_near.mesh = plane
	_far.mesh = _ring(_size * 0.5 - _step, float(cfg["far"]), 48)
	_far.position.y = -0.02
	var defines := "#define SWELL\n" if _moving else ""
	if not _shaders.has(defines):
		var shader := Shader.new()
		shader.code = defines + CODE
		_shaders[defines] = shader
	_material.shader = _shaders[defines]
	_material.set_shader_parameter("fade_from", _size * 0.3)
	_material.set_shader_parameter("fade_to", _size * 0.46)


# A flat ring (or disc with inner 0) of the ocean out to the horizon, on the xz plane.
func _ring(inner: float, outer: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := maxi(sides, 4) if inner > 0.0 else 4
	for i in n:
		var a := TAU * float(i) / float(n)
		var b := TAU * float(i + 1) / float(n)
		var o1 := Vector3(cos(a), 0, sin(a)) * outer
		var o2 := Vector3(cos(b), 0, sin(b)) * outer
		if inner > 0.0:
			var i1 := Vector3(cos(a), 0, sin(a)) * inner
			var i2 := Vector3(cos(b), 0, sin(b)) * inner
			st.add_vertex(i1)
			st.add_vertex(o1)
			st.add_vertex(o2)
			st.add_vertex(i1)
			st.add_vertex(o2)
			st.add_vertex(i2)
		else:
			st.add_vertex(Vector3.ZERO)
			st.add_vertex(o1)
			st.add_vertex(o2)
	return st.commit()


# Are the waves drawn moving (Medium and up)? Ships ride only a small bob on the flat tiers.
func is_moving() -> bool:
	return _moving


# Each frame: follow the camera, push the clock, the swell and the colours.
func follow(camera_at: Vector3, sea_offset: Vector2, seconds: float, region: Dictionary) -> void:
	var snap := Vector3(snappedf(camera_at.x, _step), 0.0, snappedf(camera_at.z, _step))
	_near.global_position = Vector3(snap.x, global_position.y, snap.z)
	_far.global_position = Vector3(camera_at.x, global_position.y - 0.02, camera_at.z)
	_material.set_shader_parameter("sea_time", seconds)
	_material.set_shader_parameter("sea_offset", sea_offset)
	_material.set_shader_parameter("centre", Vector2(camera_at.x, camera_at.z))
	_material.set_shader_parameter("swell", swell)
	_material.set_shader_parameter("gloom", gloom)
	_material.set_shader_parameter("deep_color", Color(region["sea"][0], region["sea"][1], region["sea"][2]))
	_material.set_shader_parameter("shallow_color", Color(region["shallow"][0], region["shallow"][1], region["shallow"][2]))
