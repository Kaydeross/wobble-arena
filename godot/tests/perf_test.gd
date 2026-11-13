extends SceneTree
## Performance tools test (headless): PerfStats maths (percentile, CSV line, summary of made-up rows: avg fps, % slow
## frames, worst minute, throttling hint, thermal changes, verdict), the readout exists only while Settings
## `perf_overlay` is on, and a shortened soak run (10 s over two maps, user://soak_test) writes a CSV with the right
## columns and a row a second, switches maps, ends with the summary card, a .txt and a clipboard-ready summary.
## The overlay-versus-HUD layout check is in hud_test.gd.
##   godot --headless --path godot --script res://tests/perf_test.gd -- --no-save   (npm run test:godot-perf)

const DIR := "user://soak_test"
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _row(t: float, fps: float, p95 := 16.7, thermal := "n/a") -> Dictionary:
	var frames := int(fps)
	return {"t": t, "map": "farm", "secs": 1.0, "frames": frames, "fps": fps, "slow_frames": 0 if fps >= 60.0 else frames,
		"frame_ms_avg": 1000.0 / fps, "frame_ms_p95": p95, "frame_ms_max": p95 + 1.0, "cpu_ms": 4.0, "gpu_ms": 6.0, "draws": 600, "objects": 900,
		"tier": "MID", "thermal": thermal, "mem_mb": 300.0}

func _stats() -> void:
	var v := PackedFloat64Array([5, 1, 3, 2, 4, 10, 9, 8, 7, 6])
	check(PerfStats.percentile(v, 0.95) == 10.0 and PerfStats.percentile(v, 0.5) == 5.0 and PerfStats.percentile(v, 0.1) == 1.0, "percentile (nearest rank)")
	check(PerfStats.percentile(PackedFloat64Array(), 0.95) == 0.0, "percentile of nothing")
	var line := PerfStats.csv_line(_row(3.0, 60.0))
	check(line.split(",").size() == PerfStats.COLUMNS.size(), "csv line has one field per column (%s)" % line)
	check(line.begins_with("3.00,farm,60.00,60,0,"), "csv line starts t,map,fps,frames,slow (%s)" % line)
	var no_gpu := _row(1.0, 60.0); no_gpu["gpu_ms"] = -1.0
	check(PerfStats.csv_line(no_gpu).split(",")[9] == "", "gpu_ms -1 is an empty field")
	check(PerfStats.csv_header().split(",").size() == 15 and PerfStats.csv_header().begins_with("t,map,fps,"), "csv header")
	# 60 s at 60 fps then 60 s at 30 fps (every frame slow)
	var rows := []
	for i in 120: rows.append(_row(i + 1.0, 60.0 if i < 60 else 30.0))
	var s := PerfStats.summarize(rows)
	check(int(s["frames"]) == 5400 and absf(float(s["seconds"]) - 120.0) < 1e-6, "frames / seconds (%s / %s)" % [s["frames"], s["seconds"]])
	check(absf(float(s["avg_fps"]) - 45.0) < 1e-6, "avg fps is frames / seconds, not the mean of the rows (%s)" % s["avg_fps"])
	check(absf(float(s["slow_pct"]) - 100.0 * 1800.0 / 5400.0) < 1e-6, "slow frame share (%s)" % s["slow_pct"])
	check(int(s["worst_minute"]) == 2 and absf(float(s["worst_minute_fps"]) - 30.0) < 1e-6, "worst minute (#%s %s)" % [s["worst_minute"], s["worst_minute_fps"]])
	check(absf(float(s["first_third_fps"]) - 60.0) < 1e-6 and absf(float(s["last_third_fps"]) - 30.0) < 1e-6 and s["throttle_suspected"], "fps trend flags throttling")
	check(s["verdict"] == "FAIL" and (s["reasons"] as Array).size() == 3, "verdict FAIL with three reasons (%s)" % [s["reasons"]])
	check(int(s["thermal_changes"]) == 0 and not s["thermal_known"], "no thermal data = no changes")
	var good := []
	var th := ["nominal", "nominal", "fair", "fair", "fair", "nominal"]
	for i in 180: good.append(_row(i + 1.0, 60.0, 16.7, th[i / 30]))
	var g := PerfStats.summarize(good)
	check(g["verdict"] == "PASS" and (g["reasons"] as Array).is_empty(), "steady 60 fps passes (%s)" % [g["reasons"]])
	check(int(g["thermal_changes"]) == 2 and g["thermal_known"], "thermal changes counted (%s)" % g["thermal_changes"])
	check(int(g["worst_minute"]) >= 1 and absf(float(g["worst_minute_fps"]) - 60.0) < 1e-6, "worst minute of a steady run")
	good[170]["thermal"] = "serious"
	check(PerfStats.summarize(good)["verdict"] == "FAIL", "a serious thermal state fails")
	check(PerfStats.summarize([])["verdict"] == "NO DATA", "no rows")
	var txt := PerfStats.summary_text(s, {"device": "test"})
	check(txt.contains("average fps: 45.0") and txt.contains("worst minute: #2") and txt.contains("FAIL") and txt.contains("n/a"), "summary text")
	check(PerfOverlay.format(_row(1.0, 60.0)).contains("60 fps") and PerfOverlay.format(_row(1.0, 60.0)).contains("thermal n/a"), "readout text")
	check(PerfStats.mmss(905.0) == "15:05", "mm:ss")

func _run() -> void:
	_stats()
	# the readout exists only while the setting is on
	var st: Node = root.get_node("Settings")
	st.set_value("perf_overlay", false)
	await process_frame
	check(root.get_node_or_null("PerfOverlay") == null, "no readout node when the setting is off")
	st.set_value("perf_overlay", true)
	await process_frame; await process_frame
	var ov: PerfOverlay = root.get_node_or_null("PerfOverlay")
	check(ov != null, "readout node when on")
	st.set_value("perf_overlay", false)
	await process_frame; await process_frame
	check(root.get_node_or_null("PerfOverlay") == null, "readout freed when turned off")
	check(PerfProbe.thermal_state() == "n/a", "thermal state is n/a without a plugin")
	# a 10 s soak over two maps
	_clean()
	var world: Node = SoakRun.make_world(10.0, ["farm", "arenaxl"], DIR)
	root.add_child(world)
	var soak: SoakRun = world.soak
	check(soak != null and world.sim.fighters.size() == 10, "soak world: Chaos 5v5 (%d fighters)" % world.sim.fighters.size())
	check(world.map_id == "farm" and world.mode_id == "chaos", "starts on the first map in Chaos")
	var maps_seen := {}
	var t0 := Time.get_ticks_msec()
	while not soak.done and Time.get_ticks_msec() - t0 < 60000:
		maps_seen[world.map_id] = true
		await process_frame
	check(soak.done, "soak finished")
	check(maps_seen.has("farm") and maps_seen.has("arenaxl"), "both maps played (%s)" % [maps_seen.keys()])
	check(soak.rows.size() >= 8 and soak.rows.size() <= 11, "about a row a second (%d)" % soak.rows.size())
	var f := FileAccess.open(soak.csv_path, FileAccess.READ)
	check(f != null and soak.csv_path.begins_with(DIR + "/") and soak.csv_path.ends_with(".csv"), "csv in the soak folder (%s)" % soak.csv_path)
	if f:
		var lines := f.get_as_text().strip_edges().split("\n")
		check(lines[0] == PerfStats.csv_header(), "csv header row")
		check(lines.size() == soak.rows.size() + 1, "one csv line per row (%d / %d)" % [lines.size(), soak.rows.size()])
		var maps_col := {}
		for i in range(1, lines.size()):
			var c := lines[i].split(",")
			check(c.size() == PerfStats.COLUMNS.size(), "csv row %d has %d fields" % [i, c.size()])
			maps_col[c[1]] = true
			check(float(c[2]) > 0.0 and int(c[3]) > 0 and c[12] != "", "csv row %d has fps, frames, tier" % i)
		check(maps_col.has("farm") and maps_col.has("arenaxl"), "csv records both maps (%s)" % [maps_col.keys()])
	var s: Dictionary = soak.summary
	check(float(s["avg_fps"]) > 0.0 and int(s["frames"]) > 100 and float(s["seconds"]) > 7.0, "summary numbers (%s fps, %s frames, %s s)" % [s.get("avg_fps"), s.get("frames"), s.get("seconds")])
	check(s["verdict"] in ["PASS", "FAIL"], "verdict is set")
	check(soak.card != null and soak.card.is_inside_tree() and soak.card.find_child("Copy", true, false) != null and soak.card.find_child("Back", true, false) != null, "summary card with Copy and Back")
	check(soak.stat_pairs().size() == 8, "card stats")
	check(FileAccess.file_exists(soak.txt_path) and FileAccess.get_file_as_string(soak.txt_path).contains("average fps"), "summary .txt next to the csv")
	check(soak.text.contains("soak test") and soak.text.contains(soak.csv_path.get_file()), "summary text names the csv")
	world.queue_free()
	await process_frame
	check(not root.disable_3d, "3D rendering is back on after the run")
	_clean()
	print("PERF ok" if fails == 0 else "PERF failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d:
		for fn in d.get_files(): d.remove(fn)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR))
