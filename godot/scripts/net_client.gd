class_name NetClient
extends RefCounted
## Wobble Arena protocol client, layers 1 and 2 of docs/PROTOCOL.md (server ops + room messages).
## Call poll() every frame. Connect to the signals, then connect_to_server(), join_room().

signal connected
signal disconnected
signal server_message(m: Dictionary)   ## any layer-1 message from the server
signal room_joined(room_id: String, cid: int)
signal join_failed(reason: String)
signal welcomed(slot: int, room_name: String)
signal room_message(m: Dictionary)     ## layer-2 message from the host ("msg" op)

const PROTO := 1
const BUILD := "b76.0"

var ws := WebSocketPeer.new()
var state := WebSocketPeer.STATE_CLOSED
var slot := -1
var cid := -1
var room_id := ""
var player_name := "Godot"
var token := ""

func connect_to_server(url: String) -> int:
	return ws.connect_to_url(url)

func close() -> void:
	ws.close()

func send_op(d: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))

func join_room(id: String) -> void:
	send_op({"op": "join", "id": id, "build": BUILD})

func to_host(m: Dictionary) -> void:
	send_op({"op": "tohost", "m": m})

func send_hello(skin := "none", hat := "none", color := 0x39b5a8) -> void:
	to_host({"t": "hello", "build": BUILD, "proto": PROTO, "name": player_name.substr(0, 12), "skin": skin, "hat": hat, "color": color})

func poll() -> void:
	ws.poll()
	var s := ws.get_ready_state()
	if s != state:
		state = s
		if s == WebSocketPeer.STATE_OPEN:
			if token != "":
				send_op({"op": "auth", "token": token})
			connected.emit()
		elif s == WebSocketPeer.STATE_CLOSED:
			disconnected.emit()
	while s == WebSocketPeer.STATE_OPEN and ws.get_available_packet_count() > 0:
		_handle(ws.get_packet().get_string_from_utf8())

func _handle(text: String) -> void:
	var m = JSON.parse_string(text)
	if typeof(m) != TYPE_DICTIONARY or not m.has("op"):
		return
	server_message.emit(m)
	match m["op"]:
		"joined":
			cid = int(m.get("cid", -1)); room_id = str(m.get("id", ""))
			room_joined.emit(room_id, cid)
			send_hello()
		"nojoin":
			join_failed.emit(str(m.get("reason", "")))
		"msg":
			var inner = m.get("m", {})
			if typeof(inner) != TYPE_DICTIONARY:
				return
			if inner.get("t", "") == "welcome":
				slot = int(inner.get("id", -1))
				welcomed.emit(slot, str(inner.get("name", "")))
			room_message.emit(inner)
