extends SceneTree
## Server default test (headless): the production server comes from data/extra/server.json in release exports, the dev
## address everywhere else, the default is never stored, and Reset returns to it. account_api maps wss -> https.
##   godot --headless --path godot --script res://tests/server_default_test.gd -- --no-save   (npm run test:godot-settings)

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _run() -> void:
	var st: Node = root.get_node("Settings")
	var dev: String = st.DEV_SERVER_URL
	check(dev == "ws://127.0.0.1:3000/ws", "dev default unchanged")
	var shipped := FileAccess.get_file_as_string(st.SERVER_CONFIG_PATH)
	check((JSON.parse_string(shipped) as Dictionary).get("url", "x") == "", "shipped server.json has an empty url (user fills it in)")
	check(st.server_default() == dev, "editor/dev uses the dev default")
	var tmp := "user://server_test.json"
	_write(tmp, '{"url": "wss://play.example.test/ws"}')
	check(st.server_default(tmp, true) == "wss://play.example.test/ws", "release export reads the configured url")
	check(st.server_default(tmp, false) == dev, "editor ignores the config")
	_write(tmp, '{"url": ""}')
	check(st.server_default(tmp, true) == dev, "empty url falls back")
	_write(tmp, '{"url": "https://wrong"}')
	check(st.server_default(tmp, true) == dev, "non-ws url falls back")
	_write(tmp, "not json")
	check(st.server_default(tmp, true) == dev, "bad json falls back")
	check(st.server_default("user://missing.json", true) == dev, "missing file falls back")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	st.set_value("server_url", "wss://friend.example.test/ws")
	check(st.get_value("server_url") == "wss://friend.example.test/ws", "custom server kept")
	check(st.server_status_text().ends_with("(custom)"), "status says custom")
	st.reset("server_url")
	check(st.get_value("server_url") == dev, "Reset to default restores it")
	check(st.server_status_text().ends_with("(default)"), "status says default")
	st.set_value("server_url", "  ")
	check(st.get_value("server_url") == dev, "blank value means default")
	check(AccountApi.http_base("wss://play.example.test/ws") == "https://play.example.test", "wss maps to https")
	check(AccountApi.http_base("ws://127.0.0.1:3000/ws") == "http://127.0.0.1:3000", "ws maps to http")
	print("SERVERDEFAULT ok" if fails == 0 else "SERVERDEFAULT failed (%d)" % fails)
	quit(1 if fails else 0)
