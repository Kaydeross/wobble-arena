class_name AccountApi
extends Node
## Accounts and the cloud save (docs/PROTOCOL.md section 4, server: accounts.js), the Godot port of the web client's
## `acct` / api / cloudPush / verifyLogin (public/index.html ~8666-8720). One instance lives under the Save autoload
## (`Save.cloud`); the title's Account sheet (ui/account_sheet.gd) and the Play online panel's login fields both use it.
##
## Calls: claim (just a name: the easy path, a password-less account), protect (add a password to it; the reply's recovery
## code is shown once), signup (username, email, password; also with a recovery code), login (username or email),
## logout, change_password, new_recovery, reset (forgot password: recovery code + new password), delete_account.
## Each one ends with `done(op, ok, msg)`; `msg` is plain words for the UI.
##
## Cloud sync of the Save profile, in the web's blob shape (Save.get_blob() / apply_blob()), so a web account and the app
## share progress:
##   - after a sign-in the cloud blob is merged with this device: the same (or a fresh device) -> nothing to ask; this
##     device synced with that account before and the cloud is not newer -> push; the cloud is newer and this device
##     has no unsaved change -> take the cloud (web verifyLogin); otherwise `conflict` -> Keep this device / Use cloud.
##   - every profile change marks it dirty and pushes PUSH_DELAY seconds later (like the web's timer); PUT /api/save
##     carries `base` = the save time this device last matched (web acct.t); `409 stale` = another device saved since ->
##     `conflict` again, nothing more is pushed until it is answered.
##   - offline first: a failed push is retried every RETRY_DELAY seconds, the profile is always saved on the device, and
##     sync_text() says "Saved on this device". Nothing in the game waits for the network.
## Login state (token, user, email, cloud_t, cloud_dirty, cloud_user) is kept in Settings.
## TODO(Phase 5): the token belongs in the iOS Keychain; for now it sits in settings.cfg like the other settings.

signal done(op: String, ok: bool, msg: String)   ## a call finished (signup, login, logout, password, recovery, reset, delete)
signal changed                                    ## signed in / out, or the sync state changed (sync_text())
signal conflict(info: Dictionary)                 ## {local, cloud}: one-line summaries; answer keep_device() / use_cloud()
signal recovery(code: String)                     ## a new recovery code: show it once

const PUSH_DELAY := 15.0
const RETRY_DELAY := 15.0
const FAST_RETRY := 1.5
const TIMEOUT := 10.0
const KEYS := ["token", "user", "email", "cloud_t", "cloud_dirty", "cloud_user"]

var profile: Node                  ## the SaveProfile this syncs (the Save autoload, or a test's)
var use_settings := true           ## false: login state in `mem` only (tests: a second "device")
var mem := {}
var base_override := ""            ## the API's http(s) base; "" = from Settings server_url
var push_delay := PUSH_DELAY
var retry_delay := RETRY_DELAY

var has_password := true           ## false: a name-only account (claim) that can't log in on another device yet; see protect()
var stale := false                 ## another device saved since: waiting for keep_device() / use_cloud()
var busy := false                  ## a push is on its way
var offline := false               ## the last push could not reach the server
var expired := false               ## the login ran out (401): signed out, the profile stays on the device
var last_saved := 0.0              ## unix seconds of the last cloud save / pull this session
var pending := {}                  ## {data, t} of the cloud save waiting for an answer (conflict)
var _push_in := -1.0               ## seconds until the next push (-1 = none planned)
var _applying := false

func _ready() -> void:
	if profile == null: profile = get_parent()
	if profile and profile.has_signal("changed") and not profile.changed.is_connected(_on_profile_changed):
		profile.changed.connect(_on_profile_changed)
	if signed_in(): verify.call_deferred()

# ============================== state ==============================

func _st() -> Node:
	if not use_settings or not is_inside_tree(): return null
	return get_tree().root.get_node_or_null("Settings")

func getv(k: String) -> Variant:
	var st := _st()
	if st: return st.get_value(k)
	return mem.get(k, {"token": "", "user": "", "email": "", "cloud_t": 0, "cloud_dirty": false, "cloud_user": ""}[k])

func setv(k: String, v: Variant) -> void:
	var st := _st()
	if st: st.set_value(k, v)
	else: mem[k] = v

func signed_in() -> bool:
	return str(getv("token")) != ""

func user() -> String:
	return str(getv("user"))

func email() -> String:
	return str(getv("email"))

## Server time (ms) of the cloud save this device last matched (web acct.t).
var t: int:
	get: return int(getv("cloud_t"))
	set(v):
		setv("cloud_t", v)
		if profile and "cloud_t" in profile: profile.cloud_t = v

var dirty: bool:
	get: return bool(getv("cloud_dirty"))
	set(v): setv("cloud_dirty", v)

## ws://host:port/ws -> http://host:port (wss -> https): the REST API lives on the same server.
static func http_base(ws_url: String) -> String:
	var u := ws_url.strip_edges()
	if u.begins_with("wss://"): u = "https://" + u.substr(6)
	elif u.begins_with("ws://"): u = "http://" + u.substr(5)
	if u.ends_with("/ws"): u = u.substr(0, u.length() - 3)
	return u.trim_suffix("/")

func api_base() -> String:
	if base_override != "": return base_override.trim_suffix("/")
	var st := get_tree().root.get_node_or_null("Settings") if is_inside_tree() else null
	return http_base(str(st.get_value("server_url")) if st else "ws://127.0.0.1:3000/ws")

# ============================== HTTP ==============================

## One REST call; `cb` gets {ok, status, err?, msg?, ...}. No network -> {ok: false, err: "net"}.
func call_api(method: int, path: String, body: Variant, token: String, cb: Callable) -> void:
	var h := HTTPRequest.new()
	h.timeout = TIMEOUT
	add_child(h)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "": headers.append("Authorization: Bearer " + token)
	h.request_completed.connect(func(result: int, code: int, _hd: PackedStringArray, raw: PackedByteArray) -> void:
		h.queue_free()
		var r := {}
		if result != HTTPRequest.RESULT_SUCCESS:
			r = {"ok": false, "status": 0, "err": "net", "msg": "Couldn't reach the server. Check your internet and try again."}
		else:
			var js := JSON.new()
			if js.parse(raw.get_string_from_utf8()) == OK and js.data is Dictionary: r = js.data
			r = r.duplicate()
			r["status"] = code
			if not r.has("ok"): r["ok"] = false
			if not r["ok"] and not r.has("msg"): r["msg"] = tr("The server had a problem (%d). Try again in a moment.") % code
		cb.call(r))
	var err := h.request(api_base() + path, headers, method, "" if body == null else JSON.stringify(body))
	if err != OK:
		h.queue_free()
		cb.call_deferred({"ok": false, "status": 0, "err": "net", "msg": "Couldn't reach the server. Check your internet and try again."})

## (`done` is emitted deferred: a call that ends at once still reaches a caller that awaits it right after calling.)
func _finish(op: String, ok: bool, msg: String) -> void:
	changed.emit()
	emit_signal.call_deferred("done", op, ok, msg)

# ============================== account calls ==============================

## Pick a name: a password-less account (POST /api/claim). This device's profile becomes its first cloud save. Names
## nobody uses for 30 days are freed by the server.
func claim(username: String) -> void:
	var data: Variant = profile.get_blob() if profile else null
	call_api(HTTPClient.METHOD_POST, "/api/claim", {"name": username.strip_edges(), "data": data}, "",
		func(r: Dictionary) -> void:
			if not r["ok"]: _finish("claim", false, str(r.get("msg", "Couldn't claim that name. Try again in a moment."))); return
			_signed_in(r)
			setv("cloud_user", user().to_lower())
			t = int(r.get("t", 0)); dirty = false; last_saved = Time.get_unix_time_from_system(); offline = false
			if int(r.get("t", 0)) == 0: _mark_dirty(0.0)
			_finish("claim", true, tr("Welcome, %s! Your name is yours.") % user()))

## Put a password on a name-only account so the name can log in on another device. A recovery code comes with `recovery`.
func protect(password: String) -> void:
	if password.length() < 6: _finish("protect", false, "Passwords are 6 to 72 characters."); return
	call_api(HTTPClient.METHOD_POST, "/api/protect", {"password": password}, str(getv("token")),
		func(r: Dictionary) -> void:
			if _auth_failed(r): _finish("protect", false, str(r["msg"])); return
			if not r["ok"]: _finish("protect", false, str(r.get("msg", "Couldn't set a password. Try again in a moment."))); return
			has_password = true
			if r.get("recovery") is String: recovery.emit(r["recovery"])
			_finish("protect", true, "Password set. This name now works on other devices."))

## Create an account; this device's profile becomes its first cloud save. The recovery code comes with `recovery`.
func signup(username: String, mail: String, password: String) -> void:
	var data: Variant = profile.get_blob() if profile else null
	call_api(HTTPClient.METHOD_POST, "/api/signup", {"username": username.strip_edges(), "email": mail.strip_edges(), "password": password, "data": data}, "",
		func(r: Dictionary) -> void:
			if not r["ok"]: _finish("signup", false, str(r.get("msg", "Couldn't make your account. Try again in a moment."))); return
			_signed_in(r)
			setv("cloud_user", user().to_lower())
			t = int(r.get("t", 0)); dirty = false; last_saved = Time.get_unix_time_from_system(); offline = false
			if r.get("recovery") is String: recovery.emit(r["recovery"])
			if int(r.get("t", 0)) == 0: _mark_dirty(0.0)
			_finish("signup", true, tr("Account created. You're signed in as %s.") % user()))

## Log in with a username or email. `ws_url` (optional) also becomes the server for everything else.
func login(id: String, password: String, ws_url := "") -> void:
	_set_server(ws_url)
	call_api(HTTPClient.METHOD_POST, "/api/login", {"id": id.strip_edges(), "password": password}, "",
		func(r: Dictionary) -> void:
			if not r["ok"]: _finish("login", false, str(r.get("msg", "Couldn't log in. Check your username and password."))); return
			_signed_in(r)
			_merge(r.get("data"), int(r.get("t", 0)))
			_finish("login", true, tr("Signed in as %s.") % user()))

## Forgot the password: username or email + recovery code + a new password. Signs in and shows a new recovery code.
func reset(id: String, code: String, password: String, ws_url := "") -> void:
	_set_server(ws_url)
	call_api(HTTPClient.METHOD_POST, "/api/reset", {"id": id.strip_edges(), "code": code, "password": password}, "",
		func(r: Dictionary) -> void:
			if not r["ok"]: _finish("reset", false, str(r.get("msg", "Couldn't reset your password. Check your recovery code and try again."))); return
			_signed_in(r)
			_merge(r.get("data"), int(r.get("t", 0)))
			if r.get("recovery") is String: recovery.emit(r["recovery"])
			_finish("reset", true, tr("New password set. You're signed in as %s.") % user()))

## Sign out (the last changes are pushed first when possible). The profile stays on this device as a guest.
func logout() -> void:
	var tok := str(getv("token"))
	var out := func() -> void:
		if tok != "": call_api(HTTPClient.METHOD_POST, "/api/logout", {}, tok, func(_r: Dictionary) -> void: pass)
		_clear_login()
		_finish("logout", true, "Logged out. Your progress stays on this device.")
	if signed_in() and dirty and not stale and not expired:
		push(func(_ok: bool) -> void: out.call())
	else:
		out.call()

func change_password(old: String, next: String) -> void:
	if next.length() < 6: _finish("password", false, "New passwords are 6 to 72 characters."); return
	call_api(HTTPClient.METHOD_POST, "/api/password", {"old": old, "next": next}, str(getv("token")),
		func(r: Dictionary) -> void:
			if _auth_failed(r): _finish("password", false, str(r["msg"])); return
			_finish("password", bool(r["ok"]), "Password changed." if r["ok"] else str(r.get("msg", "Couldn't change your password. Try again in a moment."))))

## A new recovery code (needs the password); the old one stops working.
func new_recovery(password: String) -> void:
	call_api(HTTPClient.METHOD_POST, "/api/recovery", {"password": password}, str(getv("token")),
		func(r: Dictionary) -> void:
			if _auth_failed(r): _finish("recovery", false, str(r["msg"])); return
			if r["ok"] and r.get("recovery") is String: recovery.emit(r["recovery"])
			_finish("recovery", bool(r["ok"]), "Save this code now. It won't be shown again." if r["ok"] else str(r.get("msg", "Couldn't make a recovery code. Try again in a moment."))))

## Delete the account and its cloud save for good (App Store 5.1.1(v)). This device starts again as a fresh guest.
func delete_account(password: String) -> void:
	call_api(HTTPClient.METHOD_POST, "/api/delete", {"password": password}, str(getv("token")),
		func(r: Dictionary) -> void:
			if _auth_failed(r): _finish("delete", false, str(r["msg"])); return
			if not r["ok"]: _finish("delete", false, str(r.get("msg", "Couldn't delete your account. Try again in a moment."))); return
			_clear_login()
			if profile:
				_applying = true
				profile.reset()
				if profile.has_method("_push_settings"): profile._push_settings()
				if profile.has_method("save"): profile.save()
				profile.changed.emit()
				_applying = false
			_finish("delete", true, "Account deleted. You're playing as a guest."))

## At start-up (web verifyLogin): is the saved login still good, and is the cloud save newer than this device's copy?
func verify() -> void:
	if not signed_in(): return
	call_api(HTTPClient.METHOD_GET, "/api/me", null, str(getv("token")), func(r: Dictionary) -> void:
		if r.get("err") == "net":
			offline = true
			if dirty: _plan(retry_delay)
			changed.emit(); return
		if int(r.get("status", 0)) == 401: _expire(); return
		if not r["ok"]: return
		if r.get("user") is Dictionary: setv("email", str(r["user"].get("email", "")))
		has_password = bool(r.get("hasPassword", true))
		_merge(r.get("data"), int(r.get("t", 0)))
		changed.emit())

func _set_server(ws_url: String) -> void:
	if ws_url.strip_edges() == "" or not is_inside_tree(): return
	var st := get_tree().root.get_node_or_null("Settings")
	if st: st.set_value("server_url", ws_url.strip_edges())

func _signed_in(r: Dictionary) -> void:
	var u: Variant = r.get("user")
	setv("token", str(r.get("token", "")))
	setv("user", str(u.get("username", "")) if u is Dictionary else str(u))
	setv("email", str(u.get("email", "")) if u is Dictionary else "")
	has_password = bool(u.get("hasPassword", true)) if u is Dictionary else true
	expired = false; stale = false; pending = {}; offline = false

func _clear_login() -> void:
	setv("token", ""); setv("user", ""); setv("email", "")
	setv("cloud_user", ""); dirty = false; t = 0; has_password = true
	stale = false; pending = {}; busy = false; offline = false; _push_in = -1.0

func _auth_failed(r: Dictionary) -> bool:
	if int(r.get("status", 0)) == 401 and r.get("err") == "auth":
		_expire()
		return true
	return false

func _expire() -> void:
	_clear_login()
	expired = true
	changed.emit()

# ============================== cloud sync ==============================

## One line about the cloud save for the Account sheet / the title chip ("" for guests).
func sync_text() -> String:
	if expired: return "Your login ran out. Log in again to save to the cloud."
	if not signed_in(): return ""
	if stale: return "Not saved to the cloud: this account changed on another device."
	if busy: return "Saving…"
	if offline: return "Saved on this device. Cloud save when you're online."
	if dirty: return "Saved on this device. Cloud save in a moment."
	var last := maxf(last_saved, t / 1000.0)
	if last <= 0.0: return "Saved on this device"
	return tr("Saved to cloud %s") % ago(Time.get_unix_time_from_system() - last)

static func ago(s: float) -> String:
	if s < 60.0: return TranslationServer.translate("just now")
	if s < 3600.0: return TranslationServer.translate("%d min ago") % floori(s / 60.0)
	if s < 86400.0: return TranslationServer.translate("%d h ago") % floori(s / 3600.0)
	var d := floori(s / 86400.0)
	return (TranslationServer.translate("%d day ago") if d == 1 else TranslationServer.translate("%d days ago")) % d

## "1,234 coins · 12 matches · 5 outfits" for a blob (the conflict choice).
static func summary(d: Variant) -> String:
	if not (d is Dictionary): return TranslationServer.translate("nothing saved")
	var w: Dictionary = d.get("wallet") if d.get("wallet") is Dictionary else {}
	var s: Dictionary = d.get("stats") if d.get("stats") is Dictionary else {}
	var sk: int = (w["skins"] as Array).size() - 1 if w.get("skins") is Array else 0
	return TranslationServer.translate("%d coins · %d matches · %d K.O.s · %d outfits") % [int(w.get("coins", 0)), int(s.get("matches", 0)), int(s.get("kos", 0)), maxi(0, sk)]

func _on_profile_changed() -> void:
	if _applying or not signed_in() or stale: return
	_mark_dirty(push_delay)

func _mark_dirty(delay: float) -> void:
	dirty = true
	if _push_in < 0.0 or _push_in > delay: _plan(delay)
	changed.emit()

func _plan(delay: float) -> void:
	_push_in = delay

func _process(dt: float) -> void:
	if _push_in < 0.0: return
	_push_in -= dt
	if _push_in <= 0.0:
		_push_in = -1.0
		push()

## Send the profile now (PUT /api/save {data, base}). `cb(ok)` when it is done (also when there is nothing to send).
func push(cb := Callable()) -> void:
	if not signed_in() or stale or expired or busy or not dirty:
		if cb.is_valid(): cb.call(not busy and not stale)
		return
	_push_in = -1.0
	busy = true
	changed.emit()
	call_api(HTTPClient.METHOD_PUT, "/api/save", {"data": profile.get_blob(), "base": t}, str(getv("token")), func(r: Dictionary) -> void:
		busy = false
		var ok := bool(r["ok"])
		if ok:
			t = int(r["t"]); dirty = false; offline = false; last_saved = Time.get_unix_time_from_system()
		elif r.get("err") == "stale":
			_conflict(r.get("data"), int(r.get("t", 0)))
		elif _auth_failed(r):
			pass
		elif r.get("err") == "fast":
			_plan(FAST_RETRY)
		else:
			offline = r.get("err") == "net" or offline
			_plan(retry_delay)
		changed.emit()
		if cb.is_valid(): cb.call(ok))

## Merge the cloud save `data` (time `ct`) with this device after a sign-in.
func _merge(data: Variant, ct: int) -> void:
	var same_user := str(getv("cloud_user")) == user().to_lower() and user() != ""
	setv("cloud_user", user().to_lower())
	if not (data is Dictionary) or profile == null:          # nothing in the cloud yet: this device's profile goes up
		t = ct
		_mark_dirty(0.0)
		return
	if _same(data):
		t = ct; dirty = false; last_saved = Time.get_unix_time_from_system()
		return
	if profile.has_method("is_fresh") and profile.is_fresh():
		_use(data, ct)
		return
	if same_user:
		if ct <= t:                                            # the cloud is what we had: this device is newer
			if dirty: _mark_dirty(0.0)
			return
		if not dirty:                                          # web verifyLogin: the cloud is newer, nothing unsaved here
			_use(data, ct)
			return
	_conflict(data, ct)

## Is `data` the same profile as this device's (after the same cleaning)?
func _same(data: Dictionary) -> bool:
	var tmp: Node = profile.get_script().new()
	tmp.apply_blob(JSON.parse_string(JSON.stringify(data)))
	var a := JSON.stringify(tmp.get_blob())
	tmp.free()
	return a == JSON.stringify(JSON.parse_string(JSON.stringify(profile.get_blob())))

func _conflict(data: Variant, ct: int) -> void:
	stale = true
	_push_in = -1.0
	pending = {"data": data, "t": ct}
	var info := {"local": summary(profile.get_blob()), "cloud": summary(data)}
	changed.emit()
	conflict.emit(info)

## The conflict info for a waiting choice ({} = none).
func conflict_info() -> Dictionary:
	if pending.is_empty(): return {}
	return {"local": summary(profile.get_blob()), "cloud": summary(pending.get("data"))}

## Conflict answer: this device's progress wins (it overwrites the cloud save).
func keep_device() -> void:
	if pending.is_empty(): return
	t = int(pending["t"])
	pending = {}
	stale = false
	dirty = true
	push()

## Conflict answer: the cloud save replaces this device's progress.
func use_cloud() -> void:
	if pending.is_empty(): return
	_use(pending["data"], int(pending["t"]))

func _use(data: Variant, ct: int) -> void:
	pending = {}
	stale = false
	_applying = true
	profile.apply_blob(data)
	if profile.has_method("_push_settings"): profile._push_settings()
	if profile.has_method("save"): profile.save()
	_applying = false
	t = ct; dirty = false; offline = false; _push_in = -1.0
	last_saved = Time.get_unix_time_from_system()
	changed.emit()

## Phones: going to the background sends what is not saved yet (web cloudBeacon).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if signed_in() and dirty: push()
