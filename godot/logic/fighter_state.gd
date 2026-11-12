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

# --- class (shared/classes.json) ---
var class_id := "wobbler"
var cls_hp := 1.0
var cls_dmg := 1.0
var cls_kb := 1.0
var cls_rate := 1.0
var cls_reload := 1.0
var cls_ammo := 1.0
var dmg_scale := 1.0             ## bots deal less (DIFFS dmg / dummies 0.45)

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
var spd_t := 0.0                 ## speed boost: x1.4 run speed (FighterPhysics)
var dash_air_t := 0.0            ## Pillars dash: air steering stays at 3 while > 0 (FighterPhysics counts it down)
var trap_t := 0.0
var struggle := 0.0
var burn := 0.0
var burn_acc := 0.0
var burner: FighterState = null
var last_attacker: FighterState = null
var last_hit_time := -99.0

# --- weapons / inventory ---
var weapon := "spatula"          ## "" = nothing (dead)
var slots: Array = [null, null, null]   ## each null or {key, ammo, mag (-1 = no magazine), pend}
var slot := -1                   ## -1 = the default spatula
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
var kick_cool := 0.0
var pad_cool := 0.0
var climb := 0.0
var climb_back := 1.0
var last_shot_t := -9.0
var hip_d := 0.0                 ## barrel tilt (hip-carried minigun)
var spin := 0.0                  ## minigun spin-up (playerControl p.spin)
var uzi_side := 0                ## dual Uzis: which gun fires next
var uzi_k: Array = [0.0, 0.0]    ## per-gun kick (visual)
var ads := 0.0                   ## scoped-in amount (cam.aim for the player)
var nocked := false
var grab_t := -1.0
var draw := 0.0

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
	phys.speed_mul = float(c.get("spd", 1.0)); phys.accel_mul = float(c.get("acc", 1.0))
	phys.air_mul = float(c.get("air", 1.0)); phys.jump_mul = float(c.get("jump", 1.0))

## Hit spheres [cx, cy, cz, r, is_head] (Fighter.spheres). Head, chest and legs are the points written by the animation.
func spheres(giant: bool) -> Array:
	var k := 1.5 if giant else 1.0
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
	return int(s["ammo"]) if s != null else 0

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
