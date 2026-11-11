# Purpose: tiny procedural chime for a gun drop: the higher the tier the more rising notes. Generated once per tier and cached; no audio files.
# Dependencies: none.
extends RefCounted

const RATE := 22050
const NOTES := [0.0, 2.0, 4.0, 7.0, 9.0, 12.0, 16.0, 19.0]  # semitones above A4 (major pentatonic climb)

static var _cache: Dictionary = {}


# Stream for tier index 0..7 (grey..pony).
static func chime(tier_index: int) -> AudioStreamWAV:
	if _cache.has(tier_index):
		return _cache[tier_index]
	var count := mini(tier_index + 1, 6)
	var note_len := 0.11
	var total := int(float(RATE) * (note_len * float(count) + 0.25))
	var data := PackedByteArray()
	data.resize(total * 2)
	for n in count:
		var freq := 440.0 * pow(2.0, float(NOTES[n]) / 12.0)
		var start := int(float(RATE) * note_len * float(n))
		var length := int(float(RATE) * 0.3)
		for i in length:
			var idx := start + i
			if idx >= total:
				break
			var t := float(i) / float(RATE)
			var env := exp(-t * 9.0)
			var s := (sin(TAU * freq * t) * 0.7 + sin(TAU * freq * 2.0 * t) * 0.2) * env * 0.35
			var prev := data.decode_s16(idx * 2)
			data.encode_s16(idx * 2, clampi(prev + int(s * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	_cache[tier_index] = wav
	return wav
