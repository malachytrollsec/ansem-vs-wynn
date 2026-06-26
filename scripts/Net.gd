extends Node
## Multiplayer room client. Speaks the same WebSocket relay protocol as the web
## build's server.mjs (ws://host/room): join -> relay-ready / hello / bye, then
## room-broadcast of any coded message. Works in native and web exports.

signal status_changed(text: String)
signal roster_changed
signal got_message(msg: Dictionary)
signal launch_match(cfg: Dictionary)

var relay_url := "ws://127.0.0.1:8799/room"
var room := ""
var role := ""
var connected := false
var roster: Array = []   # [{from, role, label}]

var _ws: WebSocketPeer = null
var _joined := false

func _ready() -> void:
	if OS.has_feature("web"):
		var injected = JavaScriptBridge.eval("window.MEMPIRES_ROOM_RELAY || ''", true)
		if typeof(injected) == TYPE_STRING and String(injected).begins_with("ws"):
			relay_url = String(injected)

func host_room(code: String) -> void:
	_start(code, "host")

func join_room(code: String) -> void:
	_start(code, "join")

func _start(code: String, r: String) -> void:
	leave()
	room = code.to_upper()
	role = r
	Game.publish_web_state({"netRole": role, "room": room, "relayUrl": relay_url, "netConnected": false})
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(relay_url)
	if err != OK:
		status_changed.emit("connect failed (%d)" % err)
		Game.web_event("net-connect-failed", {"role": role, "room": room, "err": err})
		_ws = null
		return
	status_changed.emit("connecting to relay…")
	Game.web_event("net-connecting", {"role": role, "room": room})

func leave() -> void:
	if _ws != null:
		_ws.close()
	_ws = null
	connected = false
	_joined = false
	roster.clear()
	role = ""
	room = ""
	Game.publish_web_state({"netConnected": false, "netRole": role, "room": room, "roster": 0})
	roster_changed.emit()

func _my_identity() -> Dictionary:
	return {
		"label": String(Game.KINGS[Game.player_king]["name"]),
		"king": Game.player_king,
		"color": "#%s" % Game.KINGS[Game.player_king]["color"].to_html(false),
	}

func send_msg(d: Dictionary) -> void:
	if _ws != null and connected:
		d["code"] = room
		d["role"] = role
		d["from"] = role
		Game.web_event("net-send", {"type": String(d.get("type", "")), "role": role, "room": room})
		_ws.send_text(JSON.stringify(d))

func launch(arena: String, pressure: String) -> void:
	# host announces the match config, then both sides launch
	var wager := _match_wager()
	send_msg({"type": "match-config", "arena": arena, "pressure": pressure, "host_king": Game.player_king, "wager": wager})
	launch_match.emit({"arena": arena, "pressure": pressure, "host_king": Game.player_king, "wager": wager})

func _match_wager() -> Dictionary:
	return {
		"stake": Game.wager_stake,
		"tax": Game.wager_tax(),
		"net": Game.wager_net(),
		"winPayout": Game.wager_payout(true),
		"wagerStatus": "launch",
	}

func _process(_dt: float) -> void:
	if _ws == null:
		return
	_ws.poll()
	var st := _ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _joined:
			_joined = true
			connected = true
			_ws.send_text(JSON.stringify({
				"type": "join", "code": room, "role": role, "from": role,
				"identity": _my_identity(),
			}))
			status_changed.emit("joined room %s as %s" % [room, role])
			Game.publish_web_state({"netConnected": true, "netRole": role, "room": room})
			Game.web_event("net-joined", {"role": role, "room": room})
		while _ws.get_available_packet_count() > 0:
			_handle(_ws.get_packet().get_string_from_utf8())
	elif st == WebSocketPeer.STATE_CLOSED:
		status_changed.emit("relay closed (%d)" % _ws.get_close_code())
		_ws = null
		connected = false
		_joined = false
		Game.publish_web_state({"netConnected": false, "netRole": role, "room": room})

func _handle(txt: String) -> void:
	var msg = JSON.parse_string(txt)
	if typeof(msg) != TYPE_DICTIONARY:
		return
	Game.web_event("net-recv", {"type": String(msg.get("type", "")), "from": String(msg.get("from", "")), "room": String(msg.get("code", room))})
	match String(msg.get("type", "")):
		"relay-ready":
			status_changed.emit("relay ready — share code %s" % room)
		"hello":
			_add_peer(msg, true)
		"hello-ack":
			_add_peer(msg, false)
		"bye":
			_remove_peer(msg)
		"match-config":
			launch_match.emit({
				"arena": String(msg.get("arena", "meadow")),
				"pressure": String(msg.get("pressure", "standard")),
				"host_king": String(msg.get("host_king", "doge")),
				"wager": msg.get("wager", {}),
			})
		_:
			got_message.emit(msg)

func _add_peer(msg: Dictionary, reply: bool) -> void:
	var from := String(msg.get("from", ""))
	var ident: Dictionary = msg.get("identity", {}) if typeof(msg.get("identity")) == TYPE_DICTIONARY else {}
	for p in roster:
		if p["from"] == from:
			return
	roster.append({"from": from, "role": String(msg.get("role", "")), "label": String(ident.get("label", from)), "king": String(ident.get("king", ""))})
	roster_changed.emit()
	Game.publish_web_state({"roster": roster.size(), "lastPeer": String(ident.get("label", from))})
	status_changed.emit("%s joined" % String(ident.get("label", from)))
	if reply:
		send_msg({"type": "hello-ack", "identity": _my_identity()})

func _remove_peer(msg: Dictionary) -> void:
	var from := String(msg.get("from", ""))
	roster = roster.filter(func(p): return p["from"] != from)
	roster_changed.emit()
	Game.publish_web_state({"roster": roster.size()})
	status_changed.emit("a commander left")
