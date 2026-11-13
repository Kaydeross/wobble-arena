extends Node
## Player preferences (autoload `Settings`): flat key/value store persisted with ConfigFile at user://settings.cfg.
## Defaults mirror the web game's `settings`/`TC` objects (public/index.html ~1449, ~9154). Later phases add keys here.

signal changed(key: String, value: Variant)

const PATH := "user://settings.cfg"
const SECTION := "settings"
## Dev default (editor, tests, local `npm start`). Release exports use `server_default()` below instead.
const DEV_SERVER_URL := "ws://127.0.0.1:3000/ws"
## Production server address for release exports: {"url": "wss://play.example.com/ws"}; empty = fall back to DEV_SERVER_URL.
## Public config, not a secret (never put tokens or keys in it). Shipped through the export's data/*.json filter.
const SERVER_CONFIG_PATH := "res://data/extra/server.json"
const DEFAULTS := {
	"sens": 1.0,            # look sensitivity multiplier
	"fov": 72.0,            # vertical field of view
	"cam_dist": 1.0,        # camera distance multiplier
	"cam_auto_center": true, # the camera eases back behind the player after a short walk (world/follow_camera.gd)
	"cam_center_dist": 8.0, # metres walked since the last manual look before it does
	"invert_y": false,
	"touch_mode": "auto",   # auto | on | off
	"touch_lefty": false,
	"touch_scale": 1.0,
	"touch_opacity": 0.85,
	"touch_assist": true,
	"ui_scale": "auto",     # menus, HUD and touch buttons: auto | small | normal | large (ui/ui_scale.gd)
	"show_fps": false,      # FPS / frame-time overlay (F3 or a three-finger tap toggles it)
	"perf_overlay": false,  # device readout in the top-left corner: fps, frame ms, CPU / GPU, draws, tier, thermal (ui/perf_overlay.gd)
	"effects": "auto",      # combat effects level: auto (= graphics tier) | low | medium | high (world/fx.gd)
	"screen_shake": true,   # camera shake on big hits, explosions and K.O.s (world/follow_camera.gd)
	"class": "wobbler",     # character class (shared/classes.json id)
	"color": 0x39b5a8,      # body colour (the web player's default)
	"volume": 0.5,          # sound volume 0..1 (web settings.vol; autoload Sfx)
	"muted": false,         # no sound effects
	"skin": "none",         # outfit (cosmetics.json skins)
	"hat": "none",          # hat (cosmetics.json hats)
	"name": "Player",       # name shown to other players (12 chars on the wire)
	"server_url": "ws://127.0.0.1:3000/ws",   # (the real default comes from server_default()) room server WebSocket (the REST API is the same host over http/https)
	"room_code": "",        # last room joined
	"token": "",            # account token from /api/login (sent with the `auth` op)
	"user": "",             # logged-in username
	"email": "",            # logged-in account's email (shown on the Account sheet)
	# TODO(Phase 5): keep the token in the iOS Keychain instead of settings.cfg.
	"cloud_t": 0,           # server time (ms) of the cloud save this device last matched (web acct.t)
	"cloud_dirty": false,   # the profile changed since the last cloud save (pushed when online again)
	"cloud_user": "",       # lower-case account the local profile was last synced with ("" = none / guest)
	"kill_cam": true,       # short slow-mo replay after a fast K.O. you score (offline, world/kill_cam.gd)
	"chat": false,          # iOS ships with chat off: nothing is sent or shown
	"dyn": "random",        # dynamic arena: off (Steady) | random | wobble | tilt | quake | drift (docs/DYNAMICS.md)
	"mode": "classic",      # offline game mode (shared/modes.json id; the setup wizard offers ModeRules.PLAYABLE; the Construction hub sets construction)
	"limit": -1,            # offline K.O. limit: -1 = the mode's preset, 0 = none, else 5 / 10 / 20
	"wobble_rig": "ragdoll",   # character animation: ragdoll (leg-driven floppy overlay, docs/RAGDOLL.md) | classic (web pose)
	"offline_map": "arena", # offline arena (setup wizard page 1)
	"bots": 3,              # offline bots 1..7 (team modes fix the count: ModeRules.bot_count)
	"difficulty": "normal", # offline bot skill: easy | normal | hard | insane (data/difficulties.json)
	"site_seed": 0,         # Construction: the building-site seed (0 = a new random site every match; the hub's Re-roll fixes one)
	# --- the Settings screen (ui/settings_screen.gd) ---
	"mouse_sens": 1.0,      # look sensitivity for the mouse and a controller's right stick (input/player_input.gd); touch uses `sens`
	"aim_mode": "hold",     # keyboard / mouse / controller aim: hold | toggle (touch always double-taps to toggle)
	"damage_numbers": true, # floating damage numbers over the fighter you hit (read by the world's effects)
	"sfx_volume": 1.0,      # sound effects bus 0..1 (autoload Sfx); `volume` stays the master volume
	"music_volume": 0.5,    # music bus 0..1 (autoload Music; the web settings.music)
	"lang": "auto",         # language: auto (the device's) | en | zh_TW | zh_CN | ja | fr | es (autoload Lang, i18n/strings.json)
	"seen_intro": false,    # the 3-card how-to (ui/intro_cards.gd) was shown or skipped once
}

var _cfg := ConfigFile.new()
var persist := true   ## tests turn this off so they never write the user's file

func _init() -> void:
	if OS.get_cmdline_user_args().has("--no-save"):
		persist = false
		return
	_cfg.load(PATH)   # missing file = defaults
	if migrate_server_url(_cfg, server_default()):
		_cfg.save(PATH)

## Builds before 0.2.0 (15) stored the dev address as the player's server. When this build ships a different default,
## drop that stale localhost value so the player gets the real server. Returns true when it changed `cfg`.
static func migrate_server_url(cfg: ConfigFile, shipped_default: String) -> bool:
	if shipped_default == DEV_SERVER_URL or not cfg.has_section_key(SECTION, "server_url"):
		return false
	if str(cfg.get_value(SECTION, "server_url")).strip_edges() != DEV_SERVER_URL:
		return false
	cfg.erase_section_key(SECTION, "server_url")
	return true

## The server a fresh install connects to: the configured production url in release exports, else the dev address.
## `config_path` and `release` are parameters so tests can exercise the release path in the editor.
static func server_default(config_path: String = SERVER_CONFIG_PATH, release: bool = not OS.has_feature("editor")) -> String:
	if release and FileAccess.file_exists(config_path):
		var f := FileAccess.open(config_path, FileAccess.READ)
		var j := JSON.new()
		var d: Variant = j.data if f and j.parse(f.get_as_text()) == OK else null   # quiet on bad json
		if d is Dictionary:
			var u := str((d as Dictionary).get("url", "")).strip_edges()
			if u.begins_with("ws://") or u.begins_with("wss://"):
				return u
	return DEV_SERVER_URL

## "Using: <url> (default|custom)" for the Settings screen.
func server_status_text() -> String:
	var cur := str(get_value("server_url"))
	return tr("Using: %s (%s)") % [cur, tr("default") if cur == server_default() else tr("custom")]

func get_value(key: String, default: Variant = null) -> Variant:
	if default == null:
		default = server_default() if key == "server_url" else DEFAULTS.get(key)
	return _cfg.get_value(SECTION, key, default)

func set_value(key: String, value: Variant) -> void:
	if key == "server_url" and str(value).strip_edges() in ["", server_default()]:   # the default is never stored, so a later app update can change it
		reset(key)
		return
	if _cfg.has_section_key(SECTION, key) and _cfg.get_value(SECTION, key) == value:
		return
	_cfg.set_value(SECTION, key, value)
	if persist:
		_cfg.save(PATH)
	changed.emit(key, value)

func reset(key: String) -> void:
	if _cfg.has_section_key(SECTION, key):
		_cfg.erase_section_key(SECTION, key)
		if persist:
			_cfg.save(PATH)
		changed.emit(key, get_value(key))
