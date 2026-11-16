class_name FighterState
extends RefCounted
## Gameplay state of one fighter as used by combat (the web game's Fighter fields, minus everything visual).
## Plain 64-bit floats so the combat port stays numerically identical to public/index.html.
## Position, velocity and `grounded` live in `phys` (FighterPhysics); everything else is here.
## Points that the animation produces (hand, arm direction, head, chest...) are inputs: the visual layer
## (or a test) writes them each frame, exactly like the web game reads them back from its meshes.

const BAT_N := 8                 ## points along a melee weapon (BAT_N in the web game)
const BAT_BASE := -0.25          ## where along the arm the first point sits

var phys := FighterPhysics.new()

# --- identity / rules ---
var id := 0                      ## index in Combat.fighters (any stable number)
var name := ""
var is_player := false           ## the local human (some rules differ: death timer, regen, assist)
var is_ghost := false            ## a remote player's fighter: hits are sent, not applied
var net_slot := -1               ## -1 = not online
var net_human := false           ## ghost owned by a human (routing of `h`), false = a bot owned by the host
var left := false                ## that remote player left the room
var home: Variant = null         ## practice-range dummy: [x, z] it comes back to, else null
var team := 0
var lives := 0
var elim := false
var ko := 0
var kill_t := -99.0
var gg_rung := 0                 ## Weapon Ladder rung (ModeRules.GG index)
var dash_n := 3                  ## ninja dash charges (ModeRules.DASH_MAX)
var dash_regen := 0.0
var dash_cd := 0.0
## Generic skill timers (logic/skills.gd), Godot-only and empty by default so the parity paths never see them.
## skill_n: charges left per skill id ("recover", "b:<weapon>" = a weapon's burst pool); a missing id = full.
## skill_cd: seconds until the next charge comes back, per skill id.
var skill_n := {}
var skill_cd := {}
var recover_air_t := 0.0         ## air recovery: boosted air control while > 0 (FighterPhysics counts it down)

# --- class (shared/classes.json) ---
var class_id := "wobbler"
var cls_hp := 1.0
var heal_frac := 0.6            ## share of max health a Health Pack gives this fighter (Arcade enemies get less, per difficulty)
var cls_dmg := 1.0
var cls_kb := 1.0
var cls_rate := 1.0
var cls_reload := 1.0
var cls_ammo := 1.0
var cls_head := 1.0              ## class `head` multiplier (shared/classes.json): head hit sphere, tuned matches only
var cls_size := 1.0              ## class `size` multiplier: chest/leg hit spheres, tuned matches only
## True when this fighter's match uses the balance overlay, i.e. `Combat.tuning_active()` (docs/DAMAGE.md "Tuned
## hitboxes"). Combat/MatchSim write it when a fighter is created and on every `place_at`; FighterState never reads the
## Combat class itself (no static dependency: a bare FighterState and the JS-parity paths stay on `tuned = false`).
var tuned := false
var dmg_scale := 1.0             ## bots deal less (DIFFS dmg / dummies 0.45)
var melee_force_mul := 1.0       ## outgoing melee force multiplier (Arcade difficulty; 1 = the weapon's own force)
var melee_topple_mul := 1.0      ## outgoing melee topple chance multiplier (Arcade difficulty)
var arcade_enemy := false        ## Arcade boss-rush enemy: never chases Rage / Shield crates (Pickups.bot_wants)

# --- health and status ---
var yaw := 0.0
var hp := 200.0
var dead := false
var death_t := 0.0
var fall_side := 1
var fell_t := false
var down_t := 0.0                ## knocked down
var getup_immune := 0.0
var stun := 0.0
var invuln := 0.0
var flash := 0.0
var shield_t := 0.0
var rage_t := 0.0
var big_t := 0.0                 ## Chaos "Giant" event: bigger hit spheres, double health, harder hits (ModeRules)
var spd_t := 0.0                 ## speed boost: x1.4 run speed (FighterPhysics)
## Elemental / physics statuses (Post-v0.4.0 Sprint 3.2, overlay only; docs/DAMAGE.md "Elemental and physics statuses").
## Combat.apply_status sets them from the weapon's weapon_tuning.json entry, Combat.timers counts them down and
## FighterPhysics reads them. The active multipliers keep their neutral 1.0 default, so a bare FighterState (the web
## game, the JS parity paths, online without net_zones) never changes a step: only tuning-gated code writes these.
var chill_t := 0.0               ## Snowball Cannon hit: >0 = chilled (refreshed by a new hit, never stacked)
var chill_speed := 1.0           ## move-speed multiplier while chill_t > 0 (overlay chill.speed = 0.68)
var chill_traction := 1.0        ## ground-grip multiplier while chill_t > 0 (overlay chill.traction = 0.3; 1 = normal grip)
var shock_t := 0.0               ## Live Wire hit: >0 = the short hit-stun interrupt just happened (spark event already sent)
var heavy_t := 0.0               ## Cement Bucket hit: >0 = heavier gravity and a weaker jump (walk speed unchanged)
var heavy_grav := 1.0            ## gravity multiplier while heavy_t > 0 (overlay heavy.grav = 1.4)
var heavy_jump := 1.0            ## jump-impulse multiplier while heavy_t > 0 (overlay heavy.jump = 0.65)
var trap_t := 0.0
var trap_net: RefCounted = null  ## the Weapons.TrapNet holding this fighter down (trapNet), null = none
var trap_x := 0.0                ## pinned here while trapped (trapX / trapZ)
var trap_z := 0.0
## Ledge cling (Godot-only overlay, docs/DAMAGE.md "Ledge cling and throwable rubble"; logic/ledge.gd). MatchSim creates
## the Ledge only while `Combat.tuning_active()`, and the fields stay at their inert defaults everywhere else, so the
## parity paths (web numbers, JS bots/physics references, online without net_zones) never enter a hang.
var hang := {}                   ## {} = not hanging; else {solid, x, z, nx, nz, top} (the grabbed ledge)
var hang_t := 0.0                ## s spent hanging (climb delay / pose)
var hang_cool := 0.0             ## s before another grab after a climb or a drop
var hang_drop := false           ## the controller asks to let go this step (CROUCH / a bot decision)
## Throwable rubble (Godot-only overlay, offline; logic/rubble.gd): 1 = this fighter holds a chunk (Rubble owns it).
var rubble := 0
var lie_side := 1                ## which side they lie on under a net (lieSide, visual)
var struggle := 0.0
var burn := 0.0
var burn_acc := 0.0
var burner: FighterState = null
var last_attacker: FighterState = null
var last_hit_time := -99.0

# --- teammate carry / throw, the Fastball Special (docs/DAMAGE.md): TEAM modes and Arcade co-op, tuned matches only ---
var carrying: FighterState = null    ## the teammate this fighter hoists overhead (the normal shove and weapons are off)
var carried_by: FighterState = null  ## the carrier holding this fighter overhead (pinned above it, not simulated normally)
var carry_limp := false              ## hoisted while DOWNED (an Arcade co-op seat): no body-slam, only the revive discount
var ball_t := -1.0                   ## a thrown body's flight time left, -1 = not flying (normal simulation)
var ball_owner: FighterState = null  ## who threw this body (the body-slam's attacker / K.O. credit), null = not thrown

# --- weapons / inventory ---
var weapon := "spatula"          ## "" = nothing (dead)
var slots: Array = [null, null, null]   ## each null or {key, ammo, mag (-1 = no magazine), pend}
var slot := -1                   ## -1 = the default spatula
var spatula_lock := false        ## the player chose the spatula on purpose: pickups do not pull a weapon into the hand (tuned matches)
var return_slot := -1            ## quick melee: slot to go back to (-1 = none)
var reloading := false
var rl_t := 0.0
var rl_slot := -1
var rl_dur := 0.0
var rl_shells := 0
var rl_loaded := 0
var cool := 0.0
var melee_cool := 0.0
var shove_cool := 0.0
var parry_t := 0.0               ## tuned offline combat: a shove briefly deflects a melee hit from the front
var kick_cool := 0.0
var pad_cool := 0.0
var climb := 0.0
var climb_back := 1.0
var last_shot_t := -9.0
var bloom := 0.0                 ## extra gun spread built up by sustained fire (tuned matches only)
var gun_kick := 0.0              ## recent gun hits taken: each stacked hit pushes less (tuned matches only)
var wob_x := 0.0                 ## random arm wobble added to the aim (tuned matches only)
var wob_y := 0.0
var wob_z := 0.0
var wob_t := 0.0                 ## time to the next wobble nudge
var hip_d := 0.0                 ## barrel tilt (hip-carried minigun)
var spin := 0.0                  ## minigun spin-up (playerControl p.spin)
var uzi_side := 0                ## dual Uzis: which gun fires next
var uzi_k: Array = [0.0, 0.0]    ## per-gun kick (visual)
var ads := 0.0                   ## scoped-in amount (cam.aim for the player)
var nocked := false
var grab_t := -1.0
var draw := 0.0                  ## bow draw 0..1
var flame_n := 0                 ## flamethrower shots (every third one makes the sound)

# --- melee swing ---
var swing := -1.0                ## -1 idle, 0..1.3 while swinging
var swing_yaw := 0.0
var swing_hit := {}              ## FighterState -> true: one swing hits a target once
var bat_valid := false
var bat_now := PackedFloat64Array()
var bat_prev := PackedFloat64Array()
var slam := false
var stab := false
var cyclone := false
var assist_on := false
## Charged heavy melee (docs/DAMAGE.md "Charged heavy melee"): PlayerControl's fire-key hold, Godot overlay only (offline,
## tuning_active). Both keep their defaults on the web, the JS parity paths and online, because only the tuning-gated
## input path writes `charge_t`; `melee_begin` always re-writes `heavy`, so a stale flag never reaches the next swing.
var charge_t := -1.0             ## seconds FIRE has been held for a melee charge, -1 = not charging
var heavy := false               ## this swing is a Heavy Swing: 1.45x damage / 1.5x force / breaks a parry (melee_sweep)
var face_yaw := 0.0
var kat_n := 0
var kat_t := -9.0

# --- kick ---
var kick_t := -1.0
var kick_yaw := 0.0
var kick_resolved := false
var kick_leaned := false

# --- thrown weapons ---
var throw_key := ""              ## pending throw (throwFn in the web game): weapon key, "" = none
var throw_t := 0.0
var thrown := false
var throw_hold := false
var knife_t := -1.0
var twirl_len := 1.4
var throw_pow := 0.3             ## trident: how far the throw was charged (throwPow)
var t_charge := -1.0             ## trident input state (tCharge): >= 0 charging, -1 idle, -2 waiting for release, -3 jab-or-throw
var t_pend := -1.0
var t_chg := 0.0                 ## last charge (the HUD bar / spin)
var boom: Object = null          ## Weapons.Boom in the air (p.boom): no second throw until it is back
var aim_pt: Array = []           ## the player's crosshair point (aimPoint), written by PlayerControl; homing throws read it on release

# --- points written by the animation (world space) ---
var hand_x := 0.0
var hand_y := 0.0
var hand_z := 0.0
var arm_x := 0.0                 ## arm direction (armDir), unit
var arm_y := 0.0
var arm_z := 1.0
var aim_x := 0.0                 ## where the arm wants to point (aimTarget)
var aim_y := 0.0
var aim_z := 1.0
var hand2_x := 0.0               ## off hand (armL.localToWorld(0, -0.8, 0)): the shuriken's second star; hand2_ok = written
var hand2_y := 0.0
var hand2_z := 0.0
var hand2_ok := false
var shoulder_x := 0.0
var shoulder_y := 0.0
var shoulder_z := 0.0
var head_x := 0.0
var head_y := 0.0
var head_z := 0.0
var chest_x := 0.0
var chest_y := 0.0
var chest_z := 0.0
var leg_x := 0.0                 ## legPos: the web game sets it to the feet + 0.5 in applyPose (see update_leg)
var leg_y := 0.0
var leg_z := 0.0

# --- per-match stats (newSt) ---
var st := {}

func _init() -> void:
	bat_now.resize(BAT_N * 3)
	bat_prev.resize(BAT_N * 3)
	st = new_stats()

static func new_stats() -> Dictionary:
	return {"shots": 0, "hits": 0, "falls": 0, "dmg": 0.0, "taken": 0.0, "deaths": 0, "streak": 0, "bestStreak": 0,
		"multi": 0, "bestMulti": 0, "lastKo": -99.0, "weps": {}, "heads": 0}

## Class multipliers from one shared/classes.json entry.
func set_class(cid: String, c: Dictionary) -> void:
	class_id = cid
	cls_hp = float(c.get("hp", 1.0)); cls_dmg = float(c.get("dmg", 1.0)); cls_kb = float(c.get("kb", 1.0))
	cls_rate = float(c.get("rate", 1.0)); cls_reload = float(c.get("reload", 1.0)); cls_ammo = float(c.get("ammo", 1.0))
	cls_head = float(c.get("head", 1.0)); cls_size = float(c.get("size", 1.0))
	phys.speed_mul = float(c.get("spd", 1.0)); phys.accel_mul = float(c.get("acc", 1.0))
	phys.air_mul = float(c.get("air", 1.0)); phys.jump_mul = float(c.get("jump", 1.0))

## Hit spheres [cx, cy, cz, r, is_head] (Fighter.spheres). Head, chest and legs are the points written by the animation.
## Classic (tuned = false): head 0.4, chest 0.62, legs 0.5; x1.5 for giants. Tuned matches scale the spheres by the
## class (`head` on the head, `size` on chest and legs, clamped) so a Scamp's head is a bigger target and a Bulwark's is a
## smaller one; the giant x1.5 applies on top. Untuned values stay bit-identical to the web game.
func spheres(giant: bool) -> Array:
	var k := 1.5 if (giant or big_t > 0.0) else 1.0
	if tuned:
		var hk := clampf(cls_head, 0.85, 1.25) * k
		var sk := clampf(cls_size, 0.88, 1.15) * k
		return [[head_x, head_y, head_z, 0.4 * hk, true], [chest_x, chest_y, chest_z, 0.62 * sk, false],
			[leg_x, leg_y, leg_z, 0.5 * sk, false]]
	return [[head_x, head_y, head_z, 0.4 * k, true], [chest_x, chest_y, chest_z, 0.62 * k, false],
		[leg_x, leg_y, leg_z, 0.5 * k, false]]

## Leg sphere from the feet (call it where the animation writes the other points).
func update_leg() -> void:
	leg_x = phys.px; leg_y = phys.py + 0.5; leg_z = phys.pz

func current_slot() -> Variant:
	return slots[slot] if slot >= 0 else null

## Ammo of the held slot (the `ammo` getter).
func get_ammo() -> int:
	var s: Variant = current_slot()
	return int(s["ammo"]) if s != null else 0   # the Air Blower's fractional ammo is read from the slot directly

func set_ammo(v: int) -> void:
	var s: Variant = current_slot()
	if s != null:
		s["ammo"] = v

## What the visual layer needs (docs/GODOT_ARCH.md FighterState contract).
func to_visual() -> Dictionary:
	return {"pos": Vector3(phys.px, phys.py, phys.pz), "vel": Vector3(phys.vx, phys.vy, phys.vz), "yaw": yaw,
		"aim": Vector3(aim_x, aim_y, aim_z), "grounded": phys.grounded, "crouch": phys.crouch_k, "hp": hp, "dead": dead,
		"down_t": down_t, "weapon": weapon, "swing": swing, "kick_t": kick_t, "invuln": invuln > 0.0 and not dead,
		"flash": flash, "class_id": class_id}
