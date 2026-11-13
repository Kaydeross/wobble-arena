extends SceneTree
## What's new card test (headless): news.json parses (newest first, version of project.godot on top), the title's
## "What's new" button opens the card, the newest entry is open and older ones fold, opening stores the newest version
## as seen (Save.last_seen_news, round trip through the blob; an old save without the key loads as "").
##   godot --headless --path godot --script res://tests/whats_new_test.gd -- --no-save

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	# loaded here, not named: a --script test compiles before the autoloads (Save) exist, and whats_new.gd uses Save
	var WN: GDScript = load("res://ui/whats_new.gd")
	var es: Array = WN.load_entries()
	check(es.size() >= 1, "news.json has entries")
	check(WN.newest_version() == str(ProjectSettings.get_setting("application/config/version")), "newest entry matches the app version")
	check(WN.load_entries("res://data/extra/nope.json").is_empty(), "a missing file gives no entries")
	var save: Node = root.get_node("Save")
	check(save.last_seen_news == "", "default last_seen_news is empty")
	check(not save.get_blob().has("last_seen_news"), "an unset value is not written")
	save.apply_blob({"v": 1})
	check(save.last_seen_news == "", "an old save without the key loads as empty")
	save.mark_news_seen("0.2.0")
	var blob: Dictionary = save.get_blob()
	check(blob.get("last_seen_news") == "0.2.0", "blob carries last_seen_news")
	save.apply_blob(blob)
	check(save.last_seen_news == "0.2.0", "round trip")
	save.apply_blob({"v": 1, "last_seen_news": 5})
	check(save.last_seen_news == "", "junk value is ignored")
	save.reset()
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.auto_intro = false
	main.auto_news = false
	root.add_child(main)
	await process_frame
	check(not main.news.visible, "the card stays shut when not auto-opened")
	var b: Button = main.get_node("Safe/Col/Body/Home/More/News")
	check((b.get_node("Stack/Big") as Label).text == "What's new", "button label")
	check((b.get_node("Stack/Sub") as Label).text == "Patch notes", "button sub")
	b.pressed.emit()
	await process_frame
	check(main.news.visible, "the button opens the card")
	check(save.last_seen_news == WN.newest_version(), "opening stores the newest version as seen")
	check(main.news.bodies[es[0]["version"]].visible, "newest entry is open")
	if es.size() > 1: check(not main.news.bodies[es[1]["version"]].visible, "older entries are folded")
	main.news.toggle(es[0]["version"])
	check(not main.news.bodies[es[0]["version"]].visible, "tapping a heading folds it")
	check(main.go_back() and not main.news.visible, "back closes the card")
	print("WhatsNew ok" if fails == 0 else "WhatsNew checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)
