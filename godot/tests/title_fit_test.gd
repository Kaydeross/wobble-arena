extends SceneTree
## Title text-fit audit (tools/test-title-fit.js, npm run test:godot-title-fit): every language of the game's own table (autoload
## Lang.LANGS, plus English) at 852x393, 667x375, 932x430 (+ phone insets) and 1280x720: the title idle screen, the Construction
## title, and the opened showcase (locked, locked with a weapon picked, owned, with a 2-pack registry so SWAP PACK shows):
## no text wider / taller than its control, nothing cropped or overlapping, buttons >= 44 pt (tests/fit_audit.gd).
##   godot --headless --path godot --script res://tests/title_fit_test.gd -- --no-save [--lang=ja] [--size=852x393]
const MAIN := "res://scenes/main.tscn"
const CASES := [
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(932, 430), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(1280, 720), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(874, 402), [62.0, 0.0, 62.0, 21.0]],      # iPhone 16 Pro
	[Vector2(812, 375), [44.0, 0.0, 44.0, 21.0]],      # iPhone 13 mini
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0], "large"],   # Settings > UI size: large
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0], "large"],
]
var Audit: GDScript
var audit
var langs: Array = []
var only_size := ""
var sizes := {}

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func frames(n: int) -> void:
	for i in n: await process_frame

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

func _run() -> void:
	Audit = load("res://tests/fit_audit.gd")
	audit = Audit.new()
	audit.load_keys()
	var lang_node: Node = root.get_node("Lang")
	for l: Dictionary in lang_node.LANGS: langs.append(str(l.code))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="): langs = [a.substr(7)]
		if a.begins_with("--size="): only_size = a.substr(7)
	var PACKS: GDScript = load("res://dlc/dlc_packs.gd")
	var PD: GDScript = load("res://dlc/dlc_pack_data.gd")
	var save: Node = root.get_node("Save")
	var st: Node = root.get_node("Settings")
	for kv in [["offline_map", "arena"], ["mode", "classic"], ["bots", 3], ["difficulty", "normal"], ["class", "wobbler"], ["hat", "none"], ["skin", "none"]]:
		st.set_value(kv[0], kv[1])
	var p: Resource = PD.new()
	p.pack_id = "test_pack"; p.display_name = "Test Pack"; p.subtitle = "3 Weapons + Sunny Arena"
	p.accent_color = Color("#4aa3d8"); p.weapon_ids.assign(["bat", "katana", "mallet"]); p.arena_id = "arena"; p.test_mode = "classic"; p.unlock_kind = ""
	for lang: String in langs:
		lang_node.apply(lang)
		for c: Array in CASES:
			var win: Vector2 = c[0]
			if only_size != "" and only_size != "%dx%d" % [win.x, win.y] and only_size != "%dx%d%s" % [win.x, win.y, c[2] if c.size() > 2 else ""]: continue
			var ins: Array = c[1]
			var mode: String = c[2] if c.size() > 2 else "normal"
			var cs := UiScale.canvas_size(win, mode, true)
			var k := cs.x / win.x
			SafeArea.override = [ins[0] * k, ins[1] * k, ins[2] * k, ins[3] * k]
			PACKS.extra = [p]
			save.dlc["owned"] = false
			var a: Array = await _main_in(cs)
			var vp: SubViewport = a[0]
			var m: Control = a[1]
			var sc = m.showcase
			await frames(3)
			audit.audit(m, lang, win, cs, mode + " " + "idle")
			if win.x == 852.0 and mode == "normal":
				var pl: Label = m.play.get_node("Row/Big")
				var dk: Label = m.dock.row.get_child(0).word
				sizes[lang] = "Play '%s' %dpx, dock word '%s' %dpx" % [pl.text if lang == "en" else pl.tr(pl.text), pl.get_theme_font_size("font_size"), dk.tr(dk.text), dk.get_theme_font_size("font_size")]
			m.set_dlc(true, false)
			await frames(3)
			audit.audit(m, lang, win, cs, mode + " " + "construction-title")
			m.set_dlc(false, false)
			await frames(3)
			sc.snap(true)
			await frames(4)
			audit.audit(m, lang, win, cs, mode + " " + "open-locked")
			sc.select(0)
			await frames(3)
			audit.audit(m, lang, win, cs, mode + " " + "open-locked-weapon")
			sc.select(sc.stage.arena_cell())
			await frames(3)
			audit.audit(m, lang, win, cs, mode + " " + "open-locked-arena")
			save.dlc["owned"] = true
			sc.refresh()
			await frames(4)
			audit.audit(m, lang, win, cs, mode + " " + "open-owned")
			save.dlc["owned"] = false
			if (win.x == 852.0 or win.x == 667.0) and mode == "normal" and not OS.get_cmdline_user_args().has("--no-sweep"):
				await _sweep(m, lang, win, cs)
			vp.queue_free()
			await frames(2)
			if (win.x == 852.0 or win.x == 667.0) and mode == "normal" and not OS.get_cmdline_user_args().has("--no-sweep"):
				await _sweep_world(lang, win, cs)
	# a language switched live (Settings > language) with the title already up: it re-fits (Play, the dock, the showcase)
	if only_size == "" and not OS.get_cmdline_user_args().has("--no-live"):
		var win := Vector2(852, 393)
		var cs := UiScale.canvas_size(win, "normal", true)
		var k := cs.x / win.x
		SafeArea.override = [59.0 * k, 0.0, 59.0 * k, 21.0 * k]
		PACKS.extra = [p]
		for lang: String in langs:
			lang_node.apply("en")
			var a: Array = await _main_in(cs)
			lang_node.apply(lang)
			await frames(8)
			audit.audit(a[1], lang, win, cs, "normal live-switch-idle")
			a[1].showcase.snap(true)
			await frames(4)
			audit.audit(a[1], lang, win, cs, "normal live-switch-open")
			a[0].queue_free()
			await frames(2)
	SafeArea.override = []
	PACKS.extra = []
	_report()

## The other first-screen UIs the owner reaches: the setup wizard (every page), Settings (every section), Goals, the online panel.
func _sweep(m: Control, lang: String, win: Vector2, cs: Vector2) -> void:
	m.showcase.snap(false)
	for pg in 5:
		m.open_wizard(pg)
		await frames(4)
		audit.audit(m.wizard, lang, win, cs, "wizard-page%d" % pg)
	m.close_wizard()
	await frames(2)
	m.settings.open()
	for sec: String in m.settings.SECTIONS:
		m.settings.show_section(sec)
		await frames(4)
		audit.audit(m.settings, lang, win, cs, "settings-" + sec)
	m.settings.close()
	m.goals.open()
	await frames(4)
	audit.audit(m.goals, lang, win, cs, "goals")
	m.goals.close()
	m.online_b.pressed.emit()
	await frames(4)
	audit.audit(m.online_panel, lang, win, cs, "online")
	m.go_back()
	await frames(2)

## The world's results panel and pause menu (a real offline match scene, no simulation steps run).
func _sweep_world(lang: String, win: Vector2, cs: Vector2) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(cs)
	root.add_child(vp)
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = "arena"
	w.mode_id = "classic"
	vp.add_child(w)
	await frames(8)
	var sv: Node = root.get_node("Save")
	sv.on_ko(true, false); sv.on_ko(true, false)
	w._reward = sv.finish_match(true, "Classic", "Arena")
	w._show_offline_results(true, "")
	await frames(4)
	audit.audit(w._results, lang, win, cs, "results")
	w._results.visible = false
	w._toggle_pause()
	await frames(4)
	audit.audit(w.pause_menu, lang, win, cs, "pause-menu")
	w.pause_menu.ask_quit()
	await frames(3)
	audit.audit(w.pause_menu, lang, win, cs, "pause-confirm")
	w.pause_menu.open_settings()
	await frames(4)
	audit.audit(w.pause_menu, lang, win, cs, "pause-settings")
	vp.queue_free()
	await frames(3)

func _report() -> void:
	var seen := {}
	var per := {}
	for f: Dictionary in audit.fails:
		var key := "%s|%s|%s|%s" % [f.lang, f.size, f.path, f.kind]
		if seen.has(key): continue
		seen[key] = true
		per[f.lang] = int(per.get(f.lang, 0)) + 1
		print("FITFAIL %-6s %-22s %-34s '%s' %s need %.0f avail %.0f" % [f.lang, f.size, f.path, str(f.text).replace("\n", "\\n"), f.kind, f.need, f.avail])
	for l: String in langs:
		var w: Dictionary = audit.worst.get(l, {})
		print("FITSUM %-6s fails %3d  fonts at 852x393: %s" % [l, int(per.get(l, 0)), sizes.get(l, "-")])
		for t: String in audit.untranslated.get(l, {}): print("FITUNTR %-6s %s" % [l, t])
	var n := seen.size()
	print("FIT ok" if n == 0 else "FIT failed (%d)" % n)
	quit(0 if n == 0 else 1)
