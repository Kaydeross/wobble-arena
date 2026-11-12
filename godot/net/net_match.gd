class_name NetMatch
extends RefCounted
## An online match (pure logic, no nodes). Ported from the web game's netStartMatch / makeGhost / ghostEquip /
## ghostFire / netHandle / netSnap / netStep (public/index.html ~8931-9120).
## Guest: local player simulates itself; every other slot is a ghost driven by `S` snapshots.
## Host (`is_host`): local player + bots simulate; human seats are ghosts; crates are owned here and broadcast.
## Hits on a ghost become `h` messages; `h` aimed at a fighter this side owns is applied through Combat.hit.
## Owned state goes out as `S` at 30 Hz, plus `sw`/`f`/`k`/`ko`/`take`/`crate` when they happen.
## MatchSim.step calls pre_step() / post_controls(); the world feeds handle() and on_event().

const HZ := 30.0
const PREDICT_MAX := 0.2         ## seconds a snapshot is carried forward
const EASE := 22.0               ## k = 1 - exp(-dt * EASE)
const SNAP := 6.0                ## metres: further off than this, jump straight there

## Squat flag holder so MatchSim's crouch easing works for ghosts (the web game reads g.squat).
class GhostControl:
	extends RefCounted
	var squat := false
	func think(_f: FighterState, _sim: MatchSim, _dt: float) -> void:
		pass

var sim: MatchSim
var combat: Combat
var send: Callable               ## func(m: Dictionary): room out (guest→host, or host→all / hit routing)
var my_slot := -1
var is_host := false
var slots: Array = []            ## cleaned start.slots
var ghosts := {}                 ## slot -> FighterState (remote humans; host also uses empty seats)
var ai := {}                     ## host only: slot -> bot FighterState this side simulates
var ns := {}                     ## slot -> last decoded `S` entry (+ "rt": clock when it arrived)
var clock := 0.0
var send_t := 0.0
var limit := 0
var over := false
var winner := -1
var sent_counts := {}            ## t -> how many sent (tests)
var recv_counts := {}            ## t -> how many handled (tests)
var host_session: HostSession = null   ## optional: crate cid bookkeeping + mid-match slot swaps

func _init(p_sim: MatchSim, p_send: Callable, p_slot: int, p_host: bool = false) -> void:
	sim = p_sim
	combat = p_sim.combat
	send = p_send
	my_slot = p_slot
	is_host = p_host

## Break the reference cycles with the sim.
func dispose() -> void:
	if sim: sim.net = null
	ghosts.clear(); ns.clear(); ai.clear()
	host_session = null
	sim = null; combat = null

# ============================== match setup (netStartMatch) ==============================

## Rules from `start.rules` onto Combat/physics before MatchSim.setup (setBotCfg with the host's values).
static func apply_rules(c: Combat, rules: Dictionary, host: bool = false) -> void:
	var mode: Variant = rules.get("mode")
	var md: Dictionary = c.modes.get(mode, {}) if mode is String else {}
	if md.is_empty() or md.get("teams") or mode == "sandbox" or mode == "construction": mode = "classic"   # netMode
	c.set_mode(mode)
	var hp := float(rules.get("hp", 100)) if (rules.get("hp") is float or rules.get("hp") is int) else 100.0
	c.hp_setting = hp if [100.0, 150.0, 200.0, 300.0, 500.0].has(hp) else 100.0
	var kb := float(rules.get("kb", 1)) if (rules.get("kb") is float or rules.get("kb") is int) else 1.0
	c.kb_setting = kb if [0.5, 1.0, 1.5, 2.0, 3.0].has(kb) else 1.0
	c.inf = bool(rules.get("inf", false))
	c.lives_mode = int(c.mode.get("lives", 0)) if c.mode.get("lives") else 0
	c.ffa = true
	c.net_started = true
	c.net_host = host

## Gravity setting from the rules (0.5 / 1 / 1.5, Low-G 0.15).
static func rule_grav(rules: Dictionary) -> float:
	var g := NetSnapshot.num(rules.get("grav"), 0.0, 10.0, 1.0)
	if [0.5, 1.0, 1.5].has(g) or (rules.get("mode") == "lowg" and is_equal_approx(g, 0.15)): return g
	return 1.0

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

## After MatchSim.setup: guest uses bot_count = 0 then ghosts; host uses bot_count = slots-1 then converts
## human/empty seats to ghosts (netStartMatch). Returns {FighterState: look} for the world to draw.
func setup(start: Dictionary) -> Dictionary:
	slots = start["slots"]
	limit = int(start.get("limit", 0))
	sim.net = self
	sim.pickups.remote = not is_host
	var grav := rule_grav(start.get("rules", {}))
	sim.player.net_slot = my_slot
	sim.player.phys.grav_scale = grav
	if is_host:
		return _setup_host(start, grav)
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
	return looks

## Host: MatchSim already built player + (slots-1) bots. Human seats become ghosts; bot seats stay in `ai`.
func _setup_host(start: Dictionary, grav: float) -> Dictionary:
	var looks := {}
	var bots: Array = []
	for f: FighterState in sim.fighters:
		if f != sim.player: bots.append(f)
	for s in range(1, slots.size()):
		var info: Dictionary = slots[s]
		var b: FighterState = bots[s - 1] if s - 1 < bots.size() else null
		if b == null:
			b = sim.add_fighter(info["cls"] if info["kind"] != "empty" else "wobbler")
			sim.controllers[b] = BotBrain.new(sim.difficulty, sim.diff)
		b.net_slot = s
		b.phys.grav_scale = grav
		if info["kind"] == "human":
			_make_ghost(b, s, info)
			looks[b] = sim.looks[b]
		elif info["kind"] == "empty":
			_make_ghost(b, s, {"name": "", "skin": "none", "hat": "none", "color": 0, "cls": "wobbler", "kind": "empty"})
			remove_ghost(s)
			looks[b] = sim.looks.get(b, {})
		else:
			b.is_ghost = false; b.net_human = false; b.left = false
			b.name = info["name"] if info["name"] != "" else "Bot"
			b.set_class(info["cls"], combat.classes.get(info["cls"], {}))
			var lk := look_of(info)
			sim.looks[b] = lk; looks[b] = lk
			ai[s] = b
	return looks

func _make_ghost(b: FighterState, s: int, info: Dictionary) -> void:
	b.is_ghost = true; b.left = false; b.net_slot = s; b.net_human = info.get("kind") == "human"
	b.name = info["name"] if info.get("name", "") != "" else "Player %d" % s
	b.set_class(str(info.get("cls", "wobbler")), combat.classes.get(str(info.get("cls", "wobbler")), {}))
	b.dead = false; b.hp = combat.max_hp(b); b.invuln = 0.0
	b.phys.can_climb = false
	sim.controllers[b] = GhostControl.new()
	b.weapon = ""; ghost_equip(b, "spatula")
	ghosts[s] = b
	ai.erase(s)
	sim.looks[b] = look_of(info)

static func look_of(info: Dictionary) -> Dictionary:
	var col: int = info["color"]
	var sk: Dictionary = GuestSession.data("cosmetics").get("skins", {}).get(info["skin"], {})
	if sk.has("col"): col = int(sk["col"])
	return {"skin": info["skin"], "hat": info["hat"], "color": col}

func slot_fighter(s: int) -> FighterState:
	if s == my_slot: return sim.player
	if ai.has(s): return ai[s]
	return ghosts.get(s)

## netRemoveGhost: the slot is empty now.
func remove_ghost(s: int) -> void:
	var g: FighterState = ghosts.get(s)
	if g == null: return
	g.left = true; g.dead = true; g.hp = 0.0
	g.phys.place(0.0, -300.0, 0.0)
	ns.erase(s)

## netSlotChanged: a friend replaced a bot, or left. Returns the fighter whose look changed (or null).
func slot_changed(s: int, kind: String, info: Dictionary) -> FighterState:
	if s < 0 or s >= slots.size() or s == my_slot: return null
	info["kind"] = kind
	slots[s] = info
	if is_host:
		return _host_slot_changed(s, kind, info)
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

## Host: friend takes a bot (netBotToHuman) or leaves (netHumanToBot / empty).
func _host_slot_changed(s: int, kind: String, info: Dictionary) -> FighterState:
	if kind == "human":
		var b: FighterState = ai.get(s, ghosts.get(s))
		if b == null: return null
		_make_ghost(b, s, info)
		combat.ev({"type": "toast", "text": info["name"] + " joined, a bot made room!"})
		return b
	var g: FighterState = ghosts.get(s)
	if g == null: return null
	if kind == "empty":
		remove_ghost(s); return g
	# bot returns: drop ghost, restore AI
	ghosts.erase(s); ns.erase(s)
	g.is_ghost = false; g.left = false; g.net_human = false
	g.set_class(info["cls"], combat.classes.get(info["cls"], {}))
	g.name = info["name"] if info["name"] != "" else "Bot"
	g.dead = false; g.hp = combat.max_hp(g)
	combat.clear_inventory(g); combat.set_weapon(g, "spatula")
	var brain := BotBrain.new(sim.difficulty, sim.diff)
	sim.controllers[g] = brain
	sim.looks[g] = look_of(info)
	ai[s] = g
	combat.ev({"type": "toast", "text": info["name"] + " (bot) is back"})
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

## netSnap: what each fighter this side runs was doing before this step's input.
## Guest: one Dictionary for the player. Host: Array of {f, pc, ps, pk, pd} (player + bots).
func pre_step() -> Variant:
	if is_host:
		var owned: Array = [{"f": sim.player, "pc": sim.player.cool, "ps": sim.player.swing, "pk": sim.player.kick_t, "pd": sim.player.draw}]
		for s: int in ai:
			var b: FighterState = ai[s]
			owned.append({"f": b, "pc": b.cool, "ps": b.swing, "pk": b.kick_t, "pd": b.draw})
		return owned
	var p := sim.player
	return {"pc": p.cool, "ps": p.swing, "pk": p.kick_t, "pd": p.draw}

## netStep: tell everyone what I just did, my `S` at 30 Hz, then move the ghosts toward their snapshots.
func post_controls(dt: float, pre: Variant) -> void:
	clock += dt
	if is_host and pre is Array:
		_host_actions(pre)
	else:
		var p := sim.player
		if pre is Dictionary and not p.dead:
			if pre["ps"] < 0.0 and p.swing >= 0.0:
				_send({"t": "sw", "id": my_slot, "yaw": NetSnapshot.fixed(p.swing_yaw, 2), "w": p.weapon})
			elif pre["pc"] <= 0.0 and p.cool > 0.0:
				_send({"t": "f", "id": my_slot, "w": p.weapon, "dr": NetSnapshot.fixed(pre["pd"], 2)})
			if pre["pk"] < 0.0 and p.kick_t >= 0.0:
				_send({"t": "k", "id": my_slot, "yaw": NetSnapshot.fixed(p.yaw, 2)})
	send_t -= dt
	if send_t <= 0.0:
		send_t += 1.0 / HZ
		if send_t < 0.0: send_t = 0.0
		if is_host and pre is Array:
			var list: Array = []
			for o: Dictionary in pre:
				var f: FighterState = o["f"]
				if f.net_slot < 0: continue
				var c: Variant = sim.controllers.get(f)
				var sq := 1 if c != null and c.get("squat") else 0
				list.append(NetSnapshot.encode_entry(f, {"sq": sq}))
			if list.size() > 0: _send(NetSnapshot.encode_state(list))
		else:
			var c2: Variant = sim.controllers.get(sim.player)
			var sq2 := 1 if c2 != null and c2.get("squat") else 0
			_send(NetSnapshot.encode_state([NetSnapshot.encode_entry(sim.player, {"sq": sq2})]))
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

func _host_actions(pre: Array) -> void:
	for o: Dictionary in pre:
		var f: FighterState = o["f"]
		var id := f.net_slot
		if f.dead or id < 0: continue
		if o["ps"] < 0.0 and f.swing >= 0.0:
			_send({"t": "sw", "id": id, "yaw": NetSnapshot.fixed(f.swing_yaw, 2), "w": f.weapon})
		elif o["pc"] <= 0.0 and f.cool > 0.0:
			_send({"t": "f", "id": id, "w": f.weapon, "dr": NetSnapshot.fixed(o["pd"], 2)})
		if o["pk"] < 0.0 and f.kick_t >= 0.0:
			_send({"t": "k", "id": id, "yaw": NetSnapshot.fixed(f.yaw, 2)})

func _send(m: Dictionary) -> void:
	sent_counts[m["t"]] = int(sent_counts.get(m["t"], 0)) + 1
	if send.is_valid(): send.call(m)

func _crate_spot(c: Dictionary) -> Array:
	var si = c.get("spot", -1)
	if si is int and si >= 0 and si < sim.pickups.spots.size():
		var sp: Array = sim.pickups.spots[si]
		return [sp[0], sp[1]]
	return [c["x"], c["z"]]

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
			if not is_host:
				sim.pickups.spawn_at(str(m.get("key", "")), m.get("spot"), NetSnapshot.to_int32(m.get("cid")))
		"crates":
			if not is_host and m.get("list") is Array:
				for c: Variant in m["list"]:
					if c is Dictionary: sim.pickups.spawn_at(str(c.get("key", "")), c.get("spot"), NetSnapshot.to_int32(c.get("cid")))
		"take":
			if is_host:
				# Guest already took it on their side; remove locally and the host broadcast already happened in host_recv.
				var cid := NetSnapshot.to_int32(m.get("cid"))
				if host_session: host_session.note_crate_gone(cid)
				sim.pickups.remove_cid(cid) if sim.pickups.find_cid(cid) >= 0 else _host_take_by_id(cid)
			else:
				sim.pickups.remove_cid(NetSnapshot.to_int32(m.get("cid")))
		"ko":
			var k := NetSnapshot.decode_ko(m)
			if k.is_empty(): return
			var vic := slot_fighter(k["to"])
			if vic == null or vic == sim.player: return
			if is_host and ai.has(k["to"]) and ai[k["to"]] == vic: return   # own bots already counted
			if not vic.is_ghost and not (is_host and ai.has(k["to"])): return
			var kil := slot_fighter(k["from"]) if k["from"] >= 0 else null
			if kil != null: combat.add_ko(kil, vic)
			else: combat.ev({"type": "ko", "killer": null, "victim": vic, "weapon": ""})
		"pend":
			var w := NetSnapshot.to_int32(m.get("w"))
			if not over:
				over = true; winner = w
				var f := slot_fighter(w)
				combat.ev({"type": "match_end", "w": w, "name": "You" if f == sim.player else (f.name if f else "?")})
		"slot":
			var info: Variant = m.get("info")
			if info is Dictionary:
				var s := NetSnapshot.to_int32(m.get("slot"))
				var kind: String = m.get("kind") if m.get("kind") in ["human", "bot", "empty"] else "empty"
				var g2 := slot_changed(s, kind, GuestSession.clean_info(info, s))
				if g2 != null: combat.ev({"type": "relook", "f": g2})

func _host_take_by_id(cid: int) -> void:
	# Host crates use `id` as the wire `cid` (see on_event); remove by id when `cid` field was never set.
	for i in range(sim.pickups.list.size() - 1, -1, -1):
		var p: Dictionary = sim.pickups.list[i]
		if int(p.get("cid", p.get("id", -1))) == cid:
			sim.pickups.list.remove_at(i)
			combat.ev({"type": "crate_gone", "crate": p})
			return

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
		"crate":
			if is_host:
				var c: Dictionary = e["crate"]
				if not c.has("cid"): c["cid"] = int(c["id"])
				if host_session: host_session.note_crate(int(c["cid"]))
				_send({"t": "crate", "cid": c["cid"], "key": c["key"], "spot": _crate_spot(c)})
		"crate_take":
			var c2: Dictionary = e["crate"]
			if is_host:
				var cid := int(c2.get("cid", c2.get("id", 0)))
				if cid > 0:
					if host_session: host_session.note_crate_gone(cid)
					_send({"t": "take", "cid": cid})
			elif c2.has("cid") and e.get("f") == sim.player:
				_send({"t": "take", "cid": c2["cid"]})
		"crate_gone":
			if is_host:
				var c3: Dictionary = e["crate"]
				var cid3 := int(c3.get("cid", c3.get("id", 0)))
				if host_session and cid3 > 0: host_session.note_crate_gone(cid3)
		"match_over":
			if is_host and not over:
				var w: Variant = e.get("winner")
				var wslot := my_slot
				var wname := "?"
				if w is FighterState:
					wslot = w.net_slot if w.net_slot >= 0 else my_slot
					wname = "You" if w == sim.player else w.name
				over = true; winner = wslot
				_send({"t": "pend", "w": wslot})
				combat.ev({"type": "match_end", "w": wslot, "name": wname})
