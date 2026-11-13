class_name PerfStats
extends RefCounted
## Pure maths and text for the on-device performance tools (docs/GRAPHICS.md "Measuring on device"): percentiles, the
## soak CSV format and the end-of-run summary. No nodes, so tests/perf_test.gd checks it with made-up rows.
## A row is one second of play (ui/perf_probe.gd): t, map, fps, frames, secs, slow_frames, frame_ms_avg / p95 / max,
## cpu_ms, gpu_ms (-1 = the renderer does not report it; the summary shows their medians), draws, objects, tier, thermal, mem_mb.

const COLUMNS := ["t", "map", "fps", "frames", "slow_frames", "frame_ms_avg", "frame_ms_p95", "frame_ms_max", "cpu_ms", "gpu_ms",
	"draws", "objects", "tier", "thermal", "mem_mb"]
## A frame over this is "slow": the 16.7 ms budget of 60 fps plus 0.8 ms of timer jitter (a missed refresh is 33 ms).
const SLOW_MS := 17.5
const PASS_FPS := 58.0               ## average fps for a pass (60 minus the jitter)
const PASS_SLOW_PCT := 5.0           ## at most this share of frames may be slow
const THROTTLE_DROP := 0.10          ## last third of the run this much slower than the first third = throttling suspected
const BAD_THERMAL := ["serious", "critical"]   ## iOS ProcessInfo.ThermalState names, when a plugin reports them

## Nearest-rank percentile (p in 0..1) of the values.
static func percentile(vals: PackedFloat64Array, p: float) -> float:
	if vals.is_empty(): return 0.0
	var s := vals.duplicate()
	s.sort()
	return s[clampi(ceili(p * s.size()) - 1, 0, s.size() - 1)]

static func csv_header() -> String:
	return ",".join(COLUMNS)

## One CSV line for a row (floats with 2 decimals, gpu_ms -1 left empty, no commas inside text).
static func csv_line(row: Dictionary) -> String:
	var out: PackedStringArray = []
	for c: String in COLUMNS:
		var v: Variant = row.get(c, "")
		if c == "gpu_ms" and (not (v is float or v is int) or float(v) < 0.0): out.append("")
		elif v is float: out.append("%.2f" % v)
		else: out.append(str(v).replace(",", " "))
	return ",".join(out)

static func _secs(r: Dictionary) -> float:
	return float(r["secs"]) if r.has("secs") else float(r["frames"]) / maxf(float(r["fps"]), 1e-6)

static func _avg_fps(rows: Array) -> float:
	var f := 0.0
	var s := 0.0
	for r: Dictionary in rows:
		f += float(r["frames"]); s += _secs(r)
	return f / s if s > 0.0 else 0.0

## Whole-run numbers from the rows: avg fps (frames / seconds), % slow frames, mean / worst p95, the worst 60 s window,
## fps of the first and last third (throttling hint), thermal changes and a verdict with its reasons.
static func summarize(rows: Array) -> Dictionary:
	var s := {"seconds": 0.0, "frames": 0, "avg_fps": 0.0, "slow_pct": 0.0, "p95_mean": 0.0, "p95_worst": 0.0, "cpu_ms": 0.0, "gpu_ms": -1.0,
		"draws_max": 0, "mem_mb_max": 0.0, "worst_minute": 0, "worst_minute_fps": 0.0, "first_third_fps": 0.0, "last_third_fps": 0.0,
		"throttle_suspected": false, "thermal_changes": 0, "thermal_known": false, "thermal_bad": false, "tiers": [], "maps": [],
		"verdict": "NO DATA", "reasons": []}
	if rows.is_empty(): return s
	var frames := 0
	var slow := 0
	var secs := 0.0
	var p95_sum := 0.0
	var cpu := PackedFloat64Array()           # medians below: a map load hitches one row and should not colour the run
	var gpu := PackedFloat64Array()
	var minutes := {}                        # minute index -> [frames, secs]
	for i in rows.size():
		var r: Dictionary = rows[i]
		var rs := _secs(r)
		frames += int(r["frames"]); slow += int(r["slow_frames"]); secs += rs
		p95_sum += float(r["frame_ms_p95"]); s["p95_worst"] = maxf(float(s["p95_worst"]), float(r["frame_ms_p95"]))
		cpu.append(float(r.get("cpu_ms", 0.0)))
		if float(r.get("gpu_ms", -1.0)) >= 0.0: gpu.append(float(r["gpu_ms"]))
		s["draws_max"] = maxi(int(s["draws_max"]), int(r.get("draws", 0)))
		s["mem_mb_max"] = maxf(float(s["mem_mb_max"]), float(r.get("mem_mb", 0.0)))
		var m := int(floor((float(r["t"]) - 0.001) / 60.0))
		var mm: Array = minutes.get(m, [0.0, 0.0])
		mm[0] += float(r["frames"]); mm[1] += rs
		minutes[m] = mm
		var th := str(r.get("thermal", "n/a"))
		if th != "n/a": s["thermal_known"] = true
		if th in BAD_THERMAL: s["thermal_bad"] = true
		if i > 0 and th != str(rows[i - 1].get("thermal", "n/a")): s["thermal_changes"] = int(s["thermal_changes"]) + 1
		var tier := str(r.get("tier", ""))
		if tier != "" and not (s["tiers"] as Array).has(tier): (s["tiers"] as Array).append(tier)
		var mp := str(r.get("map", ""))
		if mp != "" and not (s["maps"] as Array).has(mp): (s["maps"] as Array).append(mp)
	s["seconds"] = secs; s["frames"] = frames
	s["avg_fps"] = frames / secs if secs > 0.0 else 0.0
	s["slow_pct"] = 100.0 * slow / maxi(frames, 1)
	s["p95_mean"] = p95_sum / rows.size()
	s["cpu_ms"] = percentile(cpu, 0.5)
	if not gpu.is_empty(): s["gpu_ms"] = percentile(gpu, 0.5)
	var worst := INF
	for m: int in minutes:
		var mm: Array = minutes[m]
		if mm[1] < 5.0: continue              # a stub of a minute at the end says nothing
		var f: float = mm[0] / mm[1]
		if f < worst: worst = f; s["worst_minute"] = m + 1
	s["worst_minute_fps"] = worst if worst != INF else s["avg_fps"]
	if rows.size() >= 6:
		var n := rows.size() / 3
		s["first_third_fps"] = _avg_fps(rows.slice(0, n))
		s["last_third_fps"] = _avg_fps(rows.slice(rows.size() - n))
		s["throttle_suspected"] = float(s["last_third_fps"]) < float(s["first_third_fps"]) * (1.0 - THROTTLE_DROP)
	else:
		s["first_third_fps"] = s["avg_fps"]; s["last_third_fps"] = s["avg_fps"]
	var why: Array = s["reasons"]
	if float(s["avg_fps"]) < PASS_FPS: why.append("average fps %.1f is under %d" % [s["avg_fps"], int(PASS_FPS)])
	if float(s["slow_pct"]) > PASS_SLOW_PCT: why.append("%.1f %% of frames over %.1f ms (limit %d %%)" % [s["slow_pct"], SLOW_MS, int(PASS_SLOW_PCT)])
	if s["throttle_suspected"]: why.append("fps fell from %.1f to %.1f over the run (throttling?)" % [s["first_third_fps"], s["last_third_fps"]])
	if s["thermal_bad"]: why.append("thermal state reached serious / critical")
	s["verdict"] = "PASS" if why.is_empty() else "FAIL"
	return s

## The summary as plain text (the card's copy button, the .txt next to the CSV). `meta`: device, tier, renderer, build, csv.
static func summary_text(s: Dictionary, meta: Dictionary = {}) -> String:
	var L: PackedStringArray = []
	L.append("Wobblers Arena soak test: %s" % s["verdict"])
	for k: String in ["device", "build", "renderer", "csv"]:
		if meta.has(k): L.append("%s: %s" % [k, meta[k]])
	L.append("tier: %s   maps: %s" % [", ".join(s["tiers"]), ", ".join(s["maps"])])
	L.append("length: %s (%d frames)" % [mmss(float(s["seconds"])), int(s["frames"])])
	L.append("average fps: %.1f" % s["avg_fps"])
	L.append("frames over %.1f ms: %.2f %%" % [SLOW_MS, s["slow_pct"]])
	L.append("frame p95: mean %.1f ms, worst %.1f ms" % [s["p95_mean"], s["p95_worst"]])
	L.append("worst minute: #%d at %.1f fps" % [s["worst_minute"], s["worst_minute_fps"]])
	L.append("fps first third -> last third: %.1f -> %.1f%s" % [s["first_third_fps"], s["last_third_fps"], "  (DROP)" if s["throttle_suspected"] else ""])
	L.append("thermal: %s" % (("%d change(s)" % s["thermal_changes"]) if s["thermal_known"] else "n/a (iOS gives Godot no thermal state; judge by the fps trend)"))
	L.append("cpu %.1f ms   gpu %s   draws max %d   memory max %.0f MB" % [s["cpu_ms"], ("%.1f ms" % s["gpu_ms"]) if float(s["gpu_ms"]) >= 0.0 else "n/a", s["draws_max"], s["mem_mb_max"]])
	for r: String in s["reasons"]: L.append("! " + r)
	return "\n".join(L)

static func mmss(secs: float) -> String:
	var t := int(round(secs))
	return "%d:%02d" % [t / 60, t % 60]
