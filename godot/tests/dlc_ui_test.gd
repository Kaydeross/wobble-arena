extends SceneTree
## Construction DLC UI test (headless, run by tools/test-dlc-ui.js, npm run test:godot-dlc-ui):
##   godot --headless --path godot --script res://tests/dlc_ui_test.gd -- --no-save
## 1. DlcUnlock (dlc/construction/dlc_unlock.gd): locked by default, a wrong code changes nothing, a 1.5 s cooldown after 3
##    wrong tries, the right code (tested with a throwaway code / hash pair through redeem_with, never the real code)
##    unlocks every outfit, emote and class once and pays 5000 coins once, buying with and without enough coins, the
##    "dlc" blob key round trip (also through JSON), no printing / logging in the unlock code.
## 2. The title banner, the hub (locked / unlocked, Arcade "Coming soon" until arcade_manager.gd exists), the Classic
##    pre-match card and the Settings keys Start writes, Construction gone from the wizard, the hidden code field in
##    Settings > About (7 taps on the version line).
## 3. Layout: the title banner, the hub (locked, unlocked), the pre-match card and the code sheet at 667x375, 812x375,
##    852x393, 926x428 and an iPad in English, French and Japanese: inside the safe area, nothing overlapping, touch
##    targets >= 44 pt, 8 pt between controls, no font under 14, no truncated or clipped text.

## Loaded in _run, not compiled with the test: these classes use the autoloads (Save, Settings, ...), which a --script
## run registers only after its own script is compiled.
var DU: GDScript
var CH: GDScript
var SW: GDScript
var SS: GDScript

const TEST_CODE := "throwaway-code-123"
const TEST_HASH := "4e4feab772f70a68cb851909e699a6e76b9cada2adc0186773dd3c60fed30bc2"   ## sha256("wobblers-arena-dlc-v1:" + TEST_CODE)
const SIZES := [
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(812, 375), [44.0, 0.0, 44.0, 21.0]],
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(926, 428), [47.0, 0.0, 47.0, 21.0]],
	[Vector2(1194, 834), [0.0, 24.0, 0.0, 20.0]],
]
const STATES := ["title", "locked", "owned", "pre", "code"]
const MIN_TOUCH := 44.0
const MIN_GAP_PT := 8.0

var fails := 0
var made: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _profile() -> SaveProfile:
	var s := SaveProfile.new()
	s.persist = false
	made.append(s)
	return s

func _run() -> void:
	DU = load("res://dlc/construction/dlc_unlock.gd")
	CH = load("res://dlc/construction/construction_hub.gd")
	SW = load("res://ui/setup_wizard.gd")
	SS = load("res://ui/settings_screen.gd")
	_unlock()
	await _cooldown()
	await _flow()
	await _layouts()
	for n: Node in made: n.free()
	print("DLC UI ok" if fails == 0 else "DLC UI checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

# ---------------- 1. DlcUnlock ----------------

func _unlock() -> void:
	check(("wobblers-arena-dlc-v1:" + TEST_CODE).sha256_text() == TEST_HASH and DU.hash_of(" " + TEST_CODE + " ") == TEST_HASH, "the salted hash (spaces round the code are ignored)")
	check(DU.price() == 1500 and DU.PRICE == 1500, "the DLC costs 1500 coins")
	check(DU.DEV_HASH.length() == 64 and DU.DEV_HASH == DU.DEV_HASH.to_lower(), "the developer hash is 64 lower-case hex digits")
	var s := _profile()
	check(not DU.owned(s) and s.dlc == DlcSave.fresh(), "locked by default")
	DU.reset_attempts()
	var before := JSON.stringify(s.get_blob())
	for code: String in ["wrong", "", "  ", "DLC", TEST_CODE]:
		check(not DU.redeem(code, s), "a wrong code is refused")
		DU.reset_attempts()
	check(JSON.stringify(s.get_blob()) == before and not DU.owned(s), "wrong codes change nothing")
	# the right code (a throwaway pair)
	check(not DU.redeem_with(TEST_CODE.to_upper(), TEST_HASH, s), "the code is case-sensitive")
	check(not DU.redeem_with(TEST_CODE, "0".repeat(64), s), "another hash does not match")
	check(JSON.stringify(s.get_blob()) == before, "still nothing changed")
	var c0 := s.coins
	check(DU.redeem_with("  " + TEST_CODE + "  ", TEST_HASH, s), "the right code is accepted")
	check(DU.owned(s) and s.dlc["owned"] == true and s.codes.has("dev"), "the DLC and the dev code are in the profile")
	for k: String in LockerData.all_skins():
		if WobblerLooks.skin_def(k).size() > 0: check(s.skins.has(k), "outfit %s unlocked" % k)
	check(s.skins.has("dev") and s.skins.has("beta"), "the code outfits are unlocked")
	for id: String in LockerData.all_emotes(): check(s.owned.has(id), "emote %s unlocked" % id)
	for id: String in ExtraClasses.data().keys():
		check(s.classes.has(id) and s.owns_class(id), "class %s unlocked" % id)
	check(s.owns_class("boo") or ExtraClasses.data().size() > 0, "classes exist")
	check(s.coins == c0 + 5000, "5000 coins granted (%d -> %d)" % [c0, s.coins])
	var snap := JSON.stringify(s.get_blob())
	check(DU.redeem_with(TEST_CODE, TEST_HASH, s), "redeeming again is fine")
	check(s.coins == c0 + 5000 and s.codes.count("dev") == 1 and JSON.stringify(s.get_blob()) == snap, "a second redeem grants nothing more")
	# it survives a save round trip, through JSON like the file and the cloud
	var back := _profile()
	check(back.apply_blob(JSON.parse_string(JSON.stringify(s.get_blob()))), "the blob loads")
	check(DU.owned(back) and back.dlc["bonus"] == true and back.coins == s.coins, "owned, coins and the bonus flag survive")
	for id: String in ExtraClasses.data().keys(): check(back.owns_class(id), "class %s survives the round trip" % id)
	check(back.skins.has("dev") and back.owned.size() >= LockerData.all_emotes().size(), "outfits and emotes survive")
	check(DU.redeem_with(TEST_CODE, TEST_HASH, back) and back.coins == s.coins, "redeeming after a reload still pays once")
	# buy
	var b := _profile()
	b.coins = 1499
	check(not DU.buy(b) and b.coins == 1499 and not DU.owned(b) and DU.missing(b) == 1, "1499 coins cannot buy it (1 short)")
	b.coins = 1500
	check(DU.buy(b) and b.coins == 0 and DU.owned(b) and b.dlc["owned"] == true and not b.codes.has("dev"), "1500 coins buy it")
	check(not DU.buy(b) and b.coins == 0, "buying twice costs nothing more")
	check(b.skins.size() == _profile().skins.size(), "buying the DLC unlocks no outfits (only the code does)")
	var b2 := _profile()
	b2.coins = 4000
	check(DU.buy(b2) and b2.coins == 2500, "buying from 4000 leaves 2500")
	var back2 := _profile()
	check(back2.apply_blob(JSON.parse_string(JSON.stringify(b2.get_blob()))) and DU.owned(back2) and back2.coins == 2500, "a bought DLC survives a reload")
	# the unlock code never prints or logs
	for f: String in ["res://dlc/construction/dlc_unlock.gd", "res://dlc/construction/code_sheet.gd"]:
		var src := FileAccess.get_file_as_string(f)
		for bad: String in ["print(", "push_warning", "push_error", "printerr", "OS.alert"]:
			check(not src.contains(bad), "%s has no %s" % [f, bad])

func _cooldown() -> void:
	var s := _profile()
	DU.reset_attempts()
	for i in 3: check(not DU.redeem_with("bad%d" % i, TEST_HASH, s), "wrong try %d" % i)
	check(DU.cooldown_left() > 1.0, "three wrong tries start the cooldown (%.2f s)" % DU.cooldown_left())
	check(not DU.redeem_with(TEST_CODE, TEST_HASH, s) and not DU.owned(s), "the right code waits for the cooldown")
	var t0 := Time.get_ticks_msec()
	while DU.cooldown_left() > 0.0 and Time.get_ticks_msec() - t0 < 5000: await process_frame
	var waited := Time.get_ticks_msec() - t0
	check(DU.cooldown_left() == 0.0 and waited >= 1000 and waited <= 1700, "the cooldown ends after about 1.5 s (%d ms left to wait at the check)" % waited)
	check(DU.redeem_with(TEST_CODE, TEST_HASH, s) and DU.owned(s), "the right code works after it")
	DU.reset_attempts()

# ---------------- 2. title, hub, flow ----------------

func _main(vp: SubViewport) -> Control:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.auto_intro = false
	main.auto_news = false
	vp.add_child(main)
	return main

func _flow() -> void:
	var sv: Node = root.get_node("Save")
	var st: Node = root.get_node("Settings")
	sv.reset()
	sv.coins = 600
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	vp.disable_3d = true
	root.add_child(vp)
	var main := _main(vp)
	await process_frame
	await process_frame
	check(int(st.DEFAULTS["site_seed"]) == 0 and int(st.get_value("site_seed")) == 0, "site_seed defaults to 0 (random per match)")
	# the wizard no longer offers Construction; the mode and its rules stay
	check(not SW.modes().has("construction") and SW.modes().has("classic"), "Construction is not a wizard game type")
	for sec: Array in SW.sections(): check(not (sec[1] as Array).has("construction"), "no wizard section lists Construction")
	check(root.get_node("Content").modes.has("construction") and ModeRules.OFFLINE_ONLY.has("construction"), "the mode id and OFFLINE_ONLY are kept")
	st.set_value("mode", "construction"); st.set_value("offline_map", "siteyard")
	main.wizard.load_settings()
	check(main.wizard.mode_id == "classic" and main.wizard.map_id == "arena", "a remembered Construction start leaves the wizard on Classic / arena (%s %s)" % [main.wizard.mode_id, main.wizard.map_id])
	st.set_value("mode", "classic"); st.set_value("offline_map", "arena")
	# the banner
	var banner := main.get_node_or_null("Safe/Col/Body/Home/Construction") as Button
	check(banner != null and banner.is_visible_in_tree(), "the title has the Construction banner")
	check((banner as DontEnterSign).label == "DON'T ENTER", "the sign says DON'T ENTER")
	var hub = main.hub
	check(hub != null and not hub.visible, "the hub waits behind the banner")
	main.open_hub()
	check(hub.visible, "the hub opens")
	check(main.go_back() and not hub.visible, "go_back() closes the hub")
	# the DON'T ENTER wipe: the title turns into the Construction title, whose Play opens the hub
	main.set_dlc(true, false)
	check(main.dlc and (banner as DontEnterSign).label == "EXIT SITE", "the Construction title shows EXIT SITE")
	main.play.pressed.emit()
	check(hub.visible and not main.wizard.visible, "Play on the Construction title opens the hub")
	check(main.go_back() and not hub.visible, "go_back() closes the hub again")
	main.set_dlc(false, false)
	check(not main.dlc and (banner as DontEnterSign).label == "DON'T ENTER", "EXIT SITE returns to the normal title")
	banner.pressed.emit()
	check(main._wipe.busy, "the sign starts the tape wipe")
	main._wipe.busy = false; main._wipe.visible = false   # (the tween finishes on its own; this test does not wait for it)
	# locked hub
	main.open_hub()
	check(hub.classic_b.disabled and hub.arcade_b.disabled, "locked: both cards disabled")
	check(hub.buy_row.visible and hub.buy_b.disabled and hub.buy_b.text.contains("900"), "short of coins: the button says how many more (%s)" % hub.buy_b.text)
	check(hub.code_b.visible and hub.code_b.text == "Enter code", "locked: Enter code")
	var pads := 0
	for l: Control in hub._locks: if l.visible: pads += 1
	check(pads == 2, "locked: a padlock on each card")
	hub.open_pre()
	check(not hub.pre.visible, "a locked Classic does not open the pre-match card")
	hub.start()
	check(str(st.get_value("mode")) == "classic", "a locked Start does nothing")
	check(not hub.buy(), "buying without coins fails")
	# the code field in the hub: a wrong code says so, nothing unlocks
	hub.open_code()
	check(hub.code_sheet.visible and main.go_back() == true and not hub.code_sheet.visible and hub.visible, "go_back() closes the code sheet first")
	hub.open_code()
	DU.reset_attempts()
	hub.code_sheet.field.text = "definitely not it"
	check(not hub.code_sheet.submit() and hub.code_sheet.msg.text == "Wrong code" and hub.code_sheet.field.text == "", "a wrong code says Wrong code and clears the field")
	check(not DU.owned(), "still locked")
	hub.code_sheet.close()
	# buy
	sv.coins = 2000
	hub.refresh()
	check(not hub.buy_b.disabled and hub.buy_b.text.contains("1500"), "with 2000 coins: Unlock for 1500 coins (%s)" % hub.buy_b.text)
	check(hub.buy() and DU.owned() and sv.coins == 500, "buying takes 1500 coins and unlocks")
	check(not hub.buy_row.visible and not hub.classic_b.disabled, "unlocked: no buy row, Classic usable")
	var pads2 := 0
	for l: Control in hub._locks: if l.visible: pads2 += 1
	check(pads2 == 0, "unlocked: no padlocks")
	# Arcade: "Coming soon" until unit D's manager exists
	var ready: bool = CH.arcade_ready()
	check(hub.arcade_b.disabled == not ready, "Arcade is %s" % ("on" if ready else "off until arcade_manager.gd exists"))
	if not ready: check((hub._tags[hub.arcade_card] as Label).text == "Coming soon", "Arcade says Coming soon")
	var arcade_taps := [0]
	hub.arcade_requested.connect(func() -> void: arcade_taps[0] += 1)
	hub.arcade_b.pressed.emit()
	check(arcade_taps[0] == (1 if ready else 0), "Arcade %s" % ("opens" if ready else "does nothing while it is coming soon"))
	# Classic: the pre-match card
	var got: Array = []
	hub.start_requested.connect(func(o: Dictionary) -> void: got.append(o))
	check(hub.start_requested.is_connected(main.play_offline), "Start goes to main.play_offline")
	hub.classic_b.pressed.emit()
	check(hub.pre.visible and not hub.main_view.visible and hub.title_l.text == "Classic", "Classic opens the pre-match card")
	check(hub.bots == 7 and (hub._bot_bs[7] as Button).button_pressed, "bots default to 7 (eight fighters)")
	check(hub.site_seed == 0 and hub.seed_l.text == "Random", "the seed starts random")
	hub.set_bots(3)
	check((hub._bot_bs[3] as Button).button_pressed and not (hub._bot_bs[7] as Button).button_pressed, "bots pick")
	hub.set_bots(99)
	check(hub.bots == 7, "bots stay in 1..7")
	hub.set_bots(1)
	check(hub.bots == 1, "one bot is allowed")
	hub.set_diff("hard")
	check(str(st.get_value("difficulty")) == "hard" and (hub._diff_bs["hard"] as Button).button_pressed, "difficulty uses the Settings difficulty")
	hub.reroll()
	var seed1: int = hub.site_seed
	check(seed1 >= 1 and seed1 <= CH.SEED_MAX and hub.seed_l.text.contains(str(seed1)), "Re-roll fixes a seed and shows it (%s)" % hub.seed_l.text)
	hub.set_seed(0)
	check(hub.seed_l.text == "Random", "Random goes back to a new site every match")
	hub.set_seed(424242)
	hub.set_bots(7)
	check(main.go_back() and not hub.pre.visible and hub.main_view.visible and hub.visible, "go_back() leaves the pre-match card for the cards")
	hub.open_pre()
	hub.start()
	var want_map := "sitegen" if root.get_node("Content").maps.has("sitegen") else "siteyard"
	check(str(st.get_value("mode")) == "construction", "Start: mode = construction")
	check(int(st.get_value("bots")) == 7 and str(st.get_value("difficulty")) == "hard", "Start: bots and difficulty")
	check(str(st.get_value("offline_map")) == want_map, "Start: offline_map = %s (%s)" % [want_map, st.get_value("offline_map")])
	check(int(st.get_value("site_seed")) == 424242, "Start: site_seed")
	check(got.size() == 1 and got[0] == {"mode": "construction", "map": want_map, "bots": 7, "difficulty": "hard"}, "Start asks main for the offline match (%s)" % [got])
	check(root.get_node("Content").maps.has(want_map), "the start map exists")
	# the pre-match choices are remembered when the hub is opened again
	hub.close()
	hub.open()
	check(hub.diff == "hard" and hub.site_seed == 424242 and not hub.pre.visible, "reopening keeps difficulty and seed, starts on the cards")
	hub.close()
	st.set_value("mode", "classic"); st.set_value("offline_map", "arena"); st.set_value("site_seed", 0); st.set_value("bots", 3); st.set_value("difficulty", "normal")
	# Settings > About: seven taps on the version line open the code field
	main.show_settings(true, "about")
	await process_frame
	var set_ = main.settings
	var vl := set_.rows.get_node_or_null("Row_Version/Words/Sub") as Label
	check(vl != null and vl.mouse_filter == Control.MOUSE_FILTER_STOP, "the version line takes taps")
	for i in 6: set_.version_tap()
	check(not set_.code_sheet.visible, "six taps do nothing")
	set_.version_tap()
	check(set_.code_sheet.visible, "the seventh tap opens the code field")
	check(main.go_back() and not set_.code_sheet.visible and set_.visible, "go_back() closes it first")
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	for i in 7: vl.gui_input.emit(ev)
	check(set_.code_sheet.visible, "seven real taps on the label open it too")
	DU.reset_attempts()
	set_.code_sheet.field.text = "nope"
	check(not set_.code_sheet.submit() and set_.code_sheet.msg.text == "Wrong code", "Settings: a wrong code is refused")
	set_.code_sheet.close()
	main.show_settings(false)
	vp.queue_free()
	await process_frame
	# a match in Settings (pause menu) has no hidden code field
	var sc = SS.new()
	sc.in_match = true
	root.add_child(sc)
	await process_frame
	sc.open_section("about")
	check(sc.rows.get_node("Row_Version/Words/Sub").mouse_filter != Control.MOUSE_FILTER_STOP, "no hidden code field in a match")
	sc.queue_free()
	await process_frame

# ---------------- 3. layout ----------------

func _layouts() -> void:
	var sv: Node = root.get_node("Save")
	for loc: String in ["en", "fr", "ja"]:       # Japanese last and left on: Godot logs font errors at exit when a CJK language is switched back
		if loc != "en": root.get_node("Lang").apply(loc)
		for sz: Array in SIZES:
			for state: String in STATES:
				await _layout_case(sz[0], sz[1], state, loc, sv)
	SafeArea.override = []

func _layout_case(win: Vector2, ins_pt: Array, state: String, loc: String, sv: Node) -> void:
	var cs := UiScale.canvas_size(win, "normal", true)
	var k := cs.x / win.x
	var ins := [ins_pt[0] * k, ins_pt[1] * k, ins_pt[2] * k, ins_pt[3] * k]
	SafeArea.override = ins
	var tag := "%dx%d %s %s" % [win.x, win.y, state, loc]
	sv.coins = 2300
	sv.dlc = DlcSave.fresh()
	sv.codes = []
	sv.dlc["owned"] = state in ["owned", "pre"]
	var vp := SubViewport.new()
	vp.size = Vector2i(cs)
	vp.disable_3d = true
	root.add_child(vp)
	var main := _main(vp)
	main.browser.auto_refresh = false
	var page: Control = main.get_node("Safe/Col")
	var col: Control = page
	if state != "title":
		main.open_hub()
		page = main.hub
		col = main.hub.col
		if state == "pre": main.hub.open_pre()
		if state == "code":
			main.hub.open_code()
			page = main.hub.code_sheet.card
			col = page
	for i in 5: await process_frame
	var safe := Rect2(Vector2(ins[0], ins[1]), cs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	check(page.is_visible_in_tree(), "%s page shown" % tag)
	check(col.get_combined_minimum_size().y <= safe.size.y + 0.5, "%s column min height %.0f fits %.0f" % [tag, col.get_combined_minimum_size().y, safe.size.y])
	var all: Array = []
	_gather(page, all)
	var items: Array = []
	for c: Control in all:
		if c is BaseButton or c is LineEdit:
			var r := _shown(c)
			check(r.size.x > 0.0, "%s '%s' is visible" % [tag, _nm(c)])
			if r.size.x <= 0.0: continue
			items.append([c, r])
			check(safe.grow(0.5).encloses(r), "%s '%s' %s inside the safe area %s" % [tag, _nm(c), r, safe])
			check(minf(r.size.x, r.size.y) >= MIN_TOUCH * k - 0.5, "%s '%s' touch target %s px = %.1f pt" % [tag, _nm(c), r.size, minf(r.size.x, r.size.y) / k])
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Control = items[i][0]
			var b: Control = items[j][0]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a): continue
			var g := _gap(items[i][1], items[j][1])
			check(g >= MIN_GAP_PT * k - 0.6, "%s '%s' and '%s' are %.1f pt apart (need 8)" % [tag, _nm(a), _nm(b), g / k])
	for c: Control in all:
		if c is Label or c is Button:
			var txt: String = c.text
			if txt == "": continue
			var fs := c.get_theme_font_size("font_size")
			check(fs >= UiTheme.MIN_FONT, "%s '%s' font %d under %d" % [tag, txt, fs, UiTheme.MIN_FONT])
			_whole(c, txt, tag)
			var holder := _button_above(c) if state != "title" else null     # words inside a card stay inside the card
			if holder != null:
				var lr := c.get_global_rect()
				check(holder.get_global_rect().grow(1.0).encloses(lr), "%s '%s' %s sticks out of its card %s" % [tag, txt, lr, holder.get_global_rect()])
	if state == "locked" or state == "owned":
		var h = main.hub
		for card: Button in [h.classic_card, h.arcade_card]:
			var st := card.get_node("Margin/Stack") as Control
			check(st.get_combined_minimum_size().y <= card.size.y - 2.0 * UiTheme.SP_3 + 0.5, "%s card '%s' words (%.0f) fit the card (%.0f)" % [tag, card.name, st.get_combined_minimum_size().y, card.size.y])
	if state == "title":
		var bn := main.get_node("Safe/Col/Body/Home/Construction") as Button
		check(bn.is_visible_in_tree() and safe.grow(0.5).encloses(bn.get_global_rect()), "%s banner inside the safe area" % tag)
		check(bn.get_global_rect().size.x >= 400.0, "%s banner is wide" % tag)
		var more := main.get_node("Safe/Col/Body/Home/More") as Control
		check(bn.get_global_rect().position.y >= more.get_global_rect().end.y + 8.0 * k - 0.6, "%s banner sits below the Walldrobe row" % tag)
		check(main.get_node("Safe/Col/Build").get_global_rect().position.y >= bn.get_global_rect().end.y, "%s the version line is below the banner" % tag)
		var tip := main.get_node("Safe/Col/Tip") as Label
		if tip.visible: check(safe.encloses(tip.get_global_rect()), "%s tip inside the safe area" % tag)
	print("DLC %s canvas %dx%d checked" % [tag, cs.x, cs.y])
	vp.queue_free()
	await process_frame

func _gather(n: Node, out: Array) -> void:
	for c in n.get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree(): continue
		out.append(c)
		_gather(c, out)

func _nm(c: Control) -> String:
	var t: Variant = c.get("text")
	return str(t) if t != null and str(t) != "" else str(c.name)

func _shown(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null and r.size.x > 0.0 and r.size.y > 0.0:
		if p is Control and (p as Control).clip_contents: r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r if r.size.x > 0.0 and r.size.y > 0.0 else Rect2()

func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)

func _button_above(c: Control) -> Button:
	var p := c.get_parent()
	while p != null:
		if p is Button: return p as Button
		p = p.get_parent()
	return null

## A label / button shows all of its text: no "...", no clipped line, a wrapped label inside its box.
func _whole(c: Control, txt: String, tag: String) -> void:
	var f := c.get_theme_font("font")
	var fs := c.get_theme_font_size("font_size")
	if c is Label:
		var l := c as Label
		if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
			check(l.size.y + 0.5 >= l.get_line_count() * l.get_line_height(), "%s '%s' wraps taller than its box" % [tag, txt])
		else:
			var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if l.clip_text or l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
				check(w <= l.size.x + 1.0, "%s '%s' cut off (%.0f > %.0f)" % [tag, txt, w, l.size.x])
			else:
				check(l.size.x + 0.5 >= l.get_minimum_size().x, "%s '%s' squeezed" % [tag, txt])
	elif c is Button:
		if txt.contains("\n"): return
		var w2 := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		check(w2 <= c.size.x - 8.0, "%s button '%s' text %.0f is tight in %.0f" % [tag, txt, w2, c.size.x])
