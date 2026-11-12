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
var grav_setting := 1.0          ## cfg.grav (Moon Drift < 0.3: lobbed things float too, projG)

# --- net (filled by the net layer) ---
var net_started := false
var net_host := false
var net_apply := false           ## true while applying an `h` that arrived over the network

var time := 0.0                  ## simTime: advance it by the sim step
var fighters: Array = []         ## every FighterState in the match
var rng := CombatRng.new()
var events: Array = []
var weapons: Weapons

func _init() -> void:
	weapons = Weapons.new(self)
	set_mode("classic")

## Drop the fighter-to-fighter references (last attacker, burner, swing targets, projectiles) so nothing leaks
## when a match ends. Call before throwing the Combat away.
func dispose() -> void:
	for f: FighterState in fighters:
		f.last_attacker = null; f.burner = null; f.swing_hit = {}; f.trap_net = null
	weapons.clear()
	fighters.clear()
	events.clear()

static func read_json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

## Load weapons/classes/modes from a folder holding copies of shared/*.json (the Content autoload will call this later).
func load_content(dir: String = "res://data") -> void:
	weapons_data = read_json(dir.path_join("weapons.json"))
	classes = read_json(dir.path_join("classes.json"))
	modes = read_json(dir.path_join("modes.json"))
	set_mode(mode_id)

func set_mode(id: String) -> void:
	mode_id = id
	mode = modes.get(id, {})

func wdata(key: String) -> Dictionary:
	return weapons_data.get(key, {})

func is_friend(a: FighterState, b: FighterState) -> bool:
	return teams != 0 and a != null and b != null and a != b and a.team == b.team

func max_hp(f: FighterState) -> float:
	return hp_setting * (2.0 if giant else 1.0) * f.cls_hp

## Bots only hurt each other in a free-for-all brawl.
func bots_can_hit(a: FighterState, e: FighterState) -> bool:
	return a.is_player or e.is_player or (ffa and brawl)

func ev(e: Dictionary) -> void:
	events.append(e)

func kick_lean(f: FighterState, a: float, b: float) -> void:
	ev({"type": "lean", "f": f, "a": a, "b": b})

func kick_head(f: FighterState, a: float, b: float) -> void:
	ev({"type": "head", "f": f, "a": a, "b": b})

func push_arm(f: FighterState, x: float, y: float, z: float) -> void:
	ev({"type": "arm", "f": f, "x": x, "y": y, "z": z})

# ============================== damage ==============================

## Fighter.hit: damage, knockback, stun, K.O. Returns {applied, dmg, ko, light, ...}; false-y `applied` = no effect.
func hit(v: FighterState, dmg: float, dx: float, dy: float, dz: float, force: float, head: bool, attacker: FighterState) -> Dictionary:
	var r := {"applied": false, "ko": false}
	if v.is_ghost:                     # another player's wobbler: the shooter's game decides the hit and tells theirs
		if attacker == null or attacker.is_ghost or attacker.net_slot < 0 or v.dead or v.left or v.invuln > 0.0 or not net_started:
			return r
		if attacker.is_player:
			ev({"type": "dmg_number", "f": v, "dmg": dmg, "head": head}); attacker.st["hits"] += 1
		v.flash = 0.12
		var msg := NetSnapshot.encode_hit(v.net_slot if v.net_human else 0, v.net_slot, attacker.net_slot, dmg, dx, dy, dz, force, head)
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
	if v.shield_t > 0.0:
		dmg *= 0.5
	if v.down_t > 0.0 and not (v.trap_t > 0.0):
		dmg *= 0.5
	if attacker != null and attacker.is_player and attacker != v:
		ev({"type": "dmg_number", "f": v, "dmg": dmg, "head": head})
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
	var fk := (kb_setting if kb_setting != 0.0 else 1.0) * 0.8 * float(mode.get("kbMul", 1.0) if mode.get("kbMul", 0) else 1.0) * v.cls_kb
	var p := v.phys
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
	ev({"type": "hit", "f": v, "attacker": attacker, "dmg": dmg, "head": head, "force": force})
	if v.hp <= 0.0:
		v.st["streak"] = 0; v.st["multi"] = 0; v.st["deaths"] += 1
		v.dead = true
		v.death_t = 1.2 if v.home != null else (PLAYER_RESPAWN if v.is_player else BOT_RESPAWN)
		v.fall_side = -1 if rng.next() < 0.5 else 1
		v.down_t = 0.0; v.kick_t = -1.0
		if p.py > -1.0:
			p.vy = maxf(p.vy, 6.5)
			ev({"type": "ko_burst", "f": v})
		clear_inventory(v)
		set_weapon(v, "")
		if attacker != null and attacker != v:
			add_ko(attacker, v)
		else:
			ev({"type": "ko", "killer": null, "victim": v, "weapon": ""})
		if net_started and v.net_slot >= 0 and not v.is_ghost and (v.is_player or net_host):
			var msg := NetSnapshot.encode_ko(attacker.net_slot if attacker != null and attacker.net_slot >= 0 else -1, v.net_slot)
			ev({"type": "net", "msg": msg})
		r["ko"] = true
	return r

## addKo: K.O. credit and streaks. Match-limit checks and the kill feed are the world's job (it reads the "ko" event).
func add_ko(killer: FighterState, victim: FighterState) -> void:
	if victim != null and is_friend(killer, victim):
		return
	killer.ko += 1; killer.kill_t = time
	var k := killer.st
	k["streak"] += 1; k["bestStreak"] = maxi(k["bestStreak"], k["streak"])
	k["multi"] = k["multi"] + 1 if time - float(k["lastKo"]) < 6.0 else 1
	k["lastKo"] = time; k["bestMulti"] = maxi(k["bestMulti"], k["multi"])
	var wn: String = wdata(killer.weapon).get("name", "Spatula") if killer.weapon != "" else "Spatula"
	k["weps"][wn] = int(k["weps"].get(wn, 0)) + 1
	ev({"type": "ko", "killer": killer, "victim": victim, "weapon": wn})

## Fall over (never longer than 1.6 s); a moment of "can't be tripped" follows getting up.
func topple(f: FighterState, dur: float, msg: String = "") -> bool:
	if f.dead or f.down_t > 0.0 or f.getup_immune > 0.0:
		return false
	f.down_t = minf(dur, 1.6)
	f.fall_side = -1 if rng.next() < 0.5 else 1
	f.swing = -1.0; f.kick_t = -1.0; f.stun = maxf(f.stun, 0.35)
	if f.return_slot >= 0:
		var r := f.return_slot
		f.return_slot = -1
		equip_slot(f, r if f.slots[r] != null else -1)
	var a := rng.range_f(-3, 3)
	var b := rng.range_f(-3, 3)
	kick_head(f, a, b)
	var ax := rng.range_f(-3, 3)
	var az := rng.range_f(-3, 3)
	push_arm(f, ax, 0.0, az)
	ev({"type": "sfx", "name": "boing", "f": f})
	if f.is_player:
		ev({"type": "toast", "text": msg if msg != "" else "You fell over!"})
	return true

# ============================== timers / respawn ==============================

## Fighter.timers: per-step countdowns. Not ported yet: emotes (visual), ninja dash charges (dashTick).
func timers(f: FighterState, dt: float) -> void:
	tick_reload(f, dt)
	if f.spd_t > 0.0: f.spd_t -= dt
	if f.rage_t > 0.0: f.rage_t -= dt
	if f.shield_t > 0.0: f.shield_t -= dt
	f.cool -= dt * f.cls_rate; f.melee_cool -= dt; f.shove_cool -= dt; f.kick_cool -= dt; f.pad_cool -= dt
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
	if f.is_player and not f.dead and f.hp < max_hp(f) and time - f.last_hit_time > 4.0:
		f.hp = minf(max_hp(f), f.hp + 8.0 * max_hp(f) / 100.0 * dt)

func respawn(f: FighterState) -> void:
	if f.elim:
		return
	f.fell_t = false
	if lives_mode:
		f.lives -= 1
		if f.lives <= 0:
			f.elim = true
			ev({"type": "eliminated", "f": f})
			return
	var s: Array = spawns[int(floor(rng.next() * spawns.size()))] if spawns.size() > 0 else [0.0, 0.0]
	# TODO(shrinking arenas): MAPS[id].shrinks picks a spot inside the shrink zone instead.
	if f.home != null: s = f.home
	place_at(f, float(s[0]), float(s[1]), 0.01 if f.home != null else spawn_y)
	f.invuln = 0.3 if f.home != null else 2.5     # spawn protection
	ev({"type": "respawn", "f": f})

## placeAt: teleport and reset for a fresh life (also the match start).
func place_at(f: FighterState, x: float, z: float, y: float = 0.01) -> void:
	f.phys.place(x, y, z)
	f.hp = max_hp(f); f.dead = false; f.burn = 0.0
	f.down_t = 0.0; f.getup_immune = 0.0; f.kick_t = -1.0; f.swing = -1.0; f.stun = 0.0; f.trap_t = 0.0; f.trap_net = null
	clear_inventory(f); set_weapon(f, "spatula")
	var start: Variant = mode.get("start")
	if start is String and start != "": pickup(f, start)
	# TODO(weapon ladder): gungame gives the current rung (ggGive).

# ============================== inventory ==============================

func set_weapon(f: FighterState, key: String) -> void:
	f.weapon = key
	f.swing = -1.0; f.bat_valid = false; f.nocked = false; f.grab_t = -1.0; f.draw = 0.0
	ev({"type": "weapon", "f": f, "key": key})

func equip_slot(f: FighterState, i: int) -> bool:
	f.return_slot = -1
	if i >= 0 and f.slots[i] == null:
		return false
	if f.reloading and i != f.slot:
		cancel_reload(f, true)         # swapped away mid-reload: it finishes when you come back
	f.slot = i
	set_weapon(f, f.slots[i]["key"] if i >= 0 else "spatula")
	if i >= 0: auto_reload(f)
	return true

func clear_inventory(f: FighterState) -> void:
	cancel_reload(f, false)
	f.slots = [null, null, null]; f.slot = -1; f.return_slot = -1

## Should a freshly picked-up weapon go straight into the hand?
func auto_eq(f: FighterState, i: int) -> bool:
	if not f.is_player or auto_switch or f.slot < 0 or f.slot == i:
		return true
	var cur: Variant = f.slots[f.slot]
	return cur == null or int(cur["ammo"]) <= 0

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

## useAmmo: one shot spent (the Weapon Ladder never runs out of spare ammo).
func use_ammo(f: FighterState) -> void:
	f.st["shots"] += 1
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
			if rng.next() < 0.12: topple(f, 0.9, "Your own kick tripped you!")
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

## meleeBegin: start a swing of weapon `key` toward `yaw` (sets the cooldown, lunges forward).
func melee_begin(f: FighterState, key: String, yaw: float) -> void:
	var w := wdata(key)
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

## meleeTick: advance the swing and set the arm target (aim_*). Returns true on the step the swing ends.
func melee_tick(f: FighterState, key: String, dt: float, yaw: float) -> bool:
	var w := wdata(key)
	var st_time := float(w.get("swingTime", 0.34)) if w.get("swingTime", 0) else 0.34
	f.swing += dt / (st_time * (1.6 if f.cyclone else 1.0))
	if f.assist_on: yaw = f.swing_yaw
	var s := sin(yaw)
	var c := cos(yaw)
	var t := clampf_js(f.swing, 0.0, 1.0)
	var a := lerp_js(1.7, -1.7, t)
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
		v = norm3(s * cos(a) - c * sin(a), -0.02, c * cos(a) + s * sin(a))
	f.aim_x = v[0]; f.aim_y = v[1]; f.aim_z = v[2]
	if f.swing >= 1.3:
		f.swing = -1.0; f.slam = false; f.stab = false; f.cyclone = false; f.assist_on = false
		return true
	return false

## Melee input (the left click with a melee weapon): returns true if a swing started.
func try_melee(f: FighterState, yaw: float) -> bool:
	var w := wdata(f.weapon)
	if w.get("type", "") != "melee" or f.cool > 0.0 or f.swing >= 0.0 or f.throw_key != "" or f.dead or f.down_t > 0.0:
		return false
	melee_begin(f, f.weapon, yaw)
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
	if w.is_empty() or w.get("type", "") != "melee" or f.swing < (0.3 if f.stab else 0.04) or f.swing > 1.2 or f.dead or f.down_t > 0.0:
		f.bat_valid = false; return
	var now := f.bat_now
	var prev := f.bat_prev
	var tip := float(w["tip"])
	var tip_eff := (tip * 1.2 if f.stab else (tip * 1.1 if f.cyclone else tip)) * (2.2 if giant else 1.0)
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
						if dx * dx + dy * dy + dz * dz < rr * rr: touched = true; break
			if not touched: continue
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
			var force := float(w["force"]) * (1.1 if f.slam else (1.5 if f.cyclone else 1.0))
			if hit(e, dmg, d[0], d[1], d[2], force, false, f)["applied"]:
				var tp := float(w.get("topple", 0.0))
				if tp and rng.next() < tp: topple(e, 1.1)
				ev({"type": "sfx", "name": w.get("hitSfx", "clink"), "f": e})
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
