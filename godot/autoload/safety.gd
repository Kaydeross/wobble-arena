extends Node
## Player safety for online play. Account names are filtered by the server; this layer also filters arbitrary in-room
## display names, hides locally blocked players, and sends authenticated reports through the account API.

signal blocked_changed
signal report_finished(ok: bool, msg: String)

const SETTINGS_KEY := "blocked_names"
const BLOCKED_TERMS := ["nigger", "nigga", "faggot", "retard", "rape", "hitler", "nazi", "kkk", "porn", "whore", "slut"]
const MAX_BLOCKED := 100

var _blocked: Array = []

func _ready() -> void:
	_load()

func _load() -> void:
	var raw := str(Settings.get_value(SETTINGS_KEY, "[]"))
	var parsed: Variant = JSON.parse_string(raw)
	_blocked = []
	if parsed is Array:
		for v in parsed:
			var n := clean_name(str(v))
			if n != "" and not _blocked.has(n.to_lower()) and _blocked.size() < MAX_BLOCKED:
				_blocked.append(n.to_lower())

func clean_name(name: String) -> String:
	return name.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().substr(0, 24)

func bad_name(name: String) -> bool:
	var key := ""
	for i in clean_name(name).to_lower().length():
		var c := clean_name(name).to_lower()[i]
		match c:
			"0": c = "o"
			"1": c = "i"
			"3": c = "e"
			"4": c = "a"
			"5": c = "s"
			"7": c = "t"
			"@": c = "a"
			"$": c = "s"
		if c >= "a" and c <= "z": key += c
	for term: String in BLOCKED_TERMS:
		if key.contains(term): return true
	return false

func is_blocked(name: String) -> bool:
	return _blocked.has(clean_name(name).to_lower())

## Every player-facing name goes through here. This hides a blocked player and replaces a disallowed name before it can
## reach a nameplate, feed, result panel or report selector.
func display_name(name: String) -> String:
	var n := clean_name(name)
	if n == "": return "Player"
	if is_blocked(n): return "Blocked Player"
	if bad_name(n): return "[filtered name]"
	return n

func block(name: String) -> bool:
	var n := clean_name(name)
	if n == "" or n == "You" or n == "Blocked Player" or is_blocked(n): return false
	_blocked.append(n.to_lower())
	if _blocked.size() > MAX_BLOCKED: _blocked = _blocked.slice(_blocked.size() - MAX_BLOCKED)
	_save()
	blocked_changed.emit()
	return true

func unblock(name: String) -> bool:
	var key := clean_name(name).to_lower()
	if not _blocked.has(key): return false
	_blocked.erase(key)
	_save()
	blocked_changed.emit()
	return true

func blocked() -> Array:
	return _blocked.duplicate()

func _save() -> void:
	Settings.set_value(SETTINGS_KEY, JSON.stringify(_blocked))

func can_report() -> bool:
	return is_inside_tree() and Save != null and Save.cloud != null and Save.cloud.signed_in()

## Send an authenticated moderation report. `cb(ok, msg)` always runs, including when the player is signed out.
func report(target: String, room: String, reason: String, details: String, cb: Callable = Callable()) -> void:
	var shown := display_name(target)
	if shown == "Blocked Player" or shown == "Player" or shown == "You":
		_finish(cb, false, "Choose another player to report.")
		return
	if not can_report():
		_finish(cb, false, "Sign in to report a player.")
		return
	var allowed := ["harassment", "name", "cheating", "spam", "other"]
	if not allowed.has(reason):
		_finish(cb, false, "Choose a reason.")
		return
	Save.cloud.call_api(HTTPClient.METHOD_POST, "/api/report", {
		"target": shown,
		"room": clean_name(room).substr(0, 16),
		"reason": reason,
		"details": clean_name(details).substr(0, 240),
	}, str(Save.cloud.getv("token")), func(r: Dictionary) -> void:
		_finish(cb, bool(r.get("ok", false)), "Report sent. Thank you." if r.get("ok", false) else str(r.get("msg", "Couldn't send the report."))))

func _finish(cb: Callable, ok: bool, msg: String) -> void:
	report_finished.emit(ok, msg)
	if cb.is_valid(): cb.call(ok, msg)
