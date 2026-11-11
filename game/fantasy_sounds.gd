# Purpose: plays the fantasy world's sounds (and, as a second copy made by game/game_session.gd with `folder` and
# data/sounds.json, the gun side's shots, reloads, explosions and every enemy's attack). Which file, how loud, how much its pitch varies and how far it carries is
# data (data/fantasy/sounds.json); callers only name a sound and, if it happens somewhere, the place. A fixed set of
# players is reused in turn, and each region's ambience loop cross-fades into the next as the player walks.
# Every sound asks game/sound_board.gd whether the player muted it and tells it when it is audible.
# Dependencies: data/fantasy/sounds.json, assets/audio/fantasy/*.wav (tools/make_fantasy_sounds.py), game/sound_board.gd.
extends Node3D

const SoundBoard = preload("res://game/sound_board.gd")

var folder := "res://assets/audio/fantasy/"  # where the <id>.wav files lie (set before the first sound)

var _data: Dictionary
var _streams := {}  # id -> AudioStream (loaded the first time it is needed)
var _placed: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _next_placed := 0
var _next_flat := 0
var _beds: Array[AudioStreamPlayer] = []  # two ambience players: one fading in, one fading out
var _bed := 0
var _region := ""
var _master := 0.0
var _bed_volume := -80.0  # what the current ambience plays at when it is not muted
var _fade_until := 0.0  # engine time the ambience cross-fade is over
var _poll := 0.0


func setup(data: Dictionary) -> void:
	_data = data
	_master = float(data.get("master", 0.0))
	top_level = true
	for i in int(data.get("voices", 10)):
		var placed := AudioStreamPlayer3D.new()
		placed.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(placed)
		_placed.append(placed)
	for i in 4:
		var flat := AudioStreamPlayer.new()
		add_child(flat)
		_flat.append(flat)
	for i in 2:
		var bed := AudioStreamPlayer.new()
		bed.volume_db = -80.0
		add_child(bed)
		_beds.append(bed)


func _stream(id: String) -> AudioStream:
	if not _streams.has(id):
		var path := folder + id + ".wav"
		_streams[id] = load(path) if ResourceLoader.exists(path) else null
	return _streams[id]


# Plays a sound by id: at a world position, or flat (the same in both ears) when no position is given.
func play(id: String, at: Vector3 = Vector3.INF) -> void:
	var def: Dictionary = _data["sounds"].get(id, {})
	var stream := _stream(id)
	if def.is_empty() or stream == null or not SoundBoard.allow(id):
		return
	var pitch := 1.0
	if def.has("pitch"):
		pitch = randf_range(float(def["pitch"][0]), float(def["pitch"][1]))
	if at.is_finite():
		var voice := _placed[_next_placed]
		_next_placed = (_next_placed + 1) % _placed.size()
		voice.stream = stream
		voice.global_position = at
		voice.volume_db = float(def.get("volume", 0.0)) + _master
		voice.pitch_scale = pitch
		voice.unit_size = float(def.get("range", 40.0)) * 0.15  # fades quickly with distance and is gone at `range`
		voice.max_distance = float(def.get("range", 40.0))
		voice.play()
		var ear := get_viewport().get_camera_3d()
		if ear == null or ear.global_position.distance_to(at) <= voice.max_distance:
			SoundBoard.heard(id)
	else:
		var voice := _flat[_next_flat]
		_next_flat = (_next_flat + 1) % _flat.size()
		voice.stream = stream
		voice.volume_db = float(def.get("volume", 0.0)) + _master
		voice.pitch_scale = pitch
		voice.play()
		SoundBoard.heard(id)


# Twice a second: a muted ambience goes silent (and comes back when unmuted); a playing one counts as heard.
func _process(delta: float) -> void:
	_poll += delta
	if _poll < 0.5:
		return
	_poll = 0.0
	var bed := _beds[_bed]
	if _region == "" or not bed.playing:
		return
	var id := "ambience_" + _region
	if SoundBoard.allow(id):
		SoundBoard.heard(id)
	if Time.get_ticks_msec() / 1000.0 >= _fade_until:
		bed.volume_db = _bed_volume if SoundBoard.allow(id) else -80.0


# The ambience of a region fades in and the previous one out ("" = silence, on leaving the world).
func set_region(id: String) -> void:
	if id == _region:
		return
	_region = id
	var def: Dictionary = _data["ambience"].get(id, {})
	var seconds := float(_data.get("fade_seconds", 2.0))
	var old := _beds[_bed]
	_bed = 1 - _bed
	var fresh := _beds[_bed]
	var out := create_tween()
	out.tween_property(old, "volume_db", -80.0, seconds)
	out.tween_callback(old.stop)
	if def.is_empty():
		return
	var stream := _stream(String(def["file"]))
	if stream == null:
		return
	if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
	fresh.stream = stream
	fresh.volume_db = -60.0
	fresh.play()
	_bed_volume = float(def.get("volume", -12.0)) + _master
	_fade_until = Time.get_ticks_msec() / 1000.0 + seconds
	create_tween().tween_property(fresh, "volume_db", _bed_volume if SoundBoard.allow("ambience_" + id) else -80.0, seconds)
