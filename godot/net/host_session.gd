class_name HostSession
extends GuestSession
## The HOST role of docs/PROTOCOL.md (Phase 2): connect -> (auth) -> create a room on the relay -> lobby (hello /
## welcome / roster, slots) -> start -> in-match relaying with the host's guard rules -> rematch votes -> leave.
## Ported from the web game's netHostSrv / hostRecv / netGuard / hostDrop / netStartHosted / netRematch* / ruleSnap /
## srvInfo (public/index.html ~8965-9480). Web and Godot guests are the same to it: they speak the same layer 2.
## Extends GuestSession so the title screen and the world can hold either one (`session`); the match itself runs in
## the world as a HostMatch (net/host_match.gd), which this session creates (make_match) and relays for.
## Rules (the Host sheet): mode, K.O. limit, health, gravity, knockback, crate rate, infinite ammo and the arena floor,
## sent in `start.rules` exactly as the web host's ruleSnap. Online modes: what the web host allows (netMode) plays for
## everybody; an app-only mode (NetMatch.GODOT_MODES: Team Deathmatch, Death Match, Sudden Death, Chaos, Pillars, Moon
## Drift, the team modes) plays when every guest is a Godot client (`gd` in hello) and goes out as `rules.gmode`
## (`mode` stays Classic for the web); with a web guest in the room the match plays Classic and the host is told, and
## a web guest cannot join an app-only match that is running (`kick` with the reason).
## Host migration (take_over): a Godot guest the relay promotes carries the running match on from its last state.

signal hosted(code: String)                  ## the room is open (code = room id)

const GUEST_MSGS := ["s", "S", "sw", "f", "k", "h", "ko", "take", "chat", "emote"]
const REMATCH_WAIT := 20.0
const CONNECT_WAIT := 8.0
const RESUME_WAIT := 3.0         ## host migration: seconds the new host waits for the guests' hello before resuming
const EMOTE_GAP := 0.4           ## seconds between two emotes of one guest
const NOCREATE_TEXT := {
	"auth": "Log in to host a room (or run the server with REQUIRE_LOGIN=0).",
	"inroom": "You're already in a room.",
	"busy": "The server is full right now. Try again in a moment.",
}
## Host sheet choices (the web settings' values).
const HPS := [100, 150, 200, 300, 500]
const GRAVS := [0.5, 1.0, 1.5]
const KBS := [0.5, 1.0, 1.5, 2.0, 3.0]
const CRATES := ["slow", "normal", "fast", "chaos"]

var pub := false
var opt_max := 4
var opt_bots := true             ## free seats get bots (and a bot takes the seat of a guest who leaves)
var bot_n := NET_MAX             ## how many of the free seats get a bot at Start (the rest stay empty for late joiners)
var opt_lim := -1                ## K.O. limit: -1 = the mode's own (Auto), 0 = none
var bhv := "brawl"
var diff := "normal"
var want_mode := "classic"       ## the host's pick (any online mode, app-only ones too)
var mode_id := "classic"         ## the mode the room plays: want_mode, or Classic when it is app-only and a web guest is in
var map_id := "arena"
var dyn_kind := "off"
var hp := 200
var grav := 1.0
var kb := 1.0
var crate := "normal"
var inf := false
var my_info := {}
var conns := {}                  ## slot -> server cid
var cid_slot := {}               ## server cid -> slot
var slots: Array = []            ## the running match's slots (HostMatch fills the bots in)
var limit := 0
var dseed := 0
var pp: Array = []               ## Pillars: the shuffled pillar of every slot (HostMatch makes it)
var rv := {}                     ## slot -> true: rematch votes
var rv_timer := -1.0
var guarded := 0                 ## guest messages dropped by the guard rules (tests read it)
var relayed := 0
var migrated := ""               ## host migration: the old host's name ("" = I opened this room)
var _match: WeakRef = null       ## the HostMatch of the running match
var _closing: Array = []         ## [seconds left, cid]: guests to remove after their last message
var _connect_t := 0.0
var _last_info := ""
var _emote_t := {}               ## slot -> clock of its last emote
var _resume := {}                ## host migration: the old match (NetMatch.capture_resume) until it is resumed
var _resume_t := -1.0
var _resume_slot := -1           ## my slot in the old match
var _start_x := {}               ## extra fields of the next `start` (rs / rsx after a migration)
var _dt0 := 0.0                  ## the arena clock the next match starts at (a resumed match)

## Start hosting. `opts`: name, pub, max (2..8 seats), bots (bool = every free seat / int = how many), lim (-1 auto),
## bhv, diff, mode, map, dyn, hp, grav, kb, crate, inf. `info` = {name, skin, hat, color, cls}.
## Returns false when it could not even start (no address).
func begin_host(p_url: String, opts: Dictionary, info: Dictionary, token: String = "") -> bool:
	url = p_url.strip_edges()
	if url == "":
		_finish("Enter a server address."); return false
	my_info = clean_info(info, 0)
	my_info["gd"] = NetClient.GD
	room_name = str(opts.get("name", "")).strip_edges().substr(0, 24)
	if room_name == "": room_name = my_info["name"] + "'s room"
	room_name = room_name.substr(0, 24)
	pub = bool(opts.get("pub", false))
	opt_max = clampi(int(opts.get("max", 4)), 2, NET_MAX)
	var b: Variant = opts.get("bots", true)
	bot_n = (NET_MAX if b else 0) if b is bool else clampi(int(b), 0, NET_MAX - 1)
	opt_bots = bot_n > 0
	bhv = "dummy" if opts.get("bhv") == "dummy" else "brawl"
	diff = str(opts.get("diff", "normal"))
	var m := str(opts.get("map", "arena"))
	map_id = m if data("maps").has(m) else "arena"
	set_rules(opts)
	net.player_name = my_info["name"]; net.token = token
	phase = Phase.CONNECTING
	_connect_t = CONNECT_WAIT
	_set_status("Connecting…")
	if net.connect_to_server(url) != OK:
		_finish("Couldn't open %s. Check the address and try again." % url); return false
	return true

## The rules part of the Host sheet (also between matches / in the lobby): mode, lim, hp, grav, kb, crate, inf, dyn.
## Keys left out keep their value. The next `start` uses them; the lobby hears the new roster.
func set_rules(opts: Dictionary) -> void:
	if opts.has("mode"): want_mode = online_mode(str(opts["mode"]))
	if opts.has("lim"): opt_lim = clampi(int(opts["lim"]), -1, 999)
	if opts.has("hp"): hp = int(opts["hp"]) if HPS.has(int(opts["hp"])) else 200
	if opts.has("grav"): grav = float(opts["grav"]) if GRAVS.has(float(opts["grav"])) else 1.0
	if opts.has("kb"): kb = float(opts["kb"]) if KBS.has(float(opts["kb"])) else 1.0
	if opts.has("crate"): crate = str(opts["crate"]) if CRATES.has(str(opts["crate"])) else "normal"
	if opts.has("inf"): inf = bool(opts["inf"])
	if opts.has("dyn"):
		var dk := str(opts["dyn"])
		dyn_kind = dk if Dynamics.KINDS.has(dk) else "off"
	if opts.has("map") and data("maps").has(str(opts["map"])): map_id = str(opts["map"])
	_refresh_mode()
	if phase == Phase.LOBBY and not started:
		_all(roster_msg())
		roster_changed.emit(roster)
	push_info()

func is_host() -> bool:
	return true

## netMode for the Godot host: modes the web game knows (shared modes.json), not team modes, not Sandbox /
## Construction, and not Pillars (its `pp` / `pt` are not hosted for the web); anything else plays Classic.
static func net_mode(m: String) -> String:
	var md: Dictionary = data("modes").get(m, {})
	if md.is_empty() or md.get("teams") or m in ["sandbox", "construction", "pillars"]: return "classic"
	return m

## Modes the Host sheet offers (ModeRules.PLAYABLE without the Practice Range).
static func online_modes() -> Array:
	var out: Array = []
	for m: String in ModeRules.PLAYABLE:
		if m != "practice" and all_modes().has(m): out.append(m)
	return out

static func online_mode(m: String) -> String:
	return m if online_modes().has(m) else "classic"

## Web clients cannot play it: it needs every guest on the app.
static func app_only(m: String) -> bool:
	return NetMatch.GODOT_MODES.has(m)

## shared/modes.json + the Godot-only modes.
static var _all_modes := {}
static func all_modes() -> Dictionary:
	if _all_modes.is_empty(): _all_modes = ModeRules.merge_extra(data("modes").duplicate(true))
	return _all_modes

static func mode_name(m: String) -> String:
	return str(all_modes().get(m, {}).get("name", "Classic"))

## Every guest in the room (lobby roster, or the humans of the running match) is a Godot client.
func web_guests() -> Array:
	var out: Array = []
	for r: Dictionary in roster:
		if int(r.get("id", -1)) != 0 and not r.has("gd"): out.append(str(r.get("name", "?")))
	return out

## The mode the next match plays: the pick, or Classic when it is app-only and a web guest is here.
func _refresh_mode() -> void:
	if started: return
	mode_id = want_mode if not app_only(want_mode) or web_guests().is_empty() else "classic"

## The K.O. limit a match of `m` plays to (0 in lives / ladder modes).
func eff_limit(m: String) -> int:
	var md: Dictionary = all_modes().get(m, {})
	if md.get("lives") or md.get("ladder"): return 0
	return opt_lim if opt_lim >= 0 else ModeRules.preset_limit(m, all_modes())

func poll(dt: float) -> void:
	if phase == Phase.IDLE or phase == Phase.CLOSED:
		return
	_clock += dt
	net.poll()
	if phase == Phase.CLOSED: return
	if phase == Phase.CONNECTING or phase == Phase.JOINING:
		_connect_t -= dt
		if _connect_t <= 0.0:
			_finish("The game server at %s didn't answer. Check the address and that the server is running." % url); return
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
	if _resume_t > 0.0:
		_resume_t -= dt
		if _resume_t <= 0.0: _resume_start()

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
		_finish("Couldn't reach the game server at %s. Check the address and that the server is running." % url)
	elif phase != Phase.CLOSED and phase != Phase.IDLE:
		_finish("Lost the connection to the game server. Try again in a moment.")

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
			_finish(NOCREATE_TEXT.get(str(m.get("reason", "")), "Couldn't open a room. Try again in a moment."))
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

# ============================== host migration ==============================

## The relay promoted guest `g` (`promoted`): this session takes its connection over and hosts the same room. `rs` =
## the running match as the guest saw it (NetMatch.capture_resume; {} = none): the guests say hello again (Godot ones
## with their old slot), then after RESUME_WAIT (or when every player is back) the match goes on from that state with
## a `start` carrying `rs`. The old host's seat goes to a bot (or stays empty). Room options come from the last roster
## and `start` the guest heard.
func take_over(g: GuestSession, pub_flag: bool, rs: Dictionary) -> void:
	for pair: Array in [[net.connected, _on_connected], [net.disconnected, _on_disconnected], [net.server_message, _on_server],
			[net.join_failed, _on_join_failed], [net.room_joined, _on_joined]]:
		if (pair[0] as Signal).is_connected(pair[1]): (pair[0] as Signal).disconnect(pair[1])
	var gn: NetClient = g.net
	for pair: Array in [[gn.connected, g._on_connected], [gn.disconnected, g._on_disconnected], [gn.server_message, g._on_server],
			[gn.join_failed, g._on_join_failed], [gn.room_joined, g._on_joined]]:
		if (pair[0] as Signal).is_connected(pair[1]): (pair[0] as Signal).disconnect(pair[1])
	net = gn
	net.connected.connect(_on_connected); net.disconnected.connect(_on_disconnected); net.server_message.connect(_on_server)
	net.join_failed.connect(_on_join_failed); net.room_joined.connect(_on_joined)
	url = g.url; room_code = g.room_code; room_name = g.room_name; pub = pub_flag
	migrated = g.old_host_name()
	my_info = clean_info({"name": net.player_name, "skin": net.skin, "hat": net.hat, "color": net.color, "cls": net.cls}, 0)
	my_info["gd"] = NetClient.GD
	var lb: Dictionary = g.lobby
	var st: Dictionary = g.start_msg
	var old_slots: Array = st.get("slots", [])
	opt_max = clampi(int(lb.get("max", maxi(old_slots.size(), 2))), 2, NET_MAX)
	opt_bots = bool(lb.get("bots", true)); bot_n = NET_MAX if opt_bots else 0
	bhv = str(lb.get("bhv", "brawl")); diff = str(lb.get("diff", "normal"))
	var r: Dictionary = st.get("rules", {})
	var rl: Dictionary = lb.get("rl", {})
	if r.is_empty(): r = rl
	if not old_slots.is_empty() and data("maps").has(str(st.get("map", ""))): map_id = str(st["map"])
	var wm: Variant = rl.get("want", r.get("gmode", r.get("mode", "classic")))
	set_rules({"mode": wm if wm is String else "classic", "hp": r.get("hp", 200), "grav": r.get("grav", 1), "kb": r.get("kb", 1),
		"crate": r.get("crate", "normal"), "inf": r.get("inf", false), "dyn": r.get("dyn", "off"), "lim": int(rl.get("lim", int(lb.get("lim", -1)) if lb.has("lim") else -1))})
	slot = 0; net.slot = 0; net.cid = 0; net.pslot = -1
	roster = [my_info.duplicate()]
	started = false; start_msg = {}
	phase = Phase.LOBBY
	_resume = rs
	_resume_slot = int(rs.get("my_slot", g.slot))
	if not rs.is_empty():
		_resume_t = RESUME_WAIT
		_set_status("%s left. You're now the host: carrying the match on…" % migrated)
	else:
		_set_status("%s left. You're now the host. " % migrated + ("The room is still open to everyone." if pub else "The room code is still %s." % room_code))
	_last_info = ""
	push_info()

## A promoted host waiting to carry the old match on.
func resuming() -> bool:
	return not _resume.is_empty()

## Old slot <-> new slot after a migration: I become slot 0, the old host's seat 0 becomes my old slot.
func _mig(k: int) -> int:
	if k == _resume_slot: return 0
	if k == 0: return _resume_slot
	return k

## Old human slots (not mine, not the old host's) still waiting for their player to say hello again.
func _resume_waiting() -> Array:
	var out: Array = []
	for k in (_resume.get("slots", []) as Array).size():
		var o: Dictionary = _resume["slots"][k]
		var j := _mig(k)
		if str(o.get("kind")) == "human" and k != 0 and k != _resume_slot and not conns.has(j): out.append(j)
	return out

## The seat a guest gets back after a migration: its old slot (`pslot`), else the old human seat with its name.
func _resume_seat(m: Dictionary, info: Dictionary) -> int:
	var old: Array = _resume.get("slots", [])
	var ps := NetSnapshot.to_int32(m.get("pslot")) if m.has("pslot") else -1
	if ps > 0 and ps < old.size() and ps != _resume_slot and str(old[ps].get("kind")) == "human" and not conns.has(_mig(ps)): return _mig(ps)
	for k in old.size():
		var j := _mig(k)
		if k != 0 and k != _resume_slot and str(old[k].get("kind")) == "human" and not conns.has(j) and str(old[k].get("name")) == str(info.get("name")): return j
	return -1

## Carry the old match on: same seats (players who came back, the old host's seat a bot or empty, the bots by name),
## same map, rules, arena seed and clock; `rs` puts everybody where they were.
func _resume_start() -> void:
	_resume_t = -1.0
	if _resume.is_empty() or started or phase != Phase.LOBBY: return
	var old: Array = _resume["slots"]
	var s: Array = []
	for j in old.size():
		var k := _mig(j)
		var o: Dictionary = old[k]
		if j == 0:
			var me := my_info.duplicate(); me["kind"] = "human"; s.append(me)
		elif conns.has(j):
			var h: Dictionary = {}
			for r: Dictionary in roster: if int(r["id"]) == j: h = r
			var x := h.duplicate(); x["kind"] = "human"; s.append(x)
		elif str(o.get("kind")) == "bot":
			var bi := (o as Dictionary).duplicate(); bi["kind"] = "bot"; bi["id"] = j; s.append(bi)
		elif opt_bots and str(o.get("kind")) == "human":
			s.append({"kind": "bot", "id": j, "name": "Bot", "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "wobbler"})
		else:
			s.append({"kind": "empty", "id": j, "name": "", "skin": "none", "hat": "none", "color": 0, "cls": "wobbler"})
	var rs: Array = []
	for e: Dictionary in _resume.get("l", []):
		var x: Dictionary = e.duplicate(); x["id"] = _mig(int(e["id"]))
		if x["id"] < s.size() and str(s[x["id"]]["kind"]) != "empty": rs.append(x)
	var r: Dictionary = _resume.get("rules", {})
	var sd: Variant = r.get("dseed")
	_start_x = {"rs": rs, "rsx": _resume.get("rsx", {})}
	_dt0 = float(_resume.get("dt0", 0.0))
	var keep_seed: int = int(sd) if (sd is float or sd is int) else -1
	_resume = {}
	_begin_match(s, keep_seed)

# ============================== hostRecv ==============================

func _to(cid: int, m: Dictionary) -> void:
	net.send_op({"op": "to", "cid": cid, "m": m})

## Every guest (except one server cid, 0 = nobody).
func _all(m: Dictionary, except: int = 0) -> void:
	net.send_op({"op": "all", "m": m, "except": except})

func _close_later(cid: int) -> void:
	_closing.append([0.4, cid])

func _cap() -> int:
	if not _resume.is_empty(): return maxi(NET_MAX, (_resume["slots"] as Array).size())
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
	var gd := NetSnapshot.to_int32(m.get("gd")) > 0
	var info := clean_info(m, 0)
	if gd: info["gd"] = NetClient.GD
	if started and not gd and app_only(mode_id):            # a web player cannot play an app-only mode
		_to(cid, {"t": "kick", "msg": "This room is playing %s, which only the Wobblers Arena app has. Ask the host to pick a Classic-style mode." % mode_label()})
		_close_later(cid)
		_set_status("%s tried to join from the web browser: %s is app-only." % [info["name"], mode_label()])
		return
	var id := _resume_seat(m, info) if not _resume.is_empty() else -1
	if id < 0:
		var reserved := _resume_waiting() if not _resume.is_empty() else []
		id = 1
		while id < _cap() and (conns.has(id) or reserved.has(id) or (started and id < slots.size() and str(slots[id].get("kind")) == "human")):
			id += 1
	if id >= _cap() or conns.has(id) or (not started and _resume.is_empty() and roster.size() >= opt_max):
		_to(cid, {"t": "full"}); _close_later(cid); return
	info["id"] = id
	conns[id] = cid; cid_slot[cid] = id
	roster.append(info)
	var w := {"t": "welcome", "id": id, "name": room_name, "pub": pub, "proto": NetClient.PROTO, "gd": NetClient.GD}
	if not _resume.is_empty(): w["rsm"] = 1                  # a Godot guest keeps its arena on screen until the `start`
	_to(cid, w)
	var hm := host_match()
	if started and hm != null:                     # joining a running match: a bot makes room
		hm.bot_to_human(id, info)
		slots = hm.slots
		_to(cid, {"t": "start", "slots": slots, "map": map_id, "custom": {}, "limit": limit, "rules": rule_snap(true)})
		_to(cid, {"t": "crates", "list": hm.crate_list()})
		_all({"t": "slot", "slot": id, "kind": "human", "info": slots[id]}, cid)
	else:
		_refresh_mode()
		_all(roster_msg())
		if not gd and app_only(want_mode):
			_set_status("%s joined from the web browser: %s is app-only, so the match plays Classic." % [info["name"], mode_name(want_mode)])
		else: _set_status("%s joined!" % info["name"])
	roster_changed.emit(roster)
	push_info()
	if not _resume.is_empty() and _resume_waiting().is_empty(): _resume_start()

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
		_refresh_mode()
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
		"emote":                                     # Godot-only: a known emote id, not too often
			var e: Variant = g.get("e")
			if not (e is String) or (e as String).length() > 24 or LockerData.emote(e).is_empty(): return {}
			if _clock - float(_emote_t.get(s, -10.0)) < EMOTE_GAP: return {}
			_emote_t[s] = _clock
			return {"t": "emote", "id": s, "e": e}
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

## srvInfo: what the room list shows (`mode` web-compatible, `modeName` the mode really played).
func srv_info() -> Dictionary:
	return {"name": room_name, "host": str(my_info.get("name", "?")), "mode": net_mode(mode_id), "modeName": mode_label(),
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
	return {"t": "info", "build": NetClient.BUILD, "name": room_name, "host": str(my_info.get("name", "?")), "mode": net_mode(mode_id),
		"modeName": mode_label(), "map": map_label(), "n": n, "max": slots.size() if started and not slots.is_empty() else opt_max,
		"started": started, "pub": pub}

func mode_label() -> String:
	return mode_name(mode_id)

func map_label() -> String:
	return str(data("maps").get(map_id, {}).get("name", map_id)).substr(0, 24)

## The rules as the lobby shows them (`rl` in roster, Godot-only): want (the pick), mode (what plays), lim (the
## limit it plays to), hp, grav, kb, crate, inf, dyn, map.
func rules_list() -> Dictionary:
	return {"want": want_mode, "mode": mode_id, "lim": eff_limit(mode_id), "hp": 300 if mode_id == "explosive" else hp,
		"grav": 0.15 if mode_id == "lowg" else grav, "kb": kb, "crate": crate, "inf": inf, "dyn": dyn_kind, "map": map_label()}

func roster_msg() -> Dictionary:
	return {"t": "roster", "roster": roster, "max": opt_max, "bots": opt_bots, "lim": eff_limit(mode_id), "bhv": bhv, "diff": diff,
		"modeName": mode_label(), "map": map_label(), "rl": rules_list()}

## One line for the lobby from a rules list (rules_list() / roster `rl`): "Team Deathmatch · first to 30 · 200 HP ·
## gravity 1x · knockback 1x · normal crates · floor Steady", plus why an app-only pick plays Classic.
static func rules_text(rl: Dictionary) -> String:
	if rl.is_empty(): return ""
	var m := str(rl.get("mode", "classic"))
	var lim := int(rl.get("lim", 0))
	var md: Dictionary = all_modes().get(m, {})
	var parts: Array = [mode_name(m)]
	if str(rl.get("map", "")) != "": parts.append(str(rl["map"]))
	if md.get("lives"): parts.append("one life" if int(md["lives"]) == 1 else "%d lives" % int(md["lives"]))
	elif md.get("ladder"): parts.append("12 weapons")
	else: parts.append(("first to %d" % lim) if lim > 0 else "no K.O. limit")
	parts.append("%d HP" % int(rl.get("hp", 200)))
	parts.append("gravity %sx" % _num(float(rl.get("grav", 1.0))))
	parts.append("knockback %sx" % _num(float(rl.get("kb", 1.0))))
	parts.append("%s crates" % str(rl.get("crate", "normal")))
	if bool(rl.get("inf", false)): parts.append("infinite ammo")
	parts.append("floor " + str(Dynamics.NAMES.get(str(rl.get("dyn", "off")), "Steady")))
	var t := " · ".join(parts)
	var want := str(rl.get("want", m))
	if want != m: t += "\n%s is app-only: a web player is here, so it plays Classic." % mode_name(want)
	return t

static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else str(v)

## ruleSnap: the rules every client plays by. `joiner` = for somebody joining mid-match (dt0 = the arena clock now).
## App-only modes add `gmode` (+ `gteam` sides, `pp` pillars); web clients read `mode` (Classic) and ignore the rest.
func rule_snap(joiner: bool = false) -> Dictionary:
	var r := {"mode": net_mode(mode_id), "hp": 300 if mode_id == "explosive" else hp, "crate": crate, "wstate": {},
		"grav": 0.15 if mode_id == "lowg" else grav, "kb": kb, "inf": inf, "dyn": dyn_kind}
	if app_only(mode_id):
		r["gmode"] = mode_id
		if all_modes().get(mode_id, {}).get("teams"):
			var tm: Array = []
			for k in maxi(slots.size(), opt_max): tm.append(k % 2)
			r["gteam"] = tm
		if mode_id == "pillars" and not pp.is_empty(): r["pp"] = pp.duplicate()
	if started: r["dseed"] = dseed
	if started and dyn_kind != "off":
		var hm := host_match()
		r["dt0"] = (roundf(maxf(0.0, hm.dyn_clock()) * 1000.0) / 1000.0) if joiner and hm != null else _dt0
	return r

# ============================== the match ==============================

func host_match() -> HostMatch:
	return _match.get_ref() as HostMatch if _match != null else null

## Start (host only, from the lobby): every seat up to the room size is a human, a bot or empty (netStartHosted).
func start_match() -> bool:
	if phase != Phase.LOBBY or started: return false
	_resume = {}; _resume_t = -1.0
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

## netStartMatch (host): a fresh arena seed (or `keep_seed` for a resumed match), the world builds the match from
## `start_msg` (match_started), then HostMatch.setup calls match_ready and the `start` goes out with the bots' names.
func _begin_match(s: Array, keep_seed: int = -1) -> void:
	rv.clear(); rv_list = []; rv_total = 0; voted = false; rv_timer = -1.0
	_refresh_mode()
	started = true
	phase = Phase.MATCH
	slots = s
	pp = []
	limit = eff_limit(mode_id)
	dseed = keep_seed if keep_seed >= 0 else randi()
	start_msg = {"slots": s, "map": map_id, "custom": {}, "limit": limit, "rules": rule_snap()}
	start_msg.merge(_start_x)
	_set_status("Match started" if _start_x.is_empty() else "You're the host now: the match goes on.")
	match_started.emit(start_msg)

## The world's HostMatch is set up: send the `start` (bots now have names) and refresh the room list.
func match_ready(hm: HostMatch) -> void:
	_match = weakref(hm)
	slots = hm.slots
	start_msg["slots"] = slots
	var r := rule_snap()
	start_msg["rules"] = r
	var m := {"t": "start", "slots": slots, "map": map_id, "custom": {}, "limit": limit, "rules": r}
	m.merge(_start_x)
	_start_x = {}; _dt0 = 0.0
	_all(m)
	push_info()

## Online match setup in the world: the mode and K.O. limit (configure), the host's random source seeded from the
## arena seed, then the rules every client plays by.
func prepare_sim(sim: MatchSim, start: Dictionary) -> void:
	sim.configure(mode_id, int(start.get("limit", 0)))
	super(sim, start)
	sim.combat.rng = CombatRng.new(int(dseed % 2147483646) + 1)
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

## netRematchStart: whoever did not vote leaves (a bot takes the seat), same people, fresh match. The mode follows the
## room again (set_rules between matches, a web guest who left).
func rematch_start() -> void:
	if not started: return
	var hm := host_match()
	if hm != null and not hm.over:
		rv_timer = 0.5; return                # my own match has not finished yet
	rv_timer = -1.0
	for i: int in human_slots():
		if i == 0 or rv.has(i) or not conns.has(i): continue
		var cid: int = conns[i]
		_to(cid, {"t": "kick", "msg": "You didn't click Rematch, so you left the room."})
		_drop(cid)
		_close_later(cid)
	var s: Array = []
	for k in slots.size():
		var sl: Dictionary = slots[k]
		var kind := str(sl.get("kind"))
		if kind == "human": s.append(sl.duplicate())
		elif kind == "empty": s.append({"kind": "empty", "id": k, "name": "", "skin": "none", "hat": "none", "color": 0, "cls": "wobbler"})
		else: s.append({"kind": "bot", "id": k, "name": "Bot", "skin": "none", "hat": "none", "color": 0x39b5a8, "cls": "wobbler"})
	started = false                           # the mode may change between matches (_refresh_mode)
	_begin_match(s)
