class_name Skills
extends RefCounted
## Godot-only per-fighter skills and charge pools on top of the web game's rules (docs/DAMAGE.md "Balance and
## cooldowns"). State lives in FighterState.skill_n / skill_cd (a missing id = full charges), ticked by
## Combat.timers. Nothing here draws a random number, so the parity paths (which never fill these) are unchanged.
##
##   "b:<weapon>"  burst pool of a weapon with `burst {n, regen}` in weapon_tuning.json: n shots, then one charge
##                 back every `regen` s (cloned from the ninja dash charges in ModeRules).
##   "recover"     air recovery, the "boing burst": one charge, back on landing or after RECOVER_REGEN s.

const RECOVER_REGEN := 6.0       ## s until the recovery charge returns in the air (landing refills it at once)
const RECOVER_HIT_DELAY := 0.2   ## s after being hit before you can recover (no instant combo cancel)
const RECOVER_DAMP := 0.3        ## horizontal velocity kept from the knock
const RECOVER_PUSH := 13.0       ## m/s burst toward the stick (or the arena centre)
const RECOVER_VY := 8.0          ## upward speed at least
const RECOVER_AIR := 0.5         ## s of boosted air control (FighterPhysics reads FighterState.recover_air_t)
const RECOVER_AIR_SPEED := 12.0  ## top air speed you can steer at while boosted
const RECOVER_AIR_ACC := 22.0    ## air acceleration while boosted (normal air control is 14)
const RECOVER_INVULN := 0.2
const RECOVER_OFFER := 3.0       ## s after a hit the touch context button offers RECOVER while airborne

## Forget every pool (a fresh life: Combat.place_at).
static func reset(f: FighterState) -> void:
	if not f.skill_n.is_empty(): f.skill_n.clear()
	if not f.skill_cd.is_empty(): f.skill_cd.clear()
	f.recover_air_t = 0.0

## Count the regen timers down (Combat.timers). Landing refills the recovery charge.
static func tick(c: Combat, f: FighterState, dt: float) -> void:
	if f.skill_cd.is_empty(): return
	if f.phys.grounded and f.skill_cd.has("recover"):
		f.skill_cd.erase("recover"); f.skill_n.erase("recover")
	for id: String in f.skill_cd.keys():
		var t: float = f.skill_cd[id] - dt
		if t > 0.0:
			f.skill_cd[id] = t
			continue
		var mx := 1
		var regen := RECOVER_REGEN
		if id.begins_with("b:"):
			var b: Variant = c.wdata(id.substr(2)).get("burst")
			if not b is Dictionary:               # the pool is gone (tuning off): full again
				f.skill_cd.erase(id); f.skill_n.erase(id)
				continue
			mx = int(b.get("n", 1)); regen = float(b.get("regen", 1.0))
		var n: int = int(f.skill_n.get(id, mx)) + 1
		if n >= mx:
			f.skill_cd.erase(id); f.skill_n.erase(id)
		else:
			f.skill_n[id] = n; f.skill_cd[id] = t + regen

# ============================== weapon bursts ==============================

## The held weapon's `burst` ({n, regen}) or {} when it has none.
static func burst_of(c: Combat, f: FighterState) -> Dictionary:
	var b: Variant = c.wdata(f.weapon).get("burst") if f.weapon != "" else null
	return b if b is Dictionary else {}

## May the held weapon fire (a charge left in its burst pool, or no pool)?
static func burst_ready(c: Combat, f: FighterState) -> bool:
	var b := burst_of(c, f)
	return b.is_empty() or int(f.skill_n.get("b:" + f.weapon, int(b.get("n", 1)))) > 0

## One shot of the held weapon (Combat.use_ammo): spend a burst charge and start its regen.
static func burst_spend(c: Combat, f: FighterState) -> void:
	var b := burst_of(c, f)
	if b.is_empty(): return
	var id := "b:" + f.weapon
	var n := int(f.skill_n.get(id, int(b.get("n", 1))))
	f.skill_n[id] = maxi(0, n - 1)
	if not f.skill_cd.has(id): f.skill_cd[id] = float(b.get("regen", 1.0))

## HUD: [charges, max, 0..1 progress of the next charge] for the held weapon, [] = no pool.
static func burst_hud(c: Combat, f: FighterState) -> Array:
	var b := burst_of(c, f)
	if b.is_empty(): return []
	var id := "b:" + f.weapon
	var mx := int(b.get("n", 1))
	var regen := float(b.get("regen", 1.0))
	var prog := 1.0 - float(f.skill_cd[id]) / regen if f.skill_cd.has(id) and regen > 0.0 else 1.0
	return [int(f.skill_n.get(id, mx)), mx, clampf(prog, 0.0, 1.0)]

# ============================== air recovery ==============================

## Recovery charges left (0 or 1).
static func recover_n(f: FighterState) -> int:
	return int(f.skill_n.get("recover", 1))

## 0..1: how far the recovery charge is back (1 = ready).
static func recover_ready_k(f: FighterState) -> float:
	if recover_n(f) > 0: return 1.0
	return clampf(1.0 - float(f.skill_cd.get("recover", 0.0)) / RECOVER_REGEN, 0.0, 1.0)

## Lowest height you can still recover from: a quarter of the way down to the ring-out line, so a knock off a ledge
## can be saved but a free fall cannot.
static func recover_min_y(ring_out_y: float) -> float:
	return ring_out_y * 0.25 if ring_out_y < 0.0 else ring_out_y + 1.0

## Touch: offer the RECOVER context button? Only after a knock (hit in the last RECOVER_OFFER s) while in the air, so
## ordinary jumps and the spawn drop keep RELOAD / nothing on the button. The tap itself works any time it is allowed.
static func recover_offer(f: FighterState, sim: MatchSim) -> bool:
	var p := f.phys
	return not f.dead and not p.grounded and p.ladder.is_empty() and f.down_t <= 0.0 and f.trap_t <= 0.0 \
		and sim.combat.time - f.last_hit_time < RECOVER_OFFER and p.py >= recover_min_y(sim.ring_out_y)

## Why recovery is refused right now ("" = allowed). The touch button and tests read it.
static func recover_block(f: FighterState, sim: MatchSim) -> String:
	var p := f.phys
	if f.dead or f.elim: return "dead"
	if p.grounded: return "grounded"
	if f.down_t > 0.0: return "down"
	if f.trap_t > 0.0: return "trapped"
	if not p.ladder.is_empty(): return "ladder"
	if recover_n(f) <= 0: return "charge"
	if sim.combat.time - f.last_hit_time < RECOVER_HIT_DELAY: return "hit"
	if p.py < recover_min_y(sim.ring_out_y): return "low"
	return ""

## The "boing burst": in the air, clear the stun, kill most of the knock, burst toward the stick (or the arena
## centre) and up, then a short window of strong air control. One charge (back on landing or after RECOVER_REGEN).
static func do_recover(f: FighterState, sim: MatchSim, ix: float, iz: float) -> bool:
	if recover_block(f, sim) != "": return false
	var p := f.phys
	var l := sqrt(ix * ix + iz * iz)
	if l < 0.2:                         # no stick: back toward the middle of the arena
		ix = -p.px; iz = -p.pz; l = sqrt(ix * ix + iz * iz)
		if l < 0.05:
			ix = sin(f.yaw); iz = cos(f.yaw); l = 1.0
	ix /= l; iz /= l
	f.stun = 0.0
	p.vx = p.vx * RECOVER_DAMP + ix * RECOVER_PUSH
	p.vz = p.vz * RECOVER_DAMP + iz * RECOVER_PUSH
	p.vy = maxf(p.vy, RECOVER_VY)
	f.recover_air_t = RECOVER_AIR
	f.invuln = maxf(f.invuln, RECOVER_INVULN)
	f.skill_n["recover"] = 0; f.skill_cd["recover"] = RECOVER_REGEN
	var c := sim.combat
	c.ev({"type": "puff", "kind": "dash", "x": p.px, "y": p.py + 0.9, "z": p.pz, "dx": ix, "dz": iz})
	c.ev({"type": "sfx", "name": "swing", "f": f})
	c.ev({"type": "recover", "f": f})
	return true
