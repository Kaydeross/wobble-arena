class_name Combat
extends RefCounted
## Combat rules ported 1:1 from the web game (public/index.html, CODEMAP section 8): Fighter.hit, topple, kick,
## shove, melee swing + sweep, timers, respawn, inventory/pickup/reload. Guns and thrown weapons are in Weapons.
## Pure logic over FighterState objects: no nodes. Everything the visual layer should react to (lean/head kicks,
## arm shoves, sounds, puffs, K.O., net messages) is appended to `events` (drain it every frame) and `hit()`
## also returns its own result Dictionary.
## Random numbers come from `rng` (CombatRng), consumed in exactly the order the web game calls Math.random,
## so tools/test-combat.js can compare against the real JavaScript.

const BOT_RESPAWN := 5.0
const PLAYER_RESPAWN := 3.0
const ContentData := preload("res://autoload/content.gd")   # the ONE parsed-JSON cache (docs/GODOT_ARCH.md "JSON cache")

# --- content (shared/*.json) ---
var weapons_data := {}
var classes := {}
var modes := {}

# --- match rules (the web game's cfg + MODES[cfg.mode]) ---
var hp_setting := 200.0          ## cfg.hp
var kb_setting := 1.0            ## cfg.kb (0 counts as 1, like `cfg.kb || 1`)
var mode_id := "classic"
var mode := {}
var teams := 0                   ## cfg.teams (0 = free for all)
var ffa := true                  ## cfg.ffa
var brawl := true                ## cfg.behav == 'brawl'
var lives_mode := 0              ## cfg.lives
var inf := false                 ## cfg.inf: endless ammo
var giant := false               ## giantOn()
var auto_switch := false         ## settings.autoSwitch
var spawns: Array = []           ## MAPS[map].spawns ([x, z] pairs)
var spawn_y := 4.0               ## MAPS[map].spawnY || 4
var solids: Array = []           ## FighterPhysics.solids_from_map()
## Optional destructible environment mode (docs/DESTRUCTIBLE.md): set by MatchSim only when the mode is on. The weapon
## hooks in weapons.gd are behind `if destruct != null`, so normal matches never take the extra path.
var destruct: Destruct = null
var grav_setting := 1.0          ## cfg.grav (Moon Drift < 0.3: lobbed things float too, projG)

# --- body-part damage (shared/damage.json, docs/DAMAGE.md) ---
const DEFAULT_DAMAGE := {"tables": {
		"classic": {"head": 1.0, "torso": 1.0, "arms": 1.0, "legs": 1.0, "meleeHead": false},
		"zones": {"head": 1.5, "torso": 1.0, "arms": 0.85, "legs": 0.75, "meleeHead": true}},
	"weaponHead": {"gun": 2.0, "thrown": 1.8, "arrow": 1.8}, "geometry": {"armSide": 0.34, "legsBelow": 0.45}}
var damage: Dictionary = DEFAULT_DAMAGE
## "classic" = the web game (only headshots get a bonus: bit-identical to the JS); "zones" = the per-part table.
## A bare Combat is classic (the parity tests); MatchSim switches offline matches to "zones".
var damage_rule := "classic"
## Online matches stay classic (web clients compute their own shots that way) unless every client knows the table.
var net_zones := false

# --- aim modes (Settings `aim_mode`, docs/AIM.md) ---
## Normal (default): aim assist on (PlayerControl pulls the crosshair point toward a near enemy), standard damage.
## Advanced: no aim assist, and the LOCAL player's own hits deal +25% damage OFFLINE only: online the shooter's game
## decides every hit, so a damage buff here would break cross-play parity with the web game (and bots/ghosts keep the
## shared numbers).
## PlayerControl.think() writes this from the Settings row every local-player step, so the row applies live; tests and
## the JS parity fixtures just leave it at "normal" (a bare Combat never reads Settings, so the shared numbers are
## deterministic: docs/AIM.md).
const ADVANCED_DAMAGE := 1.25
var aim_mode := "normal"

## The Settings autoload's `aim_mode` right now ("normal" | "advanced"), for PlayerControl to copy into `aim_mode`.
static func settings_aim_mode() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	var st: Node = tree.root.get_node_or_null("Settings") if tree != null and tree.root != null else null
	return str(st.get_value("aim_mode", "normal")) if st != null else "normal"

## Advanced aim mode: no aim assist, +25% damage for the local player offline (docs/AIM.md).
func aim_advanced() -> bool:
	return aim_mode == "advanced"

# --- balance overlay (res://data/extra/weapon_tuning.json, docs/DAMAGE.md "Balance and cooldowns") ---
## Weapon key -> the weapons.json entry with the overlay merged in (empty = no overlay: a bare Combat, the parity tests).
## Used only while tuning_active(), the same gate as the zones rule, so web peers and the JS references keep the
## shared numbers.
var tuned_weapons := {}
## Crate weight overrides (drops.json `base` keys), same gate.
var tuned_drops := {}
## Per victim: [knockback velocity a flame contact has already added, combat.time of that hit]. Overlay only.
var flame_push := {}
## s without a flame hit that starts a new contact (and therefore a fresh knockback budget) on a target.
const FLAME_RESET := 0.4

# --- Arcade co-op friendly fire (docs/CONSTRUCTION_DLC.md "Unit D", owner decision: off by default) ---
## false = a player seat's weapon, projectile or explosion cannot hurt the other seat. The crew and enemy fire are not
## seats, so they still hurt everyone. Only ArcadeManager sets this and `pve_seats`; every other mode keeps the default
## (true = no extra rule, the web game's behaviour).
var friendly_fire := true
## The player seats of the current Arcade co-op run (FighterState). Crew/enemies are never in it. Empty = no seat rule.
var pve_seats: Array = []
## True when this match is a TWO-seat Arcade co-op run (the Fastball Special is allowed there; solo Arcade never carries).
## ArcadeManager writes it next to `friendly_fire`/`pve_seats`: a plain field, so Combat has no static DLC dependency.
var arcade_coop := false

# --- Wobble Reactions (Post-v0.4.0 Sprint 2.3, tuning only; docs/DAMAGE.md "Wobble Reactions") ---
## FighterState -> {dx, dz, t, pins, struck}: the fighters currently sliding across the floor as a bowling ball (Combat-owned:
## FighterState belongs to another lane). Cleared by place_at on a fresh life and dispose at the match end; empty in every
## untuned match, so the parity paths never see it.
var bowl_slides := {}
## Optional owner of the deflectable falling hazards (the Arcade's load_test crates). Duck-typed and WEAK: the DLC stage
## layer registers itself with `deflectables()` / `deflect_crate(id, dx, dz)`, so the pure logic never imports the DLC class
## and no ownership cycle is created. Null in every non-Arcade match (the redirect paths then cost one null check).
var hazard_source: WeakRef = null

# --- class signature skills (Post-v0.4.0 Sprint 3.3, tuning only; docs/DAMAGE.md "Class signature skills") ---
## FighterState -> its live signature move windows: {"fort": s, "rate": s, "slam": s}. Skills owns the rules and
## counts these down (Skills.tick); Combat only stores the table because the hit() knockback gate must read it. Cleared
## by place_at on a fresh life and by dispose at the match end; empty in every untuned match, so the parity paths never
## see it (the hit() gate then costs one is_empty check).
var sig_fx := {}

# --- net (filled by the net layer) ---
var net_started := false
var net_host := false
var net_apply := false           ## true while applying an `h` that arrived over the network

var time := 0.0                  ## simTime: advance it by the sim step
var fighters: Array = []         ## every FighterState in the match
var rng := CombatRng.new()
var events: Array = []
var weapons: Weapons
var rules: ModeRules             ## game-mode rules: K.O. limit, lives, ladder, dash, shrink (logic/mode_rules.gd)

func _init() -> void:
	weapons = Weapons.new(self)
	rules = ModeRules.new(self)
	set_mode("classic")

## Drop the fighter-to-fighter references (last attacker, burner, swing targets, projectiles) so nothing leaks
## when a match ends. Call before throwing the Combat away.
func dispose() -> void:
	for f: FighterState in fighters:
		f.last_attacker = null; f.burner = null; f.swing_hit = {}; f.trap_net = null
		f.carrying = null; f.carried_by = null; f.ball_owner = null; f.ball_t = -1.0
	weapons.clear()
	rules.winner = null
	fighters.clear()
	events.clear()
	flame_push.clear()
	pve_seats.clear()
	arcade_coop = false
	bowl_slides.clear()
	hazard_source = null
	sig_fx.clear()

## Parsed content is immutable between releases. Every caller receives a deep copy so one match can merge or alter its
## own tuning without changing later matches; the parse cache lives in the Content script (Sprint 4.2: one decode per
## file per process, shared by the autoload, MatchSim and the plain logic classes; reload() invalidates it).
static func read_json(path: String) -> Variant:
	return ContentData.read_json(path)

## Load weapons/classes/modes from a folder holding copies of shared/*.json (the Content autoload will call this later).
func load_content(dir: String = "res://data") -> void:
	weapons_data = ExtraWeapons.merge(read_json(dir.path_join("weapons.json")))   # + Godot-only weapons (res://data/extra/construction)
	classes = ExtraClasses.merge(read_json(dir.path_join("classes.json")))   # + the Godot-only classes (res://data/extra)
	modes = ModeRules.merge_extra(read_json(dir.path_join("modes.json")))   # + the Godot-only modes (res://data/extra)
	var dp := dir.path_join("damage.json")
	var dd: Variant = read_json(dp) if FileAccess.file_exists(dp) else null
	damage = dd if dd is Dictionary and dd.has("tables") else DEFAULT_DAMAGE
	set_mode(mode_id)

func set_mode(id: String) -> void:
	mode_id = id
	mode = modes.get(id, {})

func wdata(key: String) -> Dictionary:
	if not tuned_weapons.is_empty() and zones_active():
		var tw: Variant = tuned_weapons.get(key)
		if tw != null: return tw
	return weapons_data.get(key, {})

## Merge a weapon_tuning.json overlay ({weapons: {key: {field: value}}, drops: {key: weight}, swingStyles: {style:
## {param: value}}}) over the loaded weapons. Takes effect only while tuning_active().
## A MELEE weapon that names a `swingStyle` gets that archetype's parameters resolved into its own `swingStyleDef`
## dictionary (a distinct key: shared weapon records already use `style` for guns, e.g. "punch" / "flame"), so wdata()
## returns a ready dictionary and the per-frame melee paths only read values (no merge/allocation per call). A
## per-weapon `swingStyleDef` object overrides individual archetype parameters (a data edit without code edits).
func apply_tuning(t: Variant) -> void:
	tuned_weapons = {}; tuned_drops = {}
	if not t is Dictionary: return
	var styles: Dictionary = t.get("swingStyles", {})
	var ws: Dictionary = t.get("weapons", {})
	for k: String in ws:
		if not weapons_data.has(k): continue
		var m: Dictionary = (weapons_data[k] as Dictionary).duplicate(true)
		m.merge(ws[k], true)
		var sid := str(m.get("swingStyle", ""))
		if sid != "" and str(m.get("type", "")) == "melee" and styles.get(sid) is Dictionary:
			var st: Dictionary = (styles[sid] as Dictionary).duplicate()
			var own: Variant = m.get("swingStyleDef")
			if own is Dictionary: st.merge(own, true)   # a per-weapon override wins
			m["swingStyleDef"] = st
		tuned_weapons[k] = m
	tuned_drops = (t.get("drops", {}) as Dictionary).duplicate()

## True when the attacker holds a flame-style weapon (`flame`, the Construction's Angle Grinder): the only hits that use the
## overlay's per-stream knockback budget.
func _flame_style(a: FighterState) -> bool:
	return a.weapon != "" and str(wdata(a.weapon).get("style", "")) == "flame"

## True when the balance overlay is in use: one was loaded and the zones gate is open (offline / every client knows it).
func tuning_active() -> bool:
	return not tuned_weapons.is_empty() and zones_active()

func is_friend(a: FighterState, b: FighterState) -> bool:
	return teams != 0 and a != null and b != null and a != b and a.team == b.team

## Arcade co-op: true when `a` and `b` are two player seats and the run has friendly fire off. A seat's weapon, projectile
## or explosion reaches Combat.hit() with the seat as `attacker`, so this single rule covers every damage path. Crew and
## enemy fire have an attacker that is not a seat, so it still hurts both seats.
func seat_mates(a: FighterState, b: FighterState) -> bool:
	return not friendly_fire and a != null and b != null and a != b and pve_seats.has(a) and pve_seats.has(b)

func max_hp(f: FighterState) -> float:
	return hp_setting * (2.0 if giant or f.big_t > 0.0 else 1.0) * f.cls_hp

## Bots only hurt each other in a free-for-all brawl.
## Arcade co-op (docs/ARCADE_COOP_PLAN.md §4.4): a co-op seat is a ghost on the host (net_human), so the crew must be able
## to hit it like a player. ffa is false only in the Arcade's PvE mode, so the other modes are untouched.
func bots_can_hit(a: FighterState, e: FighterState) -> bool:
	return a.is_player or e.is_player or e.net_human or (ffa and brawl)

func ev(e: Dictionary) -> void:
	events.append(e)

func kick_lean(f: FighterState, a: float, b: float) -> void:
	ev({"type": "lean", "f": f, "a": a, "b": b})

func kick_head(f: FighterState, a: float, b: float) -> void:
	ev({"type": "head", "f": f, "a": a, "b": b})

func push_arm(f: FighterState, x: float, y: float, z: float) -> void:
	ev({"type": "arm", "f": f, "x": x, "y": y, "z": z})

# ============================== damage ==============================

## True when the per-part table applies: the rule asks for it and we are offline (or every client knows the table).
func zones_active() -> bool:
	return damage_rule != "classic" and (not net_started or net_zones)

## The multiplier row in use: {head, torso, arms, legs, meleeHead}.
func zone_table() -> Dictionary:
	var t: Dictionary = damage.get("tables", DEFAULT_DAMAGE["tables"])
	var key := damage_rule if zones_active() else "classic"
	return t.get(key, DEFAULT_DAMAGE["tables"][key] if DEFAULT_DAMAGE["tables"].has(key) else DEFAULT_DAMAGE["tables"]["classic"])

## A weapon family's own headshot multiplier ("gun" -> weapon headMul or 2.0, "thrown"/"arrow" -> 1.8), or -1 = use the table.
func weapon_head(kind: String, w: Dictionary = {}) -> float:
	if kind == "gun" and w.get("headMul", 0): return float(w["headMul"])
	var wh: Dictionary = damage.get("weaponHead", DEFAULT_DAMAGE["weaponHead"])
	return float(wh[kind]) if wh.has(kind) else -1.0

## Which body part of `v` the point (x, y, z) is on. `on_head` = the head hit sphere was the one touched (that decides
## "head", exactly like the old head flag). Otherwise: below the chest by more than legsBelow -> legs; further than
## armSide from the chest centre sideways (along the victim's right axis) -> arms; else torso. Scaled for giants.
func body_part(v: FighterState, x: float, y: float, z: float, on_head: bool) -> String:
	if on_head: return "head"
	var g: Dictionary = damage.get("geometry", DEFAULT_DAMAGE["geometry"])
	var k := 1.5 if giant else 1.0
	if y < v.chest_y - float(g.get("legsBelow", 0.45)) * k: return "legs"
	var side := absf(-(x - v.chest_x) * cos(v.yaw) + (z - v.chest_z) * sin(v.yaw))
	if side > float(g.get("armSide", 0.34)) * k: return "arms"
	return "torso"

## Damage multiplier for a part. `own_head` (> 0) is the weapon's own headshot value, which wins over the table's head.
## Classic: every non-head part is 1.0, so the damage is bit-identical to the web game.
func part_mul(part: String, own_head: float = -1.0) -> float:
	if part == "head" and own_head > 0.0: return own_head
	return float(zone_table().get(part, 1.0))

## The `zone` argument of hit(): which part, its multiplier and where it was struck (for the damage number and flash).
static func zone_info(part: String, mul: float, x: float, y: float, z: float) -> Dictionary:
	return {"part": part, "mul": mul, "x": x, "y": y, "z": z}

## Fighter.hit: damage, knockback, stun, K.O. Returns {applied, dmg, ko, light, ...}; false-y `applied` = no effect.
## `dmg` already includes the body-part multiplier; `zone` (zone_info(), optional) only labels the damage number /
## hit flash with the part, its bonus % and the struck point. Splash, flame and the glove pass none (whole body).
func hit(v: FighterState, dmg: float, dx: float, dy: float, dz: float, force: float, head: bool, attacker: FighterState,
		zone: Dictionary = {}) -> Dictionary:
	var r := {"applied": false, "ko": false}
	# Arcade co-op friendly fire: check before the ghost branch so a seat's hit on the other (remote) seat is never
	# relayed to its owner in the first place (offline and online use the same rule).
	if seat_mates(attacker, v):
		return r
	var part: String = zone.get("part", "head" if head else "")
	var pct := js_round((float(zone.get("mul", 1.0)) - 1.0) * 100.0) if zone.has("mul") else 0
	if v.is_ghost:                     # another player's wobbler: the shooter's game decides the hit and tells theirs
		if attacker == null or attacker.is_ghost or attacker.net_slot < 0 or v.dead or v.left or v.invuln > 0.0 or not net_started:
			return r
		if attacker.is_player:
			ev({"type": "dmg_number", "f": v, "dmg": dmg, "head": head, "part": part, "pct": pct}); attacker.st["hits"] += 1
		v.flash = 0.12
		# The hit goes to the ghost's owner (net_human) and names the fighter that dealt it. The Arcade's crew are
		# host-owned bots with a net slot, so a crew hit on a co-op ghost seat reaches its owner through this same path
		# (docs/ARCADE_COOP_PLAN.md §4.4). A host-run bot's ghost is told slot 0, exactly as before.
		var to_seat := v.net_slot if v.net_human else 0
		var msg := NetSnapshot.encode_hit(to_seat, v.net_slot, attacker.net_slot, dmg, dx, dy, dz, force, head)
		ev({"type": "net", "msg": msg})
		r["applied"] = true; r["sent"] = msg
		return r
	if attacker != null and attacker.is_ghost and not net_apply:
		return r                       # other players' shots only look real here; their damage arrives as `h`
	if v.dead or v.invuln > 0.0:
		return r
	if attacker != null and is_friend(attacker, v):
		return r
	if mode.has("dmgMul"):
		dmg *= float(mode["dmgMul"])
	if giant and attacker != null and attacker.weapon == "mammoth":
		dmg *= 0.65
	if attacker != null and attacker != v:
		dmg *= attacker.cls_dmg
	if attacker != null and attacker != v and attacker.rage_t > 0.0:
		dmg *= 1.5
	if attacker != null and attacker != v and attacker.big_t > 0.0:    # Chaos giant (Godot-only)
		dmg *= 1.5
	# Aim modes (docs/AIM.md): Advanced pays +25% damage for the local player's own hits, OFFLINE only. Bots, ghosts,
	# other players' relayed hits and every online match keep the shared numbers (the shooter decides the damage it
	# sends, so a local buff online would make the same shot hurt differently depending on who fired it).
	if attacker != null and attacker != v and attacker.is_player and not attacker.is_ghost and not net_started and aim_advanced():
		dmg *= ADVANCED_DAMAGE
	if v.shield_t > 0.0:
		dmg *= 0.5
	if v.down_t > 0.0 and not (v.trap_t > 0.0):
		dmg *= 0.5
	if attacker != null and attacker.is_player and attacker != v:
		ev({"type": "dmg_number", "f": v, "dmg": dmg, "head": head, "part": part, "pct": pct})
	v.last_attacker = attacker; v.last_hit_time = time
	if attacker != null and attacker != v:
		var real := maxf(0.0, minf(dmg, v.hp))
		attacker.st["dmg"] += real; attacker.st["hits"] += 1; v.st["taken"] += real
		if head:
			attacker.st["heads"] += 1
	v.hp -= dmg; v.flash = 0.12
	if v.is_player:
		ev({"type": "hurt", "f": v, "amount": 0.35 + dmg / 90.0})
	var light := force < 8.0           # bullets, knives: a small shove, no stun
	var kf := 0.4 if light else 1.0
	var fk := (kb_setting if kb_setting != 0.0 else 1.0) * 0.8 * float(mode.get("kbMul", 1.0) if mode.get("kbMul", 0) else 1.0) * v.cls_kb * (0.5 if v.big_t > 0.0 else 1.0)
	# Balance overlay, flame only (docs/DAMAGE.md "Flamethrower knockback"): a flame hits on every damage tick, so its
	# per-tick push used to add up to a constant shove that could carry a target who cannot walk against it. Keep the
	# tuned per-tick push, but cap the TOTAL knockback velocity one contact may add to a target at `maxForce` (m/s): the
	# first ticks shove, then the stream stops pushing until it has been off that target for FLAME_RESET s (a new contact).
	# The web game / parity tests never reach this (tuning_active() is false there).
	if tuning_active() and attacker != null and attacker != v and force > 0.0 and _flame_style(attacker):
		var fw := wdata(attacker.weapon)
		var rec: Array = flame_push.get(v, [0.0, -1e9])
		var spent := float(rec[0]) if time - float(rec[1]) <= FLAME_RESET else 0.0
		var cap := float(fw.get("maxForce", force))
		var want := force * kf * fk
		var got := minf(want, maxf(0.0, cap - spent))
		if want > 0.0:
			force *= got / want
		flame_push[v] = [spent + got, time]
	var p := v.phys
	# Fortress Stance (class signature skill, tuning only): a planted tank takes the damage but no velocity, no stun and
	# no launch at all. The gate is one is_empty() on the signature table in every untuned / parity match, so the classic
	# knockback below is bit-identical there.
	if not Skills.fortress_active(self, v):
		p.vx += dx * force * kf * fk
		p.vz += dz * force * kf * fk
		if not light:
			p.vy += (maxf(dy * force, 0.0) + force * 0.18) * fk
			p.grounded = false
			v.stun = maxf(v.stun, 0.55 if force >= 9.0 else clampf_js(0.04 + force * 0.025, 0.06, 0.4))
	var s := sin(v.yaw)
	var c := cos(v.yaw)
	var d_f := dx * s + dz * c
	var d_r := -dx * c + dz * s
	kick_lean(v, -d_f * force * 0.22, -d_r * force * 0.22)
	kick_head(v, -d_f * force * 0.5, -d_r * force * 0.5)
	var sa := force * 0.3
	push_arm(v, dx * sa, dy * sa, dz * sa)
	r["applied"] = true; r["dmg"] = dmg; r["light"] = light
	var he := {"type": "hit", "f": v, "attacker": attacker, "dmg": dmg, "head": head, "force": force, "part": part}
	if zone.has("x"): he["x"] = zone["x"]; he["y"] = zone["y"]; he["z"] = zone["z"]
	ev(he)
	if v.hp <= 0.0:
		v.st["streak"] = 0; v.st["multi"] = 0; v.st["deaths"] += 1
		v.dead = true
		v.death_t = 1.2 if v.home != null else (PLAYER_RESPAWN if v.is_player else BOT_RESPAWN)
		v.fall_side = -1 if rng.next() < 0.5 else 1
		v.down_t = 0.0; v.kick_t = -1.0
		if p.py > -1.0:
			# Fortress Stance: the K.O. keeps its burst VFX but a planted tank is never launched by the fatal hit either.
			if not Skills.fortress_active(self, v): p.vy = maxf(p.vy, 6.5)
			ev({"type": "ko_burst", "f": v})
		clear_inventory(v)
		set_weapon(v, "")
		rules.on_down(v, false)                  # Capture the Flag: the flag drops where they fell
		if attacker != null and attacker != v:
			add_ko(attacker, v)
		else:
			ev({"type": "ko", "killer": null, "victim": v, "weapon": ""})
		if rules.one_life(): rules.eliminate(v, true)    # Sudden Death: out at once
		if net_started and v.net_slot >= 0 and not v.is_ghost and (v.is_player or net_host):
			var msg := NetSnapshot.encode_ko(attacker.net_slot if attacker != null and attacker.net_slot >= 0 else -1, v.net_slot)
			ev({"type": "net", "msg": msg})
		r["ko"] = true
	return r

## addKo: K.O. credit and streaks, the Weapon Ladder step and the K.O. limit (ModeRules). The kill feed is the world's
## job (it reads the "ko" event).
func add_ko(killer: FighterState, victim: FighterState) -> void:
	if victim != null and is_friend(killer, victim):
		return
	killer.ko += 1; killer.kill_t = time
	if mode_id == "gungame": rules.gg_advance(killer)
	var k := killer.st
	k["streak"] += 1; k["bestStreak"] = maxi(k["bestStreak"], k["streak"])
	k["multi"] = k["multi"] + 1 if time - float(k["lastKo"]) < 6.0 else 1
	k["lastKo"] = time; k["bestMulti"] = maxi(k["bestMulti"], k["multi"])
	var wn: String = wdata(killer.weapon).get("name", "Spatula") if killer.weapon != "" else "Spatula"
	k["weps"][wn] = int(k["weps"].get(wn, 0)) + 1
	ev({"type": "ko", "killer": killer, "victim": victim, "weapon": wn})
	rules.check_limit(killer)

## The knockdown state both topple() and the signature moves' topple_flat() set: alive, not already down and not inside
## the get-up immunity; a swing / kick / charge in progress is cancelled and the body falls. No random number here.
func _topple_state(f: FighterState, dur: float) -> bool:
	if f.dead or f.down_t > 0.0 or f.getup_immune > 0.0:
		return false
	f.down_t = minf(dur, 1.6)
	f.swing = -1.0; f.kick_t = -1.0; f.stun = maxf(f.stun, 0.35)
	if f.return_slot >= 0:
		var r := f.return_slot
		f.return_slot = -1
		equip_slot(f, r if f.slots[r] != null else -1)
	return true

## Fall over (never longer than 1.6 s); a moment of "can't be tripped" follows getting up.
func topple(f: FighterState, dur: float, msg: String = "") -> bool:
	if not _topple_state(f, dur):
		return false
	f.fall_side = -1 if rng.next() < 0.5 else 1
	var a := rng.range_f(-3, 3)
	var b := rng.range_f(-3, 3)
	kick_head(f, a, b)
	var ax := rng.range_f(-3, 3)
	var az := rng.range_f(-3, 3)
	push_arm(f, ax, 0.0, az)
	ev({"type": "sfx", "name": "boing", "f": f})
	if f.is_player:
		ev({"type": "toast", "text": msg if msg != "" else "Whoops! You fell over"})
	return true

## Deterministic knockdown for the tuned class signature skills (Seismic Slam's shockwave): exactly the state topple()
## sets, but a fixed fall side and fixed shove angles, so it never advances combat.rng (the signature test asserts the
## RNG state is unchanged). The web game / parity paths never call this.
func topple_flat(f: FighterState, dur: float) -> bool:
	if not _topple_state(f, dur):
		return false
	f.fall_side = 1
	kick_head(f, 2.0, 0.0)
	push_arm(f, 1.0, 0.0, 0.0)
	ev({"type": "sfx", "name": "boing", "f": f})
	return true

# ============================== elemental / physics statuses ==============================

## Post-v0.4.0 Sprint 3.2 (docs/DAMAGE.md "Elemental and physics statuses"): a hit from a weapon whose weapon_tuning.json
## entry carries a status sub-dictionary tags the fighter. The status TABLE is the overlay data, not code: `chill
## {time, speed, traction}` on the Snowball Cannon, `shock {time}` on the Live Wire and `heavy {time, grav, jump}` on the
## Cement Bucket. Every branch below is behind tuning_active(), nothing here draws a random number, and re-applying only
## refreshes the timer (maxf): there is exactly one copy of each multiplier, on exactly the matching weapon's hit.
## The literals are the defaults for an overlay entry that omits a value.
const CHILL_TIME := 3.0
const CHILL_SPEED := 0.68
const CHILL_TRACTION := 0.3
const SHOCK_TIME := 0.35
const HEAVY_TIME := 4.0
const HEAVY_GRAV := 1.4
const HEAVY_JUMP := 0.65

## Apply the status of weapon data `w` (already overlay-merged by wdata()) to `v`, the fighter that weapon just hit.
## Called from the melee hit path (melee_sweep) and from Weapons.step_balls for the rolling ball weapons, i.e. once per
## applied hit and never per tick. The sub-dicts are is-Dictionary-guarded: a gun keeps its String `style` key and our
## `chill` / `shock` / `heavy` names never collide with the swing style (`swingStyleDef`) or any shared weapon field.
func apply_status(v: FighterState, w: Dictionary) -> void:
	if not tuning_active() or v == null or v.dead: return
	var ch: Variant = w.get("chill")
	if ch is Dictionary:
		var cd: Dictionary = ch
		v.chill_t = maxf(v.chill_t, float(cd.get("time", CHILL_TIME)))
		v.chill_speed = float(cd.get("speed", CHILL_SPEED))
		v.chill_traction = float(cd.get("traction", CHILL_TRACTION))
	var sh: Variant = w.get("shock")
	if sh is Dictionary:
		var sd: Dictionary = sh
		var t := float(sd.get("time", SHOCK_TIME))
		v.shock_t = maxf(v.shock_t, t)
		v.stun = maxf(v.stun, t)          # the short hit-stun; hit()'s force stagger may already be longer
		_interrupt(v)                     # stop a swing / kick / throw wind-up / bow draw / charge
		ev({"type": "spark", "f": v, "x": v.chest_x, "y": v.chest_y, "z": v.chest_z})
	var hv: Variant = w.get("heavy")
	if hv is Dictionary:
		var hd: Dictionary = hv
		v.heavy_t = maxf(v.heavy_t, float(hd.get("time", HEAVY_TIME)))
		v.heavy_grav = float(hd.get("grav", HEAVY_GRAV))
		v.heavy_jump = float(hd.get("jump", HEAVY_JUMP))

## The shock's hit-stun interrupt: whatever the victim was winding up is cancelled (the player / bot has to press again).
func _interrupt(v: FighterState) -> void:
	v.swing = -1.0; v.bat_valid = false; v.slam = false; v.stab = false; v.cyclone = false; v.assist_on = false
	v.kick_t = -1.0
	v.throw_key = ""; v.throw_hold = false
	v.t_charge = -1.0
	v.draw = 0.0; v.nocked = false
	v.charge_t = -1.0; v.heavy = false

# ============================== timers / respawn ==============================

## Fighter.timers: per-step countdowns. Not ported: emotes (visual only).
func timers(f: FighterState, dt: float) -> void:
	rules.dash_tick(f, dt)
	Skills.tick(self, f, dt)
	tick_reload(f, dt)
	if f.spd_t > 0.0: f.spd_t -= dt
	if f.rage_t > 0.0: f.rage_t -= dt
	if f.shield_t > 0.0: f.shield_t -= dt
	# Sprint 3.2 statuses: only tuning-gated code ever sets these, so the three countdowns are inert (0.0) in every
	# web / parity match. Clamped at 0 so a `> 0.0` read in FighterPhysics turns off cleanly.
	if f.chill_t > 0.0: f.chill_t = maxf(0.0, f.chill_t - dt)
	if f.shock_t > 0.0: f.shock_t = maxf(0.0, f.shock_t - dt)
	if f.heavy_t > 0.0: f.heavy_t = maxf(0.0, f.heavy_t - dt)
	f.cool -= dt * f.cls_rate; f.melee_cool -= dt; f.shove_cool -= dt; f.parry_t -= dt; f.kick_cool -= dt; f.pad_cool -= dt
	if f.invuln > 0.0: f.invuln -= dt
	if f.flash > 0.0: f.flash -= dt
	if f.trap_t > 0.0:                 # stuck under a net
		f.trap_t -= dt; f.cool = maxf(f.cool, 0.1); f.melee_cool = maxf(f.melee_cool, 0.1); f.swing = -1.0; f.stun = maxf(f.stun, 0.1)
		f.struggle -= dt
		if f.struggle <= 0.0:
			f.struggle = 0.2
			var a := rng.range_f(-1.4, 1.4)
			var b := rng.range_f(-1.4, 1.4)
			kick_lean(f, a, b)
		if f.trap_t <= 0.0:
			f.trap_t = 0.0; f.trap_net = null
	if not bowl_slides.is_empty() and bowl_slides.has(f): _bowl_tick(f, dt)   # Wobble Reactions: the bowling slide
	if f.burn > 0.0 and not f.dead:    # on fire
		f.burn -= dt; f.burn_acc += dt
		if f.burn_acc >= 0.4:
			f.burn_acc = 0.0
			hit(f, 2.2, 0.0, 1.0, 0.0, 0.0, false, f.burner)
		if rng.next() < dt * 22.0:
			var fx := f.phys.px + rng.range_f(-0.3, 0.3)
			var fy := f.phys.py + rng.range_f(0.3, 1.8)
			var fz := f.phys.pz + rng.range_f(-0.3, 0.3)
			ev({"type": "flame", "x": fx, "y": fy, "z": fz, "life": rng.range_f(0.3, 0.5)})
	if f.knife_t >= 0.0:
		f.knife_t += dt
		if f.knife_t > f.twirl_len: f.knife_t = -1.0
	if f.throw_key != "":              # thrown weapons: wind-up, release, follow-through
		if f.dead or f.down_t > 0.0:
			f.throw_key = ""; f.throw_hold = false
		else:
			f.throw_t += dt
			if f.throw_hold: f.throw_t = minf(f.throw_t, 0.15)
			var jav := f.weapon == "trident"
			var key := f.throw_key
			if not f.thrown and not f.throw_hold and f.throw_t >= (0.26 if jav else 0.11):
				f.thrown = true; weapons.release(f, key)
			if f.throw_t >= (0.52 if jav else 0.3): f.throw_key = ""
	if f.getup_immune > 0.0: f.getup_immune = maxf(0.0, f.getup_immune - dt)
	if f.down_t > 0.0:
		f.down_t -= dt
		if f.down_t <= 0.0:
			f.down_t = 0.0; f.getup_immune = 1.0
	if f.dead and not f.is_ghost:
		f.death_t -= dt
		if f.death_t <= 0.0: respawn(f)
	if f.kick_t >= 0.0: kick_step(f, dt)
	if f.is_player and not f.dead and f.hp < max_hp(f) * 0.5 and time - f.last_hit_time > 6.0:
		f.hp = minf(max_hp(f) * 0.5, f.hp + 4.0 * max_hp(f) / 100.0 * dt)  # slow, capped at 50%: hiding can not full-heal

func respawn(f: FighterState) -> void:
	if f.elim:
		return
	f.fell_t = false
	if lives_mode:
		f.lives -= 1
		if f.lives <= 0:
			rules.eliminate(f, true)
			return
	var s: Array = spawns[int(floor(rng.next() * spawns.size()))] if spawns.size() > 0 else [0.0, 0.0]
	var sz := rules.shrink_spot()                 # shrinking arenas: a spot inside the floor that is left
	if sz.size() > 0: s = sz
	if f.home != null: s = f.home
	place_at(f, float(s[0]), float(s[1]), 0.01 if f.home != null else spawn_y)
	f.invuln = 0.3 if f.home != null else 2.5     # spawn protection
	ev({"type": "respawn", "f": f})

## placeAt: teleport and reset for a fresh life (also the match start).
func place_at(f: FighterState, x: float, z: float, y: float = 0.01) -> void:
	f.tuned = tuning_active()         # class-scaled hit spheres only with the balance overlay (docs/DAMAGE.md)
	f.phys.place(x, y, z)
	f.hp = max_hp(f); f.dead = false; f.burn = 0.0
	f.down_t = 0.0; f.getup_immune = 0.0; f.kick_t = -1.0; f.swing = -1.0; f.stun = 0.0; f.trap_t = 0.0; f.trap_net = null; f.parry_t = 0.0
	f.charge_t = -1.0; f.heavy = false   # a fresh life starts with no charged heavy melee in hand
	f.chill_t = 0.0; f.shock_t = 0.0; f.heavy_t = 0.0   # Sprint 3.2 statuses do not survive a fresh life
	# Phase Shift's i-frames are the one signature window written into an existing FighterState field, so a fresh life
	# must not inherit them. place_at never touches invuln otherwise (the web game's placeAt keeps it: the combat parity
	# fixture compares it per op), and this branch only runs when the tuned move was actually used (sig_fx is empty in
	# every parity path).
	if sig_fx.has(f) and (sig_fx[f] as Dictionary).has("phase"): f.invuln = 0.0
	# Fastball Special: a fresh life lets go of (and is let go by) its carried teammate and forgets a throw in flight; the
	# carrier's link is cut on BOTH sides so a revived body never stays pinned to a carrier that moved on.
	if f.carrying != null: f.carrying.carried_by = null
	if f.carried_by != null: f.carried_by.carrying = null
	f.carrying = null; f.carried_by = null; f.carry_limp = false; f.ball_t = -1.0; f.ball_owner = null
	bowl_slides.erase(f)              # a fresh life is not still sliding as a bowling ball
	flame_push.erase(f)               # a fresh life does not inherit the last one's spent flame budget
	sig_fx.erase(f)                   # ... nor a signature move window (Fortress Stance / Tac-Reload / a dive in flight)
	Skills.reset(f)
	clear_inventory(f); set_weapon(f, "spatula")
	var start: Variant = mode.get("start")
	if start is String and start != "": pickup(f, start)
	if mode_id == "gungame": rules.gg_give(f)

# ============================== inventory ==============================

func set_weapon(f: FighterState, key: String) -> void:
	f.weapon = key
	f.swing = -1.0; f.bat_valid = false; f.nocked = false; f.grab_t = -1.0; f.draw = 0.0
	f.charge_t = -1.0; f.heavy = false   # swapping weapons cancels a charge in progress (docs/DAMAGE.md)
	ev({"type": "weapon", "f": f, "key": key})

func equip_slot(f: FighterState, i: int) -> bool:
	f.return_slot = -1
	if i >= 0 and f.slots[i] == null:
		return false
	if f.reloading and i != f.slot:
		cancel_reload(f, true)         # swapped away mid-reload: it finishes when you come back
	var was := f.weapon
	f.slot = i
	f.spatula_lock = i < 0 and f.is_player
	set_weapon(f, f.slots[i]["key"] if i >= 0 else "spatula")
	if i >= 0: auto_reload(f)
	var scd := float(wdata(f.weapon).get("swapCd", 0.0))   # tuning: heavy weapons need a moment to draw (no swap-cancel)
	if scd > 0.0 and f.weapon != was: f.cool = maxf(f.cool, scd)
	return true

func clear_inventory(f: FighterState) -> void:
	cancel_reload(f, false)
	f.slots = [null, null, null]; f.slot = -1; f.return_slot = -1; f.spatula_lock = false

## Should a freshly picked-up weapon go straight into the hand?
func auto_eq(f: FighterState, i: int) -> bool:
	if f.spatula_lock and f.slot < 0 and tuning_active(): return false   # you picked the spatula: it stays in hand
	if not f.is_player or auto_switch or f.slot < 0 or f.slot == i:
		return true
	var cur: Variant = f.slots[f.slot]
	return cur == null or float(cur["ammo"]) <= 0.0   # float: the Air Blower drains fractional ammo

func pickup(f: FighterState, key: String) -> void:
	var w := wdata(key)
	var wa := float(w.get("ammo", 0))
	var add := js_round(wa * f.cls_ammo)
	var i := -1
	for n in 3:
		if f.slots[n] != null and f.slots[n]["key"] == key: i = n; break
	if i >= 0:                         # already carrying it: the ammo goes on top
		f.slots[i]["ammo"] += add
		if f.slot != i and auto_eq(f, i): equip_slot(f, i)
		ev({"type": "pickup", "f": f, "key": key, "slot": i, "ammo_only": true})
		return
	for n in 3:
		if f.slots[n] == null: i = n; break
	if i < 0:                          # full: swap out the current one, or the emptiest
		if f.slot >= 0: i = f.slot
		else:
			var best := 2
			var best_frac := 9.0
			for n in 3:
				var fr := float(f.slots[n]["ammo"]) / float(wdata(f.slots[n]["key"]).get("ammo", 0))
				if fr < best_frac: best_frac = fr; best = n
			i = best
	var mag := -1
	if w.get("mag", 0): mag = mini(int(w["mag"]), int(wa))
	f.slots[i] = {"key": key, "ammo": add, "mag": mag, "pend": false}
	if auto_eq(f, i): equip_slot(f, i)
	ev({"type": "pickup", "f": f, "key": key, "slot": i, "ammo_only": false})

## The held weapon ran out (or a melee weapon broke): next weapon, or back to the spatula.
func drop_slot(f: FighterState) -> void:
	if f.slot < 0 or f.slots[f.slot] == null:
		return
	cancel_reload(f, false)
	f.slots[f.slot] = null
	var nxt := -1
	for n in 3:
		if f.slots[n] != null: nxt = n; break
	equip_slot(f, nxt)
	f.spatula_lock = false         # the weapon ran out; that was not a choice

## useAmmo: one shot spent (the Weapon Ladder never runs out of spare ammo).
func use_ammo(f: FighterState) -> void:
	f.st["shots"] += 1
	Skills.burst_spend(self, f)
	if inf:
		return
	if f.slot >= 0:
		var sl: Variant = f.slots[f.slot]
		if not mode.get("ladder", false): f.set_ammo(f.get_ammo() - 1)
		if sl != null and int(sl["mag"]) > 0: sl["mag"] = int(sl["mag"]) - 1
		if f.get_ammo() <= 0: drop_slot(f)
		elif sl != null and int(sl["mag"]) == 0 and wdata(sl["key"]).get("mag", 0): start_reload(f)

# --- reloading: a gun holds `mag` rounds; `ammo` is everything you carry ---

func auto_reload(f: FighterState) -> void:
	var s: Variant = f.current_slot()
	if s == null or f.reloading or inf:
		return
	var w := wdata(s["key"])
	if w.get("mag", 0) and int(s["mag"]) >= 0 and int(s["ammo"]) > 0 and (s["pend"] or int(s["mag"]) <= 0):
		start_reload(f)

func start_reload(f: FighterState) -> bool:
	if f.reloading or inf or f.slot < 0 or f.dead:
		return false
	var s: Variant = f.slots[f.slot]
	if s == null: return false
	var w := wdata(s["key"])
	if not w.get("mag", 0) or int(s["mag"]) < 0: return false
	var cap := mini(int(w["mag"]), int(s["ammo"]))
	if int(s["mag"]) >= cap: return false
	f.reloading = true; f.rl_t = 0.0; f.rl_slot = f.slot; f.rl_loaded = 0
	s["pend"] = false
	if w.get("rtype", "") == "shell":
		f.rl_shells = cap - int(s["mag"]); f.rl_dur = 0.35 + f.rl_shells * float(w["perRound"]) + 0.3
	else:
		f.rl_dur = float(w["reload"]) * f.cls_reload
	ev({"type": "reload", "f": f})
	return true

func cancel_reload(f: FighterState, keep_pending: bool) -> void:
	if not f.reloading:
		return
	var s: Variant = f.slots[f.rl_slot] if f.rl_slot >= 0 else null
	f.reloading = false
	if s != null and keep_pending and int(s["mag"]) >= 0: s["pend"] = true

func finish_reload(f: FighterState) -> void:
	var s: Variant = f.slots[f.rl_slot] if f.rl_slot >= 0 else null
	f.reloading = false
	if s != null:
		s["mag"] = mini(int(wdata(s["key"])["mag"]), int(s["ammo"])); s["pend"] = false
	f.cool = maxf(f.cool, 0.1)

func tick_reload(f: FighterState, dt: float) -> void:
	if not f.reloading:
		return
	var s: Variant = f.current_slot()
	var w := wdata(s["key"]) if s != null else {}
	if s == null or f.slot != f.rl_slot or w.is_empty() or not w.get("mag", 0) or f.dead:
		cancel_reload(f, true); return
	if f.down_t > 0.0 or f.trap_t > 0.0:
		return                         # the reload waits while you're on the floor
	f.rl_t += dt
	if w.get("rtype", "") == "shell":
		while f.rl_loaded < f.rl_shells and f.rl_t >= 0.35 + (f.rl_loaded + 0.65) * float(w["perRound"]):
			f.rl_loaded += 1; s["mag"] = mini(int(w["mag"]), int(s["mag"]) + 1)
	if f.rl_t >= f.rl_dur: finish_reload(f)

# ============================== kick and shove ==============================

func start_kick(f: FighterState, yaw: float) -> void:
	f.kick_t = 0.0; f.kick_yaw = yaw; f.kick_resolved = false; f.kick_leaned = false

## doKick (the input side): cooldown 1 s.
func do_kick(f: FighterState, yaw: float) -> bool:
	if f.dead or f.down_t > 0.0 or f.kick_t >= 0.0 or f.kick_cool > 0.0:
		return false
	f.kick_cool = 1.0; f.face_yaw = yaw
	start_kick(f, yaw)
	return true

func kick_step(f: FighterState, dt: float) -> void:
	if f.dead or f.down_t > 0.0:
		f.kick_t = -1.0; return
	f.kick_t += dt / 0.55
	var t := f.kick_t
	if t >= 0.3 and not f.kick_leaned:
		f.kick_leaned = true
		kick_lean(f, -3.2, 0.0); kick_head(f, -2.5, 0.0)
		ev({"type": "sfx", "name": "kick", "f": f})
	if t >= 0.3 and t <= 0.6 and not f.kick_resolved:
		var fx_ := sin(f.kick_yaw)
		var fz_ := cos(f.kick_yaw)
		var cx := f.phys.px + fx_ * 0.95
		var cy := f.phys.py + 0.7
		var cz := f.phys.pz + fz_ * 0.95
		var hit_any := false
		for e: FighterState in fighters:
			if e == f or e.dead: continue
			if is_friend(f, e): continue
			if not bots_can_hit(f, e): continue
			var touch := false
			for sp: Array in e.spheres(giant):
				var ddx: float = sp[0] - cx
				var ddy: float = sp[1] - cy
				var ddz: float = sp[2] - cz
				var rr: float = sp[3] + 0.5
				if ddx * ddx + ddy * ddy + ddz * ddz < rr * rr: touch = true; break
			if not touch: continue
			var d := norm3(fx_, 0.45, fz_)
			if not hit(e, 5.0, d[0], d[1], d[2], 9.0, false, f)["applied"]: continue
			topple(e, 1.3)
			ev({"type": "sfx", "name": "whack", "f": e})
			hit_any = true
		if hit_any:
			f.kick_resolved = true
			if rng.next() < 0.12: topple(f, 0.9, "Your own kick tripped you! Classic")
	if t > 0.6 and not f.kick_resolved:   # kicked thin air: easy to lose your balance
		f.kick_resolved = true
		var chance := 0.5 + (0.0 if f.phys.grounded else 0.3)
		if rng.next() < chance:
			f.phys.vx += sin(f.kick_yaw) * 2.5; f.phys.vz += cos(f.kick_yaw) * 2.5
			topple(f, 1.4, "Whoops! Missed and fell over")
	if t >= 1.0: f.kick_t = -1.0

## shove (the player's push): everyone close in front gets a big light shove.
func shove(f: FighterState, yaw: float) -> void:
	if f.shove_cool > 0.0 or f.dead or f.down_t > 0.0:
		return
	f.shove_cool = 0.9
	if tuning_active(): f.parry_t = 0.22
	var fx_ := sin(yaw)
	var fz_ := cos(yaw)
	kick_lean(f, -2.5, 0.0)
	for e: FighterState in fighters:
		if e == f or e.dead: continue
		var dx := e.phys.px - f.phys.px
		var dz := e.phys.pz - f.phys.pz
		var d := sqrt(dx * dx + dz * dz)
		if d < 2.6 and d > 0.001 and (dx * fx_ + dz * fz_) / d > 0.3:
			var n := norm3(dx / d, 0.2, dz / d)
			hit(e, 2.0, n[0], n[1], n[2], 11.0, false, f)

## A tuned offline shove is also a short parry. Only a melee hit from roughly in front counts; the attacker's swing is
## cancelled and they are staggered away. The web/classic path never reaches this (tuning_active is false).
## A Heavy Swing cannot be parried ("Charged heavy melee"): melee_sweep strips the victim's parry_t instead of deflecting.
func try_parry(v: FighterState, attacker: FighterState) -> bool:
	if not tuning_active() or v == null or attacker == null or v.parry_t <= 0.0 or v.dead or attacker.dead: return false
	if attacker.heavy: return false
	var dx := attacker.phys.px - v.phys.px
	var dz := attacker.phys.pz - v.phys.pz
	var d := sqrt(dx * dx + dz * dz)
	if d <= 0.001: return false
	var facing := (dx * sin(v.face_yaw) + dz * cos(v.face_yaw)) / d
	if facing < 0.2: return false
	v.parry_t = 0.0
	attacker.swing = -1.0; attacker.cool = maxf(attacker.cool, 0.45); attacker.stun = maxf(attacker.stun, 0.65)
	attacker.phys.vx += dx / d * 3.5; attacker.phys.vz += dz / d * 3.5
	kick_lean(attacker, 2.8, 0.0)
	ev({"type": "parry", "f": v, "attacker": attacker, "x": v.phys.px, "y": v.phys.py + 1.4, "z": v.phys.pz})
	return true

# ============================== teammate carry / throw (Fastball Special) ==============================
## Post-v0.4.0 Sprint 2.2 (docs/DAMAGE.md "Teammate carry/throw"): in TEAM modes and Arcade co-op a player hoists a teammate
## overhead with a shove (empty-handed, within CARRY_RANGE), walks at 85 % and launches the body with the fire key. A
## LIVING body slams the first enemy it touches (35 dmg / 20 force); a DOWNED Arcade co-op seat landing on the floor shaves
## 2 s off its revive countdown through the Arcade run object (sim meta "arcade_run", has_method: no static DLC dependency).
## Every branch is gated on `carry_active()` — the balance overlay PLUS a team mode or a two-seat Arcade run — so the web
## numbers, the JS parity paths and online without `net_zones` are untouched, and nothing here draws a random number.

const CARRY_MODES := ["t2", "t3", "t4", "tdm", "ctf"]   ## the TEAM modes that get the Fastball Special (Chaos/duel: no)
const CARRY_RANGE := 1.4           ## m: how close a liftable teammate must be (feet distance)
const CARRY_SPEED_MUL := 0.85      ## the carrier walks at this share of its walk speed while hoisting a teammate
const CARRY_HOLD_HEIGHT := 2.3     ## m above the carrier's feet where the hoisted body is pinned (overhead)
const THROW_SPEED := 18.0          ## m/s forward when the carried teammate is launched
const THROW_UP := 6.0              ## m/s upward arc of the launch
const SLAM_DMG := 35.0             ## a thrown LIVING teammate's body-slam damage, to the FIRST enemy it hits
const SLAM_FORCE := 20.0           ## ... and the body-slam's knockback force
const BALL_TIME := 3.0             ## s a thrown body is tracked for the slam / the downed landing
const CARRY_REVIVE_SHAVE := 2.0    ## s shaved off a downed Arcade co-op seat's revive when the body lands on the floor

## True when the Fastball Special exists in this match: the Godot balance overlay is active AND the match is a TEAM mode
## or a two-seat Arcade co-op run. FFA, classic, solo Arcade and every match on the shared web numbers: false, and the
## whole feature costs one boolean (no state, no RNG, the parity paths stay bit-identical).
func carry_active() -> bool:
	return tuning_active() and (arcade_coop or (teams != 0 and CARRY_MODES.has(mode_id)))

## A TEAMmate: the same team in a CARRY_MODES match, or one of the two player seats of an Arcade co-op run. Never an
## enemy, never in a free-for-all, and never in solo Arcade (no second seat to hoist). A remote player's ghost is not a
## carry candidate (its owner's game moves it: carrying needs a protocol), so online co-op only lights up with `net_zones`.
func carry_mate(f: FighterState, e: FighterState) -> bool:
	if f == null or e == null or f == e: return false
	if teams != 0 and CARRY_MODES.has(mode_id): return f.team == e.team and f.team >= 0
	return arcade_coop and pve_seats.has(f) and pve_seats.has(e)

## "Empty-handed" is the default Spatula: no picked-up weapon in a hand slot (the same condition quick melee reads to
## decide whether it needs a return slot). A carried teammate is not a weapon: the hand stays free to hoist one.
func empty_handed(f: FighterState) -> bool:
	return f.slot < 0

## A teammate the shove can hoist: alive, or a DOWNED Arcade co-op seat (the seat system marks it dead/elim); not already
## carried and not in the air from a throw.
func carryable(f: FighterState, e: FighterState) -> bool:
	if not carry_active() or e == null or e == f or e.left or e.is_ghost: return false
	if e.carried_by != null or e.ball_t >= 0.0: return false
	if not carry_mate(f, e): return false
	if e.dead: return arcade_coop and pve_seats.has(e)
	return not e.elim

## The nearest carryable teammate within CARRY_RANGE of f's feet (null = none). The lift itself only checks the distance.
func carry_target(f: FighterState, _yaw: float = 0.0) -> FighterState:
	if not carry_active(): return null
	var best: FighterState = null
	var bd := CARRY_RANGE * CARRY_RANGE
	for e: FighterState in fighters:
		if not carryable(f, e): continue
		var dx := e.phys.px - f.phys.px
		var dy := e.phys.py - f.phys.py
		var dz := e.phys.pz - f.phys.pz
		var d2 := dx * dx + dy * dy + dz * dz
		if d2 <= bd: bd = d2; best = e
	return best

## The shove input's carry branch: hoist the nearest carryable teammate overhead. Returns true when the shove was spent
## on the lift (the normal shove is then suppressed); false keeps the classic shove path byte-identical.
func try_carry(f: FighterState) -> bool:
	if not carry_active() or f == null or f.dead or f.down_t > 0.0 or f.trap_t > 0.0: return false
	if f.carrying != null or f.carried_by != null or f.ball_t >= 0.0: return false
	if f.shove_cool > 0.0 or not empty_handed(f): return false
	var e := carry_target(f)
	if e == null: return false
	f.carrying = e; e.carried_by = f; e.carry_limp = e.dead
	f.shove_cool = 0.9                 # the lift is a shove: the same cooldown as one
	kick_lean(f, -2.5, 0.0)
	ev({"type": "sfx", "name": "swing", "f": f})
	return true

## The fire input while carrying: launch the teammate FORWARD (the carrier's facing, THROW_SPEED) with a THROW_UP arc.
## Returns true when a throw happened (the caller fires no weapon that step).
func throw_carry(f: FighterState) -> bool:
	if f == null or f.carrying == null: return false
	var a := f.carrying
	f.carrying = null; a.carried_by = null
	var s := sin(f.face_yaw)
	var c := cos(f.face_yaw)
	var p := a.phys
	p.place(p.px, p.py, p.pz)          # clears any ladder/velocity state, keeps the pinned spot
	p.vx = s * THROW_SPEED; p.vz = c * THROW_SPEED; p.vy = THROW_UP; p.grounded = false
	a.ball_t = BALL_TIME; a.ball_owner = f
	ev({"type": "sfx", "name": "swing", "f": f})
	return true

## Let go of a hoisted teammate without throwing (carrier knocked down / killed, or the body revived by something else).
func drop_carried(f: FighterState) -> void:
	var a := f.carrying
	f.carrying = null
	if a != null: a.carried_by = null

## Pin the hoisted body overhead and integrate thrown bodies: one call per FIXED step, from MatchSim.step after physics
## and after the Net Gun pinning, so the pinned position is the one the views read (the trap-pinning pattern). `run` is the
## Arcade run object from the sim meta "arcade_run" (null in a team match): the downed-seat revive discount is called
## through it with has_method, so nothing here has a static DLC dependency. Nothing in this function draws a random number.
func carry_tick(dt: float, run: Variant = null) -> void:
	if not carry_active(): return
	for f: FighterState in fighters:
		if f.carrying != null:
			var a := f.carrying
			if a == null or a.carried_by != f or f.dead or f.down_t > 0.0 or f.elim:
				drop_carried(f)
			elif a.dead and not a.carry_limp:   # a living body died in the carrier's hands: it goes limp
				drop_carried(f)
			else:                              # pinned above the carrier exactly like the Net Gun pins its victim
				var s := sin(f.yaw)
				var c := cos(f.yaw)
				a.phys.place(f.phys.px + s * 0.15, f.phys.py + CARRY_HOLD_HEIGHT, f.phys.pz + c * 0.15)
				a.yaw = f.yaw
				a.face_yaw = f.yaw
		if f.ball_t >= 0.0:
			_ball_step(f, dt, run)

## One step of a thrown body (see carry_tick). A LIVING teammate's body slams the FIRST enemy it touches; a thrown DOWNED
## Arcade co-op seat that lands on the floor shaves its revive countdown; after that the body is simulated normally again.
func _ball_step(f: FighterState, dt: float, run: Variant) -> void:
	f.ball_t -= dt
	if f.ball_t <= 0.0 or f.phys.grounded:      # flight over (landed or out of time): the landing is the only payout
		var landed := f.phys.grounded
		var limp := f.carry_limp
		f.ball_t = -1.0; f.carry_limp = false
		f.ball_owner = null
		if landed and limp and run != null and run.has_method("fastball_revive"):
			run.call("fastball_revive", f, CARRY_REVIVE_SHAVE)   # a downed co-op seat: 2 s off its revive countdown
		return
	if f.dead or f.carry_limp: return           # a limp / killed body cannot body-slam: only its landing pays out
	for e: FighterState in fighters:
		if e == f or e.dead or e.elim or e.is_ghost: continue
		if carry_mate(f, e): continue           # never a teammate
		if not _body_touches(f, e): continue
		var owner := f.ball_owner
		var d := norm3(f.phys.vx, f.phys.vy, f.phys.vz)
		f.ball_t = -1.0; f.ball_owner = null
		if not hit(e, SLAM_DMG, d[0], d[1], d[2], SLAM_FORCE, false, owner)["applied"]: return
		ev({"type": "toast", "text": tr("FASTBALL SPECIAL!")})
		return

## The flying body overlaps `e`'s hit spheres: the body is a 2.3 m vertical segment at its current x/z (at 18 m/s one step
## is 0.15 m, so a sphere test cannot tunnel), and the sphere radius is padded by the body's own radius.
func _body_touches(f: FighterState, e: FighterState) -> bool:
	var p := f.phys
	var lo := p.py
	var hi := p.py + 2.3
	for sp: Array in e.spheres(giant):
		var dx: float = p.px - float(sp[0])
		var dz: float = p.pz - float(sp[2])
		var dy: float = float(sp[1]) - clampf(float(sp[1]), lo, hi)
		var rr: float = float(sp[3]) + 0.8
		if dx * dx + dy * dy + dz * dz < rr * rr: return true
	return false

# ============================== wobble reactions (Sprint 2.3, tuning only) ==============================

## Post-v0.4.0 Sprint 2.3 (docs/DAMAGE.md "Wobble Reactions"): two emergent physics combo reactions.
##   Human Bowling Ball: a fighter pinned by a Net Gun trap that takes a HEAVY melee swing (the weapon table's `force`
##   >= HEAVY_FORCE) is released from the net and slides at BOWL_SPEED; every other fighter the body runs over takes
##   BOWL_PIN_DMG / BOWL_PIN_FORCE once ("STRIKE!"). The bowling fighter is never hurt by its own pins.
##   Mid-Air Redirect: a melee swing or a high-force shot swats a falling load_test crate or an explosive projectile in
##   flight down the attacker's aim (Weapons.deflect_near / deflect_ray; the crates come from StageEvents through
##   `hazard_source`). The vertical speed is kept, never boosted, and no damage is multiplied.
## Every branch is gated on tuning_active() (the web numbers and the parity suites never see any of it) and NOTHING here
## draws a random number: the presentation layer builds its juice from the "reaction" event with the FxSystem's own RNG.

const BOWL_SPEED := 26.0          ## m/s the released net victim slides across the floor
const BOWL_TIME := 0.9            ## s the slide lasts (the speed is re-asserted on every fixed step, friction included)
const BOWL_PIN_DMG := 30.0        ## damage each fighter the sliding body runs over takes (once per launch)
const BOWL_PIN_FORCE := 18.0      ## ... and the bowling-pin knockback force
const BOWL_PIN_R := 1.1           ## m horizontal reach of the rolling body (2 x FighterPhysics.R plus a margin)
const HEAVY_FORCE := 16.0         ## the weapon table's `force` a melee swing needs to launch a netted fighter

## True when a melee weapon is heavy enough to launch a netted fighter: the weapon table's `force` (before any class,
## slam or cyclone multiplier, exactly the value melee_sweep multiplies).
static func heavy_melee(w: Dictionary) -> bool:
	return float(w.get("force", 0.0)) >= HEAVY_FORCE

## The falling hazard crates the stage layer currently exposes for a mid-air redirect ({id, x, y, z, r}); empty outside the
## Arcade and while the balance overlay is off. `hazard_source` is duck-typed so Combat has no static DLC dependency.
func hazard_deflectables() -> Array:
	if not tuning_active() or hazard_source == null: return []
	var src: Variant = hazard_source.get_ref()
	if src == null or not src.has_method("deflectables"): return []
	return src.deflectables()

## Redirect hazard crate `id` down the horizontal unit direction (dx, dz); the stage layer owns the crate's motion.
func deflect_hazard(id: int, dx: float, dz: float) -> bool:
	if hazard_source == null: return false
	var src: Variant = hazard_source.get_ref()
	if src == null or not src.has_method("deflect_crate"): return false
	return bool(src.deflect_crate(id, dx, dz))

## A shot ray hitting a falling hazard crate first: redirect it down the ray and return the distance (or -1 = none within
## `far`). The tracer stops on it (no damage, no damage multiplication). Called from Weapons.fire_gun, tuned only.
func deflect_hazard_ray(ox: float, oy: float, oz: float, dx: float, dy: float, dz: float, far: float) -> float:
	var haz := hazard_deflectables()
	if haz.is_empty(): return -1.0
	var best := -1.0
	var best_id := -1
	for h: Dictionary in haz:
		var t := Weapons.ray_sphere(ox, oy, oz, dx, dy, dz, float(h["x"]), float(h["y"]), float(h["z"]), float(h.get("r", 1.1)))
		if t >= 0.0 and t < far and (best < 0.0 or t < best): best = t; best_id = int(h["id"])
	if best_id < 0 or not deflect_hazard(best_id, dx, dz): return -1.0
	ev({"type": "reaction", "kind": "crate", "x": ox + dx * best, "y": oy + dy * best, "z": oz + dz * best, "dx": dx, "dz": dz})
	return best

## The Human Bowling Ball: the trap is released and the victim starts sliding down (dx, dz). The knockback from the melee
## hit is replaced by the slide (flat, 26 m/s): vertical speed and stun are zeroed so the body really runs along the floor.
func _bowl_launch(v: FighterState, a: FighterState, dx: float, dz: float) -> void:
	var net: RefCounted = v.trap_net
	if net is Weapons.TrapNet: (net as Weapons.TrapNet).victims.erase(v)   # the net lets go (a shared net keeps its others)
	v.trap_t = 0.0; v.trap_net = null
	v.stun = 0.0; v.down_t = 0.0
	var l := sqrt(dx * dx + dz * dz)
	if l < 1e-6: dx = sin(a.face_yaw); dz = cos(a.face_yaw); l = 1.0
	dx /= l; dz /= l
	var p := v.phys
	p.vy = 0.0; p.grounded = true
	p.vx = dx * BOWL_SPEED; p.vz = dz * BOWL_SPEED
	bowl_slides[v] = {"dx": dx, "dz": dz, "t": BOWL_TIME, "pins": {}, "struck": false}
	ev({"type": "reaction", "kind": "bowl", "x": p.px, "y": p.py + 0.3, "z": p.pz, "dx": dx, "dz": dz, "f": a})

## One fixed step of a sliding bowling ball (Combat.timers, per fighter, so it runs inside MatchSim.step). Re-asserts the
## slide speed, runs over every other fighter once each (30 dmg / 18 force, never the bowler itself) and emits STRIKE!
## once per launch on the first pin that really applied. The slide ends on time, death, a knockdown or a fresh net.
func _bowl_tick(f: FighterState, dt: float) -> void:
	var s: Dictionary = bowl_slides[f]
	var p := f.phys
	var t := float(s["t"]) - dt
	if t <= 0.0 or f.dead or f.down_t > 0.0 or f.trap_t > 0.0:
		bowl_slides.erase(f); return
	s["t"] = t
	var dx := float(s["dx"])
	var dz := float(s["dz"])
	p.vx = dx * BOWL_SPEED; p.vz = dz * BOWL_SPEED
	var pins: Dictionary = s["pins"]
	for e: FighterState in fighters:
		if e == f or e.dead or e.elim or e.is_ghost or pins.has(e): continue
		var ex := e.phys.px - p.px
		var ez := e.phys.pz - p.pz
		if ex * ex + ez * ez > BOWL_PIN_R * BOWL_PIN_R or absf(e.phys.py - p.py) > 1.6: continue
		pins[e] = true
		if not hit(e, BOWL_PIN_DMG, dx, 0.35, dz, BOWL_PIN_FORCE, false, f)["applied"]: continue
		if not bool(s["struck"]):
			s["struck"] = true
			ev({"type": "toast", "text": tr("STRIKE!")})

## Melee half of the Mid-Air Redirect: the weapon line (now/prev, three halfway samples per segment) sweeps through a
## falling hazard crate or an explosive projectile in flight; the first one found is redirected along the horizontal swing
## direction (vertical speed kept) and a "reaction" VFX event goes out. Tuned only, no random number.
func _deflect_melee(f: FighterState, w: Dictionary, now: PackedFloat64Array, prev: PackedFloat64Array, n: int, thick: float) -> void:
	if hazard_source == null and weapons.rockets.is_empty() and weapons.grenades.is_empty(): return
	var j := (n - 1) * 3
	var dx := now[j] - prev[j]
	var dz := now[j + 2] - prev[j + 2]
	var haz := hazard_deflectables()
	for i in n:
		for k in 3:
			var kk := k * 0.5
			var ax := prev[i * 3] + (now[i * 3] - prev[i * 3]) * kk
			var ay := prev[i * 3 + 1] + (now[i * 3 + 1] - prev[i * 3 + 1]) * kk
			var az := prev[i * 3 + 2] + (now[i * 3 + 2] - prev[i * 3 + 2]) * kk
			for h: Dictionary in haz:
				var hx: float = ax - float(h["x"])
				var hy: float = ay - float(h["y"])
				var hz: float = az - float(h["z"])
				var rr: float = float(h.get("r", 1.1)) + thick
				if hx * hx + hy * hy + hz * hz >= rr * rr: continue
				if deflect_hazard(int(h["id"]), dx, dz):
					ev({"type": "reaction", "kind": "crate", "x": float(h["x"]), "y": float(h["y"]), "z": float(h["z"]),
						"dx": dx, "dz": dz, "f": f})
					return
			if weapons.deflect_near(ax, ay, az, thick, dx, dz): return

# ============================== melee ==============================

## The katana (and typhoon/trident) snaps toward whoever is roughly in front.
func katana_target(f: FighterState, yaw: float) -> FighterState:
	var best: FighterState = null
	var bs := 1e9
	var fx_ := sin(yaw)
	var fz_ := cos(yaw)
	for e: FighterState in fighters:
		if e == f or e.dead or is_friend(f, e): continue
		if not bots_can_hit(f, e): continue
		var dx := e.phys.px - f.phys.px
		var dz := e.phys.pz - f.phys.pz
		var d := sqrt(dx * dx + dz * dz)
		if d > 7.5 or d < 0.01 or absf(e.phys.py - f.phys.py) > 3.5: continue
		var cs := (dx * fx_ + dz * fz_) / d
		if cs < 0.45: continue
		var sc := d * (2.0 - cs)
		if sc < bs: bs = sc; best = e
	return best

# --- charged heavy melee + swing archetypes (Sprint 3.1, docs/DAMAGE.md "Charged heavy melee") ---
## Godot overlay only: hold FIRE with a melee weapon for HEAVY_CHARGE 0.45 s and the swing becomes a Heavy Swing (1.45x
## damage, 1.5x force, a parry is smashed instead of deflecting the hit). Every branch is gated on tuning_active(); the
## input path additionally refuses while `net_started` (the peer "sw" replay carries no heavy bit), and nothing here
## draws a random number. A missing `swingStyleDef` dictionary = the shared/web swing: the literals in
## melee_tick/melee_sweep are then used verbatim, so the no-style path stays bit-identical.
const HEAVY_CHARGE := 0.45        ## s of held FIRE that charges a Heavy Swing (auto-released while still held)
const HEAVY_DMG_MUL := 1.45       ## Heavy Swing damage multiplier (melee_sweep, before the body-part multiplier)
const HEAVY_FORCE_MUL := 1.5      ## ... and knockback-force multiplier
const NO_STYLE := {}              ## the no-archetype swing: read-only, so the hot paths never allocate a fallback dict

## The crosshair charge ring fraction: 0 = no charge, 1 = a full Heavy Swing (HUD, Combat.charge_frac). Static so the HUD
## and the tests share the exact rule; nothing random.
static func charge_frac(t: float) -> float:
	if t <= 0.0: return 0.0
	return clampf(t / HEAVY_CHARGE, 0.0, 1.0)

## meleeBegin: start a swing of weapon `key` toward `yaw` (sets the cooldown, lunges forward). `heavy` = the charged Heavy
## Swing; only the tuning-gated input path passes true (a bare Combat, the web replay and bots always get the classic swing).
func melee_begin(f: FighterState, key: String, yaw: float, heavy: bool = false) -> void:
	var w := wdata(key)
	f.heavy = heavy and tuning_active()
	f.swing = 0.0; f.swing_yaw = yaw; f.swing_hit = {}; f.bat_valid = false; f.cool = float(w["cooldown"])
	f.slam = not f.phys.grounded and not f.dead and f.down_t <= 0.0     # swung in the air: a big overhead smack
	f.stab = false; f.assist_on = false
	var lunge := float(w.get("dash", 0)) if w.get("dash", 0) else 3.0
	var sword := key == "katana" or key == "typhoon" or key == "trident"
	f.cyclone = false
	if sword and not f.dead:
		var tgt := katana_target(f, yaw)
		if tgt != null:
			yaw = atan2(tgt.phys.px - f.phys.px, tgt.phys.pz - f.phys.pz); f.swing_yaw = yaw; f.assist_on = true; f.face_yaw = yaw
			var dx := tgt.phys.px - f.phys.px
			var dz := tgt.phys.pz - f.phys.pz
			var hi := 11.0 if key == "trident" else (float(w.get("dash", 0)) if w.get("dash", 0) else 15.0)
			lunge = clampf_js(sqrt(dx * dx + dz * dz) * 4.5, 4.0, hi)
		if f.slam: f.kat_n = 0
		else:
			if time - f.kat_t > 1.2: f.kat_n = 0
			var n := f.kat_n
			if key == "typhoon": f.cyclone = n % 3 == 2
			else: f.stab = n % 2 == 1
			f.kat_n = n + 1; f.kat_t = time
	if key == "trident" and not f.slam and not f.dead:
		f.stab = true
		if not f.assist_on: lunge = 4.5
	if f.slam:
		kick_lean(f, -3.2, 0.0)
	else:
		kick_lean(f, -1.6 if key == "trident" else (-3.2 if f.stab else -2.2), 0.0)
		var dash := lunge * 1.2 if (f.stab and key != "trident") else lunge
		f.phys.vx += sin(yaw) * dash; f.phys.vz += cos(yaw) * dash
		if w.get("dash", 0):
			if f.phys.grounded: f.phys.vy = maxf(f.phys.vy, 1.5)
			ev({"type": "puff", "x": f.phys.px, "y": f.phys.py + 1.0, "z": f.phys.pz, "kind": "dash"})
	ev({"type": "sfx", "name": "swing", "f": f})
	# Gold-rim presentation hook (docs/DAMAGE.md): nothing in the sim consumes it, the visual layer may; no random number.
	if f.heavy: ev({"type": "heavy_swing", "f": f})

## meleeTick: advance the swing and set the arm target (aim_*). Returns true on the step the swing ends. A swing archetype
## (`w.swingStyleDef`, from weapon_tuning.json swingStyles) narrows/widens the base arc (`arc`) and tilts it (`lift`);
## the other poses (slam / cyclone / stab) keep their own shape and only read the style's tip/time window in melee_sweep.
func melee_tick(f: FighterState, key: String, dt: float, yaw: float) -> bool:
	var w := wdata(key)
	var sd: Variant = w.get("swingStyleDef") if w.has("swingStyleDef") else null
	var sty: Dictionary = sd if sd is Dictionary else NO_STYLE
	var st_time := float(w.get("swingTime", 0.34)) if w.get("swingTime", 0) else 0.34
	f.swing += dt / (st_time * (1.6 if f.cyclone else 1.0))
	if f.assist_on: yaw = f.swing_yaw
	var s := sin(yaw)
	var c := cos(yaw)
	var t := clampf_js(f.swing, 0.0, 1.0)
	var half := 1.7
	var lift := -0.02
	if not sty.is_empty():
		if sty.has("arc"): half = float(sty["arc"]) * 0.5
		if sty.has("lift"): lift = float(sty["lift"])
	var a := lerp_js(half, -half, t)
	var v: Array
	if f.slam:
		var pitch := lerp_js(1.25, -1.3, t)
		var cp := cos(pitch)
		v = norm3(s * cp, sin(pitch), c * cp)
	elif f.cyclone:
		var ac := lerp_js(0.3, 0.3 - PI * 2.0, t)
		v = norm3(s * cos(ac) - c * sin(ac), -0.02, c * cos(ac) + s * sin(ac))
	elif f.stab and key == "trident":
		var pt := lerp_js(0.1, 0.75, t / 0.3) if t < 0.3 else lerp_js(0.75, -0.02, clampf_js((t - 0.3) / 0.1, 0.0, 1.0))
		var cp2 := cos(pt)
		v = norm3(s * cp2, sin(pt), c * cp2)
	elif f.stab:
		var ap := lerp_js(1.0, 0.55, t / 0.3) if t < 0.3 else lerp_js(0.55, 0.0, clampf_js((t - 0.3) / 0.12, 0.0, 1.0))
		var yy := 0.18 if t < 0.3 else -0.02
		v = norm3(s * cos(ap) - c * sin(ap), yy, c * cos(ap) + s * sin(ap))
	else:
		v = norm3(s * cos(a) - c * sin(a), lift, c * cos(a) + s * sin(a))
	f.aim_x = v[0]; f.aim_y = v[1]; f.aim_z = v[2]
	if f.swing >= 1.3:
		f.swing = -1.0; f.slam = false; f.stab = false; f.cyclone = false; f.assist_on = false; f.heavy = false
		return true
	return false

## Melee input (the left click with a melee weapon): returns true if a swing started. `heavy` = the charged Heavy Swing
## (only the tuning-gated PlayerControl path passes true; bots/quick melee/classic callers keep the classic swing).
func try_melee(f: FighterState, yaw: float, heavy: bool = false) -> bool:
	var w := wdata(f.weapon)
	if w.get("type", "") != "melee" or f.cool > 0.0 or f.swing >= 0.0 or f.throw_key != "" or f.dead or f.down_t > 0.0:
		return false
	melee_begin(f, f.weapon, yaw, heavy)
	if f.slot >= 0: f.set_ammo(f.get_ammo() - 1)
	return true

## afterSwing: a used-up melee weapon breaks; quick melee goes back to the held slot.
func after_swing(f: FighterState) -> void:
	if f.slot >= 0 and f.get_ammo() <= 0:
		drop_slot(f); return
	if f.return_slot >= 0:
		var r := f.return_slot
		f.return_slot = -1
		equip_slot(f, r if f.slots[r] != null else -1)

## meleeSweep: the weapon hurts whatever it touches. Call once per rendered frame after the animation has written
## hand_* and arm_* (the web game calls it from `frame`, not `simStep`). Tests the weapon line now, last frame and
## halfway between against every enemy's hit spheres; `swing_hit` makes one swing hit each target once.
func melee_sweep(f: FighterState) -> void:
	var w := wdata(f.weapon)
	var sd: Variant = w.get("swingStyleDef") if w.has("swingStyleDef") else null
	var sty: Dictionary = sd if sd is Dictionary else NO_STYLE
	# The hit timing window is the swing archetype's (normalized swing time 0..1.3): defaults are the classic .04/1.2 and
	# a stab still waits for .3; a style may move either end (e.g. crush ends at .85, a whip starts at .28).
	var sw0 := 0.3 if f.stab else 0.04
	var sw1 := 1.2
	if not sty.is_empty():
		if sty.has("hitStart"): sw0 = maxf(sw0, float(sty["hitStart"]))
		if sty.has("hitEnd"): sw1 = float(sty["hitEnd"])
	if w.is_empty() or w.get("type", "") != "melee" or f.swing < sw0 or f.swing > sw1 or f.dead or f.down_t > 0.0:
		f.bat_valid = false; return
	var now := f.bat_now
	var prev := f.bat_prev
	var tip := float(w["tip"])
	var tip_eff := (tip * 1.2 if f.stab else (tip * 1.1 if f.cyclone else tip)) * (2.2 if giant else 1.0)
	if not sty.is_empty() and sty.has("tipMul"): tip_eff *= float(sty["tipMul"])
	var n := FighterState.BAT_N
	for i in n:
		var s := lerp_js(FighterState.BAT_BASE, tip_eff, float(i) / float(n - 1))
		now[i * 3] = f.hand_x + f.arm_x * s; now[i * 3 + 1] = f.hand_y + f.arm_y * s; now[i * 3 + 2] = f.hand_z + f.arm_z * s
	if f.bat_valid:
		var thick := float(w["thick"])
		for e: FighterState in fighters:
			if e == f or e.dead or f.swing_hit.has(e): continue
			if is_friend(f, e): continue
			if not bots_can_hit(f, e): continue
			var edx := e.phys.px - f.phys.px
			var edz := e.phys.pz - f.phys.pz
			var touched := f.cyclone and f.swing > 0.4 and sqrt(edx * edx + edz * edz) < 3.2 and absf(e.phys.py - f.phys.py) < 2.2
			var sph := e.spheres(giant)
			var tp_at := [e.chest_x, e.chest_y, e.chest_z]   # where the bat touched (cyclone body contact: the chest)
			var tp_head := false
			for i in n:
				if touched: break
				for k in 3:
					if touched: break
					var kk := k * 0.5
					var ax := prev[i * 3] + (now[i * 3] - prev[i * 3]) * kk
					var ay := prev[i * 3 + 1] + (now[i * 3 + 1] - prev[i * 3 + 1]) * kk
					var az := prev[i * 3 + 2] + (now[i * 3 + 2] - prev[i * 3 + 2]) * kk
					for sp: Array in sph:
						var dx: float = ax - sp[0]
						var dy: float = ay - sp[1]
						var dz: float = az - sp[2]
						var rr: float = sp[3] + thick
						if dx * dx + dy * dy + dz * dz < rr * rr:
							touched = true; tp_at = [ax, ay, az]; tp_head = sp[4]; break
			if not touched: continue
			# A Heavy Swing smashes through a tuned parry instead of being deflected (docs/DAMAGE.md).
			var heavy := f.heavy
			if heavy:
				if e.parry_t > 0.0:
					e.parry_t = 0.0
					ev({"type": "parry_break", "f": e, "attacker": f, "x": e.phys.px, "y": e.phys.py + 1.4, "z": e.phys.pz})
			elif try_parry(e, f): continue
			f.swing_hit[e] = true
			# knock them the way the weapon was moving, mixed with "away from the swinger"
			var j := (n - 1) * 3
			var bx := now[j] - prev[j]
			var bz := now[j + 2] - prev[j + 2]
			var cx := edx
			var cz := edz
			if cx * cx + cz * cz < 1e-6: cx = sin(f.yaw); cz = cos(f.yaw)
			var cn := norm3(cx, 0.0, cz)
			if bx * bx + bz * bz > 1e-8:
				var bn := norm3(bx, 0.0, bz)
				bx = bn[0] * 0.7; bz = bn[2] * 0.7
			var d := norm3(cn[0] * 0.6 + bx, 0.05 if f.slam else float(w.get("lift", 0.0)), cn[2] * 0.6 + bz)
			var slam_mul := float(w.get("slamMul", 1.3)) if w.get("slamMul", 0) else 1.3
			var dmg := float(w["dmg"]) * f.dmg_scale * (slam_mul if f.slam else (1.6 if f.cyclone else 1.0))
			var force := float(w["force"]) * f.melee_force_mul * (1.1 if f.slam else (1.5 if f.cyclone else 1.0))
			# Charged Heavy Swing (overlay only; `heavy` is false unless melee_begin was told so while tuning is on).
			if heavy:
				dmg *= HEAVY_DMG_MUL
				force *= HEAVY_FORCE_MUL
			# body part: a bat on the head only counts as a headshot when the table allows melee heads (classic: never)
			var part := body_part(e, tp_at[0], tp_at[1], tp_at[2], tp_head and bool(zone_table().get("meleeHead", false)))
			var pm := part_mul(part)
			dmg *= pm
			if hit(e, dmg, d[0], d[1], d[2], force, part == "head", f, zone_info(part, pm, tp_at[0], tp_at[1], tp_at[2]))["applied"]:
				# Wobble Reactions (tuning only): a HEAVY swing on a netted fighter releases the net and starts the slide.
				# The topple roll is skipped for a launched body (a knockdown would end the slide on its first tick).
				var bowled := tuning_active() and e.trap_t > 0.0 and not e.dead and heavy_melee(w)
				if bowled: _bowl_launch(e, f, d[0], d[2])
				var tp := float(w.get("topple", 0.0)) * f.melee_topple_mul
				if not bowled and tp and rng.next() < tp: topple(e, 1.1)
				ev({"type": "sfx", "name": w.get("hitSfx", "clink"), "f": e})
				apply_status(e, w)     # Sprint 3.2: the weapon data says if this hit chills/shocks/weighs them down
		# Wobble Reactions (tuning only): the weapon line also swats a falling load-test crate / an explosive shot aside.
		if tuning_active(): _deflect_melee(f, w, now, prev, n, thick)
	for i in n * 3: prev[i] = now[i]
	f.bat_valid = true

# ============================== math helpers (same operation order as three.js / the web game) ==============================

## Vector3.normalize(): multiply by 1/length (length 0 -> unchanged).
static func norm3(x: float, y: float, z: float) -> Array:
	var l := sqrt(x * x + y * y + z * z)
	if l == 0.0: l = 1.0
	var inv := 1.0 / l
	return [x * inv, y * inv, z * inv]

static func lerp_js(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

static func clampf_js(v: float, a: float, b: float) -> float:
	return maxf(a, minf(b, v))

## Math.round: halves go up (also for negatives).
static func js_round(x: float) -> int:
	var r := floorf(x)
	return int(r + 1.0) if x - r >= 0.5 else int(r)
