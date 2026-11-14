extends SceneTree
## Reset-game test (headless): "Settings > About > Reset game" (logic/reset_game.gd, ui/reset_dialog.gd,
## ui/settings_screen.gd) takes this device back to a new install:
##   - the wipe restores every Settings key to DEFAULTS (signed out: token / user / email / cloud_*; server address, touch
##     layout, Kids mode...) and the profile to a fresh one (500 coins, the free outfits, zeroed stats, fresh goals, a
##     locked Construction DLC), clears the in-memory store / ad / blocked-names caches, and removes only the known
##     profile files from user://;
##   - the About row exists, is bright red and opens the prompt; nothing is deleted until the red button, Cancel and
##     Back / Esc leave everything untouched, the confirmed reset wipes and asks for the title reload;
##   - test-mode safety: this script always runs with `--no-save`, where Settings.persist, Save.persist and
##     ResetGame.persist are all false, so the wipe never deletes a real file. The file removal itself is checked with
##     throwaway user:// names put in ResetGame.files, and the developer's real settings.cfg / profile.json are only
##     read (before and after) to prove they were not touched. The title reload is recorded through
##     ResetGame.reload_hook instead of changing the scene.
##   godot --headless --path godot --script res://tests/reset_test.gd -- --no-save   (npm run test:godot-reset)
##   docs/RESET.md

const REAL := ["profile.json", "profile.json.bak", "profile.json.tmp"]   ## ResetGame.files' defaults, restored at the end
var fails := 0
var checked := 0
var reloads := 0

func check(ok: bool, what: String) -> void:
	checked += 1
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _write(name: String, text: String) -> void:
	var f := FileAccess.open("user://" + name, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _exists(name: String) -> bool:
	return FileAccess.file_exists("user://" + name)

func _clean() -> void:
	for name: String in ["reset_test_guard.cfg", "reset_test_a.json", "reset_test_b.json", "reset_test_other.cfg",
			"reset_test_profile.json"]:
		if _exists(name): DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + name))

func _same(a: Variant, b: Variant) -> bool:
	return a == b

func _run() -> void:
	var st: Node = root.get_node("Settings")
	var sv: SaveProfile = root.get_node("Save")
	_clean()
	check(not ResetGame.persist and not st.persist and not sv.persist, "--no-save: the wipe and both stores are memory only")
	check(ResetGame.files == REAL, "the default wipe list is the profile's own files")
	# the real files may or may not exist on this machine; only read them, so the guard below is proof either way
	var real_before := {}
	for p: String in [st.PATH, SaveProfile.PATH, SaveProfile.PATH + ".bak"]:
		real_before[p] = [FileAccess.file_exists(p), FileAccess.get_file_as_string(p) if FileAccess.file_exists(p) else ""]
	ResetGame.reload_hook = func() -> void: reloads += 1
	# ============================== the wipe ==============================
	_dirty(st, sv)
	check(sv.cloud.signed_in() and str(st.get_value("kids_mode")) == "true", "dirty state set up")
	ResetGame.files = ["reset_test_guard.cfg"]   # persist is false: the wipe must leave this throwaway file alone
	_write("reset_test_guard.cfg", "keep me")
	var out := ResetGame.wipe_all()
	# Settings: every stored key is gone and DEFAULTS apply again
	var stored: Array = st._cfg.get_section_keys(st.SECTION) if st._cfg.has_section(st.SECTION) else []
	check(stored.is_empty(), "every stored preference is forgotten (%s)" % [stored])
	for k: String in st.DEFAULTS:
		check(_same(st.get_value(k), st.DEFAULTS[k]), "setting '%s' is back to its default (%s)" % [k, st.get_value(k)])
	check(st.get_value("entitlement_remove_ads", "gone") == "gone" and st.get_value("ads_matches_since", "gone") == "gone",
		"cached ads / store keys that have no default are gone")
	# profile: a fresh install
	check(sv.coins == SaveProfile.START_COINS and int(sv.stats["kos"]) == 0 and int(sv.stats["matches"]) == 0 and float(sv.stats["secs"]) == 0.0,
		"500 coins and zeroed stats")
	check(sv.owned == ["wobble"] and sv.skins == ["none"] + LockerData.free_skins(), "free outfits and Wobble Dance only")
	check(sv.codes.is_empty() and sv.classes.is_empty() and sv.hist.is_empty() and _same(sv.daily, {"d": 0, "s": 0}), "empty codes, classes, history and daily counter")
	check(_same(sv.look, SaveProfile.DEFAULT_LOOK), "the default look")
	check(_same(sv.quests, Quests.fresh()), "fresh goals")
	check(_same(sv.dlc, DlcSave.fresh()), "the Construction DLC is locked again")
	check(sv.cloud_t == 0 and sv.loaded_from == "new", "no cloud save time / source remembered")
	# account: signed out locally
	check(not sv.cloud.signed_in() and str(st.get_value("token")) == "" and str(st.get_value("user")) == "" and str(st.get_value("email")) == "", "signed out (token / user / email cleared)")
	check(not bool(st.get_value("cloud_dirty")) and str(st.get_value("cloud_user")) == "" and sv.cloud.pending.is_empty() and not sv.cloud.stale, "the cloud sync state is forgotten")
	# the in-memory caches a scene reload would otherwise keep
	var ent: Node = root.get_node("Entitlements")
	var safety: Node = root.get_node("Safety")
	check(not bool(ent.call("has", ent.REMOVE_ADS)), "the local store-entitlement cache is cleared")
	check((safety.call("blocked") as Array).is_empty(), "blocked names are cleared")
	var rc: Node = root.get_node("RemoteConfig")
	var rc_values: Dictionary = rc.get("values")
	check(str(rc.get("source")) == "bundled" and str(rc_values.get("featured_mode")) == "classic" and not bool((rc_values["ads"] as Dictionary).get("enabled")),
		"the remote launch config is back to the bundled defaults (%s)" % [rc.get("source")])
	# files: the guard under --no-save; the real profile / settings files are untouched
	check(int(out["files"]) == 0 and _exists("reset_test_guard.cfg"), "the --no-save wipe deletes no file")
	for p: String in real_before:
		var had: bool = real_before[p][0]
		var same: bool = had == FileAccess.file_exists(p) and (not had or FileAccess.get_file_as_string(p) == real_before[p][1])
		check(same, "the player's real %s was not touched" % p)
	check(int(out["settings"]) == 1 and bool(out["profile"]) and bool(out["signed_out"]) and bool(out["reloaded"]) and reloads == 1,
		"the wipe resets settings + profile, signs out and asks for the title reload (%s)" % [out])
	# ============================== file removal, on throwaway names ==============================
	ResetGame.persist = true   # ONLY here: files is replaced by throwaway names, no real path is ever in the list
	ResetGame.files = ["reset_test_a.json", "reset_test_b.json"]
	_write("reset_test_a.json", "{}")
	_write("reset_test_b.json", "{}")
	_write("reset_test_other.cfg", "not a known game file")
	var out2 := ResetGame.wipe_all()
	check(int(out2["files"]) == 2 and not _exists("reset_test_a.json") and not _exists("reset_test_b.json"), "the known profile files are removed")
	check(_exists("reset_test_other.cfg"), "a file that is not in the known list is never deleted")
	ResetGame.persist = false
	ResetGame.files = ["reset_test_profile.json"]
	# a new install starts fresh: a dirty profile file, wiped, then the next run loads a new profile and writes a new file
	var dirty := SaveProfile.new()
	dirty.path = "user://reset_test_profile.json"
	dirty.persist = true
	dirty.coins = 9999
	dirty.dlc["owned"] = true
	check(dirty.save(), "a dirty profile file for the file test")
	ResetGame.persist = true
	ResetGame.wipe_all()
	ResetGame.persist = false
	var fresh := SaveProfile.new()
	fresh.path = "user://reset_test_profile.json"
	fresh.persist = true
	check(fresh.load_file() == "new" and fresh.coins == SaveProfile.START_COINS and _same(fresh.dlc, DlcSave.fresh()),
		"the next run loads a fresh profile (%s, %d coins)" % [fresh.loaded_from, fresh.coins])
	check(fresh.save() and _exists("reset_test_profile.json"), "it saves a fresh profile again")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://reset_test_profile.json"))
	check(doc is Dictionary and int(doc["data"]["wallet"]["coins"]) == SaveProfile.START_COINS, "the recreated file holds 500 coins")
	dirty.free()
	fresh.free()
	ResetGame.files = REAL
	_clean()
	# ============================== the row and the prompt ==============================
	await _ui(st, sv)
	ResetGame.reload_hook = Callable()
	print(("RESET ok (%d checks)" % checked) if fails == 0 else "RESET failed (%d of %d)" % [fails, checked])
	quit(0 if fails == 0 else 1)

## Dirtify every store the wipe must clean: preferences, the profile, the account session, the caches and the blocked list.
func _dirty(st: Node, sv: SaveProfile) -> void:
	for kv: Array in [["kids_mode", true], ["touch_scale", 1.4], ["touch_layout", "{\"jump\": [4, 5]}"],
			["server_url", "wss://friend.example.test/ws"], ["lang", "fr"], ["token", "token123"], ["user", "Wobbly"],
			["email", "someone@example.com"], ["cloud_t", 1712345678], ["cloud_dirty", true], ["cloud_user", "wobbly"],
			["entitlement_remove_ads", true], ["ads_matches_since", 2], ["seen_intro", true], ["name", "Champ"]]:
		st.set_value(kv[0], kv[1])
	sv.coins = 4321
	sv.owned = ["wobble", "dab"]
	sv.skins = ["none", "cowboy"]
	sv.classes = ["tank"]
	sv.codes = ["dev"]
	sv.daily = {"d": 1700000000, "s": 7}
	sv.look = {"color": 0xffffff, "hat": "crown", "skin": "cowboy", "cls": "tank"}
	sv.stats["kos"] = 99
	sv.stats["matches"] = 12
	sv.stats["secs"] = 500.0
	sv.quests = {"daily": {"d": 1700000000, "keys": ["kos"]}}
	sv.dlc["owned"] = true
	sv.dlc["arcade_best"]["normal"] = 4
	sv.hist = [{"m": "Classic", "map": "Arena", "ko": 3, "d": 0, "w": 1, "o": 0}]
	sv.last_seen_news = "0.4.0"
	sv.cloud_t = 1712345678
	var rc: Node = root.get_node("RemoteConfig")
	var vals: Dictionary = (rc.get("values") as Dictionary).duplicate(true)
	vals["featured_mode"] = "ninja"
	(vals["ads"] as Dictionary)["enabled"] = true
	rc.set("values", vals)
	rc.set("source", "remote")
	var ent: Node = root.get_node("Entitlements")
	var safety: Node = root.get_node("Safety")
	ent.call("grant_verified", ent.REMOVE_ADS)
	safety.call("block", "Troll")
	check(bool(safety.call("is_blocked", "Troll")) and bool(ent.call("has", ent.REMOVE_ADS)), "the caches are dirty too")

## The About row (only on the title's Settings), its bright-red look, and the confirmation gate: nothing until the red
## button, Cancel / Back leaves everything, the confirmed press wipes and records the reload through the test seam.
func _ui(st: Node, sv: SaveProfile) -> void:
	# autoload identifiers cannot be parsed from a --script main loop, so the page is loaded by path like ui_layout_test does
	var screen: Control = load("res://ui/settings_screen.gd").new()
	root.add_child(screen)
	await process_frame
	await process_frame
	screen.open()
	screen.show_section("about")
	await process_frame
	var row: Node = screen.rows.get_node_or_null("Row_reset_game")
	var b: Button = row.get_node_or_null("ResetGame") if row != null else null
	check(row != null and b != null and b.text == "Reset game…", "About has the 'Reset game…' row")
	if b != null:
		var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
		check(sb != null and sb.bg_color.r > 0.8 and sb.bg_color.g < 0.45 and sb.bg_color.b < 0.45, "the reset button is bright red (%s)" % [sb.bg_color if sb else "no style"])
		check(b.get_theme_color("font_color") == Color.WHITE and b.get_theme_font_size("font_size") >= 20 and b.has_theme_font_override("font"), "white bold text on the red button")
		check(b.custom_minimum_size.y >= 60.0 and screen.ui.get("reset_game") == b, "a full touch-size target, named for the page")
	var cap: Label = screen.rows.get_node_or_null("ResetWarning") as Label
	check(cap != null and cap.text == "Deletes all progress and settings. Cannot be undone." and cap.get_theme_color("font_color").r > 0.8,
		"the red caption says it deletes everything and cannot be undone")
	# not offered in a match (a reset there would drop the room / match)
	var pm: Control = load("res://ui/settings_screen.gd").new()
	pm.in_match = true
	root.add_child(pm)
	await process_frame
	pm.open()
	pm.show_section("about")
	check(pm.rows.get_node_or_null("Row_reset_game") == null and pm.ui.get("reset_game") == null, "no reset row in a match")
	pm.queue_free()
	# the gate: pressing the row opens the prompt, but deletes nothing
	sv.coins = 777
	st.set_value("kids_mode", true)
	var before := reloads
	if b == null:
		screen.queue_free()
		check(false, "cannot test the prompt without the row")
		return
	b.pressed.emit()
	await process_frame
	check(screen.reset_dialog.visible, "Reset game opens the 'Reset everything?' prompt")
	check(sv.coins == 777 and bool(st.get_value("kids_mode")) and reloads == before, "nothing is deleted before the second press")
	check(screen.reset_dialog.cancel_b.has_focus() or not bool(root.get_node("Tier").call("is_pc")), "Cancel is the default focus")
	# Cancel / Back / Esc leave everything untouched
	screen.reset_dialog.cancel_b.pressed.emit()
	check(not screen.reset_dialog.visible and sv.coins == 777 and bool(st.get_value("kids_mode")) and reloads == before,
		"Cancel leaves everything untouched")
	b.pressed.emit()
	await process_frame
	check(screen.reset_dialog.visible and screen.back() and not screen.reset_dialog.visible, "Back / Esc cancels the prompt")
	check(sv.coins == 777 and reloads == before, "cancelling deletes nothing")
	# the red button wipes and asks for the title reload (recorded by the test seam, no real scene change)
	b.pressed.emit()
	await process_frame
	screen.reset_dialog.reset_b.pressed.emit()
	await process_frame
	check(reloads == before + 1 and not screen.reset_dialog.visible, "the confirmed reset wipes and reloads the title (test seam)")
	check(sv.coins == SaveProfile.START_COINS and not bool(st.get_value("kids_mode")) and not sv.cloud.signed_in(),
		"the confirmed reset is a full wipe")
	# the prompt on a phone canvas: inside it, buttons at least 44 pt, card not wider than the screen
	var win := Vector2(852, 393)                       # iPhone 15 / 16 landscape
	var cs := UiScale.canvas_size(win, "normal", true)
	var pt := UiScale.pt_per_px(win, "normal", true)   # pt per canvas px
	var vp := SubViewport.new()
	vp.size = Vector2i(cs)
	root.add_child(vp)
	var dlg: Control = load("res://ui/reset_dialog.gd").new()
	vp.add_child(dlg)
	await process_frame
	dlg.open()
	await process_frame
	await process_frame
	var r: Rect2 = dlg.card.get_global_rect()
	check(Rect2(Vector2.ZERO, cs).grow(-1.0).encloses(r), "the prompt card fits a phone canvas (%s in %s)" % [r, cs])
	check(dlg.cancel_b.size.y * pt >= 43.5 and dlg.reset_b.size.y * pt >= 43.5, "the prompt buttons are at least 44 pt (%.1f, %.1f)" % [dlg.cancel_b.size.y * pt, dlg.reset_b.size.y * pt])
	check(r.size.x <= cs.x, "the prompt never runs off the side (%s in %s)" % [r.size, cs])
	vp.queue_free()
	screen.queue_free()
	await process_frame
