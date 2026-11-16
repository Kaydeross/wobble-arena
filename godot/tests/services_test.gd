extends SceneTree
## Launch-service policy: ads never appear during play or before consent, caps are enforced, Remove Ads suppresses
## interstitials while preserving rewarded grants, and local safety filtering/blocking works.

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
	var fake = load("res://tests/fake_ads_provider.gd").new()
	fake.finish = false
	ads.set_provider(fake)
	ads.in_match = false
	ads.in_online_lobby = false
	ads.on_match_finished(false)
	ads.on_match_finished(false)
	ads.on_match_finished(false)
	st.set_value("ads_last_shown_unix", 0)
	st.set_value("session_start", Time.get_unix_time_from_system() - 1000)
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
	await _monetization(rc, ads, ent, st)
	print("SERVICES ok" if fails == 0 else "SERVICES failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

## The provider-neutral monetization policy: nothing is visible without a provider; a mock lights every placement up;
## Remove ads / store rows follow the purchases kill switch; kids mode hides it all; the 60 s guard restores pause and
## audio. The reward payouts and the screen buttons are exercised in locker_test / quests_test (which can load the UI).
func _monetization(rc: Node, ads: Node, ent: Node, st: Node) -> void:
	rc.values = {
		"ads": {"enabled": true, "rewarded_enabled": true, "interstitial_every_matches": 3, "interstitial_min_gap_s": 30, "first_session_grace_s": 300},
		"kill_switches": {"online": false, "ads": false, "purchases": false},
	}
	st.set_value("kids_mode", false)
	ent.revoke("remove_ads")
	ads.set_consent("declared")
	ads.in_match = false
	ads.in_online_lobby = false
	ads.safety_timeout_s = 60.0

	# -- no provider: every monetization control stays away --
	ads.set_provider(null)
	ent.set_provider(null)
	ok(not ads.has_provider() and not ent.has_provider(), "no provider registered")
	ok(not AdUi.rewarded_visible(AdUi.DOUBLE_COINS), "no provider: the Double coins button is hidden")
	ok(not AdUi.rewarded_visible(AdUi.DAILY_BONUS), "no provider: the 2x daily bonus button is hidden")
	ok(not AdUi.rewarded_visible(AdUi.ARCADE_CONTINUE), "no provider: the Arcade continue button is hidden")
	ok(not AdUi.purchases_visible(), "no provider: Remove ads / Restore purchases are hidden")

	# -- a provider: the same tests light up, and the mock advertisement completes --
	var mock = load("res://tests/fake_ads_provider.gd").new()
	mock.ads = ads
	ads.set_provider(mock)
	ent.set_provider(load("res://tests/fake_store_provider.gd").new())
	st.set_value(AdUi.DAILY_BONUS_DAY, -1)
	ok(ads.has_provider() and ent.has_provider(), "a provider is registered")
	ok(AdUi.rewarded_visible(AdUi.DOUBLE_COINS) and AdUi.rewarded_visible(AdUi.DAILY_BONUS) and AdUi.rewarded_visible(AdUi.ARCADE_CONTINUE), "with a provider, ads on and consent: every rewarded placement is visible")
	ok(AdUi.purchases_visible(), "with a StoreKit provider: Remove ads / Restore purchases are visible")
	rc.values["kill_switches"]["purchases"] = true
	ok(not AdUi.purchases_visible(), "the purchases kill switch hides the store rows")
	rc.values["kill_switches"]["purchases"] = false
	ok(AdUi.purchases_visible(), "the store rows come back when the kill switch is off")

	# -- kids mode hides every placement and the store rows --
	st.set_value("kids_mode", true)
	ok(not AdUi.rewarded_visible(AdUi.DOUBLE_COINS) and not AdUi.rewarded_visible(AdUi.DAILY_BONUS) and not AdUi.rewarded_visible(AdUi.ARCADE_CONTINUE), "kids mode hides every rewarded placement")
	ok(not AdUi.purchases_visible(), "kids mode hides Remove ads / Restore purchases")
	st.set_value("kids_mode", false)

	# -- remote flags: ads off keeps everything hidden; rewarded off hides the rewarded placements only --
	rc.values["ads"]["enabled"] = false
	ok(not AdUi.rewarded_visible(AdUi.DOUBLE_COINS), "ads.enabled false keeps every rewarded placement hidden")
	rc.values["ads"]["enabled"] = true
	rc.values["ads"]["rewarded_enabled"] = false
	ok(not AdUi.rewarded_visible(AdUi.DOUBLE_COINS), "rewarded_enabled false hides the rewarded placements")
	rc.values["ads"]["rewarded_enabled"] = true
	ok(AdUi.rewarded_visible(AdUi.DOUBLE_COINS), "both ad flags true bring them back")

	# -- interstitial: first session and in-match are not eligible; the title exit is offline-only --
	st.set_value("session_start", Time.get_unix_time_from_system())
	st.set_value("ads_matches_since", 3)
	st.set_value("ads_last_shown_unix", 0)
	ads.mark_loaded("interstitial", true)
	ok(not ads.can_show("interstitial"), "no interstitial in the first session")
	st.set_value("session_start", Time.get_unix_time_from_system() - 1000)
	ok(ads.can_show("interstitial"), "after the first-session grace an interstitial is eligible")
	ads.on_match_started(false)
	ok(not ads.can_show("interstitial"), "no interstitial during a match")
	ads.on_match_finished(false)
	var world_script = load("res://world/world.gd")
	ok(not world_script.exit_interstitial_allowed(true, false), "no exit interstitial when leaving an online room")
	ok(not world_script.exit_interstitial_allowed(false, true), "no exit interstitial for the tutorial")
	ok(world_script.exit_interstitial_allowed(false, false), "an offline title exit may offer the interstitial")
	# a rematch never goes through the title exit at all: load_map keeps the World, so _exit_tree never runs.

	# -- a provider that never calls back: the 60 s guard restores pause and audio --
	var silent = load("res://tests/fake_ads_provider.gd").new()
	silent.ads = ads
	silent.finish = false
	ads.set_provider(silent)
	ads.safety_timeout_s = 0.05
	ads.mark_loaded("rewarded", true)
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var music_bus := AudioServer.get_bus_index("Music")
	var paused_before := paused
	ok(ads.show_rewarded("double_coins"), "a silent provider accepts the show")
	ok(paused, "the world is paused while the ad is up")
	ok(sfx_bus < 0 or AudioServer.is_bus_mute(sfx_bus), "sound effects are muted while the ad is up")
	ok(music_bus < 0 or AudioServer.is_bus_mute(music_bus), "music is muted while the ad is up")
	await create_timer(0.2).timeout
	ok(paused == paused_before, "the safety timeout restores the pause state")
	ok(sfx_bus < 0 or not AudioServer.is_bus_mute(sfx_bus), "the safety timeout unmutes sound effects")
	ok(music_bus < 0 or not AudioServer.is_bus_mute(music_bus), "the safety timeout unmutes music")
	ads.safety_timeout_s = 60.0

	# -- reset for the suites that follow --
	ads.set_provider(null)
	ent.set_provider(null)
	ent.revoke("remove_ads")
	st.set_value("kids_mode", false)
	st.set_value(AdUi.DAILY_BONUS_DAY, -1)
