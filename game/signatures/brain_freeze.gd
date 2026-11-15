# Purpose: BRAIN FREEZE's red-text behaviour (diary/DESIGN_UNIQUES.md, region 4 chase gun): a slushie cup with a
# straw is taped to the machine gun, and every shot is a sip (the slush in the cup sinks). After the last sip (data
# "sips", 30): brain freeze. The holder's screen frosts at the edges (a small canvas shader), the gun frosts over, and every hit freezes its
# target for "freeze_seconds" until the next reload, which refills the cup. Others see the cup's level and the frost
# (held_suffix "c0".."c9" = how full, "bf" = brain freeze; game/unique_attach.gd show_extra). A puppet's freeze goes
# to the host, who decides (game/enemy.gd apply_freeze).
# Numbers in data/gun_uniques.json brain_freeze "cfg".
# Dependencies: the holder's weapon (is_reloading); the gun model = the gimmick's parent.
extends Node3D

var _player: Node3D
var _cfg: Dictionary = {}
var _gimmick: Node3D
var _sips := 0
var _frozen := false
var _frost: CanvasLayer
var _frost_rect: ColorRect
var _frost_shown := 0.0


func bind(player: Node3D, _gun: Dictionary, def: Dictionary) -> void:
	_player = player
	_cfg = def.get("cfg", {})


func start(gimmick: Node3D) -> void:
	_gimmick = gimmick
	_show()


func stop() -> void:
	_frozen = false
	_show()
	if _frost != null:
		_frost.queue_free()
		_frost = null


func on_inspect() -> void:
	pass


# Every shot of the gun is a sip; the last one gives the brain freeze.
func on_fired() -> void:
	if _frozen:
		return
	_sips += 1
	if _sips >= int(_cfg.get("sips", 30)):
		_frozen = true
	_show()


func on_target_hit(target: Node, _at: Vector3, _amount: float, killed: bool) -> void:
	if _frozen and not killed and target.has_method("apply_freeze"):
		target.call("apply_freeze", float(_cfg.get("freeze_seconds", 3.0)))


func held_suffix() -> String:
	return "bf" if _frozen else "c%d" % mini(9, int(ceilf(fill() * 9.0)))


func fill() -> float:
	return 1.0 - clampf(float(_sips) / float(int(_cfg.get("sips", 30))), 0.0, 1.0)


func frozen() -> bool:
	return _frozen


func _process(delta: float) -> void:
	var w: Variant = _player.get("weapon") if _player != null else null
	if w != null and (_sips > 0 or _frozen) and bool(w.call("is_reloading")):  # any reload refills the cup
		_sips = 0
		_frozen = false
		_show()
	if _frost_rect != null:
		var mat := _frost_rect.material as ShaderMaterial
		_frost_shown = move_toward(_frost_shown, 1.0 if _frozen else 0.0, delta * 3.0)
		mat.set_shader_parameter("amount", _frost_shown)


func _show() -> void:
	show_cup(_gimmick, fill(), _frozen)
	if _frozen and _frost == null and _player != null and _player.is_inside_tree():
		_make_frost()


# The cup's level and the frost on the gun (also another player's copy).
static func show_cup(piece: Node3D, how_full: float, is_frozen: bool) -> void:
	if piece == null or not is_instance_valid(piece):
		return
	var slush := piece.find_child("Slush", true, false) as Node3D
	if slush != null:
		slush.visible = how_full > 0.02
		slush.scale = Vector3(1.0, maxf(how_full, 0.02), 1.0)
	var gun_model := piece.get_parent() as Node3D
	if gun_model == null:
		return
	var frost: StandardMaterial3D = gun_model.get_meta("brain_frost") if gun_model.has_meta("brain_frost") else null
	if frost == null:
		frost = StandardMaterial3D.new()
		frost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		frost.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		frost.albedo_color = Color(0.35, 0.55, 0.75)
		gun_model.set_meta("brain_frost", frost)
	for mesh in gun_model.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_overlay = frost if is_frozen else null


# The holder's screen frosts at the edges: one full-screen rectangle with a small shader (a ragged frost rim from a noise
# texture made once, ice crystals in it); no post effect, cheap on the HD 620.
const FROST_CODE := """
shader_type canvas_item;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float amount = 0.0;
void fragment() {
	vec2 uv = UV;
	float d = length((uv - 0.5) * vec2(1.0, 0.72)) * 2.0;
	float n = texture(noise_tex, uv * 2.5).r;
	float rim = smoothstep(0.62, 1.08, d + (n - 0.5) * 0.45);
	float ice = smoothstep(0.62, 0.85, texture(noise_tex, uv * 8.0 + vec2(0.3, 0.7)).r) * rim;
	COLOR = vec4(0.86, 0.95, 1.0, clamp(rim * 0.7 + ice * 0.35, 0.0, 0.92) * amount);
}
"""

static var _noise: NoiseTexture2D


func _make_frost() -> void:
	_frost = CanvasLayer.new()
	_frost.layer = 4
	if _noise == null:
		var gen := FastNoiseLite.new()
		gen.frequency = 0.02
		gen.fractal_octaves = 4
		_noise = NoiseTexture2D.new()
		_noise.noise = gen
		_noise.seamless = true
		_noise.width = 256
		_noise.height = 256
	var shader := Shader.new()
	shader.code = FROST_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("noise_tex", _noise)
	var rect := ColorRect.new()
	rect.material = mat
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frost.add_child(rect)
	_frost_rect = rect
	add_child(_frost)
