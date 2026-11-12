class_name NetClient
extends RefCounted
## Wobblers Arena protocol client, layers 1 and 2 of docs/PROTOCOL.md (server ops + room messages).
## Call poll() every frame. Connect to the signals, then connect_to_server(), join_room().
## GuestSession (net/guest_session.gd) drives this for the guest role.

signal connected
signal disconnected
signal server_message(m: Dictionary)   ## any layer-1 message from the server
signal room_joined(room_id: String, cid: int)
signal join_failed(reason: String)
signal welcomed(slot: int, room_name: String)
signal room_message(m: Dictionary)     ## layer-2 message from the host ("msg" op)

const PROTO := 1
## The web game's NET_BUILD (public/index.html ~8551). The server refuses a join whose build differs from the room's;
## compatibility is really decided by `proto` in hello/welcome (PROTOCOL.md 6.1), see GuestSession's retry.
const BUILD := "b77.0"

var ws := WebSocketPeer.new()
var state := WebSocketPeer.STATE_CLOSED
var slot := -1
var cid := -1
var room_id := ""
var player_name := "Godot"
var token := ""
## hello info (PROTOCOL.md 2.1): skin, hat, color and the optional class id `cls` ("" = leave it out).
var skin := "none"
var hat := "none"
var color := 0x39b5a8
var cls := ""

func connect_to_server(url: String) -> int:
	state = WebSocketPeer.STATE_CLOSED
	return ws.connect_to_url(url)

func close() -> void:
	ws.close()

func is_open() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN

func send_op(d: Dictionary) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(d))

## `build` "" leaves the field out (the server then skips its build filter).
func join_room(id: String, build: String = BUILD) -> void:
	var m := {"op": "join", "id": id}
	if build != "": m["build"] = build
	send_op(m)

func to_host(m: Dictionary) -> void:
	send_op({"op": "tohost", "m": m})

func hello_info() -> Dictionary:
	var m := {"name": player_name.substr(0, 12), "skin": skin, "hat": hat, "color": color}
	if cls != "": m["cls"] = cls
	return m

func send_hello() -> void:
	var m := {"t": "hello", "build": BUILD, "proto": PROTO}
	m.merge(hello_info())
	to_host(m)

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
			if inner.get("t", "") == "welcome" and not m.has("from"):
				slot = int(inner.get("id", -1))
				welcomed.emit(slot, str(inner.get("name", "")))
			room_message.emit(inner)
