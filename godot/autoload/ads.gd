extends Node
## Provider-neutral ad policy. The App Store SDK is deliberately behind `set_provider`; this layer owns all decisions
## about whether an ad may appear. A provider must report completion explicitly. No ad is shown during a match, in an
## online lobby, before consent is resolved, or when remote config disables ads.

signal reward_result(granted: bool, placement: String)
signal interstitial_finished(shown: bool)

const INTERSTITIAL := "interstitial"
const REWARDED := "rewarded"
const SESSION_START := "session_start"
const MATCHES_SINCE := "ads_matches_since"
const LAST_SHOWN := "ads_last_shown_unix"

var in_match := false
var in_online_lobby := false
var safety_timeout_s := 60.0      ## a provider that never calls finish_* must not leave the game paused / silent
var _provider: Object
var _consent := "unknown"         # unknown | declared | denied | nonpersonal
var _loaded := {INTERSTITIAL: false, REWARDED: false}
var _ad_active := false
var _was_paused := false
var _ad_mutes := {}               ## AudioServer bus index -> whether it was muted before the ad
var _placement := ""              ## the rewarded placement on screen ("" for an interstitial): reported on a timeout

func _ready() -> void:
	# Only the safety Timer below opts into PROCESS_MODE_ALWAYS; this node needs no processing of its own, paused or not.
	if int(Settings.get_value(SESSION_START, 0)) <= 0:
		Settings.set_value(SESSION_START, Time.get_unix_time_from_system())

func has_provider() -> bool:
	return _provider != null

func set_provider(provider: Object) -> void:
	_provider = provider

func set_consent(state: String) -> void:
	_consent = state if state in ["unknown", "declared", "denied", "nonpersonal"] else "unknown"

func consent_ready() -> bool:
	return _consent == "declared" or _consent == "nonpersonal" or _consent == "denied"

func can_request(placement: String) -> bool:
	if placement not in [INTERSTITIAL, REWARDED] or _provider == null:
		return false
	if _ad_active:                                           # one fullscreen ad at a time: no nested show can cut the pause short
		return false
	if bool(Settings.get_value("kids_mode", false)):         # Kids mode never shows or triggers any ad
		return false
	if RemoteConfig.killed("ads") or not bool(RemoteConfig.ad_value("enabled", false)):
		return false
	if placement == REWARDED and not bool(RemoteConfig.ad_value("rewarded_enabled", false)):
		return false
	if in_match or in_online_lobby or not consent_ready() or _consent == "denied":
		return false
	if placement == INTERSTITIAL and Entitlements.remove_ads():
		return false
	return true

func can_show(placement: String) -> bool:
	if not can_request(placement):
		return false
	if not bool(_loaded.get(placement, false)):
		return false
	if placement == REWARDED:
		return true
	var now := int(Time.get_unix_time_from_system())
	var start := int(Settings.get_value(SESSION_START, now))
	if now - start < int(RemoteConfig.ad_value("first_session_grace_s", 300)):
		return false
	var gap := int(RemoteConfig.ad_value("interstitial_min_gap_s", 180))
	if now - int(Settings.get_value(LAST_SHOWN, 0)) < gap:
		return false
	var since := int(Settings.get_value(MATCHES_SINCE, 0))
	return since >= int(RemoteConfig.ad_value("interstitial_every_matches", 3))

func request_load(placement: String) -> bool:
	if not can_request(placement) or _provider == null or not _provider.has_method("load"):
		return false
	_loaded[placement] = false
	_provider.call("load", placement)
	return true

func mark_loaded(placement: String, ok: bool) -> void:
	if _loaded.has(placement):
		_loaded[placement] = ok

## Returns whether the provider accepted the show request. Completion arrives through finish_*.
func show_interstitial() -> bool:
	if not can_show(INTERSTITIAL) or _provider == null or not _provider.has_method("show"):
		return false
	_placement = ""
	_loaded[INTERSTITIAL] = false
	_begin_ad()
	if not _accepted(_provider.call("show", INTERSTITIAL)):
		_end_ad()
		return false
	# Only an accepted show spends the gap and the every-N-matches counter: a refused one must not burn them.
	Settings.set_value(LAST_SHOWN, Time.get_unix_time_from_system())
	Settings.set_value(MATCHES_SINCE, 0)
	return true

func show_rewarded(placement: String) -> bool:
	if not can_show(REWARDED) or _provider == null or not _provider.has_method("show"):
		return false
	_placement = placement
	_loaded[REWARDED] = false
	_begin_ad()
	if not _accepted(_provider.call("show", REWARDED, placement)):
		_end_ad()
		return false
	return true

## A fullscreen ad (or a rewarded video) is on screen: freeze the world and silence the game. Restored by finish_* or,
## when a provider never calls back, by safety_timeout_s. The UI only ever shows an ad through can_show().
func _begin_ad() -> void:
	if _ad_active:
		return
	_ad_active = true
	_was_paused = get_tree().paused
	get_tree().paused = true
	_ad_mutes.clear()
	for bus_name: String in ["SFX", "Music"]:
		var i := AudioServer.get_bus_index(bus_name)
		if i < 0: continue
		_ad_mutes[i] = AudioServer.is_bus_mute(i)
		AudioServer.set_bus_mute(i, true)
	var timer := _safety_timer()
	if timer != null:
		timer.start(maxf(0.05, safety_timeout_s))

func _end_ad() -> void:
	if not _ad_active:
		return
	_ad_active = false
	_placement = ""
	var timer := get_node_or_null("AdSafety") as Timer
	if timer != null: timer.stop()
	for i: int in _ad_mutes:
		AudioServer.set_bus_mute(i, bool(_ad_mutes[i]))
	_ad_mutes.clear()
	# Restore the pause state even if a scene change happened under the ad: the tree outlives the requesting node.
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.paused = _was_paused

## Created on first use: the Timer runs while the tree is paused.
func _safety_timer() -> Timer:
	var t := get_node_or_null("AdSafety") as Timer
	if t == null:
		t = Timer.new()
		t.name = "AdSafety"
		t.one_shot = true
		t.process_mode = Node.PROCESS_MODE_ALWAYS
		t.timeout.connect(_on_ad_timeout)
		add_child(t)
	return t

## No completion arrived: restore the game and let the placement's requester hear "not granted", so its button does not
## stay disabled. A late finish_* still emits its result and is idempotent here.
func _on_ad_timeout() -> void:
	var placement := _placement
	_end_ad()
	if placement != "":
		reward_result.emit(false, placement)

## A provider's show/purchase may return nothing (void) or an explicit bool. Only `false` means refused.
static func _accepted(v: Variant) -> bool:
	return v != false

func finish_interstitial(shown: bool) -> void:
	_end_ad()
	interstitial_finished.emit(shown)

## The provider contract: granted only after a verified user-earned reward. Remove Ads grants the bonus without a view.
func finish_rewarded(placement: String, granted: bool) -> void:
	_end_ad()
	reward_result.emit(granted or Entitlements.remove_ads(), placement)

func on_match_started(online: bool) -> void:
	in_match = true
	in_online_lobby = online

func on_match_finished(online: bool) -> void:
	in_match = false
	if online or Entitlements.remove_ads():
		in_online_lobby = false
		return
	Settings.set_value(MATCHES_SINCE, int(Settings.get_value(MATCHES_SINCE, 0)) + 1)
	in_online_lobby = false

## An offline Arcade attempt ended on its failed card. The run no longer blocks an ad, but this is not a finished match:
## the interstitial frequency counter must not move. A retry re-enters through on_match_started().
func on_attempt_ended() -> void:
	in_match = false

func on_lobby_entered(online: bool) -> void:
	in_match = false
	in_online_lobby = online
