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
## The Locker (5 tabs) and the Shop (2 tabs) get the same layout checks (ui/locker.gd: header, preview, tabs, card
## grid, footer), and the title's Locker / Shop row.
## The Account sheet (ui/account_sheet.gd, from the title chip): every page (guest, sign up, log in, forgot password,
## recovery code, signed in, change password, delete, conflict) inside the safe area, nothing overlapping, touch
## targets at least 44 pt tall; _logic checks the chip opens it and the delete button waits for the typed word.
## Polish pass: the room browser in the online panel (loading, a full list with greyed-out rows, empty, server
## unreachable), every Settings section, the Controls picture, the three how-to cards and the pause menu (menu,
## quit question, its Settings and Controls pages) at every size, also iPhone 8 / SE landscape (667x375): inside the
## safe area, nothing overlapping, rows reachable by scrolling, touch targets at least TOUCH_PX tall.
##   godot --headless --path godot --script res://tests/ui_layout_test.gd -- --no-save   (npm run test:godot-ui)

const BASE := Vector2(1170, 540)   ## project.godot viewport size (stretch canvas_items, aspect expand)
## window size in points, safe-area insets in points (left, top, right, bottom) like an iPhone 15 / 16
const CASES := [
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(1170, 540), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(1280, 720), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(390, 844), [0.0, 59.0, 0.0, 34.0]],
]
## Screens: the title, its online panel, the settings sheet and the five setup-wizard pages.
const SCREENS := ["title", "online", "rooms", "rooms-empty", "rooms-error", "set-controls", "set-camera", "set-graphics",
	"set-audio", "set-gameplay", "set-account", "set-about", "help", "intro0", "intro1", "intro2", "pause", "pause-confirm",
	"pause-settings", "pause-help", "host", "host-mode", "host-rules", "lobby", "w0", "w1", "w2", "w3", "w4", "l0", "l1", "l2", "l3", "l4", "s0", "s1",
	"a-guest", "a-signup", "a-login", "a-reset", "a-code", "a-signed", "a-password", "a-delete", "a-conflict"]
const SIGNED := ["a-signed", "a-password", "a-delete", "a-conflict"]
const MIN_TOUCH := 44.0      ## pt: Apple's minimum touch target
## Touch targets on the new pages, in canvas px: 44 pt at the reference iPhone landscape (852x393 -> canvas 1171x540).
## (667x375 is width-bound: its canvas is 1170x658, so the same buttons are about 34 pt there.)
const TOUCH_PX := 60.0
## Title column blocks (paths under Main) that must not overlap each other.
const BLOCKS := ["Safe/Col/Top/Logo", "Safe/Col/Top/GuestChip", "Safe/Col/Top/Gear", "Safe/Col/Body", "Safe/Col/Tip", "Safe/Col/Build"]
const HOME := ["Safe/Col/Body/Home/Play", "Safe/Col/Body/Home/Online", "Safe/Col/Body/Home/More/Locker", "Safe/Col/Body/Home/More/Shop"]
const OB := "Safe/Col/Body/Online/Box/"
## the online panel (back, name, the room list, join with a code, host, account, status, roster): must not overlap
const ONLINE := [OB + "Head/Back", OB + "Head/Title", OB + "Head/Name", OB + "Main/Rooms/Head/Refresh", OB + "Main/Rooms/Scroll",
	OB + "Main/Side/CodeL", OB + "Main/Side/CodeRow/Room", OB + "Main/Side/CodeRow/Join", OB + "Main/Side/Host", OB + "Main/Side/Account",
	OB + "Foot/Status", OB + "Foot/Roster"]
## mock public rooms: a normal one, one playing, a full one, another game version, and enough to scroll
const MOCK_ROOMS := [
	{"id": "r1", "name": "Wobble Party", "host": "Alice", "mode": "classic", "modeName": "Classic", "map": "Arena", "n": 3, "max": 8, "started": false, "build": "b77.0"},
	{"id": "r2", "name": "Knockout Kings with a very long room name", "host": "Bob", "mode": "t2", "modeName": "2 vs 2", "map": "Bouncy Rooftop", "n": 2, "max": 4, "started": true, "build": "b77.0"},
	{"id": "r3", "name": "Full House", "host": "Carol", "mode": "classic", "modeName": "Classic", "map": "Farm", "n": 4, "max": 4, "started": false, "build": "b77.0"},
	{"id": "r4", "name": "Old Version Room", "host": "Dan", "mode": "classic", "modeName": "Classic", "map": "Volcano", "n": 1, "max": 6, "started": false, "build": "b70.2"},
	{"id": "r5", "name": "Late Night", "host": "Eve", "mode": "sudden", "modeName": "Sudden Death", "map": "Candy", "n": 1, "max": 8, "started": false, "build": ""},
	{"id": "r6", "name": "Casual", "host": "Finn", "mode": "classic", "modeName": "Classic", "map": "Dojo", "n": 1, "max": 8, "started": false, "build": "b77.0"},
]
const HB := "HostSheet/Center/Card/Box/"
## host a room: tabs (Room / Mode / Rules), the arena hint, Cancel / Create room
const HOST_FRAME := [HB + "Title", HB + "Tabs/Room", HB + "Tabs/Mode", HB + "Tabs/Rules", HB + "Hint", HB + "Buttons/Cancel", HB + "Buttons/Create"]
## the three tabs: Room (name, who can join, seats, bots), Mode (game type, K.O. limit, floor), Rules (health, gravity,
## ammo, knockback, crates)
const HOST_TABS := {
	"host": [HB + "Room/RoomName", HB + "Room/Vis/P0", HB + "Room/Vis/P1", HB + "Room/Max/P2", HB + "Room/Max/P8", HB + "Room/Bots/P0", HB + "Room/Bots/P7"],
	"host-mode": [HB + "Mode/Game/Prev", HB + "Mode/Game/Name", HB + "Mode/Game/Next", HB + "Mode/ModeHint", HB + "Mode/Lim/P0", HB + "Mode/Lim/P5",
		HB + "Mode/Floor/Poff", HB + "Mode/Floor/Pdrift"],
	"host-rules": [HB + "Rules/Hp/P100", HB + "Rules/Hp/P500", HB + "Rules/Pair/Grav/P0", HB + "Rules/Pair/Grav/P2", HB + "Rules/Pair/Inf/P0",
		HB + "Rules/Pair/Inf/P1", HB + "Rules/Kb/P0", HB + "Rules/Kb/P4", HB + "Rules/Crate/Pslow", HB + "Rules/Crate/Pchaos"],
}
const LB := "Lobby/Center/Card/Box/"
## the lobby: room, code, players, info, Leave / Start
const LOBBY := [LB + "Title", LB + "Code", LB + "Players", LB + "Info", LB + "Rules", LB + "Buttons/Leave", LB + "Buttons/Start"]
const W := "Safe/Wizard/"
## wizard frame: header, page, footer buttons (must not overlap each other)
const WFRAME := [W + "Head/Title", W + "Head/Step", W + "Pages", W + "Foot/Back", W + "Foot/Steps", W + "Foot/Next"]

const L := "Safe/Locker/"
## Locker / Shop frame (must not overlap each other); the tab buttons are added per mode
const LFRAME := [L + "Head/Title", L + "Head/Sub", L + "Head/Coins", L + "Head/Switch", L + "Body/Preview", L + "Body/Right/Tabs",
	L + "Body/Right/Frame", L + "Foot/Back", L + "Foot/Action"]

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
	main.browser.auto_refresh = false
	var wiz := scr.begins_with("w")
	var lock := scr.begins_with("l") or scr.begins_with("s") and not scr.begins_with("set-")
	var acct := scr.begins_with("a-")
	var over: Control = null          ## a new page / sheet checked generically (its visible controls)
	var over_col: Control = null      ## its column (must fit the height)
	var over_scroll: ScrollContainer = null
	if scr.begins_with("pause"):
		var pm: Control = load("res://ui/pause_menu.gd").new()
		main.add_child(pm)
		await process_frame
		pm.open()
		over = pm.card; over_col = pm.card
		if scr == "pause-confirm": pm.ask_quit(); over = pm.confirm; over_col = pm.confirm
		elif scr == "pause-settings": pm.open_settings(); over = pm.settings; over_col = pm.settings.col; over_scroll = pm.settings.scroll
		elif scr == "pause-help": pm.open_help(); over = pm.help; over_col = pm.help.col
	elif scr.begins_with("set-"):
		main.show_settings(true, scr.substr(4))
		over = main.settings; over_col = main.settings.col; over_scroll = main.settings.scroll
	elif scr == "help":
		main.show_settings(true, "controls")
		main.settings.open_help()
		over = main.settings.help; over_col = main.settings.help.col
	elif scr.begins_with("intro"):
		main.intro.open()
		main.intro.go(int(scr.substr(5)))
		over = main.intro.card; over_col = main.intro.card
	var cloud: Node = root.get_node("Save").cloud
	if acct:
		if scr in SIGNED:
			cloud.setv("token", "ab".repeat(32)); cloud.setv("user", "Wobbly_Champ16"); cloud.setv("email", "someone.with.a.long.name@example.com")
		if scr == "a-conflict":
			cloud.pending = {"data": {"wallet": {"coins": 12345, "skins": ["none", "cowboy"]}, "stats": {"matches": 321, "kos": 999}}, "t": 1}
		if scr == "a-code": main.account._on_recovery("ABCD-EFGH-JKLM-NPQR")
		main.open_account(scr.substr(2))
		main.account.msg_l.text = "That username and recovery code do not match. Check the code (letters and numbers, no mix-ups between O and 0)."
	elif lock:
		var shop := scr.begins_with("s")
		main.open_locker(shop)
		main.locker._show_tab(main.locker.tabs()[int(scr.substr(1))])
	elif scr == "online" or scr.begins_with("rooms"):
		main.show_tab(true)
		main.get_node(OB + "Foot/Roster").text = "In the room: Alice, Bob, Carol"
		if scr == "rooms": main.browser.show_rooms(load("res://net/room_list.gd").clean(MOCK_ROOMS))
		elif scr == "rooms-empty": main.browser.show_rooms([])
		elif scr == "rooms-error": main.browser.show_rooms([], load("res://net/room_list.gd").ERR_REACH)
		over_scroll = main.browser.scroll
	elif scr.begins_with("host"):
		main.show_tab(true)
		main.show_host(true)
		if scr == "host-mode":
			main.set_host_mode("chaos")            # the longest blurb, app-only
			main.show_host_tab("Mode")
		elif scr == "host-rules": main.show_host_tab("Rules")
	elif scr == "lobby":
		main.show_tab(true)
		main.show_lobby(true)
		main.get_node(LB + "Code").text = "Room code ABCDE"
		main.get_node(LB + "Info").text = "8 / 8 players · empty seats get bots"
		var rl: Label = main.get_node(LB + "Rules")
		rl.text = HostSession.rules_text({"want": "tdm", "mode": "classic", "lim": 30, "hp": 500, "grav": 1.5, "kb": 0.5, "crate": "chaos",
			"inf": true, "dyn": "random", "map": "Bouncy Rooftop"})
		rl.visible = true
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
	if over != null:
		for c: Control in _controls(over, over_scroll): inside.append(str(main.get_path_to(c)))
		if over.name == "ControlsHelp": inside.append(str(main.get_path_to(over.pic)))
		groups.append(inside)
		check(over.is_visible_in_tree(), "%s page shown" % tag)
		if win.x > win.y: _touch_sizes(main, inside, tag)
		if over.name == "Settings":
			var ts: ScrollContainer = over.get_node("Safe/Col/TabScroll")
			check(ts.get_child(0).get_combined_minimum_size().x <= ts.size.x + 0.5, "%s settings tabs fit in one row (%.0f > %.0f)" % [tag, ts.get_child(0).get_combined_minimum_size().x, ts.size.x])
			check(over.rows.get_child_count() >= 1, "%s section has rows" % tag)
		if over_scroll: _scroll_rows(main, over_scroll, safe, tag, win.x > win.y)
		_no_word(over, "fighter", tag)
	elif acct:
		var card: Control = main.account.card
		for c: Control in _leaves(card): inside.append(str(main.get_path_to(c)))
		groups.append(inside)
		check(main.account.pages[scr.substr(2)].visible and main.account.visible, "%s account page shown" % tag)
		for p: String in inside:
			var c: Control = main.get_node(p)
			if (c is Button or c is LineEdit) and win.x > win.y:   # (portrait shows the landscape canvas scaled down)
				check(c.get_global_rect().size.y >= TOUCH_PX - 0.5, "%s %s touch target %.0f tall" % [tag, p, c.get_global_rect().size.y])
	elif lock:
		inside = LFRAME.duplicate()
		for b in main.locker.tab_row.get_children(): inside.append(L + "Body/Right/Tabs/" + b.name)
		groups.append(LFRAME)
		groups.append(inside.slice(LFRAME.size()))
	elif wiz:
		inside = WFRAME.duplicate()
		for b in main.wizard.step_bs: inside.append(W + "Foot/Steps/" + b.name)
		groups.append(WFRAME)
		groups.append(inside.slice(WFRAME.size()))
	else:
		var on_panel := scr in ["online", "lobby"] or scr.begins_with("rooms") or scr.begins_with("host")
		var blocks: Array = BLOCKS.filter(func(b: String) -> bool: return not (on_panel and b.ends_with("/Tip")))
		inside = blocks + (ONLINE if on_panel else HOME)
		groups.append(blocks)
		if scr == "online" or scr.begins_with("rooms"):
			groups.append(ONLINE)
			if win.x > win.y: _touch_sizes(main, ONLINE, tag)
			_scroll_rows(main, over_scroll, safe, tag, win.x > win.y)
			_rooms_state(main.browser, scr, tag)
		elif not on_panel: groups.append(HOME)
		if scr.begins_with("host"):
			var hs: Array = HOST_FRAME + HOST_TABS[scr]
			inside = inside + hs; groups.append(hs)
			if win.x > win.y: _touch_sizes(main, hs, tag)
			var card: Control = main.get_node("HostSheet/Center/Card")
			check(card.get_combined_minimum_size().y <= safe.size.y + 0.5, "%s host sheet min height %.0f fits %.0f" % [tag, card.get_combined_minimum_size().y, safe.size.y])
		if scr == "lobby": inside = inside + LOBBY; groups.append(LOBBY)
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
	if lock: _locker_grid(main.locker, safe, tag)
	# the whole column fits (containers would otherwise overflow past the bottom)
	var col: Control = over_col if over_col != null else main.wizard if wiz else main.locker if lock else main.account.card if acct else main.get_node("Safe/Col")
	check(col.get_combined_minimum_size().y <= safe.size.y + 0.5, "%s column min height %.0f fits %.0f" % [tag, col.get_combined_minimum_size().y, safe.size.y])
	_labels_fit(main, tag)
	if lock:
		_not_cut(main.locker.get_node("Head"), tag)
		_not_cut(main.locker.get_node("Foot"), tag)
		check(main.locker.title_l.text == ("Shop" if scr.begins_with("s") else "Locker"), "%s title says %s" % [tag, main.locker.title_l.text])
		for b: Button in main.locker.tab_row.get_children():
			check(b.size.x + 0.5 >= b.get_minimum_size().x, "%s tab '%s' squeezed" % [tag, b.text])
		check(main.locker.preview_tr.get_global_rect().size.y >= 110.0, "%s preview big enough (%s)" % [tag, main.locker.preview_tr.get_global_rect().size])
	elif wiz:
		_not_cut(main.wizard.get_node("Head"), tag)
		_not_cut(main.wizard.get_node("Foot"), tag)
		if scr == "w4": _not_cut(main.wizard.pages[4], tag)
		for i in main.wizard.step_bs.size():
			var sb: Button = main.wizard.step_bs[i]
			check(sb.text == STEP_TEXT[i], "%s step pill %d says '%s'" % [tag, i + 1, sb.text])
			check(sb.size.x + 0.5 >= sb.get_minimum_size().x, "%s step pill '%s' squeezed" % [tag, sb.text])
		_no_word(main.wizard, "fighter", tag)
	elif over == null:
		_not_cut(main.get_node("Safe/Col"), tag)
		if scr == "title":
			check(main.get_node("Safe/Col/Body/Home/Play/Stack/Big").text == "Play", "%s Play button says Play" % tag)
			check(main.get_node("Safe/Col/Body/Home/Online/Stack/Big").text == "Play online with friends", "%s online button label" % tag)
			check(main.who.text == "Guest", "%s chip says Guest (%s)" % [tag, main.who.text])
			_no_word(main.get_node("Safe/Col/Top"), "offline", tag, true)   # no status pill saying "Offline"
	if acct:
		cloud.setv("token", ""); cloud.setv("user", ""); cloud.setv("email", ""); cloud.pending = {}
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

## The Locker / Shop card grid: no horizontal overflow, cards apart and big enough to tap, the first row visible, every
## card reachable by scrolling.
func _locker_grid(lk: Control, safe: Rect2, tag: String) -> void:
	var sc: ScrollContainer = lk.scroll
	var g: GridContainer = lk.grid
	var sr := sc.get_global_rect()
	check(safe.grow(0.5).encloses(sr), "%s locker scroll %s inside the safe area" % [tag, sr])
	check(g.get_combined_minimum_size().x <= sr.size.x + 0.5, "%s locker grid min width %.0f fits %.0f" % [tag, g.get_combined_minimum_size().x, sr.size.x])
	var cards: Array = g.get_children()
	check(cards.size() == lk.items(lk.tab).size() and cards.size() > 0, "%s locker %s has a card per item (%d)" % [tag, lk.tab, cards.size()])
	var bottom := 0.0
	for i in cards.size():
		var c: Control = cards[i]
		var r := c.get_global_rect()
		bottom = maxf(bottom, c.position.y + c.size.y)
		check(r.position.x >= sr.position.x - 0.5 and r.end.x <= sr.end.x + 0.5, "%s locker card %s within the scroll width" % [tag, c.name])
		check(c.size.y >= 90.0 and c.size.x >= 120.0, "%s locker card %s big enough to tap (%s)" % [tag, c.name, c.size])
		if i < g.columns: check(sr.grow(0.5).encloses(r), "%s locker first-row card %s visible" % [tag, c.name])
		if i + 1 < cards.size():
			check(not r.grow(-0.5).intersects((cards[i + 1] as Control).get_global_rect().grow(-0.5)), "%s locker cards %s and %s overlap" % [tag, c.name, cards[i + 1].name])
	check(bottom - sc.size.y <= maxf(0.0, g.size.y - sc.size.y) + 0.5, "%s every locker card reachable" % tag)

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
	check(main.settings.visible, "gear opens the Settings screen")
	main.settings.show_section("graphics")
	main.settings.ctl["show_fps"].button_pressed = true
	check(bool(st.get_value("show_fps")), "Show FPS saved")
	st.set_value("show_fps", false)
	check(not main.settings.ctl["show_fps"].button_pressed, "the switch follows a change made elsewhere (F3)")
	main.settings.ctl["effects"]["low"].pressed.emit()
	check(str(st.get_value("effects")) == "low", "Effects saved (%s)" % st.get_value("effects"))
	main.settings.ctl["effects"]["auto"].pressed.emit()
	main.settings.ctl["screen_shake"].button_pressed = false
	check(not bool(st.get_value("screen_shake")), "Screen shake saved")
	main.settings.ctl["screen_shake"].button_pressed = true
	main.settings.show_section("audio")
	main.settings.ctl["sfx_volume"].value = 0.4
	var sb := AudioServer.get_bus_index("SFX")
	check(sb >= 0 and absf(db_to_linear(AudioServer.get_bus_volume_db(sb)) - 0.4) < 0.01, "Sound effects volume drives the SFX bus live")
	main.settings.ctl["sfx_volume"].value = 1.0
	main.settings.show_section("controls")
	main.settings._on_row_tapped(main.settings.rows.get_node("Row_touch_lefty"))
	check(bool(st.get_value("touch_lefty")), "a tap on a row's words flips its switch")
	st.set_value("touch_lefty", false)
	main.go_back()
	check(not main.settings.visible, "Back closes the Settings screen")
	# the Host sheet: tabs, the game type stepper (every online mode, app-only ones marked), the rules summary
	main.show_tab(true)
	main.show_host(true)
	var hb := "HostSheet/Center/Card/Box/"
	check(main.get_node(hb + "Room").visible and not main.get_node(hb + "Rules").visible, "the Host sheet opens on Room")
	main.get_node(hb + "Tabs/Rules").pressed.emit()
	check(main.get_node(hb + "Rules").visible and not main.get_node(hb + "Room").visible, "the Rules tab shows the rules")
	main.set_host_mode("classic")
	var seen := {}
	for i in HostSession.online_modes().size():
		main.get_node(hb + "Mode/Game/Next").pressed.emit()
		seen[str(main._host["mode"])] = str(main.get_node(hb + "Mode/Game/Name").text)
	check(seen.size() == HostSession.online_modes().size() and not seen.has("practice"), "› walks every online mode (%d)" % seen.size())
	check(seen.get("tdm", "").ends_with("(app)") and not seen.get("classic", "").ends_with("(app)"), "app-only modes are marked: %s" % seen.get("tdm"))
	main.set_host_mode("tdm")
	main._host_bs["lim_2"].pressed.emit(); main._host_bs["hp_300"].pressed.emit(); main._host_bs["grav_0"].pressed.emit()
	main._host_bs["kb_3"].pressed.emit(); main._host_bs["crate_chaos"].pressed.emit(); main._host_bs["inf_1"].pressed.emit(); main._host_bs["dyn_quake"].pressed.emit()
	var hh: Dictionary = main._host
	check(hh["mode"] == "tdm" and hh["lim"] == 5 and hh["hp"] == 300 and is_equal_approx(hh["grav"], 0.5) and is_equal_approx(hh["kb"], 2.0) \
		and hh["crate"] == "chaos" and hh["inf"] and hh["dyn"] == "quake", "the sheet's picks: %s" % hh)
	main.show_host(false)
	var sum := HostSession.rules_text({"want": "tdm", "mode": "classic", "lim": 5, "hp": 300, "grav": 0.5, "kb": 2.0, "crate": "chaos", "inf": true, "dyn": "quake", "map": "Arena"})
	check(sum.begins_with("Classic · Arena · first to 5 · 300 HP · gravity 0.5x · knockback 2x · chaos crates · infinite ammo · floor Quake") \
		and sum.contains("Team Deathmatch is app-only"), "lobby rules line: %s" % sum)
	# the title chip opens the Account sheet; Delete waits for the typed word
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	main.chip.gui_input.emit(ev)
	check(main.account.visible and main.account.page == "guest", "the chip opens the Account sheet (guest)")
	main.account.ui["guest/Signup"].pressed.emit()
	check(main.account.page == "signup", "Create account opens the sign-up page")
	main.account.close()
	main.account.open("delete")
	main.account.ui["delete/Pass"].text = "pw"
	main.account.ui["delete/Pass"].text_changed.emit("pw")
	check(main.account.ui["delete/Go"].disabled, "Delete account disabled before typing DELETE")
	main.account.ui["delete/Confirm"].text = "delete"
	main.account.ui["delete/Confirm"].text_changed.emit("delete")
	check(not main.account.ui["delete/Go"].disabled, "Delete account enabled after typing DELETE")
	main.account.close()
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

## Visible buttons, fields, sliders and labels under `n`, not looking inside `skip` (a scroll list checked by row).
func _controls(n: Node, skip: Node = null) -> Array:
	var out: Array = []
	for c in n.get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree() or c == skip: continue
		if c is Button or c is LineEdit or c is Slider or (c is Label and (c as Label).text != ""): out.append(c)
		else: out.append_array(_controls(c, skip))
	return out

## Buttons, fields and sliders at least TOUCH_PX tall.
func _touch_sizes(main: Node, paths: Array, tag: String) -> void:
	for p: String in paths:
		var c: Control = main.get_node(p)
		if c is Button or c is LineEdit or c is Slider:
			check(c.get_global_rect().size.y >= TOUCH_PX - 0.5, "%s %s touch target %.0f tall" % [tag, p, c.get_global_rect().size.y])

## A scrolled list (Settings rows, the room list): inside the safe area, no sideways overflow, rows apart and inside
## the list's width, every row reachable, the controls in a row apart from each other and big enough to tap.
func _scroll_rows(main: Node, sc: ScrollContainer, safe: Rect2, tag: String, touch: bool) -> void:
	var sr := sc.get_global_rect()
	check(safe.grow(0.5).encloses(sr), "%s list %s inside the safe area %s" % [tag, sr, safe])
	check(sr.size.y >= 60.0, "%s list tall enough to use (%.0f)" % [tag, sr.size.y])
	var content: Control = null
	for c in sc.get_children(): if c is Control and not (c is ScrollBar): content = c
	check(content.get_combined_minimum_size().x <= sr.size.x + 0.5, "%s list content min width %.0f fits %.0f" % [tag, content.get_combined_minimum_size().x, sr.size.x])
	var rows: Array = content.get_children().filter(func(r: Node) -> bool: return r is Control and (r as Control).visible)
	check(rows.size() > 0, "%s list has rows" % tag)
	var bottom := 0.0
	for i in rows.size():
		var r: Control = rows[i]
		var rr := r.get_global_rect()
		bottom = maxf(bottom, r.position.y + r.size.y)
		check(rr.position.x >= sr.position.x - 0.5 and rr.end.x <= sr.end.x + 0.5, "%s row %s %s within the list width %s" % [tag, r.name, rr, sr])
		if i + 1 < rows.size():
			check(not rr.grow(-0.5).intersects((rows[i + 1] as Control).get_global_rect().grow(-0.5)), "%s rows %s and %s overlap" % [tag, r.name, rows[i + 1].name])
		var cs: Array = [r] if r is Button else _controls(r)
		for a in cs.size():
			var ca: Control = cs[a]
			if touch and (ca is Button or ca is LineEdit or ca is Slider):
				check(ca.size.y >= TOUCH_PX - 0.5, "%s %s/%s touch target %.0f tall" % [tag, r.name, ca.name, ca.size.y])
			for b in range(a + 1, cs.size()):
				check(not ca.get_global_rect().grow(-0.5).intersects((cs[b] as Control).get_global_rect().grow(-0.5)), "%s %s: %s overlaps %s" % [tag, r.name, ca.name, cs[b].name])
	var max_scroll := maxf(0.0, content.size.y - sc.size.y)
	check(bottom - sc.size.y <= max_scroll + 0.5, "%s every row reachable (bottom %.0f, scroll %.0f)" % [tag, bottom, max_scroll])
	_labels_fit(content, tag)

## The room list says what is going on: rows (greyed out with the reason when they cannot be joined), empty, error.
func _rooms_state(b: Control, scr: String, tag: String) -> void:
	match scr:
		"rooms":
			check(b.state == "rooms" and b.rows_by_id.size() == MOCK_ROOMS.size(), "%s a row per room (%d)" % [tag, b.rows_by_id.size()])
			check(not b.rows_by_id["r1"].disabled and not b.rows_by_id["r5"].disabled, "%s joinable rooms are enabled" % tag)
			check(b.rows_by_id["r3"].disabled and b.rows_by_id["r3"].get_node("Row/Info/Sub").text.contains("Full"), "%s a full room is greyed out and says Full" % tag)
			check(b.rows_by_id["r4"].disabled and b.rows_by_id["r4"].get_node("Row/Info/Sub").text.contains("Different game version"), "%s another version is greyed out and says why" % tag)
			check(b.rows_by_id["r2"].get_node("Row/Players").text == "2/4", "%s players n/max" % tag)
			check(b.rows_by_id["r2"].get_node("Row/Info/Sub").text.contains("Playing now") and b.rows_by_id["r1"].get_node("Row/Info/Sub").text.contains("In the lobby"), "%s started / lobby shown" % tag)
		"rooms-empty":
			check(b.state == "empty" and b.msg_l.text.begins_with("No rooms yet") and b.action_b.text == "Host a room", "%s empty state (%s)" % [tag, b.msg_l.text if b.msg_l else ""])
		"rooms-error":
			check(b.state == "error" and b.msg_l.text.contains("reach the game server") and b.action_b.text == "Try again", "%s error state" % tag)
		"online":
			check(b.msg_l != null and b.msg_l.text == "Looking for rooms…", "%s loading state" % tag)

## Visible buttons, fields and labels under `n` (the Account card's controls).
func _leaves(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree(): continue
		if c is Button or c is LineEdit or (c is Label and (c as Label).text != ""): out.append(c)
		else: out.append_array(_leaves(c))
	return out

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
