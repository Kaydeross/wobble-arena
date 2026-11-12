class_name HostSession
extends GuestSession
## The HOST role of docs/PROTOCOL.md (Phase 2): connect -> (auth) -> create a room on the relay -> lobby (hello /
## welcome / roster, slots) -> start -> in-match relaying with the host's guard rules -> rematch votes -> leave.
## Ported from the web game's netHostSrv / hostRecv / netGuard / hostDrop / netStartHosted / netRematch* / ruleSnap /
## srvInfo (public/index.html ~8965-9480). Web and Godot guests are the same to it: they speak the same layer 2.
## Extends GuestSession so the title screen and the world can hold either one (`session`); the match itself runs in
## the world as a HostMatch (net/host_match.gd), which this session creates (make_match) and relays for.
## Online modes: what the web host allows (netMode: team modes, Sandbox and Construction play Classic). Pillars needs
## the pillar shuffle (`pp`) and the clock, not hosted yet: it plays Classic too. Godot-only modes stay offline.

signal hosted(code: String)                  ## the room is open (code = room id)

const GUEST_MSGS := ["s", "S", "sw", "f", "k", "h", "ko", "take", "chat"]
const REMATCH_WAIT := 20.0
const CONNECT_WAIT := 8.0
const NOCREATE_TEXT := {
	"auth": "Log in to host a room (or run the server with REQUIRE_LOGIN=0).",
	"inroom": "You are already in a room.",
	"busy": "The server is full right now. Try again in a moment.",
}

var pub := false
var opt_max := 4
var opt_bots := true             ## free seats get bots (and a bot takes the seat of a guest who leaves)
var bot_n := NET_MAX             ## how many of the free seats get a bot at Start (the rest stay empty for late joiners)
var opt_lim := 0                 ## K.O. limit (0 = none)
var bhv := "brawl"
var diff := "normal"
var mode_id := "classic"         ## already through net_mode
var map_id := "arena"
var dyn_kind := "off"
var hp := 200
var my_info := {}
var conns := {}                  ## slot -> server cid
var cid_slot := {}               ## server cid -> slot
var slots: Array = []            ## the running match's slots (HostMatch fills the bots in)
var limit := 0
var dseed := 0
var rv := {}                     ## slot -> true: rematch votes
var rv_timer := -1.0
var guarded := 0                 ## guest messages dropped by the guard rules (tests read it)
var relayed := 0
var _match: WeakRef = null       ## the HostMatch of the running match
var _closing: Array = []         ## [seconds left, cid]: guests to remove after their last message
var _connect_t := 0.0
var _last_info := ""

## Start hosting. `opts`: name, pub, max (2..8 seats), bots (bool = every free seat / int = how many), lim, bhv, diff, mode, map, dyn, hp.
## `info` = {name, skin, hat, color, cls}. Returns false when it could not even start (no address).
func begin_host(p_url: String, opts: Dictionary, info: Dictionary, token: String = "") -> bool:
	url = p_url.strip_edges()
	if url == "":
		_finish("Enter a server address."); return false
	my_info = clean_info(info, 0)
	room_name = str(opts.get("name", "")).strip_edges().substr(0, 24)
	if room_name == "": room_name = my_info["name"] + "'s room"
	room_name = room_name.substr(0, 24)
	pub = bool(opts.get("pub", false))
	opt_max = clampi(int(opts.get("max", 4)), 2, NET_MAX)
	var b: Variant = opts.get("bots", true)
	bot_n = (NET_MAX if b else 0) if b is bool else clampi(int(b), 0, NET_MAX - 1)
	opt_bots = bot_n > 0
	opt_lim = maxi(0, int(opts.get("lim", 0)))
	bhv = "dummy" if opts.get("bhv") == "dummy" else "brawl"
	diff = str(opts.get("diff", "normal"))
	mode_id = net_mode(str(opts.get("mode", "classic")))
	var m := str(opts.get("map", "arena"))
	map_id = m if data("maps").has(m) else "arena"
	var dk := str(opts.get("dyn", "off"))
	dyn_kind = dk if Dynamics.KINDS.has(dk) else "off"
	var h := int(opts.get("hp", 200))
	hp = h if [100, 150, 200, 300, 500].has(h) else 200
	net.player_name = my_info["name"]; net.token = token
	phase = Phase.CONNECTING
	_connect_t = CONNECT_WAIT
	_set_status("Connecting…")
	if net.connect_to_server(url) != OK:
		_finish("Could not open %s" % url); return false
	return true

func is_host() -> bool:
	return true

## netMode for the Godot host: modes the web game knows (shared modes.json), not team modes, not Sandbox /
## Construction, and not Pillars yet; anything else plays Classic.
static func net_mode(m: String) -> String:
	var md: Dictionary = data("modes").get(m, {})
	if md.is_empty() or md.get("teams") or m in ["sandbox", "construction", "pillars"]: return "classic"
	return m

func poll(dt: float) -> void:
	if phase == Phase.IDLE or phase == Phase.CLOSED:
		return
	_clock += dt
	net.poll()
	if phase == Phase.CLOSED: return
	if phase == Phase.CONNECTING or phase == Phase.JOINING:
		_connect_t -= dt
		if _connect_t <= 0.0:
			_finish("The game server at %s did not answer. Check the address and that the server is running." % url); return
	for i in range(_closing.size() - 1, -1, -1):
		_closing[i][0] -= dt
		if _closing[i][0] <= 0.0:
			net.send_op({"op": "close", "cid": _closing[i][1]})
			_closing.remove_at(i)
	if rv_timer > 0.0:
		rv_timer -= dt
		if rv_timer <= 0.0:
			rv_timer = -1.0
			rematch_start()

# ============================== layer 1 ==============================

func _on_connected() -> void:
	if phase != Phase.CONNECTING: return
	phase = Phase.JOINING
	_connect_t = CONNECT_WAIT
	_set_status("Opening a room…")
	_last_info = JSON.stringify(srv_info())
	net.send_op({"op": "create", "pub": pub, "info": srv_info()})

func _on_disconnected() -> void:
	if phase == Phase.CONNECTING or phase == Phase.JOINING:
		_finish("Could not reach the game server at %s. Check the address and that the server is running." % url)
	elif phase != Phase.CLOSED and phase != Phase.IDLE:
		_finish("Lost the connection to the game server.")

func _on_joined(_id: String, _cid: int) -> void:
	pass

func _on_join_failed(_reason: String) -> void:
	pass

func _on_server(m: Dictionary) -> void:
	match str(m.get("op", "")):
		"created":
			if phase != Phase.JOINING: return
			room_code = str(m.get("id", ""))
			slot = 0; net.slot = 0
			roster = [my_info.duplicate()]
			phase = Phase.LOBBY
			_set_status(("Your room is open. It shows up in everyone's room list (%s)." if pub else "Room ready! Tell your friends the code: %s") % room_code)
			hosted.emit(room_code)
			roster_changed.emit(roster)
		"nocreate":
			_finish(NOCREATE_TEXT.get(str(m.get("reason", "")), "Could not open a room. Try again."))
		"peer":
			var cid := NetSnapshot.to_int32(m.get("cid"))
			if str(m.get("ev", "")) == "close": _drop(cid)
		"msg":
			if not m.has("from"): return             # the host only listens to guests
			var inner: Variant = m.get("m")
			if inner is Dictionary: _host_recv(NetSnapshot.to_int32(m["from"]), inner)
			else: guarded += 1
		"noauth":
			if net.token != "": _set_status("Your login expired. Log in again.")

# ============================== hostRecv ==============================

func _to(cid: int, m: Dictionary) -> void:
	net.send_op({"op": "to", "cid": cid, "m": m})

## Every guest (except one server cid, 0 = nobody).
func _all(m: Dictionary, except: int = 0) -> void:
	net.send_op({"op": "all", "m": m, "except": except})

func _close_later(cid: int) -> void:
	_closing.append([0.4, cid])

func _cap() -> int:
	return slots.size() if started and not slots.is_empty() else NET_MAX

func _host_recv(cid: int, m: Dictionary) -> void:
	var t: Variant = m.get("t")
	if not (t is String):
		guarded += 1; return
	if t == "info":
		_to(cid, room_info()); return
	if t == "hello":
		_hello(cid, m); return
	if not cid_slot.has(cid):
		guarded += 1; return
	var s: int = cid_slot[cid]
	if t == "rv":
		vote(s); return
	if t == "ping":
		_to(cid, {"t": "pong", "ts": m.get("ts")}); return
	var g := guard(m, s)
	if g.is_empty():
		guarded += 1; return
	relayed += 1
	if g["t"] == "h":
		var to := NetSnapshot.to_int32(g.get("to"))
		if to == 0: _handle(g)
		elif conns.has(to): _to(conns[to], g)
		return
	_handle(g)
	_all(g, cid)

func _handle(m: Dictionary) -> void:
	if started: match_message.emit(m)

func _hello(cid: int, m: Dictionary) -> void:
	if cid_slot.has(cid): return
	if m.has("proto") and NetSnapshot.to_int32(m["proto"]) != NetClient.PROTO:
		_to(cid, {"t": "badver"}); _close_later(cid); return
	var id := 1
	while id < _cap() and (conns.has(id) or (started and id < slots.size() and str(slots[id].get("kind")) == "human")):
		id += 1
	if id >= _cap() or conns.has(id) or (not started and roster.size() >= opt_max):
		_to(cid, {"t": "full"}); _close_later(cid); return
	var info := clean_info(m, id)
	conns[id] = cid; cid_slot[cid] = id
	roster.append(info)
	_to(cid, {"t": "welcome", "id": id, "name": room_name, "pub": pub, "proto": NetClient.PROTO})
	var hm := host_match()
	if started and hm != null:                     # joining a running match: a bot makes room
		hm.bot_to_human(id, info)
		slots = hm.slots
		_to(cid, {"t": "start", "slots": slots, "map": map_id, "custom": {}, "limit": limit, "rules": rule_snap(true)})
		_to(cid, {"t": "crates", "list": hm.crate_list()})
		_all({"t": "slot", "slot": id, "kind": "human", "info": slots[id]}, cid)
	else:
		_all(roster_msg())
		_set_status("%s joined!" % info["name"])
	roster_changed.emit(roster)
	push_info()

## hostDrop: a guest left (or was removed).
func _drop(cid: int) -> void:
	if not cid_slot.has(cid): return
	var id: int = cid_slot[cid]
	cid_slot.erase(cid); conns.erase(id)
	var who := ""
	for i in range(roster.size() - 1, -1, -1):
		if int(roster[i]["id"]) == id:
			who = roster[i]["name"]; roster.remove_at(i)
	rv.erase(id)
	var hm := host_match()
	if started and hm != null:
		var info := hm.human_to_bot(id, opt_bots)
		slots = hm.slots
		var kind := str(info.get("kind", "empty"))
		_all({"t": "slot", "slot": id, "kind": kind, "info": info})
		if who != "": hm.combat.ev({"type": "toast", "text": who + " left" + (", a bot took their place" if kind == "bot" else "")})
	else:
		_all(roster_msg())
	if who != "": _set_status("%s left." % who)
	roster_changed.emit(roster)
	push_info()

## netGuard: a guest may only speak for its own fighter. Returns the fixed message, or {} to drop it.
func guard(m: Dictionary, s: int) -> Dictionary:
	var t := str(m.get("t", ""))
	if not GUEST_MSGS.has(t): return {}
	var g := m.duplicate(true)
	match t:
		"s", "sw", "f", "k":
			g["id"] = s
		"chat":
			g["id"] = s
			g["txt"] = str(g.get("txt", "")).substr(0, 140)
		"S":
			if not (g.get("l") is Array): return {}
			var mine: Array = []
			for it: Variant in g["l"]:
				if it is Dictionary:
					var c: Dictionary = it
					c["id"] = s
					mine.append(c)
					break
			if mine.is_empty(): return {}
			g["l"] = mine
		"h":
			var h := NetSnapshot.decode_hit(g, s)
			if h.is_empty(): return {}
			h["d"] = NetSnapshot.fixed(h["d"], 2); h["hd"] = 1 if h["hd"] else 0
			return h
		"ko":
			if NetSnapshot.to_int32(g.get("to")) != s: return {}
		"take":
			var hm := host_match()
			if hm == null or not hm.has_crate(NetSnapshot.to_int32(g.get("cid"))): return {}
	return g

# ============================== messages the host builds ==============================

## srvInfo: what the room list shows.
func srv_info() -> Dictionary:
	return {"name": room_name, "host": str(my_info.get("name", "?")), "mode": mode_id, "modeName": mode_label(),
		"map": map_label(), "max": slots.size() if started and not slots.is_empty() else opt_max, "started": started,
		"build": NetClient.BUILD}

## netPushInfo: refresh the room-list entry when it changed.
func push_info() -> void:
	if phase < Phase.LOBBY or phase == Phase.CLOSED: return
	var i := srv_info()
	var s := JSON.stringify(i)
	if s == _last_info: return
	_last_info = s
	net.send_op({"op": "update", "info": i})

## roomInfo: the reply to `info` (peer-mode browsing).
func room_info() -> Dictionary:
	var n := 0
	if started:
		for x: Dictionary in slots: if x.get("kind") == "human": n += 1
	else: n = roster.size()
	return {"t": "info", "build": NetClient.BUILD, "name": room_name, "host": str(my_info.get("name", "?")), "mode": mode_id,
		"modeName": mode_label(), "map": map_label(), "n": n, "max": slots.size() if started and not slots.is_empty() else opt_max,
		"started": started, "pub": pub}

func mode_label() -> String:
	return str(data("modes").get(mode_id, {}).get("name", "Classic"))

func map_label() -> String:
	return str(data("maps").get(map_id, {}).get("name", map_id)).substr(0, 24)

func roster_msg() -> Dictionary:
	return {"t": "roster", "roster": roster, "max": opt_max, "bots": opt_bots, "lim": opt_lim, "bhv": bhv, "diff": diff,
		"modeName": mode_label(), "map": map_label()}

## ruleSnap: the rules every client plays by. `joiner` = for somebody joining mid-match (dt0 = the arena clock now).
func rule_snap(joiner: bool = false) -> Dictionary:
	var r := {"mode": mode_id, "hp": hp, "crate": "normal", "wstate": {}, "grav": 1, "kb": 1, "inf": false, "dyn": dyn_kind}
	if started: r["dseed"] = dseed
	if started and dyn_kind != "off":
		var hm := host_match()
		r["dt0"] = (roundf(maxf(0.0, hm.dyn_clock()) * 1000.0) / 1000.0) if joiner and hm != null else 0
	return r

# ============================== the match ==============================

func host_match() -> HostMatch:
	return _match.get_ref() as HostMatch if _match != null else null

## Start (host only, from the lobby): every seat up to the room size is a human, a bot or empty (netStartHosted).
func start_match() -> bool:
	if phase != Phase.LOBBY or started: return false
	var need := opt_max
	for r: Dictionary in roster: need = maxi(need, int(r["id"]) + 1)
	var s: Array = []
	var bots_left := bot_n
	for k in need:
		var h: Dictionary = {}
		for r: Dictionary in roster:
			if int(r["id"]) == k: h = r
		if not h.is_empty():
			var x := h.duplicate(); x["kind"] = "human"; s.append(x)
		else:
			bots_left -= 1
			s.append({"kind": "bot" if bots_left >= 0 else "empty", "id": k, "name": "Bot" if bots_left >= 0 else "", "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "wobbler"})
	_begin_match(s)
	return true

## netStartMatch (host): a fresh arena seed, the world builds the match from `start_msg` (match_started), then
## HostMatch.setup calls match_ready and the `start` goes out with the bots' names and looks.
func _begin_match(s: Array) -> void:
	rv.clear(); rv_list = []; rv_total = 0; voted = false; rv_timer = -1.0
	started = true
	phase = Phase.MATCH
	slots = s
	limit = 0 if (data("modes").get(mode_id, {}).get("lives") or data("modes").get(mode_id, {}).get("ladder")) else opt_lim
	dseed = randi()
	start_msg = {"slots": s, "map": map_id, "custom": {}, "limit": limit, "rules": rule_snap()}
	_set_status("Match started")
	match_started.emit(start_msg)

## The world's HostMatch is set up: send the `start` (bots now have names) and refresh the room list.
func match_ready(hm: HostMatch) -> void:
	_match = weakref(hm)
	slots = hm.slots
	start_msg["slots"] = slots
	var r := rule_snap()
	start_msg["rules"] = r
	_all({"t": "start", "slots": slots, "map": map_id, "custom": {}, "limit": limit, "rules": r})
	push_info()

## Online match setup in the world: the mode and K.O. limit (configure), then the rules every client plays by.
func prepare_sim(sim: MatchSim, start: Dictionary) -> void:
	sim.configure(mode_id, int(start.get("limit", 0)))
	super(sim, start)
	sim.combat.net_host = true
	sim.combat.brawl = bhv != "dummy"

func sim_bots(start: Dictionary) -> int:
	return maxi(0, (start.get("slots", []) as Array).size() - 1)

func make_match(sim: MatchSim) -> NetMatch:
	return HostMatch.new(sim, send, self)

## Out from the host's match: hits to the one guest who applies them (`to`), everything else to every guest.
func send(m: Dictionary) -> void:
	if phase < Phase.LOBBY or phase == Phase.CLOSED: return
	if record: sent.append(m)
	if m.get("t") == "h":
		var to := NetSnapshot.to_int32(m.get("to"))
		if conns.has(to): _to(conns[to], m)
		return
	_all(m)

# ============================== rematch ==============================

func human_slots() -> Array:
	var out: Array = []
	for k in slots.size():
		if str(slots[k].get("kind")) == "human": out.append(k)
	return out

func vote_rematch() -> void:
	if started and not voted:
		voted = true
		vote(0)

## netVote / netRematchCheck: everybody voted -> restart; else restart in 20 s anyway.
func vote(s: int) -> void:
	if not started: return
	rv[s] = true
	var hs := human_slots()
	rv_list = rv.keys(); rv_total = hs.size()
	_all({"t": "rvs", "list": rv_list, "total": rv_total})
	votes_changed.emit(rv_list, rv_total)
	var all_in := true
	for i: int in hs:
		if not rv.has(i): all_in = false
	if all_in: rematch_start()
	elif rv_timer < 0.0: rv_timer = REMATCH_WAIT

## netRematchStart: whoever did not vote leaves (a bot takes the seat), same people, fresh match.
func rematch_start() -> void:
	if not started: return
	var hm := host_match()
	if hm != null and not hm.over:
		rv_timer = 0.5; return                # my own match has not finished yet
	rv_timer = -1.0
	for i: int in human_slots():
		if i == 0 or rv.has(i) or not conns.has(i): continue
		var cid: int = conns[i]
		_to(cid, {"t": "kick", "msg": "You did not click Rematch, so you left the room."})
		_drop(cid)
		_close_later(cid)
	var s: Array = []
	for k in slots.size():
		var sl: Dictionary = slots[k]
		var kind := str(sl.get("kind"))
		if kind == "human": s.append(sl.duplicate())
		elif kind == "empty": s.append({"kind": "empty", "id": k, "name": "", "skin": "none", "hat": "none", "color": 0, "cls": "wobbler"})
		else: s.append({"kind": "bot", "id": k, "name": "Bot", "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "wobbler"})
	_begin_match(s)
