extends SceneTree
## Replays the scenario from tools/bots-reference.js through BotBrain (+ Combat, Weapons, ModeRules dashes) and compares
## the bots' decisions after every op with the web game's real botThink.
## godot --headless --path godot --script res://tests/bots_parity_test.gd -- SHARED_DIR REFERENCE_JSON
## Ops and their meaning must stay identical to `apply()` in tools/bots-reference.js.

const TOL := 1e-9
const CombatTest := preload("res://tests/combat_test.gd")

var sim: MatchSim
var c: Combat
var F: Array = []
var B: Array = []                ## BotBrain per fighter (null for the player)
var jumps: Array = []
const OFF := {"head": [0.0, 1.95, 0.0], "chest": [0.0, 1.22, 0.0], "hand": [0.3, 1.3, 0.4], "shoulder": [0.3, 1.55, 0.0]}
const SET_FIELDS := {"invuln": "invuln", "hp": "hp", "downT": "down_t", "stun": "stun", "hipD": "hip_d", "slot": "slot", "weapon": "weapon",
	"dashN": "dash_n", "dashCd": "dash_cd", "team": "team", "dead": "dead", "cool": "cool"}
const BRAIN_FIELDS := {"hopT": "hop_t", "hopY0": "hop_y0", "hopTo": "hop_to", "escapeT": "escape_t", "hopN": "hop_n"}
var diffs: Dictionary

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var ref: Dictionary = CombatTest.revive(JSON.parse_string(FileAccess.get_file_as_string(a[1])))
	var sc: Dictionary = ref["scenario"]
	diffs = Combat.read_json(a[0].path_join("difficulties.json"))
	sim = MatchSim.new(a[0])
	c = sim.combat
	c.rng = CombatRng.new(int(sc["seed"]))
	c.damage_rule = "classic"          # the web reference hits are classic (MatchSim defaults to zones)
	sim.map = {"spawns": [[0, 0]], "wander": 14}
	c.fighters = []
	sim.fighters = c.fighters
	var i := 0
	for d: Dictionary in sc["fighters"]:
		var f := FighterState.new()
		f.id = i
		var cid: String = d.get("cls", "wobbler")
		f.set_class(cid, c.classes[cid])
		f.is_player = d.get("player", false)
		var p: Array = d["pos"]
		f.phys.px = p[0]; f.phys.py = p[1]; f.phys.pz = p[2]
		f.phys.grounded = true
		f.hp = c.max_hp(f)
		F.append(f); c.fighters.append(f)
		jumps.append(0)
		if f.is_player:
			sim.player = f; B.append(null)
		else:
			var br := BotBrain.new(diffs["normal"], "normal")
			br.ai_t = float(d.get("aiT", 1.0)); br.strafe = float(d.get("strafe", 1.0))
			br.unstick = false; br.hold_busy = false     # the web behaviour exactly
			B.append(br)
		i += 1
	var ops: Array = sc["ops"]
	var states: Array = ref["states"]
	var worst := 0.0
	var worst_k := -1
	var first := ""
	var t0 := Time.get_ticks_usec()
	for k in ops.size():
		apply(ops[k])
		c.events.clear()
		var err := compare(states[k])
		if err[0] > TOL and first == "":
			first = "FIRST diff at op %d %s: %s" % [k, JSON.stringify(ops[k]), err[1]]
			print(first)
		if err[0] > worst: worst = err[0]; worst_k = k
	print("BOTS ops=%d worst_error=%s at op %d (%.2fs)" % [ops.size(), String.num_scientific(worst), worst_k, (Time.get_ticks_usec() - t0) / 1e6])
	for br in B:
		if br != null: br.target = null
	sim.dispose(); F.clear(); B.clear()
	quit(0 if worst <= TOL else 1)

func pose(f: FighterState) -> void:
	var p := f.phys
	f.head_x = p.px + OFF["head"][0]; f.head_y = p.py + OFF["head"][1]; f.head_z = p.pz + OFF["head"][2]
	f.chest_x = p.px + OFF["chest"][0]; f.chest_y = p.py + OFF["chest"][1]; f.chest_z = p.pz + OFF["chest"][2]
	f.hand_x = p.px + OFF["hand"][0]; f.hand_y = p.py + OFF["hand"][1]; f.hand_z = p.pz + OFF["hand"][2]
	f.shoulder_x = p.px + OFF["shoulder"][0]; f.shoulder_y = p.py + OFF["shoulder"][1]; f.shoulder_z = p.pz + OFF["shoulder"][2]
	f.update_leg()
	f.arm_x = f.aim_x; f.arm_y = f.aim_y; f.arm_z = f.aim_z

func apply(op: Dictionary) -> void:
	var f: FighterState = F[int(op["f"])] if op.has("f") else null
	match String(op["op"]):
		"cfg":
			var key: String = op["key"]
			var val: Variant = op["val"]
			match key:
				"solids": c.solids = val; sim.solids = val
				"spawns": c.spawns = val; sim.map["spawns"] = val
				"wander": sim.map["wander"] = val
				"edgeGuard": sim.map["edgeGuard"] = bool(val)
				"hp": c.hp_setting = float(val)
				"diff":
					for br in B:
						if br != null: br.d = diffs[val]; br.diff = val
				"mode": c.set_mode(str(val))
				"teams": c.teams = int(val)
				"ffa": c.ffa = bool(val)
				"behav": c.brawl = val == "brawl"
				_: push_error("unknown cfg " + key)
		"set":
			var key2: String = op["key"]
			if key2 == "grounded": f.phys.grounded = bool(op["val"])
			elif key2 == "slots": f.slots = [null, null, null]
			elif BRAIN_FIELDS.has(key2): B[int(op["f"])].set(BRAIN_FIELDS[key2], op["val"])
			else: f.set(SET_FIELDS[key2], op["val"])
		"place": f.phys.px = op["p"][0]; f.phys.py = op["p"][1]; f.phys.pz = op["p"][2]
		"vel": f.phys.vx = op["v"][0]; f.phys.vy = op["v"][1]; f.phys.vz = op["v"][2]
		"pickup": c.pickup(f, str(op["key"]))
		"crate": sim.pickups.list.append({"key": op["key"], "x": float(op["x"]), "y": float(op["gy"]) + 0.4, "z": float(op["z"]), "gy": float(op["gy"]), "grounded": true})
		"nocrates": sim.pickups.list.clear()
		"think":
			var dt := float(op["dt"])
			for n in int(op["n"]):
				for g: FighterState in F: pose(g)
				for j in F.size():
					if B[j] == null: continue
					var g: FighterState = F[j]
					B[j].think(g, sim, dt)
					if g.phys.want_jump: jumps[j] += 1; g.phys.want_jump = false
				for g: FighterState in F: c.timers(g, dt)
				c.weapons.step_all(dt)
				c.time += dt
				for g: FighterState in F: pose(g)
				for g: FighterState in F: c.melee_sweep(g)
				for g: FighterState in F: c.weapons.grab_tick(g, dt)
				c.events.clear()
		_: push_error("unknown op " + str(op["op"]))

func dump(i: int) -> Array:
	var f: FighterState = F[i]
	var p := f.phys
	var out: Array = [p.px, p.pz, f.hp, int(f.dead), f.cool, f.kick_cool, f.kick_t, f.swing, f.weapon, f.slot, f.draw, int(f.nocked), p.vx, p.vz, f.dash_n, int(f.reloading)]
	var br: BotBrain = B[i]
	if br != null:
		out.append_array([p.wish_x, p.wish_z, f.face_yaw, br.target.id if br.target != null else -1, br.aim_off[0], br.aim_off[1], br.aim_off[2], br.think_t, br.ai_t,
			br.wander[0] if br.wander != null else 999, br.wander[1] if br.wander != null else 999, br.jump_t, br.stuck_t, br.escape_t, br.give_t, br.wd_t, br.strafe,
			int(br.los), br.burst, f.aim_x, f.aim_y, f.aim_z, br.hop_t, maxi(br.hop_n, 0), jumps[i]])
	return out

const NAMES := ["px", "pz", "hp", "dead", "cool", "kickCool", "kickT", "swing", "weapon", "slot", "draw", "nocked", "vx", "vz", "dashN", "reloading",
	"wishX", "wishZ", "faceYaw", "target", "aimOffX", "aimOffY", "aimOffZ", "thinkT", "aiT", "wanderX", "wanderZ", "jumpT", "stuckT", "escapeT", "giveT",
	"wdT", "strafe", "los", "burst", "aimX", "aimY", "aimZ", "hopT", "hopN", "jumps"]

func compare(s: Dictionary) -> Array:
	var worst := 0.0
	var what := ""
	var fs: Array = s["f"]
	for i in F.size():
		var mine := dump(i)
		var ref: Array = fs[i]
		if mine.size() != ref.size(): return [1e9, "fighter %d size %d vs %d" % [i, mine.size(), ref.size()]]
		for k in mine.size():
			var e := 0.0
			if mine[k] is String or ref[k] is String: e = 0.0 if str(mine[k]) == str(ref[k]) else 1e9
			else:
				var x := float(mine[k])
				var y := float(ref[k])
				if x != y: e = absf(x - y) / maxf(1.0, absf(y))
			if e > worst: worst = e; what = "fighter %d %s: godot %s js %s" % [i, NAMES[k], mine[k], ref[k]]
	var ce := 0.0 if sim.pickups.list.size() == int(s["c"]) else 1e9
	if ce > worst: worst = ce; what = "crates godot %d js %d" % [sim.pickups.list.size(), s["c"]]
	return [worst, what]
