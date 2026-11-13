extends SceneTree
## Graphics budget bench (docs/GRAPHICS.md). Builds three heavy maps with 10 fighters (the player + 9 bots) in the
## offline world on the current tier (`-- --tier=pc|mobile|web`, run with the matching --rendering-method), plays
## them for a while and records per map: CPU time of the match step (sim + fighters + camera, World.tick), the wall
## time of whole frames (vsync off: CPU + GPU on this machine), and from RenderingServer the draw calls, primitives
## and objects of a frame. Headless runs have no renderer: then only the CPU numbers are measured and checked.
##   godot --path godot [--headless] [--rendering-method mobile] --script res://tests/gfx_bench.gd -- --tier=mobile
## Prints `GFX <tier> <map> ...` per map, `FAIL ...` for every number over its budget, then `GFX ok` / `GFX FAILED`.
## The fourth scene, `fx`, is the effects stress test (docs/GRAPHICS.md "Effects"): Farm with 10 fighters, bots armed
## with melee weapons (swing trails) and, every frame, synthetic Combat events on top of the real fight: hits with
## sparks, explosions, flames, muzzle flashes, dashes and K.O. confetti, so every pool runs at or near its cap on the
## tier's effects level. Same budgets; also fails if a pool or the ribbons go over their caps.

const FRAME := 1.0 / 60.0
const WARM := 90           # frames before measuring (shader compiles, first shadow renders)
const FRAMES := 240
const MAPS := ["farm", "candy", "craterdome", "fx"]
const FX_MAP := "farm"

## Budgets per tier (docs/GRAPHICS.md has the measured numbers and the reasoning). cpu = mean ms of World.tick on
## the dev machine (sim + 10 fighters' animation + camera; a phone CPU is ~3x slower, so 4 ms here is ~12 ms on an
## iPhone 12, inside its 16.6 ms frame with room for the render thread); draws / prims = the busiest frame including
## shadow passes (device independent; ~10 fighters x ~35 parts are most of the draws); frame = mean wall ms of a whole
## frame here (vsync may cap it at the display rate), a loose sanity check only.
const BUDGET := {
	"HIGH": {"cpu": 4.0, "draws": 1400, "prims": 200000, "frame": 16.6},
	"MID": {"cpu": 4.0, "draws": 800, "prims": 130000, "frame": 12.0},
	"LOW": {"cpu": 4.0, "draws": 650, "prims": 110000, "frame": 12.0},
}

var tier_name := ""
var k := 0
var world: Node
var n := 0
var cpu: Array = []
var wall: Array = []
var draws: Array = []
var prims: Array = []
var objs: Array = []
var t_last := 0
var failed := false
var headless := false
var rng := RandomNumberGenerator.new()
var fx_peak := {}

func _initialize() -> void:
	headless = DisplayServer.get_name() == "headless"
	var q := int(root.get_node("Tier").quality())
	tier_name = ["LOW", "MID", "HIGH"][q]
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("GFX tier %s renderer %s%s" % [tier_name, RenderingServer.get_current_rendering_method(), " (headless: CPU only)" if headless else ""])
	process_frame.connect(_next, CONNECT_ONE_SHOT)

func _next() -> void:
	if world: world.free(); world = null
	if k >= MAPS.size():
		print("GFX ok" if not failed else "GFX FAILED")
		quit(0 if not failed else 1)
		return
	world = load("res://world/world.tscn").instantiate()
	world.map_id = FX_MAP if MAPS[k] == "fx" else MAPS[k]
	world.auto_run = false
	world.bot_count = 9
	world.rng_seed = 4242
	world.dyn_choice = "off"
	world.ko_limit = 0
	root.add_child(world)
	world.touch.visible = false
	n = 0
	cpu.clear(); wall.clear(); draws.clear(); prims.clear(); objs.clear()
	fx_peak.clear()
	rng.seed = 99
	t_last = Time.get_ticks_usec()
	process_frame.connect(_frame)

func _frame() -> void:
	var now := Time.get_ticks_usec()
	if MAPS[k] == "fx": _stress()
	var t0 := Time.get_ticks_usec()
	world.tick(FRAME)
	var t1 := Time.get_ticks_usec()
	if n >= WARM:
		cpu.append((t1 - t0) / 1000.0)
		wall.append((now - t_last) / 1000.0)
		if not headless:
			draws.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			prims.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
			objs.append(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))
	t_last = now
	if MAPS[k] == "fx": _fx_check()
	n += 1
	if n < WARM + FRAMES:
		return
	process_frame.disconnect(_frame)
	_report(MAPS[k])
	k += 1
	_next.call_deferred()

## Effects stress: synthetic visual events on top of the fight (they only feed the effects; the bench never compares
## sim state). Bots get melee weapons now and then so swing trails run too.
func _stress() -> void:
	var sim: MatchSim = world.sim
	var fs: Array = sim.fighters
	var pick := func() -> FighterState: return fs[rng.randi_range(1, fs.size() - 1)]
	if n % 90 == 0:
		for f: FighterState in fs:
			if not f.is_player and not f.dead: sim.combat.pickup(f, ["katana", "bat", "trident", "mallet"][rng.randi() % 4])
	for j in 2:
		var v: FighterState = pick.call()
		sim.combat.ev({"type": "hit", "f": v, "attacker": pick.call(), "dmg": rng.randf_range(10, 60), "head": false,
			"force": rng.randf_range(4, 16), "part": ["head", "torso", "arms", "legs"][rng.randi() % 4],
			"x": v.chest_x, "y": v.chest_y, "z": v.chest_z})
	var a: FighterState = pick.call()
	if n % 6 == 0:
		sim.combat.ev({"type": "explode", "x": a.phys.px, "y": a.phys.py + 1.0, "z": a.phys.pz, "gy": a.phys.py, "rad": 4.0})
	if n % 3 == 0: sim.combat.ev({"type": "shot", "f": a, "key": "ak"})
	if n % 10 == 0: sim.combat.ev({"type": "puff", "kind": "dash", "x": a.phys.px, "y": a.phys.py + 0.9, "z": a.phys.pz, "dx": 1.0, "dz": 0.0})
	if n % 20 == 0: sim.combat.ev({"type": "ko", "killer": pick.call(), "victim": a, "weapon": "Katana"})
	for j in 3:
		sim.combat.ev({"type": "flame", "x": a.phys.px, "y": a.phys.py + 1.2, "z": a.phys.pz, "vx": rng.randf_range(-3, 3), "vy": 2.0, "vz": rng.randf_range(-3, 3), "life": 0.5})

func _fx_check() -> void:
	if world.fx == null: return
	var s: Dictionary = world.fx.stats()
	for key: String in s:
		fx_peak[key] = maxi(int(fx_peak.get(key, 0)), int(s[key]["n"]))
		_check(int(s[key]["n"]) <= int(s[key]["cap"]), "fx %s %d > cap %d" % [key, s[key]["n"], s[key]["cap"]])
	fx_peak["ribbons"] = maxi(int(fx_peak.get("ribbons", 0)), world.trails.live.size())
	_check(world.trails.live.size() <= world.trails.cap(), "ribbons %d > cap %d" % [world.trails.live.size(), world.trails.cap()])

func _report(id: String) -> void:
	var b: Dictionary = BUDGET[tier_name]
	var c := _mean(cpu)
	var line := "GFX %s %-10s fighters %d | cpu %.2f ms (p95 %.2f)" % [tier_name, id, world.sim.fighters.size(), c, _p95(cpu)]
	if id == "fx":
		line += " | fx lv %d peaks %s" % [world.fx.lv, str(fx_peak).replace(" ", "")]
	_check(c <= b["cpu"], "%s %s cpu %.2f ms > %.1f" % [tier_name, id, c, b["cpu"]])
	if headless:
		print(line)
		return
	var f := _mean(wall)
	var d := _max(draws)
	var p := _max(prims)
	line += " | frame %.2f ms (p95 %.2f) | draws %d | prims %d | objects %d" % [f, _p95(wall), d, p, _max(objs)]
	print(line)
	_check(d <= b["draws"], "%s %s draw calls %d > %d" % [tier_name, id, d, b["draws"]])
	_check(p <= b["prims"], "%s %s primitives %d > %d" % [tier_name, id, p, b["prims"]])
	_check(f <= b["frame"], "%s %s frame %.2f ms > %.1f" % [tier_name, id, f, b["frame"]])

func _check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		print("FAIL " + msg)

func _mean(a: Array) -> float:
	var s := 0.0
	for x in a: s += float(x)
	return s / maxf(1.0, a.size())

func _max(a: Array) -> int:
	var m := 0
	for x in a: m = maxi(m, int(x))
	return m

func _p95(a: Array) -> float:
	if a.is_empty(): return 0.0
	var s := a.duplicate()
	s.sort()
	return float(s[mini(s.size() - 1, int(s.size() * 0.95))])
