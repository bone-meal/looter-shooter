# Purpose: developer probe (local only): can two WebRTC peers connect when their ICE candidates travel ONLY inside
# the session description (as a=candidate lines), with no separate candidate list? Prints the result and quits.
# Dependencies: the webrtc_native GDExtension.
extends Node

var a := WebRTCPeerConnection.new()
var b := WebRTCPeerConnection.new()
var a_desc := {}
var b_desc := {}
var a_cands: Array[String] = []
var b_cands: Array[String] = []
var chan: WebRTCDataChannel


func _ready() -> void:
	a.initialize({"iceServers": []})
	b.initialize({"iceServers": []})
	a.session_description_created.connect(func(t: String, s: String) -> void:
		a.set_local_description(t, s)
		a_desc = {"type": t, "sdp": s})
	b.session_description_created.connect(func(t: String, s: String) -> void:
		b.set_local_description(t, s)
		b_desc = {"type": t, "sdp": s})
	a.ice_candidate_created.connect(func(_m: String, _i: int, c: String) -> void: a_cands.append(c))
	b.ice_candidate_created.connect(func(_m: String, _i: int, c: String) -> void: b_cands.append(c))
	chan = a.create_data_channel("x", {"negotiated": true, "id": 1})
	b.create_data_channel("x", {"negotiated": true, "id": 1})
	a.create_offer()
	var t := 0.0
	while (a_desc.is_empty() or a.get_gathering_state() != WebRTCPeerConnection.GATHERING_STATE_COMPLETE) and t < 5.0:
		a.poll()
		await get_tree().process_frame
		t += get_process_delta_time()
	_say("A candidates: %d first: %s" % [a_cands.size(), a_cands[0] if not a_cands.is_empty() else "-"])
	if a_desc.is_empty():
		_say("PROBE no offer made")
		get_tree().quit()
		return
	_say("A sdp has candidates already: %s" % str(String(a_desc["sdp"]).contains("a=candidate")))
	b.set_remote_description(a_desc["type"], _with(a_desc["sdp"], a_cands))
	t = 0.0
	while (b_desc.is_empty() or b.get_gathering_state() != WebRTCPeerConnection.GATHERING_STATE_COMPLETE) and t < 5.0:
		b.poll()
		a.poll()
		await get_tree().process_frame
		t += get_process_delta_time()
	a.set_remote_description(b_desc["type"], _with(b_desc["sdp"], b_cands))
	t = 0.0
	while t < 8.0 and (a.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED or b.get_connection_state() != WebRTCPeerConnection.STATE_CONNECTED):
		a.poll()
		b.poll()
		await get_tree().process_frame
		t += get_process_delta_time()
	_say("PROBE connected A=%s B=%s after %.1f s" % [a.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED, b.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED, t])
	get_tree().quit()


var _lines := PackedStringArray()


func _say(text: String) -> void:
	print(text)
	_lines.append(text)
	var file := FileAccess.open("res://tools/webrtc_sdp_probe.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()


func _with(sdp: String, cands: Array[String]) -> String:
	var out := sdp
	if not out.ends_with("\r\n"):
		out += "\r\n"
	for c in cands:
		out += (c if c.begins_with("a=") else "a=" + c) + "\r\n"
	return out
