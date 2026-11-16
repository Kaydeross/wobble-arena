extends SceneTree
## Analytics policy (headless): a no-op unless the remote flag is on and the player has not opted out, bounded queue,
## batch shape and the event-name allow-list. No network: `sender` captures the JSON body.
##   godot --headless --path godot --script res://tests/analytics_test.gd -- --no-save   (npm run test:godot-analytics)

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var an: Node = root.get_node("Analytics")
	var rc: Node = root.get_node("RemoteConfig")
	var st: Node = root.get_node("Settings")
	var bodies: Array = []
	an.sender = func(body: String) -> void: bodies.append(JSON.parse_string(body))
	st.set_value("kids_mode", false)

	# off by default: the shipped remote flag is false
	check(not an.enabled(), "disabled by the default remote config")
	an.track("match_start", {"mode": "classic"})
	an.begin()
	check(an.queue.is_empty(), "flag off: track() and begin() queue nothing")
	check(str(st.get_value("analytics_iid", "")) == "", "flag off: no install id is made")

	# flag on, opted out
	rc.values["analytics"] = true
	st.set_value("analytics_optout", true)
	check(not an.enabled(), "opted out is disabled even when the flag is on")
	an.track("match_start")
	an.begin()
	check(an.queue.is_empty() and str(st.get_value("analytics_iid", "")) == "", "opted out: nothing queued, no install id")

	# kids mode never sends
	st.set_value("analytics_optout", false)
	check(an.queue.is_empty() or an.enabled(), "opting back in is allowed")
	an.queue.clear()
	an._started = false
	st.set_value("kids_mode", true)
	check(not an.enabled(), "Kids mode is disabled")
	an.track("match_start")
	check(an.queue.is_empty(), "Kids mode: nothing queued")
	check(st.DEFAULTS.get("analytics_optout", true) == false, "analytics_optout defaults to false (toggle on)")
	st.set_value("analytics_iid", "")
	st.set_value("kids_mode", false)    # leaving Kids mode starts the session: install id, install, session_start
	check(an.enabled(), "flag on, not opted out, not Kids mode: enabled")
	var iid := str(st.get_value("analytics_iid", ""))
	check(iid.length() == 32 and iid.is_valid_hex_number(false), "a 32-hex random install id is made")
	check(an.queue.size() == 2 and an.queue[0]["n"] == "install" and an.queue[1]["n"] == "session_start", "first run queues install then session_start")
	an.begin()
	check(an.queue.size() == 2, "begin() twice in one session does nothing")
	an._started = false
	an.queue.clear()
	an.begin()
	check(an.queue.size() == 1 and an.queue[0]["n"] == "session_start" and str(st.get_value("analytics_iid", "")) == iid, "later sessions: session_start only, same id")

	# whitelist
	an.queue.clear()
	an.track("purchase_card_number")
	an.track("")
	check(an.queue.is_empty(), "names off the allow-list are dropped")

	# params: scalars only, bounded
	var p: Dictionary = an.clean_params({"mode": "x".repeat(200), "ok": true, "n": 3, "f": 1.23456, "Bad": 1, "arr": [1], "d": {"a": 1}, "bad key": 1})
	check(str(p["mode"]).length() == 64 and p["ok"] == true and p["n"] == 3 and is_equal_approx(float(p["f"]), 1.23), "scalars kept and cut")
	check(not p.has("Bad") and not p.has("arr") and not p.has("d") and not p.has("bad key"), "non-scalar and badly named params are dropped")
	var many := {}
	for i in 20: many["k%d" % i] = i
	check(an.clean_params(many).size() == 8, "at most 8 params")
	an.track("error", {"text": "y".repeat(500)})
	check(str(an.queue[0]["p"]["text"]).length() == 200, "error text is cut to 200")

	# batch shape and flush
	an.queue.clear()
	an.track("match_start", {"mode": "classic", "map": "arena", "online": false})
	an.flush()
	check(bodies.size() == 1 and an.queue.is_empty(), "flush sends the queue")
	var b: Dictionary = bodies[0]
	check(b.keys().size() == 4 and b.has("iid") and b.has("ver") and b.has("plat") and b.has("events"), "batch has exactly iid, ver, plat, events")
	check(b["iid"] == iid and str(b["ver"]) != "" and str(b["plat"]) != "", "batch carries the install id, version and platform")
	var ev: Dictionary = b["events"][0]
	check(ev.keys().size() == 3 and ev["n"] == "match_start" and ev["t"] > 1000000000000 and ev["p"]["map"] == "arena", "event has n, t, p")
	check(not ("name" in b or "user" in b or "token" in b or "email" in b), "no account fields in a batch")

	# flush early at 20, and the queue cap
	bodies.clear()
	for i in 19: an.track("session_start")
	check(bodies.is_empty() and an.queue.size() == 19, "19 events wait")
	an.track("session_start")
	check(bodies.size() == 1 and (bodies[0]["events"] as Array).size() == 20 and an.queue.is_empty(), "the 20th event flushes")
	an.sender = Callable()
	an._inflight = [{"n": "install", "t": 1, "p": {}}]   # a batch in flight blocks sending, so the queue can fill
	for i in 260: an.track("session_start")
	check(an.queue.size() == 200, "the queue is capped at 200 (oldest dropped)")
	an._inflight = []

	# the one retry
	an.queue.clear()
	an._inflight = [{"n": "install", "t": 1, "p": {}}]
	an._tries = 0
	an._failed()
	check(not an._inflight.is_empty(), "first failure keeps the batch for one retry")
	an._failed()
	check(an._inflight.is_empty(), "the second failure drops it")

	# opting out clears what is waiting
	an.track("install")
	st.set_value("analytics_optout", true)
	check(an.queue.is_empty(), "opting out clears the queue")
	st.set_value("analytics_optout", false)

	print("ANALYTICS ok" if fails == 0 else "ANALYTICS FAILED %d" % fails)
	quit(1 if fails > 0 else 0)
