extends SceneTree
## Background music (run by tools/test-music.js):
##   godot --headless --path godot --script res://tests/music_test.gd -- --no-save
## Checks: every loop of res://audio/music/music.json loads as a looping Ogg stream of the rendered length; the Music
## bus exists and follows the `music_volume` setting; the tier choice (with hysteresis) and the mood -> loop mapping;
## playback starts, crossfades to another loop and stops without adding nodes.

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var music: Node = root.get_node("Music")
	check(music != null, "Music autoload")
	music.auto = false                 # drive it by hand (the test has no world scene)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://audio/music/music.json"))
	check(meta != null and meta.size() == music.TRACKS.size(), "music.json lists every loop")
	for n: String in music.TRACKS:
		var s: AudioStream = music.streams.get(n)
		check(s is AudioStreamOggVorbis, n + ": Ogg stream")
		if not (s is AudioStreamOggVorbis): continue
		check((s as AudioStreamOggVorbis).loop, n + ": loops")
		var want := float(meta[n]["seconds"])
		check(absf(s.get_length() - want) < 0.05, "%s: length %.3f s (rendered %.3f s)" % [n, s.get_length(), want])
		print("MUSIC %-10s %.2f s  %s bpm" % [n, s.get_length(), str(meta[n]["bpm"])])

	# volume setting -> Music bus
	var settings: Node = root.get_node("Settings")
	var bus := AudioServer.get_bus_index("Music")
	check(bus >= 0, "Music bus")
	settings.set_value("music_volume", 0.25)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25)), "music_volume -> Music bus")
	settings.set_value("music_volume", 0.0)
	check(AudioServer.is_bus_mute(bus), "music_volume 0 mutes the Music bus")
	settings.reset("music_volume")
	check(not AudioServer.is_bus_mute(bus), "default music volume is audible")

	# mood + intensity -> loop (with hysteresis)
	var cases := [["menu", 0.9, "", "menu"], ["", 0.5, "", ""], ["match", 0.1, "", "match_low"], ["match", 0.5, "", "match_mid"],
		["match", 0.9, "", "match_high"], ["match", 0.65, "match_high", "match_high"], ["match", 0.55, "match_high", "match_mid"],
		["match", 0.34, "match_mid", "match_mid"], ["match", 0.25, "match_mid", "match_low"], ["match", 0.4, "match_low", "match_mid"]]
	for c: Array in cases:
		music.set_mood(c[0]); music.intensity = c[1]; music.track = c[2]
		check(music.pick_track() == c[3], "mood %s, intensity %.2f, from '%s' -> %s (got %s)" % [c[0], c[1], c[2], c[3], music.pick_track()])
	music.track = ""

	# play: menu starts, a tier change crossfades at a bar line, "" stops; no nodes are added
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	music.set_mood("menu")
	await process_frame
	await process_frame
	check(music.track == "menu", "menu loop starts (track %s)" % music.track)
	music._start("match_mid", 0.0, 0.05)             # what _process does on the bar line
	check(music.track == "match_mid", "switches loop")
	var playing := 0
	for p: AudioStreamPlayer in music._players:
		if p.playing: playing += 1
	check(playing >= 1 and playing <= 2, "one or two players during a crossfade (%d)" % playing)
	music.set_mood("")
	for i in 60: await process_frame
	check(music.track == "", "silent mood stops the music")
	check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes0, "music allocates no nodes")
	music.stop_all()
	for i in 3: await process_frame

	print("MUSIC ok" if fails == 0 else "MUSIC FAILED (%d)" % fails)
	quit(1 if fails else 0)
