extends SceneTree
## Title redesign test (headless, tools/test-title.js, npm run test:godot-title): the "Hero Stage" title (the icon
## dock, Play, the chips, the CONSTRUCTION pill on the full-screen 3D stage) and the DLC showcase (scripts/main.gd, ui/title_showcase.gd, ui/showcase_stage.gd, dlc/dlc_pack_data.gd, docs/TITLE.md).
##   data     the pack registry: the Construction pack's 9 weapon ids are real Construction weapons, its arena is Site
##            Yard, and is_unlocked follows the profile live (no stored bool)
##   routes   every dock button, Play, the chips and the DLC entries still go where they went before the redesign
##   sizes    at 852x393, 667x375 and 932x430 (with phone insets), landscape only: every title control, the pill, the opened
##            bar (Back, swap arrows, TEST IN, UNLOCK PACK) and every rack cell is at least 44 x 44 pt, inside the safe
##            area, and nothing interactive overlaps
##   states   idle -> open (a ray-picked tap on the container, and the tag button) -> pick a weapon (the wobbler holds
##            it and wears the pack's hat; nothing is written to Settings / Save) -> swap (a second, test-only pack) ->
##            back, with taps spammed mid-animation: the state is always consistent and input never locks; one pack
##            hides the swap arrows; Escape / Android back close the container first
##   trial    TEST IN SITE YARD starts Site Yard in Construction mode with the 9 weapons on the floor, for a player
##            who does not own the pack, and neither grants it nor changes coins / stats / history
##   godot --headless --path godot --script res://tests/title_showcase_test.gd -- --no-save

const MAIN := "res://scenes/main.tscn"
const MIN_TOUCH := 44.0
const CASES := [
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(932, 430), [59.0, 0.0, 59.0, 21.0]],
]
## Scripts that use the autoloads are loaded at run time (a --script main loop compiles before the autoloads exist).
var TS: GDScript
var PACKS: GDScript
var PD: GDScript
var DU: GDScript
var WOB: GDScript

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func frames(n: int) -> void:
	for i in n: await process_frame

func until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > sec * 1000.0: return false
		await process_frame
	return true

func _run() -> void:
	TS = load("res://ui/title_showcase.gd")
	PACKS = load("res://dlc/dlc_packs.gd")
	PD = load("res://dlc/dlc_pack_data.gd")
	DU = load("res://dlc/construction/dlc_unlock.gd")
	WOB = load("res://actors/wobbler.gd")
	var st: Node = root.get_node("Settings")
	for kv in [["offline_map", "arena"], ["mode", "classic"], ["bots", 3], ["difficulty", "normal"], ["class", "wobbler"], ["hat", "none"], ["skin", "none"]]:
		st.set_value(kv[0], kv[1])
	_data()
	await _routes()
	for c: Array in CASES: await _sizes(c[0], c[1])
	SafeArea.override = []
	await _states()
	await _one_pack()
	await _trial()
	print("TITLE ok" if fails == 0 else "TITLE failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _test_pack() -> Resource:
	var p: Resource = PD.new()
	p.pack_id = "test_pack"
	p.display_name = "Test Pack"
	p.subtitle = "3 Weapons + Sunny Arena"
	p.accent_color = Color("#4aa3d8")
	p.weapon_ids.assign(["bat", "katana", "mallet"])
	p.arena_id = "arena"
	p.test_mode = "classic"
	p.unlock_kind = ""
	return p

# ---------------------------------------------------------------- data

func _data() -> void:
	var content: Node = root.get_node("Content")
	var save: Node = root.get_node("Save")
	PACKS.extra = []
	var packs: Array = PACKS.all(content.weapons, content.maps)
	check(packs.size() == 1 and packs[0].pack_id == "construction", "one shipped pack: construction (%d)" % packs.size())
	if packs.is_empty(): return
	var p: Resource = packs[0]
	check(content.pack_ids().has(p.pack_id), "the pack id is the data pack's manifest id (%s)" % [content.pack_ids()])
	check(p.display_name == "Construction" and p.subtitle == "9 Weapons + Site Yard", "name and subtitle (%s / %s)" % [p.display_name, p.subtitle])
	check(p.weapon_ids.size() == 9, "9 weapon ids (%d)" % p.weapon_ids.size())
	for id: String in p.weapon_ids:
		var w: Dictionary = content.weapons.get(id, {})
		check(not w.is_empty() and str(w.get("name", "")) != "", "weapon '%s' is a real weapon" % id)
		check(w.get("constructionOnly") == true, "weapon '%s' is a Construction tool" % id)
		var mesh: ArrayMesh = WOB._weapon_visual(id)
		check(mesh != null and mesh.get_surface_count() > 0, "weapon '%s' has a model" % id)
	var ids: Array = Array(p.weapon_ids).duplicate(); ids.sort()
	var dlc_keys: Array = Array(WeaponModels.DLC_KEYS).duplicate(); dlc_keys.sort()
	check(Array(ids) == dlc_keys, "the pack lists exactly the Construction tools (%s)" % [ids])
	check(p.real_weapons(content.weapons).size() == 9, "all 9 pass real_weapons()")
	check(p.arena_id == "siteyard" and content.maps.has("siteyard") and str(content.maps["siteyard"].get("name", "")) == "Site Yard", "the arena is Site Yard")
	check(content.modes.has(p.test_mode) and ModeRules.maps_for(p.test_mode).has(p.arena_id), "the test mode '%s' plays on the arena" % p.test_mode)
	check(WobblerLooks.hat_parts(p.badge_icon).size() > 0, "the preview hat '%s' exists" % p.badge_icon)
	# ownership is live
	var was: bool = bool(save.dlc.get("owned", false))
	save.dlc["owned"] = false
	check(not p.is_unlocked and not p.unlocked(), "locked while the profile does not own the DLC")
	save.dlc["owned"] = true
	check(p.is_unlocked, "unlocked the moment the profile owns it (no stale bool)")
	save.dlc["owned"] = false
	check(not p.is_unlocked, "and locked again")
	save.dlc["owned"] = was
	var has_bool := false
	for pr: Dictionary in p.get_property_list():
		if str(pr["name"]) == "is_unlocked" and (int(pr["usage"]) & PROPERTY_USAGE_STORAGE) != 0: has_bool = true
	check(not has_bool, "is_unlocked is not stored in the .tres")
	# a broken pack is skipped, a second valid one is listed after the shipped one
	var bad: Resource = _test_pack(); bad.pack_id = "bad"; bad.arena_id = "no_such_arena"
	PACKS.extra = [bad, _test_pack(), _test_pack()]
	var two: Array = PACKS.all(content.weapons, content.maps)
	check(two.size() == 2 and two[1].pack_id == "test_pack", "registry: broken and duplicate packs skipped, 2 listed (%d)" % two.size())
	PACKS.extra = []
	print("TITLE data checked")

# ---------------------------------------------------------------- routes

func _main_in(cs: Vector2) -> Array:
	var vp := SubViewport.new()
	vp.size = Vector2i(cs)
	root.add_child(vp)
	var m: Control = load(MAIN).instantiate()
	m.auto_intro = false
	m.auto_news = false
	vp.add_child(m)
	m.browser.auto_refresh = false
	await frames(4)
	return [vp, m]

func _has_target(sig: Signal, method: String) -> bool:
	for c: Dictionary in sig.get_connections():
		if (c["callable"] as Callable).get_method() == method: return true
	return false

func _routes() -> void:
	var a: Array = await _main_in(Vector2(1170, 540))
	var vp: SubViewport = a[0]
	var m: Control = a[1]
	var rail: Control = m.hero
	var names: Array = []
	for c in m.dock.row.get_children(): if c is BaseButton: names.append(str(c.name))
	check(names == ["Quick", "Online", "Locker", "Shop", "Goals"], "the dock holds the five menu actions in order (%s)" % [names])
	check((m.play.get_node("Row/Big") as Label).text == "Play" and (m.quick_b.get_node("Stack/Word") as Label).text == "Quick play"
		and (m.online_b.get_node("Stack/Word") as Label).text == "Online" and (m.locker_b.get_node("Stack/Word") as Label).text == "Walldrobe"
		and (m.shop_b.get_node("Stack/Word") as Label).text == "Shop" and (m.goals_b.get_node("Stack/Word") as Label).text == "Goals", "the dock keeps the real words")
	check(m.get_node_or_null("Safe/Rail") == null and m.get_node_or_null("Safe/Col/Body/Home/Construction") == null, "no menu rail and no DON'T ENTER bar any more")
	# Play -> the setup wizard, page 0
	m.play.pressed.emit()
	check(m.wizard.visible and m.wizard.page == 0 and not m.col.visible and not rail.visible, "Play opens the setup wizard")
	check(not m.showcase.visible and not m.showcase.overlay.visible, "the stage leaves with the title home")
	m.go_back()
	await frames(2)
	check(not m.wizard.visible and m.col.visible and rail.visible and m.showcase.visible, "Back from the wizard: the title home again")
	# Quick play -> quick_play (a random offline match: starting it would replace the scene, so the wiring is checked)
	check(_has_target(m.quick_b.pressed, "quick_play"), "Quick play is wired to quick_play")
	# Play online -> the online panel
	m.online_b.pressed.emit()
	check(m.online_panel.visible and not m.home.visible and not rail.visible and not m.showcase.visible and not m.coins_chip.visible, "Online opens the online panel")
	m.go_back()
	check(m.home.visible and rail.visible and m.showcase.visible, "Back from the online panel")
	# Walldrobe / Shop
	m.locker_b.pressed.emit()
	check(m.locker.visible and not m.locker.shop, "Walldrobe opens the Walldrobe")
	m.go_back()
	m.shop_b.pressed.emit()
	check(m.locker.visible and m.locker.shop, "Shop opens the Shop")
	m.go_back()
	check(not m.locker.visible and rail.visible, "Back from the Shop")
	# Goals, Settings (gear), Account (chip)
	m.goals_b.pressed.emit()
	check(m.goals.visible, "Goals opens the Goals screen")
	m.go_back()
	check(not m.goals.visible, "Back from Goals")
	m.gear.pressed.emit()
	check(m.settings.visible, "the gear opens Settings")
	m.go_back()
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT; ev.pressed = true
	m.chip.gui_input.emit(ev)
	check(m.account.visible, "the chip opens the Account sheet")
	m.go_back()
	check(not m.account.visible and not m.settings.visible, "Back from the sheets")
	# the coin chip -> the Shop
	var evc := InputEventMouseButton.new()
	evc.button_index = MOUSE_BUTTON_LEFT; evc.pressed = true
	m.coins_chip.gui_input.emit(evc)
	check(m.locker.visible and m.locker.shop, "the coin chip opens the Shop")
	m.go_back()
	check(not m.locker.visible and rail.visible and m.coins_chip.visible, "Back from the Shop (chip)")
	check(m._coins_l.text == str(root.get_node("Save").coins), "the coin chip shows the coins")
	# the DLC entries: the DON'T ENTER sign (in the opened showcase) and the pill on the Construction title -> toggle_dlc
	check(_has_target(m.showcase.site_requested, "toggle_dlc"), "the DON'T ENTER / EXIT SITE sign is wired to toggle_dlc")
	check(m.showcase.pill.pressed.get_connections().size() >= 1 and m.showcase.pill.label == "CONSTRUCTION" and m.showcase.pill.tag == "NEW", "the pill says CONSTRUCTION - NEW while the pack is not owned")
	m.showcase.snap(true)
	check(m.showcase.site_b.is_visible_in_tree() and m.showcase.site_b.label == "DON'T ENTER", "the opened showcase shows the DON'T ENTER sign")
	m.showcase.snap(false)
	m.set_dlc(true, false)
	check(m.showcase.site_exit and m.showcase.pill.label == "EXIT SITE" and m.showcase.pill.tag == "", "on the Construction title the pill says EXIT SITE")
	check(m.showcase.pill.visible and not m.showcase.is_open(), "the Construction title: the container is closed again")
	m.set_dlc(false, false)
	m.set_dlc(true, false)
	m.play.pressed.emit()
	check(m.dlc and m.hub.visible and not m.wizard.visible, "Construction title: Play opens the hub")
	m.go_back()
	m.set_dlc(false, false)
	check(not m.dlc and not m.hub.visible, "EXIT SITE: the normal title")
	check(not m.go_back(), "Back on the bare title does nothing")
	vp.queue_free()
	await frames(2)
	print("TITLE routes checked")

# ---------------------------------------------------------------- sizes

func _pt(px: float, win: Vector2, cs: Vector2) -> float:
	return px * win.x / cs.x

func _big(c: Control, win: Vector2, cs: Vector2, tag: String, what: String) -> void:
	var r := c.get_global_rect().size
	check(c.is_visible_in_tree(), "%s %s visible" % [tag, what])
	check(_pt(r.x, win, cs) >= MIN_TOUCH - 0.4 and _pt(r.y, win, cs) >= MIN_TOUCH - 0.4, "%s %s is %.1f x %.1f pt (need 44)" % [tag, what, _pt(r.x, win, cs), _pt(r.y, win, cs)])

func _apart(rects: Dictionary, tag: String) -> void:
	var keys: Array = rects.keys()
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			check(not (rects[keys[i]] as Rect2).grow(-0.5).intersects((rects[keys[j]] as Rect2).grow(-0.5)), "%s %s %s overlaps %s %s" % [tag, keys[i], rects[keys[i]], keys[j], rects[keys[j]]])

## The title logo follows the language (zh_TW 搖擺擂台, zh_CN 摇摆擂台, ja グラグラ大乱闘; fr / es keep the brand) and
## still fits its box, inside the safe area and clear of the coin / guest / gear chips, whatever the language.
func _logo_langs(m: Control, rects: Dictionary, safe: Rect2, tag: String) -> void:
	var logo := m.get_node("Safe/Col/Top/Logo") as WobbleLogo
	var want := {"en": ["WOBBLERS", "ARENA"], "zh_TW": ["搖擺", "擂台"], "zh_CN": ["摇摆", "擂台"], "ja": ["グラグラ", "大乱闘"], "fr": ["WOBBLERS", "ARENA"], "es": ["WOBBLERS", "ARENA"]}
	for loc: String in want:
		TranslationServer.set_locale(loc)
		await frames(3)
		m.apply_safe_area()
		await frames(2)
		var ltag := "%s [%s]" % [tag, loc]
		check(Array(logo.lines) == want[loc], "%s logo says %s (%s)" % [ltag, want[loc], logo.lines])
		var lr := logo.get_global_rect()
		check(safe.grow(0.5).encloses(lr), "%s logo %s inside the safe area" % [ltag, lr])
		check(logo.get_combined_minimum_size().x <= logo.size.x + 0.5, "%s logo text fits its box (%.0f of %.0f)" % [ltag, logo.get_combined_minimum_size().x, logo.size.x])
		for n: String in ["Coins", "Chip", "Gear"]:
			check(not lr.grow(-0.5).intersects((rects[n] as Rect2).grow(-0.5)), "%s logo %s clear of %s %s" % [ltag, lr, n, rects[n]])
		check(logo.font_size >= 36, "%s logo is big enough (%d)" % [ltag, logo.font_size])
	TranslationServer.set_locale("en")
	await frames(3)
	m.apply_safe_area()
	await frames(2)
	check(Array(logo.lines) == ["WOBBLERS", "ARENA"], "%s switching back to English restores the logo" % tag)

func _sizes(win: Vector2, ins_pt: Array) -> void:
	var cs := UiScale.canvas_size(win, "normal", true)
	var k := cs.x / win.x
	SafeArea.override = [ins_pt[0] * k, ins_pt[1] * k, ins_pt[2] * k, ins_pt[3] * k]
	var safe := Rect2(Vector2(ins_pt[0] * k, ins_pt[1] * k), cs - Vector2((ins_pt[0] + ins_pt[2]) * k, (ins_pt[1] + ins_pt[3]) * k))
	PACKS.extra = [_test_pack()]
	var a: Array = await _main_in(cs)
	var vp: SubViewport = a[0]
	var m: Control = a[1]
	var sc = m.showcase
	var tag := "%dx%d" % [win.x, win.y]
	check(sc.packs.size() == 2, "%s two packs in the showcase" % tag)
	# idle: every title control. The dock items count with their word (the whole item is the touch target).
	var idle := {"Play": m.play, "Quick": m.quick_b, "Online": m.online_b, "Walldrobe": m.locker_b, "Shop": m.shop_b, "Goals": m.goals_b,
		"Coins": m.coins_chip, "Chip": m.chip, "Gear": m.gear, "Pill": sc.pill}
	var rects := {}
	for n: String in idle:
		var c: Control = idle[n]
		_big(c, win, cs, tag, n)
		rects[n] = c.get_global_rect()
		check(safe.grow(0.5).encloses(rects[n]), "%s %s %s inside the safe area %s" % [tag, n, rects[n], safe])
	for n: String in ["Quick", "Online", "Walldrobe", "Shop", "Goals"]:    # (the dock panel hugs its items: only the panel is checked against the rest)
		rects.erase(n)
	rects["Dock"] = m.dock.get_global_rect()
	rects["Logo"] = (m.get_node("Safe/Col/Top/Logo") as Control).get_global_rect()
	rects["Version"] = (m.hero.get_node("Build") as Control).get_global_rect()
	check(safe.grow(0.5).encloses(rects["Dock"]) and safe.grow(0.5).encloses(rects["Logo"]) and safe.grow(0.5).encloses(rects["Version"]), "%s dock, logo and version inside the safe area" % tag)
	_apart(rects, tag + " idle")
	await _logo_langs(m, rects, safe, tag)
	# the dock's words: legible (11 pt or more) and each fits its item; the items are apart; the no-subtitle rule: Play is one word
	var items: Dictionary = {}
	for it: Control in m.dock.row.get_children(): items[it.name] = it.get_global_rect()
	_apart(items, tag + " dock items")
	for it in m.dock.row.get_children():
		var w: Label = it.word
		var fs := w.get_theme_font_size("font_size")
		check(float(fs) * win.x / cs.x >= 11.0 and fs >= UiTheme.MIN_FONT, "%s dock word '%s' is %.1f pt (need 11+)" % [tag, w.text, float(fs) * win.x / cs.x])
		check(w.get_theme_font("font").get_string_size(w.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= (it as Control).size.x + 0.5, "%s dock word '%s' fits its item" % [tag, w.text])
	check(m.play.get_node("Row").get_child_count() == 2 and m.play.get_node_or_null("Stack") == null, "%s Play is just the triangle and the word (no subtitle)" % tag)
	var box: Rect2 = sc.container_screen_rect()
	check(_pt(box.size.x, win, cs) >= MIN_TOUCH and _pt(box.size.y, win, cs) >= MIN_TOUCH, "%s the hanging container is a 44 pt target (%.0f x %.0f pt)" % [tag, _pt(box.size.x, win, cs), _pt(box.size.y, win, cs)])
	check(safe.grow(2.0).encloses(box), "%s the container %s hangs inside the safe area %s" % [tag, box, safe])
	for n: String in ["Logo", "Coins", "Chip", "Gear", "Dock", "Play"]:
		var o: Rect2 = rects[n] if rects.has(n) else (idle[n] as Control).get_global_rect()
		check(not box.grow(-1.0).intersects(o), "%s the container %s clear of %s %s" % [tag, box, n, o])
	var hero_pct := 0.0
	var wob_i: Vector2 = sc.stage.project(sc.stage.wobbler().global_position + Vector3(0, 0.1, 0)) * sc.size
	var wob_h: Vector2 = sc.stage.project(sc.stage.wobbler().global_position + Vector3(0, 2.5 * sc.stage.WOB_IDLE_SCALE, 0)) * sc.size
	hero_pct = (wob_i.y - wob_h.y) / cs.y
	check(hero_pct >= 0.5 and hero_pct <= 0.8, "%s the idle wobbler is big: %.0f %% of the screen height" % [tag, hero_pct * 100.0])
	check(sc.tap_at(box.get_center()), "%s a tap on the container opens it" % tag)
	sc.snap(true)
	await frames(3)
	# opened: the bar, Back, the header and the rack cells
	check(not m.get_node("Safe").visible, "%s the title's own controls are away while the container is open" % tag)
	check(sc.site_b.is_visible_in_tree() and not sc.pill.visible, "%s opened: the DON'T ENTER sign shows, the pill is away" % tag)
	var open_c := {"Back": sc.back_b, "Prev": sc.prev_b, "Next": sc.next_b, "Test": sc.test_b, "Site": sc.site_b}
	open_c["Unlock" if not sc.pack().is_unlocked else "Owned"] = sc.unlock_b if not sc.pack().is_unlocked else sc.owned_chip
	rects = {}
	for n: String in open_c:
		var c: Control = open_c[n]
		if n != "Owned": _big(c, win, cs, tag, n)
		else: check(c.is_visible_in_tree(), "%s the OWNED badge shows" % tag)
		rects[n] = c.get_global_rect()
		check(safe.grow(0.5).encloses(rects[n]), "%s %s %s inside the safe area %s" % [tag, n, rects[n], safe])
		if c is Button and not (c as Button).disabled:
			pass
	rects["Header"] = sc.header.get_global_rect()
	rects["Caption"] = sc.caption.get_global_rect()
	check(safe.grow(0.5).encloses(rects["Header"]), "%s the pack header %s inside the safe area" % [tag, rects["Header"]])
	var n_cells: int = sc.stage.weapon_ids.size()
	check(n_cells == 9, "%s the rack shows 9 weapons (%d)" % [tag, n_cells])
	for i in n_cells + 1:
		var cell: int = i if i < n_cells else sc.stage.arena_cell()
		var r: Rect2 = sc.cell_screen_rect(cell)
		check(_pt(r.size.x, win, cs) >= MIN_TOUCH - 0.4 and _pt(r.size.y, win, cs) >= MIN_TOUCH - 0.4, "%s rack cell %d is %.1f x %.1f pt (need 44)" % [tag, cell, _pt(r.size.x, win, cs), _pt(r.size.y, win, cs)])
		check(safe.grow(0.5).encloses(r), "%s rack cell %d %s inside the safe area" % [tag, cell, r])
		rects["Cell%d" % cell] = r.grow(-2.5)     # (a cell's bounding box includes the perspective slant of its edges: neighbours share an edge)
		var hit: Dictionary = sc.stage.pick((r.get_center() - sc.global_position) / sc.size)
		if cell == sc.stage.arena_cell(): check(hit.get("kind", "") == "arena", "%s the arena badge is pickable (%s)" % [tag, hit])
		else: check(hit.get("kind", "") == "weapon" and int(hit.get("index", -1)) == cell, "%s a ray at cell %d picks weapon %d (%s)" % [tag, cell, cell, hit])
		var px: Button = sc.proxies[cell]
		check(px.visible and px.focus_mode == Control.FOCUS_ALL and px.tooltip_text != "", "%s cell %d has a focusable, named proxy" % [tag, cell])
	_apart(rects, tag + " open")
	# the wobbler is in the picture too
	var wob: Vector2 = sc.stage.project(sc.stage.wobbler().global_position + Vector3(0, 1.2, 0)) * sc.size
	check(Rect2(Vector2.ZERO, cs).has_point(wob), "%s the wobbler is in the open picture (%s)" % [tag, wob])
	# owned: the OWNED badge replaces UNLOCK PACK
	var save: Node = root.get_node("Save")
	save.dlc["owned"] = true
	sc.refresh()
	await frames(2)
	check(not sc.unlock_b.visible and sc.owned_chip.is_visible_in_tree(), "%s owned: the OWNED badge instead of UNLOCK PACK" % tag)
	check(safe.grow(0.5).encloses(sc.bar.get_global_rect()), "%s owned: the bar %s stays inside the safe area" % [tag, sc.bar.get_global_rect()])
	save.dlc["owned"] = false
	sc.refresh()
	print("TITLE %s canvas %dx%d checked (hero %.0f %% tall, container %.0f x %.0f pt, cell %.0f x %.0f pt)" % [tag, cs.x, cs.y, hero_pct * 100.0,
		_pt(box.size.x, win, cs), _pt(box.size.y, win, cs), _pt(sc.cell_screen_rect(0).size.x, win, cs), _pt(sc.cell_screen_rect(0).size.y, win, cs)])
	vp.queue_free()
	PACKS.extra = []
	await frames(2)

# ---------------------------------------------------------------- the state machine

func _click(target: Control, at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = at
	ev.global_position = at
	target.gui_input.emit(ev)

func _consistent(sc, m: Control, tag: String) -> void:
	var s: int = sc.state
	var st = sc.stage
	if s == TS.State.IDLE:
		check(is_zero_approx(st.lower) and is_zero_approx(st.doors) and is_zero_approx(st.cam_k) and is_zero_approx(st.hoist) and is_zero_approx(sc.ui_k),
			"%s IDLE pose is the hover (%.2f %.2f %.2f %.2f ui %.2f)" % [tag, st.lower, st.doors, st.cam_k, st.hoist, sc.ui_k])
		check(m.get_node("Safe").visible and is_equal_approx(m.get_node("Safe").modulate.a, 1.0), "%s IDLE: the title's controls are back" % tag)
		check(not sc.catcher.visible and sc.pill.visible and not sc.back_b.visible and not sc.bar.visible and not sc.site_b.visible, "%s IDLE: only the pill shows" % tag)
		check(st.selected == -1 and st.held_weapon() == "", "%s IDLE: the wobbler's hands are empty" % tag)
	elif s == TS.State.OPENED:
		check(is_equal_approx(st.lower, 1.0) and is_equal_approx(st.doors, 1.0) and is_equal_approx(st.cam_k, 1.0) and is_zero_approx(st.hoist) and is_equal_approx(sc.ui_k, 1.0),
			"%s OPENED pose is landed and open (%.2f %.2f %.2f %.2f ui %.2f)" % [tag, st.lower, st.doors, st.cam_k, st.hoist, sc.ui_k])
		check(not m.get_node("Safe").visible, "%s OPENED: the title's controls are away" % tag)
		check(sc.catcher.visible and not sc.pill.visible and sc.back_b.visible and not sc.back_b.disabled and not sc.test_b.disabled, "%s OPENED: Back and the bar are live" % tag)
	else:
		check(sc.catcher.visible and not sc.pill.visible, "%s mid-animation: the catcher shields the title" % tag)
		check(sc._tw != null and sc._tw.is_valid() and sc._tw.is_running(), "%s mid-animation: a tween is driving it (never a dead state)" % tag)
	for v: float in [st.lower, st.doors, st.cam_k, st.hoist, sc.ui_k]:
		check(v >= -0.2 and v <= 1.2 and is_finite(v), "%s pose value %.2f in range" % [tag, v])

func _states() -> void:
	PACKS.extra = [_test_pack()]
	var st: Node = root.get_node("Settings")
	var save: Node = root.get_node("Save")
	save.dlc["owned"] = false
	var blob0 := JSON.stringify(save.get_blob())
	var a: Array = await _main_in(Vector2(1170, 540))
	var vp: SubViewport = a[0]
	var m: Control = a[1]
	var sc = m.showcase
	sc.speed = 5.0
	_consistent(sc, m, "start")
	check(sc.packs.size() == 2 and sc.pack().pack_id == "construction", "the showcase starts on the shipped pack")
	# a tap beside the container does nothing; a tap on it (ray pick through the stage slot) opens
	var box: Rect2 = sc.container_screen_rect()
	_click(sc, Vector2(6, 6))
	check(sc.state == TS.State.IDLE, "a tap on empty stage does not open")
	_click(sc, box.get_center())
	check(sc.state == TS.State.OPENING, "a tap on the container starts OPENING (%d)" % sc.state)
	_consistent(sc, m, "opening")
	check(not sc.open(), "open() while OPENING is ignored")
	check(not sc.swap(1), "swap while OPENING is ignored")
	_click(sc.catcher, sc.cell_screen_rect(2).get_center())
	check(sc.stage.selected == -1, "a tap on the rack while OPENING is dropped")
	check(await until(func() -> bool: return sc.state == TS.State.OPENED, 6.0), "OPENING reaches OPENED")
	_consistent(sc, m, "opened")
	check(sc.thuds == 1, "the container landed once (%d thuds)" % sc.thuds)
	# pick a weapon with a ray: the wobbler holds it and wears the hard hat; nothing is saved
	_click(sc.catcher, sc.cell_screen_rect(3).get_center())
	var want: String = sc.pack().weapon_ids[3]
	check(sc.stage.selected == 3 and sc.stage.held_weapon() == want and sc.stage.wobbler().weapon == want, "tapping rack cell 3 puts '%s' in the wobbler's hand (%s)" % [want, sc.stage.wobbler().weapon])
	check(sc.stage.wobbler().hat_name == "hardhat", "the Construction preview wears the hard hat (%s)" % sc.stage.wobbler().hat_name)
	check(str(st.get_value("hat", "none")) == "none" and JSON.stringify(save.get_blob()) == blob0, "the preview writes nothing to Settings / Save")
	check(sc.caption.text == str(root.get_node("Content").weapons[want]["name"]), "the caption names the weapon (%s)" % sc.caption.text)
	sc.proxies[5].pressed.emit()
	check(sc.stage.selected == 5, "a rack proxy (keyboard / gamepad) picks its weapon")
	# swap to the next pack; spamming swap mid-animation does not skip packs
	check(sc.prev_b.visible and sc.next_b.visible, "two packs: the swap arrows show")
	sc.next_b.pressed.emit()
	check(sc.state == TS.State.SWAPPING and sc.stage.selected == -1, "SWAP PACK > starts SWAPPING and puts the weapon away")
	for i in 5:
		check(not sc.swap(1), "swap spam is ignored while SWAPPING")
		sc.next_b.pressed.emit()
		await process_frame
	_consistent(sc, m, "swapping")
	check(await until(func() -> bool: return sc.state == TS.State.OPENED, 6.0), "SWAPPING reaches OPENED")
	check(sc.index == 1 and sc.pack().pack_id == "test_pack" and sc.stage.pack == sc.pack(), "exactly one step on: the test pack (%d)" % sc.index)
	check(Array(sc.stage.weapon_ids) == ["bat", "katana", "mallet"], "the rack shows the new pack's weapons (%s)" % [sc.stage.weapon_ids])
	check(not sc.unlock_b.visible and sc.owned_chip.visible, "a free pack shows OWNED")
	check(sc.thuds == 2, "the new container landed (%d thuds)" % sc.thuds)
	_consistent(sc, m, "swapped")
	_click(sc.catcher, sc.cell_screen_rect(1).get_center())
	check(sc.stage.held_weapon() == "katana" and sc.stage.wobbler().hat_name == "none", "a pack without a hat keeps the wobbler's own hat")
	# cells past the pack's weapons are empty
	_click(sc.catcher, sc.cell_screen_rect(6).get_center())
	check(sc.stage.held_weapon() == "katana", "an empty rack cell changes nothing")
	sc.prev_b.pressed.emit()
	check(sc.state == TS.State.SWAPPING, "< SWAP PACK swaps back")
	check(sc.back() and sc.state == TS.State.SWAPPING, "Back during a swap is taken (queued)")
	check(await until(func() -> bool: return sc.state == TS.State.IDLE, 8.0), "the queued Back closes after the swap")
	check(sc.index == 0, "wrapped back to the first pack")
	_consistent(sc, m, "closed")
	# Back mid-opening reverses at once; opening mid-closing reverses again
	sc.pill.pressed.emit()
	await frames(3)
	check(sc.state == TS.State.OPENING, "the tag button opens too")
	check(m.go_back() and sc.state == TS.State.CLOSING, "go_back() mid-opening starts CLOSING")
	_consistent(sc, m, "closing")
	await frames(2)
	check(sc.open() and sc.state == TS.State.OPENING, "open() mid-closing re-opens from where it is")
	check(await until(func() -> bool: return sc.state == TS.State.OPENED, 6.0), "and reaches OPENED")
	_consistent(sc, m, "re-opened")
	# Escape (ui_cancel) closes the container before anything else
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"; esc.pressed = true
	m._unhandled_input(esc)
	check(sc.state == TS.State.CLOSING, "Escape closes the container")
	m.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check(sc.state == TS.State.CLOSING, "Android back mid-closing is harmless")
	check(await until(func() -> bool: return sc.state == TS.State.IDLE, 6.0), "CLOSING reaches IDLE")
	_consistent(sc, m, "idle again")
	# spam: random open / back / swap / taps every frame, at several speeds; the state stays consistent throughout
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261116
	for round_i in 6:
		sc.speed = [1.0, 3.0, 8.0, 20.0, 2.0, 40.0][round_i]
		for f in 90:
			match rng.randi_range(0, 7):
				0: sc.pill.pressed.emit()
				1: sc.back_b.pressed.emit()
				2: sc.next_b.pressed.emit()
				3: sc.prev_b.pressed.emit()
				4: _click(sc.catcher, sc.cell_screen_rect(rng.randi_range(0, 9)).get_center())
				5: _click(sc, sc.container_screen_rect().get_center())
				6: m.go_back()
				7: pass
			if f % 3 == 0: await process_frame
			_consistent(sc, m, "spam %d/%d" % [round_i, f])
		# never locked: from wherever the spam left it, Back gets to IDLE and the title answers
		sc.speed = 10.0
		var guard := 0
		while sc.state != TS.State.IDLE and guard < 2000:
			sc.back()
			await process_frame
			guard += 1
		check(sc.state == TS.State.IDLE, "round %d: Back always gets to IDLE (%d frames)" % [round_i, guard])
		_consistent(sc, m, "after spam %d" % round_i)
		check(sc.open(), "round %d: the container opens again after the spam" % round_i)
		check(await until(func() -> bool: return sc.state == TS.State.OPENED, 6.0), "round %d: and reaches OPENED" % round_i)
		check(sc.back() and await until(func() -> bool: return sc.state == TS.State.IDLE, 6.0), "round %d: and closes" % round_i)
	check(JSON.stringify(save.get_blob()) == blob0 and not DU.owned(), "none of it touched the profile")
	# the title is alive after all that: Play still opens the wizard, which also puts the stage away
	m.play.pressed.emit()
	check(m.wizard.visible and not sc.visible, "after the spam Play still opens the wizard")
	m.go_back()
	# leaving the title while the container is open snaps it shut
	sc.open()
	await frames(4)
	m.open_wizard(0)
	check(sc.state == TS.State.IDLE and m.get_node("Safe").visible and m.wizard.visible, "opening a page mid-animation snaps the showcase shut")
	m.go_back()
	await frames(2)
	_consistent(sc, m, "after a page")
	# UNLOCK PACK routes to the existing unlock flow (the hub), and Back from there returns to the open container
	sc.snap(true)
	check(sc.unlock_b.visible and not sc.pack().is_unlocked, "locked pack: UNLOCK PACK shows")
	sc.unlock_b.pressed.emit()
	check(m.hub.visible and m.hub.buy_row.visible, "UNLOCK PACK opens the Construction hub's unlock row")
	check(m.go_back() and not m.hub.visible and sc.state == TS.State.OPENED, "Back from the hub: still on the open container")
	save.coins = DU.price()
	sc.unlock_b.pressed.emit()
	check(m.hub.buy(), "the hub's existing purchase works from here")
	m.go_back()
	await frames(2)
	check(sc.pack().is_unlocked and not sc.unlock_b.visible and sc.owned_chip.visible, "after buying: OWNED replaces UNLOCK PACK")
	save.dlc["owned"] = false
	save.coins = 500
	sc.snap(false)
	vp.queue_free()
	PACKS.extra = []
	await frames(2)
	print("TITLE states checked")

func _one_pack() -> void:
	var a: Array = await _main_in(Vector2(1170, 540))
	var vp: SubViewport = a[0]
	var m: Control = a[1]
	var sc = m.showcase
	sc.speed = 20.0
	check(sc.packs.size() == 1, "the shipped game has one pack")
	sc.pill.pressed.emit()
	check(await until(func() -> bool: return sc.state == TS.State.OPENED, 6.0), "one pack: opens")
	check(not sc.prev_b.visible and not sc.next_b.visible, "one pack: no swap arrows")
	check(not sc.swap(1) and not sc.swap(-1) and sc.state == TS.State.OPENED, "one pack: swap() is a no-op")
	check(sc.back() and await until(func() -> bool: return sc.state == TS.State.IDLE, 6.0), "one pack: closes")
	vp.queue_free()
	await frames(2)
	print("TITLE one pack checked")

# ---------------------------------------------------------------- the test drive

func _trial() -> void:
	var save: Node = root.get_node("Save")
	var content: Node = root.get_node("Content")
	save.dlc["owned"] = false
	save.coins = 500
	var blob0 := JSON.stringify(save.get_blob())
	var m: Control = load(MAIN).instantiate()
	m.auto_intro = false
	m.auto_news = false
	root.add_child(m)
	current_scene = m
	m.browser.auto_refresh = false
	await frames(3)
	var sc = m.showcase
	sc.snap(true)
	check(not sc.pack().is_unlocked, "the player does not own the pack")
	check(sc.test_b.text == "TEST IN SITE YARD", "the button says TEST IN SITE YARD (%s)" % sc.test_b.text)
	sc.test_b.pressed.emit()
	check(await until(func() -> bool: return current_scene != null and current_scene.has_method("load_map") and current_scene.get("sim") != null, 20.0), "TEST IN SITE YARD starts a match")
	var w: Node = current_scene
	if w == null or w.get("sim") == null:
		print("TITLE trial FAILED to start")
		return
	check(w.map_id == "siteyard" and w.trial == true and w.arcade == null and w.session == null, "the test drive plays Site Yard, offline (%s)" % w.map_id)
	check(w.sim.combat.mode_id == "construction", "in Construction mode (%s)" % w.sim.combat.mode_id)
	check(w.sim.combat.rules.limit == 0, "with no K.O. limit (%d)" % w.sim.combat.rules.limit)
	var on_floor: Array = []
	for p: Dictionary in w.sim.pickups.list:
		if p.get("perm", false): on_floor.append(str(p["key"]))
	on_floor.sort()
	var want: Array = Array(PACKS.find("construction", content.weapons, content.maps).weapon_ids).duplicate(); want.sort()
	check(on_floor == want, "all 9 pack weapons lie on the floor (%s)" % [on_floor])
	# a taken weapon works for a non-owner
	w.sim.combat.pickup(w.sim.player, "nailgun")
	var got := false
	for s in w.sim.player.slots:
		if s != null and str(s["key"]) == "nailgun": got = true
	check(got, "a player who does not own the pack can pick a pack weapon up")
	await frames(30)
	# K.O.s, hits and a finished match pay nothing and save nothing
	w._on_ko({"type": "ko", "victim": w.sim.fighters[1], "killer": w.sim.player, "fall": false})
	w.sim.combat.ev({"type": "match_over", "title": "You win!", "sub": "", "won": true, "winner": w.sim.player})
	await frames(10)
	check(JSON.stringify(save.get_blob()) == blob0, "the test drive leaves the profile untouched (coins %d)" % save.coins)
	check(not DU.owned() and not bool(save.dlc.get("owned", false)), "the test drive does not grant the pack")
	check(w._reward.is_empty(), "no reward summary")
	w.queue_free()
	await frames(3)
	print("TITLE trial checked")
