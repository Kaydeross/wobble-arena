class_name PerfProbe
extends RefCounted
## Collects frame times and renderer numbers and turns each second of them into one row (logic/perf_stats.gd).
## Used by the on-screen readout (ui/perf_overlay.gd) and the soak run (world/soak_run.gd). Does nothing until `begin`;
## `end` switches the renderer's timing queries off again. Per frame it costs one array append and a few monitor reads.

var _dts := PackedFloat64Array()
var _cpu := 0.0                 ## sum of per-frame process ms
var _gpu := 0.0                 ## sum of per-frame GPU ms (frames that reported one)
var _gpu_n := 0
var _draws := 0.0
var _objs := 0.0
var _rid := RID()
var secs := 0.0                 ## seconds collected since the last take()

func begin(vp: Viewport) -> void:
	_rid = vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	_reset()

func end() -> void:
	if _rid.is_valid(): RenderingServer.viewport_set_measure_render_time(_rid, false)
	_rid = RID()

func _reset() -> void:
	_dts.clear(); _cpu = 0.0; _gpu = 0.0; _gpu_n = 0; _draws = 0.0; _objs = 0.0; secs = 0.0

func add_frame(dt: float) -> void:
	_dts.append(dt)
	secs += dt
	_cpu += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	if _rid.is_valid():
		var g := RenderingServer.viewport_get_measured_render_time_gpu(_rid)   # 0 where the renderer cannot time (Compatibility, headless)
		if g > 0.0: _gpu += g; _gpu_n += 1

## One row for the frames since the last take (empty when there were none); starts the next window.
func take(t: float, map: String = "") -> Dictionary:
	var n := _dts.size()
	if n == 0: return {}
	var slow := 0
	var mx := 0.0
	for d in _dts:
		if d * 1000.0 > PerfStats.SLOW_MS: slow += 1
		mx = maxf(mx, d)
	var row := {"t": snappedf(t, 0.1), "map": map, "secs": secs, "frames": n, "fps": n / maxf(secs, 1e-6), "slow_frames": slow,
		"frame_ms_avg": secs / n * 1000.0, "frame_ms_p95": PerfStats.percentile(_dts, 0.95) * 1000.0, "frame_ms_max": mx * 1000.0,
		"cpu_ms": _cpu / n, "gpu_ms": _gpu / _gpu_n if _gpu_n > 0 else -1.0, "draws": int(round(_draws / n)), "objects": int(round(_objs / n)),
		"tier": tier_name(), "thermal": thermal_state(), "mem_mb": memory_mb()}
	_reset()
	return row

## Static + video memory the engine tracks, in MB (not the iOS footprint: that is in Xcode's gauges).
static func memory_mb() -> float:
	return (Performance.get_monitor(Performance.MEMORY_STATIC) + Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0

## Render tier of this run (LOW / MID / HIGH quality, from the Tier autoload; looked up so this file compiles before it exists).
static func tier_name() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var t: Node = tree.root.get_node_or_null("Tier") if tree and tree.root else null
	return ["LOW", "MID", "HIGH"][int(t.quality())] if t else "n/a"

## Godot 4.7 has no thermal API on iOS (nor battery temperature). "n/a" unless a native plugin registered a singleton
## `WobbleThermal` with `state() -> String` (nominal / fair / serious / critical = ProcessInfo.ThermalState); see docs/GRAPHICS.md.
static func thermal_state() -> String:
	if Engine.has_singleton("WobbleThermal"):
		return str(Engine.get_singleton("WobbleThermal").call("state"))
	return "n/a"
