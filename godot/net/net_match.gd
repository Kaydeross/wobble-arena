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
	c.net_host = false

## Gravity setting from the rules (0.5 / 1 / 1.5, Low-G 0.15).
static func rule_grav(rules: Dictionary) -> float:
	var g := NetSnapshot.num(rules.get("grav"), 0.0, 10.0, 1.0)
	if [0.5, 1.0, 1.5].has(g) or (rules.get("mode") == "lowg" and is_equal_approx(g, 0.15)): return g
	return 1.0

## After MatchSim.setup(.., bot_count = 0): my slot on the player, a ghost for every other slot (human, bot or empty).
## Returns {FighterState: look} for the world to draw.
func setup(start: Dictionary) -> Dictionary:
	slots = start["slots"]
	limit = int(start.get("limit", 0))
	sim.net = self
	sim.pickups.remote = true
	var grav := rule_grav(start.get("rules", {}))
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
	return looks

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
	elif Weapons.LAUNCH.has(t): combat.weapons.call(Weapons.LAUNCH[t], g, key)

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

## netSnap: what my fighter was doing before this step's input.
func pre_step() -> Dictionary:
	var p := sim.player
	return {"pc": p.cool, "ps": p.swing, "pk": p.kick_t, "pd": p.draw}

## netStep: tell everyone what I just did, my `S` at 30 Hz, then move the ghosts toward their snapshots.
func post_controls(dt: float, pre: Variant) -> void:
	clock += dt
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
		var c: Variant = sim.controllers.get(p)
		var sq := 1 if c != null and c.get("squat") else 0
		_send(NetSnapshot.encode_state([NetSnapshot.encode_entry(p, {"sq": sq})]))
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
				combat.ev({"type": "match_end", "w": w, "name": "You" if f == sim.player else (f.name if f else "?")})
		"slot":
			var info: Variant = m.get("info")
			if info is Dictionary:
				var s := NetSnapshot.to_int32(m.get("slot"))
				var kind: String = m.get("kind") if m.get("kind") in ["human", "bot", "empty"] else "empty"
				var g2 := slot_changed(s, kind, GuestSession.clean_info(info, s))
				if g2 != null: combat.ev({"type": "relook", "f": g2})

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
