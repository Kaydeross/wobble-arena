extends Node
## First-party, anonymous usage events (docs/ANALYTICS.md). No third-party SDK, no personal data: a random install id,
## an allow-listed event name and a few small scalar params, posted in batches to this game's own server (POST /api/event).
##
## A no-op unless the remote config switch `analytics` is on AND the player has not turned off "Share anonymous usage
## data" (Settings `analytics_optout`). Kids mode never sends anything. Everything fails silently: a batch is retried once,
## then dropped, and the queue is capped, so analytics can never slow or break the game.

const NAMES := ["install", "session_start", "session_end", "ftue_step", "match_start", "match_end", "coins_spent", "online_join_result", "error"]
const FLUSH_EVERY := 30.0
const FLUSH_AT := 20            ## flush early when this many events are waiting
const QUEUE_MAX := 200
const BATCH_MAX := 50           ## matches the server's per-batch limit
const PARAMS_MAX := 8
const STR_MAX := 64
const ERROR_STR_MAX := 200
const ERRORS_PER_SESSION := 5
const TIMEOUT := 8.0

var queue: Array = []           ## events waiting to be sent: {n, t, p}
var sender: Callable            ## tests: called with the JSON body (String) instead of making a request
var errors_sent := 0
var sessions := 0               ## session_start events tracked since boot
var _inflight: Array = []       ## the batch being sent (kept for the one retry)
var _tries := 0
var _request: HTTPRequest
var _started := false
var _t0 := 0.0                  ## ticks (s) when this session began
var _timer: Timer
var _logger: ErrorLogger
var _seen_errors := {}
var _match := {}                ## the running match: {mode, map, online, t0}

## Collects script errors from any thread; the main thread turns them into `error` events when it flushes.
class ErrorLogger extends Logger:
	var mutex := Mutex.new()
	var pending: Array = []
	var armed := false
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if not armed or error_type != Logger.ERROR_TYPE_SCRIPT or pending.size() >= 20: return
		mutex.lock()
		pending.append({"text": rationale if rationale != "" else code, "at": "%s:%d" % [file.get_file(), line], "fn": function})
		mutex.unlock()
	func take() -> Array:
		mutex.lock()
		var out := pending
		pending = []
		mutex.unlock()
		return out

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Settings.changed.connect(_on_setting)
	RemoteConfig.refreshed.connect(func(_ok: bool) -> void: begin())
	if DisplayServer.get_name() == "headless": return   # headless tests: no timers, no logger, no network
	_timer = Timer.new()
	_timer.wait_time = FLUSH_EVERY
	_timer.autostart = true
	_timer.timeout.connect(flush)
	add_child(_timer)
	_logger = ErrorLogger.new()
	OS.add_logger(_logger)
	begin.call_deferred()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			end_session()
		NOTIFICATION_APPLICATION_RESUMED:
			begin()

## True only when the remote switch is on, the player has not opted out, and it is not Kids mode.
func enabled() -> bool:
	return bool(RemoteConfig.get_value("analytics", false)) and not bool(Settings.get_value("analytics_optout", false)) \
		and not bool(Settings.get_value("kids_mode", false))

## Starts a session: the install id (made once, the first time analytics is allowed), `install` for a new id, `session_start`.
func begin() -> void:
	if _started or not enabled(): return
	_started = true
	_t0 = Time.get_ticks_msec() / 1000.0
	sessions += 1
	if _logger: _logger.armed = true
	if str(Settings.get_value("analytics_iid", "")) == "":
		Settings.set_value("analytics_iid", _new_iid())
		track("install")
	track("session_start")

func end_session() -> void:
	if not _started: return
	_started = false
	track("session_end", {"secs": int(Time.get_ticks_msec() / 1000.0 - _t0)})
	flush()

func _new_iid() -> String:
	var c := Crypto.new().generate_random_bytes(16)
	return c.hex_encode()

func _on_setting(key: String, value: Variant) -> void:
	if key == "analytics_optout" and bool(value):
		queue.clear()
		_inflight = []
		_started = false
		if _logger: _logger.armed = false
	elif key in ["analytics_optout", "kids_mode"]:
		begin()

## Queue one event. Unknown names and every call while analytics is off do nothing.
func track(event: String, params: Dictionary = {}) -> void:
	if not enabled() or not NAMES.has(event): return
	queue.append({"n": event, "t": int(Time.get_unix_time_from_system() * 1000.0), "p": clean_params(params, ERROR_STR_MAX if event == "error" else STR_MAX)})
	if queue.size() > QUEUE_MAX: queue = queue.slice(queue.size() - QUEUE_MAX)
	if queue.size() >= FLUSH_AT: flush()

## Scalars only (bool, int, float, String), snake_case keys, at most 8, strings cut to `str_max` characters.
static func clean_params(p: Dictionary, str_max: int = STR_MAX) -> Dictionary:
	var out := {}
	for k: Variant in p:
		if out.size() >= PARAMS_MAX: break
		var key := str(k)
		if key.length() > 24 or not key.is_valid_identifier() or key != key.to_lower(): continue
		var v: Variant = p[k]
		if v is String or v is StringName: out[key] = str(v).substr(0, str_max)
		elif v is bool or v is int: out[key] = v
		elif v is float and is_finite(v): out[key] = snappedf(v, 0.01)
	return out

## The wire body for one batch (docs/PROTOCOL.md 4.2): nothing but the install id, build tags and the events.
static func batch_body(iid: String, ver: String, plat: String, events: Array) -> Dictionary:
	return {"iid": iid, "ver": ver, "plat": plat, "events": events}

func flush() -> void:
	_drain_errors()
	if not enabled() or not _inflight.is_empty():
		return
	if queue.is_empty(): return
	_inflight = queue.slice(0, BATCH_MAX)
	queue = queue.slice(_inflight.size())
	_tries = 0
	_send()

func _send() -> void:
	var body := JSON.stringify(batch_body(str(Settings.get_value("analytics_iid", "")), str(ProjectSettings.get_setting("application/config/version", "0.0.0")), OS.get_name().to_lower(), _inflight))
	if sender.is_valid():
		sender.call(body)
		_inflight = []
		return
	var base := RemoteConfig.api_base()
	if base == "" or DisplayServer.get_name() == "headless" or not is_inside_tree():
		_inflight = []
		return
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT
	add_child(_request)
	_request.request_completed.connect(_on_done)
	if _request.request(base + "/api/event", PackedStringArray(["content-type: application/json"]), HTTPClient.METHOD_POST, body) != OK:
		_request.queue_free()
		_request = null
		_failed()

func _on_done(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if _request: _request.queue_free()
	_request = null
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		_inflight = []
	elif result == HTTPRequest.RESULT_SUCCESS and code >= 400 and code < 500 and code != 429:
		_inflight = []          # the server refused it: resending the same batch cannot help
	else:
		_failed()

## One retry (on the next flush or when asked again), then the batch is dropped.
func _failed() -> void:
	_tries += 1
	if _tries > 1: _inflight = []
	elif is_inside_tree(): get_tree().create_timer(FLUSH_EVERY).timeout.connect(func() -> void: if not _inflight.is_empty() and _request == null: _send())

## Script errors seen by the logger become `error` events: de-duplicated by place, 5 a session, text cut to 200 characters.
func _drain_errors() -> void:
	if _logger == null: return
	for e: Dictionary in _logger.take():
		if errors_sent >= ERRORS_PER_SESSION: break
		var id := str(e["at"]) + str(e["text"]).substr(0, 40)
		if _seen_errors.has(id): continue
		_seen_errors[id] = true
		errors_sent += 1
		track("error", {"text": str(e["text"]), "at": e["at"]})

## --- Game hooks: one line at each call site ---

## A match began (offline or online). Marks the first one ever as an FTUE step.
func match_started(mode: String, map: String, online: bool) -> void:
	_match = {"mode": mode, "map": map, "online": online, "t0": Time.get_ticks_msec()}
	track("match_start", {"mode": mode, "map": map, "online": online})
	if int(Save.stats.get("matches", 0)) == 0: track("ftue_step", {"step": "first_match_start"})

## The results are showing. `result`: "win" | "loss" | "other".
func match_finished(result: String) -> void:
	if _match.is_empty(): return
	var m := _match
	_match = {}
	track("match_end", {"mode": m["mode"], "map": m["map"], "online": m["online"], "result": result, "secs": (Time.get_ticks_msec() - int(m["t0"])) / 1000})
	if int(Save.stats.get("matches", 0)) <= 1: track("ftue_step", {"step": "first_match_end", "result": result})
