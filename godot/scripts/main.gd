extends Control
## Title scene, readable in two seconds: the logo, one big "Play" (offline, against computer players: opens the setup
## wizard, ui/setup_wizard.gd: Game type -> Arena -> Players -> Character -> Start), one secondary "Play online with
## friends" (its sub line says it needs internet, or the room state while connected; it opens the online panel: server
## address, room code, name, Join as a guest with GuestSession, and a minimal login: POST /api/login, token kept in
## Settings), a chip saying who you are ("Guest" or "Signed in as NAME"), a gear for the settings sheet (Show FPS) and
## a small tip line. Laid out with containers inside a safe-area
## MarginContainer so nothing overlaps at any aspect ratio (tests/ui_layout_test.gd checks 852x393, 1170x540,
## 1280x720 and 390x844: the title, the online panel, every wizard page and the settings sheet).
## Command line (after `--`): --join=ROOM [--server=ws://host:3000/ws] [--name=NAME] joins straight away;
## --mode=ID / --map=ID preselect the wizard (the world reads them too when it starts).

const WORLD := "res://world/world.tscn"
const MARGIN := Vector4(28, 18, 28, 14)   ## left, top, right, bottom padding inside the safe area
const TIPS := [
	"Tip: push the stick to the edge to sprint.",
	"Tip: knock other players off the edge to score.",
	"Tip: crates drop weapons, heals and power-ups.",
	"Tip: kick and shove work even without a weapon.",
]
const ONLINE_SUB := "Needs internet · join a room code"

## Set by the world when it hands an active session back (host migration) and/or a message to show.
var session: GuestSession = null
var notice := ""

const O := "Safe/Col/Body/Online/Box/"
@onready var safe: MarginContainer = $Safe
@onready var col: VBoxContainer = $Safe/Col
@onready var who: Label = $Safe/Col/Top/GuestChip/Row/Who
@onready var gear: Button = $Safe/Col/Top/Gear
@onready var home: Control = $Safe/Col/Body/Home
@onready var online_panel: Control = $Safe/Col/Body/Online
@onready var play: Button = $Safe/Col/Body/Home/Play
@onready var online_b: Button = $Safe/Col/Body/Home/Online
@onready var status: Label = get_node(O + "Status")
var wizard: SetupWizard
var sheet: Control                  ## settings sheet (gear): Show FPS
var fps_toggle: CheckButton
var _ui := {}
var _api: AccountApi

func _ready() -> void:
	wizard = SetupWizard.new()
	wizard.visible = false
	safe.add_child(wizard)
	wizard.start_requested.connect(play_offline)
	wizard.closed.connect(close_wizard)
	play.pressed.connect(open_wizard)
	online_b.pressed.connect(show_tab.bind(true))
	(get_node(O + "Head/Back") as Button).pressed.connect(show_tab.bind(false))
	gear.icon = _gear_icon()
	gear.pressed.connect(show_settings.bind(true))
	_build_sheet()
	Settings.changed.connect(_on_setting)
	$Safe/Col/Tip.text = TIPS[randi() % TIPS.size()]
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
		elif a.begins_with("--mode=") and SetupWizard.modes().has(a.substr(7)): wizard.set_mode(a.substr(7))
		elif a.begins_with("--map=") and Content.maps.has(a.substr(6)): wizard.set_map(a.substr(6))
	_play_sub()
	show_tab(notice != "" or session != null or join != "")
	if join != "" and session == null:
		_ui["room"].text = join
		join_room()
	JuicyButton.attach_all(self)
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()
	if Tier.is_pc():
		play.grab_focus.call_deferred()   # keyboard / gamepad start on Play

func _process(dt: float) -> void:
	if session != null:
		session.poll(dt)

## The offline arenas for a mode (SetupWizard.maps_for).
func maps_for(mode: String) -> Array:
	return SetupWizard.maps_for(mode)

## The title (Play / Play online with friends) or the online panel.
func show_tab(online: bool) -> void:
	home.visible = not online
	online_panel.visible = online
	if online and Tier.is_pc(): (get_node(O + "Head/Back") as Button).grab_focus.call_deferred()

## The setup wizard (page 0 = Game type) instead of the title column.
func open_wizard(p: int = 0) -> void:
	col.visible = false
	wizard.visible = true
	wizard.go(p)

func close_wizard() -> void:
	wizard.visible = false
	col.visible = true
	_play_sub()
	if Tier.is_pc(): play.grab_focus.call_deferred()

## Play keeps one plain sub line; the last setup is its tooltip (the wizard opens on it anyway).
func _play_sub() -> void:
	play.tooltip_text = "Last time: " + wizard.summary_line()

func show_settings(on: bool) -> void:
	sheet.visible = on
	if on and Tier.is_pc(): fps_toggle.grab_focus.call_deferred()

## Settings sheet: a dimmed backdrop (tap to close) and a small card.
func _build_sheet() -> void:
	sheet = Control.new()
	sheet.name = "Sheet"
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet.visible = false
	add_child(sheet)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed: show_settings(false))
	sheet.add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(cc)
	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(440, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var t := Label.new()
	t.text = "Settings"
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override("font_size", 32)
	box.add_child(t)
	fps_toggle = CheckButton.new()
	fps_toggle.name = "Fps"
	fps_toggle.text = "Show FPS"
	fps_toggle.custom_minimum_size = Vector2(0, 56)
	fps_toggle.add_theme_font_size_override("font_size", 22)
	fps_toggle.button_pressed = bool(Settings.get_value("show_fps", false))
	fps_toggle.toggled.connect(func(on: bool): Settings.set_value("show_fps", on))
	box.add_child(fps_toggle)
	var cam_row := HBoxContainer.new()
	cam_row.name = "CamRow"
	cam_row.add_theme_constant_override("separation", 12)
	var cam_l := Label.new()
	cam_l.text = "Camera"
	cam_l.add_theme_font_size_override("font_size", 22)
	cam_row.add_child(cam_l)
	var cam_tg := OptionButton.new()
	cam_tg.name = "CamCenter"
	cam_tg.custom_minimum_size = Vector2(0, 56)
	cam_tg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cam_tg.add_theme_font_size_override("font_size", 22)
	cam_tg.add_item("Manual (classic)")
	cam_tg.add_item("Auto-centre (slow)")
	cam_tg.select(1 if bool(Settings.get_value("cam_auto_center", true)) else 0)
	cam_tg.item_selected.connect(func(i: int): Settings.set_value("cam_auto_center", i == 1))
	cam_row.add_child(cam_tg)
	box.add_child(cam_row)
	var done := Button.new()
	done.name = "Done"
	done.text = "Done"
	done.theme_type_variation = &"PrimaryButton"
	done.add_theme_font_size_override("font_size", 26)
	done.custom_minimum_size = Vector2(0, 60)
	done.pressed.connect(show_settings.bind(false))
	box.add_child(done)

## A small white gear (no image files): a disc with eight teeth and a hole.
static func _gear_icon() -> ImageTexture:
	var n := 34
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(n, n) / 2.0
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) - c
			var r := p.length()
			var a := atan2(p.y, p.x)
			var tooth := clampf(cos(a * 8.0) * 3.0, -1.0, 1.0) * 0.5 + 0.5   # 0 between teeth, 1 on a tooth
			var outer := lerpf(11.5, 15.5, tooth)
			var cov := clampf(outer - r + 0.5, 0.0, 1.0) * clampf(r - 5.0 + 0.5, 0.0, 1.0)
			if cov > 0.0: img.set_pixel(x, y, Color(1, 1, 1, cov))
	return ImageTexture.create_from_image(img)

func _on_setting(key: String, v: Variant) -> void:
	if key == "show_fps" and fps_toggle.button_pressed != bool(v):
		fps_toggle.set_pressed_no_signal(bool(v))

## Status line in the online panel; while connected the Play online button's sub line shows it too.
func _status(t: String) -> void:
	status.text = t
	status.tooltip_text = t
	var on := session != null and session.is_active()
	var sub: Label = $Safe/Col/Body/Home/Online/Stack/Sub
	sub.text = ("Connected · " + t) if on else ONLINE_SUB
	sub.tooltip_text = sub.text

## Safe-area insets (notch, home indicator) plus our own padding.
func apply_safe_area() -> void:
	var i := SafeArea.insets(get_viewport())
	safe.add_theme_constant_override("margin_left", int(MARGIN.x + i[0]))
	safe.add_theme_constant_override("margin_top", int(MARGIN.y + i[1]))
	safe.add_theme_constant_override("margin_right", int(MARGIN.z + i[2]))
	safe.add_theme_constant_override("margin_bottom", int(MARGIN.w + i[3]))

# ---------------- online ----------------

func _build_online() -> void:
	var n := O
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
	who.text = ("Signed in as " + u.substr(0, 12)) if logged and u != "" else "Guest"
	who.tooltip_text = "Sign in from Play online with friends" if not logged else "Signed in: " + u

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

## Starts the offline match the wizard describes (map, mode, bots, bot skill; class and floor via Settings).
func play_offline() -> void:
	if session != null: session.leave("")
	wizard.save()
	var world: Node = load(WORLD).instantiate()
	world.map_id = wizard.map_id
	world.mode_id = wizard.mode_id
	world.bot_count = wizard.bots
	world.difficulty = wizard.diff
	get_tree().change_scene_to_node(world)
