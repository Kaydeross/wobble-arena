extends Node
## Non-secret launch configuration. A bundled file gives safe defaults immediately; the same host that serves the game
## and account API can replace them over HTTPS. Values are allow-listed by shape before use, and every consumer must keep
## a local fallback when the request fails or returns junk.
##
## The endpoint is /api/config. Remote values only tune policy, news and feature switches; executable DLC is never loaded
## from here.

signal refreshed(ok: bool)

const BUNDLED_PATH := "res://data/extra/remote_config.json"
const TIMEOUT := 8.0
const DEFAULTS := {
	"schema": 1,
	"featured_mode": "classic",
	"news": "",
	"minimum_version": "0.3.0",
	"ads": {
		"enabled": false,
		"interstitial_every_matches": 3,
		"interstitial_min_gap_s": 180,
		"first_session_grace_s": 300,
		"rewarded_enabled": false,
	},
	"kill_switches": {"online": false, "ads": false, "purchases": false},
	"analytics": false,
	"updated": "",
}

var values: Dictionary = DEFAULTS.duplicate(true)
var source := "defaults"
var last_error := ""
var refreshing := false
var _request: HTTPRequest

func _ready() -> void:
	var bundled := read_config(BUNDLED_PATH)
	if not bundled.is_empty():
		values = validate(bundled)
		source = "bundled"
	if DisplayServer.get_name() == "headless": return   # headless tests: no network, and no HTTPRequest/Timer nodes that upset node-count baselines
	refresh.call_deferred()

func get_value(key: String, fallback: Variant = null) -> Variant:
	return values.get(key, DEFAULTS.get(key, fallback))

func ad_value(key: String, fallback: Variant = null) -> Variant:
	var ads: Dictionary = values.get("ads", {})
	var defaults: Dictionary = DEFAULTS["ads"]
	return ads.get(key, defaults.get(key, fallback))

func killed(feature: String) -> bool:
	var switches: Dictionary = values.get("kill_switches", {})
	return bool(switches.get(feature, false))

func refresh() -> void:
	if refreshing or not is_inside_tree():
		return
	var base := _api_base()
	if base == "":
		_finish(false, "No server configured")
		return
	refreshing = true
	_request = HTTPRequest.new()
	_request.timeout = TIMEOUT
	add_child(_request)
	_request.request_completed.connect(_on_request_done)
	var err := _request.request(base + "/api/config")
	if err != OK:
		_request.queue_free()
		_request = null
		_finish(false, "Could not start config request")

func _api_base() -> String:
	var st := get_tree().root.get_node_or_null("Settings") if is_inside_tree() else null
	if st == null:
		return ""
	return AccountApi.http_base(str(st.get_value("server_url")))

func _on_request_done(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	if _request != null:
		_request.queue_free()
		_request = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_finish(false, "Config request failed (%d)" % code)
		return
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		_finish(false, "Config response is not an object")
		return
	var cleaned := validate(parsed)
	values = cleaned
	source = "remote"
	_finish(true, "")

func _finish(ok: bool, error: String) -> void:
	refreshing = false
	last_error = error
	refreshed.emit(ok)

## Returns the complete, bounded configuration dictionary. Unknown keys are discarded. Invalid values fall back, so a
## malformed remote response cannot disable a safety policy or inject arbitrary data into the game.
static func validate(raw: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	out["schema"] = clampi(int(raw.get("schema", 1)), 1, 1)
	var mode := str(raw.get("featured_mode", out["featured_mode"]))
	out["featured_mode"] = mode if mode.length() <= 32 and mode.is_valid_identifier() else DEFAULTS["featured_mode"]
	out["news"] = str(raw.get("news", "")).replace("\n", " ").substr(0, 160)
	out["updated"] = str(raw.get("updated", "")).substr(0, 32)
	out["analytics"] = bool(raw.get("analytics", false))
	var min_version := str(raw.get("minimum_version", DEFAULTS["minimum_version"]))
	out["minimum_version"] = min_version if _version_ok(min_version) else DEFAULTS["minimum_version"]
	var ads: Variant = raw.get("ads")
	if ads is Dictionary:
		var a: Dictionary = out["ads"]
		a["enabled"] = bool(ads.get("enabled", a["enabled"]))
		a["rewarded_enabled"] = bool(ads.get("rewarded_enabled", a["rewarded_enabled"]))
		a["interstitial_every_matches"] = clampi(int(ads.get("interstitial_every_matches", a["interstitial_every_matches"])), 1, 20)
		a["interstitial_min_gap_s"] = clampi(int(ads.get("interstitial_min_gap_s", a["interstitial_min_gap_s"])), 30, 3600)
		a["first_session_grace_s"] = clampi(int(ads.get("first_session_grace_s", a["first_session_grace_s"])), 0, 3600)
		out["ads"] = a
	var kill: Variant = raw.get("kill_switches")
	if kill is Dictionary:
		var k: Dictionary = out["kill_switches"]
		for name: String in ["online", "ads", "purchases"]:
			k[name] = bool(kill.get(name, k[name]))
		out["kill_switches"] = k
	return out

static func _version_ok(v: String) -> bool:
	var parts := v.split(".")
	if parts.size() != 3:
		return false
	for p: String in parts:
		if p == "" or not p.is_valid_int() or int(p) < 0:
			return false
	return true

static func read_config(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}

## Numeric semver comparison for the launch/update notice. A suffix on the running build does not matter.
static func version_less(a: String, b: String) -> bool:
	var aa := a.split(".")
	var bb := b.split(".")
	for i in 3:
		var av := int(aa[i]) if i < aa.size() and aa[i].is_valid_int() else 0
		var bv := int(bb[i]) if i < bb.size() and bb[i].is_valid_int() else 0
		if av != bv:
			return av < bv
	return false

func update_required() -> bool:
	var current := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	return version_less(current, str(values.get("minimum_version", "0.0.0")))
