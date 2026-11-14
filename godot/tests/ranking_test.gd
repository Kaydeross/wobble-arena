extends SceneTree
## Server identity + leaderboard client test (run by tools/test-ranking.js; the live part needs that runner's server):
##   godot --headless --path godot --script res://tests/ranking_test.gd -- --no-save [--api=URL --token=TOK --old=URL --oldjson=URL]
## Checks: ServerInfo classification for the Official / Local / Custom URLs (with host, colour and the wrong-server hint),
## the ServerBadge chip; the RankingSheet's states (loading, rows, empty, error, unsupported-404, offline) with their
## copy and actions (Retry), the "you" record below the top N (out-of-table pill, estimated marker) and the in-table
## highlight, the sign-in / not-on-the-board hints, the board tabs and the remembered board, the Sync button's
## disabled/explained cases, AccountApi.rank_failure's classification, the one career-totals helper (rank_stats) and the
## guards that stop a Kids-mode or signed-out submit before it reaches the network.
## With --api= it also runs the end-to-end part against the real server tools/test-ranking.js started: sign-in read,
## client-side Sync (POST /api/rank), and the unsupported/offline states against fake old/unreachable servers.

var fails := 0

func check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok: fails += 1

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _until(cond: Callable, secs := 6.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > secs * 1000.0: return false
		await process_frame
	return true

## Every label text inside the table rows, for "name / score / (you)" checks.
func _row_text(sheet: RankingSheet) -> String:
	var texts: Array = []
	for r in sheet.rows.get_children():
		for n in r.find_children("*", "Label", true, false): texts.append((n as Label).text)
	return " | ".join(texts)

func _run() -> void:
	var settings: Node = root.get_node("Settings")
	var save: Node = root.get_node("Save")
	var cloud: AccountApi = save.cloud
	settings.set_value("kids_mode", false)

	# ---------------- ServerInfo: the shipped URL is Official, private hosts are Local, everything else Custom
	var shipped := ServerInfo.shipped_url()
	check(shipped != "", "the shipped server URL is readable from %s" % ServerInfo.SERVER_CONFIG_PATH)
	var official := ServerInfo.classify(shipped)
	check(official.kind == ServerInfo.OFFICIAL and str(official.label).contains("Official") and official.official, "the shipped URL is Official (%s)" % official.label)
	check(official.host == ServerInfo.host_of(shipped) and official.host != "", "Official host = %s" % official.host)
	check((official.color as Color).g > (official.color as Color).r, "Official has a colour")
	var no_path := ServerInfo.classify(shipped.trim_suffix("/ws"))
	check(no_path.kind == ServerInfo.OFFICIAL, "the same server without the /ws path is still Official")
	var locales := {
		"ws://127.0.0.1:3000/ws": "127.0.0.1:3000",
		"ws://localhost:3000/ws": "localhost:3000",
		"ws://192.168.1.20:3000/ws": "192.168.1.20:3000",
		"ws://10.0.0.5:3000/ws": "10.0.0.5:3000",
		"ws://172.20.0.9:3000/ws": "172.20.0.9:3000",
		"ws://100.101.102.103:3000/ws": "100.101.102.103:3000",
		"ws://dev-pc.local:3000/ws": "dev-pc.local:3000",
		"ws://node.tailcc5a5.ts.net/ws": "node.tailcc5a5.ts.net",
	}
	for u: String in locales:
		var i := ServerInfo.classify(u)
		check(i.kind == ServerInfo.LOCAL, "%s is Local" % u)
		check(i.host == locales[u], "%s host = %s" % [u, i.host])
	for u: String in ["wss://play.example.com/ws", "ws://192.0.2.10:3000/ws", "wss://arena.example.net:8443/ws"]:
		check(ServerInfo.classify(u).kind == ServerInfo.CUSTOM, "%s is Custom" % u)
	check(ServerInfo.classify("nonsense").kind == ServerInfo.CUSTOM, "a URL with no host is Custom (never guessed Official)")
	check(not ServerInfo.is_local("wss://play.example.com/ws"), "a public host is not Local")
	check(ServerInfo.classify("").kind == ServerInfo.current().kind, "classify(\"\") classifies the current server")
	# the wrong-server hint: only when the two servers differ
	check(ServerInfo.mismatch_hint("") == "", "no hint when there is nothing to compare")
	check(ServerInfo.mismatch_hint(shipped, shipped) == "", "no hint for the same server")
	check(ServerInfo.mismatch_hint("ws://127.0.0.1:3000/ws", shipped) != "", "a hint when the room is Local but this device is Official")
	check(ServerInfo.mismatch_hint(shipped, "ws://127.0.0.1:3000/ws") != "", "a hint when the room is Official but this device is Local")
	var hint := ServerInfo.mismatch_hint("wss://play.example.com/ws", "ws://127.0.0.1:3000/ws")
	check(hint.contains("play.example.com") and hint.contains("127.0.0.1:3000") and hint.contains("same server"), "the hint names both hosts: " + hint)

	# Settings.server_url drives current()/classify("")
	settings.set_value("server_url", "ws://127.0.0.1:3000/ws")
	check(ServerInfo.current().kind == ServerInfo.LOCAL, "current() reads Settings.server_url (Local)")
	settings.set_value("server_url", "wss://play.example.com/ws")
	check(ServerInfo.current().kind == ServerInfo.CUSTOM, "current() follows a custom URL")
	settings.set_value("server_url", shipped)
	check(ServerInfo.current().kind == ServerInfo.OFFICIAL, "current() follows the shipped URL")
	settings.set_value("server_url", "")

	# ---------------- ServerBadge chip
	var badge := ServerBadge.new()
	root.add_child(badge)
	badge.setup("ws://127.0.0.1:3000/ws")
	check(badge.text().contains("Local") and badge.text().contains("127.0.0.1:3000"), "badge text: " + badge.text())
	check(badge.host() == "127.0.0.1:3000" and badge.tooltip_text == "ws://127.0.0.1:3000/ws", "badge tooltip is the full URL")
	badge.setup(shipped)
	check(badge.kind() == ServerInfo.OFFICIAL and badge.text().contains("Official"), "badge follows the URL: " + badge.text())
	badge.setup("wss://play.example.com/ws")
	check(badge.text().contains("Custom"), "custom badge: " + badge.text())

	# ---------------- RankingSheet: build, rows, tabs, loading
	var sheet := RankingSheet.new()
	root.add_child(sheet)
	sheet.open("kos", false)
	check(sheet.visible and sheet.state == "loading", "the sheet opens in the loading state")
	check(sheet.status_l.text.contains("Loading"), "the loading state says so: " + sheet.status_l.text)
	check(not sheet.retry_b.visible, "the loading state has no Retry")
	check(sheet.badge != null and sheet.badge.text() != "", "the header carries the ServerInfo badge: " + (sheet.badge.text() if sheet.badge else ""))
	var hd: Control = sheet.get_node("Center/Card/Box/Head")
	print("HEADMIN ", hd.get_combined_minimum_size(), " badge ", sheet.badge.get_combined_minimum_size(), " title ", sheet.title_l.get_combined_minimum_size(), " host ", sheet.host_l.get_combined_minimum_size(), " card ", sheet.card.get_combined_minimum_size())
	check(sheet.host_l.text.contains(ServerInfo.current().host), "the header names the server host")
	sheet.show_entries([
		{"rank": 1, "name": "Wobble_Wanda", "score": 128, "updated": Time.get_unix_time_from_system() * 1000.0 - 120000},
		{"rank": 2, "name": "GodotGuest", "score": 90, "updated": Time.get_unix_time_from_system() * 1000.0 - 3600000},
		{"rank": 3, "name": "Kid_Carl", "score": 12, "updated": 0},
	])
	check(sheet.state == "rows" and sheet.row_count() == 3, "three mock rows build (%d)" % sheet.row_count())
	var joined := _row_text(sheet)
	check(joined.contains("Wobble_Wanda") and joined.contains("128"), "the rows show name and score: " + joined)
	check(joined.contains("2 min ago") or joined.contains("1 h ago"), "the rows show when the score was set: " + joined)
	check(not sheet.you_box.visible or sheet.hint_text() != "", "signed out: the sheet asks for a sign-in instead of a own row")
	check(sheet.hint_text().contains("Sign in on the Account screen"), "signed out copy: " + sheet.hint_text())
	check(sheet.sign_in_b.visible and sheet.sync_b.disabled, "signed out: Sign in shown, Sync disabled")
	check(sheet.sync_msg_l.text.contains("Sign in"), "signed out: Sync explains why it is off: " + sheet.sync_msg_l.text)
	sheet.open("wins", false)
	check(sheet.board == "wins" and (sheet.tabs["wins"] as Button).button_pressed, "the board tabs switch")
	sheet.open("arcade", false)
	check(sheet.board == "arcade" and (sheet.tabs["arcade"] as Button).button_pressed and not (sheet.tabs["kos"] as Button).button_pressed, "Arcade tab is the only pressed one")
	sheet.open("kos", false)

	# ---------------- "you": below the top N (pill), in the table (highlight), or not on the board yet
	cloud.setv("token", "test-token")
	cloud.setv("user", "Tester")
	sheet.show_entries([
		{"rank": 1, "name": "Wobble_Wanda", "score": 128},
		{"rank": 2, "name": "GodotGuest", "score": 90},
		{"rank": 3, "name": "Kid_Carl", "score": 12},
	], {"you": {"rank": 12, "score": 340, "estimated": true}})
	check(sheet.you_l.visible and not sheet.you_hint_l.visible, "a signed-in player outside the top N gets a row below the table")
	var yt := sheet.you_text()
	check(yt.contains("#12") and yt.contains("340") and yt.contains("K.O.s"), "the own row shows rank and score: " + yt)
	check(yt.contains("estimated"), "an estimated position is marked: " + yt)
	check(not sheet.sync_b.disabled, "signed in: Sync is enabled")
	sheet.show_entries([
		{"rank": 1, "name": "Wobble_Wanda", "score": 128},
		{"rank": 2, "name": "Tester", "score": 90},
		{"rank": 3, "name": "Kid_Carl", "score": 12},
	], {"you": {"rank": 2, "score": 90}})
	joined = _row_text(sheet)
	check(joined.contains("(you)") and joined.contains("Tester"), "the in-table own row is highlighted: " + joined)
	check(not sheet.you_l.visible, "no duplicate pill when the own row is already in the table")
	sheet.you = {"rank": 1, "score": 0, "estimated": true}      # a signed-in player with no score on this board
	sheet.show_empty()
	check(sheet.state == "empty" and sheet.row_count() == 0, "the empty state clears the rows")
	check(sheet.status_l.text.contains("No scores on K.O.s"), "the empty state names the board: " + sheet.status_l.text)
	check(sheet.status_l.text.contains("play a match while signed in"), "the empty state invites the first score: " + sheet.status_l.text)
	check(sheet.hint_text().contains("not on the K.O.s board yet"), "signed in, no score: says so: " + sheet.hint_text())
	check(not sheet.sync_b.disabled, "signed in, no score: Sync is offered")

	# ---------------- failure states: unsupported (old server), offline, error + Retry
	check(AccountApi.rank_failure({"ok": false, "status": 404, "err": "none", "json": true}).kind == "unsupported", "a JSON 404 is classified as an old server")
	check(AccountApi.rank_failure({"ok": false, "status": 404, "err": "none", "json": false, "text": "not found"}).kind == "unsupported", "a plain-text 404 is classified as an old server")
	check(AccountApi.rank_failure({"ok": false, "status": 0, "err": "net", "json": false}).kind == "offline", "no network is classified offline")
	check(AccountApi.rank_failure({"ok": false, "status": 401, "err": "auth", "json": true}).kind == "auth", "a 401 asks for a sign-in")
	check(AccountApi.rank_failure({"ok": false, "status": 500, "err": "server", "json": true}).kind == "error", "a 500 is a plain error")
	sheet.show_failure({"ok": false, "status": 404, "err": "none", "msg": "Not found.", "json": true})
	check(sheet.state == "unsupported", "a 404 from an old server is the unsupported state")
	check(sheet.status_l.text.contains("older build") and sheet.status_l.text.contains("Update the server"), "the unsupported state explains the old server: " + sheet.status_l.text)
	check(not sheet.status_l.text.contains("Not found"), "the raw server text is never shown")
	check(sheet.retry_b.visible, "the unsupported state offers Retry")
	sheet.show_failure({"ok": false, "status": 404, "err": "none", "json": false, "text": "not found"})
	check(sheet.state == "unsupported" and sheet.status_l.text.contains("older build"), "a plain-text 404 lands in the same state without the raw text")
	sheet.show_offline()
	check(sheet.state == "offline" and sheet.status_l.text.contains("reach"), "the offline state says the server can't be reached: " + sheet.status_l.text)
	check(sheet.retry_b.visible, "the offline state offers Retry")
	sheet.show_failure({"ok": false, "status": 500, "err": "server", "msg": "The server had a problem.", "json": true})
	check(sheet.state == "error" and sheet.status_l.text.contains("problem"), "a real error shows the server's plain message")
	check(sheet.retry_b.visible and sheet.retry_b.text == "Retry", "the error state offers Retry")
	sheet.show_error("Couldn't reach the server.")
	check(sheet.state == "error" and sheet.status_l.text.contains("reach"), "show_error still shows a caller message")

	# the tabs stay usable and the selected board is remembered through an error + Retry
	cloud.base_override = "http://127.0.0.1:9"
	sheet._pick("wins")
	check(sheet.board == "wins" and sheet.state == "loading", "switching tabs starts a load for that board")
	var went_offline: bool = await _until(func() -> bool: return sheet.state == "offline", 8.0)
	check(went_offline, "an unreachable server is the offline state (%s)" % sheet.state)
	check(sheet.board == "wins" and (sheet.tabs["wins"] as Button).button_pressed, "the selected board survives the failure")
	sheet.retry_b.pressed.emit()
	check(sheet.state == "loading", "Retry fetches again")
	await _until(func() -> bool: return sheet.state == "offline", 8.0)
	cloud.base_override = ""

	# ---------------- the one career-totals helper (auto-submit and Sync use it)
	save.stats["kos"] = 7
	save.stats["wins"] = 3
	save.stats["matches"] = 5
	var dlc: Dictionary = save.dlc
	var best: Dictionary = dlc["arcade_best"]
	best["easy"] = 1
	best["normal"] = 2
	best["nightmare"] = 2
	var st := AccountApi.rank_stats(save)
	check(int(st.get("kos", 0)) == 7 and int(st.get("wins", 0)) == 3 and int(st.get("matches", 0)) == 5, "rank_stats sends the career totals: " + JSON.stringify(st))
	check(int(st.get("arcade_best", 0)) == 2 and str(st.get("arcade_diff", "")) == "nightmare", "rank_stats weights the Arcade best like the server: " + JSON.stringify(st))
	check(AccountApi.rank_stats(null).is_empty(), "rank_stats is safe without a profile")
	check(AccountApi.rank_arcade_best(save).get("arcade_diff", "") == "nightmare", "rank_arcade_best picks the weighted difficulty")

	# ---------------- Kids mode: no submission, and the sheet says so
	settings.set_value("kids_mode", true)
	check(AccountApi.kids_mode(), "Settings kids_mode is read")
	check(not AccountApi.rank_allowed(), "Kids mode is not ranked")
	var got: Array = [{}]
	cloud.submit_rank({"kos": 99, "wins": 2, "matches": 3}, func(r: Dictionary) -> void: got[0] = r)
	check(str((got[0] as Dictionary).get("err", "")) == "kids" and not bool((got[0] as Dictionary).get("ok", true)), "a Kids-mode submit is refused before the network: " + JSON.stringify(got[0]))
	sheet.open("kos", false)
	check(sheet.kids and sheet.note_l.visible and sheet.note_l.text.contains("Kids mode"), "the sheet explains Kids mode is not ranked")
	check(sheet.sync_b.disabled and sheet.sync_msg_l.text.contains("Kids"), "Kids mode: Sync is disabled and explained: " + sheet.sync_msg_l.text)
	sheet.show_entries([{"rank": 1, "name": "Someone", "score": 5}])
	check(sheet.row_count() == 1, "the sheet still shows the board in Kids mode (reading is fine)")
	sheet.close()
	settings.set_value("kids_mode", false)
	check(AccountApi.rank_allowed(), "Kids mode off ranks again")
	cloud.setv("token", "")
	cloud.setv("user", "")
	got = [{}]
	cloud.submit_rank({"kos": 1}, func(r: Dictionary) -> void: got[0] = r)
	check(str((got[0] as Dictionary).get("err", "")) == "auth", "a signed-out submit is refused before the network: " + JSON.stringify(got[0]))

	# ---------------- live end-to-end (tools/test-ranking.js): the real server + fake old/dead servers
	var live_api := ""
	var live_tok := ""
	var live_old := ""
	var live_oldjson := ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--api="): live_api = a.substr(6)
		elif a.begins_with("--token="): live_tok = a.substr(8)
		elif a.begins_with("--oldjson="): live_oldjson = a.substr(10)
		elif a.begins_with("--old="): live_old = a.substr(6)
	if live_api != "":
		cloud.base_override = live_api
		cloud.setv("token", live_tok)
		cloud.setv("user", "GodotE2E")
		settings.set_value("kids_mode", false)
		var st_live := AccountApi.rank_stats(save)
		check(int(st_live.get("kos", 0)) == 7, "live: the Sync payload is the local career totals: " + JSON.stringify(st_live))
		sheet.open("kos", true)
		var rows_ok: bool = await _until(func() -> bool: return sheet.state == "rows", 15.0)
		check(rows_ok, "live: the real server's board loads with %d rows (%s)" % [sheet.row_count(), sheet.state])
		check(sheet.row_count() == RankingSheet.LIMIT, "live: the board fills the requested top %d" % RankingSheet.LIMIT)
		check(sheet.hint_text().contains("not on the K.O.s board yet"), "live: a signed-in player with no score is told so and offered Sync: " + sheet.hint_text())
		check(not sheet.sync_b.disabled, "live: Sync is enabled when signed in")
		sheet.sync_score()
		var synced7: bool = await _until(func() -> bool: return not sheet._syncing and int(sheet.you.get("score", 0)) >= 7, 15.0)
		check(synced7, "live: Sync posts the totals and the reply's `you` carries them (%d)" % int(sheet.you.get("score", 0)))
		check(sheet.you_l.visible and sheet.you_text().contains("#"), "live: the own record shows below the top N: " + sheet.you_text())
		check(not sheet._you_in_entries(), "live: the own record really is outside the shown top N")
		check(sheet.sync_msg_l.text.contains("Score sent"), "live: the Sync answer says it was sent: " + sheet.sync_msg_l.text)
		save.stats["kos"] = 11
		sheet.sync_score()
		var synced11: bool = await _until(func() -> bool: return not sheet._syncing and int(sheet.you.get("score", 0)) >= 11, 15.0)
		check(synced11, "live: a later Sync raises the server's stored best (monotonic): %d" % int(sheet.you.get("score", 0)))
		# the Wins board: our synced wins are on it, so the in-table row is highlighted and the pill is not duplicated
		sheet.open("wins", true)
		var wins_ok: bool = await _until(func() -> bool: return sheet.state == "rows" and not sheet._syncing, 15.0)
		check(wins_ok, "live: the Wins board loads")
		check(sheet._you_in_entries() and not sheet.you_l.visible, "live: an in-table own row is highlighted instead of the pill")
		check(_row_text(sheet).contains("(you)"), "live: the highlighted row says (you): " + _row_text(sheet))
		# an old server: a plain-text "not found" (older server.js falls through to static files)
		cloud.base_override = live_old
		sheet.open("kos", true)
		var old_ok: bool = await _until(func() -> bool: return sheet.state == "unsupported", 15.0)
		check(old_ok, "live: a plain-text 404 from an old server is the unsupported state (%s)" % sheet.state)
		check(sheet.status_l.text.contains("older build") and not sheet.status_l.text.contains("Not found"), "live: old server explained, raw text hidden: " + sheet.status_l.text)
		check(sheet.retry_b.visible, "live: the old-server state offers Retry")
		# a JSON 404 (a new server without the route: err none / Not found.)
		cloud.base_override = live_oldjson
		sheet.open("kos", true)
		var json_old_ok: bool = await _until(func() -> bool: return sheet.state == "unsupported", 15.0)
		check(json_old_ok, "live: a JSON 404 is the same unsupported state (%s)" % sheet.state)
		# unreachable
		cloud.base_override = "http://127.0.0.1:9"
		sheet.open("kos", true)
		var offline_ok: bool = await _until(func() -> bool: return sheet.state == "offline", 15.0)
		check(offline_ok, "live: an unreachable server is the offline state (%s)" % sheet.state)
		check(sheet.retry_b.visible, "live: the offline state offers Retry")
		cloud.base_override = ""
	else:
		# no server was provided: the dead-port path is still the offline state (never a crash, never a wait)
		cloud.base_override = "http://127.0.0.1:9"
		sheet.open("kos", true)
		var got_offline: bool = await _until(func() -> bool: return sheet.state == "offline", 8.0)
		check(got_offline, "an unreachable leaderboard shows the offline state (%s)" % sheet.state)
		check(sheet.status_l.text != "" and sheet.row_count() == 0 and sheet.retry_b.visible, "the offline state has a message, no rows and Retry")
		cloud.base_override = ""

	# ---------------- layout: the whole card (wrapped footer included) fits the supported canvas sizes
	# (headless windows cannot be resized, so the sheet's documented test hook fakes the canvas)
	cloud.setv("token", "test-token")
	cloud.setv("user", "Tester")
	for vp: Vector2 in [Vector2(910, 512), Vector2(1170, 540), Vector2(1280, 720)]:
		sheet.canvas_size_override = vp
		sheet.show_entries([
			{"rank": 1, "name": "Wobble_Wanda", "score": 128},
			{"rank": 2, "name": "GodotGuest", "score": 90},
			{"rank": 3, "name": "Kid_Carl", "score": 12},
		], {"you": {"rank": 12, "score": 340, "estimated": true}})
		sheet._layout()
		var ms := sheet.card.get_combined_minimum_size()
		check(ms.y <= vp.y - 8.0 and ms.x <= vp.x - 36.0, "the leaderboard card fits %s (needs %s)" % [vp, ms])
	sheet.canvas_size_override = Vector2.ZERO
	await process_frame
	cloud.setv("token", "")
	cloud.setv("user", "")
	settings.set_value("kids_mode", false)
	sheet.close()
	badge.queue_free()
	sheet.queue_free()

	print("RANKING " + ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)
