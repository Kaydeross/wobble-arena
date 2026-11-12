class_name HostSession
extends RefCounted
## The host role of docs/PROTOCOL.md over the existing WebSocket relay (server.js is a post office, not a game
## server). Ported from the web game's netHostSrv / hostRecv / hostDrop / netGuard / netStartHosted /
## netVote / netRematch* (public/index.html ~8975–9480).
## Same surface as GuestSession so the title screen and world can drive either: begin → lobby → start_match →
## in-match relay, plus poll/send/leave/vote_rematch. Guests join with GuestSession (or the browser); this
## client assigns slots, runs bots (via NetMatch.is_host), validates guest messages and broadcasts.

signal status_changed(text: String)
signal welcomed(slot: int, room_name: String)   ## host is always slot 0; fired once the room exists
signal roster_changed(roster: Array)
signal match_started(start: Dictionary)
signal match_message(m: Dictionary)             ## guest traffic that NetMatch must apply locally
signal votes_changed(list: Array, total: int)
signal rehosted                                 ## unused as host; kept for world signal wiring
signal ended(reason: String)
signal guest_joined(slot: int, info: Dictionary) ## mid-match: a friend took a bot's place
signal guest_left(slot: int, kind: String)       ## mid-match: human → bot or empty

enum Phase { IDLE, CONNECTING, CREATING, LOBBY, MATCH, CLOSED }

const NET_MAX := 8
const GUEST_MSGS := ["s", "S", "sw", "f", "k", "h", "ko", "take", "chat"]
const NOCREATE_TEXT := {
	"auth": "Log in to host a room (or run the server with REQUIRE_LOGIN=0).",
	"inroom": "You are already in a room.",
	"busy": "The server is full right now. Try again in a moment.",
}

var net := NetClient.new()
var phase := Phase.IDLE
var url := ""
var room_code := ""
var slot := 0                    ## host is always game slot 0
var room_name := ""
var pub := false
var roster: Array = []           ## cleaned {id,name,skin,hat,color,cls}, host is roster[0]
var lobby := {}                  ## max, bots, lim, bhv, diff, modeName, map
var started := false
var start_msg := {}
var status := ""
var end_reason := ""
var rv_list: Array = []
var rv_total := 0
var voted := false
var dropped := 0
var sent: Array = []
var record := false
## Server connection id → game slot (after hello). Open peers waiting for hello are in pending_peers.
var peers := {}                  ## server_cid -> true (open)
var slot_of := {}                ## server_cid -> game slot
var cid_of := {}                 ## game slot -> server_cid
var pending_peers: Array = []    ## server cids that have not said hello yet
var slots: Array = []            ## last start.slots (kind per seat)
var opt_max := 4
var opt_bots := true
var opt_lim := 0
var bhv := "brawl"
var diff := "normal"
var map_id := "arena"
var mode_id := "classic"
var hp := 200.0
var crate := "normal"
var grav := 1.0
var kb := 1.0
var inf := false
var dyn_kind := "off"
var crate_cids: Array = []       ## host-owned pickup cids currently on the floor (netGuard take)
var _rv := {}                    ## slot -> true (rematch votes)
var _rv_t := -1.0                ## countdown to force rematch; <0 = idle
var _clock := 0.0
var _has_crate: Callable = Callable()   ## optional: func(cid) -> bool from the live match

func _init() -> void:
	net.connected.connect(_on_connected)
	net.disconnected.connect(_on_disconnected)
	net.server_message.connect(_on_server)
	net.room_created.connect(_on_created)
	net.create_failed.connect(_on_create_failed)

## Start hosting. `info` = {name, skin, hat, color, cls}; `opts` may set pub, room_name, max, bots, lim, bhv,
## diff, map, mode, hp, crate, grav, kb, inf, dyn.
func begin(p_url: String, info: Dictionary, token: String = "", opts: Dictionary = {}) -> bool:
	url = p_url.strip_edges()
	if url == "":
		_finish("Enter a server address."); return false
	net.player_name = str(info.get("name", "Player")).substr(0, 12)
	net.skin = str(info.get("skin", "none")); net.hat = str(info.get("hat", "none"))
	net.color = int(info.get("color", 0x39b5a8)); net.cls = str(info.get("cls", ""))
	net.token = token
	pub = bool(opts.get("pub", false))
	room_name = str(opts.get("room_name", net.player_name + "'s room")).substr(0, 24)
	opt_max = clampi(int(opts.get("max", 4)), 2, NET_MAX)
	opt_bots = bool(opts.get("bots", true))
	opt_lim = maxi(0, int(opts.get("lim", 0)))
	bhv = "dummy" if opts.get("bhv") == "dummy" else "brawl"
	diff = str(opts.get("diff", "normal"))
	map_id = str(opts.get("map", "arena"))
	mode_id = str(opts.get("mode", "classic"))
	hp = float(opts.get("hp", 200))
	crate = str(opts.get("crate", "normal"))
	grav = float(opts.get("grav", 1))
	kb = float(opts.get("kb", 1))
	inf = bool(opts.get("inf", false))
	dyn_kind = str(opts.get("dyn", "off"))
	roster = [GuestSession.clean_info(net.hello_info(), 0)]
	lobby = _lobby_fields()
	phase = Phase.CONNECTING
	_set_status("Connecting…")
	if net.connect_to_server(url) != OK:
		_finish("Could not open %s" % url); return false
	return true

func is_active() -> bool:
	return phase != Phase.IDLE and phase != Phase.CLOSED

func is_host() -> bool:
	return true

func poll(dt: float) -> void:
	if phase == Phase.IDLE or phase == Phase.CLOSED:
		return
	_clock += dt
	net.poll()
	if _rv_t >= 0.0:
		_rv_t -= dt
		if _rv_t <= 0.0:
			_rv_t = -1.0
			_rematch_start()

## Room message to every guest (hostOut for non-hit). Hits use send_hit.
func send(m: Dictionary) -> void:
	if phase < Phase.LOBBY or phase == Phase.CLOSED:
		return
	if record: sent.append(m)
	if str(m.get("t", "")) == "h":
		send_hit(m)
	else:
		net.to_all(m)

func send_hit(m: Dictionary) -> void:
	var to := NetSnapshot.to_int32(m.get("to"))
	if cid_of.has(to):
		net.to_guest(int(cid_of[to]), m)
	elif to == 0:
		match_message.emit(m)   # a guest hit a bot: apply locally

func vote_rematch() -> void:
	if started and not voted:
		voted = true
		_vote(0)

func leave(reason: String = "You left the room.") -> void:
	_finish(reason)

## Host presses Start (netStartHosted). Builds slots, emits match_started, broadcasts `start`.
func start_match() -> Dictionary:
	if phase != Phase.LOBBY or started:
		return {}
	var need := maxi(opt_max, _roster_span())
	need = clampi(need, 2, NET_MAX)
	var built: Array = []
	for k in need:
		var h: Variant = _roster_at(k)
		if h != null:
			var info: Dictionary = h.duplicate()
			info["kind"] = "human"
			built.append(info)
		else:
			built.append({"kind": "bot" if opt_bots else "empty", "id": k, "name": "Bot" if opt_bots else "",
				"skin": "none", "hat": "none", "color": 0 if not opt_bots else 0xf08a3c, "cls": "wobbler"})
	var rules := rule_snap()
	var s := {"slots": built, "map": map_id if GuestSession.data("maps").has(map_id) else "arena",
		"custom": {}, "limit": opt_lim, "rules": rules}
	# Fill bot looks from clean_info so guests accept them.
	for i in s["slots"].size():
		var sl: Dictionary = s["slots"][i]
		if sl["kind"] != "human":
			var cleaned := GuestSession.clean_info(sl, i)
			cleaned["kind"] = sl["kind"]
			if sl["kind"] == "bot" and cleaned["name"] == "Player": cleaned["name"] = "Bot"
			if sl["kind"] == "empty": cleaned["name"] = ""; cleaned["color"] = 0
			s["slots"][i] = cleaned
	slots = s["slots"]
	started = true; start_msg = s; voted = false; _rv.clear(); rv_list = []; rv_total = 0; _rv_t = -1.0
	phase = Phase.MATCH
	_set_status("Match started")
	_push_info()
	net.to_all({"t": "start", "slots": slots, "map": s["map"], "custom": {}, "limit": opt_lim, "rules": rules})
	match_started.emit(s)
	return s

## Rematch with the same seats (non-voters kicked). Call when the match is over.
func rematch() -> Dictionary:
	if phase != Phase.MATCH:
		return {}
	_rematch_start()
	return start_msg

func set_crate_check(cb: Callable) -> void:
	_has_crate = cb

func note_crate(cid: int) -> void:
	if cid > 0 and not crate_cids.has(cid): crate_cids.append(cid)

func note_crate_gone(cid: int) -> void:
	crate_cids.erase(cid)

func _finish(reason: String) -> void:
	if phase == Phase.CLOSED:
		return
	var was := phase
	phase = Phase.CLOSED
	started = false
	end_reason = reason
	if was >= Phase.CREATING: net.send_op({"op": "leave"})
	net.close()
	_set_status(reason)
	ended.emit(reason)

func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)

func _lobby_fields() -> Dictionary:
	var md: Dictionary = GuestSession.data("modes").get(mode_id, {})
	var mp: Dictionary = GuestSession.data("maps").get(map_id, {})
	return {"max": opt_max, "bots": opt_bots, "lim": opt_lim, "bhv": bhv, "diff": diff,
		"modeName": str(md.get("name", mode_id)).substr(0, 24), "map": str(mp.get("name", map_id)).substr(0, 24)}

func rule_snap() -> Dictionary:
	var mode := mode_id
	var modes: Dictionary = GuestSession.data("modes")
	var md: Dictionary = modes.get(mode, {})
	if md.is_empty() or md.get("teams") or mode == "sandbox" or mode == "construction":
		mode = "classic"
	var g := grav
	if not ([0.5, 1.0, 1.5].has(g) or (mode == "lowg" and is_equal_approx(g, 0.15))): g = 1.0
	var k := kb
	if not [0.5, 1.0, 1.5, 2.0, 3.0].has(k): k = 1.0
	var h := hp
	if not [100.0, 150.0, 200.0, 300.0, 500.0].has(h): h = 100.0
	var dyn := dyn_kind if Dynamics.KINDS.has(dyn_kind) else "off"
	var seed := int(randi()) & 0xFFFFFFFF
	return {"mode": mode, "hp": h, "crate": crate, "wstate": {}, "grav": g, "kb": k, "inf": inf,
		"dyn": dyn, "dseed": seed, "dt0": 0.0}

func room_info() -> Dictionary:
	return {"name": room_name, "host": roster[0]["name"] if roster.size() > 0 else "?",
		"mode": mode_id, "modeName": lobby.get("modeName", mode_id), "map": lobby.get("map", ""),
		"max": slots.size() if started and slots.size() > 0 else opt_max, "started": started, "build": NetClient.BUILD}

func _push_info() -> void:
	net.update_info(room_info())

func _roster_msg() -> Dictionary:
	lobby = _lobby_fields()
	return {"t": "roster", "roster": roster, "max": opt_max, "bots": opt_bots, "lim": opt_lim, "bhv": bhv,
		"diff": diff, "modeName": lobby["modeName"], "map": lobby["map"]}

func _roster_at(id: int) -> Variant:
	for r: Dictionary in roster:
		if int(r["id"]) == id: return r
	return null

func _roster_span() -> int:
	var n := 1
	for r: Dictionary in roster:
		n = maxi(n, int(r["id"]) + 1)
	return n

func _slot_cap() -> int:
	return slots.size() if started and slots.size() > 0 else NET_MAX

# ============================== layer 1 ==============================

func _on_connected() -> void:
	if phase != Phase.CONNECTING: return
	phase = Phase.CREATING
	_set_status("Opening room…")
	net.create_room(pub, room_info())

func _on_disconnected() -> void:
	if phase == Phase.CONNECTING:
		_finish("Could not reach the game server at %s." % url)
	elif phase != Phase.CLOSED and phase != Phase.IDLE:
		_finish("Lost the connection to the game server.")

func _on_created(id: String, p_pub: bool) -> void:
	room_code = id; pub = p_pub; slot = 0; net.slot = 0
	phase = Phase.LOBBY
	_set_status(("Your room is open. It shows up in everyone's room list." if pub
		else "Room ready! Tell your friend the code %s." % id))
	roster_changed.emit(roster)
	welcomed.emit(0, room_name)

func _on_create_failed(reason: String) -> void:
	_finish(NOCREATE_TEXT.get(reason, "Could not open a room (%s)." % reason))

func _on_server(m: Dictionary) -> void:
	match str(m.get("op", "")):
		"peer":
			var cid := NetSnapshot.to_int32(m.get("cid"))
			if m.get("ev") == "open":
				peers[cid] = true
				if not pending_peers.has(cid): pending_peers.append(cid)
			else:
				_peer_close(cid)
		"msg":
			if not m.has("from"):
				dropped += 1; return
			var from := NetSnapshot.to_int32(m.get("from"))
			var inner: Variant = m.get("m")
			if inner is Dictionary: _host_recv(from, inner)
			else: dropped += 1
		"noauth":
			if net.token != "": _set_status("Your login expired. Log in again.")

func _peer_close(server_cid: int) -> void:
	peers.erase(server_cid)
	pending_peers.erase(server_cid)
	if not slot_of.has(server_cid):
		return
	var sid: int = slot_of[server_cid]
	slot_of.erase(server_cid); cid_of.erase(sid)
	var left_name := ""
	for r: Dictionary in roster:
		if int(r["id"]) == sid: left_name = r["name"]
	roster = roster.filter(func(r: Dictionary) -> bool: return int(r["id"]) != sid)
	if started:
		var kind := "bot" if opt_bots else "empty"
		if sid >= 0 and sid < slots.size():
			if opt_bots:
				slots[sid] = GuestSession.clean_info({"name": "Bot", "skin": "none", "hat": "none", "color": 0xf08a3c, "cls": "wobbler"}, sid)
				slots[sid]["kind"] = "bot"
			else:
				slots[sid] = {"kind": "empty", "id": sid, "name": "", "skin": "none", "hat": "none", "color": 0, "cls": "wobbler"}
			net.to_all({"t": "slot", "slot": sid, "kind": kind, "info": slots[sid]})
			guest_left.emit(sid, kind)
		_set_status(("%s left, a bot took their place" if opt_bots else "%s left") % (left_name if left_name != "" else "A player"))
	else:
		net.to_all(_roster_msg())
		roster_changed.emit(roster)
		if left_name != "": _set_status("%s left" % left_name)

# ============================== layer 2 (hostRecv) ==============================

func _host_recv(server_cid: int, m: Dictionary) -> void:
	var t: Variant = m.get("t")
	if not (t is String):
		dropped += 1; return
	if t == "info":
		net.to_guest(server_cid, room_info()); return
	if t == "hello":
		_on_hello(server_cid, m); return
	if not slot_of.has(server_cid):
		dropped += 1; return
	var sid: int = slot_of[server_cid]
	if t == "rv":
		_vote(sid); return
	if t == "ping":
		net.to_guest(server_cid, {"t": "pong", "ts": m.get("ts")}); return
	var guarded := net_guard(m, sid)
	if guarded.is_empty():
		dropped += 1; return
	if guarded["t"] == "take":
		var cid := NetSnapshot.to_int32(guarded.get("cid"))
		var ok := crate_cids.has(cid)
		if not ok and _has_crate.is_valid(): ok = bool(_has_crate.call(cid))
		if not ok:
			dropped += 1; return
		note_crate_gone(cid)
	if guarded["t"] == "h":
		var to := NetSnapshot.to_int32(guarded.get("to"))
		if to == 0:
			match_message.emit(guarded)
		elif cid_of.has(to):
			net.to_guest(int(cid_of[to]), guarded)
		return
	match_message.emit(guarded)
	net.to_all(guarded, server_cid)

func _on_hello(server_cid: int, m: Dictionary) -> void:
	var proto_ok := true
	if m.has("proto"):
		proto_ok = NetSnapshot.to_int32(m["proto"]) == NetClient.PROTO
	elif m.get("build") and str(m["build"]) != NetClient.BUILD:
		proto_ok = false
	if not proto_ok:
		net.to_guest(server_cid, {"t": "badver"})
		net.close_guest(server_cid)
		return
	var id := 1
	while id < _slot_cap() and (_slot_taken(id) or (started and id < slots.size() and slots[id].get("kind") == "human")):
		id += 1
	if id >= _slot_cap() or _slot_taken(id) or (started and id >= slots.size()):
		net.to_guest(server_cid, {"t": "full"})
		net.close_guest(server_cid)
		return
	var info := GuestSession.clean_info(m, id)
	slot_of[server_cid] = id; cid_of[id] = server_cid
	pending_peers.erase(server_cid)
	roster.append(info)
	net.to_guest(server_cid, {"t": "welcome", "id": id, "name": room_name, "pub": pub, "proto": NetClient.PROTO})
	if started:
		slots[id] = info.duplicate(); slots[id]["kind"] = "human"
		net.to_guest(server_cid, {"t": "start", "slots": slots, "map": start_msg.get("map", map_id),
			"custom": start_msg.get("custom", {}), "limit": start_msg.get("limit", 0), "rules": start_msg.get("rules", {})})
		var crates: Array = []
		for c: int in crate_cids: crates.append({"cid": c})   # world may enrich; empty list is fine
		# Live crate list is pushed by NetMatch after bind; a mid-join still gets start.
		net.to_all({"t": "slot", "slot": id, "kind": "human", "info": info}, server_cid)
		guest_joined.emit(id, info)
		_set_status("%s joined, a bot made room!" % info["name"])
	else:
		net.to_all(_roster_msg())
		roster_changed.emit(roster)
		_set_status("%s joined!" % info["name"])

func _slot_taken(id: int) -> bool:
	return cid_of.has(id) or (id == 0)

func _vote(sid: int) -> void:
	if not started: return
	_rv[sid] = true
	rv_list = _rv.keys()
	rv_total = _human_slots().size()
	net.to_all({"t": "rvs", "list": rv_list, "total": rv_total})
	votes_changed.emit(rv_list, rv_total)
	var hs := _human_slots()
	var all := true
	for h: int in hs:
		if not _rv.has(h): all = false; break
	if all:
		_rematch_start()
	elif _rv_t < 0.0:
		_rv_t = 20.0

func _human_slots() -> Array:
	var out: Array = []
	if not started: return out
	for i in slots.size():
		if slots[i].get("kind") == "human": out.append(i)
	return out

func _rematch_start() -> void:
	if not started or phase != Phase.MATCH:
		return
	_rv_t = -1.0
	for i in _human_slots():
		if i == 0 or _rv.has(i): continue
		if cid_of.has(i):
			var c: int = cid_of[i]
			net.to_guest(c, {"t": "kick", "msg": "You did not click Rematch, so you left the room."})
			net.close_guest(c)
			_peer_close(c)
	_rv.clear(); voted = false; rv_list = []; rv_total = 0
	var rebuilt: Array = []
	for k in slots.size():
		var sl: Dictionary = slots[k]
		if sl.get("kind") == "human":
			rebuilt.append(sl)
		elif sl.get("kind") == "empty":
			rebuilt.append({"kind": "empty", "id": k, "name": "", "skin": "none", "hat": "none", "color": 0, "cls": "wobbler"})
		else:
			var b := GuestSession.clean_info({"name": "Bot", "skin": "none", "hat": "none", "color": 0xf08a3c, "cls": "wobbler"}, k)
			b["kind"] = "bot"; rebuilt.append(b)
	slots = rebuilt
	start_msg = {"slots": slots, "map": start_msg.get("map", map_id), "custom": start_msg.get("custom", {}),
		"limit": start_msg.get("limit", opt_lim), "rules": rule_snap()}
	crate_cids.clear()
	net.to_all({"t": "start", "slots": slots, "map": start_msg["map"], "custom": start_msg["custom"],
		"limit": start_msg["limit"], "rules": start_msg["rules"]})
	match_started.emit(start_msg)

## netGuard: stamp the guest's slot, clamp hits, drop host-only types. {} = drop.
static func net_guard(m: Dictionary, guest_slot: int) -> Dictionary:
	var t: Variant = m.get("t")
	if not (t is String) or not GUEST_MSGS.has(t):
		return {}
	var out: Dictionary = m.duplicate(true)
	match t:
		"s":
			out["id"] = guest_slot
		"S":
			if not (out.get("l") is Array): return {}
			var mine: Array = []
			for it: Variant in out["l"]:
				if it is Dictionary:
					var one: Dictionary = it.duplicate()
					one["id"] = guest_slot
					mine.append(one)
					break
			if mine.is_empty(): return {}
			out["l"] = mine
		"sw", "f", "k", "chat":
			out["id"] = guest_slot
		"h":
			var hit := NetSnapshot.decode_hit(out, guest_slot)
			if hit.is_empty(): return {}
			out = hit
		"ko":
			var ko := NetSnapshot.decode_ko(out, guest_slot)
			if ko.is_empty(): return {}
			out = ko
		"take":
			pass   # cid checked by the live match via HostSession when wired; still stamp nothing
	return out
