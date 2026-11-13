extends SceneTree
## Body-part damage (docs/DAMAGE.md): zone geometry, the per-part table on every hit path (hitscan, knife, arrow, melee,
## splash) and the classic rule (web-compatible: only the weapon's head bonus). npm run test:godot-damage
## godot --headless --path godot --script res://tests/damage_test.gd

const EPS := 1e-9
var fails := 0
var checks := 0
var c: Combat
var A: FighterState              ## attacker (a player, so damage numbers are emitted)
var V: FighterState              ## victim at (0, 0, 10) facing the attacker

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1; print("FAIL " + what)

func near(a: float, b: float, what: String) -> void:
	ok(absf(a - b) <= EPS * maxf(1.0, absf(b)), "%s: got %.12f want %.12f" % [what, a, b])

func fighter(x: float, z: float, yaw: float) -> FighterState:
	var f := FighterState.new()
	f.set_class("wobbler", c.classes.get("wobbler", {}))
	f.phys.px = x; f.phys.py = 0.0; f.phys.pz = z; f.yaw = yaw
	pose(f)
	return f

func pose(f: FighterState) -> void:
	var p := f.phys
	f.head_x = p.px; f.head_y = p.py + 1.95; f.head_z = p.pz
	f.chest_x = p.px; f.chest_y = p.py + 1.22; f.chest_z = p.pz
	f.hand_x = p.px; f.hand_y = p.py + 1.3; f.hand_z = p.pz
	f.shoulder_x = p.px; f.shoulder_y = p.py + 1.55; f.shoulder_z = p.pz
	f.update_leg()

func reset() -> void:
	c.events.clear(); c.weapons.clear()
	V.hp = 1e6; V.dead = false; V.invuln = 0.0; V.down_t = 0.0; V.stun = 0.0
	V.phys.px = 0.0; V.phys.py = 0.0; V.phys.pz = 10.0; V.phys.vx = 0.0; V.phys.vy = 0.0; V.phys.vz = 0.0; pose(V)
	A.phys.px = 0.0; A.phys.py = 0.0; A.phys.pz = 0.0; pose(A)
	A.cool = 0.0; A.swing_hit = {}

## The last damage number of this action: {dmg, part, pct} (dmg -1 = no hit).
func last_number() -> Dictionary:
	var r := {"dmg": -1.0, "part": "?", "pct": 0}
	for e: Dictionary in c.events:
		if e["type"] == "dmg_number": r = {"dmg": float(e["dmg"]), "part": String(e["part"]), "pct": int(e["pct"])}
	return r

# --- one hit per weapon family, aimed at a point on the victim ---

func shoot(key: String, target: Array) -> Dictionary:
	reset()
	var d := Combat.norm3(target[0] - A.hand_x, target[1] - A.hand_y, target[2] - A.hand_z)
	A.arm_x = d[0]; A.arm_y = d[1]; A.arm_z = d[2]; A.aim_x = d[0]; A.aim_y = d[1]; A.aim_z = d[2]
	c.weapons.fire_gun(A, key, target)
	return last_number()

func knife(target: Array) -> Dictionary:
	reset()
	var k := Weapons.Proj.new()
	k.key = "knife"; k.w = c.wdata("knife"); k.owner = A; k.age = 1.0; k.grav = 0.0
	k.px = target[0]; k.py = target[1]; k.pz = 8.6; k.vz = 30.0
	c.weapons.projectiles.append(k)
	for i in 10: c.weapons.step_projectiles(0.016)
	return last_number()

func arrow(target: Array) -> Dictionary:
	reset()
	var a := Weapons.Shot.new()
	a.kind = "arrow"; a.key = "bow"; a.w = c.wdata("bow"); a.owner = A; a.age = 1.0; a.ch = 1.0
	a.px = target[0]; a.py = target[1]; a.pz = 8.6; a.vz = 30.0
	c.weapons.arrows.append(a)
	for i in 10:
		a.vy = 0.0                     # no drop: land exactly at the target's height
		c.weapons.step_arrows(0.016)
	return last_number()

func melee(target: Array) -> Dictionary:
	reset()
	A.weapon = "bat"; A.swing = 0.5; A.stab = false; A.cyclone = false; A.slam = false; A.down_t = 0.0
	A.hand_x = target[0]; A.hand_y = target[1]; A.hand_z = 7.8
	A.arm_x = 0.0; A.arm_y = 0.0; A.arm_z = 1.0
	for i in FighterState.BAT_N * 3: A.bat_prev[i] = 50.0     # last frame the bat was far away
	A.bat_valid = true
	c.melee_sweep(A)
	return last_number()

func _initialize() -> void:
	c = Combat.new()
	c.load_content("res://data")
	c.weapons_data["tgun"] = {"type": "gun", "dmg": 20.0, "force": 2.0, "range": 60.0, "spread": 0.0, "muzzle": 0.0}
	c.weapons_data["tgun3"] = {"type": "gun", "dmg": 20.0, "force": 2.0, "range": 60.0, "spread": 0.0, "muzzle": 0.0, "headMul": 3.0}
	A = fighter(0.0, 0.0, 0.0); A.is_player = true
	V = fighter(0.0, 10.0, PI)
	c.fighters = [A, V]
	c.hp_setting = 1e6

	# 1. geometry: zones from the hit point relative to the body points, rotated with the victim
	ok(c.body_part(V, 0.0, 1.95, 10.0, true) == "head", "head sphere -> head")
	ok(c.body_part(V, 0.0, 1.3, 9.4, false) == "torso", "chest front -> torso")
	ok(c.body_part(V, 0.5, 1.3, 9.7, false) == "arms", "chest side -> arms")
	ok(c.body_part(V, -0.5, 1.3, 9.7, false) == "arms", "other side -> arms")
	ok(c.body_part(V, 0.0, 0.4, 9.5, false) == "legs", "below the hips -> legs")
	ok(c.body_part(V, 0.0, 1.3, 9.5, false) == "torso", "front centre -> torso")
	V.yaw = PI * 0.5                   # turned sideways: x is now front/back, z is the side
	ok(c.body_part(V, 0.5, 1.3, 10.0, false) == "torso", "yaw 90: x offset is front -> torso")
	ok(c.body_part(V, 0.0, 1.3, 10.5, false) == "arms", "yaw 90: z offset is the side -> arms")
	V.yaw = PI
	c.giant = true
	ok(c.body_part(V, 0.45, 1.3, 9.7, false) == "torso", "giant: wider torso")
	c.giant = false

	# 2. rules: MatchSim offline = zones, online falls back to classic unless net_zones
	ok(not c.zones_active(), "bare Combat is classic")
	var sim := MatchSim.new()
	ok(sim.combat.zones_active(), "MatchSim offline uses the zones table")
	sim.combat.net_started = true
	ok(not sim.combat.zones_active(), "online -> classic by default")
	sim.combat.net_zones = true
	ok(sim.combat.zones_active(), "online with net_zones -> zones")
	sim.dispose()

	var T := {"head": [0.0, 1.95, 10.0], "torso": [0.0, 1.22, 10.0], "arms": [0.5, 1.3, 10.0], "legs": [0.0, 0.4, 10.0]}
	var tbl: Dictionary = c.damage["tables"]["zones"]
	for rule: String in ["classic", "zones"]:
		c.damage_rule = rule
		var z := rule == "zones"
		# expected multiplier per family and part (head = the weapon's own rule, melee head = the table)
		var fam := {
			"gun": {"head": 2.0}, "gun3": {"head": 3.0}, "knife": {"head": 1.8}, "arrow": {"head": 1.8},
			"melee": {"head": float(tbl["head"]) if z else 1.0}}
		for k: String in fam:
			for p: String in ["torso", "arms", "legs"]:
				fam[k][p] = float(tbl[p]) if z else 1.0
		var runs := {
			"gun": func(t: Array) -> Dictionary: return shoot("tgun", t),
			"gun3": func(t: Array) -> Dictionary: return shoot("tgun3", t),
			"knife": func(t: Array) -> Dictionary: return knife(t),
			"arrow": func(t: Array) -> Dictionary: return arrow(t),
			"melee": func(t: Array) -> Dictionary: return melee(t)}
		for k: String in runs:
			var base: Dictionary = runs[k].call(T["torso"])
			ok(base["dmg"] > 0.0 and base["part"] == "torso", "%s %s: torso hit (%s)" % [rule, k, base])
			for p: String in ["head", "arms", "legs"]:
				var r: Dictionary = runs[k].call(T[p])
				var want_part := p
				if k == "melee" and p == "head" and not z: want_part = "torso"   # classic melee never headshots
				ok(r["part"] == want_part, "%s %s %s: part %s" % [rule, k, p, r["part"]])
				var m: float = fam[k][p] if want_part == p else 1.0
				near(r["dmg"], base["dmg"] * m, "%s %s %s dmg" % [rule, k, p])
				ok(r["pct"] == Combat.js_round((m - 1.0) * 100.0), "%s %s %s pct %d" % [rule, k, p, r["pct"]])

	# 3. classic is the old formula exactly: gun head x2 (or headMul), knives/arrows x1.8, everything else x1
	c.damage_rule = "classic"
	ok(is_equal_approx(c.part_mul("arms", 2.0), 1.0) and c.part_mul("legs") == 1.0 and c.part_mul("head", 2.0) == 2.0, "classic multipliers")
	c.damage_rule = "zones"
	ok(c.part_mul("head") == 1.5 and c.part_mul("arms") == 0.85 and c.part_mul("legs") == 0.75 and c.part_mul("torso") == 1.0, "zones table values")

	# 4. splash has no part (whole body)
	reset()
	c.weapons.explode(0.0, 1.2, 9.0, A, c.wdata("rocket"))
	var sp := last_number()
	ok(sp["dmg"] > 0.0 and sp["part"] == "" and sp["pct"] == 0, "explosion: no body part (%s)" % [sp])

	c.dispose(); A = null; V = null
	print("DAMAGE checks=%d failures=%d" % [checks, fails])
	quit(0 if fails == 0 else 1)
