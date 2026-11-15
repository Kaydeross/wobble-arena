extends SceneTree
## Balance overlay, tuned class hitboxes, weapon burst pools, swap draw time and the air recovery ("boing burst"),
## logic/skills.gd and docs/DAMAGE.md "Balance and cooldowns". npm run test:godot-skills
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
	_hitboxes()
	_bursts()
	_swap()
	_recover()
	_parry()
	_physics()
	_controls()
	_carry()
	_reactions()
	print("SKILLS %d checks, %d failed" % [checks, fails])
	quit(0 if fails == 0 else 1)

# 1. the overlay: on offline (zones), off for a bare Combat, online and the classic rule
func _tuning() -> void:
	var bare := Combat.new()
	bare.load_content()
	var shared_head := float(bare.wdata("mammoth")["headMul"])
	ok(not bare.tuning_active() and is_equal_approx(shared_head, 8.0), "bare Combat: shared numbers, Mammoth headMul %s (no online one-shot)" % shared_head)
	ok(is_equal_approx(float(bare.wdata("mallet")["ammo"]), 6.0), "shared Giant Mallet has 6 swings per pickup (%.0f)" % float(bare.wdata("mallet")["ammo"]))
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
	ok(is_equal_approx(float(c.wdata("rocket")["burst"]["regen"]), 3.5) and is_equal_approx(float(c.wdata("glauncher")["burst"]["regen"]), 3.0) \
		and is_equal_approx(float(c.wdata("meteor")["burst"]["regen"]), 4.5), "heavy launchers recharge in 3.0-4.5 s")
	ok(is_equal_approx(float(c.wdata("blower")["dmg"]), 2.8), "Air Blower puff does 2.8 (a full tank can finish a 150 HP class)")
	ok(float(c.wdata("minigun")["force"]) < float(bare.wdata("minigun")["force"]), "minigun knockback lowered")
	# Sprint 1.2: bow ammo, net trap and Uzi damage (all through Combat.wdata(); shared numbers stay the web ones)
	var bow := c.wdata("bow")
	ok(float(bow["ammo"]) == 8.0 and float(bare.wdata("bow")["ammo"]) == 12.0,
		"Twin Fang Bow: 8 volleys tuned (shared 12)")
	ok(float(bow["ammo"]) * 2.0 * float(bow["dmg"]) == 768.0,
		"bow pickup is 768 damage at full draw (8 volleys x 2 arrows x 48)")
	ok(float(c.wdata("net")["trap"]) == 2.0 and float(bare.wdata("net")["trap"]) == 4.5,
		"Net Gun: trap 2.0 s tuned (shared 4.5, tuned was 2.5)")
	ok(float(c.wdata("uzi")["dmg"]) == 3.8 and float(bare.wdata("uzi")["dmg"]) == 4.4,
		"Uzi: 3.8 damage tuned (shared 4.4, tuned was 3.4)")
	ok(float(c.wdata("uzi")["mag"]) * float(c.wdata("uzi")["dmg"]) == 152.0,
		"one Uzi mag is 152 damage (40 rounds), enough for a 150 HP class")
	# the tuned bow ammo reaches the pickup budget, the shared one keeps 12
	var picker := FighterState.new()
	picker.set_class("wobbler", c.classes["wobbler"])
	c.pickup(picker, "bow")
	ok(picker.get_ammo() == 8, "tuned bow pickup gives 8 volleys (%d)" % picker.get_ammo())
	var picker_web := FighterState.new()
	picker_web.set_class("wobbler", bare.classes["wobbler"])
	bare.pickup(picker_web, "bow")
	ok(picker_web.get_ammo() == 12, "shared/web bow pickup still gives 12 volleys (%d)" % picker_web.get_ammo())
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

# 1b. tuned class hit spheres (docs/DAMAGE.md "Tuned hitboxes"): the class `head` scales the head sphere, `size` the
# chest/legs, both clamped; a bare FighterState, the classic rule, the web and online-without-net_zones keep exactly
# 0.4 / 0.62 / 0.5 (x1.5 for giants). No random numbers anywhere.
func _hitboxes() -> void:
	var sim := new_sim()                  # offline MatchSim: the overlay is on, so every fighter is armed
	var c := sim.combat
	ok(sim.player.tuned and c.tuning_active(), "offline match: the player is armed with the tuned hit spheres")
	# A bare FighterState is what the JS-parity tests and the web shape use: never scaled.
	var bare := FighterState.new()
	bare.set_class("kid", c.classes["kid"])
	ok(not bare.tuned, "bare FighterState: untuned by default")
	ok(bare.cls_head == 1.4 and bare.cls_size == 0.86, "set_class stores the class head/size (%s / %s)" % [bare.cls_head, bare.cls_size])
	var b0 := bare.spheres(false)
	ok(float(b0[0][3]) == 0.4 and float(b0[1][3]) == 0.62 and float(b0[2][3]) == 0.5,
		"untuned spheres are exactly 0.4 / 0.62 / 0.5 (%s)" % [[float(b0[0][3]), float(b0[1][3]), float(b0[2][3])]])
	var b1 := bare.spheres(true)
	ok(float(b1[0][3]) == 0.4 * 1.5 and float(b1[1][3]) == 0.62 * 1.5 and float(b1[2][3]) == 0.5 * 1.5,
		"untuned giant spheres are the old 1.5x values (%s)" % [[float(b1[0][3]), float(b1[1][3]), float(b1[2][3])]])
	bare.big_t = 1.0
	ok(float(bare.spheres(false)[0][3]) == 0.4 * 1.5, "untuned Chaos Giant (big_t) also x1.5")
	# Tuned: neutral class multipliers keep the classic radii bit-identically (Wobbler 1 / 1).
	var p0 := sim.player.spheres(false)
	ok(float(p0[0][3]) == 0.4 and float(p0[1][3]) == 0.62 and float(p0[2][3]) == 0.5,
		"tuned Wobbler (1 / 1): still exactly 0.4 / 0.62 / 0.5")
	var st0 := c.rng.state
	var kid := sim.add_fighter("kid")             # head 1.4, size 0.86 -> clamped to 1.25 / 0.88
	var ks := kid.spheres(false)
	ok(is_equal_approx(float(ks[0][3]), 0.4 * 1.25), "Scamp head 1.4 clamps to +25%% (%.3f)" % float(ks[0][3]))
	ok(is_equal_approx(float(ks[1][3]), 0.62 * 0.88) and is_equal_approx(float(ks[2][3]), 0.5 * 0.88),
		"Scamp size 0.86 clamps to 0.88 (chest %.4f, legs %.4f)" % [float(ks[1][3]), float(ks[2][3])])
	var alien := sim.add_fighter("alien")         # head 1.3 -> also clamped to 1.25
	ok(float(alien.spheres(false)[0][3]) == float(ks[0][3]), "every head >= 1.25 class clamps to the same head radius")
	var tank := sim.add_fighter("tank")           # Bulwark: head 0.85 (smallest), size 1.16 -> clamped to 1.15
	var ts := tank.spheres(false)
	ok(is_equal_approx(float(ts[0][3]), 0.4 * 0.85), "Bulwark head 0.85 stays 0.85 (smallest target, %.3f)" % float(ts[0][3]))
	ok(is_equal_approx(float(ts[1][3]), 0.62 * 1.15) and is_equal_approx(float(ts[2][3]), 0.5 * 1.15),
		"Bulwark size 1.16 clamps to 1.15 (chest %.4f, legs %.4f)" % [float(ts[1][3]), float(ts[2][3])])
	var bruiser := sim.add_fighter("bruiser")     # head 0.92, size 1.12: inside the clamps
	var bs := bruiser.spheres(false)
	ok(is_equal_approx(float(bs[0][3]), 0.4 * 0.92) and is_equal_approx(float(bs[1][3]), 0.62 * 1.12),
		"Bruiser scales inside the clamps (head %.3f, chest %.4f)" % [float(bs[0][3]), float(bs[1][3])])
	# The giant x1.5 still applies on top of the class scale.
	var gk := kid.spheres(true)
	ok(is_equal_approx(float(gk[0][3]), 0.4 * 1.25 * 1.5) and is_equal_approx(float(gk[1][3]), 0.62 * 0.88 * 1.5),
		"giant x1.5 applies on top of the class scale (head %.3f)" % float(gk[0][3]))
	# No class may scale past the clamp bounds.
	var head_max := 0.0
	var body_max := 0.0
	for cid: String in c.classes:
		var s := sim.add_fighter(cid).spheres(false)
		head_max = maxf(head_max, float(s[0][3])); body_max = maxf(body_max, float(s[1][3]))
	ok(head_max <= 0.4 * 1.25 + 1e-9 and body_max <= 0.62 * 1.15 + 1e-9,
		"clamp bounds hold for every class (head <= %.3f, chest <= %.3f)" % [head_max, body_max])
	ok(c.rng.state == st0, "hit spheres draw no random numbers")
	# The flag is re-armed whenever a life (re)starts: classic rule, online without net_zones and no overlay all disarm.
	c.damage_rule = "classic"
	c.place_at(kid, 0.0, 0.0)
	var off := kid.spheres(false)
	ok(not kid.tuned and float(off[0][3]) == 0.4 and float(off[1][3]) == 0.62,
		"classic rule: place_at restores the web spheres for a Scamp (head %.3f)" % float(off[0][3]))
	c.damage_rule = "zones"; c.net_started = true
	c.place_at(kid, 0.0, 0.0)
	ok(not kid.tuned and float(kid.spheres(false)[0][3]) == 0.4, "online without net_zones: classic spheres (web parity)")
	c.net_zones = true
	c.place_at(kid, 0.0, 0.0)
	ok(kid.tuned and is_equal_approx(float(kid.spheres(false)[0][3]), 0.4 * 1.25), "online with net_zones: tuned spheres")
	c.net_zones = false; c.net_started = false; c.apply_tuning({})
	c.place_at(kid, 0.0, 0.0)
	ok(not kid.tuned and float(kid.spheres(false)[0][3]) == 0.4, "no overlay (empty tuning): classic spheres")
	sim.dispose()

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

# 7. Fastball Special: teammate carry & throw (docs/DAMAGE.md "Teammate carry/throw"). Only in tuned TEAM modes or a
# two-seat Arcade co-op run; gated on Combat.tuning_active() and drawing no random numbers. The Arcade revive-discount
# round trip needs a real run and lives in arcade_test.gd.
func _carry_sim() -> MatchSim:
	var sim := new_sim(2)
	var c := sim.combat
	c.mode_id = "t2"; c.mode = c.modes.get("t2", {}); c.teams = 2; c.ffa = true; c.brawl = true
	sim.fighters[0].team = 0; sim.fighters[1].team = 0; sim.fighters[2].team = 1
	sim.controllers.erase(sim.fighters[1]); sim.controllers.erase(sim.fighters[2])   # the test drives the other two
	return sim

func _carry() -> void:
	# --- gating: a tuned TEAM mode (t2/t3/t4, tdm, ctf) or a two-seat Arcade co-op run only ---
	var ffa := new_sim(2)
	ok(not ffa.combat.carry_active(), "classic (FFA): the Fastball Special is off")
	ffa.combat.mode_id = "t2"
	ok(not ffa.combat.carry_active(), "a team-mode name without teams: still off")
	ffa.combat.teams = 2
	ok(ffa.combat.carry_active(), "t2 with teams: on")
	ffa.combat.apply_tuning({})              # the shared web numbers (online without net_zones / the parity paths)
	ok(not ffa.combat.carry_active(), "tuning off: off (the web / parity path)")
	var ffa_p := ffa.player
	var ffa_ally: FighterState = ffa.fighters[1]
	ffa_p.team = 0; ffa_ally.team = 0
	ffa_ally.phys.place(ffa_p.phys.px, ffa_p.phys.py, ffa_p.phys.pz + 1.0)
	ffa_p.slot = -1; ffa_p.shove_cool = 0.0
	ok(not ffa.combat.try_carry(ffa_p), "tuning off: the shove stays a shove")
	ffa.dispose()
	# --- the lift: 1.4 m, ally-only, empty-handed ---
	var sim := _carry_sim()
	var c := sim.combat
	var p := sim.player
	var ally: FighterState = sim.fighters[1]
	var enemy: FighterState = sim.fighters[2]
	p.phys.place(0.0, 0.0, 0.0); ally.phys.place(0.0, 0.0, 1.0); enemy.phys.place(0.0, 0.0, 10.0)
	pose(p); pose(ally); pose(enemy)
	p.slot = -1; p.shove_cool = 0.0; p.face_yaw = 0.0
	ok(c.empty_handed(p), "the default Spatula is empty-handed")
	ok(c.carry_target(p) == ally, "the ally at 1.0 m is the carry target")
	ally.phys.place(0.0, 0.0, 1.5)
	ok(c.carry_target(p) == null, "1.5 m is outside CARRY_RANGE 1.4")
	ally.phys.place(0.0, 0.0, 1.0)
	enemy.phys.place(0.0, 0.0, 1.0); ally.phys.place(0.0, 0.0, 10.0)
	ok(c.carry_target(p) == null, "an enemy is never a carry target")
	enemy.phys.place(0.0, 0.0, 10.0); ally.phys.place(0.0, 0.0, 1.0); pose(ally)
	c.pickup(p, "bat")
	ok(not c.empty_handed(p) and not c.try_carry(p), "a picked-up weapon is not empty-handed: no lift")
	c.clear_inventory(p); c.set_weapon(p, "spatula")
	var st0 := c.rng.state
	ok(c.try_carry(p), "the empty-handed shove hoists the ally")
	ok(p.carrying == ally and ally.carried_by == p and not ally.carry_limp and p.shove_cool > 0.0, "the carry state is on both sides")
	ok(c.rng.state == st0, "the lift draws no random numbers")
	# --- the real input path: the shove tap lifts (normal shove suppressed), the carrier walks at 0.85x ---
	var pc: PlayerControl = sim.controllers[p]
	pc.cam_yaw = 0.0
	enemy.phys.place(0.0, 0.0, 1.8)          # inside the normal shove's 2.6 m front cone
	c.events.clear(); p.shove_cool = 0.0
	pc.input.press("shove")
	sim.step(DT)
	ok(p.carrying == ally, "PlayerControl: the shove tap hoists the teammate")
	ok(not c.events.any(func(e: Dictionary) -> bool: return e.get("type") == "hit" and e.get("f") == enemy),
		"PlayerControl: the normal shove is suppressed")
	ok(is_equal_approx(p.phys.speed, 7.5 * Combat.CARRY_SPEED_MUL), "the carrier walks at 0.85x (%.3f m/s)" % p.phys.speed)
	enemy.phys.place(0.0, 0.0, 10.0)
	# pinned overhead: the body follows the carrier, keeps its velocity zeroed and does not fall or steer
	for i in 20: sim.step(DT)
	ok(is_equal_approx(ally.phys.py, p.phys.py + Combat.CARRY_HOLD_HEIGHT),
		"the hoisted body is pinned overhead (%.2f m)" % (ally.phys.py - p.phys.py))
	ok(ally.phys.vx == 0.0 and ally.phys.vy == 0.0 and ally.phys.vz == 0.0, "the hoisted body is not simulated normally")
	# --- the fire path throws it; the exact launch vector is 18 m/s along the facing + 6 m/s up ---
	p.face_yaw = 0.0
	pc.input.hold("script", "fire", true)
	sim.step(DT)
	ok(p.carrying == null and ally.ball_t > 0.0, "PlayerControl: fire throws the carried teammate")
	ok(ally.phys.vz > 15.0 and ally.phys.vy > 3.0, "the thrown body leaves forward and high (%s)" % [[ally.phys.vx, ally.phys.vy, ally.phys.vz]])
	pc.input.clear()
	sim.dispose()
	# exact launch vector, checked on a direct throw before physics integrates it
	var s2 := _carry_sim()
	var p2 := s2.player
	var a2: FighterState = s2.fighters[1]
	p2.phys.place(0.0, 0.0, 0.0); a2.phys.place(0.0, 0.0, 1.0); pose(a2)
	p2.slot = -1; p2.shove_cool = 0.0; p2.face_yaw = 0.0
	ok(s2.combat.try_carry(p2), "hoist for the vector check")
	var st1 := s2.combat.rng.state
	ok(s2.combat.throw_carry(p2), "direct throw")
	ok(is_equal_approx(a2.phys.vz, Combat.THROW_SPEED) and is_equal_approx(a2.phys.vx, 0.0) and is_equal_approx(a2.phys.vy, Combat.THROW_UP),
		"launch vector: facing x 18 m/s + 6 m/s up (%s)" % [[a2.phys.vx, a2.phys.vy, a2.phys.vz]])
	ok(a2.ball_t > 0.0 and a2.ball_owner == p2 and p2.carrying == null and a2.carried_by == null, "the body is in flight (thrower recorded)")
	ok(s2.combat.rng.state == st1, "the throw draws no random numbers")
	s2.dispose()
	# --- living body-slam: 35 dmg / 20 force to the FIRST enemy, the thrown fighter takes no damage ---
	var s3 := _carry_sim()
	var c3 := s3.combat
	var p3 := s3.player
	var a3: FighterState = s3.fighters[1]
	var v1: FighterState = s3.fighters[2]
	var v2 := s3.add_fighter("wobbler")
	v2.team = 1
	p3.phys.place(0.0, 0.0, 0.0); a3.phys.place(0.0, 0.0, 1.0)
	v1.phys.place(0.0, 0.0, 8.0); v2.phys.place(0.0, 0.0, 12.0)
	for v: FighterState in [v1, v2]:
		v.hp = 200.0; v.invuln = 0.0; v.down_t = 0.0; v.shield_t = 0.0; v.cls_kb = 1.0
	pose(p3); pose(a3); pose(v1); pose(v2)
	p3.slot = -1; p3.shove_cool = 0.0; p3.face_yaw = 0.0
	var hp1 := v1.hp; var hp2 := v2.hp; var ahp := a3.hp
	c3.events.clear()
	ok(c3.try_carry(p3) and c3.throw_carry(p3), "hoist + throw for the slam")
	var guard := 0
	while v1.hp >= hp1 and guard < 240:
		s3.step(DT); guard += 1
	ok(v1.hp < hp1, "the flying body hit the first enemy (%d steps)" % guard)
	ok(is_equal_approx(hp1 - v1.hp, Combat.SLAM_DMG), "body-slam damage is 35 (%.3f)" % (hp1 - v1.hp))
	ok(is_equal_approx(v2.hp, hp2), "only the FIRST enemy is hit")
	ok(is_equal_approx(a3.hp, ahp), "the thrown fighter takes no damage from its own slam")
	var toast := false
	var slam_force := -1.0
	var slam_dmg := -1.0
	for e: Dictionary in c3.events:
		if e.get("type") == "toast" and str(e.get("text", "")).contains("FASTBALL"): toast = true
		if e.get("type") == "hit" and e.get("f") == v1:
			slam_force = float(e.get("force", -1.0)); slam_dmg = float(e.get("dmg", -1.0))
	ok(toast, "the FASTBALL SPECIAL! toast fires")
	ok(is_equal_approx(slam_force, Combat.SLAM_FORCE) and is_equal_approx(slam_dmg, Combat.SLAM_DMG),
		"the slam carries 35 dmg / 20 force (%s / %s)" % [slam_dmg, slam_force])
	s3.dispose()
	# --- downed Arcade co-op seat: limp body (no slam); place_at cuts the carry link on both sides ---
	var s4 := _carry_sim()
	var c4 := s4.combat
	var p4 := s4.player
	var a4: FighterState = s4.fighters[1]
	var e4: FighterState = s4.fighters[2]
	c4.arcade_coop = true; c4.pve_seats = [p4, a4]
	a4.dead = true; a4.elim = true; a4.death_t = 1e9
	p4.slot = -1; p4.shove_cool = 0.0
	p4.phys.place(0.0, 0.0, 0.0); a4.phys.place(0.0, 0.0, 1.0); e4.phys.place(0.0, 0.0, 8.0)
	e4.hp = 200.0; e4.invuln = 0.0
	pose(p4); pose(a4); pose(e4)
	ok(c4.carryable(p4, a4) and c4.try_carry(p4), "a downed co-op seat can be hoisted")
	ok(a4.carry_limp, "the hoisted downed body is limp (revive discount only, no slam)")
	p4.face_yaw = 0.0
	ok(c4.throw_carry(p4), "the limp body is thrown")
	var ehp := e4.hp
	for i in 240: s4.step(DT)
	ok(is_equal_approx(e4.hp, ehp), "a limp body never body-slams")
	a4.dead = true; a4.elim = true; a4.death_t = 1e9
	a4.phys.place(0.0, 0.0, 1.0); p4.phys.place(0.0, 0.0, 0.0); p4.shove_cool = 0.0
	ok(c4.try_carry(p4), "re-hoist for the place_at check")
	c4.place_at(a4, 0.0, 0.0)
	ok(p4.carrying == null and a4.carried_by == null and a4.ball_t < 0.0, "place_at cuts the carry link on both sides")
	s4.dispose()

# 8. Wobble Reactions (Sprint 2.3, docs/DAMAGE.md "Wobble Reactions"): the human bowling ball and the mid-air redirects.
# Every branch is gated on Combat.tuning_active(); none of them draws a random number.

## A duck-typed stand-in for the Arcade StageEvents crate provider (`Combat.hazard_source`): the pure-logic suite never
## imports the DLC class. `items` are the deflectables() rows; `calls` records every [id, dx, dz] deflect request.
class FakeHazards:
	extends RefCounted
	var items: Array = []
	var calls: Array = []
	func has_deflectables() -> bool: return not items.is_empty()
	func deflectables() -> Array: return items
	func deflect_crate(id: int, dx: float, dz: float) -> bool:
		calls.append([id, dx, dz])
		return true

## Put `a` at the origin facing +z, mid-swing with `key`, and sweep the weapon line once through z ~ 0.4 .. 2.1.
func _swing(c: Combat, a: FighterState, key: String) -> void:
	c.set_weapon(a, key)
	a.phys.place(0.0, 0.01, 0.0)
	a.yaw = 0.0; a.face_yaw = 0.0
	a.dead = false; a.down_t = 0.0; a.trap_t = 0.0; a.cool = 0.0; a.swing_hit = {}
	a.hand_x = 0.0; a.hand_y = 1.3; a.hand_z = 0.0
	a.arm_x = 0.0; a.arm_y = 0.0; a.arm_z = 1.0
	a.swing = 0.5; a.stab = false; a.cyclone = false; a.slam = false; a.assist_on = false
	for i in FighterState.BAT_N * 3: a.bat_prev[i] = 0.0
	for i in FighterState.BAT_N: a.bat_prev[i * 3 + 1] = 1.3
	a.bat_valid = true
	c.melee_sweep(a)

func _reactions() -> void:
	# --- 8a. Human Bowling Ball: a heavy swing on a NETTED fighter releases the trap and slides it at 26 m/s ---
	var sim := new_sim(0)
	var c := sim.combat
	var a := sim.player
	var v := sim.add_fighter("wobbler")
	var pin := sim.add_fighter("wobbler")
	c.place_at(v, 0.0, 1.2)
	c.place_at(pin, 0.0, 20.0)
	v.hp = 200.0; v.invuln = 0.0; v.cls_kb = 1.0
	var net := Weapons.TrapNet.new()
	net.life = 2.0; net.victims = [v]
	v.trap_t = 2.0; v.trap_net = net
	pose(a); pose(v)
	var rng_before: int = c.rng.state
	_swing(c, a, "bat")                        # Bat force 17 >= HEAVY_FORCE 16
	ok(v.trap_t == 0.0 and v.trap_net == null, "bowling: the heavy melee releases the Net Gun trap")
	ok(net.victims.is_empty(), "bowling: the TrapNet itself let the victim go")
	ok(c.bowl_slides.has(v), "bowling: the netted fighter starts sliding")
	ok(is_equal_approx(sqrt(v.phys.vx * v.phys.vx + v.phys.vz * v.phys.vz), Combat.BOWL_SPEED),
		"bowling: launched at 26 m/s (%.3f)" % sqrt(v.phys.vx * v.phys.vx + v.phys.vz * v.phys.vz))
	ok(v.phys.vz > 0.0 and is_equal_approx(v.phys.vy, 0.0) and v.phys.grounded, "bowling: flat slide along the swing (+z)")
	ok(v.stun == 0.0, "bowling: the hit's stun is cleared so the 26 m/s slide is real")
	ok(c.rng.state == rng_before, "bowling: the reaction draws no random numbers")
	var slide: Dictionary = c.bowl_slides[v]
	var sdx := float(slide["dx"])
	var sdz := float(slide["dz"])
	# the pin: one other fighter in the slide's path takes 30 dmg / 18 force; the bowler takes none of it
	c.place_at(pin, v.phys.px + sdx * 1.0, v.phys.pz + sdz * 1.0)
	pin.hp = 200.0; pin.invuln = 0.0; pin.cls_kb = 1.0; pin.dead = false; pin.down_t = 0.0
	var vhp := v.hp
	var php := pin.hp
	c.events.clear()
	c.timers(v, DT)                            # one fixed step: the bowling ball runs over the pin
	var fk := (c.kb_setting if c.kb_setting != 0.0 else 1.0) * 0.8 \
		* (float(c.mode.get("kbMul", 1.0)) if c.mode.get("kbMul", 0) else 1.0) * pin.cls_kb
	ok(is_equal_approx(php - pin.hp, Combat.BOWL_PIN_DMG), "bowling pin: 30 damage (%.2f)" % (php - pin.hp))
	ok(is_equal_approx(pin.phys.vx, sdx * Combat.BOWL_PIN_FORCE * fk) and is_equal_approx(pin.phys.vz, sdz * Combat.BOWL_PIN_FORCE * fk),
		"bowling pin: 18 force down the slide")
	ok(is_equal_approx(v.hp, vhp), "bowling: the bowler is not hurt by its own pin")
	var toasts := 0
	for e: Dictionary in c.events:
		if e.get("type") == "toast" and str(e.get("text", "")).contains("STRIKE"): toasts += 1
	ok(toasts == 1, "bowling: exactly one STRIKE! toast per launch")
	var php2 := pin.hp
	c.timers(v, DT)
	ok(is_equal_approx(pin.hp, php2), "bowling: one pin hit per launch (no double damage)")
	ok(c.bowl_slides.has(v), "bowling: still sliding the next fixed step")
	c.place_at(v, 0.0, 5.0)
	ok(not c.bowl_slides.has(v), "bowling: place_at clears the slide on a new life")
	# --- gating: trap_t == 0, a light weapon, and tuning off never launch ---
	var v2 := sim.add_fighter("wobbler")
	c.place_at(v2, 0.0, 1.2); v2.hp = 200.0; v2.invuln = 0.0
	pose(v2); _swing(c, a, "bat")
	ok(not c.bowl_slides.has(v2), "bowling: a fighter that is not netted is never launched")
	v2.trap_t = 2.0; v2.trap_net = null
	pose(v2); _swing(c, a, "spatula")          # Spatula force 13 < 16
	ok(not c.bowl_slides.has(v2) and v2.trap_t > 0.0, "bowling: a light weapon (Spatula 13) never launches")
	c.apply_tuning({})
	ok(not c.tuning_active(), "reactions: tuning off for the gate check")
	pose(v2); _swing(c, a, "bat")
	ok(not c.bowl_slides.has(v2) and v2.trap_t > 0.0, "reactions: tuning off leaves the trap and the slide alone")
	sim.dispose()

	# --- 8b. Mid-Air Crate Redirect: the combat/weapons layer swats a falling crate down the attacker's aim. The real
	# StageEvents crate (registration, drift, am.ev, landing) is exercised in arcade_test.gd; here the duck-typed provider is
	# the exact contract `Combat.hazard_source` documents (the pure-logic suite never imports the DLC class).
	var s2 := new_sim(0)
	var c2 := s2.combat
	var a2 := s2.player
	var fake := FakeHazards.new()
	fake.items = [{"id": 7, "x": 0.0, "y": 1.3, "z": 1.2, "r": 1.1}]
	c2.hazard_source = weakref(fake)
	ok(c2.hazard_deflectables().size() == 1, "redirect: the combat sees the registered falling crate")
	var prng: int = c2.rng.state
	_swing(c2, a2, "bat")
	ok(fake.calls.size() == 1 and int(fake.calls[0][0]) == 7 and float(fake.calls[0][2]) > 0.0
		and is_equal_approx(float(fake.calls[0][1]), 0.0),
		"redirect: a melee swing deflects the crate down its swing (+z), once")
	ok(c2.rng.state == prng, "redirect: the crate swat draws no random numbers")
	# a high-force shot does the same down the pellet ray; a low-force shot and tuning-off do not
	a2.phys.place(0.0, 0.01, 0.0)
	pose(a2)
	a2.hand_x = 0.0; a2.hand_y = 1.3; a2.hand_z = 0.0
	a2.arm_x = 0.0; a2.arm_y = 0.0; a2.arm_z = 1.0
	fake.items = [{"id": 9, "x": 0.0, "y": 1.3, "z": 3.0, "r": 0.5}]
	fake.calls.clear()
	c2.weapons.fire_gun(a2, "sniper")
	ok(fake.calls.size() == 1 and int(fake.calls[0][0]) == 9 and is_equal_approx(float(fake.calls[0][2]), 1.0),
		"redirect: the tuned Sniper shot (maxForce 8) deflects the crate down its aim")
	fake.calls.clear()
	c2.weapons.fire_gun(a2, "ak")
	ok(fake.calls.is_empty(), "redirect: a low-force shot (AK 2.2) never deflects a crate")
	c2.apply_tuning({})
	fake.calls.clear()
	c2.weapons.fire_gun(a2, "sniper")
	ok(fake.calls.is_empty(), "redirect: tuning off never deflects a crate")
	c2.hazard_source = null
	s2.dispose()

	# --- 8c. Mid-Air Redirect: explosive projectiles in flight (melee + high-force shot) ---
	var s3 := new_sim(0)
	var c3 := s3.combat
	var a3 := s3.player
	a3.phys.place(0.0, 0.01, 0.0)
	pose(a3)
	c3.weapons.launch_rocket(a3, "rocket")
	ok(c3.weapons.rockets.size() == 1, "redirect: a rocket is in flight")
	var r: Weapons.Shot = c3.weapons.rockets[0]
	r.px = 0.0; r.py = 1.3; r.pz = 1.2; r.vx = 0.0; r.vy = 1.0; r.vz = -10.0; r.age = 0.5
	_swing(c3, a3, "bat")
	ok(r.vz > 0.0 and is_equal_approx(sqrt(r.vx * r.vx + r.vz * r.vz), 10.0) and is_equal_approx(r.vy, 1.0),
		"redirect: a melee swing swats the rocket down the swing, keeping its horizontal speed and vy")
	c3.weapons.rockets.clear()
	c3.weapons.launch_grenade(a3, "glauncher")
	var g: Weapons.Shot = c3.weapons.grenades[0]
	g.px = 0.0; g.py = 1.3; g.pz = 1.2; g.vx = -5.0; g.vz = -10.0; g.vy = 2.0; g.landed = false
	_swing(c3, a3, "bat")
	ok(g.vz > 0.0 and is_equal_approx(sqrt(g.vx * g.vx + g.vz * g.vz), sqrt(125.0)) and is_equal_approx(g.vy, 2.0),
		"redirect: a grenade in flight is swatted the same way (horizontal speed kept)")
	c3.weapons.grenades.clear()
	# the shot path: the tuned Sniper (maxForce 8) swats a rocket in front of it and the tracer stops on it
	a3.phys.place(0.0, 0.01, 0.0)
	pose(a3)
	a3.hand_x = 0.0; a3.hand_y = 1.3; a3.hand_z = 0.0
	a3.arm_x = 0.0; a3.arm_y = 0.0; a3.arm_z = 1.0
	c3.weapons.rockets.clear()
	c3.weapons.launch_rocket(a3, "rocket")
	var r2: Weapons.Shot = c3.weapons.rockets[0]
	r2.px = 0.0; r2.py = 1.3; r2.pz = 3.0; r2.vx = 0.0; r2.vy = 0.0; r2.vz = -40.0; r2.age = 0.2
	c3.events.clear()
	c3.weapons.fire_gun(a3, "sniper")
	ok(r2.vz > 0.0 and is_equal_approx(sqrt(r2.vx * r2.vx + r2.vz * r2.vz), 40.0) and is_equal_approx(r2.vy, 0.0),
		"redirect: the tuned Sniper shot (maxForce 8) swats the rocket down its aim")
	var tracer_ok := false
	for e: Dictionary in c3.events:
		if e.get("type") == "tracer" and float(e["ez"]) > 2.4 and float(e["ez"]) < 3.6: tracer_ok = true
	ok(tracer_ok, "redirect: the shot's tracer stops on the swatted rocket (no damage)")
	ok(float(c3.wdata("sniper")["maxForce"]) >= Weapons.SHOT_DEFLECT_FORCE
		and float(c3.wdata("ak")["maxForce"]) < Weapons.SHOT_DEFLECT_FORCE,
		"redirect: high-force shot threshold: tuned Sniper 8 qualifies, AK 2.2 does not")
	c3.weapons.rockets.clear()
	c3.weapons.launch_rocket(a3, "rocket")
	var r3: Weapons.Shot = c3.weapons.rockets[0]
	r3.px = 0.0; r3.py = 1.3; r3.pz = 3.0; r3.vx = 0.0; r3.vy = 0.0; r3.vz = -40.0; r3.age = 0.2
	c3.weapons.fire_gun(a3, "ak")
	ok(r3.vz < 0.0, "redirect: a low-force shot (AK) never redirects a projectile")
	c3.apply_tuning({})
	c3.weapons.rockets.clear()
	c3.weapons.launch_rocket(a3, "rocket")
	var r4: Weapons.Shot = c3.weapons.rockets[0]
	r4.px = 0.0; r4.py = 1.3; r4.pz = 3.0; r4.vx = 0.0; r4.vy = 0.0; r4.vz = -40.0; r4.age = 0.2
	c3.weapons.fire_gun(a3, "sniper")
	ok(r4.vz < 0.0, "redirect: tuning off never redirects")
	s3.dispose()
