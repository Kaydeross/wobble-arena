class_name BotBrain
extends RefCounted
## The web game's bot AI (botThink + pickTarget, botWants, botGround; public/index.html ~7733-7971), one
## brain per bot. Ported line by line, in the same order, with every Math.random() replaced by combat.rng in the same
## call order, so a seeded match is repeatable and tools/bots-reference.js (the real JS) can check the decisions exactly
## (npm run test:godot-bots).
##   - target: re-picked every DIFFS.react + 0..0.3 s (or when the target dies): the nearest enemy, +3 m for bots (a
##     slight preference for the human); team-aware through Combat.is_friend; only the player when bots are not in a
##     free-for-all; dummies (cfg.behav 'dummy') only look at the player and wander.
##   - aim error: a new random offset of +-BOT_AIM_ERR[diff] on every re-pick; fire only when the wobbly arm (or the
##     hip-carried barrel) lines up (0.95 easy, 0.975 others), there is line of sight, and the target is inside
##     min(weapon range, DIFFS.sight) * 0.92.
##   - movement: crates it wants (weapons only when empty-handed, power-ups, heals under 85% health) within BOT_GRAB[diff];
##     otherwise chase: guns keep their BOT_PREF range (back off inside 55%, circle-strafe in between), melee walks in.
##     Wander when there is nobody to chase.
##   - edge awareness: never walk or hop off into the void: probe the floor ahead (1.1, 2.3 m and further with speed),
##     turn up to +-0.8 / 1.5 rad to find floor, else stop; no jump without somewhere to land.
##   - stuck watchdog: pushing for over a second without moving 0.8 m -> give up on that crate for 4 s, escape for
##     1.6 s to a random wander spot. Hop onto things in the way (stuck 0.18 s), up to a target on a ledge, and the
##     odd bouncy hop (DIFFS.jump).
##   - attacks: guns in bursts (botBurst) with DIFFS.atk pauses, reload when empty (or under 60% with nobody in sight),
##     launchers / throwables per BOT_FIRE, the bow draws to 85%; kicks and spatula / melee swings inside 2.4 m;
##     ninja dashes toward a target 6..26 m away.
## Deliberate differences: `unstick`, `hold_busy` and `shrink_guard` (see below). Not in the web AI (so not here): ladder climbing (only the player grabs ladders), a low-health target preference,
## Construction blocks (bots ignore them), hot potato fleeing (no web mode sets `potato` any more).

const AIM_ERR := {"easy": 2.2, "normal": 1.1, "hard": 0.45, "insane": 0.12}       ## BOT_AIM_ERR
const PREF := {"net": 7, "flame": 5, "katana": 12, "boomerang": 11, "shuriken": 13, "typhoon": 13, "bow": 14, "glauncher": 12,
	"cluster": 11, "knife": 9, "snake": 7, "ak": 10, "smg": 6, "minigun": 8, "revolver": 10, "mammoth": 9, "snow": 8, "uzi": 8,
	"shotgun": 5, "sniper": 24, "glove": 3.2, "rocket": 12, "meteor": 14,
	# DLC pack weapons (godot/data/extra/<pack>/weapons.json; keys that exist only in a pack mode, so no parity path reads them).
	# The default 8 m kept a bot outside the 92% of the range it fires from: the 7 m Flambe Torch and Didgeridoo Blaster never fired.
	"flambetorch": 4.5, "didgeridooblaster": 4.5, "peppergrinder": 9, "snowballcannon": 10, "ornamentlauncher": 10,
	"aussieboomerang": 11, "giftbomb": 10, "souppot": 10, "vegemitejar": 9}           ## BOT_PREF (preferred range by weapon key)
const GRAB := {"easy": 9, "normal": 15, "hard": 32, "insane": 70}                  ## BOT_GRAB (how far a bot walks for a crate)

## ---- BOT_FIRE: how bots use each non-gun ranged weapon TYPE (web: rocket + PROJ[type]) ----
## A held weapon counts as ranged when its type is "gun" or Weapons.LAUNCH has a fire function for it, exactly like the
## web `ranged` test (gun / rocket / PROJ[type]). This table only says how to aim and pace it:
##   aim: "chest" (aimOff around the chest), "glauncher" / "net" (at the feet plus the lob drop), "ball" (lobbed: +0.2 per m + 0.7)
##   min: no shot closer than this (m); cr: [a, b] random extra cooldown, divided by DIFFS.atk
## Weapons batch 2 (shuriken, typhoon, boomerang, snake, snow = type "ball"; the trident is melee for bots) is in
## Weapons.LAUNCH and uses the web values below. A future LAUNCH type missing here uses BOT_FIRE_DEFAULT (throw at the
## chest from the BOT_PREF range).
##   wait (Godot-only, with `hold_busy`): "boom" = not while its boomerang is out (FighterState.boom), "typhoon" = not
##   while its blades are out (Weapons.ty_in_flight). The web bot pulls the trigger anyway: the launcher refuses, but
##   the bot still pays the cooldown and one ammo (and draws its random cooldown).
const BOT_FIRE := {
	"rocket": {"aim": "chest", "min": 5.0, "cr": [0.2, 0.8]},
	"glauncher": {"aim": "glauncher", "min": 5.0, "cr": [0.1, 0.6]},
	"net": {"aim": "net", "min": 0.0, "cr": [0.1, 0.6]},
	"bow": {"aim": "chest", "min": 0.0, "cr": [0.1, 0.6]},
	"knife": {"aim": "chest", "min": 0.0, "cr": [0.1, 0.6]},
	# --- weapons batch 2 ---
	"shuriken": {"aim": "chest", "min": 0.0, "cr": [0.1, 0.6]},
	"typhoon": {"aim": "chest", "min": 0.0, "cr": [0.1, 0.6], "wait": "typhoon"},
	"boomerang": {"aim": "chest", "min": 0.0, "cr": [0.1, 0.6], "wait": "boom"},
	"snake": {"aim": "chest", "min": 0.0, "cr": [0.1, 0.6]},
	"ball": {"aim": "ball", "min": 6.0, "cr": [0.1, 0.6]},
}
const BOT_FIRE_DEFAULT := {"aim": "chest", "min": 0.0, "cr": [0.1, 0.6]}

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
var aim_off: Array = [0.0, 0.0, 0.0]   ## aimOff (doubles: Vector3 is single precision)
var wander: Variant = null       ## [x, z] or null
# stuck watchdog
var escape_t := 0.0              ## escapeT: running off to a wander spot, no chasing / crates
var give_t := 0.0                ## giveT: how long bad_crate stays ignored
var bad_crate: Variant = null    ## the crate it got stuck going for (Dictionary) or null
var wd_on := false               ## wdX !== undefined
var wd_x := 0.0
var wd_z := 0.0
var wd_t := 0.0
# hop state (kept for the web parity dump)
var hop_t := 0.0
var hop_n := -1                  ## -1 = unset (undefined in the web game: no air dash before its own jump)
var hop_y0 := 0.0
var hop_to := 0
var mt := 0.0                    ## b.mt: a range dummy's mover clock (PracticeRange.range_bot)
## counters for tests / the HUD (not in the web game): how often the watchdog fired.
var escapes := 0
## Godot-only fix (on by default; the parity test turns it off): when the watchdog trips again during an escape, the
## web bot picks another random spot, which from a pocket in a corner (rooftops: between a block and the stairs)
## mostly points back into the corner, so it can stay there for minutes. With `unstick` the second trip sends it 5 m
## straight back from where it was pushing instead. Same random numbers either way.
var unstick := true
## Godot-only (on by default; the parity test turns it off): BOT_FIRE "wait" rows hold fire instead of wasting a
## cooldown and ammo on a boomerang / typhoon throw the launcher refuses.
var hold_busy := true
## Godot-only (on): on a shrinking floor (Mega Damage, Sudden Death on shrink / squeeze) a bot within SHRINK_MARGIN of
## the floor's edge steps back in, so the floor does not shrink out from under it (the web bots only use the
## shrinking `wander` range and fall off with the edge). Inactive when nothing shrinks, so parity is unaffected.
var shrink_guard := true
const SHRINK_MARGIN := 3.0

func _init(difficulty: Dictionary, p_diff: String) -> void:
	d = difficulty
	diff = p_diff

## pickTarget: the nearest enemy, with a slight preference for the human.
## Arcade co-op (docs/ARCADE_COOP_PLAN.md §4.4, 2+ seats only): MatchSim carries the run's player seats in the
## "pve_seats" meta (ArcadeManager.setup_sim). Then the crew (a bot with is_player false) hunts the nearest LIVING seat -
## a teammate bot seat included - and a teammate bot seat (is_player true) hunts the crew. One seat / no meta = the
## single-player path below, unchanged: the web parity reference never sees this branch.
func pick_target(b: FighterState, sim: MatchSim) -> FighterState:
	var ctf: CtfRules = sim.combat.rules.ctf       # Capture the Flag only (null elsewhere: the parity runs never see this)
	if ctf != null:
		var ct := ctf.bot_target(b)
		if ct != null: return ct
	var best: FighterState = null
	var bd := 1e9
	var pve: Array = sim.get_meta("pve_seats", [])
	var cands: Array
	if pve.size() > 1:
		cands = pve if not b.is_player else sim.fighters.filter(func(f: FighterState) -> bool: return not pve.has(f))
	elif sim.combat.ffa:
		cands = sim.fighters
	else:
		cands = [sim.player]
	for f: FighterState in cands:
		if f == b or f.dead or sim.combat.is_friend(b, f): continue
		if pve.size() > 1 and f.elim: continue
		var dd := sqrt((f.phys.px - b.phys.px) * (f.phys.px - b.phys.px) + (f.phys.pz - b.phys.pz) * (f.phys.pz - b.phys.pz)) + (0.0 if f.is_player else 3.0)
		if dd < bd: bd = dd; best = f
	return best

## botGround: is there floor to stand on (or a short drop to it) at (x, z)? Shrinking floors and moving tiles are in
## sim.solids, so the shrinking edge counts as void too.
static func ground_at(solids: Array, py: float, x: float, z: float, up: float = 0.7) -> bool:
	var hi := py + up
	var lo := py - 7.0
	for sb: Dictionary in solids:
		if x > sb["minX"] and x < sb["maxX"] and z > sb["minZ"] and z < sb["maxZ"]:
			var top: float = sb["top"]
			if top <= hi and top >= lo: return true
	return false

## botThink, one fixed step.
func think(b: FighterState, sim: MatchSim, dt: float) -> void:
	if b.carried_by != null: return         # Fastball Special: a carried teammate bot does not act from overhead
	# Ledge cling (overlay only, docs/DAMAGE.md): a bot that caught a ledge hangs for the overlay's delay, then climbs.
	# `b.hang` is only ever written by Ledge (MatchSim creates it while Combat.tuning_active()), so the parity paths never
	# enter this branch.
	if not b.hang.is_empty():
		b.phys.want_jump = sim.ledge != null and b.hang_t >= float((sim.ledge.cfg as Dictionary)["botClimbDelay"])
		return
	var combat := sim.combat
	if not combat.brawl and PracticeRange.is_range(sim.map):    # practice-range dummies (rangeBot)
		PracticeRange.range_bot(b, sim.fighters.find(b) - 1, sim.player, sim.map["range"], dt, self)
		return
	var rng := combat.rng
	var p := b.phys
	var brawl := combat.brawl
	var busy := b.dead or b.down_t > 0.0
	var wkey := b.weapon if combat.weapons_data.has(b.weapon) else "spatula"
	var w := combat.wdata(wkey)
	var wt: String = w.get("type", "")
	var ranged := brawl and b.slot >= 0 and (wt == "gun" or Weapons.LAUNCH.has(wt))
	if not ranged or wt != "bow": b.draw = 0.0; b.nocked = false
	jump_t -= dt; escape_t -= dt; give_t -= dt
	if brawl:                                      # re-pick a target a few times a second (a bit later on easy)
		think_t -= dt
		if think_t <= 0.0 or (target != null and target.dead):
			think_t = float(d.get("react", 0.25)) + rng.range_f(0, 0.3)
			target = pick_target(b, sim)
			var e: float = AIM_ERR.get(diff, 1.1)
			aim_off = [rng.range_f(-e, e), rng.range_f(-e, e) * 0.5, rng.range_f(-e, e)]
			if rng.next() < 0.4: strafe *= -1.0
			los = target != null and sim.has_los(b, target)
	else: target = null if sim.player == null or sim.player.dead else sim.player
	var tg := target
	var dx := tg.phys.px - p.px if tg else 0.0
	var dz := tg.phys.pz - p.pz if tg else 0.0
	var dist := sqrt(dx * dx + dz * dz) if tg else 99.0
	var to_yaw := atan2(dx, dz)

	if b.swing >= 0.0:                             # finish a swing
		b.face_yaw = b.swing_yaw
		if not busy and combat.melee_tick(b, wkey, dt, b.swing_yaw): combat.after_swing(b)

	ai_t -= dt
	if ai_t <= 0.0:
		ai_t = rng.range_f(2, 5)
		var wr := sim.wander()
		if rng.next() < 0.35: wander = null
		else: wander = [rng.range_f(-wr, wr), rng.range_f(-wr, wr)]

	var crate: Dictionary = {}                     # is there a crate worth walking to?
	if brawl and not busy:
		var bd: float = GRAB.get(diff, 15)
		for c: Dictionary in sim.pickups.list:
			if not c["grounded"] or not sim.pickups.bot_wants(b, c): continue
			if escape_t > 0.0 or (bad_crate != null and is_same(c, bad_crate) and give_t > 0.0) or c["gy"] > p.py + 1.7: continue   # not one it can't reach
			var cd := sqrt((c["x"] - p.px) * (c["x"] - p.px) + (c["z"] - p.pz) * (c["z"] - p.pz))
			if cd < bd and not (tg and dist < 3.5): bd = cd; crate = c

	# Throwable rubble (overlay only, offline destructible matches): a resting chunk worth the detour when an enemy is
	# around, then walked to exactly like a crate. `sim.rubble` is null in every other match.
	var chunk: Dictionary = {}
	if sim.rubble != null and not busy and b.rubble == 0 and b.stun <= 0.0 and b.swing < 0.0 and b.kick_t < 0.0 \
			and escape_t <= 0.0 and b.shove_cool <= 0.0 and tg != null and not tg.dead:
		chunk = sim.rubble.bot_chunk(b, float((sim.rubble.cfg as Dictionary)["botGrab"]))
	var goal: Array = []                           # Capture the Flag: [x, z, kind] = walk to the free flag / run with it / stay with the carrier
	if combat.rules.ctf != null and brawl and not busy:
		goal = combat.rules.ctf.bot_goal(b)
		if goal.size() > 0 and goal[2] != "escort": crate = {}
	if not chunk.is_empty() and crate.is_empty():
		crate = chunk                                # walk to the chunk first: it is the ranged option that always works
	var wish := [p.wish_x, p.wish_z]               # kept while stunned, like b.wish
	var chasing := brawl and tg != null and not (escape_t > 0.0)
	if not busy and b.swing < 0.0 and b.kick_t < 0.0 and b.stun <= 0.0:
		var dj := float(d.get("jump", 0))
		if not crate.is_empty():
			var cx: float = crate["x"] - p.px
			var cz: float = crate["z"] - p.pz
			var cd := sqrt(cx * cx + cz * cz)
			if cd == 0.0: cd = 1.0
			wish = [cx / cd, cz / cd]; b.face_yaw = atan2(cx, cz)
			if dj and p.grounded and jump_t <= 0.0 and rng.next() < dt:
				p.want_jump = true; jump_t = rng.range_f(1.2, 3)
		elif goal.size() > 0:
			var gx: float = goal[0] - p.px
			var gz: float = goal[1] - p.pz
			var gd := sqrt(gx * gx + gz * gz)
			if gd < 0.25: wish = [0.0, 0.0]
			else: wish = [gx / gd, gz / gd]; b.face_yaw = atan2(gx, gz)
			if dj and p.grounded and jump_t <= 0.0 and rng.next() < dt * 0.5:
				p.want_jump = true; jump_t = rng.range_f(1.2, 3)
		elif chasing:
			var pref: float = float(PREF.get(b.weapon, 8)) if ranged else 1.7
			var id := 1.0 / maxf(dist, 0.05)            # (two bots can stand on exactly the same spot)
			if sim.rubble != null and b.rubble == 1:    # holding a chunk: close to the overlay's throwing window
				if dist > float((sim.rubble.cfg as Dictionary)["botThrowMax"]) * 0.8: wish = [dx * id, dz * id]
				else: wish = [0.0, 0.0]
			elif ranged:
				if dist > pref + 2.0: wish = [dx * id, dz * id]
				elif dist < pref * 0.55: wish = [-dx * id * 0.8, -dz * id * 0.8]
				else: wish = [-dz * id * 0.65 * strafe, dx * id * 0.65 * strafe]   # circle-strafe
			elif dist > pref: wish = [dx * id, dz * id]
			else: wish = [0.0, 0.0]
			b.face_yaw = to_yaw
			if dj and p.grounded and jump_t <= 0.0 and dist > 3.0 and rng.next() < dt * dj * 2.0:    # harder bots hop around
				p.want_jump = true; jump_t = rng.range_f(1.2, 3)
		elif wander != null:
			var wx: float = wander[0] - p.px
			var wz: float = wander[1] - p.pz
			var wd := sqrt(wx * wx + wz * wz)
			if wd < 0.8: wander = null; wish = [0.0, 0.0]
			else:
				wish = [wx / wd * 0.6, wz / wd * 0.6]; b.face_yaw = atan2(wx, wz)
		else: wish = [0.0, 0.0]
	elif busy or b.swing >= 0.0 or b.kick_t >= 0.0: wish = [0.0, 0.0]

	if not crate.is_empty() and str(crate.get("state", "")) != "" and sim.rubble != null:
		var cdx: float = float(crate["x"]) - p.px
		var cdz: float = float(crate["z"]) - p.pz
		if _hyp(cdx, cdz) <= float((sim.rubble.cfg as Dictionary)["pickupRange"]):
			sim.rubble.try_pickup(b)                 # in reach: SHOVE's equivalent (a bot has no input state for it)
	# stuck watchdog: pushing for over a second without getting anywhere (under a platform, against a wall) -> give up and wander elsewhere
	if not busy and b.swing < 0.0 and _hyp(wish[0], wish[1]) > 0.3:
		if not wd_on: wd_on = true; wd_x = p.px; wd_z = p.pz; wd_t = 0.0
		wd_t += dt
		if wd_t > 1.0:
			if _hyp(p.px - wd_x, p.pz - wd_z) < 0.8:
				var again := escape_t > 0.0                  # the last escape did not get anywhere either
				var wr2 := sim.wander()
				bad_crate = crate if not crate.is_empty() else null; give_t = 4.0; escape_t = 1.6
				wander = [rng.range_f(-wr2, wr2), rng.range_f(-wr2, wr2)]; ai_t = rng.range_f(2, 4); stuck_t = 0.0; jump_t = 1.0
				escapes += 1
				var bl := _hyp(wish[0], wish[1])
				if unstick and again and bl > 0.0:          # Godot-only: back off away from what blocks it (no extra random numbers)
					wander = [p.px - wish[0] / bl * 5.0, p.pz - wish[1] / bl * 5.0]
			wd_x = p.px; wd_z = p.pz; wd_t = 0.0
	else: wd_on = false; wd_t = 0.0
	# jumping: hop up onto things in the way, up to a target on higher ground, and the odd bouncy hop
	if not busy and p.grounded and b.swing < 0.0:
		var wl := _hyp(wish[0], wish[1])
		if wl > 0.3 and _hyp(p.vx, p.vz) < 1.3: stuck_t += dt
		else: stuck_t = 0.0
		var high := tg != null and not tg.dead and tg.phys.py > p.py + 0.7 and tg.phys.py < p.py + 1.7 and dist < 7.0 and not (escape_t > 0.0)
		if (stuck_t > 0.18 and not (escape_t > 0.0)) or (high and jump_t <= 0.0):
			p.want_jump = true; stuck_t = 0.0; jump_t = rng.range_f(0.6, 1.4)
		elif brawl and wl > 0.3 and jump_t <= 0.0 and rng.next() < dt * 0.25 * maxf(0.4, float(d.get("jump", 0)) * 3.0):
			p.want_jump = true; jump_t = rng.range_f(1.5, 3.5)
	if p.grounded and not busy and not (hop_t > 1.0):     # edge awareness: never walk or hop off into the void
		var wl2 := _hyp(wish[0], wish[1])
		if wl2 > 0.05:
			var ux: float = wish[0] / wl2
			var uz: float = wish[1] / wl2
			var sp2 := _hyp(p.vx, p.vz)
			if not _clear(sim.solids, p, ux, uz, 1.0, 0.0, sp2):
				var done := false
				for a: float in [0.8, -0.8, 1.5, -1.5]:
					var ca := cos(a)
					var sa := sin(a)
					if _clear(sim.solids, p, ux, uz, ca, sa, sp2):
						wish = [(ux * ca - uz * sa) * wl2, (ux * sa + uz * ca) * wl2]; done = true; break
				if not done: wish = [0.0, 0.0]
				p.want_jump = false
			if p.want_jump and not ground_at(sim.solids, p.py, p.px + wish[0] / wl2 * 3.6, p.pz + wish[1] / wl2 * 3.6, 3.2): p.want_jump = false   # nowhere to land
		elif p.want_jump and tg and not ground_at(sim.solids, p.py, p.px + sin(b.face_yaw) * 3.6, p.pz + cos(b.face_yaw) * 3.6, 3.2): p.want_jump = false
	if shrink_guard and not busy and not combat.rules.shrink.is_empty():   # Godot-only: keep off the edge of a shrinking floor
		_shrink_guard(combat.rules.shrink["box"], p, wish)
	# Ledge cling edge probe (overlay only): a falling bot steers toward a catchable ledge so the grab reaches. `sim.ledge`
	# is null in every untuned match, so the parity reference never sees it.
	if sim.ledge != null and not p.grounded and p.vy <= 0.0 and not busy:
		var lp := sim.ledge.probe(p)
		if not lp.is_empty():
			var ldx := float(lp["x"]) - p.px
			var ldz := float(lp["z"]) - p.pz
			var ll := _hyp(ldx, ldz)
			if ll > 0.05:
				wish = [ldx / ll, ldz / ll]
				p.want_jump = false
	p.wish_x = wish[0]; p.wish_z = wish[1]

	if combat.rules.dash_gear(b) and tg and not tg.dead and b.dash_n > 0 and b.dash_cd <= 0.0 \
			and dist > 6.0 and dist < 26.0 and rng.next() < dt * 0.35:
		combat.rules.do_dash(b, tg.phys.px - p.px, tg.phys.pz - p.pz)      # ninja dash toward the target
	var aiming := false
	if ranged and b.rubble == 0 and tg and not tg.dead and not busy and dist < float(d.get("sight", 20)) and crate.is_empty():
		# point the (wobbly) arm at them; fire once it's roughly lined up
		var bf: Dictionary = BOT_FIRE.get(wt, BOT_FIRE_DEFAULT)
		var tx: float = tg.chest_x + aim_off[0]
		var ty: float = tg.chest_y + aim_off[1]
		var tz: float = tg.chest_z + aim_off[2]
		match bf["aim"] if wt != "gun" else "chest":
			"glauncher":                                # aim at the feet, allowing for the drop
				var tt := dist / float(w["speed"])
				ty = tg.phys.py + 0.15 + maxf(0.0, 4.5 * tt * tt - 1.8 * tt)
			"net":
				var tt2 := dist / float(w["speed"])
				ty = tg.phys.py + 0.45 + maxf(0.0, 3.5 * tt2 * tt2 - 1.5 * tt2)
			"ball": ty += dist * 0.2 + 0.7
		var ax := tx - b.shoulder_x
		var ay := ty - b.shoulder_y
		var az := tz - b.shoulder_z
		var av := Combat.norm3(ax, ay, az)
		b.aim_x = av[0]; b.aim_y = av[1]; b.aim_z = av[2]
		aiming = true
		var rng_max := minf(float(w["range"]) if w.get("range", 0) else 40.0, float(d.get("sight", 20)))
		var min_d: float = 0.0 if wt == "gun" else float(bf["min"])
		var hv := Combat.norm3(tx - b.hand_x, ty - b.hand_y, tz - b.hand_z)
		var bdir := _barrel(b)
		var lined: bool = bdir[0] * hv[0] + bdir[1] * hv[1] + bdir[2] * hv[2] > (0.95 if diff == "easy" else 0.975)
		if wt == "bow":
			if b.cool <= 0.0 and los:
				if not b.nocked:
					if b.grab_t < 0.0: b.grab_t = 0.0
				else: b.draw = minf(1.0, b.draw + dt / 0.55)
			else: b.draw = 0.0
		var wait: String = bf.get("wait", "") if hold_busy and wt != "gun" else ""
		var out := (wait == "boom" and b.boom != null) or (wait == "typhoon" and combat.weapons.ty_in_flight(b))
		if not out and b.swing < 0.0 and b.kick_t < 0.0 and b.cool <= 0.0 and b.stun <= 0.0 and lined and los and dist > min_d and dist < rng_max * 0.92 \
				and (wt != "bow" or b.draw >= 0.85):
			b.face_yaw = to_yaw
			var atk := float(d.get("atk", 1))
			if wt == "gun":
				if b.reloading: b.cool = 0.05
				else:
					b.cool = float(w["cooldown"]) + rng.range_f(0, 0.12)
					combat.weapons.fire_gun(b, b.weapon)
					if float(w["cooldown"]) < 0.2:
						burst += 1
						if burst >= int(w.get("botBurst", 4)): burst = 0; b.cool += rng.range_f(0.8, 1.6) / atk
					else: b.cool += rng.range_f(0, 0.5) / atk
			else:
				var cr: Array = bf["cr"]
				b.cool = float(w["cooldown"]) + rng.range_f(cr[0], cr[1]) / atk
				combat.weapons.call(Weapons.LAUNCH[wt], b, b.weapon, [])
			if not (wt == "gun" and b.reloading): combat.use_ammo(b)
	# Throwable rubble (overlay only): throw the held chunk at the target when it is inside the overlay's window. The throw
	# is aimed ballistically (Rubble.throw_at) and resolved through Combat.hit; after it the bot is back on its weapon.
	if sim.rubble != null and b.rubble == 1 and tg != null and not tg.dead and not busy and b.stun <= 0.0:
		b.face_yaw = to_yaw
		var ty_aim: float = tg.chest_y if tg.chest_y > tg.phys.py + 0.5 else tg.phys.py + 1.1
		var av := Combat.norm3(tg.chest_x - b.shoulder_x, ty_aim - b.shoulder_y, tg.chest_z - b.shoulder_z)
		b.aim_x = av[0]; b.aim_y = av[1]; b.aim_z = av[2]
		if sim.rubble.bot_throw(b, tg, los, dist):
			b.cool = maxf(b.cool, float((sim.rubble.cfg as Dictionary)["botThink"]) + 0.25)
	if b.slot >= 0 and w.get("mag", 0) and not combat.inf and not b.reloading:      # bots top up their guns too, mostly when nobody is in sight
		var bs: Variant = b.current_slot()
		if bs != null and int(bs["mag"]) >= 0 and _can_reload_now(b) and (int(bs["mag"]) <= 0 or (not aiming and int(bs["mag"]) < float(w["mag"]) * 0.6)):
			combat.start_reload(b)

	# close-range attacks: kick, spatula (or a held melee weapon)
	if not busy and b.kick_t < 0.0 and b.swing < 0.0 and b.rubble == 0 and tg and not tg.dead and dist < 2.4:
		var kk := float(d.get("kick", 1))
		var atk2 := float(d.get("atk", 1))
		if brawl and b.kick_cool <= 0.0 and rng.next() < dt * 1.2 * kk:
			b.face_yaw = to_yaw; combat.start_kick(b, to_yaw); b.kick_cool = rng.range_f(2.5, 5) / kk
		elif brawl and b.cool <= 0.0 and rng.next() < dt * 1.6 * atk2:
			if b.slot >= 0 and wt == "melee":
				combat.melee_begin(b, b.weapon, to_yaw); b.set_ammo(b.get_ammo() - 1); b.cool = rng.range_f(1.0, 2.0) / atk2
			elif b.slot >= 0:
				sim.quick_melee(b, to_yaw); b.cool = rng.range_f(0.8, 1.6) / atk2
			else:
				combat.melee_begin(b, "spatula", to_yaw); b.cool = rng.range_f(1.0, 2.0) / atk2
			b.face_yaw = to_yaw
	if not b.dead and b.swing < 0.0 and not aiming:        # arm hangs down a little in front
		var v := Combat.norm3(sin(b.yaw) * 0.25, -1.0, cos(b.yaw) * 0.25)
		b.aim_x = v[0]; b.aim_y = v[1]; b.aim_z = v[2]

## Step back in from the edge of the shrinking floor box: drop the outward part of the wish and add an inward push.
static func _shrink_guard(bx: Dictionary, p: FighterPhysics, wish: Array) -> void:
	var ix := 0.0
	var iz := 0.0
	if p.px < float(bx["minX"]) + SHRINK_MARGIN: ix = 1.0
	elif p.px > float(bx["maxX"]) - SHRINK_MARGIN: ix = -1.0
	if p.pz < float(bx["minZ"]) + SHRINK_MARGIN: iz = 1.0
	elif p.pz > float(bx["maxZ"]) - SHRINK_MARGIN: iz = -1.0
	if ix == 0.0 and iz == 0.0: return
	if ix != 0.0 and wish[0] * ix < 0.0: wish[0] = 0.0
	if iz != 0.0 and wish[1] * iz < 0.0: wish[1] = 0.0
	wish[0] += ix * 0.8; wish[1] += iz * 0.8
	var l := _hyp(wish[0], wish[1])
	if l > 1.0: wish[0] /= l; wish[1] /= l

## The `clear` probe of the edge check: floor along the direction (ux, uz) turned by (ca, sa) at 1.1, 2.3 and 2.3 + speed * 0.2 m.
static func _clear(solids: Array, p: FighterPhysics, ux: float, uz: float, ca: float, sa: float, sp: float) -> bool:
	var ddx := ux * ca - uz * sa
	var ddz := ux * sa + uz * ca
	for dd: float in [1.1, 2.3, 2.3 + sp * 0.2]:
		if not ground_at(solids, p.py, p.px + ddx * dd, p.pz + ddz * dd): return false
	return true

## Fighter.canReloadNow
static func _can_reload_now(b: FighterState) -> bool:
	return not (b.dead or b.down_t > 0.0 or b.trap_t > 0.0 or b.swing >= 0.0 or b.kick_t >= 0.0 or b.throw_key != "")

## Fighter.barrelDir (the hip-carried minigun's barrel tilts down) or the arm.
static func _barrel(f: FighterState) -> Array:
	if f.hip_d == 0.0: return [f.arm_x, f.arm_y, f.arm_z]
	var hl := sqrt(f.arm_x * f.arm_x + f.arm_z * f.arm_z)
	if hl == 0.0: hl = 1.0
	var np := asin(Combat.clampf_js(f.arm_y, -1.0, 1.0)) + f.hip_d
	return [f.arm_x / hl * cos(np), sin(np), f.arm_z / hl * cos(np)]

## Math.hypot for two numbers in doubles (Vector2 is single precision).
static func _hyp(a: float, b: float) -> float:
	return sqrt(a * a + b * b)
