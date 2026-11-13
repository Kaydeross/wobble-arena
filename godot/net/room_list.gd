class_name RoomList
extends RefCounted
## The public room list (docs/PROTOCOL.md layer 1: `list` -> `rooms`), like the web game's netBrowse: open a socket,
## send `list`, take the first `rooms` reply, close. Call fetch(url), then poll(dt) every frame until `done`.
## `done(rooms, err)`: rooms = [{id, name, host, mode, modeName, map, n, max, started, build, pub}] (fullest first),
## err = "" or a sentence for the player (server unreachable, no answer).

signal done(rooms: Array, err: String)

const TIMEOUT := 6.0
const ERR_REACH := "Can't reach the game server. Check your internet, then try again."
const ERR_SILENT := "The game server did not answer. Try again in a moment."

var ws := WebSocketPeer.new()
var busy := false
var rooms: Array = []
var error := ""
var online := -1                 ## players connected to the server (from `rooms`), -1 = unknown
var _t := 0.0
var _sent := false
var _opened := false

func fetch(url: String) -> void:
	if busy: return
	busy = true
	_t = 0.0; _sent = false; _opened = false
	ws = WebSocketPeer.new()
	if url.strip_edges() == "" or ws.connect_to_url(url.strip_edges()) != OK:
		_finish([], tr(ERR_REACH))

func poll(dt: float) -> void:
	if not busy: return
	_t += dt
	ws.poll()
	var s := ws.get_ready_state()
	if s == WebSocketPeer.STATE_OPEN:
		_opened = true
		if not _sent:
			_sent = true
			ws.send_text(JSON.stringify({"op": "list"}))
		while busy and ws.get_available_packet_count() > 0:
			var m: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if m is Dictionary and str(m.get("op", "")) == "rooms":
				if m.get("online") is float: online = int(m["online"])
				_finish(clean(m.get("rooms", [])), "")
				return
	elif s == WebSocketPeer.STATE_CLOSED:
		_finish([], tr(ERR_SILENT) if _opened else tr(ERR_REACH))
		return
	if busy and _t > TIMEOUT:
		_finish([], tr(ERR_SILENT) if _opened else tr(ERR_REACH))

func _finish(list: Array, err: String) -> void:
	busy = false
	ws.close()
	rooms = list
	error = err
	done.emit(list, err)

## Server rows -> typed dictionaries (anything malformed dropped), fullest first.
static func clean(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array): return out
	for r: Variant in raw:
		if not (r is Dictionary) or str(r.get("id", "")) == "": continue
		out.append({"id": str(r["id"]), "name": str(r.get("name", "Room")), "host": str(r.get("host", "")),
			"mode": str(r.get("mode", "")), "modeName": str(r.get("modeName", r.get("mode", ""))), "map": str(r.get("map", "")),
			"n": int(r.get("n", 0)), "max": int(r.get("max", 0)), "started": bool(r.get("started", false)), "build": str(r.get("build", ""))})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["n"] > b["n"])
	return out

## Why a room cannot be joined from the list ("" = it can): another game version, or no free seat.
static func blocked_reason(r: Dictionary) -> String:
	var b := str(r.get("build", ""))
	if b != "" and b != NetClient.BUILD: return TranslationServer.translate("Different game version")
	if int(r.get("max", 0)) > 0 and int(r.get("n", 0)) >= int(r.get("max", 0)): return TranslationServer.translate("Full")
	return ""
