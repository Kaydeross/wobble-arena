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
	for c: Node in sfx.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing and (c as AudioStreamPlayer).stream == boom_stream: boom_alive = true
	check(boom_alive, "an important sound survives a full pool of short fire")

	# per-play jitter: pitch about +-4 %, volume about +-1.5 dB around what the caller asked for
	sfx.stop_all()
	for i in 3: await process_frame
	sfx.play("click", 0.8)
	var one: AudioStreamPlayer = null
	for c: Node in sfx.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing: one = c as AudioStreamPlayer
	check(one != null, "a player started for the variation check")
	if one != null:
		check(absf(one.pitch_scale - 1.0) <= 0.041, "pitch variation about +-4%% (got %.3f)" % one.pitch_scale)
		check(absf(one.volume_db - linear_to_db(0.8)) <= 1.6, "volume variation about +-1.5 dB (got %.2f)" % one.volume_db)
	sfx.stop_all()
	for i in 3: await process_frame

	# --- spatial (3D) sound, docs/AUDIO.md "Spatial sound" ---
	# play_at with the headless dummy driver: no 3D pool is built (the node-count baselines of the other suites stay
	# untouched) and the sound falls back to the 2D pool.
	var kids3 := sfx.get_child_count()
	var nodes3 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var at0: int = sfx.at_calls
	sfx.play_at("boom", Vector3(3.0, 0.5, 4.0), 0.7)
	check(sfx.get_child_count() == kids3 and int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == nodes3, "play_at builds no nodes headless")
	check(sfx.at_calls == at0 + 1 and sfx.at_3d == 0, "headless play_at records the request and falls back to 2D")
	check(sfx.at_pos.distance_to(Vector3(3.0, 0.5, 4.0)) < 0.001, "play_at keeps the position it was given")

	# The test builds the pool under the headless driver (force_3d) to check its bound and the voice stealing.
	sfx.force_3d = true
	sfx.stop_all()
	for i in 3: await process_frame
	for i in sfx.POOL_3D + 4: sfx.play_at("shot", Vector3(float(i), 0.0, 0.0), 0.8)
	check(sfx._pool3d.size() == sfx.POOL_3D, "the 3D pool is bounded to %d voices (got %d)" % [sfx.POOL_3D, sfx._pool3d.size()])
	check(sfx.get_child_count() == kids3 + sfx.POOL_3D, "the 3D pool adds exactly %d nodes" % sfx.POOL_3D)
	check(sfx.at_3d == sfx.POOL_3D + 4, "play_at takes a 3D voice once the pool exists")
	var p3: AudioStreamPlayer3D = sfx._pool3d[0]
	check(p3.bus == "SFX" and p3.unit_size > 0.0 and p3.max_distance > p3.unit_size, "3D voices use the SFX bus and an arena-scale falloff")

	# Voice stealing: eight voices busy, the ninth sound takes the oldest one and moves it to the new source.
	sfx.stop_all()
	for i in 3: await process_frame
	sfx.play_at("click", Vector3.ZERO)
	OS.delay_msec(3)                                  # voice 0 is strictly the oldest start tick
	for i in range(1, sfx.POOL_3D): sfx.play_at("click", Vector3(float(i), 0.0, 0.0))
	check(sfx._pool3d[0].stream == sfx.streams["click"] and sfx._pool3d[0].playing, "a 3D voice plays the requested sound")
	sfx.play_at("boom", Vector3(20.0, 2.0, -6.0), 0.9)
	check(sfx._pool3d.size() == sfx.POOL_3D, "stealing a 3D voice allocates no node")
	check(sfx._pool3d[0].stream == sfx.streams["boom"], "a full 3D pool steals its oldest voice")
	check(sfx._pool3d[0].global_position.distance_to(Vector3(20.0, 2.0, -6.0)) < 0.001, "the stolen voice moves to the new source")

	# Settings > Audio "3D sound" off: play_at falls back to the 2D pool even though the 3D pool exists.
	var set3: Node = root.get_node("Settings")
	var at3: int = sfx.at_3d
	set3.set_value("sfx_3d", false)
	for i in 3: await process_frame
	sfx.play_at("boom", Vector3(9.0, 0.0, 9.0), 0.5)
	check(sfx.at_3d == at3, "3D off: play_at takes no 3D voice")
	var flat := false
	for c: Node in sfx.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing: flat = true
	check(flat, "3D off: play_at played through Sfx.play (2D)")
	set3.set_value("sfx_3d", true)

	# World events (what World._drain_events feeds to Sfx.on_event) reach play_at with their source position.
	var sim := MatchSim.new()
	var me := FighterState.new(); me.is_player = true; me.phys.px = 1.0; me.phys.pz = 2.0
	var foe := FighterState.new(); foe.phys.px = -12.0; foe.phys.py = 0.5; foe.phys.pz = 7.0
	sim.player = me
	sfx.stop_all()
	for i in 3: await process_frame
	sfx.on_event({"type": "sfx", "name": "clink", "x": 4.0, "y": 1.0, "z": -3.0}, sim)
	check(sfx.at_pos.distance_to(Vector3(4.0, 1.0, -3.0)) < 0.001, "a prop hit plays at the hit position")
	var n0: int = sfx.at_calls
	sfx.on_event({"type": "shot", "f": foe, "key": "ak"}, sim)
	check(sfx.at_calls == n0 + 1 and sfx.at_pos.distance_to(sfx.fighter_pos(foe)) < 0.001, "another fighter's gunshot plays at that fighter")
	n0 = sfx.at_calls
	sfx.on_event({"type": "shot", "f": me, "key": "ak"}, sim)
	check(sfx.at_calls == n0, "the local player's own gunshot stays 2D")
	sfx.on_event({"type": "crate_land", "crate": {"id": 1, "key": "ak", "x": -8.0, "z": 11.0, "gy": 2.0}}, sim)
	check(sfx.at_pos.distance_to(Vector3(-8.0, 2.4, 11.0)) < 0.001, "a crate landing plays at the crate")
	sfx.force_3d = false
	sfx.stop_all()

	# settings
	var settings: Node = root.get_node("Settings")
	var bus := AudioServer.get_bus_index("Master")
	settings.set_value("volume", 0.25)
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25)), "volume setting -> Master bus")
	settings.set_value("muted", true)
	check(AudioServer.is_bus_mute(bus), "muted setting mutes the Master bus")
	sfx.play("boom")
	var any := false
	for c: Node in sfx.get_children():
		if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing: any = true
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
