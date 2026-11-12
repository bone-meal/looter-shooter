# Purpose: applies the Graphics preset (render scale, anti-aliasing, mesh smoothness, view distance, and for the realistic look texture size, shadow size, prop density) and the Lighting shader preset (cel shading, outlines, rim light, sky, glow, fog, colour grading, sun shadows) from data/graphics.json. The "realistic" preset switches the world to PBR textures, lights it from an HDRI sky and adds ambient occlusion; on the Forward+ renderer it also turns on real-time GI, volumetric fog and screen reflections. New meshes are styled as they enter the scene tree; a preset change restyles everything once (never per frame).
# Dependencies: core/data_store.gd, data/graphics.json, game/surface_library.gd, game/ground_blend.gd, game/water_surface.gd, game/look_props.gd. Owned by game/game_session.gd, which passes its Environment and sun.
extends Node

const DataStore = preload("res://core/data_store.gd")
const SurfaceLibrary = preload("res://game/surface_library.gd")
const GroundBlend = preload("res://game/ground_blend.gd")
const FantasyGround = preload("res://game/fantasy_ground.gd")
const WaterSurface = preload("res://game/water_surface.gd")
const LookProps = preload("res://game/look_props.gd")

const SKY_TOP := Color(0.12, 0.3, 0.68)
const SKY_HORIZON := Color(0.5, 0.66, 0.84)
const WARM_SUN := Color(1.0, 0.9, 0.74)  # "warmth" 1 = golden sun, cool blue ambient
const COOL_AMBIENT := Color(0.78, 0.86, 1.0)
const FLAT_SKY := Color(0.55, 0.7, 0.85)
const HDRI_DIR := "res://assets/cc0/hdris/"

# Photo sky. The sun in the photo is thousands of times brighter than the rest; it is capped so the sky lights the
# scene softly and the DirectionalLight stays the only hard sun.
const HDRI_SKY_CODE := """
shader_type sky;
// Forward+ shows the same photo much paler than Compatibility does (measured on the GTX 1080). "deepen" (0..1) pushes
// the photo through the sRGB-to-linear curve so Forward+ can be matched to the deep blue Compatibility sky.
uniform sampler2D panorama : filter_linear, repeat_enable;
uniform float energy = 1.0;
uniform float brightest = 8.0;
uniform float deepen = 0.0;
uniform vec3 tint = vec3(1.0);  // a region's own sky colour multiplied onto the photo (fantasy world)

vec3 deeper(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void sky() {
	vec3 photo = texture(panorama, SKY_COORDS).rgb;
	COLOR = min(mix(photo, deeper(photo), deepen), vec3(brightest)) * energy * tint;
}
"""

var env: Environment
var sun: DirectionalLight3D

var _graphics := {}
var _shaders := {}
var _revision := 0  # bumped on every apply; meshes/materials remember the revision they were styled for
var _outline := StandardMaterial3D.new()
var _sky := Sky.new()
var _hdri_sky := Sky.new()
var _hdri_material := ShaderMaterial.new()


static func presets() -> Dictionary:
	return DataStore.load_json("res://data/graphics.json")


# True when the game runs on the Forward+ renderer (GTX 1080 class); false on Compatibility (OpenGL).
static func is_forward() -> bool:
	return RenderingServer.get_rendering_device() != null


func _ready() -> void:
	_outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline.albedo_color = Color(0.04, 0.03, 0.05)
	_outline.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline.grow = true
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = SKY_TOP
	sky_mat.sky_horizon_color = SKY_HORIZON
	sky_mat.ground_horizon_color = SKY_HORIZON
	sky_mat.ground_bottom_color = Color(0.2, 0.3, 0.42)
	_sky.sky_material = sky_mat
	var hdri_shader := Shader.new()
	hdri_shader.code = HDRI_SKY_CODE
	_hdri_material.shader = hdri_shader
	_hdri_sky.sky_material = _hdri_material
	get_tree().node_added.connect(_on_node_added)


func apply(graphics_id: String, shader_id: String) -> void:
	var data := presets()
	_graphics = _find(data.get("graphics", []), graphics_id)
	_shaders = _find(data.get("shaders", []), shader_id)
	if is_forward() and _shaders.get("forward") is Dictionary:
		# The two renderers show the same numbers differently, so a look can carry Forward+ replacements.
		var forward_look: Dictionary = _shaders["forward"]
		_shaders = _shaders.merged(forward_look, true)
	_revision += 1
	_outline.grow_amount = float(_shaders.get("outline", 0.0))
	_apply_world_look()
	_apply_viewport()
	_apply_environment()
	_style_tree(get_tree().root)


# True while the sky is the photo (the realistic look): then a region colours it with set_sky_tint.
func has_photo_sky() -> bool:
	return env != null and env.sky == _hdri_sky and env.background_mode == Environment.BG_SKY


func set_sky_tint(color: Color) -> void:
	_hdri_material.set_shader_parameter("tint", Vector3(color.r, color.g, color.b))


func _find(list: Array, id: String) -> Dictionary:
	for entry: Dictionary in list:
		if String(entry["id"]) == id:
			return entry
	if list.is_empty():
		return {}
	var first: Dictionary = list[0]
	return first


# The realistic-look numbers of the current graphics tier.
func _tier() -> Dictionary:
	var tier: Dictionary = _graphics.get("realistic", {})
	return tier


# The extra numbers a tier uses on the Forward+ renderer ({} on Compatibility or when the tier has none).
func _forward() -> Dictionary:
	if not is_forward():
		return {}
	var extra: Dictionary = _tier().get("forward", {})
	return extra


func _textured() -> bool:
	return bool(_shaders.get("textures", false))


# Flat colours or PBR textures for the world surfaces, water, and which props exist.
func _apply_world_look() -> void:
	var tier := _tier()
	var toon := bool(_shaders.get("toon", false))
	SurfaceLibrary.configure(_textured(), String(tier.get("tex", "1k")), int(tier.get("maps", 3)))
	GroundBlend.configure(toon)
	FantasyGround.configure(toon)
	var water := 0
	if _textured():
		water = int(tier.get("water", 1))
	WaterSurface.configure(water, toon)
	LookProps.configure(_textured(), float(tier.get("props", 1.0)))


func _apply_viewport() -> void:
	var vp := get_viewport()
	var forward := _forward()
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = float(forward.get("render_scale", _graphics.get("render_scale", 1.0)))
	var msaa := int(forward.get("msaa", _graphics.get("msaa", 0)))
	vp.msaa_3d = Viewport.MSAA_8X if msaa >= 8 else Viewport.MSAA_4X if msaa >= 4 else Viewport.MSAA_2X if msaa >= 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if bool(_graphics.get("fxaa", false)) else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.mesh_lod_threshold = 1.0
	if _textured():
		vp.mesh_lod_threshold = float(_tier().get("lod", 1.0))
	var cam := vp.get_camera_3d()
	if cam != null:
		cam.far = float(_graphics.get("view_distance", 1000.0))


func _apply_environment() -> void:
	if env == null or sun == null:
		return
	var s := _shaders
	var hdri := _hdri(s)
	if hdri != null:
		_hdri_material.set_shader_parameter("panorama", hdri)
		_hdri_material.set_shader_parameter("energy", float(s.get("sky_energy", 1.0)))
		_hdri_material.set_shader_parameter("brightest", float(s.get("sky_brightest", 8.0)))
		_hdri_material.set_shader_parameter("deepen", float(s.get("sky_deepen", 0.0)))
		env.background_mode = Environment.BG_SKY
		env.sky = _hdri_sky
		env.sky_rotation = Vector3(0.0, deg_to_rad(float(s.get("sky_yaw", 0.0))), 0.0)
	elif bool(s.get("sky", false)):
		env.background_mode = Environment.BG_SKY
		env.sky = _sky
		env.sky_rotation = Vector3.ZERO
	else:
		env.background_mode = Environment.BG_COLOR
		env.background_color = FLAT_SKY
	var warmth := float(s.get("warmth", 0.0))
	if hdri != null:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY  # the photo sky lights the shade
		var sky_light := float(s.get("ambient", 1.0))
		var bounce := 0.0
		if not bool(_forward().get("sdfgi", false)):
			# No real-time GI here (Compatibility, or a tier without it): fake the light bouncing off the ground
			# with a warm fill, otherwise walls in shadow go almost black.
			sky_light = float(s.get("ambient_no_gi", sky_light))
			bounce = float(s.get("bounce", 0.0))
		env.ambient_light_sky_contribution = 1.0 - bounce
		env.ambient_light_color = Color.html(String(s.get("bounce_color", "#ffffff")))
		env.ambient_light_energy = sky_light
		env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR  # the plain sky as ambient washed everything out (tried)
		env.ambient_light_color = Color.WHITE.lerp(COOL_AMBIENT, warmth) * float(s.get("ambient", 0.6))
		env.ambient_light_energy = 1.0
		env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	sun.light_color = Color.WHITE.lerp(WARM_SUN, warmth)
	var glow := float(s.get("glow", 0.0))
	env.glow_enabled = glow > 0.0
	env.glow_intensity = glow
	env.glow_bloom = 0.0  # bloom on the whole frame turned the sand white (tried)
	env.glow_hdr_threshold = float(s.get("glow_threshold", 0.97))  # only near-white and glowing things bloom
	var fog := float(s.get("fog", 0.0))
	env.fog_enabled = fog > 0.0
	env.fog_density = fog
	env.fog_light_color = SKY_HORIZON
	env.fog_sun_scatter = 0.15
	env.fog_aerial_perspective = 1.0 if hdri != null else 0.0  # far things fade into the photo sky's own colour
	env.fog_sky_affect = 0.0 if hdri != null else 1.0
	match String(s.get("tonemap", "linear")):
		"filmic":
			env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		"aces":
			env.tonemap_mode = Environment.TONE_MAPPER_ACES
		"agx":
			env.tonemap_mode = Environment.TONE_MAPPER_AGX
		_:
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_white = float(s.get("white", 1.0))
	env.tonemap_exposure = float(s.get("exposure", 1.0))
	env.adjustment_enabled = true
	env.adjustment_saturation = float(s.get("saturation", 1.0))
	env.adjustment_contrast = float(s.get("contrast", 1.0))
	sun.light_energy = float(s.get("sun_energy", 1.0))
	var shadow_size := int(s.get("shadows", 0))
	if _textured():
		shadow_size = int(_tier().get("shadows", shadow_size))  # the realistic look takes its shadow size from the graphics tier
	sun.shadow_enabled = shadow_size > 0
	if shadow_size > 0:
		RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
		var splits := 4 if shadow_size >= 4096 else 2
		var reach := 120.0 if shadow_size >= 4096 else 70.0
		if _textured():  # a graphics tier may name its own (round 5: High draws 2 splits to 70 m, a third fewer shadow draws, same picture)
			splits = int(_tier().get("shadow_splits", splits))
			reach = float(_tier().get("shadow_far", reach))
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if splits >= 4 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = reach
		sun.shadow_blur = float(s.get("shadow_blur", 1.0))
		sun.shadow_bias = 0.05
		sun.shadow_normal_bias = 1.5
	var ssao := 0.0
	if bool(_tier().get("ssao", false)):
		ssao = float(s.get("ssao", 0.0))
	env.ssao_enabled = ssao > 0.0
	env.ssao_intensity = maxf(ssao, 0.01)
	env.ssao_radius = 1.0
	_apply_forward_extras()


# Real-time GI, indirect light, reflections and volumetric fog exist only on the Forward+ renderer.
func _apply_forward_extras() -> void:
	var forward := _forward()
	var on := _textured() and not forward.is_empty()
	env.sdfgi_enabled = on and bool(forward.get("sdfgi", false))
	env.sdfgi_use_occlusion = true
	env.sdfgi_cascades = int(forward.get("gi_cascades", 4))
	# These two are engine-wide switches, so every tier sets them (missing key = the engine's own default).
	RenderingServer.gi_set_use_half_resolution(bool(forward.get("gi_half", false)))
	RenderingServer.environment_set_sdfgi_frames_to_update_light(int(forward.get("gi_update", 2)) as RenderingServer.EnvironmentSDFGIFramesToUpdateLight)  # 2 = over 4 frames, 4 = over 16
	env.sdfgi_min_cell_size = 0.4
	env.ssil_enabled = on and bool(forward.get("ssil", false))
	env.ssr_enabled = on and bool(forward.get("ssr", false))
	var haze := 0.0
	if on:
		haze = float(forward.get("volumetric", 0.0))
	env.volumetric_fog_enabled = haze > 0.0
	env.volumetric_fog_density = haze
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 96.0
	env.volumetric_fog_sky_affect = 0.1
	sun.light_angular_distance = 0.0  # NOT widened with distance: at 0.5 every shadow became one dithered veil over the whole view and cost half the frame (round 5)
	get_viewport().use_debanding = on


# The photo sky of a preset, or null when it has none or the file is not downloaded/imported.
func _hdri(s: Dictionary) -> Texture2D:
	var id := String(s.get("sky_hdri", ""))
	if id == "":
		return null
	var path := "%s%s/%s_%s.hdr" % [HDRI_DIR, id, id, String(s.get("sky_res", "2k"))]
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


func _on_node_added(node: Node) -> void:
	if _revision == 0:
		return
	if node is GeometryInstance3D:
		_style_geometry(node)
	elif node is Camera3D and node.get_viewport() == get_viewport():
		(node as Camera3D).far = float(_graphics.get("view_distance", 1000.0))


func _style_tree(node: Node) -> void:
	if node is GeometryInstance3D:
		_style_geometry(node)
	for child in node.get_children():
		_style_tree(child)


func _style_geometry(g: GeometryInstance3D) -> void:
	_style_material(g.material_override)
	var mesh: Mesh = null
	if g is MeshInstance3D:
		var mi := g as MeshInstance3D
		mesh = mi.mesh
		for i in mi.get_surface_override_material_count():
			_style_material(mi.get_surface_override_material(i))
	elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
		mesh = (g as MultiMeshInstance3D).multimesh.mesh
	if mesh == null:
		return
	_smooth_mesh(mesh)
	for i in mesh.get_surface_count():
		_style_material(mesh.surface_get_material(i))


func _style_material(m: Material) -> void:
	if not (m is StandardMaterial3D) or m == _outline:
		return
	if int(m.get_meta("style_rev", -1)) == _revision:
		return
	m.set_meta("style_rev", _revision)
	var sm := m as StandardMaterial3D
	if sm.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or sm.emission_enabled:
		return  # glows, effects and see-through things keep their flat look
	var toon := bool(_shaders.get("toon", false))
	sm.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON if toon else BaseMaterial3D.DIFFUSE_BURLEY
	sm.specular_mode = BaseMaterial3D.SPECULAR_TOON if toon else BaseMaterial3D.SPECULAR_SCHLICK_GGX
	var rim := float(_shaders.get("rim", 0.0))
	sm.rim_enabled = rim > 0.0
	sm.rim = rim
	sm.rim_tint = 0.4
	if sm.next_pass == null or sm.next_pass == _outline:
		sm.next_pass = _outline if float(_shaders.get("outline", 0.0)) > 0.0 else null


func _smooth_mesh(mesh: Mesh) -> void:
	if not (mesh is PrimitiveMesh):
		return
	if int(mesh.get_meta("detail_rev", -1)) == _revision:
		return
	mesh.set_meta("detail_rev", _revision)
	var k := float(_graphics.get("mesh_detail", 1.0))
	if mesh is SphereMesh:
		var sphere := mesh as SphereMesh
		var base := _base(mesh, Vector2i(sphere.radial_segments, sphere.rings))
		sphere.radial_segments = maxi(4, roundi(base.x * k))
		sphere.rings = maxi(3, roundi(base.y * k))
	elif mesh is CylinderMesh:
		var cyl := mesh as CylinderMesh
		var base := _base(mesh, Vector2i(cyl.radial_segments, cyl.rings))
		cyl.radial_segments = maxi(4, roundi(base.x * k))
	elif mesh is CapsuleMesh:
		var cap := mesh as CapsuleMesh
		var base := _base(mesh, Vector2i(cap.radial_segments, cap.rings))
		cap.radial_segments = maxi(4, roundi(base.x * k))
		cap.rings = maxi(2, roundi(base.y * k))
	elif mesh is TorusMesh:
		var torus := mesh as TorusMesh
		var base := _base(mesh, Vector2i(torus.rings, torus.ring_segments))
		torus.rings = maxi(4, roundi(base.x * k))
		torus.ring_segments = maxi(3, roundi(base.y * k))


# The segment counts the mesh was built with (remembered the first time).
func _base(mesh: Mesh, current: Vector2i) -> Vector2i:
	if not mesh.has_meta("base_seg"):
		mesh.set_meta("base_seg", current)
	var base: Vector2i = mesh.get_meta("base_seg")
	return base
