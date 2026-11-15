class_name Skills
extends RefCounted
## Godot-only per-fighter skills and charge pools on top of the web game's rules (docs/DAMAGE.md "Balance and
## cooldowns"). State lives in FighterState.skill_n / skill_cd (a missing id = full charges), ticked by
## Combat.timers. Nothing here draws a random number, so the parity paths (which never fill these) are unchanged.
##
##   "b:<weapon>"  burst pool of a weapon with `burst {n, regen}` in weapon_tuning.json: n shots, then one charge
##                 back every `regen` s (cloned from the ninja dash charges in ModeRules).
##   "recover"     air recovery, the "boing burst": one charge, back on landing or after RECOVER_REGEN s.
##   "sig"         the class signature move (Sprint 3.3, docs/DAMAGE.md "Class signature skills"): one charge, back
##                 after SIGNATURE_CD s. FighterState.class_id picks the move (SIG_CLASS); the short move windows live
##                 in Combat.sig_fx so Combat.hit can read the Fortress Stance immunity. Nothing here draws a random
##                 number and every entry point is gated on Combat.tuning_active().

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
	# Class signature skills (Sprint 3.3): the short move windows live in Combat.sig_fx, which is empty in every untuned
	# / parity match, so this costs one is_empty() there and nothing else. The 12 s charge itself is the "sig" id below.
	if not c.sig_fx.is_empty() and c.sig_fx.has(f): _sig_tick(c, f, dt)
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
		elif id == SIG_ID:                        # class signature skill: one charge, SIGNATURE_CD seconds
			regen = SIGNATURE_CD
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

# ============================== class signature skills (Sprint 3.3) ==============================
## ONE signature move per class on a shared 12 s cooldown ("sig"), triggered by the touch context button or the signature
## key (keyboard B / pad D-pad Up). Everything is gated on Combat.tuning_active() (offline / net_zones), so the web game,
## the JS parity paths and online without net_zones never reach it; bots never cast (no BotBrain change), so their
## decisions and the bots-reference parity stay identical. No branch here draws a combat random number: the hits use the
## shared Combat.hit() (whose only draw is the normal K.O. fall side, exactly like any attack) and the Seismic Slam's
## knockdown uses the deterministic Combat.topple_flat().
##
## Class mapping: the six moves cover the ten class ids that have a signature move; SIG_CLASS is the one table, so
## "every shipped class id maps or is documented as none" is tested totally. Elder (Gramps) has none (SIG_NONE) and an
## unknown class id gets none too.

const SIG_ID := "sig"             ## the charge id in FighterState.skill_n / skill_cd
const SIGNATURE_CD := 12.0        ## s for the one signature charge to come back (Combat.place_at refills it)
const SIG_NONE := ["elder"]       ## shipped classes with no signature move (the context button stays RELOAD / hidden)

## Class id -> move id: wobbler -> belly; bruiser/champ/rampage -> slam; kid/dash -> vault; tank -> fort;
## alien/ace -> tac; ghost -> phase. The extra Godot-only classes share their archetype's move.
const SIG_CLASS := {
	"wobbler": "belly",
	"bruiser": "slam", "champ": "slam", "rampage": "slam",
	"kid": "vault", "dash": "vault",
	"tank": "fort",
	"alien": "tac", "ace": "tac",
	"ghost": "phase",
}
## Move id -> English name (the i18n key; shown as a toast on cast and read by tests).
const SIG_NAMES := {
	"belly": "Belly Bounce", "slam": "Seismic Slam", "vault": "Vault Flip",
	"fort": "Fortress Stance", "tac": "Tac-Reload", "phase": "Phase Shift",
}

# --- Belly Bounce (wobbler): radial knock away/up; the caster bounces off the floor too ---
const SIG_BELLY_R := 3.0          ## m horizontal reach
const SIG_BELLY_DY := 2.0         ## m vertical reach
const SIG_BELLY_DMG := 10.0
const SIG_BELLY_FORCE := 15.0
const SIG_BELLY_UP := 0.55        ## the hit direction's y component
const SIG_BELLY_HOP := 4.5        ## m/s upward bounce for the caster when grounded

# --- Seismic Slam (bruiser/champ/rampage): an airborne dive that lands as an AoE topple shockwave ---
const SIG_SLAM_R := 3.8           ## m horizontal reach on landing
const SIG_SLAM_DY := 2.5          ## m vertical reach on landing
const SIG_SLAM_DMG := 18.0
const SIG_SLAM_FORCE := 22.0
const SIG_SLAM_UP := 0.25         ## the hit direction's y component
const SIG_SLAM_DOWN := 1.1        ## s the shockwave knockdown lasts (Combat.topple_flat)
const SIG_SLAM_AROUND := 3.0      ## s an armed dive may stay airborne before it fizzles
const SIG_SLAM_DIVE := -22.0      ## m/s straight down (FighterPhysics' terminal fall speed)

# --- Vault Flip (kid/dash): 1.5 s speed burst + a springboard bounce off an opponent in front ---
const SIG_VAULT_R := 2.0          ## m reach of the springboard
const SIG_VAULT_DY := 2.4         ## m vertical reach
const SIG_VAULT_DMG := 6.0
const SIG_VAULT_FORCE := 10.0
const SIG_VAULT_UP := -0.4        ## the stomped victim is pushed down (a head bounce, not a launch)
const SIG_VAULT_VY := 9.5         ## m/s upward spring for the caster
const SIG_VAULT_SPD := 1.5        ## s of the x1.4 speed burst (FighterState.spd_t, FighterPhysics)

# --- Fortress Stance (tank): 1.5 s planted: no knockback at all + the tuned parry window ---
const SIG_FORT_TIME := 1.5

# --- Tac-Reload (alien/ace): instant magazine refill + 1.5 s of x1.5 fire rate ---
const SIG_RATE_TIME := 1.5
const SIG_RATE_MUL := 1.5

# --- Phase Shift (ghost): 0.6 s of invulnerability (attacks, projectiles, nets and props pass through) ---
const SIG_PHASE_TIME := 0.6

## The signature move id for a class ("" = none, also for an unknown id).
static func sig_of(class_id: String) -> String:
	return str(SIG_CLASS.get(class_id, ""))

## The signature move id for a fighter ("" = none).
static func sig_kind(f: FighterState) -> String:
	return sig_of(f.class_id)

## The English (i18n key) name of a move id ("" = none).
static func sig_name(kind: String) -> String:
	return str(SIG_NAMES.get(kind, ""))

## May the signature skill be cast? (one charge, not charging and not on cooldown; a missing id = full)
static func sig_ready(f: FighterState) -> bool:
	return int(f.skill_n.get(SIG_ID, 1)) > 0 and not f.skill_cd.has(SIG_ID)

## 0..1: how far the signature charge is back (1 = ready; mirrors recover_ready_k).
static func sig_ready_k(f: FighterState) -> float:
	if sig_ready(f): return 1.0
	return clampf(1.0 - float(f.skill_cd.get(SIG_ID, 0.0)) / SIGNATURE_CD, 0.0, 1.0)

## Why the signature skill cannot be cast right now ("" = allowed): the touch context button and the tests read it.
## The order mirrors recover_block, plus an "off" for the overlay gate and the per-move requirements (air / ground /
## a firearm in hand) so the offer is only shown when the cast would really work.
static func sig_block(f: FighterState, sim: MatchSim) -> String:
	if f == null or sim == null: return "none"
	var c := sim.combat
	if not c.tuning_active(): return "off"
	if f.dead or f.elim: return "dead"
	if f.down_t > 0.0: return "down"
	if f.trap_t > 0.0: return "trapped"
	var kind := sig_kind(f)
	if kind == "": return "none"
	if not sig_ready(f): return "charge"
	match kind:
		"slam":
			if f.phys.grounded: return "grounded"      # the ground-pound needs air under the feet
		"fort":
			if not f.phys.grounded: return "air"        # "plants feet": ground only
		"tac":
			if not _tac_gun(f, c): return "gun"         # needs a firearm with a magazine in hand
	return ""

## Touch: should the context button offer the signature skill? Only while ready AND appropriate, so a Fortress Stance
## in the air or a Tac-Reload without a gun never takes the button (RELOAD / nothing shows instead).
static func sig_offer(f: FighterState, sim: MatchSim) -> bool:
	return sig_block(f, sim) == ""

## Combat.hit: is `v` inside a Fortress Stance window? Empty table in every untuned / parity match (one is_empty check).
static func fortress_active(c: Combat, v: FighterState) -> bool:
	if c.sig_fx.is_empty(): return false
	var fx: Variant = c.sig_fx.get(v)
	return fx is Dictionary and (fx as Dictionary).has("fort")

## Cast the class signature move. `yaw` is the caster's facing (PlayerControl passes face_yaw; the touch button writes
## the same "signature" tap). Returns false when refused; only a real cast spends the charge.
static func do_signature(f: FighterState, sim: MatchSim, yaw: float) -> bool:
	if sig_block(f, sim) != "": return false
	var kind := sig_kind(f)
	var c := sim.combat
	f.skill_n[SIG_ID] = 0
	f.skill_cd[SIG_ID] = SIGNATURE_CD
	match kind:
		"belly": _belly(c, f)
		"slam": _slam_arm(c, f)
		"vault": _vault(c, f, yaw)
		"fort": _fortress(c, f)
		"tac": _tac(c, f)
		"phase": _phase(c, f)
	if f.is_player:
		c.ev({"type": "toast", "text": TranslationServer.translate(sig_name(kind))})
	return true

## A firearm with a magazine in hand that Tac-Reload can refill.
static func _tac_gun(f: FighterState, c: Combat) -> bool:
	var s: Variant = f.current_slot()
	if s == null: return false
	var w := c.wdata(f.weapon)
	return str(w.get("type", "")) == "gun" and int(w.get("mag", 0)) > 0 and int(s["mag"]) >= 0

## The move's live window dictionary in Combat.sig_fx (created on first use; erased by place_at / dispose / _sig_tick).
static func _fx(c: Combat, f: FighterState) -> Dictionary:
	var fx: Variant = c.sig_fx.get(f)
	if fx is Dictionary: return fx
	var d := {}
	c.sig_fx[f] = d
	return d

## Can `f`'s signature move consider `e` a target? The same filters a kick uses (never self / dead / eliminated /
## friend / a bot that may not hit in this mode); ghosts are included so Combat.hit applies the online net rules.
static func _sigs_target(c: Combat, f: FighterState, e: FighterState) -> bool:
	return e != f and not e.dead and not e.elim and not c.is_friend(f, e) and c.bots_can_hit(f, e)

## One fixed step of the signature windows (Combat.timers via Skills.tick), before the charge regen. Only fighters with
## a live window are ticked; nothing here draws a random number.
static func _sig_tick(c: Combat, f: FighterState, dt: float) -> void:
	var fx: Variant = c.sig_fx.get(f)
	if not fx is Dictionary: return
	var d: Dictionary = fx
	if d.has("rate"):
		if not f.dead: f.cool -= dt * f.cls_rate * (SIG_RATE_MUL - 1.0)   # Tac-Reload: x1.5 fire rate
		var rt := float(d["rate"]) - dt
		if rt > 0.0: d["rate"] = rt
		else: d.erase("rate")
	if d.has("fort"):
		var ft := float(d["fort"]) - dt
		if ft > 0.0: d["fort"] = ft
		else: d.erase("fort")
	if d.has("phase"):
		var pt := float(d["phase"]) - dt
		if pt > 0.0: d["phase"] = pt
		else: d.erase("phase")
	if d.has("slam"):
		var st := float(d["slam"]) - dt
		if st <= 0.0:
			d.erase("slam")                     # fizzled: the dive never landed in time
		elif f.phys.grounded and not f.dead and f.down_t <= 0.0:
			d.erase("slam")
			_slam_land(c, f)
	if d.is_empty(): c.sig_fx.erase(f)

## Belly Bounce: everyone close (3 m, 2 m vertically) is knocked away and up; the caster bounces off the floor.
static func _belly(c: Combat, f: FighterState) -> void:
	var p := f.phys
	if p.grounded:
		p.vy = maxf(p.vy, SIG_BELLY_HOP)
		p.grounded = false
	for e: FighterState in c.fighters:
		if not _sigs_target(c, f, e): continue
		var dx := e.phys.px - p.px
		var dz := e.phys.pz - p.pz
		if dx * dx + dz * dz > SIG_BELLY_R * SIG_BELLY_R or absf(e.phys.py - p.py) > SIG_BELLY_DY: continue
		var l := sqrt(dx * dx + dz * dz)
		if l < 0.001:
			dx = sin(f.yaw); dz = cos(f.yaw); l = 1.0
		dx /= l; dz /= l
		c.hit(e, SIG_BELLY_DMG, dx, SIG_BELLY_UP, dz, SIG_BELLY_FORCE, false, f)
	c.ev({"type": "puff", "x": p.px, "y": p.py + 0.6, "z": p.pz, "n": 10, "spd": 4.5, "color": 0xffffff})
	c.ev({"type": "sfx", "name": "boing", "f": f})

## Seismic Slam, cast: an instant dive. The shockwave resolves in _sig_tick when the body reaches the floor.
static func _slam_arm(c: Combat, f: FighterState) -> void:
	_fx(c, f)["slam"] = SIG_SLAM_AROUND
	f.phys.vy = SIG_SLAM_DIVE
	f.phys.grounded = false
	c.ev({"type": "puff", "x": f.phys.px, "y": f.phys.py + 1.0, "z": f.phys.pz, "n": 6, "spd": 3.0, "color": 0xffffff})
	c.ev({"type": "sfx", "name": "swing", "f": f})

## Seismic Slam, landing: 3.8 m radius (2.5 m vertically) takes 18 dmg / 22 force and a deterministic flat topple.
static func _slam_land(c: Combat, f: FighterState) -> void:
	var p := f.phys
	for e: FighterState in c.fighters:
		if not _sigs_target(c, f, e): continue
		var dx := e.phys.px - p.px
		var dz := e.phys.pz - p.pz
		if dx * dx + dz * dz > SIG_SLAM_R * SIG_SLAM_R or absf(e.phys.py - p.py) > SIG_SLAM_DY: continue
		var l := sqrt(dx * dx + dz * dz)
		if l < 0.001:
			dx = sin(f.yaw); dz = cos(f.yaw); l = 1.0
		dx /= l; dz /= l
		if c.hit(e, SIG_SLAM_DMG, dx, SIG_SLAM_UP, dz, SIG_SLAM_FORCE, false, f)["applied"]:
			c.topple_flat(e, SIG_SLAM_DOWN)          # deterministic: no combat.rng draw
	c.ev({"type": "puff", "x": p.px, "y": p.py + 0.3, "z": p.pz, "n": 16, "spd": 6.0, "color": 0xffffff})
	c.ev({"type": "sfx", "name": "whack", "f": f})

## Vault Flip: a 1.5 s speed burst; with an opponent in the 2 m front cone the caster springs off their head.
static func _vault(c: Combat, f: FighterState, yaw: float) -> void:
	var p := f.phys
	f.spd_t = maxf(f.spd_t, SIG_VAULT_SPD)
	var fx_ := sin(yaw)
	var fz_ := cos(yaw)
	var bounced := false
	for e: FighterState in c.fighters:
		if not _sigs_target(c, f, e): continue
		var dx := e.phys.px - p.px
		var dz := e.phys.pz - p.pz
		var d := sqrt(dx * dx + dz * dz)
		if d > SIG_VAULT_R or d < 0.001 or absf(e.phys.py - p.py) > SIG_VAULT_DY: continue
		if (dx * fx_ + dz * fz_) / d < 0.0: continue         # behind: no springboard
		if c.hit(e, SIG_VAULT_DMG, dx / d, SIG_VAULT_UP, dz / d, SIG_VAULT_FORCE, false, f)["applied"]:
			bounced = true
	if bounced:
		p.vy = maxf(p.vy, SIG_VAULT_VY)
		p.grounded = false
	c.ev({"type": "puff", "kind": "dash", "x": p.px, "y": p.py + 0.4, "z": p.pz, "dx": fx_, "dz": fz_})
	c.ev({"type": "sfx", "name": "boing", "f": f})

## Fortress Stance: 1.5 s planted. Combat.hit adds no knockback / stun / launch for the window (damage still lands, so a
## K.O. hit still kills, just without the launch) and the same window is the tuned parry window (try_parry), so the next
## melee hit from the front is cancelled and the attacker staggered. A Heavy Swing breaks that parry (charged-melee
## rule) but still cannot launch the planted tank.
static func _fortress(c: Combat, f: FighterState) -> void:
	_fx(c, f)["fort"] = SIG_FORT_TIME
	f.parry_t = maxf(f.parry_t, SIG_FORT_TIME)
	c.ev({"type": "puff", "x": f.phys.px, "y": f.phys.py + 0.2, "z": f.phys.pz, "n": 8, "spd": 2.5, "color": 0xffffff})
	c.ev({"type": "sfx", "name": "clink", "f": f})

## Tac-Reload: the held firearm's magazine is instantly topped up from the reserve (the same min(mag, ammo) a finished
## reload uses) and the cooldown recovery is x1.5 for 1.5 s (Skills.tick adds the extra dt * cls_rate * 0.5).
static func _tac(c: Combat, f: FighterState) -> void:
	var s: Variant = f.current_slot()
	if s == null: return
	var w := c.wdata(f.weapon)
	c.cancel_reload(f, false)
	s["mag"] = mini(int(w.get("mag", 0)), int(s["ammo"]))
	_fx(c, f)["rate"] = SIG_RATE_TIME
	c.ev({"type": "puff", "x": f.phys.px, "y": f.phys.py + 1.1, "z": f.phys.pz, "n": 6, "spd": 2.5, "color": 0xffe08a})
	c.ev({"type": "sfx", "name": "mag", "f": f})

## Phase Shift: 0.6 s of invulnerability. Combat.hit returns early and the Net Gun's landNet skips invuln targets, so
## attacks, projectiles, nets and damaging props pass through; a fresh life (place_at) clears it like every temp state.
static func _phase(c: Combat, f: FighterState) -> void:
	_fx(c, f)["phase"] = SIG_PHASE_TIME     # marker only: lets place_at drop the i-frames on a fresh life
	f.invuln = maxf(f.invuln, SIG_PHASE_TIME)
	c.ev({"type": "puff", "x": f.phys.px, "y": f.phys.py + 1.0, "z": f.phys.pz, "n": 10, "spd": 3.0, "color": 0x9fd9ff})
	c.ev({"type": "sfx", "name": "dash", "f": f})
