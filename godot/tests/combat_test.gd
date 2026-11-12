extends SceneTree
## Replays the scenario from tools/combat-reference.js through Combat/Weapons and compares every state with the web game's.
## godot --headless --path godot --script res://tests/combat_test.gd -- SHARED_DIR REFERENCE_JSON
## Ops and their meaning must stay identical to `apply()` in tools/combat-reference.js.

const TOL := 1e-9

var c: Combat
var F: Array = []                ## FighterState per scenario fighter
var off: Array = []              ## pose offsets per fighter {head, chest, hand, shoulder}
var follow: Array = []           ## arm follows the aim target
var melee_yaw: Array = []
var lean: Array = []
var head: Array = []
var arm: Array = []
var netlog: Array = []
var aim_point := [0.0, 1.5, -20.0]

const SET_FIELDS := {"shieldT": "shield_t", "rageT": "rage_t", "downT": "down_t", "trapT": "trap_t", "invuln": "invuln", "yaw": "yaw",
	"hp": "hp", "stun": "stun", "burn": "burn", "getupImmune": "getup_immune", "cool": "cool", "kickCool": "kick_cool",
	"shoveCool": "shove_cool", "climb": "climb", "hipD": "hip_d", "dmgScale": "dmg_scale", "lastHitTime": "last_hit_time",
	"team": "team", "isGhost": "is_ghost"}

## "#<16 hex>" strings back to the exact doubles (see exactJson in tools/combat-reference.js).
static func revive(v: Variant) -> Variant:
	if v is String and v.length() == 17 and v.begins_with("#"):
		var b: PackedByteArray = (v as String).substr(1).hex_decode()
		b.reverse()
		return b.decode_double(0)
	if v is Array:
		var a := []
		for x: Variant in v: a.append(revive(x))
		return a
	if v is Dictionary:
		var d := {}
		for k: Variant in v: d[k] = revive(v[k])
		return d
	return v

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var ref: Dictionary = revive(JSON.parse_string(FileAccess.get_file_as_string(a[1])))
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
		f.net_slot = int(d.get("netSlot", -1))
		f.team = int(d.get("team", 0))
		f.dmg_scale = float(d.get("dmgScale", 1.0)) if d.get("dmgScale", 0) else 1.0
		f.yaw = float(d.get("yaw", 0.0))
		var p: Array = d["pos"]
		f.phys.px = p[0]; f.phys.py = p[1]; f.phys.pz = p[2]
		f.phys.grounded = d.get("grounded", true) != false
		f.hp = c.max_hp(f)
		F.append(f); c.fighters.append(f)
		off.append({"head": [0.0, 1.95, 0.0], "chest": [0.0, 1.22, 0.0], "hand": [0.3, 1.3, 0.4], "shoulder": [0.3, 1.55, 0.0]})
		follow.append(true); melee_yaw.append(0.0)
		lean.append([0.0, 0.0]); head.append([0.0, 0.0]); arm.append([0.0, 0.0, 0.0])
		i += 1
	var ops: Array = sc["ops"]
	var states: Array = ref["states"]
	var worst := 0.0
	var worst_k := -1
	var first := ""
	for k in ops.size():
		apply(ops[k])
		drain()
		var err := compare(states[k])
		if err[0] > TOL and first == "":
			first = "FIRST diff at op %d %s: %s" % [k, JSON.stringify(ops[k]), err[1]]
			print(first)
		if err[0] > worst: worst = err[0]; worst_k = k
	print("COMBAT ops=%d worst_error=%s at op %d" % [ops.size(), String.num_scientific(worst), worst_k])
	var net_ok := check_net(ref["net"])
	c.dispose(); F.clear(); lean.clear()
	quit(0 if worst <= TOL and net_ok else 1)

func pose(i: int) -> void:
	var f: FighterState = F[i]
	var o: Dictionary = off[i]
	var p := f.phys
	f.head_x = p.px + o["head"][0]; f.head_y = p.py + o["head"][1]; f.head_z = p.pz + o["head"][2]
	f.chest_x = p.px + o["chest"][0]; f.chest_y = p.py + o["chest"][1]; f.chest_z = p.pz + o["chest"][2]
	f.hand_x = p.px + o["hand"][0]; f.hand_y = p.py + o["hand"][1]; f.hand_z = p.pz + o["hand"][2]
	f.shoulder_x = p.px + o["shoulder"][0]; f.shoulder_y = p.py + o["shoulder"][1]; f.shoulder_z = p.pz + o["shoulder"][2]
	f.update_leg()
	if follow[i]:
		f.arm_x = f.aim_x; f.arm_y = f.aim_y; f.arm_z = f.aim_z

func pose_all() -> void:
	for i in F.size(): pose(i)

func apply(op: Dictionary) -> void:
	var f: FighterState = F[int(op["f"])] if op.has("f") else null
	match op["op"]:
		"cfg":
			var key: String = op["key"]
			var val: Variant = op.get("val")
			match key:
				"giant": c.giant = bool(val)
				"net":
					c.net_started = val != null; c.net_host = val != null
					if val != null:
						for j in F.size(): F[j].net_human = val["kinds"][j] == "human"
				"spawns": c.spawns = val; c.spawn_y = float(op["y"])
				"solids": c.solids = val
				"aimPoint": aim_point = val
				"aim": F[0].ads = float(val)
				"mode": c.set_mode(val)
				"kb": c.kb_setting = float(val)
				"teams": c.teams = int(val)
				_: push_error("cfg " + key)
		"set":
			var key2: String = op["key"]
			if key2 == "burner": f.burner = F[int(op["val"])]
			elif key2 == "grounded": f.phys.grounded = bool(op["val"])
			elif key2 == "team": f.team = int(op["val"])
			elif key2 == "isGhost": f.is_ghost = bool(op["val"])
			else: f.set(SET_FIELDS[key2], float(op["val"]))
		"place": f.phys.px = op["p"][0]; f.phys.py = op["p"][1]; f.phys.pz = op["p"][2]
		"vel": f.phys.vx = op["v"][0]; f.phys.vy = op["v"][1]; f.phys.vz = op["v"][2]
		"pose":
			var i := int(op["f"])
			if op.has("off"): off[i].merge(op["off"], true)
			if op.has("arm"):
				follow[i] = false; f.arm_x = op["arm"][0]; f.arm_y = op["arm"][1]; f.arm_z = op["arm"][2]
			else: follow[i] = true
			if op.has("aim"): f.aim_x = op["aim"][0]; f.aim_y = op["aim"][1]; f.aim_z = op["aim"][2]
		"class": f.set_class(op["cls"], c.classes[op["cls"]])
		"hit", "nethit":
			pose_all()
			var at := int(op["a"])
			var d: Array = op["dir"]
			c.net_apply = op["op"] == "nethit"
			c.hit(f, float(op["dmg"]), d[0], d[1], d[2], float(op["force"]), int(op.get("head", 0)) != 0, F[at] if at >= 0 else null)
			c.net_apply = false
		"topple": c.topple(f, float(op["dur"]))
		"pickup": c.pickup(f, op["key"])
		"equip": c.equip_slot(f, int(op["i"]))
		"reload": c.start_reload(f)
		"placeAt": c.place_at(f, float(op["x"]), float(op["z"]), float(op["y"]))
		"fire":
			pose_all()
			c.weapons.try_fire(f, aim_point if f.is_player else [])
		"hold":
			pose_all()
			if not c.wdata(f.weapon).get("spinup", 0): f.spin = 0.0
			if not f.dead and f.down_t <= 0.0 and c.wdata(f.weapon).get("type", "") == "gun":
				c.weapons.gun_tick(f, bool(op["held"]), float(op["dt"]), aim_point if f.is_player else [])
		"blow":
			pose_all()
			if not f.dead and f.down_t <= 0.0 and c.wdata(f.weapon).get("type", "") == "blower":
				c.weapons.blower_tick(f, bool(op["held"]), float(op["dt"]))
		"melee":
			if c.try_melee(f, float(op["yaw"])): melee_yaw[int(op["f"])] = float(op["yaw"])
		"kick": c.do_kick(f, float(op["yaw"]))
		"shove": c.shove(f, float(op["yaw"]))
		"step":
			var dt := float(op["dt"])
			for n in int(op["n"]):
				pose_all()
				for g: FighterState in F: c.timers(g, dt)
				for j in F.size():
					var g: FighterState = F[j]
					var wk := g.weapon if c.wdata(g.weapon).get("swingTime", 0) else "spatula"
					if g.swing >= 0.0 and not g.dead and c.melee_tick(g, wk, dt, melee_yaw[j]): c.after_swing(g)
				c.weapons.step_projectiles(dt)
				c.time += dt
				pose_all()
				for g: FighterState in F: c.melee_sweep(g)
				drain()
		_: push_error("unknown op " + str(op["op"]))

func drain() -> void:
	for e: Dictionary in c.events:
		match e["type"]:
			"lean": var l: Array = lean[e["f"].id]; l[0] += e["a"]; l[1] += e["b"]
			"head": var h: Array = head[e["f"].id]; h[0] += e["a"]; h[1] += e["b"]
			"arm": var r: Array = arm[e["f"].id]; r[0] += e["x"]; r[1] += e["y"]; r[2] += e["z"]
			"net": netlog.append(e["msg"])
	c.events.clear()

func dump_fighter(i: int) -> Array:
	var f: FighterState = F[i]
	var p := f.phys
	var sl := []
	for s: Variant in f.slots:
		sl.append(null if s == null else [s["key"], s["ammo"], s["mag"], 1 if s["pend"] else 0])
	return [p.px, p.py, p.pz, p.vx, p.vy, p.vz, int(p.grounded), f.hp, int(f.dead), f.death_t, f.down_t, f.getup_immune, f.stun, f.invuln, f.flash,
		f.cool, f.swing, f.kick_t, f.weapon, f.slot, sl, int(f.reloading), f.rl_t, f.ko, f.st["hits"], f.st["dmg"], f.st["taken"], f.st["deaths"], f.st["heads"], f.st["shots"],
		f.st["streak"], f.st["multi"], lean[i][0], lean[i][1], head[i][0], head[i][1], arm[i][0], arm[i][1], arm[i][2], f.aim_x, f.aim_y, f.aim_z, f.climb, f.fall_side,
		f.throw_t, f.knife_t, f.return_slot, f.lives, int(f.elim), melee_yaw[i], f.last_hit_time, f.spin, f.uzi_side]

const NAMES := ["px", "py", "pz", "vx", "vy", "vz", "grounded", "hp", "dead", "deathT", "downT", "getupImmune", "stun", "invuln", "flash", "cool", "swing", "kickT",
	"weapon", "slot", "slots", "reloading", "rlT", "ko", "hits", "dmg", "taken", "deaths", "heads", "shots", "streak", "multi", "leanA", "leanB", "headA", "headB",
	"armX", "armY", "armZ", "aimX", "aimY", "aimZ", "climb", "fallSide", "throwT", "knifeT", "returnSlot", "lives", "elim", "meleeYaw", "lastHitTime", "spin", "uziSide"]

## Worst difference between two JSON-like values ([error, description]).
func diff(a: Variant, b: Variant, what: String) -> Array:
	if (a is float or a is int) and (b is float or b is int):
		var e := absf(float(a) - float(b))
		if is_nan(float(a)) != is_nan(float(b)): e = 1e9
		elif is_nan(e): e = 0.0
		if e == 0.0: return [0.0, ""]
		return [e, "%s godot=%s js=%s" % [what, String.num(float(a), 15), String.num(float(b), 15)]]
	if a is Array and b is Array:
		if a.size() != b.size(): return [1e9, "%s size godot=%d js=%d %s | %s" % [what, a.size(), b.size(), str(a), str(b)]]
		var w := [0.0, ""]
		for j in a.size():
			var d := diff(a[j], b[j], "%s[%d]" % [what, j])
			if d[0] > w[0]: w = d
		return w
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return [1e9, "%s keys godot=%s js=%s" % [what, str(a), str(b)]]
		var w2 := [0.0, ""]
		for k: Variant in b:
			if not a.has(k): return [1e9, "%s missing %s" % [what, k]]
			var d2 := diff(a[k], b[k], "%s.%s" % [what, k])
			if d2[0] > w2[0]: w2 = d2
		return w2
	if (a == null and b == null) or (a is String and b is String and a == b) or (a is bool and b is bool and a == b):
		return [0.0, ""]
	return [1e9, "%s godot=%s js=%s" % [what, str(a), str(b)]]

func compare(st: Dictionary) -> Array:
	var w := [0.0, ""]
	for i in F.size():
		var js: Array = st["f"][i]
		js[20] = JSON.parse_string(js[20])           # slots: small ints only, safe to parse
		var gd := dump_fighter(i)
		for j in gd.size():
			var d := diff(gd[j], js[j], "f%d.%s" % [i, NAMES[j]])
			if d[0] > w[0]: w = d
	var pk := []
	for k: Weapons.Proj in c.weapons.projectiles:
		pk.append([k.px, k.py, k.pz, k.vx, k.vy, k.vz, k.age, k.stuck])
	var dk := diff(pk, st["k"], "projectiles")
	if dk[0] > w[0]: w = dk
	var dn := diff(netlog, st["net"], "net")
	if dn[0] > w[0]: w = dn
	netlog.clear()
	return w

## JS rounding (toFixed / Math.round) and netCleanHit against the web game's results.
func check_net(net: Dictionary) -> bool:
	var bad := 0
	for row: Array in net["fixed"]:
		var v: float = row[0]
		if NetSnapshot.fixed(v, 2) != row[1] or NetSnapshot.fixed(v, 3) != row[2] or Combat.js_round(v) != int(row[3]):
			bad += 1
			if bad < 5: print("NET round diff v=%s godot=%s %s %d js=%s %s %d" % [str(v), str(NetSnapshot.fixed(v, 2)), str(NetSnapshot.fixed(v, 3)), Combat.js_round(v), str(row[1]), str(row[2]), row[3]])
	for row: Array in net["hits"]:
		var h := NetSnapshot.decode_hit(row[0])
		var want: Array = row[1]
		if h.is_empty() or h["d"] != want[0] or h["f"] != want[1] or h["x"] != want[2] or h["y"] != want[3] or h["z"] != want[4]:
			bad += 1
			if bad < 10: print("NET hit diff %s -> godot %s js %s" % [str(row[0]), str(h), str(want)])
	print("NET rounding=%d hits=%d mismatches=%d" % [net["fixed"].size(), net["hits"].size(), bad])
	return bad == 0
