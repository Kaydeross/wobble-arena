extends SceneTree
## Balance overlay, weapon burst pools, swap draw time and the air recovery ("boing burst"), logic/skills.gd and
## docs/DAMAGE.md "Balance and cooldowns". npm run test:godot-skills
## godot --headless --path godot --script res://tests/skills_test.gd

const DT := 1.0 / 120.0
var fails := 0
var checks := 0

func ok(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		fails += 1; print("FAIL " + what)

func pose(f: FighterState) -> void:
	var p := f.phys
	f.head_x = p.px; f.head_y = p.py + 1.95; f.head_z = p.pz
	f.chest_x = p.px; f.chest_y = p.py + 1.22; f.chest_z = p.pz
	f.hand_x = p.px + 0.3; f.hand_y = p.py + 1.3; f.hand_z = p.pz + 0.4
	f.shoulder_x = p.px; f.shoulder_y = p.py + 1.55; f.shoulder_z = p.pz
	f.update_leg()

func new_sim(bots: int = 0) -> MatchSim:
	var maps: Dictionary = load("res://autoload/content.gd").load_json("maps")
	var m: Dictionary = maps["arena"]
	var g: Dictionary = m["geometry"]
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(77)
	sim.setup("arena", m, g.get("ladders", []), g.get("bouncePads", []), "wobbler", PlayerControl.new(InputState.new()), bots)
	return sim

## Put f in the air at height y with velocity (vx, vy, vz), last hit long ago.
func airborne(sim: MatchSim, f: FighterState, y: float, vx: float = 0.0, vy: float = 0.0, vz: float = 0.0) -> void:
	f.phys.place(f.phys.px, y, f.phys.pz); f.phys.grounded = false
	f.phys.vx = vx; f.phys.vy = vy; f.phys.vz = vz
	f.dead = false; f.down_t = 0.0; f.trap_t = 0.0; f.stun = 0.0
	f.last_hit_time = sim.combat.time - 5.0
	Skills.reset(f)

func _initialize() -> void:
	_tuning()
	_bursts()
	_swap()
	_recover()
	_parry()
	_physics()
	_controls()
	print("SKILLS %d checks, %d failed" % [checks, fails])
	quit(0 if fails == 0 else 1)

# 1. the overlay: on offline (zones), off for a bare Combat, online and the classic rule
func _tuning() -> void:
	var bare := Combat.new()
	bare.load_content()
	var shared_head := float(bare.wdata("mammoth")["headMul"])
	ok(not bare.tuning_active() and shared_head > 15.0, "bare Combat: shared numbers (headMul %s)" % shared_head)
	var sim := MatchSim.new()
	var c := sim.combat
	ok(c.tuning_active(), "MatchSim offline: tuning on")
	var mam := c.wdata("mammoth")
	ok(float(mam["headMul"]) == 8.0 and float(mam["cooldown"]) == 1.4, "mammoth tuned (%s, %s)" % [mam["headMul"], mam["cooldown"]])
	var head_dmg := float(mam["dmg"]) * float(mam["headMul"]) * float(c.classes["bruiser"].get("dmg", 1.0))
	ok(head_dmg < c.hp_setting, "mammoth headshot is not a one-shot even for a Bruiser (%.1f < %.0f)" % [head_dmg, c.hp_setting])
	for k: String in ["meteor", "rocket", "glauncher", "cluster"]:
		var t := c.wdata(k)
		var s := bare.wdata(k)
		ok(float(t["cooldown"]) > float(s["cooldown"]) and float(t["ammo"]) < float(s["ammo"]), "%s: slower and less ammo" % k)
		ok(t.get("burst") is Dictionary, "%s has a burst pool" % k)
	ok(float(c.wdata("minigun")["force"]) < float(bare.wdata("minigun")["force"]), "minigun knockback lowered")
	ok(float(c.tuned_drops.get("meteor", 9.0)) < float(sim.pickups.drops["base"]["meteor"]), "meteor crate weight lowered")
	ok(c.wdata("spatula") == bare.wdata("spatula"), "untuned weapons unchanged")
	c.damage_rule = "classic"
	ok(not c.tuning_active() and float(c.wdata("mammoth")["headMul"]) == shared_head, "classic rule (parity tests): shared numbers")
	c.damage_rule = "zones"
	c.net_started = true
	ok(not c.tuning_active() and float(c.wdata("rocket")["cooldown"]) == float(bare.wdata("rocket")["cooldown"]), "online: web numbers")
	c.net_zones = true
	ok(c.tuning_active(), "online with net_zones: tuning on")
	sim.dispose(); bare.dispose()

# 2. burst pools: n shots, then one charge back every regen s; firing is refused while empty
func _bursts() -> void:
	var sim := new_sim()
	var c := sim.combat
	var p := sim.player
	c.pickup(p, "rocket")
	ok(p.weapon == "rocket", "holding a rocket launcher")
	pose(p)
	var b: Dictionary = Skills.burst_of(c, p)
	var n := int(b["n"])
	var regen := float(b["regen"])
	ok(Skills.burst_hud(c, p) == [n, n, 1.0], "full pool on the HUD (%s)" % [Skills.burst_hud(c, p)])
	var rng0 := c.rng.state
	for i in n:
		p.cool = 0.0
		ok(c.weapons.try_fire(p, []), "burst shot %d fires" % (i + 1))
	p.cool = 0.0
	ok(not Skills.burst_ready(c, p) and not c.weapons.try_fire(p, []), "empty pool: no shot")
	ok(String(c.rules.hud_text(p)).contains("Shots " + "-".repeat(n)), "HUD pips empty (%s)" % c.rules.hud_text(p))
	c.weapons.clear()
	var st0 := c.rng.state
	for i in int(regen / DT) + 2: Skills.tick(c, p, DT)
	ok(c.rng.state == st0, "pool ticks draw no random numbers")
	ok(int(p.skill_n.get("b:rocket", n)) == 1, "one charge back after regen (%s)" % p.skill_n)
	for i in int(regen * (n - 1) / DT) + 2: Skills.tick(c, p, DT)
	ok(not p.skill_n.has("b:rocket") and not p.skill_cd.has("b:rocket"), "pool full again after n regens")
	ok(rng0 != 0, "rng sane")
	# the pool belongs to the weapon key, a fresh life forgets it
	Skills.burst_spend(c, p)
	ok(p.skill_n.has("b:rocket"), "spent")
	c.place_at(p, 0.0, 0.0)
	ok(p.skill_n.is_empty() and p.skill_cd.is_empty(), "respawn clears the pools")
	# without the overlay (online web numbers) there is no pool at all
	c.net_started = true
	c.pickup(p, "rocket")
	Skills.burst_spend(c, p)
	ok(p.skill_n.is_empty() and Skills.burst_ready(c, p), "no pool while the tuning is off")
	sim.dispose()

# 3. swapCd: drawing a heavy weapon takes a moment (no swap-cancel); light weapons are unchanged
func _swap() -> void:
	var sim := new_sim()
	var c := sim.combat
	var p := sim.player
	c.pickup(p, "meteor"); c.pickup(p, "smg")
	var mi := -1
	var si := -1
	for i in 3:
		if p.slots[i] != null and p.slots[i]["key"] == "meteor": mi = i
		if p.slots[i] != null and p.slots[i]["key"] == "smg": si = i
	ok(mi >= 0 and si >= 0, "meteor and smg in slots")
	c.equip_slot(p, si); p.cool = 0.0
	c.equip_slot(p, mi)
	ok(p.cool >= float(c.wdata("meteor")["swapCd"]) - 1e-9, "meteor draw time (%s)" % p.cool)
	p.cool = 0.0
	c.equip_slot(p, si)
	ok(p.cool == 0.0, "smg has no draw time")
	c.net_started = true
	c.equip_slot(p, mi)
	ok(p.cool == 0.0, "no draw time with the web numbers")
	sim.dispose()

# 4. air recovery rules and effect
func _recover() -> void:
	var sim := new_sim()
	var c := sim.combat
	var p := sim.player
	airborne(sim, p, 3.0, -15.0, -4.0, 0.0)
	p.stun = 1.0
	var st0 := c.rng.state
	c.events.clear()
	ok(Skills.recover_block(p, sim) == "", "allowed in the air (%s)" % Skills.recover_block(p, sim))
	ok(Skills.do_recover(p, sim, 1.0, 0.0), "recover toward the stick")
	ok(c.rng.state == st0, "recovery draws no random numbers")
	ok(p.stun == 0.0, "stun cleared")
	ok(absf(p.phys.vx - (-15.0 * Skills.RECOVER_DAMP + Skills.RECOVER_PUSH)) < 1e-9, "knock damped + burst (%s)" % p.phys.vx)
	ok(p.phys.vy >= Skills.RECOVER_VY, "pops up (%s)" % p.phys.vy)
	ok(p.recover_air_t > 0.0 and p.invuln > 0.0, "boosted air control + short invuln")
	var kinds := []
	for e: Dictionary in c.events: kinds.append(e["type"])
	ok(kinds.has("puff") and kinds.has("sfx") and kinds.has("recover"), "puff + sfx events (%s)" % [kinds])
	ok(not Skills.do_recover(p, sim, 1.0, 0.0) and Skills.recover_block(p, sim) == "charge", "one charge only")
	# landing refills it
	p.phys.grounded = true
	Skills.tick(c, p, DT)
	ok(Skills.recover_n(p) == 1, "landing refills the charge")
	# or RECOVER_REGEN s in the air
	airborne(sim, p, 3.0)
	ok(Skills.do_recover(p, sim, 0.0, 1.0), "second recovery")
	p.phys.grounded = false
	for i in int(Skills.RECOVER_REGEN / DT) - 10: Skills.tick(c, p, DT)
	ok(Skills.recover_n(p) == 0 and Skills.recover_ready_k(p) > 0.9, "almost back (%s)" % Skills.recover_ready_k(p))
	for i in 20: Skills.tick(c, p, DT)
	ok(Skills.recover_n(p) == 1, "back after %ss in the air" % Skills.RECOVER_REGEN)
	# no stick: toward the arena centre
	p.phys.px = 8.0; p.phys.pz = 0.0
	airborne(sim, p, 3.0)
	ok(Skills.do_recover(p, sim, 0.0, 0.0) and p.phys.vx < -10.0 and absf(p.phys.vz) < 1e-9, "no stick: toward the centre (%s)" % p.phys.vx)
	# refusals
	var cases := {"grounded": func(): p.phys.grounded = true,
		"down": func(): p.down_t = 1.0,
		"trapped": func(): p.trap_t = 1.0,
		"dead": func(): p.dead = true,
		"ladder": func(): p.phys.ladder = {"x": 0.0},
		"hit": func(): p.last_hit_time = c.time - 0.05,
		"low": func(): p.phys.py = Skills.recover_min_y(sim.ring_out_y) - 1.0}
	for why: String in cases:
		airborne(sim, p, 3.0)
		(cases[why] as Callable).call()
		ok(Skills.recover_block(p, sim) == why and not Skills.do_recover(p, sim, 1.0, 0.0), "refused: %s (%s)" % [why, Skills.recover_block(p, sim)])
		p.phys.ladder = {}
	airborne(sim, p, 3.0)
	ok(not Skills.recover_offer(p, sim), "plain jump: touch button does not offer RECOVER")
	p.last_hit_time = c.time - 0.5
	ok(Skills.recover_offer(p, sim), "knocked: touch button offers RECOVER")
	ok(Skills.recover_min_y(-25.0) > -25.0 + 10.0, "free falls cannot be saved (min y %s)" % Skills.recover_min_y(-25.0))
	p.dead = false
	sim.dispose()

# 4b. tuned shove: a short front-facing window cancels melee and staggers the attacker; classic stays untouched
func _parry() -> void:
	var sim := new_sim(0)
	var c := sim.combat
	var v := sim.player
	var a := sim.add_fighter("bruiser")
	v.phys.place(0.0, 0.0, 0.0); a.phys.place(0.0, 0.0, 2.0)
	v.face_yaw = 0.0; a.face_yaw = PI
	v.hp = c.max_hp(v); a.hp = c.max_hp(a)
	v.parry_t = 0.0; v.down_t = 0.0; a.down_t = 0.0
	c.shove(v, 0.0)
	ok(v.parry_t > 0.0, "tuned shove opens a parry window")
	c.events.clear(); a.stun = 0.0
	a.weapon = "bat"; a.swing = 0.5
	var hp0 := v.hp
	ok(c.try_parry(v, a), "a front-facing hit inside the window is parried")
	ok(is_equal_approx(v.hp, hp0), "the parry itself does not damage the defender")
	ok(a.swing < 0.0 and a.stun >= 0.6, "the parried attacker has the swing cancelled and is staggered")
	ok(c.events.any(func(e: Dictionary) -> bool: return e.get("type") == "parry"), "the parry emits a visual/audio event")
	ok(not c.try_parry(v, a), "one shove deflects only one incoming hit")
	v.face_yaw = PI; v.parry_t = 0.22
	ok(not c.try_parry(v, a), "a hit from behind is not deflected")
	c.damage_rule = "classic"
	v.parry_t = 1.0
	ok(not c.try_parry(v, a), "classic/web combat never applies the tuned parry")
	sim.dispose()

# 5. physics: the default (recover_air_t = 0) is unchanged; the boost keeps the burst and steers it
func _physics() -> void:
	var sim := new_sim()
	var p := sim.player
	var q := FighterState.new()
	for f: FighterState in [p, q]:
		f.phys.place(0.0, 5.0, 0.0); f.phys.grounded = false; f.phys.vx = 13.0
		f.phys.wish_x = 1.0; f.phys.speed = 7.5
	q.phys.set_map(sim.map, [])
	for i in 30:
		p.phys.step(DT, [], p); q.phys.step(DT, [], q)
	ok(p.phys.vx == q.phys.vx and p.phys.py == q.phys.py, "no recovery: identical physics")
	ok(p.phys.vx < 10.0, "normal air control pulls the knock down to run speed (%s)" % p.phys.vx)
	for f: FighterState in [p, q]:
		f.phys.place(0.0, 5.0, 0.0); f.phys.grounded = false; f.phys.vx = 13.0; f.phys.vz = 0.0
	p.recover_air_t = Skills.RECOVER_AIR
	for i in 30:
		p.phys.step(DT, [], p); q.phys.step(DT, [], q)
	ok(p.phys.vx > 11.5 and p.phys.vx > q.phys.vx + 2.0, "boost keeps the burst (%s vs %s)" % [p.phys.vx, q.phys.vx])
	p.phys.wish_x = 0.0; p.phys.wish_z = 1.0
	p.phys.vx = 0.0; p.phys.vz = -10.0
	q.phys.wish_x = 0.0; q.phys.wish_z = 1.0
	q.phys.vx = 0.0; q.phys.vz = -10.0
	p.recover_air_t = Skills.RECOVER_AIR
	for i in 20:
		p.phys.step(DT, [], p); q.phys.step(DT, [], q)
	ok(p.phys.vz > q.phys.vz + 1.0, "boost steers back harder (%s vs %s)" % [p.phys.vz, q.phys.vz])
	sim.dispose()

# 6. controls: the recover tap and the dash key without dash gear; bots never recover
func _controls() -> void:
	var sim := new_sim(3)
	var p := sim.player
	var pc: PlayerControl = sim.controllers[p]
	airborne(sim, p, 3.0, 0.0, -2.0, 0.0)
	pc.input.press("recover")
	sim.step(DT)
	ok(Skills.recover_n(p) == 0 and p.recover_air_t > 0.0, "recover tap works")
	airborne(sim, p, 3.0, 0.0, -2.0, 0.0)
	pc.input.press("dash")
	sim.step(DT)
	ok(Skills.recover_n(p) == 0, "dash key recovers in the air without dash gear")
	ok(not pc.input.peek("recover") and not pc.input.peek("dash"), "taps consumed")
	p.down_t = 1.0
	pc.input.press("recover")
	sim.step(DT)
	ok(not pc.input.peek("recover"), "taps drained while down")
	p.down_t = 0.0
	for i in 600:
		for b: FighterState in sim.fighters.slice(1):
			pose(b)
		sim.step(DT)
	var used := false
	for b: FighterState in sim.fighters.slice(1):
		if b.skill_n.has("recover") or b.recover_air_t > 0.0: used = true
	ok(not used, "bots never use the recovery")
	sim.dispose()
