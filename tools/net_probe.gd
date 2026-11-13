# Purpose: developer probe of online joining through the REAL public trackers and STUN servers of data/net.json:
# a hidden host and a hidden joiner in one program (each with its own multiplayer root) try to connect the way two
# players in different houses do (the local-network shortcut is switched off). Logs every tracker's state, what the joiner's answers carried, and whether the join completed.
# Log tools/net_probe.log (ends NET_PROBE_DONE joined=true|false). Not part of the game.
# Dependencies: addons/tube, the webrtc_native GDExtension, data/net.json, core/data_store.gd.
extends Node

const DataStore = preload("res://core/data_store.gd")
const LIMIT := 60.0

var _lines := PackedStringArray()
var _host: Node
var _guest: Node
var _start := 0.0
var _joined := false
var _done := false


func _ready() -> void:
	_start = Time.get_ticks_msec() / 1000.0
	var cfg: Dictionary = DataStore.load_json("res://data/net.json")
	_say("trackers %s, timeout %.1f s x %d attempts" % [str(cfg["trackers"]), float(cfg.get("signaling_timeout_seconds", 2.0)), int(cfg.get("signaling_attempts", 3))])
	_host = _client(cfg, "Host")
	_guest = _client(cfg, "Guest")
	_host.connect("session_created", func() -> void:
		_say("host: session %s created" % String(_host.get("session_id")))
		_no_lan(_host)  # only the internet way: as for a friend in another house
		_guest.call("join_session", String(_host.get("session_id")))
		_no_lan(_guest))
	_guest.connect("session_joined", func() -> void:
		_joined = true
		_say("guest: JOINED after %.1f s" % _age())
		_finish())
	_host.call("create_session")
	get_tree().create_timer(8.0).timeout.connect(_trackers_report)
	get_tree().create_timer(LIMIT).timeout.connect(_finish)


# Switches Tube's local-network shortcut off for one side.
func _no_lan(client: Node) -> void:
	var lan: Variant = client.get("_local_signaling_peer")
	if lan != null:
		(lan as Object).call("close")
		client.set("_local_signaling_peer", null)


func _client(cfg: Dictionary, who: String) -> Node:
	var root := Node.new()
	root.name = who
	add_child(root)
	var context = (load("res://addons/tube/tube_context.gd") as Script).new()
	var trackers: Array[String] = []
	for url in cfg["trackers"]:
		trackers.append(String(url))
	var stun: Array[String] = []
	for url in cfg["stun"]:
		stun.append(String(url))
	context.set("app_id", String(cfg["app_id"]))
	context.set("trackers_urls", trackers)
	context.set("stun_servers_urls", stun)
	var client: Node = (load("res://addons/tube/tube_client.gd") as Script).new()
	client.set("peer_signaling_timeout", float(cfg.get("signaling_timeout_seconds", 2.0)))
	client.set("peer_signaling_max_attempts", int(cfg.get("signaling_attempts", 3)))
	client.set("context", context)
	client.set("multiplayer_root_node", root)
	root.add_child(client)
	client.connect("error_raised", func(code: int, message: String) -> void: _say("%s ERROR %d: %s" % [who, code, message]))
	client.connect("_tracker_initiated", func(tracker: Object) -> void:
		tracker.connect("warning_raised", func(message: String) -> void: _say("%s tracker %s: %s" % [who, _url(tracker), message]))
		tracker.connect("received_data", func(data: Dictionary) -> void:
			if data.has("answer"):
				var answer: Dictionary = data["answer"]
				_say("%s got an answer via %s: fields %s, candidates in sdp %d, in list %d" % [who, _url(tracker), str(answer.keys()), String(answer.get("sdp", "")).count("a=candidate"), (answer.get("ice_candidates", []) as Array).size()])))
	return client


func _url(tracker: Object) -> String:
	return String((tracker.get("socket") as WebSocketPeer).get_requested_url())


func _trackers_report() -> void:
	for who: Node in [_host, _guest]:
		var states := PackedStringArray()
		for tracker: Object in who.get("_trackers"):
			states.append("%s %s" % [_url(tracker), "OPEN" if bool(tracker.call("is_open")) else "closed"])
		_say("%s trackers after 8 s: %s" % [who.get_parent().name, ", ".join(states)])


func _finish() -> void:
	if _done:
		return
	_done = true
	_say("NET_PROBE_DONE joined=%s after %.1f s" % [str(_joined), _age()])
	get_tree().create_timer(1.0).timeout.connect(get_tree().quit)


func _age() -> float:
	return Time.get_ticks_msec() / 1000.0 - _start


func _say(text: String) -> void:
	print(text)
	_lines.append("%5.1f  %s" % [_age(), text])
	var file := FileAccess.open("res://tools/net_probe.log", FileAccess.WRITE)
	file.store_string("\n".join(_lines) + "\n")
	file.close()
