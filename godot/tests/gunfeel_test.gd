extends SceneTree
## Gun feel (balance overlay): scatter bloom, arm wobble, stacked-hit knockback damping, shorter net trap.
## npm run test:godot-gunfeel

var fails := 0
var checks := 0

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1; print("FAIL " + what)

func _initialize() -> void:
	var maps: Dictionary = load("res://autoload/content.gd").load_json("maps")
	var m: Dictionary = maps["arena"]
	var g: Dictionary = m["geometry"]
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(5)
	sim.setup("arena", m, g.get("ladders", []), g.get("bouncePads", []), "wobbler", PlayerControl.new(InputState.new()), 1)
	var c := sim.combat
	var p: FighterState = c.fighters[0]
	ok(c.tuning_active(), "tuning on")
	ok(float(c.wdata("net")["trap"]) <= 3.0, "net trap shortened (%s)" % c.wdata("net")["trap"])
	for k: String in ["ak", "smg", "uzi", "minigun", "revolver", "sniper"]:
		ok(float(c.wdata(k).get("wobble", 0.0)) > 0.0, "%s wobbles" % k)
	var bare := Combat.new(); bare.load_content()
	ok(float(c.wdata("ak")["dmg"]) < float(bare.wdata("ak")["dmg"]), "ak damage lowered")
	ok(float(c.wdata("ak")["spread"]) > float(bare.wdata("ak")["spread"]), "ak spread widened")
	# sustained fire builds bloom, then it cools; wobble moves the aim; stacked hits shrink the push
	p.weapon = "ak"
	p.phys.place(p.phys.px, 0.0, p.phys.pz)
	p.hand_x = p.phys.px; p.hand_y = 1.3; p.hand_z = p.phys.pz
	for i in 20: c.weapons.fire_gun(p, "ak", [p.phys.px, 1.3, p.phys.pz + 20.0])
	ok(p.bloom > 0.02, "bloom builds (%.4f)" % p.bloom)
	var moved := false
	for i in 240:
		c.weapons.climb_tick(p, 1.0 / 120.0)
		if absf(p.wob_x) + absf(p.wob_y) + absf(p.wob_z) > 0.0005: moved = true
	ok(moved, "arm wobble moves the aim")
	ok(p.bloom < 0.02, "bloom cools (%.4f)" % p.bloom)
	var v: FighterState = c.fighters[1]
	var w := c.weapons
	v.gun_kick = 0.0
	var first := 1.0 / (1.0 + Weapons.GUN_KICK_DAMP * v.gun_kick)
	v.gun_kick = 3.0
	var third := 1.0 / (1.0 + Weapons.GUN_KICK_DAMP * v.gun_kick)
	ok(third < first * 0.4, "stacked hits push less (%.2f vs %.2f)" % [third, first])
	for i in 360: w.climb_tick(v, 1.0 / 120.0)
	ok(v.gun_kick < 2.0, "stack recovers (%.2f)" % v.gun_kick)
	print("GUNFEEL %d checks, %d failed" % [checks, fails])
	quit(0 if fails == 0 else 1)
