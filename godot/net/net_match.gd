class_name NetMatch
extends RefCounted
## An online match seen from a guest (pure logic, no nodes). Ported from the web game's netStartMatch (guest side),
## makeGhost/ghostEquip/ghostFire, netHandle, netSnap and netStep (public/index.html ~8931-9120):
## - the local player simulates itself (MatchSim/PlayerControl as offline);
## - every other slot is a ghost FighterState (`is_ghost`), moved by the `S` snapshots its owner sends
##   (predict by the snapshot's age <= 0.2 s, ease with k = 1 - exp(-dt*22), snap beyond 6 m), with swings,
##   shots and kicks replayed for the look only;
## - hits on a ghost become `h` messages (Combat emits them), `h` aimed at me is applied through Combat.hit;
## - my own state goes out as `S` at 30 Hz, plus `sw`/`f`/`k`/`ko`/`take` when they happen.
## MatchSim.step calls pre_step() / post_controls(); the world feeds handle() and on_event().
## Godot-only additions (docs/PROTOCOL.md 6.3, ignored by web clients): `rules.gmode` (an app-only mode: teams from
## `rules.gteam`, Pillars spots from `rules.pp`), `gm` mode-state messages from a Godot host (K.O.s, ladder rungs,
## Pillars clock, Chaos events), `start.rs` (the match state after a host migration) and `emote`.

const HZ := 30.0
const PREDICT_MAX := 0.2         ## seconds a snapshot is carried forward
const EASE := 22.0               ## k = 1 - exp(-dt * EASE)
const SNAP := 6.0                ## metres: further off than this, jump straight there
## Modes only Godot clients play online (the web client's netMode turns them into Classic): sent as `rules.gmode`.
const GODOT_MODES := ["tdm", "deathmatch", "sudden", "chaos", "pillars", "lowg", "duel", "t2", "t3", "t4"]

## Squat flag holder so MatchSim's crouch easing works for ghosts (the web game reads g.squat).
class GhostControl:
	extends RefCounted
	var squat := false
	func think(_f: FighterState, _sim: MatchSim, _dt: float) -> void:
		pass

var sim: MatchSim
var combat: Combat
var send: Callable               ## func(m: Dictionary): a room message to the host
var my_slot := -1
var slots: Array = []            ## cleaned start.slots
var ghosts := {}                 ## slot -> FighterState
var ns := {}                     ## slot -> last decoded `S` entry (+ "rt": clock when it arrived)
var clock := 0.0
var send_t := 0.0
var limit := 0
var over := false
var winner := -1
var rules: Dictionary = {}       ## start.rules
var gmode := ""                  ## the app-only mode this match plays ("" = a web-compatible mode)
var sent_counts := {}            ## t -> how many sent (tests)
var recv_counts := {}            ## t -> how many handled (tests)

func _init(p_sim: MatchSim, p_send: Callable, p_slot: int) -> void:
	sim = p_sim
	combat = p_sim.combat
	send = p_send
	my_slot = p_slot

## Break the reference cycles with the sim.
func dispose() -> void:
	if sim: sim.net = null
	ghosts.clear(); ns.clear()
	sim = null; combat = null

# ============================== match setup (netStartMatch, guest side) ==============================

## Rules from `start.rules` onto Combat/physics before MatchSim.setup (setBotCfg with the host's values).
static func apply_rules(c: Combat, rules: Dictionary) -> void:
	var mode := play_mode(c.modes, rules)
	c.set_mode(mode)
	c.teams = int(c.mode.get("teams", 0)) if is_gmode(c.modes, rules) else 0
	c.giant = mode == "giant"
	c.grav_setting = rule_grav(rules)
	var hp := float(rules.get("hp", 100)) if (rules.get("hp") is float or rules.get("hp") is int) else 100.0
	c.hp_setting = hp if [100.0, 150.0, 200.0, 300.0, 500.0].has(hp) else 100.0
	var kb := float(rules.get("kb", 1)) if (rules.get("kb") is float or rules.get("kb") is int) else 1.0
	c.kb_setting = kb if [0.5, 1.0, 1.5, 2.0, 3.0].has(kb) else 1.0
	c.inf = bool(rules.get("inf", false))
	c.lives_mode = int(c.mode.get("lives", 0)) if c.mode.get("lives") else 0
	c.ffa = true
	c.net_started = true
	c.net_host = false

## The mode a client plays from `rules`: an app-only `gmode` (Godot host, every player on the app), else `mode`
## through netMode (unknown / team modes, Sandbox and Construction play Classic).
static func play_mode(modes: Dictionary, rules: Dictionary) -> String:
	if is_gmode(modes, rules): return str(rules["gmode"])
	var mode: Variant = rules.get("mode")
	var md: Dictionary = modes.get(mode, {}) if mode is String else {}
	if md.is_empty() or md.get("teams") or mode == "sandbox" or mode == "construction": return "classic"   # netMode
	return mode

static func is_gmode(modes: Dictionary, rules: Dictionary) -> bool:
	var g: Variant = rules.get("gmode")
	return g is String and GODOT_MODES.has(g) and modes.has(g)

## Gravity setting from the rules (0.5 / 1 / 1.5, Low-G 0.15).
static func rule_grav(rules: Dictionary) -> float:
	var g := NetSnapshot.num(rules.get("grav"), 0.0, 10.0, 1.0)
	if [0.5, 1.0, 1.5].has(g) or ((rules.get("mode") == "lowg" or rules.get("gmode") == "lowg") and is_equal_approx(g, 0.15)): return g
	return 1.0

## `rules.gteam`: the side (0 / 1) of slot `s`, -1 = none.
static func rule_team(rules: Dictionary, s: int) -> int:
	var t: Variant = rules.get("gteam")
	if not (t is Array) or s < 0 or s >= (t as Array).size(): return -1
	return clampi(NetSnapshot.to_int32(t[s]), 0, 1)

## `rules.pp`: the pillar (spawn index) of slot `s` on a map with `n` spawns, -1 = none (a permutation of 0..n-1).
static func rule_pillar(rules: Dictionary, s: int, n: int) -> int:
	var pp: Variant = rules.get("pp")
	if not (pp is Array) or (pp as Array).size() != n or n <= 0: return -1
	var seen := {}
	for v: Variant in pp:
		var i := NetSnapshot.to_int32(v)
		if i < 0 or i >= n or seen.has(i): return -1
		seen[i] = true
	return NetSnapshot.to_int32(pp[s % n])

## Dynamic arena from the rules (netStartMatch, guest side): {choice, seed, t0}. Unknown kind => steady.
## Set them on the MatchSim (dyn_choice / dyn_seed / dyn_t0) before setup().
static func rule_dyn(rules: Dictionary) -> Dictionary:
	var k: Variant = rules.get("dyn")
	var sd: Variant = rules.get("dseed")
	var t0: Variant = rules.get("dt0")
	var seed := 0
	if (sd is float or sd is int) and is_finite(float(sd)):
		seed = int(fposmod(signf(float(sd)) * floor(absf(float(sd))), 4294967296.0))   # `>>> 0` (ToUint32)
	return {"choice": k if k is String and Dynamics.KINDS.has(k) else "off", "seed": seed,
		"t0": clampf(float(t0), 0.0, 36000.0) if (t0 is float or t0 is int) and is_finite(float(t0)) else 0.0}

## After MatchSim.setup(.., bot_count = 0): my slot on the player, a ghost for every other slot (human, bot or empty).
## Returns {FighterState: look} for the world to draw.
func setup(start: Dictionary) -> Dictionary:
	slots = start["slots"]
	limit = int(start.get("limit", 0))
	rules = start.get("rules", {})
	sim.net = self
	sim.pickups.remote = true
	var grav := rule_grav(rules)
	sim.player.net_slot = my_slot
	sim.player.phys.grav_scale = grav
	var looks := {}
	var spawns: Array = sim.map.get("spawns", [])
	var n := 0
	for s in slots.size():
		if s == my_slot: continue
		var info: Dictionary = slots[s]
		var g := sim.add_fighter(info["cls"])
		g.is_ghost = true; g.net_slot = s; g.net_human = info["kind"] == "human"
		g.name = info["name"] if info["name"] != "" else "Player %d" % s
		g.phys.grav_scale = grav
		g.phys.can_climb = false
		sim.controllers[g] = GhostControl.new()
		var sp: Array = spawns[n % spawns.size()] if spawns.size() > 0 else [0, 0]
		n += 1
		combat.place_at(g, float(sp[0]), float(sp[1]), float(sim.map.get("spawnY", 0.01)))
		ghost_equip(g, "spatula")
		ghosts[s] = g
		var lk := look_of(info)
		sim.looks[g] = lk
		looks[g] = lk
		if info["kind"] == "empty": remove_ghost(s)
	_setup_mode()
	if start.get("rs") is Array: apply_resume(start["rs"], start.get("rsx", {}))
	return looks

## App-only mode on a guest: the host decides the end and runs the Chaos events; sides and pillar spots from the rules.
func _setup_mode() -> void:
	gmode = str(rules["gmode"]) if is_gmode(combat.modes, rules) else ""
	if gmode == "": return
	var r := combat.rules
	r.remote = true
	r.limit = limit
	if not r.chaos.is_empty(): r.chaos["next"] = INF
	_assign_teams()
	_place_pillars()

## Team modes: everybody's side from `rules.gteam` (the colours follow when the world builds the views).
func _assign_teams() -> void:
	if not combat.mode.get("teams"): return
	combat.teams = maxi(1, int(combat.mode.get("teams", 1)))
	for s in slots.size():
		var f := slot_fighter(s)
		if f != null: f.team = maxi(0, rule_team(rules, s))

## Pillars: the fighters this side runs stand on the pillar the host shuffled for their slot, facing the middle.
func _place_pillars() -> void:
	if combat.mode_id != "pillars": return
	var spots: Array = sim.map.get("spawns", [])
	for f: FighterState in owned():
		var i := rule_pillar(rules, f.net_slot, spots.size())
		if i < 0: continue
		var sp: Array = spots[i]
		combat.place_at(f, float(sp[0]), float(sp[1]), float(sim.map.get("spawnY", 0.01)))
		f.yaw = atan2(-float(sp[0]), -float(sp[1])); f.face_yaw = f.yaw

## The match state from before a host migration (`start.rs`: one entry per slot) and `rsx` (pt: Pillars clock).
func apply_resume(rs: Array, rsx: Variant) -> void:
	for e: Variant in rs:
		if not (e is Dictionary): continue
		var f := slot_fighter(NetSnapshot.to_int32(e.get("id")))
		if f == null or f.left: continue
		f.ko = maxi(0, NetSnapshot.to_int32(e.get("ko")))
		f.st["deaths"] = maxi(0, NetSnapshot.to_int32(e.get("dt")))
		f.gg_rung = clampi(NetSnapshot.to_int32(e.get("gg")), 0, ModeRules.GG.size() - 1)
		if combat.lives_mode:
			f.lives = clampi(NetSnapshot.to_int32(e.get("lv")), 0, 99)
			if NetSnapshot.to_int32(e.get("el")) != 0:
				f.elim = true; f.lives = 0; f.dead = true; f.death_t = 1e9; f.hp = 0.0
				continue
		if NetSnapshot.to_int32(e.get("d")) != 0: continue          # was down: it starts on its spawn
		var x := NetSnapshot.num(e.get("x"), -500.0, 500.0, NAN)
		var y := NetSnapshot.num(e.get("y"), -50.0, 200.0, NAN)
		var z := NetSnapshot.num(e.get("z"), -500.0, 500.0, NAN)
		if is_nan(x) or is_nan(y) or is_nan(z): continue
		f.phys.place(x, y, z)
		f.yaw = NetSnapshot.num(e.get("yaw"), -100.0, 100.0, f.yaw); f.face_yaw = f.yaw
		var hp := NetSnapshot.num(e.get("hp"), 0.0, 10000.0, 0.0)
		if hp > 0.0: f.hp = minf(hp, combat.max_hp(f))
		if combat.mode_id == "gungame" and not f.is_ghost: combat.rules.gg_give(f)
	combat.ev({"type": "toast", "text": "Host changed: the match goes on"})
	if rsx is Dictionary and not combat.rules.pil.is_empty() and rsx.has("pt"):
		combat.rules.pil["t"] = NetSnapshot.num(rsx.get("pt"), 0.0, ModeRules.PIL_TIME, ModeRules.PIL_TIME)

## The state a guest hands over when the relay promotes it to host (host migration): {} when there is no running
## match. slots / map / limit / rules of the old match, `l` = every slot's fighter, `dt0` = the arena clock.
func capture_resume() -> Dictionary:
	if sim == null or over or combat.rules.match_over or slots.is_empty(): return {}
	var l: Array = []
	for s in slots.size():
		var f := slot_fighter(s)
		if f == null: continue
		var p := f.phys
		l.append({"id": s, "x": NetSnapshot.fixed(p.px, 2), "y": NetSnapshot.fixed(p.py, 2), "z": NetSnapshot.fixed(p.pz, 2),
			"yaw": NetSnapshot.fixed(f.yaw, 2), "hp": NetSnapshot.fixed(f.hp, 1), "ko": f.ko, "dt": int(f.st["deaths"]),
			"lv": f.lives, "el": 1 if f.elim else 0, "d": 1 if (f.dead or f.left) else 0, "gg": f.gg_rung})
	var x := {}
	if not combat.rules.pil.is_empty(): x["pt"] = NetSnapshot.fixed(float(combat.rules.pil["t"]), 1)
	return {"slots": slots.duplicate(true), "map": sim.map_id, "limit": limit, "rules": rules.duplicate(true), "l": l, "rsx": x,
		"dt0": roundf(maxf(0.0, sim.dyn_clock()) * 1000.0) / 1000.0, "my_slot": my_slot}

## Plays emote `id` for everyone (`emote`, Godot-only: the web game has no emote message).
func send_emote(id: String) -> void:
	if my_slot < 0 or LockerData.emote(id).is_empty(): return
	_send({"t": "emote", "id": my_slot, "e": id})

static func look_of(info: Dictionary) -> Dictionary:
	var col: int = info["color"]
	var sk: Dictionary = GuestSession.data("cosmetics").get("skins", {}).get(info["skin"], {})
	if sk.has("col"): col = int(sk["col"])
	return {"skin": info["skin"], "hat": info["hat"], "color": col}

func slot_fighter(s: int) -> FighterState:
	if s == my_slot: return sim.player
	return ghosts.get(s)

## netRemoveGhost: the slot is empty now.
func remove_ghost(s: int) -> void:
	var g: FighterState = ghosts.get(s)
	if g == null: return
	g.left = true; g.dead = true; g.hp = 0.0
	g.phys.place(0.0, -300.0, 0.0)
	ns.erase(s)

## netSlotChanged: a friend replaced a bot, or left. Returns the ghost whose look changed (or null).
func slot_changed(s: int, kind: String, info: Dictionary) -> FighterState:
	if s < 0 or s >= slots.size() or s == my_slot: return null
	info["kind"] = kind
	slots[s] = info
	var g: FighterState = ghosts.get(s)
	if g == null: return null
	g.net_human = kind == "human"
	if kind == "empty":
		remove_ghost(s); return g
	if g.left:
		g.left = false; g.dead = false; g.hp = combat.max_hp(g); ns.erase(s); g.weapon = ""; ghost_equip(g, "spatula")
	g.set_class(info["cls"], combat.classes.get(info["cls"], {}))
	g.name = info["name"]
	sim.looks[g] = look_of(info)
	combat.ev({"type": "toast", "text": info["name"] + (" joined!" if kind == "human" else " (bot) is back")})
	return g

# ============================== ghosts (ghostEquip / ghostFire) ==============================

func ghost_equip(g: FighterState, key: String) -> void:
	if key == "" or not combat.weapons_data.has(key): key = "spatula"
	if g.weapon == key: return
	g.slots = [{"key": key, "ammo": 999, "mag": -1, "pend": 0} if key != "spatula" else null, null, null]
	g.slot = 0 if key != "spatula" else -1
	combat.set_weapon(g, key)

func ghost_fire(g: FighterState, m: Dictionary) -> void:
	var key: Variant = m.get("w")
	if not (key is String) or key == "": return
	ghost_equip(g, key)
	var w := combat.wdata(key)
	if w.is_empty(): return
	g.cool = float(w.get("cooldown", 0.2)); g.draw = NetSnapshot.num(m.get("dr"), 0.0, 1.0, 0.0)
	if not sim.pickups.usable(key): return     # weapon types not ported yet: no replay (the hit still arrives as `h`)
	var t: String = w.get("type", "")
	if t == "gun": combat.weapons.fire_gun(g, key)
	elif Weapons.LAUNCH.has(t):
		if t == "bow": g.draw = maxf(0.5, g.draw if g.draw != 0.0 else 0.8)
		combat.weapons.call(Weapons.LAUNCH[t], g, key, [])

## The interpolation of netStep for one ghost: where it is drawn after this step.
## g = [x, y, z] now, s = the snapshot (x, y, z, vx, vy, vz, g), rt = clock when it arrived. Returns [x, y, z].
static func interp(g: Array, s: Dictionary, clock_now: float, rt: float, dt: float) -> Array:
	var age := minf(PREDICT_MAX, maxf(0.0, clock_now - rt))
	var tx: float = s["x"] + s["vx"] * age
	var tz: float = s["z"] + s["vz"] * age
	var ty: float = s["y"] + (0.0 if s["g"] else s["vy"] * age)
	var dx: float = tx - g[0]
	var dz: float = tz - g[2]
	var far := sqrt(dx * dx + dz * dz) > SNAP or absf(ty - g[1]) > SNAP
	var k := 1.0 if far else 1.0 - exp(-dt * EASE)
	return [g[0] + (tx - g[0]) * k, g[1] + (ty - g[1]) * k, g[2] + (tz - g[2]) * k]

# ============================== per step (netSnap / netStep) ==============================

## The fighters this side runs and reports (`S`, `sw`, `f`, `k`): the guest only its own; HostMatch adds the bots.
func owned() -> Array:
	return [sim.player]

## netSnap: what each fighter I run was doing before this step's input.
func pre_step() -> Array:
	var out: Array = []
	for f: FighterState in owned():
		out.append({"f": f, "pc": f.cool, "ps": f.swing, "pk": f.kick_t, "pd": f.draw})
	return out

## netStep: tell everyone what I just did, my `S` at 30 Hz, then move the ghosts toward their snapshots.
func post_controls(dt: float, pre: Variant) -> void:
	clock += dt
	_before_report(dt)
	if pre is Array: report(pre, dt)
	step_ghosts(dt)

## Hook for HostMatch (the host's end-of-match checks).
func _before_report(_dt: float) -> void:
	pass

## sw / f / k for what the owned fighters just started, and one `S` with all of them at 30 Hz.
func report(pre: Array, dt: float) -> void:
	for o: Dictionary in pre:
		var p: FighterState = o["f"]
		if p.dead or p.net_slot < 0: continue
		if o["ps"] < 0.0 and p.swing >= 0.0:
			_send({"t": "sw", "id": p.net_slot, "yaw": NetSnapshot.fixed(p.swing_yaw, 2), "w": p.weapon})
		elif o["pc"] <= 0.0 and p.cool > 0.0:
			_send({"t": "f", "id": p.net_slot, "w": p.weapon, "dr": NetSnapshot.fixed(o["pd"], 2)})
		if o["pk"] < 0.0 and p.kick_t >= 0.0:
			_send({"t": "k", "id": p.net_slot, "yaw": NetSnapshot.fixed(p.yaw, 2)})
	send_t -= dt
	if send_t <= 0.0:
		send_t += 1.0 / HZ
		if send_t < 0.0: send_t = 0.0
		var list: Array = []
		for o: Dictionary in pre:
			var p: FighterState = o["f"]
			if p.net_slot < 0: continue
			var c: Variant = sim.controllers.get(p)
			var sq := 1 if c != null and c.get("squat") else 0
			list.append(NetSnapshot.encode_entry(p, {"sq": sq}))
		if not list.is_empty(): _send(NetSnapshot.encode_state(list))

## The ghosts: replay swings, ease toward the last snapshot (netStep's ghost loop).
func step_ghosts(dt: float) -> void:
	for s: int in ghosts:
		var g: FighterState = ghosts[s]
		if g.left: continue
		if g.swing >= 0.0 and not g.dead:
			var key := g.weapon if combat.wdata(g.weapon).get("swingTime", 0) else "spatula"
			combat.melee_tick(g, key, dt, g.swing_yaw)
		var e: Variant = ns.get(s)
		if e == null: continue
		var ph := g.phys
		var at := interp([ph.px, ph.py, ph.pz], e, clock, e["rt"], dt)
		ph.px = at[0]; ph.py = at[1]; ph.pz = at[2]
		ph.vx = e["vx"]; ph.vy = 0.0; ph.vz = e["vz"]
		ph.wish_x = e["vx"] * 0.3; ph.wish_z = e["vz"] * 0.3
		ph.grounded = e["g"]
		(sim.controllers[g] as GhostControl).squat = e["sq"]
		g.hp = e["hp"]; g.invuln = 1.0 if e["iv"] else 0.0
		if combat.lives_mode != 0:
			g.lives = e["lv"]
			if e["el"] and not g.elim: g.elim = true; combat.ev({"type": "eliminated", "f": g})
			elif not e["el"] and g.elim: g.elim = false
		if g.swing < 0.0 and g.kick_t < 0.0: g.face_yaw = e["yaw"]
		g.aim_x = e["ax"]; g.aim_y = e["ay"]; g.aim_z = e["az"]
		if e["d"] and not g.dead:
			g.dead = true; g.hp = 0.0; g.fall_side = -1 if randf() < 0.5 else 1; g.down_t = 0.0; g.kick_t = -1.0; g.swing = -1.0
			ghost_equip(g, "spatula"); combat.set_weapon(g, ""); g.slot = -1
		elif not e["d"] and g.dead:
			g.dead = false; g.weapon = ""; ghost_equip(g, e["w"])
		if not g.dead: ghost_equip(g, e["w"])

func _send(m: Dictionary) -> void:
	sent_counts[m["t"]] = int(sent_counts.get(m["t"], 0)) + 1
	if send.is_valid(): send.call(m)

# ============================== incoming (netHandle) ==============================

func handle(m: Dictionary) -> void:
	var t: String = str(m.get("t", ""))
	recv_counts[t] = int(recv_counts.get(t, 0)) + 1
	var g: FighterState = ghosts.get(NetSnapshot.to_int32(m.get("id")))
	match t:
		"s":
			_snapshot(NetSnapshot.decode_entry(m))
		"S":
			for e: Dictionary in NetSnapshot.decode_state(m): _snapshot(e)
		"sw":
			if g != null and not g.dead and not g.left:
				ghost_equip(g, str(m.get("w", "")))
				var yaw := NetSnapshot.num(m.get("yaw"), -100.0, 100.0, g.yaw)
				g.face_yaw = yaw
				combat.melee_begin(g, g.weapon if combat.wdata(g.weapon).get("swingTime", 0) else "spatula", yaw)
		"f":
			if g != null and not g.dead and not g.left: ghost_fire(g, m)
		"k":
			if g != null and not g.dead and not g.left:
				var yaw := NetSnapshot.num(m.get("yaw"), -100.0, 100.0, g.yaw)
				g.face_yaw = yaw; combat.start_kick(g, yaw)
		"h":
			var h := NetSnapshot.decode_hit(m)
			if h.is_empty(): return
			var victim := slot_fighter(h["vs"])
			if victim == null or victim.is_ghost or victim.dead: return
			combat.net_apply = true
			combat.hit(victim, h["d"], h["x"], h["y"], h["z"], h["f"], h["hd"], slot_fighter(h["from"]))
			combat.net_apply = false
		"crate":
			sim.pickups.spawn_at(str(m.get("key", "")), m.get("spot"), NetSnapshot.to_int32(m.get("cid")))
		"crates":
			if m.get("list") is Array:
				for c: Variant in m["list"]:
					if c is Dictionary: sim.pickups.spawn_at(str(c.get("key", "")), c.get("spot"), NetSnapshot.to_int32(c.get("cid")))
		"take":
			sim.pickups.remove_cid(NetSnapshot.to_int32(m.get("cid")))
		"ko":
			var k := NetSnapshot.decode_ko(m)
			if k.is_empty(): return
			var vic := slot_fighter(k["to"])
			if vic == null or vic == sim.player or not vic.is_ghost: return
			var kil := slot_fighter(k["from"]) if k["from"] >= 0 else null
			if kil != null: combat.add_ko(kil, vic)
			else: combat.ev({"type": "ko", "killer": null, "victim": vic, "weapon": ""})
		"pend":
			var w := NetSnapshot.to_int32(m.get("w"))
			if not over:
				over = true; winner = w
				var f := slot_fighter(w)
				var nm := "You" if f == sim.player else (f.name if f else "?")
				if combat.teams and f != null and f.team >= 0:      # team modes: the side wins
					nm = "You" if f.team == sim.player.team else ("Blue team" if f.team == 0 else "Red team")
				combat.ev({"type": "match_end", "w": w, "name": nm})
		"gm":
			_mode_message(m)
		"emote":
			var e: Variant = m.get("e")
			if g != null and not g.dead and not g.left and e is String and not LockerData.emote(e).is_empty():
				combat.ev({"type": "emote", "f": g, "id": e})
		"slot":
			var info: Variant = m.get("info")
			if info is Dictionary:
				var s := NetSnapshot.to_int32(m.get("slot"))
				var kind: String = m.get("kind") if m.get("kind") in ["human", "bot", "empty"] else "empty"
				var g2 := slot_changed(s, kind, GuestSession.clean_info(info, s))
				if g2 != null: combat.ev({"type": "relook", "f": g2})

## `gm` from a Godot host: "st" = K.O.s / deaths / ladder rungs per slot and the Pillars clock (1 Hz), "cw" / "cs" /
## "ce" = a Chaos event warned / started (g = the giant's slot) / ended.
func _mode_message(m: Dictionary) -> void:
	var k := str(m.get("k", ""))
	match k:
		"st":
			for key: String in ["ko", "dt", "gg"]:
				var arr: Variant = m.get(key)
				if not (arr is Array): continue
				for s in mini((arr as Array).size(), slots.size()):
					var f := slot_fighter(s)
					if f == null: continue
					var v := maxi(0, NetSnapshot.to_int32(arr[s]))
					if key == "ko": f.ko = v
					elif key == "dt": f.st["deaths"] = v
					elif f.is_ghost: f.gg_rung = mini(v, ModeRules.GG.size() - 1)
			if m.has("pt") and not combat.rules.pil.is_empty():
				combat.rules.pil["t"] = NetSnapshot.num(m.get("pt"), 0.0, ModeRules.PIL_TIME, combat.rules.pil["t"])
		"cw", "cs", "ce":
			var giant := slot_fighter(NetSnapshot.to_int32(m.get("g"))) if m.has("g") else null
			var fl := str(m.get("fl", ""))
			combat.rules.chaos_remote(k, str(m.get("id", "")), fl if fl in ["quake", "wobble"] else "", giant, sim.dyn)

func _snapshot(e: Dictionary) -> void:
	if e.is_empty(): return
	var g: FighterState = ghosts.get(int(e["id"]))
	if g == null or g.left: return
	e["rt"] = clock
	ns[int(e["id"])] = e

## Combat events this side must tell the others about (the world drains them every frame).
func on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"net":
			_send(e["msg"])
		"crate_take":
			var c: Dictionary = e["crate"]
			if c.has("cid") and e.get("f") == sim.player: _send({"t": "take", "cid": c["cid"]})
