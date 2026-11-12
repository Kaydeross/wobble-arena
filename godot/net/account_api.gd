class_name AccountApi
extends Node
## Minimal client for the account REST API (docs/PROTOCOL.md section 4): POST /api/login only, for now.
## The token goes to Settings ("token", "user") and NetClient sends it with the `auth` op. Phase 3 does the real
## account screens (signup, cloud save, logout, delete).

signal finished(ok: bool, message: String)

var _http: HTTPRequest

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_done)

## ws://host:port/ws -> http://host:port (wss -> https): the REST API lives on the same server.
static func http_base(ws_url: String) -> String:
	var u := ws_url.strip_edges()
	if u.begins_with("wss://"): u = "https://" + u.substr(6)
	elif u.begins_with("ws://"): u = "http://" + u.substr(5)
	if u.ends_with("/ws"): u = u.substr(0, u.length() - 3)
	return u.trim_suffix("/")

func login(ws_url: String, id: String, password: String) -> void:
	if _http == null: _ready()
	_http.cancel_request()
	var body := JSON.stringify({"id": id.strip_edges(), "password": password})
	var err := _http.request(http_base(ws_url) + "/api/login", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		finished.emit(false, "Could not reach the server (%d)." % err)

func logout() -> void:
	Settings.set_value("token", "")
	Settings.set_value("user", "")

func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		finished.emit(false, "Could not reach the server."); return
	var r: Variant = JSON.parse_string(body.get_string_from_utf8())
	if code == 200 and r is Dictionary and r.get("ok") and r.get("token") is String:
		Settings.set_value("token", r["token"])
		Settings.set_value("user", str(r.get("user", "")))
		finished.emit(true, "Logged in as %s." % str(r.get("user", "")))
		return
	var msg := "Login failed (%d)." % code
	if r is Dictionary and r.get("msg"): msg = str(r["msg"])
	finished.emit(false, msg)
