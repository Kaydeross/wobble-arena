extends SceneTree
## Menu flow test (headless, npm run test:godot-flow drives it next to a real relay, tools/test-godot-flow.js):
##   first launch: the how-to cards show once, Next / Let's play, remembered (seen_intro)
##   Title > Play > Wizard (every page) > Start
##   Title > Settings > each section > Back (Back button, Escape-style go_back, the Controls picture, the how-to again)
##   Title > Play online > room browser: the relay unreachable (error state, Try again), no rooms (empty state:
##     prints EMPTY_OK, the runner then opens two public rooms, one on another game version), the list (the other
##     version greyed out), tap the good room -> joined (prints JOINED), Leave; Back to the title; Back on the bare
##     title does nothing
##   Pause: the menu, Settings and Controls pages and back, Quit asks while the match runs, Keep playing, back resumes,
##     the online wording (Leave room), Quit after the question
##   godot --headless --path godot --script res://tests/flow_test.gd -- ws://127.0.0.1:PORT/ws --no-save

var fails := 0
var url := ""

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("ws://"): url = a
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func frames(n: int) -> void:
	for i in n: await process_frame

## Wait (up to `sec`) until `cond` is true, polling every frame.
func until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > sec * 1000.0: return false
		await process_frame
	return true

func _run() -> void:
	var st: Node = root.get_node("Settings")
	st.set_value("server_url", url)
	await _intro(st)
	await _wizard()
	await _settings(st)
	if url != "": await _online(st)
	await _pause()
	print("FLOW ok" if fails == 0 else "FLOW failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _main(intro: Variant = false) -> Control:
	var m: Control = load("res://scenes/main.tscn").instantiate()
	m.auto_intro = intro
	root.add_child(m)
	await frames(3)
	return m

func _intro(st: Node) -> void:
	st.set_value("seen_intro", false)
	var m := await _main(null)
	check(not m.intro.visible, "tests (--no-save) never get the how-to on their own")
	m.queue_free()
	m = await _main(true)
	check(m.intro.visible and m.intro.page == 0 and m.intro.title_l.text == "Move and look", "first launch shows the how-to")
	m.intro.next_b.pressed.emit()
	check(m.intro.page == 1 and m.intro.title_l.text == "Fire and melee", "Next: card 2")
	m.go_back()
	check(m.intro.page == 0, "Back: card 1 again")
	m.intro.go(2)
	check(m.intro.next_b.text == "Let's play" and m.intro.title_l.text == "Grab the crates", "card 3 ends with Let's play")
	m.intro.next_b.pressed.emit()
	check(not m.intro.visible and bool(st.get_value("seen_intro")), "Let's play closes it and remembers")
	m.queue_free()
	st.set_value("seen_intro", false)
	m = await _main(true)
	m.intro.skip_b.pressed.emit()
	check(not m.intro.visible and bool(st.get_value("seen_intro")), "Skip closes it and remembers")
	m.queue_free()
	print("FLOW intro checked")

func _wizard() -> void:
	var m := await _main()
	var started := [false]
	m.wizard.start_requested.disconnect(m.play_offline)   # (no scene change in a --script test)
	m.wizard.start_requested.connect(func() -> void: started[0] = true)
	m.play.pressed.emit()
	check(m.wizard.visible and m.wizard.page == 0, "Play opens the wizard")
	for i in 4:
		m.wizard.next_b.pressed.emit()
		check(m.wizard.page == i + 1, "Next goes to page %d" % (i + 2))
	check(m.wizard.next_b.text == "Start", "the last page says Start")
	m.wizard.next_b.pressed.emit()
	check(started[0], "Start starts the match")
	m.wizard.go(2)
	m.go_back(); m.go_back(); m.go_back()
	check(not m.wizard.visible and m.home.visible, "Back through the wizard returns to the title")
	check(not m.go_back(), "Back on the bare title does nothing (the app does not quit)")
	m.queue_free()
	print("FLOW wizard checked")

func _settings(st: Node) -> void:
	var m := await _main()
	m.gear.pressed.emit()
	var s: Control = m.settings
	check(s.visible and s.section == "controls", "the gear opens Settings on Controls")
	for sec: String in s.SECTIONS:
		s.tabs[sec].pressed.emit()
		await process_frame
		check(s.section == sec and s.rows.get_child_count() > 0, "Settings > %s has rows" % sec)
	s.tabs["controls"].pressed.emit()
	check(s.ctl.has("aim_button"), "Controls: the Aim button row")
	s.tabs["gameplay"].pressed.emit()
	await process_frame
	check(s.ctl.has("aim_mode"), "Gameplay: the Aim mode row exists")
	if s.ctl.has("aim_mode"):
		var aim_ctl: Dictionary = s.ctl["aim_mode"]
		check(aim_ctl.has("normal") and aim_ctl.has("advanced"), "Aim mode offers Normal and Advanced")
		check(str(st.get_value("aim_mode")) == "normal", "aim mode defaults to Normal")
		(aim_ctl["advanced"] as Button).pressed.emit()
		check(str(st.get_value("aim_mode")) == "advanced", "choosing Advanced saves at once")
		(aim_ctl["normal"] as Button).pressed.emit()
		check(str(st.get_value("aim_mode")) == "normal", "choosing Normal saves at once")
	s.tabs["controls"].pressed.emit()
	s.ui["help"].pressed.emit()
	check(s.help.visible, "Controls > See the controls")
	m.go_back()
	check(not s.help.visible and s.visible, "Back closes the controls picture only")
	s.ui["intro"].pressed.emit()
	check(s.intro.visible, "Controls > Show the how-to again")
	s.intro.skip_b.pressed.emit()
	s.tabs["account"].pressed.emit()
	s.ui["account"].pressed.emit()
	check(m.account.visible, "Account > Open account opens the Account sheet")
	m.go_back()
	check(not m.account.visible and s.visible, "Back closes the Account sheet, Settings stays")
	s.tabs["camera"].pressed.emit()
	s.ctl["cam_auto_center"][false].pressed.emit()
	check(not bool(st.get_value("cam_auto_center")), "Camera: Manual saved")
	s.ctl["cam_auto_center"][true].pressed.emit()
	s.back_b.pressed.emit()
	check(not s.visible, "Back closes Settings")
	m.queue_free()
	print("FLOW settings checked")

func _online(st: Node) -> void:
	var m := await _main()
	var b: Control = m.browser
	# the relay unreachable: a clear error with Try again
	b.auto_refresh = false
	m.show_tab(true)
	b.url = "ws://127.0.0.1:9/ws"
	b.refresh()
	check(await until(func() -> bool: return b.state == "error", 8.0), "unreachable relay -> error state (%s)" % b.state)
	check(b.msg_l.text.contains("reach the game server") and b.action_b.text == "Try again", "error says what to do")
	m.show_tab(false)
	# the real relay: no rooms yet
	b.auto_refresh = true
	m.show_tab(true)
	await frames(2)
	check(b.state == "loading" and b.count_l.text == "Looking for rooms…", "showing the panel refreshes the list (%s)" % b.state)
	check(b.url == url, "the list asks the configured server")
	check(await until(func() -> bool: return b.state == "empty" or b.state == "error", 8.0), "list answered (%s)" % b.state)
	check(b.state == "empty" and b.action_b != null and b.action_b.text == "Host a room", "empty state with Host a room (%s: %s)" % [b.state, b.msg_l.text if b.msg_l else ""])
	b.action_b.pressed.emit()
	check(m.host_sheet.visible, "the empty state's Host a room opens the host sheet")
	m.go_back()
	check(not m.host_sheet.visible and m.online_panel.visible, "Back closes the host sheet")
	print("EMPTY_OK")
	var t0 := Time.get_ticks_msec()
	while b.state != "rooms" or b.rooms.size() < 2:
		if Time.get_ticks_msec() - t0 > 20000: break
		if not b.list.busy: b.refresh()
		await frames(20)
	check(b.rooms.size() == 2, "two public rooms listed (%d)" % b.rooms.size())
	var good: Button = null
	for r: Dictionary in b.rooms:
		var row: Button = b.rows_by_id[r["id"]]
		if r["name"] == "Old Room": check(row.disabled and row.get_node("Row/Info/Sub").text.contains("Different game version"), "another version is greyed out")
		else: good = row
	check(good != null and not good.disabled, "the room on our version can be joined")
	if good:
		good.pressed.emit()
		check(m.session != null, "tapping a room starts joining")
		check(await until(func() -> bool: return m.session != null and m.status.text.begins_with("Connected"), 10.0), "joined (%s)" % m.status.text)
		print("JOINED")
		check(m._ui["leave"].visible and not m._ui["join"].visible, "Leave shows while in a room")
		m._ui["leave"].pressed.emit()
		await frames(2)
		check(m.session == null and m._ui["join"].visible, "Leave ends the session")
	m.go_back()
	check(m.home.visible and not m.online_panel.visible, "Back from the online panel returns to the title")
	m.queue_free()
	print("FLOW online checked")

func _pause() -> void:
	var w: Node = load("res://world/world.tscn").instantiate()
	w.auto_run = false
	w.bot_count = 1
	w.rng_seed = 5
	root.add_child(w)
	await frames(3)
	# HUD: the Advanced aim badge follows the setting live (docs/AIM.md)
	var st: Node = root.get_node("Settings")
	st.set_value("aim_mode", "advanced")
	w.tick(1.0 / 60.0)
	var aim_badge: Label = w.hud.find_child("AimBadge", true, false)
	check(aim_badge != null and aim_badge.visible, "Advanced aim badge shows in a match")
	st.set_value("aim_mode", "normal")
	w.tick(1.0 / 60.0)
	check(aim_badge != null and not aim_badge.visible, "the aim badge hides in Normal")
	var pm: Control = w.pause_menu
	var quit := [false]
	pm.quit_requested.disconnect(w._on_title_pressed)   # (no scene change in a --script test)
	pm.quit_requested.connect(func() -> void: quit[0] = true)
	w._toggle_pause()
	check(w.paused and pm.visible and pm.page() == "menu", "pause shows the menu")
	check(pm.quit_b.text == "Quit to title", "offline: Quit to title")
	pm.settings_b.pressed.emit()
	check(pm.page() == "settings" and not pm.settings.tabs["account"].disabled, "Settings from the pause menu")
	pm.settings.tabs["account"].pressed.emit()
	check(pm.settings.ui.get("account") == null, "no Account sheet inside a match")
	pm.back()
	check(pm.page() == "menu", "Back: the menu again")
	pm.help_b.pressed.emit()
	check(pm.page() == "help", "Controls picture")
	pm.back()
	check(pm.page() == "menu", "Back from the controls picture")
	pm.quit_b.pressed.emit()
	check(pm.page() == "confirm" and not quit[0], "Quit asks first while the match runs")
	pm.stay_b.pressed.emit()
	check(pm.page() == "menu" and w.paused, "Keep playing returns to the menu")
	pm.back()
	check(not w.paused and not pm.visible, "Back on the menu resumes")
	w._toggle_pause()
	pm.online = true
	check(pm.quit_b.text == "Leave room" and pm.go_b.text == "Leave room", "online: Leave room")
	pm.quit_b.pressed.emit()
	pm.go_b.pressed.emit()
	check(quit[0], "Leave room after the question")
	pm.match_running = func() -> bool: return false
	quit[0] = false
	pm.open()
	pm.quit_b.pressed.emit()
	check(quit[0], "after the match: no question")
	w.queue_free()
	await frames(2)
	print("FLOW pause checked")
