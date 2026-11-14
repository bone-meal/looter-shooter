# Purpose: the sounds of opening a card pack, made in code (no audio files): a paper tear (short noise bursts) and the
# reveal chimes, which are the loot-tier chimes of game/tier_sound.gd (common = green, rare = blue, epic = purple,
# legendary = orange, a foil = rainbow / pony). Ids for the Sounds page (data/sound_list.json "Card packs"):
# card_tear, card_<rarity>, card_foil.
# Dependencies: game/tier_sound.gd.
extends RefCounted

const TierSound = preload("res://game/tier_sound.gd")

const RATE := 22050
const TIER_OF := {"common": 1, "rare": 2, "epic": 3, "legendary": 5}

static var _tear: AudioStreamWAV


static func tear() -> AudioStreamWAV:
	if _tear != null:
		return _tear
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var total := int(RATE * 0.42)
	var data := PackedByteArray()
	data.resize(total * 2)
	var low := 0.0
	for i in total:
		var t := float(i) / RATE
		# crackles: the paper gives way in little steps that come faster, then a last rip
		var step := fmod(t * (22.0 + 40.0 * t), 1.0)
		var env := (1.0 - step) * (0.5 + 0.5 * t / 0.42) * clampf((0.42 - t) / 0.06, 0.0, 1.0)
		var noise := rng.randf_range(-1.0, 1.0)
		low = low * 0.55 + noise * 0.45  # a little softer than white noise
		data.encode_s16(i * 2, int(clampf(low * env * 0.8, -1.0, 1.0) * 32000.0))
	_tear = AudioStreamWAV.new()
	_tear.format = AudioStreamWAV.FORMAT_16_BITS
	_tear.mix_rate = RATE
	_tear.data = data
	return _tear


# The chime for a revealed card (a foil rings as rainbow / pony).
static func reveal(rarity: String, finish: String) -> AudioStreamWAV:
	if finish == "pony":
		return TierSound.chime(7)
	if finish == "rainbow":
		return TierSound.chime(6)
	return TierSound.chime(int(TIER_OF.get(rarity, 1)))


static func id_of(rarity: String, finish: String) -> String:
	return "card_foil" if finish != "" else "card_" + rarity
