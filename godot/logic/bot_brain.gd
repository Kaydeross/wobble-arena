class_name BotBrain
extends RefCounted
## A reduced port of the web game's bot AI (botThink, public/index.html ~7441) for the Phase 1 slice: re-pick the
## nearest enemy a few times a second, walk to it (or to a crate it wants), circle-strafe and shoot with a gun once
## the wobbly arm is lined up, kick and swing up close, hop when stuck. Not ported yet (full AI task): edge
## awareness, the stuck watchdog's escape, pillars hops, hot potato, ninja dashes. Launchers, nets and the bow
## (draw to 85% before letting go) use the web game's aim and range rules.
## Random numbers come from combat.rng, so a seeded match is repeatable.

const AIM_ERR := {"easy": 2.2, "normal": 1.1, "hard": 0.45, "insane": 0.12}       ## BOT_AIM_ERR
const PREF := {"net": 7, "flame": 5, "katana": 12, "boomerang": 11, "shuriken": 13, "typhoon": 13, "bow": 14, "glauncher": 12,
	"cluster": 11, "knife": 9, "snake": 7, "ak": 10, "smg": 6, "minigun": 8, "revolver": 10, "mammoth": 9, "snow": 8, "uzi": 8,
	"shotgun": 5, "sniper": 24, "glove": 3.2, "rocket": 12, "meteor": 14}           ## BOT_PREF
const GRAB := {"easy": 9, "normal": 15, "hard": 32, "insane": 70}                  ## BOT_GRAB

var d: Dictionary                ## DIFFS[cfg.diff] (shared/difficulties.json)
var diff := "normal"
var squat := false
var target: FighterState = null
var think_t := 0.0
var ai_t := 1.0
var jump_t := 0.0
var stuck_t := 0.0
var strafe := 1.0
var los := false
var burst := 0
var aim_off := Vector3.ZERO
var wander: Variant = null       ## [x, z] or null

func _init(difficulty: Dictionary, p_diff: String) -> void:
	d = difficulty
	diff = p_diff

## pickTarget: the nearest enemy, with a slight preference for the human.
func pick_target(b: FighterState, sim: MatchSim) -> FighterState:
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in (sim.fighters if sim.combat.ffa else [sim.player]):
		if f == b or f.dead or sim.combat.is_friend(b, f): continue
		var dist := Vector2(f.phys.px - b.phys.px, f.phys.pz - b.phys.pz).length() + (0.0 if f.is_player else 3.0)
		if dist < bd: bd = dist; best = f
	return best

func think(b: FighterState, sim: MatchSim, dt: float) -> void:
	var combat := sim.combat
	var rng := combat.rng
	var p := b.phys
	var brawl := combat.brawl
	var busy := b.dead or b.down_t > 0.0
	var w := combat.wdata(b.weapon if b.weapon != "" else "spatula")
	var wt: String = w.get("type", "")
	var ranged := brawl and b.slot >= 0 and (wt == "gun" or Weapons.LAUNCH.has(wt))
	if not ranged or wt != "bow": b.draw = 0.0; b.nocked = false
	jump_t -= dt
	think_t -= dt
	if think_t <= 0.0 or (target != null and target.dead):
		think_t = float(d.get("react", 0.25)) + rng.range_f(0, 0.3)
		target = pick_target(b, sim)
		var e: float = AIM_ERR.get(diff, 1.1)
		aim_off = Vector3(rng.range_f(-e, e), rng.range_f(-e, e) * 0.5, rng.range_f(-e, e))
		if rng.next() < 0.4: strafe *= -1.0
		los = target != null and sim.has_los(b, target)
	var tg := target
	var dx := tg.phys.px - p.px if tg else 0.0
	var dz := tg.phys.pz - p.pz if tg else 0.0
	var dist := sqrt(dx * dx + dz * dz) if tg else 99.0
	var to_yaw := atan2(dx, dz)

	if b.swing >= 0.0:                     # finish a swing
		b.face_yaw = b.swing_yaw
		if not busy and combat.melee_tick(b, b.weapon if b.weapon != "" else "spatula", dt, b.swing_yaw): combat.after_swing(b)

	ai_t -= dt
	if ai_t <= 0.0:
		ai_t = rng.range_f(2, 5)
		var wr := float(sim.map.get("wander", 10))
		wander = null if rng.next() < 0.35 else [rng.range_f(-wr, wr), rng.range_f(-wr, wr)]

	var crate: Dictionary = {}               # a crate worth walking to?
	if brawl and not busy:
		var bd: float = GRAB.get(diff, 15)
		for c: Dictionary in sim.pickups.list:
			if not c["grounded"] or not sim.pickups.bot_wants(b, c) or c["gy"] > p.py + 1.7: continue
			var cd := Vector2(c["x"] - p.px, c["z"] - p.pz).length()
			if cd < bd and not (tg and dist < 3.5): bd = cd; crate = c

	var wish := Vector2.ZERO
	if not busy and b.swing < 0.0 and b.kick_t < 0.0 and b.stun <= 0.0:
		if not crate.is_empty():
			var cx: float = crate["x"] - p.px
			var cz: float = crate["z"] - p.pz
			var cd := sqrt(cx * cx + cz * cz)
			if cd == 0.0: cd = 1.0
			wish = Vector2(cx / cd, cz / cd); b.face_yaw = atan2(cx, cz)
		elif brawl and tg:
			var pref: float = float(PREF.get(b.weapon, 8)) if ranged else 1.7
			var id := 1.0 / maxf(dist, 0.05)
			if ranged:
				if dist > pref + 2.0: wish = Vector2(dx * id, dz * id)
				elif dist < pref * 0.55: wish = Vector2(-dx * id * 0.8, -dz * id * 0.8)
				else: wish = Vector2(-dz * id * 0.65 * strafe, dx * id * 0.65 * strafe)   # circle-strafe
			elif dist > pref: wish = Vector2(dx * id, dz * id)
			b.face_yaw = to_yaw
			var dj := float(d.get("jump", 0))
			if dj and p.grounded and jump_t <= 0.0 and dist > 3.0 and rng.next() < dt * dj * 2.0:
				p.want_jump = true; jump_t = rng.range_f(1.2, 3)
		elif wander != null:
			var wx: float = wander[0] - p.px
			var wz: float = wander[1] - p.pz
			var wd := sqrt(wx * wx + wz * wz)
			if wd < 0.8: wander = null
			else:
				wish = Vector2(wx / wd * 0.6, wz / wd * 0.6); b.face_yaw = atan2(wx, wz)
	p.wish_x = wish.x; p.wish_z = wish.y

	if not busy and p.grounded and b.swing < 0.0:          # hop onto things in the way, and the odd bouncy hop
		var wl := wish.length()
		if wl > 0.3 and Vector2(p.vx, p.vz).length() < 1.3: stuck_t += dt
		else: stuck_t = 0.0
		var high := tg != null and not tg.dead and tg.phys.py > p.py + 0.7 and tg.phys.py < p.py + 1.7 and dist < 7.0
		if stuck_t > 0.18 or (high and jump_t <= 0.0):
			p.want_jump = true; stuck_t = 0.0; jump_t = rng.range_f(0.6, 1.4)
		elif brawl and wl > 0.3 and jump_t <= 0.0 and rng.next() < dt * 0.25 * maxf(0.4, float(d.get("jump", 0)) * 3.0):
			p.want_jump = true; jump_t = rng.range_f(1.5, 3.5)

	var aiming := false
	if ranged and tg and not tg.dead and not busy and dist < float(d.get("sight", 20)) and crate.is_empty():
		var tx := tg.chest_x + aim_off.x
		var ty := tg.chest_y + aim_off.y
		var tz := tg.chest_z + aim_off.z
		if wt == "glauncher" or wt == "net":           # aim at the feet, allowing for the drop
			var tt := dist / float(w["speed"])
			if wt == "glauncher": ty = tg.phys.py + 0.15 + maxf(0.0, 4.5 * tt * tt - 1.8 * tt)
			else: ty = tg.phys.py + 0.45 + maxf(0.0, 3.5 * tt * tt - 1.5 * tt)
		var ax := tx - b.shoulder_x
		var ay := ty - b.shoulder_y
		var az := tz - b.shoulder_z
		var al := sqrt(ax * ax + ay * ay + az * az)
		if al > 1e-6:
			b.aim_x = ax / al; b.aim_y = ay / al; b.aim_z = az / al
		aiming = true
		var rng_max := minf(float(w.get("range", 40)) if w.get("range", 0) else 40.0, float(d.get("sight", 20)))
		var hx := tx - b.hand_x
		var hy := ty - b.hand_y
		var hz := tz - b.hand_z
		var hl := sqrt(hx * hx + hy * hy + hz * hz)
		var lined := hl > 1e-6 and (b.arm_x * hx + b.arm_y * hy + b.arm_z * hz) / hl > (0.95 if diff == "easy" else 0.975)
		var min_d := 5.0 if (wt == "rocket" or wt == "glauncher") else 0.0
		if wt == "bow":
			if b.cool <= 0.0 and los:
				if not b.nocked:
					if b.grab_t < 0.0: b.grab_t = 0.0
				else: b.draw = minf(1.0, b.draw + dt / 0.55)
			else: b.draw = 0.0
		if b.swing < 0.0 and b.kick_t < 0.0 and b.cool <= 0.0 and b.stun <= 0.0 and lined and los and dist > min_d and dist < rng_max * 0.92 \
				and (wt != "bow" or b.draw >= 0.85):
			b.face_yaw = to_yaw
			if wt == "gun":
				if b.reloading: b.cool = 0.05
				else:
					combat.weapons.fire_gun(b, b.weapon)
					b.cool = float(w["cooldown"]) + rng.range_f(0, 0.12)
					if float(w["cooldown"]) < 0.2:
						burst += 1
						if burst >= int(w.get("botBurst", 4)): burst = 0; b.cool += rng.range_f(0.8, 1.6) / float(d.get("atk", 1))
					else: b.cool += rng.range_f(0, 0.5) / float(d.get("atk", 1))
					combat.use_ammo(b)
			else:
				var cr := rng.range_f(0.2, 0.8) if wt == "rocket" else rng.range_f(0.1, 0.6)
				b.cool = float(w["cooldown"]) + cr / float(d.get("atk", 1))
				combat.weapons.call(Weapons.LAUNCH[wt], b, b.weapon, [])
				combat.use_ammo(b)
	var bs: Variant = b.current_slot()
	if bs != null and w.get("mag", 0) and not combat.inf and not b.reloading:      # top up the gun
		if int(bs["mag"]) >= 0 and (int(bs["mag"]) <= 0 or (not aiming and int(bs["mag"]) < float(w["mag"]) * 0.6)):
			combat.start_reload(b)

	# close-range attacks: kick, spatula (or a held melee weapon)
	if not busy and b.kick_t < 0.0 and b.swing < 0.0 and tg and not tg.dead and dist < 2.4:
		var kk := float(d.get("kick", 1))
		var atk := float(d.get("atk", 1))
		if brawl and b.kick_cool <= 0.0 and rng.next() < dt * 1.2 * kk:
			b.face_yaw = to_yaw; combat.start_kick(b, to_yaw); b.kick_cool = rng.range_f(2.5, 5) / kk
		elif brawl and b.cool <= 0.0 and rng.next() < dt * 1.6 * atk:
			if b.slot >= 0 and wt == "melee":
				combat.melee_begin(b, b.weapon, to_yaw); b.set_ammo(b.get_ammo() - 1); b.cool = rng.range_f(1.0, 2.0) / atk
			elif b.slot >= 0:
				sim.quick_melee(b, to_yaw); b.cool = rng.range_f(0.8, 1.6) / atk
			else:
				combat.melee_begin(b, "spatula", to_yaw); b.cool = rng.range_f(1.0, 2.0) / atk
			b.face_yaw = to_yaw
	if not b.dead and b.swing < 0.0 and not aiming:        # arm hangs down a little in front
		var v := Combat.norm3(sin(b.yaw) * 0.25, -1.0, cos(b.yaw) * 0.25)
		b.aim_x = v[0]; b.aim_y = v[1]; b.aim_z = v[2]
