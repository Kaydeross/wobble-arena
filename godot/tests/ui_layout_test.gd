extends SceneTree
## Title-screen layout test (headless): instances scenes/main.tscn in a viewport the size of the stretched canvas
## for several window sizes (iPhone landscape 852x393, 1170x540, 1280x720, iPhone portrait 390x844), with and
## without phone safe-area insets, on every screen (title, online panel, settings sheet, the host-a-room sheet, the
## lobby sheet, the five setup-wizard pages),
## and checks that the controls stay inside the safe area, do not overlap each other, can be reached (card grids
## scroll), that no label is squeezed below its text size and that the title / wizard frame labels are not cut off
## ("…"). Then drives the wizard (step names, navigation, saved choices, arena moved by a game type, team bot counts),
## the card grid scrolling (mouse drag and touch drag scroll + fling and never pick a card, a tap picks one, the
## selected card is scrolled into view) and the character stage (one SubViewport, renders only on its page).
##   godot --headless --path godot --script res://tests/ui_layout_test.gd -- --no-save   (npm run test:godot-ui)

const BASE := Vector2(1170, 540)   ## project.godot viewport size (stretch canvas_items, aspect expand)
## window size in points, safe-area insets in points (left, top, right, bottom) like an iPhone 15 / 16
const CASES := [
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(1170, 540), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(1280, 720), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(390, 844), [0.0, 59.0, 0.0, 34.0]],
]
## Screens: the title, its online panel, the settings sheet and the five setup-wizard pages.
const SCREENS := ["title", "online", "settings", "host", "lobby", "w0", "w1", "w2", "w3", "w4"]
## Title column blocks (paths under Main) that must not overlap each other.
const BLOCKS := ["Safe/Col/Top/Logo", "Safe/Col/Top/GuestChip", "Safe/Col/Top/Gear", "Safe/Col/Body", "Safe/Col/Tip", "Safe/Col/Build"]
const HOME := ["Safe/Col/Body/Home/Play", "Safe/Col/Body/Home/Online"]
const OB := "Safe/Col/Body/Online/Box/"
## the online panel (back, server, room, name, join, login fields, status, roster): also must not overlap each other
const ONLINE := [OB + "Head/Back", OB + "ServerRow/Server", OB + "RoomRow/Room", OB + "RoomRow/Name", OB + "RoomRow/Join", OB + "RoomRow/Host",
	OB + "AcctRow/User", OB + "AcctRow/Pass", OB + "AcctRow/Login", OB + "Status", OB + "Roster"]
const SHEET := ["Sheet/Center/Card/Box/Fps", "Sheet/Center/Card/Box/Done"]
const HB := "HostSheet/Center/Card/Box/"
## host a room: name, who can join, seats, bots, Cancel / Create room
const HOSTS := [HB + "Title", HB + "RoomName", HB + "Vis/P0", HB + "Vis/P1", HB + "Max/P2", HB + "Max/P8", HB + "Bots/P0", HB + "Bots/P7",
	HB + "Hint", HB + "Buttons/Cancel", HB + "Buttons/Create"]
const LB := "Lobby/Center/Card/Box/"
## the lobby: room, code, players, info, Leave / Start
const LOBBY := [LB + "Title", LB + "Code", LB + "Players", LB + "Info", LB + "Buttons/Leave", LB + "Buttons/Start"]
const W := "Safe/Wizard/"
## wizard frame: header, page, footer buttons (must not overlap each other)
const WFRAME := [W + "Head/Title", W + "Head/Step", W + "Pages", W + "Foot/Back", W + "Foot/Steps", W + "Foot/Next"]

const STEP_TEXT := ["1 Game type", "2 Arena", "3 Players", "4 Character", "5 Start"]

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

## The 2D canvas size Godot uses for a window (stretch mode canvas_items, aspect expand).
static func canvas_size(win: Vector2) -> Vector2:
	var k := minf(win.x / BASE.x, win.y / BASE.y)
	return (win / k).round()

func _run() -> void:
	var st: Node = root.get_node("Settings")
	for kv in [["offline_map", "arena"], ["mode", "classic"], ["bots", 3], ["difficulty", "normal"], ["class", "wobbler"]]:
		st.set_value(kv[0], kv[1])
	for c: Array in CASES:
		for with_insets in [false, true]:
			for scr: String in SCREENS:
				await _case(c[0], c[1] if with_insets else [0.0, 0.0, 0.0, 0.0], scr)
	SafeArea.override = []
	await _logic()
	print("UI ok" if fails == 0 else "UI layout checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _no_overlap(rects: Dictionary, keys: Array, tag: String) -> void:
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = rects[keys[i]]
			var b: Rect2 = rects[keys[j]]
			check(not a.grow(-0.5).intersects(b.grow(-0.5)), "%s %s %s overlaps %s %s" % [tag, keys[i], a, keys[j], b])

func _case(win: Vector2, ins_pt: Array, scr: String) -> void:
	var cs := canvas_size(win)
	var k := cs.x / win.x
	var ins := [ins_pt[0] * k, ins_pt[1] * k, ins_pt[2] * k, ins_pt[3] * k]
	SafeArea.override = ins
	var vp := SubViewport.new()
	vp.size = Vector2i(cs)
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	var wiz := scr.begins_with("w")
	if scr == "online":
		main.show_tab(true)
		main.get_node(OB + "Roster").text = "In the room: Alice, Bob, Carol"
	elif scr == "settings":
		main.show_settings(true)
	elif scr == "host":
		main.show_tab(true)
		main.show_host(true)
	elif scr == "lobby":
		main.show_tab(true)
		main.show_lobby(true)
		main.get_node(LB + "Code").text = "Room code ABCDE"
		main.get_node(LB + "Info").text = "8 / 8 players · empty seats get bots"
		for i in 8:
			var pl := Label.new()
			pl.text = "Wobbly name %d%s" % [i, "  (host)" if i == 0 else ""]
			pl.add_theme_font_size_override("font_size", 20)
			main.get_node(LB + "Players").add_child(pl)
	elif wiz:
		main.open_wizard(int(scr.substr(1)))
	for i in 4:
		await process_frame
	var tag := "%dx%d%s %s" % [win.x, win.y, " safe" if ins_pt != [0.0, 0.0, 0.0, 0.0] else "", scr]
	var safe := Rect2(Vector2(ins[0], ins[1]), cs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	var inside: Array = []
	var groups: Array = []      ## lists of paths that must not overlap each other
	if wiz:
		inside = WFRAME.duplicate()
		for b in main.wizard.step_bs: inside.append(W + "Foot/Steps/" + b.name)
		groups.append(WFRAME)
		groups.append(inside.slice(WFRAME.size()))
	else:
		var on_panel := scr in ["online", "host", "lobby"]
		inside = BLOCKS + (ONLINE if on_panel else HOME)
		groups.append(BLOCKS)
		if scr == "online": groups.append(ONLINE)
		elif not on_panel: groups.append(HOME)
		if scr == "host": inside = inside + HOSTS; groups.append(HOSTS)
		if scr == "lobby": inside = inside + LOBBY; groups.append(LOBBY)
		if scr == "settings": inside = inside + SHEET; groups.append(SHEET)
	var rects := {}
	for p: String in inside:
		var n: Control = main.get_node(p)
		var r := n.get_global_rect()
		rects[p] = r
		check(n.is_visible_in_tree(), "%s %s visible" % [tag, p])
		check(r.size.x >= 1.0 and r.size.y >= 1.0, "%s %s has a size (%s)" % [tag, p, r])
		check(safe.grow(0.5).encloses(r), "%s %s %s inside the safe area %s" % [tag, p, r, safe])
	for g: Array in groups: _no_overlap(rects, g, tag)
	if wiz: _page(main, int(scr.substr(1)), safe, tag)
	# the whole column fits (containers would otherwise overflow past the bottom)
	var col: Control = main.wizard if wiz else main.get_node("Safe/Col")
	check(col.get_combined_minimum_size().y <= safe.size.y + 0.5, "%s column min height %.0f fits %.0f" % [tag, col.get_combined_minimum_size().y, safe.size.y])
	_labels_fit(main, tag)
	if wiz:
		_not_cut(main.wizard.get_node("Head"), tag)
		_not_cut(main.wizard.get_node("Foot"), tag)
		if scr == "w4": _not_cut(main.wizard.pages[4], tag)
		for i in main.wizard.step_bs.size():
			var sb: Button = main.wizard.step_bs[i]
			check(sb.text == STEP_TEXT[i], "%s step pill %d says '%s'" % [tag, i + 1, sb.text])
			check(sb.size.x + 0.5 >= sb.get_minimum_size().x, "%s step pill '%s' squeezed" % [tag, sb.text])
		_no_word(main.wizard, "fighter", tag)
	else:
		_not_cut(main.get_node("Safe/Col"), tag)
		if scr == "title":
			check(main.get_node("Safe/Col/Body/Home/Play/Stack/Big").text == "Play", "%s Play button says Play" % tag)
			check(main.get_node("Safe/Col/Body/Home/Online/Stack/Big").text == "Play online with friends", "%s online button label" % tag)
			check(main.who.text == "Guest", "%s chip says Guest (%s)" % [tag, main.who.text])
			_no_word(main.get_node("Safe/Col/Top"), "offline", tag, true)   # no status pill saying "Offline"
	print("UI %s canvas %dx%d checked" % [tag, cs.x, cs.y])
	vp.queue_free()
	await process_frame

## One wizard page: every control is reachable. Card grids: no horizontal overflow, cards apart, the first row fully
## visible and every card reachable by scrolling; pill rows and summary rows: inside the safe area and apart.
func _page(main: Control, p: int, safe: Rect2, tag: String) -> void:
	var w = main.wizard
	var page: Control = w.pages[p]
	check(page.is_visible_in_tree(), "%s page %d visible" % [tag, p])
	var sc: ScrollContainer = page.get_node_or_null("Frame/Scroll")
	var free: Array = []        ## controls outside the scroll area
	if sc:
		var g: GridContainer = sc.get_node("Grid")
		var sr := sc.get_global_rect()
		check(safe.grow(0.5).encloses(sr), "%s scroll %s inside the safe area" % [tag, sr])
		check(g.get_combined_minimum_size().x <= sr.size.x + 0.5, "%s grid min width %.0f fits %.0f" % [tag, g.get_combined_minimum_size().x, sr.size.x])
		var cards: Array = g.get_children()
		check(cards.size() > 0, "%s page %d has cards" % [tag, p])
		var bottom := 0.0
		for i in cards.size():
			var c: Control = cards[i]
			var r := c.get_global_rect()
			bottom = maxf(bottom, c.position.y + c.size.y)
			check(r.position.x >= sr.position.x - 0.5 and r.end.x <= sr.end.x + 0.5, "%s card %s %s within the scroll width %s" % [tag, c.name, r, sr])
			check(c.size.y >= 90.0 and c.size.x >= 150.0, "%s card %s big enough to tap (%s)" % [tag, c.name, c.size])
			if i < g.columns: check(sr.grow(0.5).encloses(r), "%s first-row card %s visible" % [tag, c.name])
			for j in range(i + 1, cards.size()):
				check(not r.grow(-0.5).intersects((cards[j] as Control).get_global_rect().grow(-0.5)), "%s cards %s and %s overlap" % [tag, c.name, cards[j].name])
		var max_scroll := maxf(0.0, g.size.y - sc.size.y)
		check(bottom - sc.size.y <= max_scroll + 0.5, "%s every card reachable (bottom %.0f, scroll %.0f)" % [tag, bottom, max_scroll])
	for c in page.get_children():
		if c == sc or c.name == "Frame": continue
		if c is HBoxContainer:
			for b in c.get_children(): if b is Button: free.append(b)
		elif c is Button: free.append(c)
	for b: Control in free:
		var r := b.get_global_rect()
		check(safe.grow(0.5).encloses(r), "%s %s %s inside the safe area" % [tag, b.name, r])
		check(r.size.y >= 44.0, "%s %s tall enough to tap (%s)" % [tag, b.name, r.size])
	for i in free.size():
		for j in range(i + 1, free.size()):
			check(not (free[i] as Control).get_global_rect().grow(-0.5).intersects((free[j] as Control).get_global_rect().grow(-0.5)), "%s %s overlaps %s" % [tag, free[i].name, free[j].name])

## Wizard behaviour: step names, navigation, remembered choices, the arena moving when a game type does not allow it,
## team bot counts; then scrolling and the character stage.
func _logic() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await process_frame
	var w = main.wizard
	var st: Node = root.get_node("Settings")
	main.play.pressed.emit()
	check(w.visible and not main.get_node("Safe/Col").visible and w.page == 0, "Play opens the wizard on the game type page")
	check(w.title_l.text == "Pick a game type", "page 1 is the game type (%s)" % w.title_l.text)
	var names: Array = []
	for m: String in w.modes(): names.append(m)
	for m: String in ModeRules.PLAYABLE: check(names.has(m), "wizard offers %s" % m)
	check(names.has("construction"), "wizard offers construction")
	check(w._mode_bs.size() == names.size(), "a card per mode")
	check(w._map_bs.size() == w.maps_for("classic").size(), "a card per classic arena")
	w.next_b.pressed.emit()
	check(w.page == 1 and w.title_l.text == "Pick an arena", "Next goes to the arena")
	w.set_map("park")
	w.back_b.pressed.emit()
	check(w.page == 0, "Back goes to the game type")
	w.set_mode("ninja")
	check(w.maps_for("ninja").has(w.map_id) and w.map_id != "park", "ninja moves off Bouncy Rooftop (%s)" % w.map_id)
	check(w.note != "" and w.note_l.text == w.note, "the move is explained: '%s'" % w.note)
	check(w._map_bs.size() == w.maps_for("ninja").size(), "the arena page follows the game type")
	check(str(st.get_value("offline_map")) == w.map_id and str(st.get_value("mode")) == "ninja", "map + mode saved")
	w.set_mode("classic")
	check(w.map_id == "park", "back to the picked arena in classic (%s)" % w.map_id)
	w.set_mode("t2")
	check(w.bot_total() == 3, "2v2 plays 3 bots")
	check(w._bot_bs[3].button_pressed and w._bot_bs[1].disabled, "2v2 locks the bot count")
	w.set_mode("tdm")                    # Godot-only modes: Team Deathmatch sizes the teams, odd bot counts only
	w.set_bots(4)
	check(w.bot_total() == 5 and w._bot_bs[5].button_pressed and w._bot_bs[4].disabled and not w._bot_bs[7].disabled, "TDM keeps the sides even (%d)" % w.bot_total())
	check(w.players_hint.text.contains("3 vs 3"), "TDM hint: %s" % w.players_hint.text)
	w.set_mode("chaos")
	check(w.bot_total() == 9 and w._bot_bs[7].disabled and w.players_hint.text.contains("5 vs 5"), "Chaos locks 5 v 5 (%d)" % w.bot_total())
	var cm: Array = w.maps_for("chaos")
	check(cm.size() >= 4 and cm.all(func(id: String) -> bool: return ModeRules.CHAOS_MAPS.has(id)) and cm.has(w.map_id), "Chaos on the big arenas only (%s)" % [cm])
	check(w.maps_for("sudden").has("shrink") and w.maps_for("sudden").has("arena"), "Sudden Death on every arena incl. the shrinking ones")
	w.set_mode("t2")
	w.set_mode("classic")
	w.set_bots(5); w.set_diff("hard"); w.set_class("bruiser"); w.set_dyn("tilt")
	check(int(st.get_value("bots")) == 5 and str(st.get_value("difficulty")) == "hard" and str(st.get_value("class")) == "bruiser" \
		and str(st.get_value("dyn")) == "tilt", "players, skill, class and floor saved")
	w.go(3)
	check(w.title_l.text == "Pick your character", "page 4 is the character (%s)" % w.title_l.text)
	w.go(4)
	check(w.next_b.text == "Start" and w.step_bs[4].text == "5 Start", "last page is Start")
	var sums: Array = []
	for l: Label in w._sum_vals: sums.append(l.text)
	check(sums[0].begins_with("Classic") and sums[1] == "Bouncy Rooftop" and sums[2].contains("5 bots") and sums[3] == "Bruiser", "summary lists the picks: %s" % [sums])
	w._sum_bs[1].pressed.emit()
	check(w.page == 1, "a summary row jumps to its page")
	w.go(0)
	w.back_b.pressed.emit()
	check(not w.visible and main.get_node("Safe/Col").visible, "Back on page 1 returns to the title")
	check(main.play.tooltip_text.contains("Bouncy Rooftop"), "Play remembers the setup (%s)" % main.play.tooltip_text)
	# a fresh title remembers everything
	var m2: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(m2)
	await process_frame
	var w2 = m2.wizard
	check(w2.map_id == "park" and w2.mode_id == "classic" and w2.bots == 5 and w2.diff == "hard" and w2.cls == "bruiser", "choices remembered")
	m2.queue_free()
	main.gear.pressed.emit()
	check(main.sheet.visible, "gear opens the settings sheet")
	main.fps_toggle.button_pressed = true
	check(bool(st.get_value("show_fps")), "Show FPS saved")
	main.fps_toggle.button_pressed = false
	main.show_settings(false)
	await _scrolling(vp, main)
	await _stage(main)
	print("UI wizard logic checked")
	vp.queue_free()
	await process_frame

func _mouse(vp: SubViewport, pos: Vector2, pressed: Variant, device := 0) -> void:
	var e: InputEvent
	if pressed == null:
		var mm := InputEventMouseMotion.new()
		mm.position = pos; mm.global_position = pos; mm.button_mask = MOUSE_BUTTON_MASK_LEFT
		e = mm
	else:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT; mb.pressed = pressed; mb.position = pos; mb.global_position = pos
		mb.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e = mb
	e.device = device
	vp.push_input(e)

## A finger as the engine delivers it: ScreenTouch / ScreenDrag plus the emulated mouse events (device -1).
func _finger(vp: SubViewport, pos: Vector2, pressed: Variant) -> void:
	if pressed == null:
		var d := InputEventScreenDrag.new()
		d.position = pos
		vp.push_input(d)
	else:
		var t := InputEventScreenTouch.new()
		t.position = pos; t.pressed = pressed
		vp.push_input(t)
	_mouse(vp, pos, pressed, InputEvent.DEVICE_ID_EMULATION)

func _send(kind: String, vp: SubViewport, pos: Vector2, pressed: Variant) -> void:
	if kind == "mouse": _mouse(vp, pos, pressed)
	else: _finger(vp, pos, pressed)

## Arena grid: a drag (mouse, then touch) scrolls, flings on and never picks a card; a tap picks the card under it;
## opening the page scrolls the selected card into view.
func _scrolling(vp: SubViewport, main: Control) -> void:
	var w = main.wizard
	main.open_wizard(1)
	for i in 3: await process_frame
	var sc: DragScroll = w.scroll_of(1)
	check(sc.max_scroll() > 100.0, "arena grid scrolls (%.0f)" % sc.max_scroll())
	var before: String = w.map_id
	for kind: String in ["mouse", "touch"]:
		sc.velocity = 0.0
		sc.set_process(false)
		sc.scroll_vertical = 0
		await process_frame
		var s0 := sc.scroll_vertical
		var sr := sc.get_global_rect()
		var p := Vector2(sr.position.x + sr.size.x * 0.4, sr.end.y - 40.0)
		check(sc.card_at(p) != null, "%s: drag starts on a card" % kind)
		_send(kind, vp, p, true)
		for k in range(1, 9): _send(kind, vp, p - Vector2(0, 22.0 * k), null)
		var s1 := sc.scroll_vertical
		_send(kind, vp, p - Vector2(0, 22.0 * 8), false)
		check(s1 > s0 + 100, "%s drag scrolls (%d -> %d)" % [kind, s0, s1])
		check(w.map_id == before, "%s drag does not pick a card (%s)" % [kind, w.map_id])
		check(sc.velocity > 0.0 or sc.scroll_vertical >= sc.max_scroll() - 1, "%s release flings (v %.0f)" % [kind, sc.velocity])
		for i in 3: await process_frame
		check(sc.scroll_vertical >= s1, "%s fling keeps going (%d -> %d)" % [kind, s1, sc.scroll_vertical])
		check(w.map_id == before, "%s fling does not pick a card" % kind)
	# a tap (a few px of jitter) picks; so does a mouse click
	sc.velocity = 0.0
	sc.set_process(false)
	sc.scroll_vertical = 0
	await process_frame
	var sr2 := sc.get_global_rect()
	var tp := Vector2(sr2.position.x + sr2.size.x * 0.6, sr2.position.y + 60.0)
	var card: Control = sc.card_at(tp)
	check(card != null and String(card.name) != before, "tap target is another card")
	_finger(vp, tp, true); _finger(vp, tp + Vector2(4, 3), null); _finger(vp, tp + Vector2(4, 3), false)
	check(card != null and w.map_id == String(card.name), "a tap picks the card (%s)" % w.map_id)
	var cp := sr2.position + Vector2(40, 40)
	_mouse(vp, cp, true); _mouse(vp, cp, false)
	check(w.map_id == String(sc.card_at(cp).name), "a mouse click picks the card")
	# the selected card is in view when the page opens
	var last: String = w.maps_for(w.mode_id)[-1]
	w.set_map(last)
	sc.scroll_vertical = 0
	w.go(0)
	w.go(1)
	for i in 3: await process_frame
	var r: Rect2 = w._map_bs[last].get_global_rect()
	check(sc.get_global_rect().grow(0.5).encloses(r), "selected arena %s scrolled into view (%s in %s)" % [last, r, sc.get_global_rect()])
	check(w.selected_card(1) == w._map_bs[last], "selected_card")
	w.set_map("park")

## The character page: a 3D render per class card, one shared stage that renders only on that page.
func _stage(main: Control) -> void:
	var w = main.wizard
	var vps: Array = w.find_children("*", "SubViewport", true, false)
	check(vps.size() == 1 and vps[0] == w.stage, "one shared SubViewport for the character renders (%d)" % vps.size())
	check(w.stage.get_node("Pivot").get_child(0) is Wobbler, "the stage holds the real Wobbler")
	check(w.stage.has_node("Sun") and w.stage.has_node("Rim") and (w.stage.get_node("Sun") as DirectionalLight3D).shadow_enabled, "sun with shadow + rim light")
	main.open_wizard(3)
	await process_frame
	check(w.stage.active, "stage runs on the character page")
	for id: String in root.get_node("Content").classes:
		check(w._class_art.has(id) and w._class_bs[id].find_children("Render", "TextureRect", true, false).size() == 1, "card %s has a render" % id)
	check(w._class_art[w.cls].texture == w.stage.get_texture(), "the selected card shows the live stage")
	w.set_class("kid")
	check(w.stage.current == "kid" and w._class_art["kid"].texture == w.stage.get_texture(), "picking a character swaps the stage model")
	w.go(4)
	check(not w.stage.active and w.stage.render_target_update_mode == SubViewport.UPDATE_DISABLED, "stage stops off its page")
	w.set_class("bruiser")
	main.close_wizard()

## No word `word` (any case) in the labels / buttons under `n`.
func _no_word(n: Node, word: String, tag: String, visible_only := false) -> void:
	if (n is Label or n is Button) and (not visible_only or (n as Control).is_visible_in_tree()):
		var t: String = n.text
		check(not t.to_lower().contains(word), "%s '%s' says %s" % [tag, t, word])
	for c in n.get_children(): _no_word(c, word, tag, visible_only)

## Visible labels that clip with an ellipsis still show their whole text (nothing cut to "…").
func _not_cut(n: Node, tag: String) -> void:
	if n is Label and n.is_visible_in_tree() and n.clip_text and n.text != "":
		var l := n as Label
		var f := l.get_theme_font("font")
		var need := f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x
		check(need <= l.size.x + 1.0, "%s label '%s' cut off (%.0f > %.0f)" % [tag, l.text, need, l.size.x])
	for c in n.get_children(): _not_cut(c, tag)

## No label is narrower than its text (clipped) unless it is meant to clip or wrap.
func _labels_fit(n: Node, tag: String) -> void:
	if n is Label and n.is_visible_in_tree():
		var l := n as Label
		if not l.clip_text and l.autowrap_mode == TextServer.AUTOWRAP_OFF and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var need := l.get_minimum_size()
			check(l.size.x + 0.5 >= need.x and l.size.y + 0.5 >= need.y, "%s label '%s' clipped (%s < %s)" % [tag, l.text, l.size, need])
	for c in n.get_children():
		_labels_fit(c, tag)
