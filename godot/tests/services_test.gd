extends SceneTree
## Launch-service policy: ads never appear during play or before consent, caps are enforced, Remove Ads suppresses
## interstitials while preserving rewarded grants, and local safety filtering/blocking works.

class FakeProvider extends RefCounted:
	var calls: Array = []
	func load(placement: String) -> void: calls.append("load:" + placement)
	func show(placement: String, reward := "") -> void: calls.append("show:" + placement + (":" + reward if reward != "" else ""))
	func purchase(_id: String) -> bool: return true
	func restore() -> bool: return true
	func owned(_id: String) -> bool: return false

var fails := 0
func ok(cond: bool, what: String) -> void:
	if not cond: fails += 1; print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var rc: Node = root.get_node("RemoteConfig")
	var ads: Node = root.get_node("Ads")
	var ent: Node = root.get_node("Entitlements")
	var safety: Node = root.get_node("Safety")
	var st: Node = root.get_node("Settings")   # --script tests have the autoloads as nodes, not as global identifiers
	rc.values = {
		"ads": {"enabled": true, "rewarded_enabled": true, "interstitial_every_matches": 3, "interstitial_min_gap_s": 30, "first_session_grace_s": 0},
		"kill_switches": {"online": false, "ads": false, "purchases": false},
	}
	ent.revoke("remove_ads")
	var fake := FakeProvider.new()
	ads.set_provider(fake)
	ads.in_match = false
	ads.in_online_lobby = false
	ads.on_match_finished(false)
	ads.on_match_finished(false)
	ads.on_match_finished(false)
	st.set_value("ads_last_shown_unix", 0)
	st.set_value("ads_session_start", Time.get_unix_time_from_system() - 1000)
	ok(not ads.can_request("interstitial"), "ads wait until consent is resolved")
	ads.set_consent("declared")
	ok(ads.can_request("interstitial"), "consent and caps allow an interstitial request")
	ads.mark_loaded("interstitial", true)
	ok(ads.show_interstitial(), "an eligible interstitial can show")
	ok(fake.calls.has("show:interstitial"), "the provider receives the show call")
	ads.on_match_started(false)
	ok(not ads.can_request("rewarded"), "no ad can appear during a match")
	ads.on_match_finished(false)
	ads.mark_loaded("rewarded", true)
	ok(ads.show_rewarded("double_coins"), "an eligible rewarded placement can show")
	ent.grant_verified("remove_ads")
	ok(not ads.can_request("interstitial"), "Remove Ads suppresses forced interstitials")
	ok(not ads.show_rewarded("double_coins"), "Remove Ads also skips the rewarded video")
	var rewards := []
	ads.reward_result.connect(func(granted: bool, placement: String) -> void: rewards.append([granted, placement]))
	ads.finish_rewarded("double_coins", false)
	ok(rewards.size() == 1 and rewards[0][0], "Remove Ads grants the reward without a video")
	ads.set_consent("denied")
	ok(not ads.can_request("rewarded"), "declined consent blocks ad requests")

	ok(safety.bad_name("N1gg3r"), "filtered-name leetspeak is recognised")
	ok(safety.display_name("N1gg3r") == "[filtered name]", "a disallowed name is redacted")
	ok(safety.block("Rude_Randy") and safety.display_name("rude_randy") == "Blocked Player", "a local block hides the player")
	ok(safety.unblock("rude_randy"), "a player can be unblocked")
	print("SERVICES ok" if fails == 0 else "SERVICES failed (%d)" % fails)
	quit(0 if fails == 0 else 1)
