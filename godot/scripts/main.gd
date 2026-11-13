extends Control
## Title scene: offline play (map + class pickers) and the online panel: server address, room code, name, Join
## (as a guest, GuestSession) and a minimal login (POST /api/login, token kept in Settings). Laid out with containers
## inside a safe-area MarginContainer so nothing overlaps at any aspect ratio (tests/ui_layout_test.gd checks
## 852x393, 1170x540, 1280x720 and 390x844 with both the Offline and the Play online tab open).
## Command line (after `--`): --join=ROOM [--server=ws://host:3000/ws] [--name=NAME] joins straight away.

const WORLD := "res://world/world.tscn"
const OFFLINE_MAPS := ["arena", "practice"]
const DLC_MAPS := ["siteyard"]            ## Construction DLC: the Site Yard worksite
const MARGIN := Vector4(28, 18, 28, 14)   ## left, top, right, bottom padding inside the safe area
const TIPS := [
	"Tip: push the stick to the edge to sprint.",
	"Tip: knock fighters off the edge for a K.O.",
	"Tip: crates drop weapons, heals and power-ups.",
	"Tip: kick and shove work even without a weapon.",
	"Tip: press F3 (or tap with three fingers) to show the FPS meter.",
]
const DLC_TIPS := [
	"Hard hats on. Mind the open edges: one big swing and you are off the slab.",
	"Scaffold towers and timber stacks make good cover.",
	"Site rule: knock fighters off the slab for a K.O.",
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
@onready var class_pick: OptionButton = get_node(P + "Offline/ClassRow/Class")
@onready var fps_toggle: CheckButton = get_node(P + "Offline/FpsRow/Fps")
@onready var status: Label = get_node(P + "Online/Status")
@onready var play: Button = $Safe/Col/Body/Play
var class_ids: Array = []
var dlc := false                 ## Construction DLC title showing (never saved: the app always opens on the normal title)
var _maps: Array = OFFLINE_MAPS
var _sign: DontEnterSign
var _wipe: DlcTransition
var _sub_default := ""
var _ui := {}
var _api: AccountApi

func _ready() -> void:
	_fill_maps()
	class_ids = Content.classes.keys()
	for cid in class_ids:
		class_pick.add_item(str(Content.get_class_data(cid).get("name", cid)))
	class_pick.select(maxi(class_ids.find(str(Settings.get_value("class", "wobbler"))), 0))
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
	_build_dlc()
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
	var id: String = _maps[maxi(map_pick.selected, 0)]
	if not dlc: Settings.set_value("offline_map", id)
	if class_ids.size() > 0:
		Settings.set_value("class", class_ids[maxi(class_pick.selected, 0)])
	var world: Node = load(WORLD).instantiate()
	world.map_id = id
	get_tree().change_scene_to_node(world)

# ---------------- Construction DLC ----------------

## Map picker for the current title: the normal arenas, or the DLC worksite.
func _fill_maps() -> void:
	_maps = DLC_MAPS if dlc else OFFLINE_MAPS
	map_pick.clear()
	for id in _maps:
		map_pick.add_item(str(Content.get_map(id).get("name", id)))
	var last := _maps.find(str(Settings.get_value("offline_map", "arena"))) if not dlc else 0
	map_pick.select(maxi(last, 0))

## The "DON'T ENTER" sign in the header and the tape-wipe overlay.
func _build_dlc() -> void:
	_sub_default = $Safe/Col/Body/Play/Stack/Sub.text
	_sign = DontEnterSign.new()
	_sign.name = "DontEnter"
	_sign.pressed.connect(toggle_dlc)
	# footer row: the sign on the left, the build label on the right (the header row has no spare width on phones)
	var col: VBoxContainer = $Safe/Col
	var build: Label = $Safe/Col/Build
	var foot := HBoxContainer.new()
	foot.name = "Foot"
	col.add_child(foot)
	col.move_child(foot, build.get_index())
	build.reparent(foot, false)
	build.size_flags_vertical = Control.SIZE_SHRINK_END
	_sign.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	foot.add_child(_sign)
	foot.move_child(_sign, 0)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	foot.move_child(gap, 1)
	_wipe = DlcTransition.new()
	_wipe.name = "Wipe"
	add_child(_wipe)

func toggle_dlc() -> void:
	set_dlc(not dlc)

## Switch between the normal and the Construction title. Animated: hazard tape sweeps across, the title changes
## under it, the tape clears and the logo and PLAY button drop in.
func set_dlc(on: bool, animated := true) -> void:
	if on == dlc or _wipe.busy: return
	if not animated:
		_apply_dlc(on)
		return
	_wipe.banner = "CONSTRUCTION SITE" if on else "BACK TO THE ARENA"
	_wipe.run(_apply_dlc.bind(on), _drop_in)

func _apply_dlc(on: bool) -> void:
	dlc = on
	$Background.mix = 1.0 if on else 0.0
	var logo: WobbleLogo = $Safe/Col/Top/Logo
	if on: logo.set_palette(Color(0.92, 0.9, 0.84), Hazard.YELLOW, Color(0.1, 0.08, 0.06))
	else: logo.set_palette(WobbleLogo.WHITE, WobbleLogo.YELLOW, WobbleLogo.INK)
	_sign.label = "EXIT SITE" if on else "DON'T ENTER"
	_sign.tooltip_text = _sign.label.capitalize()
	$Safe/Col/Body/Play/Stack/Sub.text = "Site Yard vs bots" if on else _sub_default
	$Safe/Col/Tip.text = (DLC_TIPS if on else TIPS)[randi() % (DLC_TIPS if on else TIPS).size()]
	_fill_maps()

## Logo and PLAY button thump in after the tape clears.
func _drop_in() -> void:
	for n: Control in [$Safe/Col/Top/Logo, $Safe/Col/Body/Play]:
		n.pivot_offset = n.size / 2.0
		n.scale = Vector2.ONE * 1.18
		n.modulate.a = 0.0
		var tw := n.create_tween().set_parallel(true)
		tw.tween_property(n, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "modulate:a", 1.0, 0.2)
