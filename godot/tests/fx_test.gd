extends SceneTree
## Effects test (docs/GRAPHICS.md "Effects"), headless:
##   POOL   every FxSystem pool on every effects level is flooded far past its cap: live counts never exceed the cap,
##          full pools recycle their oldest slots, everything expires, damage-number labels stay within their pool
##   MATCH  a seeded offline match with effects on (HIGH): pools, ribbons and labels stay within their caps every frame,
##          ribbon objects are reused, the effects actually ran (sparks, trails, hitstop, shake)
##   HASH   the same seeded match with effects off: the sim state hash after every second is identical (effects never
##          touch the sim, hitstop never changes gameplay timing)
##   godot --headless --path godot --script res://tests/fx_test.gd -- --no-save
## Prints POOL / MATCH / HASH lines, FAIL ... per broken check, then FX ok / FX FAILED.

const FRAME := 1.0 / 60.0
const SECS := 40
const SEED := 777

var failed := false
var runs: Array = []               ## per run: Array of hashes (one per second)
var world: Node
var stage := 0
var i := 0
var hashes: Array = []
var max_seen := {}
var trail_peak := 0
var trail_created := 0
var hitstops := 0
var shakes := 0
var ribbons_seen := 0

func check(ok: bool, msg: String) -> void:
	if not ok:
		failed = true
		print("FAIL " + msg)

func _initialize() -> void:
	var st := root.get_node("Settings")
	st.set_value("touch_mode", "off")
	st.set_value("effects", "high")
	st.set_value("screen_shake", true)
	_pools()
	process_frame.connect(_next, CONNECT_ONE_SHOT)

# ---------------------------------------------------------------- pools

func _pools() -> void:
	for lv in 3:
		var fx := FxSystem.new(lv)
		root.add_child(fx)
		var caps := {}
		for k: String in FxSystem.CAPS: caps[k] = FxSystem.CAPS[k][lv]
		var over := false
		for n in 400:                                  # far past every cap
			var at := Vector3(n % 7, 1, n % 5)
			fx.puff(at, Color.WHITE, 12, 5.0)
			fx.sparks(at, Color.RED, 60.0, 12.0)
			fx.explosion(at, 0.0, 4.0)
			fx.confetti(at, Color.BLUE)
			fx.dash(at, Vector3.FORWARD)
			fx.muzzle(at, Vector3.FORWARD, "ak")
			fx.dmg_number(at, 12.0, "head", 50)
			fx.update(FRAME, Vector3.ZERO)
			for k: String in caps:
				if fx.pools[k].n > caps[k]: over = true
		var s := fx.stats()
		var line := "POOL lv%d" % lv
		for k: String in caps:
			var p: Dictionary = s[k]
			line += " %s %d/%d (peak %d, recycled %d)" % [k, p["n"], p["cap"], p["peak"], p["recycled"]]
			check(p["peak"] <= p["cap"], "lv%d %s peak %d > cap %d" % [lv, k, p["peak"], p["cap"]])
			check(p["spawned"] > p["cap"], "lv%d %s never filled (%d spawned)" % [lv, k, p["spawned"]])
			check(p["recycled"] > 0, "lv%d %s never recycled" % [lv, k])
		check(not over, "lv%d a pool went over its cap" % lv)
		check(s["labels"]["n"] <= s["labels"]["cap"], "lv%d labels %d > %d" % [lv, s["labels"]["n"], s["labels"]["cap"]])
		var live0 := fx.live_count()
		for n in 240: fx.update(FRAME, Vector3.ZERO)   # 4 s: everything expires
		check(fx.live_count() == 0, "lv%d %d effects still live after 4 s" % [lv, fx.live_count()])
		for k: String in caps:
			check(fx.pools[k].mm.visible_instance_count == 0, "lv%d %s still drawn" % [lv, k])
		print(line + " | live %d -> %d | specks %d" % [live0, fx.live_count(), s["specks"]["n"]])
		fx.free()

# ---------------------------------------------------------------- matches

func _next() -> void:
	if world:
		runs.append(hashes.duplicate())
		world.free(); world = null
	if stage >= 2:
		_finish()
		return
	world = load("res://world/world.tscn").instantiate()
	world.map_id = "arena"
	world.auto_run = false
	world.bot_count = 7
	world.rng_seed = SEED
	world.dyn_choice = "off"
	world.mode_id = "classic"
	world.ko_limit = 0
	world.difficulty = "hard"
	world.fx_enabled = stage == 0
	root.add_child(world)
	world.touch.visible = false
	hashes.clear()
	i = 0
	process_frame.connect(_frame)

func _frame() -> void:
	world.tick(FRAME)
	i += 1
	if world.fx:
		if world._hitstop > 0: hitstops += 1
		if world.cam.shake > 0.0: shakes += 1
		var s: Dictionary = world.fx.stats()
		for k: String in s:
			max_seen[k] = maxi(int(max_seen.get(k, 0)), int(s[k]["n"]))
			check(int(s[k]["n"]) <= int(s[k]["cap"]), "match %s %d > cap %d" % [k, s[k]["n"], s[k]["cap"]])
		var tr: Trails = world.trails
		trail_peak = maxi(trail_peak, tr.live.size())
		trail_created = tr.created
		ribbons_seen += tr.tri_count()
		check(tr.live.size() <= tr.cap(), "ribbons %d > cap %d" % [tr.live.size(), tr.cap()])
	if i % 60 == 0:
		hashes.append(_hash())
	if i < SECS * 60:
		return
	process_frame.disconnect(_frame)
	if stage == 0:
		var c: Dictionary = world.counts
		var line := "MATCH fx on: hits %d kos %d shots %d explode %d | peaks" % [c.get("hit", 0), c.get("ko", 0), c.get("shot", 0), c.get("explode", 0)]
		for k: String in max_seen: line += " %s %d" % [k, max_seen[k]]
		line += " | ribbons peak %d made %d (cap %d) | hitstop frames %d | shake frames %d" % [trail_peak, trail_created, world.trails.cap(), hitstops, shakes]
		print(line)
		check(int(c.get("hit", 0)) > 5, "too few hits to test effects (%d)" % c.get("hit", 0))
		check(int(max_seen.get("bits", 0)) > 0, "no particles ran")
		check(ribbons_seen > 0, "no trail was drawn")
		check(trail_created <= world.trails.cap(), "ribbon objects not reused (%d made)" % trail_created)
		check(hitstops > 0, "hitstop never triggered")
		check(shakes > 0, "camera shake never triggered")
	stage += 1
	_next.call_deferred()

## The sim state: every fighter's physics, health, score, weapon and timers, the combat clock, live projectiles.
func _hash() -> int:
	var sim: MatchSim = world.sim
	var a: Array = [sim.combat.time]
	for f: FighterState in sim.fighters:
		var p := f.phys
		a.append_array([p.px, p.py, p.pz, p.vx, p.vy, p.vz, p.grounded, f.hp, f.ko, f.dead, f.weapon, f.swing, f.yaw,
			f.hand_x, f.hand_y, f.hand_z, int(f.st["deaths"])])
	a.append(sim.pickups.list.size())
	return var_to_str(a).hash()

func _finish() -> void:
	var on: Array = runs[0]
	var off: Array = runs[1]
	var first := -1
	for k in mini(on.size(), off.size()):
		if on[k] != off[k]:
			first = k; break
	print("HASH %d seconds compared, effects on vs off: %s" % [mini(on.size(), off.size()), "identical" if first < 0 and on.size() == off.size() else "DIFFER from second %d" % (first + 1)])
	check(first < 0 and on.size() == off.size() and on.size() == SECS, "sim hash differs with effects on vs off")
	print("FX ok" if not failed else "FX FAILED")
	quit(0 if not failed else 1)
