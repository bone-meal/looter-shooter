# Purpose: the picture shown while the game is busy (a session is being built, Aurelind is being entered): one of the
# game's own screenshots picked at random (assets/ui/loading/<name>.jpg, listed in data/loading.json; taken by the
# "!photo" step of tools/dev_boot.gd), the word Loading and a bar that moves with every mark of game/load_clock.gd.
# The work it covers gives no frames back, so each change is drawn at once with RenderingServer.force_draw; the 3D
# view is switched off meanwhile (nothing half-built is drawn, and the forced frames cost almost nothing).
# Dependencies: game/load_clock.gd, core/data_store.gd.
extends Control

const LoadClock = preload("res://game/load_clock.gd")
const DataStore = preload("res://core/data_store.gd")

var _picture := TextureRect.new()
var _front := Control.new()
var _names: Array = []
var _steps := 1
var _seen := 0
var _fading: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	if FileAccess.file_exists("res://data/loading.json"):
		_names = DataStore.load_json("res://data/loading.json").get("pictures", [])
	_picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_picture)
	_front.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.draw.connect(_draw_front)
	add_child(_front)


# Shows a random picture right now. `steps` = how many LoadClock marks the coming work will make (for the bar).
func begin(steps: int) -> void:
	if _fading != null:
		_fading.kill()
	_steps = maxi(steps, 1)
	_seen = 0
	modulate.a = 1.0
	_picture.texture = null
	if not _names.is_empty():
		var path := "res://assets/ui/loading/%s.jpg" % String(_names[randi() % _names.size()])
		if ResourceLoader.exists(path):
			_picture.texture = load(path) as Texture2D
	visible = true
	get_viewport().disable_3d = true
	LoadClock.on_mark = _step
	_front.queue_redraw()
	RenderingServer.force_draw()


func _step() -> void:
	_seen += 1
	_front.queue_redraw()
	RenderingServer.force_draw()


# The work is done: the world is drawn again and the picture fades away.
func finish(_unused: int = 0) -> void:
	LoadClock.on_mark = Callable()
	get_viewport().disable_3d = false
	_seen = _steps
	_front.queue_redraw()
	_fading = create_tween()
	_fading.tween_property(self, "modulate:a", 0.0, 0.6)
	_fading.tween_callback(hide)


func _draw_front() -> void:
	var area := _front.size
	if _picture.texture == null:
		_front.draw_rect(Rect2(Vector2.ZERO, area), Color(0.05, 0.06, 0.08))
	_front.draw_rect(Rect2(0.0, area.y - 58.0, area.x, 58.0), Color(0, 0, 0, 0.55))
	_front.draw_string(ThemeDB.fallback_font, Vector2(28.0, area.y - 22.0), "Loading", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(1, 1, 1, 0.92))
	var bar := Rect2(140.0, area.y - 34.0, area.x - 180.0, 8.0)
	_front.draw_rect(bar, Color(1, 1, 1, 0.18))
	_front.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(_seen) / float(_steps), 0.0, 1.0), bar.size.y)), Color(1.0, 0.82, 0.3))
