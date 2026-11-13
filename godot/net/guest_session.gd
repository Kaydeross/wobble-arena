class_name GuestSession
extends RefCounted
## The guest role of docs/PROTOCOL.md: connect -> (auth) -> join -> hello -> welcome -> roster/start/slot/crates ->
## in-match messages, plus ping/pong, rematch votes, kick/full/badver and host migration. Ported from the web game's
## netJoinSrv / srvRecv / clientRecv / netMigrate (public/index.html ~8701-9000).
## Lives across scenes (the title screen starts it, the world takes it over on `start`). Call poll(dt) every frame.
## In-match messages go out through `match_message`; the world's NetMatch handles them (netHandle).
## Host migration: `promoted` -> this client becomes the room's host (HostSession.take_over, `promoted` signal: the
## world / title swap their session) and carries the running match on from its last state; `rehost` -> say hello again
## with my old slot (`pslot`); a Godot new host that resumes the match says so in `welcome` (`rsm`), the world keeps
## showing the arena until the resumed `start` arrives, otherwise the old behaviour (back to the lobby).

signal status_changed(text: String)
signal welcomed(slot: int, room_name: String)
signal roster_changed(roster: Array)
signal match_started(start: Dictionary)      ## cleaned `start` (also on rematch and when joining a running match)
signal match_message(m: Dictionary)          ## S, sw, f, k, h, ko, crate, crates, take, pend, slot (only while started)
signal votes_changed(list: Array, total: int)
signal rehosted                              ## the host left, re-joining the new one: any running match is over
signal host_changing(old_host: String)       ## the host left; a new host may carry the match on (wait for `start`)
signal promoted(host: GuestSession)          ## I am the new host: `host` (a HostSession) replaces this session
signal ended(reason: String)                 ## the session is over (left, kicked, refused, connection lost)

enum Phase { IDLE, CONNECTING, JOINING, WAITING, LOBBY, MATCH, CLOSED }

const PING_EVERY := 1.5
const NET_MAX := 8
## What a guest may hear before `welcome` (clientRecv).
const BEFORE_WELCOME := ["welcome", "full", "badver", "kick"]
const NOJOIN_TEXT := {
	"auth": "Pick a name to play online (or run the server with REQUIRE_LOGIN=0).",
	"build": "That room is running a different version of the game.",
	"full": "That room is full.",
	"inroom": "You're already in a room.",
	"none": "No room with that code. Check the letters, and make sure the host still has the room open.",
}

var net := NetClient.new()
var phase := Phase.IDLE
var url := ""
var room_code := ""
var slot := -1
var room_name := ""
var roster: Array = []
var lobby := {}                  ## roster options: max, bots, lim, bhv, diff, modeName, map (+ rl: a Godot host's rules)
var host_gd := false             ## the host is a Godot client (`gd` in welcome)
## The world sets this while a match runs: returns NetMatch.capture_resume() (the state a promoted guest carries on).
var resume_provider: Callable
var started := false
var start_msg := {}              ## the last cleaned `start`
var status := ""
var end_reason := ""
var ping_ms := -1
var rv_list: Array = []
var rv_total := 0
var voted := false
var dropped := 0                 ## room messages refused (not from the host / before welcome / junk); tests read it
var sent: Array = []             ## when `record` is on: every room message sent (tests)
var record := false
var _ping_t := 0.0
var _build_retry := false
var _clock := 0.0
var _rehosting := false
var _rehost_t := 0.0
const REHOST_WAIT := 10.0

func _init() -> void:
	net.connected.connect(_on_connected)
	net.disconnected.connect(_on_disconnected)
	net.server_message.connect(_on_server)
	net.join_failed.connect(_on_join_failed)
	net.room_joined.connect(_on_joined)

func _on_joined(_id: String, _cid: int) -> void:
	phase = Phase.WAITING
	_set_status("Connected! Waiting for the host…")

## Start: `info` = {name, skin, hat, color, cls}; `token` from /api/login ("" = not logged in).
func begin(p_url: String, p_room: String, info: Dictionary, token: String = "") -> bool:
	url = p_url.strip_edges(); room_code = p_room.strip_edges()
	if url == "" or room_code == "":
		_finish("Enter a server address and a room code."); return false
	net.player_name = str(info.get("name", "Player")).substr(0, 12)
	net.skin = str(info.get("skin", "none")); net.hat = str(info.get("hat", "none"))
	net.color = int(info.get("color", 0x39b5a8)); net.cls = str(info.get("cls", ""))
	net.token = token
	phase = Phase.CONNECTING
	_set_status("Connecting…")
	if net.connect_to_server(url) != OK:
		_finish(tr("Couldn't open %s. Check the address and try again.") % url); return false
	return true

func is_active() -> bool:
	return phase != Phase.IDLE and phase != Phase.CLOSED

func poll(dt: float) -> void:
	if phase == Phase.IDLE or phase == Phase.CLOSED:
		return
	_clock += dt
	net.poll()
	if phase >= Phase.WAITING and phase != Phase.CLOSED:
		_ping_t -= dt
		if _ping_t <= 0.0:
			_ping_t = PING_EVERY
			if slot >= 0: send({"t": "ping", "ts": snappedf(_clock * 1000.0, 0.01)})
	if _rehosting:
		_rehost_t -= dt
		if _rehost_t <= 0.0:
			_rehosting = false; net.pslot = -1
			rehosted.emit()

## One room message to the host (tohost).
func send(m: Dictionary) -> void:
	if phase < Phase.WAITING or phase == Phase.CLOSED:
		return
	if record: sent.append(m)
	net.to_host(m)

func vote_rematch() -> void:
	if started and not voted:
		voted = true
		send({"t": "rv"})

## Leave the room on purpose (or because of `reason`): `leave` op, close the socket, `ended`.
func leave(reason: String = "You left the room.") -> void:
	_finish(reason)

func _finish(reason: String) -> void:
	if phase == Phase.CLOSED:
		return
	var was := phase
	phase = Phase.CLOSED
	started = false
	end_reason = reason
	if was >= Phase.WAITING: net.send_op({"op": "leave"})
	net.close()
	_set_status(reason)
	ended.emit(reason)

func _set_status(t: String) -> void:
	status = t
	status_changed.emit(t)

# ============================== the world's hooks ==============================

func is_host() -> bool:
	return false

## Online match setup in the world (before MatchSim.setup): the host's rules and dynamic arena from `start`.
func prepare_sim(sim: MatchSim, start: Dictionary) -> void:
	NetMatch.apply_rules(sim.combat, start.get("rules", {}))
	var rd := NetMatch.rule_dyn(start.get("rules", {}))
	sim.dyn_choice = rd["choice"]; sim.dyn_seed = rd["seed"]; sim.dyn_t0 = rd["t0"]

## Bots MatchSim.setup creates: none on a guest (the host runs them, they are ghosts here).
func sim_bots(_start: Dictionary) -> int:
	return 0

## The world's NetMatch for this match (HostSession returns a HostMatch).
func make_match(sim: MatchSim) -> NetMatch:
	return NetMatch.new(sim, send, slot)

# ============================== layer 1 ==============================

func _on_connected() -> void:
	if phase != Phase.CONNECTING: return
	phase = Phase.JOINING
	_set_status(tr("Joining %s…") % room_code)
	net.join_room(room_code)

func _on_disconnected() -> void:
	if phase == Phase.CONNECTING:
		_finish(tr("Couldn't reach the game server at %s. Check the address and that the server is running.") % url)
	elif phase != Phase.CLOSED and phase != Phase.IDLE:
		_finish("Lost the connection to the game server. Try again in a moment.")

func _on_join_failed(reason: String) -> void:
	# The server compares `build` strings; the web game bumps NET_BUILD every release while the room protocol stays
	# `proto: 1` (PROTOCOL.md 6.1: build is informational). Retry once without a build: the host's hello check decides.
	if reason == "build" and not _build_retry:
		_build_retry = true
		net.join_room(room_code, "")
		return
	_finish(tr(NOJOIN_TEXT[reason]) if NOJOIN_TEXT.has(reason) else tr("Couldn't join the room (%s). Try again.") % reason)

func _on_server(m: Dictionary) -> void:
	match str(m.get("op", "")):
		"msg":
			if m.has("from"):              # only the host ever gets `from`: not addressed to a guest, never trusted
				dropped += 1; return
			var inner: Variant = m.get("m")
			if inner is Dictionary: _on_room(inner)
			else: dropped += 1
		"kicked":
			_finish("You were removed from the room.")
		"hostgone":
			_finish("The host left the room.")
		"promoted":
			_promote(bool(m.get("pub", false)))
		"rehost":
			_rehost()
		"noauth":
			if net.token != "": _set_status("Your login expired. Log in again.")

## netMigrate(false): the host left, another guest hosts now. Say hello to the new host (with my old slot); the
## running match waits for its `welcome` (a resuming Godot host) or ends (`rehosted`).
func _rehost() -> void:
	if phase < Phase.WAITING or phase == Phase.CLOSED:
		return
	var old := old_host_name()
	net.pslot = slot if started else -1
	slot = -1; net.slot = -1; started = false; roster = []; voted = false; rv_list = []; rv_total = 0; host_gd = false
	phase = Phase.WAITING
	net.send_hello()
	_set_status(tr("%s left. Joining the new host…") % old)
	_rehosting = true; _rehost_t = REHOST_WAIT
	host_changing.emit(old)

func old_host_name() -> String:
	for r: Dictionary in roster:
		if int(r.get("id", -1)) == 0: return str(r["name"])
	var sl: Array = start_msg.get("slots", [])
	if sl.size() > 0: return str(sl[0].get("name", "The host"))
	return "The host"

## netMigrate(true): the relay made me the host. A HostSession takes the connection (and the running match's state)
## over; this session closes without leaving the room.
func _promote(pub_flag: bool) -> void:
	if phase < Phase.WAITING or phase == Phase.CLOSED:
		return
	var rs: Dictionary = {}
	if started and resume_provider.is_valid():
		var v: Variant = resume_provider.call()
		if v is Dictionary: rs = v
	var hs: GuestSession = load("res://net/host_session.gd").new()
	hs.call("take_over", self, pub_flag, rs)
	phase = Phase.CLOSED
	started = false
	promoted.emit(hs)

# ============================== layer 2 (clientRecv) ==============================

func _on_room(m: Dictionary) -> void:
	var t: Variant = m.get("t")
	if not (t is String):
		dropped += 1; return
	if slot < 0 and not BEFORE_WELCOME.has(t):   # nothing counts until the host has welcomed me
		dropped += 1; return
	match t:
		"welcome":
			if slot >= 0: return
			if m.has("proto") and NetSnapshot.to_int32(m["proto"]) != NetClient.PROTO:
				_finish("That room is running a different version of the game."); return
			var id := NetSnapshot.to_int32(m.get("id"))
			if id < 1 or id >= NET_MAX:
				dropped += 1; return
			slot = id; net.slot = id
			room_name = str(m.get("name", "")).substr(0, 24)
			host_gd = NetSnapshot.to_int32(m.get("gd")) > 0
			phase = Phase.LOBBY
			_set_status(tr("In room \"%s\" as player %d. Waiting for the host to start…") % [room_name, slot])
			welcomed.emit(slot, room_name)
			if _rehosting:
				_rehosting = false; net.pslot = -1
				if host_gd and NetSnapshot.to_int32(m.get("rsm")) > 0:
					_set_status("The new host is carrying the match on…")
				else:
					start_msg = {}
					rehosted.emit()
		"roster":
			if not (m.get("roster") is Array): return
			roster = []
			for r: Variant in (m["roster"] as Array).slice(0, NET_MAX):
				var d: Dictionary = r if r is Dictionary else {}
				roster.append(clean_info(d, NetSnapshot.to_int32(d.get("id"))))
			if m.get("max"):
				lobby = {"max": NetSnapshot.to_int32(m["max"]), "bots": bool(m.get("bots")), "lim": NetSnapshot.to_int32(m.get("lim")),
					"bhv": "dummy" if m.get("bhv") == "dummy" else "brawl", "diff": str(m.get("diff", "normal")),
					"modeName": str(m.get("modeName", "")).substr(0, 24), "map": str(m.get("map", "")).substr(0, 24)}
				if m.get("rl") is Dictionary: lobby["rl"] = m["rl"]
			roster_changed.emit(roster)
		"full":
			_finish("That room is full.")
		"badver":
			_finish("That room is running a different version of the game.")
		"kick":
			_finish(str(m.get("msg", "You were removed from the room.")).substr(0, 200))
		"rvs":
			rv_list = m.get("list") if m.get("list") is Array else []
			rv_total = NetSnapshot.to_int32(m.get("total"))
			votes_changed.emit(rv_list, rv_total)
		"start":
			var s := clean_start(m, slot)
			if s.is_empty():
				dropped += 1; return
			_rehosting = false
			started = true; start_msg = s; voted = false; rv_list = []; rv_total = 0
			phase = Phase.MATCH
			_set_status("Match started")
			match_started.emit(s)
		"pong":
			var ts := NetSnapshot.num(m.get("ts"), 0.0, 1e12, -1.0)
			if ts >= 0.0: ping_ms = maxi(0, roundi(_clock * 1000.0 - ts))
		"chat":
			pass                           # chat is off on this client (iOS ships without it)
		_:
			if started: match_message.emit(m)

# ============================== cleaning (cleanInfo) ==============================

## cleanInfo: a player's name/outfit/hat/colour/class, junk replaced by defaults.
static func clean_info(m: Dictionary, id: int) -> Dictionary:
	var cos: Dictionary = data("cosmetics")
	var skin: Variant = m.get("skin")
	var hat: Variant = m.get("hat")
	var col := NetSnapshot.to_int32(m.get("color"))
	var cls: Variant = m.get("cls")
	return {"id": id, "name": (str(m["name"]) if m.get("name") else "Player").substr(0, 12),
		"skin": skin if skin is String and cos.get("skins", {}).has(skin) else "none",
		"hat": hat if hat is String and cos.get("hats", []).has(hat) else "none",
		"color": col if cos.get("swatch", []).has(float(col)) or cos.get("swatch", []).has(col) else 0x39b5a8,
		"cls": cls if cls is String and data("classes").has(cls) else "wobbler"}.merged({"gd": 1} if NetSnapshot.to_int32(m.get("gd")) > 0 else {})

## A `start` checked and cleaned: {slots[{kind, id, name, skin, hat, color, cls}], map, custom, limit, rules}.
## {} = unusable (no slots, or my slot is not in it).
static func clean_start(m: Dictionary, my_slot: int) -> Dictionary:
	var raw: Variant = m.get("slots")
	if not (raw is Array) or raw.size() < 2 or raw.size() > NET_MAX or my_slot < 0 or my_slot >= raw.size():
		return {}
	var slots: Array = []
	for i in raw.size():
		var d: Dictionary = raw[i] if raw[i] is Dictionary else {}
		var kind: String = d.get("kind") if d.get("kind") in ["human", "bot", "empty"] else "empty"
		var info := clean_info(d, i)
		if kind == "bot" and not d.get("name"): info["name"] = "Bot"
		info["kind"] = kind
		slots.append(info)
	var map_id: Variant = m.get("map")
	return {"slots": slots, "map": map_id if map_id is String and data("maps").has(map_id) else "arena",
		"custom": m.get("custom") if m.get("custom") is Dictionary else {}, "limit": maxi(0, NetSnapshot.to_int32(m.get("limit"))),
		"rules": m.get("rules") if m.get("rules") is Dictionary else {}, "rs": m.get("rs") if m.get("rs") is Array else null,
		"rsx": m.get("rsx") if m.get("rsx") is Dictionary else {}}

## res://data/<name>.json, read once (static: the net code also runs in headless tests before autoloads exist).
static var _data := {}
static func data(file_name: String) -> Dictionary:
	if not _data.has(file_name):
		var v: Variant = Combat.read_json("res://data/%s.json" % file_name)
		_data[file_name] = v if v is Dictionary else {}
	return _data[file_name]
