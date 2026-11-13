extends SceneTree
## Replays the scenario from tools/modes-reference.js through Combat + ModeRules and compares every state with the web game's.
## godot --headless --path godot --script res://tests/modes_parity_test.gd -- SHARED_DIR REFERENCE_JSON
## Ops and their meaning must stay identical to `apply()` in tools/modes-reference.js.

const TOL := 1e-9
const CombatTest := preload("res://tests/combat_test.gd")

var c: Combat
var F: Array = []

const SET_FIELDS := {"invuln": "invuln", "team": "team", "lives": "lives", "ko": "ko", "dead": "dead", "deathT": "death_t", "elim": "elim",
	"ggRung": "gg_rung", "downT": "down_t"}

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var ref: Dictionary = CombatTest.revive(JSON.parse_string(FileAccess.get_file_as_string(a[1])))
	var sc: Dictionary = ref["scenario"]
	c = Combat.new()
	c.load_content(a[0])
	c.rng = CombatRng.new(int(sc["seed"]))
	var i := 0
	for d: Dictionary in sc["fighters"]:
		var f := FighterState.new()
		f.id = i
		var cid: String = d.get("cls", "wobbler")
		f.set_class(cid, c.classes[cid])
		f.is_player = d.get("player", false)
		f.dmg_scale = float(d.get("dmgScale", 1.0)) if d.get("dmgScale", 0) else 1.0
		f.yaw = float(d.get("yaw", 0.0))
		var p: Array = d["pos"]
		f.phys.px = p[0]; f.phys.py = p[1]; f.phys.pz = p[2]
		f.phys.grounded = true
		f.hp = c.max_hp(f)
		F.append(f); c.fighters.append(f)
		i += 1
	var ops: Array = sc["ops"]
	var states: Array = ref["states"]
	var worst := 0.0
	var worst_k := -1
	var first := ""
	for k in ops.size():
		apply(ops[k])
		c.events.clear()
		var err := compare(states[k])
		if err[0] > TOL and first == "":
			first = "FIRST diff at op %d %s: %s" % [k, JSON.stringify(ops[k]), err[1]]
			print(first)
		if err[0] > worst: worst = err[0]; worst_k = k
	print("MODES ops=%d worst_error=%s at op %d ends=%s" % [ops.size(), String.num_scientific(worst), worst_k, _ends])
	c.dispose()
	quit(0 if worst <= TOL else 1)

var _ends := ""

func apply(op: Dictionary) -> void:
	var f: FighterState = F[int(op["f"])] if op.has("f") else null
	match String(op["op"]):
		"cfg":
			var key: String = op["key"]
			var val: Variant = op["val"]
			match key:
				"spawns": c.spawns = val; c.spawn_y = float(op["y"])
				"solids": c.solids = val
				"matchOver": c.rules.match_over = bool(val)
				"shrink":
					if str(val) != "": c.rules.setup_shrink(str(val), {"shrinks": true}, c.solids)
					else: c.rules.shrink = {}
				"mode": c.set_mode(str(val))
				"teams": c.teams = int(val)
				"lives": c.lives_mode = int(val)
				"limit": c.rules.limit = int(val)
				_: push_error("unknown cfg " + key)
		"set":
			var key: String = op["key"]
			if key == "py": f.phys.py = float(op["val"])
			elif key == "deaths": f.st["deaths"] = int(op["val"])
			elif key == "grounded": f.phys.grounded = bool(op["val"])
			else: f.set(SET_FIELDS[key], op["val"])
		"placeAt": c.place_at(f, float(op["x"]), float(op["z"]), float(op["y"]))
		"pickup": c.pickup(f, str(op["key"]))
		"hit":
			var d: Array = op["dir"]
			var at := int(op["a"])
			c.hit(f, float(op["dmg"]), d[0], d[1], d[2], float(op["force"]), bool(op["head"]), F[at] if at >= 0 else null)
		"ko": c.add_ko(F[int(op["a"])], f)
		"respawn": c.respawn(f)
		"dash": c.rules.do_dash(f, float(op["ix"]), float(op["iz"]))
		"pilInit": c.rules.init_pillars()
		"step":
			var dt := float(op["dt"])
			for n in int(op["n"]):
				c.time += dt
				c.rules.update_pillars(dt)
				c.rules.update_shrink(dt)
				for g: FighterState in F: c.timers(g, dt)
		_: push_error("unknown op " + str(op["op"]))
	for e: Dictionary in c.events:
		if e["type"] == "match_over":
			_ends += ("," if _ends != "" else "") + str((e["winner"] as FighterState).id)

func _num_err(a: Variant, b: Variant) -> float:
	if a is String or b is String:
		return 0.0 if str(a) == str(b) else 1.0
	var x := float(a)
	var y := float(b)
	if x == y: return 0.0
	return absf(x - y) / maxf(1.0, absf(y))

func compare(s: Dictionary) -> Array:
	var worst := 0.0
	var what := ""
	var fs: Array = s["f"]
	for i in F.size():
		var f: FighterState = F[i]
		var p := f.phys
		var sl: Array = []
		for x: Variant in f.slots:
			sl.append([x["key"], x["ammo"], x["mag"]] if x != null else null)
		var mine: Array = [p.px, p.py, p.pz, p.vx, p.vy, p.vz, 1 if p.grounded else 0, f.hp, 1 if f.dead else 0, f.death_t, f.ko, f.lives,
			1 if f.elim else 0, f.team, f.weapon, JSON.stringify(sl).replace(".0", ""), f.slot, f.invuln, f.dash_n, f.dash_regen, f.dash_cd, f.gg_rung,
			int(f.st["deaths"]), int(f.st["streak"]), f.fall_side, f.dash_air_t]
		var ref: Array = fs[i]
		for k in mine.size():
			var e := _num_err(mine[k], ref[k])
			if e > worst: worst = e; what = "fighter %d field %d: godot %s js %s" % [i, k, mine[k], ref[k]]
	var m: Array = s["m"]
	var ge := _num_err(1 if c.rules.match_over else 0, m[0]) + _num_err(_ends, m[1]) + _num_err(c.time, m[2])
	if ge > worst: worst = ge; what = "match: godot %s %s %s js %s" % [c.rules.match_over, _ends, c.time, m]
	var pv: Variant = s.get("p")
	if (pv == null) != c.rules.pil.is_empty():
		return [1.0, "pillars presence"]
	if pv != null:
		for k in 2:
			var e := _num_err([c.rules.pil["t"], c.rules.pil["next"]][k], pv[k])
			if e > worst: worst = e; what = "pillars field %d: godot %s js %s" % [k, [c.rules.pil["t"], c.rules.pil["next"]][k], pv[k]]
	var sh: Variant = s["s"]
	var rs := c.rules.shrink
	if (sh == null) != rs.is_empty():
		return [1.0, "shrink presence"]
	if sh != null:
		var b: Dictionary = rs["box"]
		var mine2: Array = [rs["size"], rs["start"], rs["dir"], rs["hold"], rs["cycle"], rs["rest"], b["minX"], b["maxX"], b["minZ"], b["maxZ"]]
		for k in mine2.size():
			var e := _num_err(mine2[k], sh[k])
			if e > worst: worst = e; what = "shrink field %d: godot %s js %s" % [k, mine2[k], sh[k]]
	return [worst, what]
