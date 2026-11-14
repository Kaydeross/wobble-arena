extends SceneTree
## Server identity + leaderboard client test (run by tools/test-ranking.js, headless, no server needed):
##   godot --headless --path godot --script res://tests/ranking_test.gd -- --no-save
## Checks: ServerInfo classification for the Official / Local / Custom URLs (with host, colour and the wrong-server hint),
## the ServerBadge chip, the RankingSheet's rows / "you" highlight / empty / error / loading states and its server header,
## the Kids-mode note, and the guards that stop a Kids-mode or signed-out submit before it reaches the network.

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

	# ---------------- RankingSheet: build, rows, "you", tabs, states
	var sheet := RankingSheet.new()
	root.add_child(sheet)
	sheet.open("kos", false)
	check(sheet.visible and sheet.state == "loading", "the sheet opens in the loading state")
	check(sheet.badge != null and sheet.badge.text() != "", "the header carries the ServerInfo badge: " + (sheet.badge.text() if sheet.badge else ""))
	check(sheet.host_l.text.contains(ServerInfo.current().host), "the header names the server host")
	sheet.show_entries([
		{"rank": 1, "name": "Wobble_Wanda", "score": 128, "updated": Time.get_unix_time_from_system() * 1000.0 - 120000},
		{"rank": 2, "name": "GodotGuest", "score": 90, "updated": Time.get_unix_time_from_system() * 1000.0 - 3600000},
		{"rank": 3, "name": "Kid_Carl", "score": 12, "updated": 0, "me": true},
	])
	check(sheet.state == "rows" and sheet.row_count() == 3, "three mock rows build (%d)" % sheet.row_count())
	var texts: Array = []
	for r in sheet.rows.get_children():
		for n in r.find_children("*", "Label", true, false): texts.append((n as Label).text)
	var joined := " | ".join(texts)
	check(joined.contains("Wobble_Wanda") and joined.contains("128"), "the rows show name and score: " + joined)
	check(joined.contains("(you)"), "the signed-in player's row is highlighted: " + joined)
	check(joined.contains("2 min ago") or joined.contains("1 h ago"), "the rows show when the score was set: " + joined)
	sheet.open("wins", false)
	check(sheet.board == "wins" and (sheet.tabs["wins"] as Button).button_pressed, "the board tabs switch")
	sheet.open("arcade", false)
	check(sheet.board == "arcade" and (sheet.tabs["arcade"] as Button).button_pressed and not (sheet.tabs["kos"] as Button).button_pressed, "Arcade tab is the only pressed one")
	sheet.show_empty()
	check(sheet.state == "empty" and sheet.row_count() == 0 and sheet.status_l.text.contains("No scores"), "the empty state says so: " + sheet.status_l.text)
	sheet.show_error("Couldn't reach the server.")
	check(sheet.state == "error" and sheet.status_l.text.contains("reach"), "the error state shows the message")
	sheet.close()
	check(not sheet.visible, "the sheet closes")

	# ---------------- Kids mode: no submission, and the sheet says so
	settings.set_value("kids_mode", true)
	check(AccountApi.kids_mode(), "Settings kids_mode is read")
	check(not AccountApi.rank_allowed(), "Kids mode is not ranked")
	var got: Array = [{}]
	cloud.submit_rank({"kos": 99, "wins": 2, "matches": 3}, func(r: Dictionary) -> void: got[0] = r)
	check(str((got[0] as Dictionary).get("err", "")) == "kids" and not bool((got[0] as Dictionary).get("ok", true)), "a Kids-mode submit is refused before the network: " + JSON.stringify(got[0]))
	sheet.open("kos", false)
	check(sheet.kids and sheet.note_l.visible and sheet.note_l.text.contains("Kids mode"), "the sheet explains Kids mode is not ranked")
	sheet.show_entries([{"rank": 1, "name": "Someone", "score": 5}])
	check(sheet.row_count() == 1, "the sheet still shows the board in Kids mode (reading is fine)")
	sheet.close()
	settings.set_value("kids_mode", false)
	check(AccountApi.rank_allowed(), "Kids mode off ranks again")
	cloud.setv("token", "")
	got = [{}]
	cloud.submit_rank({"kos": 1}, func(r: Dictionary) -> void: got[0] = r)
	check(str((got[0] as Dictionary).get("err", "")) == "auth", "a signed-out submit is refused before the network: " + JSON.stringify(got[0]))

	# ---------------- the real fetch path: a dead server ends in the error state (never a crash, never a wait on gameplay)
	cloud.base_override = "http://127.0.0.1:9"
	sheet.open("kos", true)
	var got_error: bool = await _until(func() -> bool: return sheet.state == "error", 8.0)
	check(got_error, "an unreachable leaderboard shows the error state (%s)" % sheet.state)
	check(sheet.status_l.text != "" and sheet.row_count() == 0, "the error state has a message and no rows")
	cloud.base_override = ""
	sheet.close()
	badge.queue_free()
	sheet.queue_free()

	print("RANKING " + ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)
