extends SceneTree
## Title-screen layout test (headless): instances scenes/main.tscn in a viewport the size of the stretched canvas
## for several window sizes (iPhone landscape 852x393, 1170x540, 1280x720, iPhone portrait 390x844), with and
## without phone safe-area insets, on every screen (title, online panel, settings sheet, the five setup-wizard pages),
## and checks that the controls stay inside the safe area, do not overlap each other, can be reached (card grids
## scroll) and that no label is squeezed below its text size. Then drives the wizard (navigation, saved choices,
## map moved by a mode, team bot counts).
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
const SCREENS := ["title", "online", "settings", "w0", "w1", "w2", "w3", "w4"]
## Title column blocks (paths under Main) that must not overlap each other.
const BLOCKS := ["Safe/Col/Top/Logo", "Safe/Col/Top/GuestChip", "Safe/Col/Top/Gear", "Safe/Col/Body", "Safe/Col/Tip", "Safe/Col/Build"]
const HOME := ["Safe/Col/Body/Home/Play", "Safe/Col/Body/Home/Online"]
const OB := "Safe/Col/Body/Online/Box/"
## the online panel (back, server, room, name, join, login fields, status, roster): also must not overlap each other
const ONLINE := [OB + "Head/Back", OB + "ServerRow/Server", OB + "RoomRow/Room", OB + "RoomRow/Name", OB + "RoomRow/Join",
	OB + "RoomRow/Create", OB + "AcctRow/User", OB + "AcctRow/Pass", OB + "AcctRow/Login", OB + "Status", OB + "Roster"]
const SHEET := ["Sheet/Center/Card/Box/Fps", "Sheet/Center/Card/Box/Done"]
const W := "Safe/Wizard/"
## wizard frame: header, page, footer buttons (must not overlap each other)
const WFRAME := [W + "Head/Title", W + "Head/Step", W + "Pages", W + "Foot/Back", W + "Foot/Steps", W + "Foot/Next"]

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
		inside = BLOCKS + (ONLINE if scr == "online" else HOME)
		groups.append(BLOCKS)
		if scr == "online": groups.append(ONLINE)
		else: groups.append(HOME)
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
	print("UI %s canvas %dx%d checked" % [tag, cs.x, cs.y])
	vp.queue_free()
	await process_frame

## One wizard page: every control is reachable. Card grids: no horizontal overflow, cards apart, the first row fully
## visible and every card reachable by scrolling; pill rows and summary rows: inside the safe area and apart.
func _page(main: Control, p: int, safe: Rect2, tag: String) -> void:
	var w = main.wizard
	var page: Control = w.pages[p]
	check(page.is_visible_in_tree(), "%s page %d visible" % [tag, p])
	var sc: ScrollContainer = page.get_node_or_null("Scroll")
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
		if c == sc: continue
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

## Wizard behaviour: navigation, remembered choices, the map moving when a mode does not allow it, team bot counts.
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
	check(w.visible and not main.get_node("Safe/Col").visible and w.page == 0, "PLAY opens the wizard on the arena page")
	var names: Array = []
	for m: String in w.modes(): names.append(m)
	for m: String in ModeRules.PLAYABLE: check(names.has(m), "wizard offers %s" % m)
	check(names.has("construction"), "wizard offers construction")
	check(w._mode_bs.size() == names.size(), "a card per mode")
	check(w._map_bs.size() == w.maps_for("classic").size(), "a card per classic arena")
	w.set_map("park")
	w.next_b.pressed.emit()
	check(w.page == 1, "Next goes to the game type")
	w.set_mode("ninja")
	check(w.maps_for("ninja").has(w.map_id) and w.map_id != "park", "ninja moves off Bouncy Rooftop (%s)" % w.map_id)
	check(w.note != "" and w.note_l.text == w.note, "the move is explained: '%s'" % w.note)
	check(str(st.get_value("offline_map")) == w.map_id and str(st.get_value("mode")) == "ninja", "map + mode saved")
	w.set_mode("classic")
	check(w.map_id == "park", "back to the picked arena in classic (%s)" % w.map_id)
	w.set_mode("t2")
	check(w.bot_total() == 3, "2v2 plays 3 bots")
	check(w._bot_bs[3].button_pressed and w._bot_bs[1].disabled, "2v2 locks the bot count")
	w.set_mode("classic")
	w.set_bots(5); w.set_diff("hard"); w.set_class("bruiser"); w.set_dyn("tilt")
	check(int(st.get_value("bots")) == 5 and str(st.get_value("difficulty")) == "hard" and str(st.get_value("class")) == "bruiser" \
		and str(st.get_value("dyn")) == "tilt", "players, skill, class and floor saved")
	w.go(4)
	check(w.next_b.text == "START", "last page says START")
	check(w._sum_vals[2].text.contains("5 bots") and w._sum_vals[3].text == "Bruiser", "summary lists the picks")
	w._sum_bs[0].pressed.emit()
	check(w.page == 0, "a summary row jumps to its page")
	w.back_b.pressed.emit()
	check(not w.visible and main.get_node("Safe/Col").visible, "Back on page 1 returns to the title")
	check(main.get_node("Safe/Col/Body/Home/Play/Stack/Sub").text.contains("Bouncy Rooftop"), "PLAY shows the setup")
	# a fresh title remembers everything
	var m2: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(m2)
	await process_frame
	var w2 = m2.wizard
	check(w2.map_id == "park" and w2.mode_id == "classic" and w2.bots == 5 and w2.diff == "hard" and w2.cls == "bruiser", "choices remembered")
	main.gear.pressed.emit()
	check(main.sheet.visible, "gear opens the settings sheet")
	main.fps_toggle.button_pressed = true
	check(bool(st.get_value("show_fps")), "Show FPS saved")
	main.fps_toggle.button_pressed = false
	print("UI wizard logic checked")
	vp.queue_free()
	await process_frame

## No label is narrower than its text (clipped) unless it is meant to clip or wrap.
func _labels_fit(n: Node, tag: String) -> void:
	if n is Label and n.is_visible_in_tree():
		var l := n as Label
		if not l.clip_text and l.autowrap_mode == TextServer.AUTOWRAP_OFF and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var need := l.get_minimum_size()
			check(l.size.x + 0.5 >= need.x and l.size.y + 0.5 >= need.y, "%s label '%s' clipped (%s < %s)" % [tag, l.text, l.size, need])
	for c in n.get_children():
		_labels_fit(c, tag)
