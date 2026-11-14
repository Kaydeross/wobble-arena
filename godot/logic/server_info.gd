class_name ServerInfo
extends RefCounted
## Which server the game is pointed at (Settings "server_url"), for every screen that can talk to the network.
##
## Kinds (docs/PROTOCOL.md "Server identity"):
##   Official  this build's shipped server: the `url` in res://data/extra/server.json (docs/SERVER_PLAN.md). Only this one
##             is the real server; a room created here is on the Official server.
##   Local     the dev / home server: localhost, 127.x, private LAN ranges (10/8, 172.16/12, 192.168/16), link-local,
##             Tailscale-style CGNAT hosts (100.64/10, *.ts.net, *.tailscale.net) and *.local / *.lan / *.home names.
##             The editor and a plain `npm start` use this.
##   Custom    any other address a player typed in the Settings screen.
##
## Why it matters: a room CODE is only a key on the server that created it. A friend on the Local server and a friend on
## the Official server will never find each other's rooms, and the code says nothing about the server. classify() names
## the current server; mismatch_hint(other_url) explains that case in plain words and is never shown for the same one.
##
## Everything here is static and pure (classify() takes a URL, no tree) except current_url()/current(), which read the
## Settings autoload. The UI part is ui/server_badge.gd (a small reusable chip); no screen is forced to add it.

const OFFICIAL := "official"
const LOCAL := "local"
const CUSTOM := "custom"

const SERVER_CONFIG_PATH := "res://data/extra/server.json"   ## Settings.SERVER_CONFIG_PATH (release build's shipped server)
const DEV_URL := "ws://127.0.0.1:3000/ws"                    ## Settings.DEV_SERVER_URL (editor / local `npm start`)

const LABELS := {
	OFFICIAL: "Official server",
	LOCAL: "Local server",
	CUSTOM: "Custom server",
}
const SHORT := {OFFICIAL: "Official", LOCAL: "Local", CUSTOM: "Custom"}
const COLORS := {
	OFFICIAL: Color(0.294, 0.82, 0.541),   # UiTheme.GOOD green: the real thing
	LOCAL: Color(0.961, 0.725, 0.259),     # UiTheme.WARN amber: only this device / the LAN
	CUSTOM: Color(0.55, 0.72, 0.98),       # blue: somebody's own server
}

## The release build's shipped server URL ("" when server.json is missing or has no url).
static func shipped_url() -> String:
	if not FileAccess.file_exists(SERVER_CONFIG_PATH): return ""
	var f := FileAccess.open(SERVER_CONFIG_PATH, FileAccess.READ)
	if f == null: return ""
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary): return ""
	var u := str((d as Dictionary).get("url", "")).strip_edges()
	return u if u.begins_with("ws://") or u.begins_with("wss://") else ""

## The server this device is set to use right now (Settings.server_url, falling back to the dev address).
static func current_url() -> String:
	var st := _settings()
	var u := str(st.get_value("server_url")).strip_edges() if st else ""
	return u if u != "" else DEV_URL

## The current server, classified (`{"kind", "label", "short", "host", "color", "url", "official", "official_url"}`).
static func current() -> Dictionary:
	return classify("")

## Classify a server URL. `url == ""` means the current Settings.server_url.
static func classify(url: String = "") -> Dictionary:
	var u := url.strip_edges()
	if u == "": u = current_url()
	var official := shipped_url()
	var kind := CUSTOM
	if official != "" and _norm(u) == _norm(official): kind = OFFICIAL
	elif is_local(u): kind = LOCAL
	var host := host_of(u)
	return {
		"url": u,
		"kind": kind,
		"label": LABELS[kind],
		"short": SHORT[kind],
		"host": host,
		"color": COLORS[kind],
		"official": kind == OFFICIAL,
		"official_url": official,
	}

## "host:port" of a ws:// or wss:// URL (user info stripped; the /ws path dropped).
static func host_of(url: String) -> String:
	var u := url.strip_edges()
	var i := u.find("://")
	if i >= 0: u = u.substr(i + 3)
	elif u.begins_with("//"): u = u.substr(2)
	var cut := u.find("/")
	if cut < 0: cut = u.find("?")
	if cut >= 0: u = u.substr(0, cut)
	var at := u.rfind("@")
	if at >= 0: u = u.substr(at + 1)
	return u

## True for localhost, a private LAN address or a Tailscale-style local host.
static func is_local(url: String) -> bool:
	var h := _host_only(host_of(url)).to_lower().trim_suffix(".")
	if h == "": return false
	if h in ["localhost", "127.0.0.1", "0.0.0.0", "::1", "[::1]", "host.docker.internal", "10.0.2.2"]: return true
	var p := h.split(".")
	if p.size() == 4 and _is_byte(p[0]) and _is_byte(p[1]) and _is_byte(p[2]) and _is_byte(p[3]):
		var a := int(p[0])
		var b := int(p[1])
		if a == 0 or a == 10 or a == 127: return true
		if a == 192 and b == 168: return true
		if a == 169 and b == 254: return true
		if a == 172 and b >= 16 and b <= 31: return true
		if a == 100 and b >= 64 and b <= 127: return true   # Tailscale / carrier-grade NAT
		return false
	if h.ends_with(".local") or h.ends_with(".lan") or h.ends_with(".home") or h.ends_with(".internal") or h.ends_with(".localdomain") or h.ends_with(".home.arpa"): return true
	if h.ends_with(".ts.net") or h.ends_with(".tailscale.net") or h.begins_with("tailscale-"): return true
	return false

## Plain words for "your friend's room code will not be found here", or "" when both URLs are the same server.
## `other_url` is the server the room/invite is on (a friend's Settings.server_url or the URL in the invite); "" = current.
static func mismatch_hint(other_url: String, my_url: String = "") -> String:
	var other := classify(other_url)
	var mine := classify(my_url) if my_url.strip_edges() != "" else current()
	if other["url"] == "" or mine["url"] == "": return ""
	if _norm(other["url"]) == _norm(mine["url"]): return ""
	if other["kind"] == OFFICIAL and mine["kind"] != OFFICIAL:
		return TranslationServer.translate("That room is on the Official server, but this device is on the %s (%s). Room codes only work on the same server: switch the server in Settings, or ask your friend to join yours.") % [mine["label"].to_lower(), mine["host"]]
	if mine["kind"] == OFFICIAL and other["kind"] != OFFICIAL:
		return TranslationServer.translate("That room is on the %s (%s), but this device is on the Official server. Room codes only work on the same server: ask your friend to switch to the Official server.") % [other["label"].to_lower(), other["host"]]
	return TranslationServer.translate("That room is on the %s (%s), but this device is on the %s (%s). Room codes only work on the same server.") % [other["label"].to_lower(), other["host"], mine["label"].to_lower(), mine["host"]]

## "Official · homeserver.tailcc5a5.ts.net" for a button/tooltip (the badge shows the same thing with a colour).
static func line(url: String = "") -> String:
	var i := classify(url)
	return "%s · %s" % [TranslationServer.translate(i["label"]), i["host"]]

static func _settings() -> Node:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var tree := ml as SceneTree
		if tree.root != null: return tree.root.get_node_or_null("Settings")
	return null

static func _norm(u: String) -> String:
	var s := u.strip_edges().to_lower()
	while s.ends_with("/"): s = s.substr(0, s.length() - 1)
	if s.ends_with("/ws"): s = s.substr(0, s.length() - 3)
	return s

static func _host_only(host: String) -> String:
	if host.begins_with("["):
		var close := host.find("]")
		return host.substr(0, close + 1) if close >= 0 else host
	var colon := host.rfind(":")
	if colon > 0 and host.substr(colon + 1).is_valid_int(): return host.substr(0, colon)
	return host

static func _is_byte(s: String) -> bool:
	return s.is_valid_int() and int(s) >= 0 and int(s) <= 255
