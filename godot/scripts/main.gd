extends Control
## Title scene: offline play (class, mode, floor and map pickers) and the online panel: server address, room code, name, Join
## (as a guest, GuestSession) and a minimal login (POST /api/login, token kept in Settings). Laid out with containers
## inside a safe-area MarginContainer so nothing overlaps at any aspect ratio (tests/ui_layout_test.gd checks
## 852x393, 1170x540, 1280x720 and 390x844 with both the Offline and the Play online tab open).
## Command line (after `--`): --join=ROOM [--server=ws://host:3000/ws] [--name=NAME] joins straight away.

const WORLD := "res://world/world.tscn"
const OFFLINE_MAPS := ["arena", "practice"]
## Offline modes on the title screen (Settings "mode"). A mode with its own maps (MODES[id].maps in the web game,
## i.e. maps whose `only` is the mode) plays only those: Construction -> Site Yard. The others use OFFLINE_MAPS.
const OFFLINE_MODES := ["classic", "construction"]
const MARGIN := Vector4(28, 18, 28, 14)   ## left, top, right, bottom padding inside the safe area
const TIPS := [
	"Tip: push the stick to the edge to sprint.",
	"Tip: knock fighters off the edge for a K.O.",
	"Tip: crates drop weapons, heals and power-ups.",
	"Tip: kick and shove work even without a weapon.",
	"Tip: press F3 (or tap with three fingers) to show the FPS meter.",
]

## Set by the world when it hands an active session back (host migration) and/or a message to show.
var session: GuestSession = null
var notice := ""

const P := "Safe/Col/Body/Picks/Box/"
@onready var safe: MarginContainer = $Safe
@onready var chip: Label = $Safe/Col/Top/GuestChip/Row/Status
@onready var who: Label = $Safe/Col/Top/GuestChip/Row/Who
@onready var dot: Panel = $Safe/Col/Top/GuestChip/Row/Dot
@onready var map_pick: OptionButton = get_node(P + "Offline/MapRow/Map")
@onready var mode_pick: OptionButton = get_node(P + "Offline/ModeRow/Mode")
@onready var class_pick: OptionButton = get_node(P + "Offline/ClassRow/Class")
@onready var dyn_pick: OptionButton = get_node(P + "Offline/ModeRow/Dyn")   ## dynamic floor (Settings "dyn"): Steady / Random / Wobble / Tilt / Quake / Drift
@onready var fps_toggle: CheckButton = get_node(P + "Offline/FpsRow/Fps")
@onready var status: Label = get_node(P + "Online/Status")
@onready var play: Button = $Safe/Col/Body/Play
var class_ids: Array = []
var map_ids: Array = []          ## the maps map_pick lists for the picked mode
var _ui := {}
var _api: AccountApi

func _ready() -> void:
	for m: String in OFFLINE_MODES:
		mode_pick.add_item(str(Content.modes.get(m, {}).get("name", m.capitalize())))
	mode_pick.select(maxi(OFFLINE_MODES.find(str(Settings.get_value("mode", "classic"))), 0))
	mode_pick.item_selected.connect(func(i: int) -> void:
		Settings.set_value("mode", OFFLINE_MODES[i])
		_fill_maps())
	_fill_maps()
	class_ids = Content.classes.keys()
	for cid in class_ids:
		class_pick.add_item(str(Content.get_class_data(cid).get("name", cid)))
	class_pick.select(maxi(class_ids.find(str(Settings.get_value("class", "wobbler"))), 0))
	for k: String in Dynamics.KINDS:
		dyn_pick.add_item(str(Dynamics.NAMES[k]))
	dyn_pick.select(maxi(Dynamics.KINDS.find(str(Settings.get_value("dyn", "random"))), 0))
	dyn_pick.item_selected.connect(func(i: int) -> void: Settings.set_value("dyn", Dynamics.KINDS[i]))
	play.pressed.connect(play_offline)
	fps_toggle.button_pressed = bool(Settings.get_value("show_fps", false))
	fps_toggle.toggled.connect(func(on: bool): Settings.set_value("show_fps", on))
	Settings.changed.connect(_on_setting)
	$Safe/Col/Tip.text = TIPS[randi() % TIPS.size()]
	var group := ButtonGroup.new()
	for t in ["OfflineTab", "OnlineTab"]:
		var b: Button = get_node(P + "Tabs/" + t)
		b.button_group = group
		b.toggled.connect(func(on: bool): if on: show_tab(t == "OnlineTab"))
	_api = AccountApi.new()
	add_child(_api)
	_api.finished.connect(func(_ok: bool, msg: String) -> void: _status(msg); _refresh_login())
	_build_online()
	_status(notice if notice != "" else "Join a friend's room.")
	if session != null:
		_bind_session()
		_status((notice + "  " if notice != "" else "") + session.status)
	var join := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--join="): join = a.substr(7)
		elif a.begins_with("--server="): _ui["server"].text = a.substr(9)
		elif a.begins_with("--name="): _ui["name"].text = a.substr(7)
	if notice != "" or session != null or join != "":
		show_tab(true)
	if join != "" and session == null:
		_ui["room"].text = join
		join_room()
	JuicyButton.attach_all(self)
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()
	if Tier.is_pc():
		play.grab_focus.call_deferred()   # keyboard / gamepad start on PLAY

func _process(dt: float) -> void:
	if session != null:
		session.poll(dt)

## The offline maps for a mode: the maps only that mode plays (`only` == mode, e.g. Site Yard for Construction),
## else the usual OFFLINE_MAPS.
func maps_for(mode: String) -> Array:
	var own: Array = []
	for id: String in Content.maps:
		if str(Content.get_map(id).get("only", "")) == mode: own.append(id)
	return own if own.size() > 0 else OFFLINE_MAPS.duplicate()

func _fill_maps() -> void:
	map_ids = maps_for(OFFLINE_MODES[maxi(mode_pick.selected, 0)])
	map_pick.clear()
	for id: String in map_ids:
		map_pick.add_item(str(Content.get_map(id).get("name", id)))
	map_pick.select(maxi(map_ids.find(str(Settings.get_value("offline_map", "arena"))), 0))

## Offline pickers or the online panel in the right-hand card.
func show_tab(online: bool) -> void:
	get_node(P + "Offline").visible = not online
	get_node(P + "Online").visible = online
	(get_node(P + "Tabs/OnlineTab") as Button).set_pressed_no_signal(online)
	(get_node(P + "Tabs/OfflineTab") as Button).set_pressed_no_signal(not online)

func _on_setting(key: String, v: Variant) -> void:
	if key == "show_fps" and fps_toggle.button_pressed != bool(v):
		fps_toggle.set_pressed_no_signal(bool(v))

## Status line in the online panel; the chip at the top shows it short, with a coloured dot.
func _status(t: String) -> void:
	status.text = t
	status.tooltip_text = t
	var on := session != null and session.is_active()
	chip.text = t if on else "Offline"
	_dot(UiTheme.GOOD if on else UiTheme.MUTED)

func _dot(c: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(5)
	dot.add_theme_stylebox_override("panel", sb)

## Safe-area insets (notch, home indicator) plus our own padding.
func apply_safe_area() -> void:
	var i := SafeArea.insets(get_viewport())
	safe.add_theme_constant_override("margin_left", int(MARGIN.x + i[0]))
	safe.add_theme_constant_override("margin_top", int(MARGIN.y + i[1]))
	safe.add_theme_constant_override("margin_right", int(MARGIN.z + i[2]))
	safe.add_theme_constant_override("margin_bottom", int(MARGIN.w + i[3]))

# ---------------- online ----------------

func _build_online() -> void:
	var n := P + "Online/"
	_ui["server"] = get_node(n + "ServerRow/Server")
	_ui["room"] = get_node(n + "RoomRow/Room")
	_ui["name"] = get_node(n + "RoomRow/Name")
	_ui["join"] = get_node(n + "RoomRow/Join")
	_ui["leave"] = get_node(n + "RoomRow/Leave")
	_ui["user"] = get_node(n + "AcctRow/User")
	_ui["pass"] = get_node(n + "AcctRow/Pass")
	_ui["login"] = get_node(n + "AcctRow/Login")
	_ui["logout"] = get_node(n + "AcctRow/Logout")
	_ui["acct"] = get_node(n + "AcctRow/Acct")
	_ui["roster"] = get_node(n + "Roster")
	_ui["server"].text = str(Settings.get_value("server_url"))
	_ui["room"].text = str(Settings.get_value("room_code", ""))
	_ui["name"].text = str(Settings.get_value("name", "Player"))
	_ui["user"].text = str(Settings.get_value("user", ""))
	_ui["join"].pressed.connect(join_room)
	_ui["leave"].pressed.connect(func() -> void: if session: session.leave("You left the room."))
	_ui["login"].pressed.connect(func() -> void:
		_status("Logging in…")
		_api.login(_ui["server"].text, _ui["user"].text, _ui["pass"].text))
	_ui["logout"].pressed.connect(func() -> void: _api.logout(); _status("Logged out."); _refresh_login())
	_refresh_login()
	_refresh_buttons()

func _refresh_login() -> void:
	var u := str(Settings.get_value("user", ""))
	var logged := str(Settings.get_value("token", "")) != ""
	_ui["acct"].text = ("Logged in: " + u) if logged else "Not logged in"
	_ui["acct"].visible = logged
	_ui["logout"].visible = logged
	for k in ["user", "pass", "login"]:
		_ui[k].visible = not logged
	who.text = u.to_upper().substr(0, 12) if logged and u != "" else "GUEST"

func _refresh_buttons() -> void:
	var on := session != null and session.is_active()
	_ui["join"].disabled = on
	_ui["leave"].visible = on
	if not on: _ui["roster"].text = ""

func join_room() -> void:
	if session != null and session.is_active(): return
	var url := str(_ui["server"].text).strip_edges()
	var room := str(_ui["room"].text).strip_edges()      # the server matches codes case-insensitively
	var nm := str(_ui["name"].text).strip_edges().substr(0, 12)
	if nm == "": nm = "Player"
	Settings.set_value("server_url", url); Settings.set_value("room_code", room); Settings.set_value("name", nm)
	if class_ids.size() > 0: Settings.set_value("class", class_ids[maxi(class_pick.selected, 0)])
	session = GuestSession.new()
	_bind_session()
	session.begin(url, room, {"name": nm, "skin": Settings.get_value("skin", "none"), "hat": Settings.get_value("hat", "none"),
		"color": Settings.get_value("color", 0x39b5a8), "cls": Settings.get_value("class", "wobbler")}, str(Settings.get_value("token", "")))
	_refresh_buttons()

func _bind_session() -> void:
	session.status_changed.connect(_on_status)
	session.ended.connect(_on_ended)
	session.roster_changed.connect(_on_roster)
	session.match_started.connect(_enter_match)
	_refresh_buttons()

func _unbind_session() -> void:
	session.status_changed.disconnect(_on_status)
	session.ended.disconnect(_on_ended)
	session.roster_changed.disconnect(_on_roster)
	session.match_started.disconnect(_enter_match)

func _on_status(t: String) -> void:
	_status(t)

func _on_ended(_reason: String) -> void:
	_unbind_session()
	session = null
	_refresh_buttons()
	_status(status.text)

func _on_roster(r: Array) -> void:
	var names: Array = []
	for e: Dictionary in r: names.append(e["name"])
	_ui["roster"].text = "In the room: " + ", ".join(names)

## `start` from the host: into the match (the world takes the session over).
func _enter_match(s: Dictionary) -> void:
	if not is_inside_tree(): return
	_unbind_session()
	var world: Node = load(WORLD).instantiate()
	world.session = session
	world.start_msg = s
	session = null
	get_tree().change_scene_to_node.call_deferred(world)

func play_offline() -> void:
	if session != null: session.leave("")
	var id: String = map_ids[maxi(map_pick.selected, 0)]
	var mode: String = OFFLINE_MODES[maxi(mode_pick.selected, 0)]
	Settings.set_value("offline_map", id)
	Settings.set_value("mode", mode)
	if class_ids.size() > 0:
		Settings.set_value("class", class_ids[maxi(class_pick.selected, 0)])
	var world: Node = load(WORLD).instantiate()
	world.map_id = id
	world.mode_id = mode
	get_tree().change_scene_to_node(world)
