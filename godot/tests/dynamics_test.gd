extends SceneTree
## Dynamic arenas parity and behaviour (run by tools/test-godot-dynamics.js, which writes the JS vectors):
##   godot --headless --path godot --script res://tests/dynamics_test.gd -- --no-save VECTORS_JSON
## 1. Dynamics.* against the web game's DYN-PURE functions: hashes, plans and resolves exact; floats within 1e-9.
## 2. ArenaDyn collision: the floor is split into tiles in the same place and order, and every solid follows the offsets
##    (and drift deltas) over 40 s of 1/120 s steps.
## 3. Fighters ride moving tiles and drifting blocks; MatchSim wires the clock; NetMatch.rule_dyn reads start.rules.

const TOL := 1e-9
var fails := 0
var checks := 0
var worst := 0.0

func check(c: bool, msg: String) -> void:
	checks += 1
	if not c:
		fails += 1
		if fails <= 30: print("FAIL ", msg)

func close(a: float, b: float, msg: String) -> void:
	var e := absf(a - b)
	if e > worst: worst = e
	check(e <= TOL, "%s: godot %s js %s (err %s)" % [msg, a, b, e])

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var V: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[args.size() - 1]))
	_pure(V)
	_maps(V)
	_sims(V)
	_riders()
	_net()
	print("DYN %s checks=%d fails=%d worst_float_error=%s" % ["ok" if fails == 0 else "FAILED", checks, fails, worst])
	quit(0 if fails == 0 else 1)

func _pure(V: Dictionary) -> void:
	for r: Array in V["hash"]:
		var h := Dynamics.hash32(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		check(h == int(r[4]), "hash%s = %d, js %d" % [r.slice(0, 4), h, int(r[4])])
	for r: Array in V["rand"]:
		close(Dynamics.rand(int(r[0]), int(r[1]), int(r[2]), int(r[3])), r[4], "rand%s" % [r.slice(0, 4)])
	for r: Array in V["ramp"]:
		close(Dynamics.ramp(r[0]), r[1], "ramp(%s)" % r[0])
	for r: Array in V["resolve"]:
		var k := Dynamics.resolve(r[0], int(r[1]), r[2], r[3])
		check(k == r[4], "resolve%s = %s, js %s" % [r.slice(0, 4), k, r[4]])
	for r: Array in V["offset"]:
		close(Dynamics.offset(r[0], int(r[1]), r[2], int(r[3]), int(r[4]), int(r[5]), int(r[6]), int(r[7])), r[8], "offset%s" % [r.slice(0, 8)])
	for r: Array in V["delta"]:
		close(Dynamics.delta(int(r[0]), r[1], int(r[2])), r[3], "delta%s" % [r.slice(0, 3)])

func _inputs(m: Dictionary) -> Array:
	var g: Dictionary = m["geometry"]
	var lad: Array = []
	for l: Dictionary in g.get("ladders", []): lad.append({"x": float(l["x"]), "z": float(l["z"])})
	var pd: Array = []
	for q: Dictionary in g.get("bouncePads", []): pd.append({"x": float(q["x"]), "z": float(q["z"]), "r": float(q.get("r", 1.2))})
	var sp: Array = m.get("spawns", []) + m.get("bots", []) + ([m["player"]] if m.has("player") else [])
	return [FighterPhysics.solids_from_map(m), lad, pd, sp]

func _maps(V: Dictionary) -> void:
	var maps: Dictionary = load("res://autoload/content.gd").load_json("maps")
	check(maps.size() == V["maps"].size(), "same map count")
	for id: String in V["maps"]:
		var want: Dictionary = V["maps"][id]
		var m: Dictionary = maps.get(id, {})
		check(Dynamics.map_allowed(id, m) == want["allowed"], "%s map_allowed" % id)
		var a := _inputs(m)
		var p := Dynamics.plan(a[0], a[1], a[2], a[3])
		var w: Dictionary = want["plan"]
		var same: bool = int(p["floor"]) == int(w["floor"]) and int(p["nx"]) == int(w["nx"]) and int(p["nz"]) == int(w["nz"]) \
			and int(p["free"]) == int(w["free"]) and bool(p["canTile"]) == bool(w["canTile"]) and p["mask"].size() == w["mask"].size() \
			and p["drift"].size() == w["drift"].size()
		if same:
			for i in p["mask"].size(): same = same and int(p["mask"][i]) == int(w["mask"][i])
			for i in p["drift"].size(): same = same and int(p["drift"][i]["i"]) == int(w["drift"][i]["i"]) and p["drift"][i]["axis"] == w["drift"][i]["axis"]
		check(same, "%s plan: godot %s js %s" % [id, JSON.stringify(p), JSON.stringify(w)])

func _sims(V: Dictionary) -> void:
	var maps: Dictionary = load("res://autoload/content.gd").load_json("maps")
	for sv: Dictionary in V["sims"]:
		var id: String = sv["id"]
		var m: Dictionary = maps[id]
		var g: Dictionary = m["geometry"]
		var solids := FighterPhysics.solids_from_map(m)
		var d := ArenaDyn.new()
		d.setup(id, m, solids, g.get("ladders", []), g.get("bouncePads", []), sv["choice"], int(sv["seed"]))
		check(d.kind == sv["kind"], "%s %s resolves to %s (js %s)" % [id, sv["choice"], d.kind, sv["kind"]])
		check(solids.size() == int(sv["nsol"]), "%s %s solids %d (js %d)" % [id, sv["kind"], solids.size(), int(sv["nsol"])])
		var ci := 0
		var cks: Array = sv["checks"]
		var time := 0.0
		for n in range(1, 40 * 120 + 1):
			time += 1.0 / 120.0
			d.update(time, [])
			if ci < cks.size() and int(cks[ci][0]) == n:
				var want: Array = cks[ci][1]
				for i in mini(want.size(), solids.size()):
					var s: Dictionary = solids[i]
					var w: Array = want[i]
					var got := [s.minX, s.maxX, s.minZ, s.maxZ, s.top, s.bottom]
					for k in 6: close(got[k], w[k], "%s %s step %d solid %d field %d" % [id, sv["kind"], n, i, k])
				ci += 1
		check(ci == cks.size(), "%s all checkpoints seen" % id)
		# the tile solids are the floor's place in the list and sit where Dynamics.offset says
		if d.kind != "off" and d.kind != "drift":
			var fi: int = d.plan["floor"]
			for e: Dictionary in d.tiles:
				var want_top: float = float(d.plan["top"]) + Dynamics.offset(d.kind, d.seed, time, e["ix"], e["iz"], d.plan["nx"], d.plan["nz"], e["mask"])
				check(absf(e["s"].top - want_top) < 1e-9, "%s tile (%d,%d) top follows the offset" % [id, e["ix"], e["iz"]])
				check(is_same(solids[fi + e["iz"] * int(d.plan["nx"]) + e["ix"]], e["s"]), "%s tile order" % id)

## Fighters ride: stand on a free tile of a wobbling / tilting floor and on a drifting block for 20 s.
func _riders() -> void:
	var maps: Dictionary = load("res://autoload/content.gd").load_json("maps")
	var m: Dictionary = maps["arena"]
	var g: Dictionary = m["geometry"]
	for kind: String in ["wobble", "tilt", "drift"]:
		var solids := FighterPhysics.solids_from_map(m)
		var d := ArenaDyn.new()
		d.setup("arena", m, solids, g.get("ladders", []), g.get("bouncePads", []), kind, 31337)
		check(d.kind == kind, "arena runs %s" % kind)
		var f := FighterState.new()
		var on: Dictionary = {}
		if kind == "drift":
			on = d.drift[0]
		else:
			for e: Dictionary in d.tiles:
				if e["mask"] == 0 and e["ix"] > 1 and e["iz"] > 1: on = e; break
		var s: Dictionary = on["s"]
		f.phys.place((s.minX + s.maxX) * 0.5, s.top + 0.01, (s.minZ + s.maxZ) * 0.5)
		var t := 0.0
		var off_top := 0.0
		var lost := 0
		var start_x := f.phys.px
		var start_z := f.phys.pz
		var rel_x := 0.0
		var rel0 := Vector2.ZERO          # where on the block the rider settled (it lands a few steps in)
		for n in 20 * 120:
			t += 1.0 / 120.0
			d.update(t, [f])
			f.phys.step(1.0 / 120.0, solids, f)
			if n > 60:
				off_top = maxf(off_top, absf(f.phys.py - s.top))
				if not f.phys.grounded: lost += 1
				var rel := Vector2(f.phys.px - (s.minX + s.maxX) * 0.5, f.phys.pz - (s.minZ + s.maxZ) * 0.5)
				if n == 61: rel0 = rel
				rel_x = maxf(rel_x, (rel - rel0).length())
		check(lost == 0, "%s: rider stays grounded (%d steps airborne)" % [kind, lost])
		check(off_top < 1e-6, "%s: rider stays on the top (max gap %.6f)" % [kind, off_top])
		if kind == "drift":
			check(rel_x < 1e-6, "drift: rider moves with the block (drift from centre %.6f)" % rel_x)
			check(Vector2(f.phys.px - start_x, f.phys.pz - start_z).length() > 0.01 or absf(Dynamics.delta(31337, t, 0)) < 0.01, "drift: the block carried the rider")

## MatchSim clock + the net rules reader.
func _net() -> void:
	var rd := NetMatch.rule_dyn({"dyn": "quake", "dseed": 4294967301.0, "dt0": 12.5})
	check(rd["choice"] == "quake" and rd["seed"] == 5 and is_equal_approx(rd["t0"], 12.5), "rule_dyn reads dyn/dseed/dt0 (%s)" % rd)
	rd = NetMatch.rule_dyn({"dyn": "lava", "dseed": -1, "dt0": 99999})
	check(rd["choice"] == "off" and rd["seed"] == 4294967295 and rd["t0"] == 36000.0, "rule_dyn: unknown kind steady, seed >>> 0, dt0 clamped (%s)" % rd)
	rd = NetMatch.rule_dyn({})
	check(rd["choice"] == "off" and rd["seed"] == 0 and rd["t0"] == 0.0, "rule_dyn: missing = steady")
	# two sims with the same rules move the same tiles the same way (host / guest), even when one joined late (t0)
	var maps: Dictionary = load("res://autoload/content.gd").load_json("maps")
	var a := MatchSim.new()
	var b := MatchSim.new()
	for x: MatchSim in [a, b]:
		x.dyn_choice = "random"; x.dyn_seed = 2024
	b.dyn_t0 = 5.0
	var m: Dictionary = maps["arena"]
	var g: Dictionary = m["geometry"]
	for x: MatchSim in [a, b]:
		x.setup("arena", m, g.get("ladders", []), g.get("bouncePads", []), "wobbler", PlayerControl.new(InputState.new()), 0)
	check(a.dyn.kind == b.dyn.kind and a.dyn.kind != "off", "MatchSim: same rules, same kind (%s)" % a.dyn.kind)
	for n in 6 * 120: a.step(1.0 / 120.0)
	for n in 1 * 120: b.step(1.0 / 120.0)
	var worst_ab := 0.0
	for i in a.solids.size():
		worst_ab = maxf(worst_ab, absf(a.solids[i].top - b.solids[i].top) + absf(a.solids[i].minX - b.solids[i].minX) + absf(a.solids[i].minZ - b.solids[i].minZ))
	check(worst_ab < 1e-6, "MatchSim: a guest that joined at t0 = 5 s matches the host (%s)" % worst_ab)
	a.dispose(); b.dispose()
