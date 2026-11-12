class_name HostMatch
extends NetMatch
## An online match seen from the HOST (pure logic, no nodes). Ported from the host half of the web game's
## netStartMatch / makeGhost / netBotToHuman / netHumanToBot / netSnap / netStep / netHandle (public/index.html ~9150-9380):
## - MatchSim.setup made one bot per slot after 0 (bots[k - 1] plays slot k); human slots turn their bot into a ghost
##   (moved by the guest's `S`), empty slots hide it, bot slots keep their BotBrain and are reported by the host;
## - the host's own fighter and every bot go out in one `S` at 30 Hz, plus `sw` / `f` / `k`;
## - crates are spawned here only and announced with a `cid` (`crate`), every take is told (`take`);
## - the K.O. limit / last one standing is decided here and sent as `pend`.
## HostSession (net/host_session.gd) guards and relays the guests' messages and feeds the allowed ones to handle().

const EMPTY_INFO := {"name": "", "skin": "none", "hat": "none", "color": 0xcccccc, "cls": "wobbler"}

var host: WeakRef                ## the HostSession
var ai := {}                     ## slot -> FighterState: bots this host runs
var brains := {}                 ## slot -> the bot's controller, kept while a guest plays that slot
var orig := {}                   ## slot -> {cls, name, look, dmg, speed}: the bot as MatchSim made it
var crate_id := 0
var n_comp := 0                  ## fighters in the match when it started (last-one-standing check)

func _init(p_sim: MatchSim, p_send: Callable, p_host: RefCounted) -> void:
	super(p_sim, p_send, 0)
	host = weakref(p_host)

func dispose() -> void:
	ai.clear(); brains.clear(); orig.clear()
	super()

func owned() -> Array:
	var out: Array = [sim.player]
	for s: int in ai:
		if not (ai[s] as FighterState).left: out.append(ai[s])
	return out

func slot_fighter(s: int) -> FighterState:
	if s == 0: return sim.player
	if ghosts.has(s): return ghosts[s]
	return ai.get(s)

## netStartMatch, host side. `start.slots` kinds: human (with info), bot, empty. Fills in the bots' names and looks
## (slots is what the `start` message carries) and tells the HostSession the match is ready.
func setup(start: Dictionary) -> Dictionary:
	slots = (start["slots"] as Array).duplicate(true)
	limit = int(start.get("limit", 0))
	sim.net = self
	sim.pickups.remote = false
	var grav := rule_grav(start.get("rules", {}))
	sim.player.net_slot = 0
	sim.player.phys.grav_scale = grav
	var looks := {}
	for k in range(1, slots.size()):
		if k >= sim.fighters.size(): break
		var b: FighterState = sim.fighters[k]
		b.net_slot = k
		b.phys.grav_scale = grav
		orig[k] = {"cls": b.class_id, "name": b.name, "look": sim.looks.get(b, {}).duplicate(), "dmg": b.dmg_scale, "speed": b.phys.speed}
		brains[k] = sim.controllers.get(b)
		var info: Dictionary = slots[k]
		match str(info.get("kind", "bot")):
			"human":
				looks[b] = _make_ghost(b, k, info)
			"empty":
				_make_ghost(b, k, EMPTY_INFO)
				remove_ghost(k)
				slots[k] = {"kind": "empty", "id": k, "name": "", "skin": "none", "hat": "none", "color": 0, "cls": "wobbler"}
			_:
				ai[k] = b
				slots[k] = bot_info(b, k)
	n_comp = 0
	for f: FighterState in sim.fighters:
		if not f.left: n_comp += 1
	var h: RefCounted = host.get_ref()
	if h != null: h.call("match_ready", self)
	return looks

## infoOfBot: what the slot list says about a bot.
func bot_info(b: FighterState, k: int) -> Dictionary:
	var lk: Dictionary = sim.looks.get(b, {})
	return {"kind": "bot", "id": k, "name": b.name, "skin": str(lk.get("skin", "none")), "hat": str(lk.get("hat", "none")),
		"color": int(lk.get("color", 0x39b5a8)), "cls": b.class_id if b.class_id != "" else "wobbler"}

## makeGhost: a bot's fighter becomes a guest's ghost. Returns its look.
func _make_ghost(b: FighterState, k: int, info: Dictionary) -> Dictionary:
	var cls: String = str(info.get("cls", "wobbler"))
	if not combat.classes.has(cls): cls = "wobbler"
	b.is_ghost = true; b.net_human = info != EMPTY_INFO; b.left = false; b.dead = false
	b.set_class(cls, combat.classes.get(cls, {}))
	b.hp = combat.max_hp(b); b.invuln = 0.0
	combat.clear_inventory(b)
	b.weapon = ""; ghost_equip(b, "spatula")
	b.name = str(info.get("name", "")) if str(info.get("name", "")) != "" else "Player %d" % k
	b.phys.can_climb = false
	b.elim = false; b.lives = combat.lives_mode
	sim.controllers[b] = GhostControl.new()
	ghosts[k] = b
	ai.erase(k)
	ns.erase(k)
	var lk := look_of({"skin": str(info.get("skin", "none")), "hat": str(info.get("hat", "none")), "color": int(info.get("color", 0x39b5a8))})
	sim.looks[b] = lk
	return lk

## netBotToHuman: a guest joined a running match and takes the place of bot `k` (or an empty seat).
func bot_to_human(k: int, info: Dictionary) -> FighterState:
	var b := slot_fighter(k)
	if b == null: return null
	var was_left := b.left
	_make_ghost(b, k, info)
	if was_left: _place(b)
	var s: Dictionary = info.duplicate()
	s["kind"] = "human"; s["id"] = k
	slots[k] = s
	combat.ev({"type": "relook", "f": b})
	combat.ev({"type": "toast", "text": str(info.get("name", "Player")) + " joined, a bot made room!"})
	return b

## netHumanToBot: the guest in slot `k` left; with `bots` on, the bot comes back, else the seat is emptied.
func human_to_bot(k: int, bots: bool) -> Dictionary:
	var g: FighterState = ghosts.get(k)
	if g == null: return slots[k] if k < slots.size() else {}
	if not bots:
		remove_ghost(k)
		slots[k] = {"kind": "empty", "id": k, "name": "", "skin": "none", "hat": "none", "color": 0, "cls": "wobbler"}
		return slots[k]
	ghosts.erase(k); ns.erase(k)
	var o: Dictionary = orig.get(k, {"cls": "wobbler", "name": "Bot", "look": {"skin": "none", "hat": "none", "color": 0xcccccc}, "dmg": 0.45, "speed": 4.4})
	g.is_ghost = false; g.net_human = false
	g.set_class(o["cls"], combat.classes.get(o["cls"], {}))
	g.name = o["name"]; g.dmg_scale = o["dmg"]; g.phys.speed = o["speed"]
	sim.looks[g] = (o["look"] as Dictionary).duplicate()
	combat.clear_inventory(g); combat.set_weapon(g, "spatula")
	if g.left:
		g.left = false; g.dead = false; g.hp = combat.max_hp(g); _place(g)
	if g.dead: g.death_t = 0.0
	sim.controllers[g] = brains.get(k) if brains.get(k) != null else GhostControl.new()
	ai[k] = g
	slots[k] = bot_info(g, k)
	combat.ev({"type": "relook", "f": g})
	return slots[k]

func _place(f: FighterState) -> void:
	var sp: Array = sim.map.get("spawns", [])
	var p: Array = sp[randi() % sp.size()] if sp.size() > 0 else [0, 0]
	combat.place_at(f, float(p[0]), float(p[1]), float(sim.map.get("spawnY", 0.01)))

## netStep's host check: in a lives mode, when players left and only one is still in, that one wins.
func _before_report(_dt: float) -> void:
	var r := combat.rules
	if combat.lives_mode == 0 or r.match_over or n_comp < 2: return
	var alive: Array = []
	for f: FighterState in sim.fighters:
		if not f.elim and not f.left: alive.append(f)
	if alive.size() <= 1:
		r.end_match(alive[0] if alive.size() > 0 else sim.player)

## A guest's message, already guarded and stamped by HostSession (netHandle on the host).
func handle(m: Dictionary) -> void:
	var t := str(m.get("t", ""))
	if t == "crate" or t == "crates" or t == "pend" or t == "slot": return    # only the host says these
	super(m)

## Combat events: the host's own messages (hits on ghosts, K.O.s of its bots), crates and the match end.
func on_event(e: Dictionary) -> void:
	match String(e["type"]):
		"net":
			_send(e["msg"])
		"crate":
			var c: Dictionary = e["crate"]
			if not c.has("cid") or int(c["cid"]) <= 0:
				crate_id += 1
				c["cid"] = crate_id
				_send({"t": "crate", "cid": crate_id, "key": c["key"], "spot": crate_spot(c)})
		"crate_take":
			var c2: Dictionary = e["crate"]
			var f: FighterState = e.get("f")
			if c2.has("cid") and f != null and not f.is_ghost: _send({"t": "take", "cid": c2["cid"]})
		"match_over":
			if not over:
				over = true
				var w: FighterState = e.get("winner")
				winner = w.net_slot if w != null and w.net_slot >= 0 else 0
				_send({"t": "pend", "w": winner})

## The crate's spot as the web game sends it (MAPS[map].drops entry: [x, z, floor y?]).
func crate_spot(c: Dictionary) -> Array:
	var si := int(c.get("spot", -1))
	var spots: Array = sim.pickups.spots
	if si >= 0 and si < spots.size(): return (spots[si] as Array).duplicate()
	return [NetSnapshot.fixed(float(c["x"]), 2), NetSnapshot.fixed(float(c["z"]), 2)]

## Crates on the map now (`crates`, for a guest joining mid-match).
func crate_list() -> Array:
	var out: Array = []
	for c: Dictionary in sim.pickups.list:
		if c.has("cid"): out.append({"cid": c["cid"], "key": c["key"], "spot": crate_spot(c)})
	return out

func has_crate(cid: int) -> bool:
	return sim != null and sim.pickups.find_cid(cid) >= 0

## Pillars clock etc. are not hosted yet; the dynamic-arena clock for a joiner (`dt0`).
func dyn_clock() -> float:
	return sim.dyn_clock() if sim != null else 0.0
