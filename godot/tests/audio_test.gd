extends SceneTree
## Sound effects (run by tools/test-audio.js):
##   godot --headless --path godot --script res://tests/audio_test.gd -- --no-save EXPECTED_JSON
## EXPECTED_JSON = {name: {dur}} from the web game's SFX table (tools/render-sfx.js). Checks: every JS name has a
## stream in the Sfx autoload, lengths within 10% of the JS durations, peak in (0.01, 1.0], Sfx.play works for every
## name without allocating players, volume/muted settings reach the Master bus.

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

static func peak(s: AudioStreamWAV) -> float:
	var d := s.data
	var pk := 0
	for i in range(0, d.size() - 1, 2):
		pk = maxi(pk, absi(d.decode_s16(i)))
	return pk / 32767.0

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var exp_path := ""
	for a in args:
		if a.ends_with(".json"): exp_path = a
	var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(exp_path))
	check(expected != null and expected.size() > 0, "expected durations loaded from " + exp_path)
	var sfx: Node = root.get_node("Sfx")
	check(sfx != null, "Sfx autoload")
	var names: PackedStringArray = sfx.NAMES
	check(names.size() == expected.size(), "Sfx.NAMES matches the JS table (%d vs %d)" % [names.size(), expected.size()])
	var worst := 0.0
	for n: String in expected:
		var s: AudioStream = sfx.streams.get(n)
		check(s is AudioStreamWAV, n + ": has a WAV stream")
		if not (s is AudioStreamWAV): continue
		var w := s as AudioStreamWAV
		check(w.format == AudioStreamWAV.FORMAT_16_BITS and w.mix_rate == 44100 and not w.stereo, n + ": 16-bit 44.1 kHz mono PCM")
		var jd := float(expected[n]["dur"])
		var err := absf(w.get_length() - jd) / jd
		worst = maxf(worst, err)
		check(err <= 0.1, "%s: length %.3f s vs JS %.3f s" % [n, w.get_length(), jd])
		var pk := peak(w)
		check(pk <= 1.0 and pk > 0.01, "%s: peak %.3f" % [n, pk])
		print("SFX %-8s %.3f s (JS %.3f)  peak %.3f" % [n, w.get_length(), jd, pk])

	# play every name (twice the pool size in a burst): no new nodes, no errors
	var kids := sfx.get_child_count()
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	for r in 2:
		for n: String in expected: sfx.play(n, 0.8)
	sfx.play("thunder")           # unknown names are ignored, like the JS sfx()
	await process_frame
	await process_frame
	check(sfx.get_child_count() == kids and int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes0, "play() allocates no nodes")

	# priority: a full pool of rapid short fire must not cut a boom (12 players, boom priority 2, shots priority 0)
	sfx.stop_all()
	for i in 3: await process_frame
	var boom_stream: AudioStream = sfx.streams.get("boom")
	sfx.play("boom")
	for i in 20: sfx.play("shot")             # far more than the pool: the shots recycle each other, never the boom
	var boom_alive := false
	for p: AudioStreamPlayer in sfx.get_children():
		if p.playing and p.stream == boom_stream: boom_alive = true
	check(boom_alive, "an important sound survives a full pool of short fire")

	# per-play jitter: pitch about +-4 %, volume about +-1.5 dB around what the caller asked for
	sfx.stop_all()
	for i in 3: await process_frame
	sfx.play("click", 0.8)
	var one: AudioStreamPlayer = null
	for p: AudioStreamPlayer in sfx.get_children():
		if p.playing: one = p
	check(one != null, "a player started for the variation check")
	if one != null:
		check(absf(one.pitch_scale - 1.0) <= 0.041, "pitch variation about +-4%% (got %.3f)" % one.pitch_scale)
		check(absf(one.volume_db - linear_to_db(0.8)) <= 1.6, "volume variation about +-1.5 dB (got %.2f)" % one.volume_db)
	sfx.stop_all()
	for i in 3: await process_frame

	# settings
	var settings: Node = root.get_node("Settings")
	var bus := AudioServer.get_bus_index("Master")
	settings.set_value("volume", 0.25)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25)), "volume setting -> Master bus")
	settings.set_value("muted", true)
	check(AudioServer.is_bus_mute(bus), "muted setting mutes the Master bus")
	sfx.play("boom")
	var any := false
	for p: AudioStreamPlayer in sfx.get_children(): any = any or p.playing
	check(not any, "nothing plays while muted")
	settings.set_value("muted", false)
	check(not AudioServer.is_bus_mute(bus), "unmute")
	sfx.resume()
	settings.reset("volume"); settings.reset("muted")
	sfx.stop_all()
	for i in 3: await process_frame

	print("AUDIO %d sounds, worst length error %.1f%%" % [expected.size(), worst * 100.0])
	print("AUDIO ok" if fails == 0 else "AUDIO FAILED (%d)" % fails)
	quit(1 if fails else 0)
