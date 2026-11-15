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

## Fighter mesh budget (post-v0.4.0 Sprint 4.2): every offline scene below runs with 10 fighters. The `solo1` scene is
## the same map with ONE fighter, so its draw-call difference from `farm` is the fighters' own cost INCLUDING the
## shadow passes the renderer actually runs (HIGH 4 cascades, MID 2, LOW none: LOW fighters don't cast shadows, the
## blob shadows are custom `_draw` nodes and never appear in the draw-call counter). Printed per scene and for `solo1`.
const FARM := "farm"
const MESH_BUDGET := 16        # per-fighter MeshInstance3D ceiling (world looks, weapon included; see Wobbler.mesh_stats)
const SURF_BUDGET := 18        # per-fighter surface (draw-call) ceiling, main pass + shadow casters use the same surfaces

var scene_id := ""
var scene_map := ""
var scene_bots := 9
var farm_draws_10 := 0
var farm_draws_1 := 0

func _initialize() -> void:
	headless = DisplayServer.get_name() == "headless"
	var q := int(root.get_node("Tier").quality())
	tier_name = ["LOW", "MID", "HIGH"][q]
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("GFX tier %s renderer %s%s" % [tier_name, RenderingServer.get_current_rendering_method(), " (headless: CPU only)" if headless else ""])
	process_frame.connect(_next, CONNECT_ONE_SHOT)

## The scene list: the four benchmark maps with 10 fighters, then one fighter on Farm for the fighters' own draw cost.
static func scenes() -> Array:
	var out: Array = []
	for m: String in MAPS:
		out.append([m, FX_MAP if m == "fx" else m, 9])
	out.append(["solo1", FARM, 0])
	return out

func _next() -> void:
	if world: world.free(); world = null
	var all := scenes()
	if k >= all.size():
		if not headless and farm_draws_10 > 0:
			print("GFX draws farm 10 fighters=%d 1 fighter=%d -> fighters %d (%.0f%% of the 10-fighter frame)" % [
				farm_draws_10, farm_draws_1, farm_draws_10 - farm_draws_1,
				100.0 * float(farm_draws_10 - farm_draws_1) / maxf(1.0, float(farm_draws_10))])
		print("GFX ok" if not failed else "GFX FAILED")
		quit(0 if not failed else 1)
		return
	scene_id = all[k][0]
	scene_map = all[k][1]
	scene_bots = int(all[k][2])
	world = load("res://world/world.tscn").instantiate()
	world.map_id = scene_map
	world.auto_run = false
	world.bot_count = scene_bots
	world.rng_seed = 4242
	world.dyn_choice = "off"
	world.ko_limit = 0
	if scene_id == "solo1":
		world.mode_id = "classic"
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
	if scene_id == "fx": _stress()
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
	if scene_id == "fx": _fx_check()
	n += 1
	if n < WARM + FRAMES:
		return
	process_frame.disconnect(_frame)
	_report(scene_id)
	k += 1
	_next.call_deferred()

## The fighters' visible mesh cost: MeshInstance3D nodes and their surfaces under every Fighter (hidden weapon holders
## are excluded from the visible numbers; the "all" numbers show what is retained in the tree).
func _fighter_stats() -> Dictionary:
	var meshes := 0
	var meshes_vis := 0
	var surfaces := 0
	var surfaces_vis := 0
	for v: Variant in world.views.values():
		var node: Node = v
		meshes += _count_meshes(node, false)
		meshes_vis += _count_meshes(node, true)
		surfaces += _count_surfaces(node, false)
		surfaces_vis += _count_surfaces(node, true)
	return {"fighters": world.views.size(), "meshes": meshes_vis, "meshes_all": meshes,
		"surfaces": surfaces_vis, "surfaces_all": surfaces}

func _count_meshes(n: Node, visible_only: bool) -> int:
	var k := 1 if n is MeshInstance3D and (not visible_only or (n as MeshInstance3D).is_visible_in_tree()) else 0
	for ch in n.get_children():
		k += _count_meshes(ch, visible_only)
	return k

func _count_surfaces(n: Node, visible_only: bool) -> int:
	var k := 0
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if not visible_only or mi.is_visible_in_tree():
			var mesh: Mesh = mi.mesh
			if mesh != null: k += mesh.get_surface_count()
	for ch in n.get_children():
		k += _count_surfaces(ch, visible_only)
	return k

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
	var fs := _fighter_stats()
	var per_ms := float(fs["meshes"]) / maxf(1.0, float(fs["fighters"]))
	var per_sf := float(fs["surfaces"]) / maxf(1.0, float(fs["fighters"]))
	var line := "GFX %s %-10s fighters %d | cpu %.2f ms (p95 %.2f) | fighter meshes %d (%.1f/fighter) surfaces %d (%.1f/fighter) nodes-kept %d" % [
		tier_name, id, world.sim.fighters.size(), c, _p95(cpu), fs["meshes"], per_ms, fs["surfaces"], per_sf, fs["meshes_all"]]
	if id == "fx":
		line += " | fx lv %d peaks %s" % [world.fx.lv, str(fx_peak).replace(" ", "")]
	_check(c <= b["cpu"], "%s %s cpu %.2f ms > %.1f" % [tier_name, id, c, b["cpu"]])
	if fs["fighters"] > 0 and per_ms > MESH_BUDGET:
		_check(false, "%s %s fighter meshes %.1f per fighter > %d" % [tier_name, id, per_ms, MESH_BUDGET])
	if fs["fighters"] > 0 and per_sf > SURF_BUDGET:
		_check(false, "%s %s fighter surfaces %.1f per fighter > %d" % [tier_name, id, per_sf, SURF_BUDGET])
	if int(fs["fighters"]) >= 10:          # the 10-fighter world gate (docs/GRAPHICS.md: 135/155 measured)
		_check(int(fs["meshes"]) <= 150, "%s %s 10-fighter meshes %d > 150" % [tier_name, id, fs["meshes"]])
		_check(int(fs["surfaces"]) <= 175, "%s %s 10-fighter surfaces %d > 175" % [tier_name, id, fs["surfaces"]])
	if headless:
		print(line)
		return
	var f := _mean(wall)
	var d := _max(draws)
	var p := _max(prims)
	line += " | frame %.2f ms (p95 %.2f) | draws %d | prims %d | objects %d" % [f, _p95(wall), d, p, _max(objs)]
	print(line)
	if id == "farm":
		farm_draws_10 = d
	elif id == "solo1":
		farm_draws_1 = d
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
