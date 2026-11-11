# Purpose: signs and verifies the local profile save with HMAC-SHA256, so casual edits of the save file are detected.
# Dependencies: none (uses the engine's Crypto). Limit: the key ships inside the game, so a determined person can extract it; the host's join check (core/join_check.gd) is the real defence.
extends RefCounted


# The key is stored as two XOR halves so it is not a plain string in the exported file.
static func _key() -> PackedByteArray:
	var a := PackedByteArray([1, 25, 221, 117, 133, 70, 73, 86, 60, 0, 122, 126, 220, 92, 77, 186, 48, 170, 226, 73, 23, 198, 150, 32, 169, 216, 165, 34, 139, 130, 108, 4])
	var b := PackedByteArray([169, 172, 30, 67, 247, 62, 39, 5, 195, 52, 167, 58, 223, 69, 30, 183, 35, 11, 209, 204, 77, 171, 82, 144, 45, 222, 255, 150, 247, 45, 7, 98])
	var key := PackedByteArray()
	for i in a.size():
		key.append(a[i] ^ b[i])
	return key


static func sign_payload(payload: String) -> String:
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, _key(), payload.to_utf8_buffer()).hex_encode()


static func verify(payload: String, signature: String) -> bool:
	var expected: String = sign_payload(payload)
	if expected.length() != signature.length():
		return false
	var diff := 0
	for i in expected.length():
		diff |= expected.unicode_at(i) ^ signature.unicode_at(i)
	return diff == 0
