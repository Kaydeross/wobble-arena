extends Control
## Title scene, readable in two seconds: the logo, one big "Play" (offline, against computer players: opens the setup
## wizard, ui/setup_wizard.gd: Game type -> Arena -> Players -> Character -> Start), one secondary "Play online with
## friends" (its sub line says it needs internet, or the room state while connected). The online panel: your name,
## the public room list (ui/room_browser.gd: tap a room to join, Refresh, empty / error states), "Join with a code"
## for private rooms (GuestSession), "Host a room" (the host sheet: room name, public / private, seats, bots ->
## HostSession) and an account button; both roles wait in the lobby sheet (the players, Start for the host, Leave).
## A chip saying who you are ("Guest" or "Signed in as NAME"; tap it for the Account sheet, ui/account_sheet.gd),
## a gear for the Settings screen (ui/settings_screen.gd: Controls, Camera, Graphics, Audio, Gameplay, Account,
## About) and a small tip line. On the very first launch the how-to cards (ui/intro_cards.gd) show once.
## Back everywhere: the Back buttons, Escape / controller B (ui_cancel) and Android's back gesture (go_back(): the top
## sheet or page closes; on the title itself nothing happens, the app never quits on back).
## Laid out with containers inside a safe-area MarginContainer so nothing overlaps at any aspect ratio
## (tests/ui_layout_test.gd checks 852x393, 667x375, 1170x540, 1280x720 and 390x844 on every page and sheet).
## Under the two Play buttons: Locker and Shop (ui/locker.gd, one screen in two modes; the Shop button shows your coins).
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
const ONLINE_SUB := "Needs internet · public rooms or a code"

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
@onready var status: Label = get_node(O + "Foot/Status")
var wizard: SetupWizard
var locker: LockerScreen            ## the Locker / Shop screen (hidden until opened)
var locker_b: Button
var shop_b: Button
var settings: SettingsScreen        ## the Settings screen (gear)
var intro: IntroCards               ## the first-run how-to (also Settings > Controls)
var browser: RoomBrowser            ## public rooms in the online panel
## true / false: show the how-to on start or not; null = when it was never seen (not in tests: they run with --no-save)
var auto_intro: Variant = null
var _ui := {}
var account: AccountSheet           ## the Account sheet (title chip)
var chip: PanelContainer
var host_sheet: Control             ## "Host a room": name, public / private, seats, bots
var lobby: Control                  ## the room's lobby: players, Start (host only), Leave
var _host := {"pub": false, "max": 4, "bots": 2}
var _host_bs := {}                  ## "pub_0/1", "max_N", "bots_N" -> Button

func _ready() -> void:
	wizard = SetupWizard.new()
	wizard.visible = false
	safe.add_child(wizard)
	wizard.start_requested.connect(play_offline)
	wizard.closed.connect(close_wizard)
	locker = LockerScreen.new()
	locker.visible = false
	safe.add_child(locker)
	locker.closed.connect(close_locker)
	_build_more()
	play.pressed.connect(open_wizard)
	online_b.pressed.connect(show_tab.bind(true))
	(get_node(O + "Head/Back") as Button).pressed.connect(show_tab.bind(false))
	gear.icon = _gear_icon()
	gear.pressed.connect(show_settings.bind(true))
	settings = SettingsScreen.new()
	add_child(settings)
	settings.closed.connect(func() -> void: if Tier.is_pc(): gear.grab_focus.call_deferred())
	settings.account_requested.connect(func() -> void: open_account())
	_build_host_sheet()
	_build_lobby()
	$Safe/Col/Tip.text = TIPS[randi() % TIPS.size()]
	account = AccountSheet.new()
	add_child(account)
	account.closed.connect(func() -> void:
		if settings.visible: settings.show_section(settings.section)   # the Account section shows who you are now
		elif Tier.is_pc(): gear.grab_focus.call_deferred())
	Save.cloud.done.connect(func(_op: String, _ok: bool, _msg: String) -> void: _refresh_login())
	Save.cloud.changed.connect(_refresh_login)
	_build_chip()
	_build_online()
	_status(notice if notice != "" else "Pick a room, or join a friend with their code.")
	if session != null:
		_bind_session()
		_status((notice + "  " if notice != "" else "") + session.status)
		_on_roster(session.roster)
	var join := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--join="): join = a.substr(7)
		elif a.begins_with("--server="): Settings.set_value("server_url", a.substr(9))
		elif a.begins_with("--name="): _ui["name"].text = a.substr(7)
		elif a.begins_with("--mode=") and SetupWizard.modes().has(a.substr(7)): wizard.set_mode(a.substr(7))
		elif a.begins_with("--map=") and Content.maps.has(a.substr(6)): wizard.set_map(a.substr(6))
	_play_sub()
	show_tab(notice != "" or session != null or join != "")
	if join != "" and session == null:
		_ui["room"].text = join
		join_room()
	JuicyButton.attach_all(self)
	if not Save.cloud.pending.is_empty(): account.open("conflict")   # a cloud conflict found during a match
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()
	if Tier.is_pc():
		play.grab_focus.call_deferred()   # keyboard / gamepad start on Play
	get_tree().set_quit_on_go_back(false)  # Android back never quits from a menu: go_back() handles it
	intro = IntroCards.new()
	add_child(intro)
	intro.closed.connect(func() -> void: if Tier.is_pc(): play.grab_focus.call_deferred())
	var first: bool = auto_intro if auto_intro is bool else (Settings.persist and not bool(Settings.get_value("seen_intro", false)))
	if first and session == null and join == "" and notice == "": intro.open()

## Back (Escape / controller B via ui_cancel, Android's back gesture): close the top thing. The wizard and the Locker
## handle ui_cancel themselves; the back gesture reaches them through here. On the bare title nothing happens.
func go_back() -> bool:
	if intro.visible: return intro.back()
	if account.visible: return account.back()
	if settings.visible: return settings.back()
	if lobby.visible:
		if session: session.leave("You left the room.")
		show_lobby(false)
		return true
	if host_sheet.visible: show_host(false); return true
	if locker.visible:
		if locker.confirm.visible: locker.show_confirm(false)
		else: locker.close()
		return true
	if wizard.visible: wizard.back(); return true
	if online_panel.visible: show_tab(false); return true
	return false

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and not e.is_echo() and go_back():
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		go_back()

func _process(dt: float) -> void:
	if session != null:
		session.poll(dt)

## The offline arenas for a mode (SetupWizard.maps_for).
func maps_for(mode: String) -> Array:
	return SetupWizard.maps_for(mode)

## The Locker / Shop row under Play online: two clear buttons, each with a one-line sub (the Shop's shows your coins).
func _build_more() -> void:
	var more := HBoxContainer.new()
	more.name = "More"
	more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	more.add_theme_constant_override("separation", 16)
	home.add_child(more)
	home.add_theme_constant_override("separation", 12)   # one more row: a little tighter, so the column still fits a phone
	locker_b = _small_button("Locker", "Outfits, hats and emotes")
	locker_b.pressed.connect(open_locker.bind(false))
	more.add_child(locker_b)
	shop_b = _small_button("Shop", "")
	shop_b.pressed.connect(open_locker.bind(true))
	more.add_child(shop_b)
	Save.changed.connect(_coins_sub)
	_coins_sub()

func _small_button(big: String, sub: String) -> Button:
	var b := Button.new()
	b.name = big
	b.custom_minimum_size = Vector2(252, 54)
	var st := VBoxContainer.new()
	st.name = "Stack"
	st.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	st.offset_left = 14; st.offset_right = -14
	st.alignment = BoxContainer.ALIGNMENT_CENTER
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	st.add_theme_constant_override("separation", -4)
	b.add_child(st)
	var bl := Label.new()
	bl.name = "Big"
	bl.text = big
	bl.add_theme_font_size_override("font_size", 24)
	bl.add_theme_font_override("font", UiTheme.font(700))
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	st.add_child(bl)
	var sl := Label.new()
	sl.name = "Sub"
	sl.text = sub
	sl.theme_type_variation = &"MutedLabel"
	sl.add_theme_font_size_override("font_size", 15)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.clip_text = true
	sl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	st.add_child(sl)
	return b

func _coins_sub() -> void:
	if shop_b: (shop_b.get_node("Stack/Sub") as Label).text = "You have %d coins" % Save.coins

## The Locker (shop = false) or the Shop instead of the title column.
func open_locker(shop_mode: bool = false, tab: String = "") -> void:
	col.visible = false
	wizard.visible = false
	locker.visible = true
	locker.open(shop_mode, tab)

func close_locker() -> void:
	locker.visible = false
	col.visible = true
	if wizard.stage:                    # the look may have changed: the Character page renders it again
		wizard.stage.baked.clear()
		wizard.stage.current = ""
	_coins_sub()
	if Tier.is_pc(): locker_b.grab_focus.call_deferred()

## The title (Play / Play online with friends) or the online panel.
func show_tab(online: bool) -> void:
	browser.url = str(Settings.get_value("server_url"))
	home.visible = not online
	online_panel.visible = online
	$Safe/Col/Tip.visible = not online    # the room list needs the height
	if online and Tier.is_pc(): (get_node(O + "Head/Back") as Button).grab_focus.call_deferred()
	elif not online and Tier.is_pc(): online_b.grab_focus.call_deferred()

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

func show_settings(on: bool, section := "") -> void:
	if on:
		settings.open()
		if section != "": settings.show_section(section)
	else: settings.close()

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
	var n := O + "Main/Side/"
	_ui["room"] = get_node(n + "CodeRow/Room")
	_ui["name"] = get_node(O + "Head/Name")
	_ui["join"] = get_node(n + "CodeRow/Join")
	_ui["leave"] = get_node(n + "CodeRow/Leave")
	_ui["roster"] = get_node(O + "Foot/Roster")
	_ui["room"].text = str(Settings.get_value("room_code", ""))
	_ui["name"].text = str(Settings.get_value("name", "Player"))
	_ui["name"].text_changed.connect(func(t: String) -> void: if t.strip_edges() != "": Settings.set_value("name", t.strip_edges().substr(0, 12)))
	_ui["join"].pressed.connect(join_room)
	_ui["room"].text_submitted.connect(func(_t: String) -> void: join_room())
	var side: VBoxContainer = get_node(O + "Main/Side")
	var hb := Button.new()
	hb.name = "Host"
	hb.text = "Host a room"
	hb.theme_type_variation = &"PrimaryButton"
	hb.custom_minimum_size = Vector2(0, 62)
	hb.add_theme_font_size_override("font_size", 24)
	hb.pressed.connect(show_host.bind(true))
	side.add_child(hb)
	_ui["host"] = hb
	var ab := Button.new()
	ab.name = "Account"
	ab.custom_minimum_size = Vector2(0, 62)
	ab.add_theme_font_size_override("font_size", 18)
	ab.clip_text = true
	ab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	ab.pressed.connect(func() -> void: open_account("" if Save.cloud.signed_in() else "login"))
	side.add_child(ab)
	_ui["acct"] = ab
	browser = RoomBrowser.new()
	browser.url = str(Settings.get_value("server_url"))
	var mainrow: HBoxContainer = get_node(O + "Main")
	mainrow.add_child(browser)
	mainrow.move_child(browser, 0)
	browser.join_requested.connect(join_room_id)
	browser.host_requested.connect(show_host.bind(true))
	_ui["leave"].pressed.connect(func() -> void: if session: session.leave("You left the room."))
	_refresh_login()
	_refresh_buttons()

## The title chip: tap (or click / Enter) opens the Account sheet. A big touch target like the gear.
func _build_chip() -> void:
	chip = $Safe/Col/Top/GuestChip
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.focus_mode = Control.FOCUS_ALL
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.custom_minimum_size = Vector2(0, 56)
	(chip.get_node("Row") as HBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed) \
				or e.is_action_pressed("ui_accept"):
			chip.accept_event()
			open_account())

## The Account sheet (guest: sign up / log in; signed in: the account page).
func open_account(pg := "") -> void:
	account.open(pg)

func _refresh_login() -> void:
	var u := Save.cloud.user()
	var logged := Save.cloud.signed_in()
	_ui["acct"].text = ("Signed in as " + u) if logged else "Log in to host"
	_ui["acct"].tooltip_text = "Your account" if logged else "Hosting a room needs an account. Joining works as a guest."
	who.text = ("Signed in as " + u.substr(0, 12)) if logged and u != "" else "Guest"
	var sync := Save.cloud.sync_text()
	who.tooltip_text = ("Account: sign up or log in to save to the cloud" if not logged else "Signed in: " + u) + ("\n" + sync if sync != "" else "")
	chip.tooltip_text = who.tooltip_text

func _refresh_buttons() -> void:
	var on := session != null and session.is_active()
	_ui["join"].disabled = on
	_ui["host"].disabled = on
	_ui["leave"].visible = on
	_ui["join"].visible = not on
	if not on:
		_ui["roster"].text = ""
		show_lobby(false)

## A room from the public list.
func join_room_id(id: String) -> void:
	if session != null and session.is_active(): return
	_ui["room"].text = id
	join_room()

func join_room() -> void:
	if session != null and session.is_active(): return
	var url := str(Settings.get_value("server_url")).strip_edges()
	var room := str(_ui["room"].text).strip_edges()      # the server matches codes case-insensitively
	var nm := str(_ui["name"].text).strip_edges().substr(0, 12)
	if nm == "": nm = "Player"
	if room == "":
		_status("Type the room code your friend gave you, or pick a room from the list.")
		return
	Settings.set_value("room_code", room); Settings.set_value("name", nm)
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
	if session is HostSession: (session as HostSession).hosted.connect(_on_hosted)
	_refresh_buttons()

func _unbind_session() -> void:
	session.status_changed.disconnect(_on_status)
	session.ended.disconnect(_on_ended)
	session.roster_changed.disconnect(_on_roster)
	session.match_started.disconnect(_enter_match)
	if session is HostSession and (session as HostSession).hosted.is_connected(_on_hosted): (session as HostSession).hosted.disconnect(_on_hosted)

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
	if session != null and session.is_active() and (session.slot >= 0 or session.is_host()) and not session.started:
		_fill_lobby()
		show_lobby(true)

## `start` from the host: into the match (the world takes the session over).
func _enter_match(s: Dictionary) -> void:
	if not is_inside_tree(): return
	_unbind_session()
	show_lobby(false)
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

# ---------------- hosting and the lobby ----------------

func _sheet_frame(sheet_name: String, title: String, min_w: float) -> VBoxContainer:
	var sh := Control.new()
	sh.name = sheet_name
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sh.visible = false
	add_child(sh)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sh.add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sh.add_child(cc)
	var card := PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(min_w, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var t := Label.new()
	t.name = "Title"
	t.text = title
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override("font_size", 30)
	box.add_child(t)
	return box

## One labelled row of toggle pills (the setup wizard's style).
func _pill_row(box: Control, row_name: String, label: String, keys: Array, names: Array, prefix: String, on_pick: Callable) -> void:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var l := Label.new()
	l.text = label
	l.theme_type_variation = &"MutedLabel"
	l.add_theme_font_size_override("font_size", 18)
	l.custom_minimum_size = Vector2(110, 0)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(l)
	var g := ButtonGroup.new()
	for i in keys.size():
		var b := Button.new()
		b.name = "P" + str(keys[i])
		b.text = str(names[i])
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(on_pick.bind(keys[i]))
		row.add_child(b)
		_host_bs[prefix + str(keys[i])] = b

func _build_host_sheet() -> void:
	var box := _sheet_frame("HostSheet", "Host a room", 620)
	host_sheet = get_node("HostSheet")
	var nm := LineEdit.new()
	nm.name = "RoomName"
	nm.placeholder_text = "Room name"
	nm.max_length = 24
	nm.custom_minimum_size = Vector2(0, 48)
	nm.add_theme_font_size_override("font_size", 18)
	box.add_child(nm)
	_ui["rname"] = nm
	_pill_row(box, "Vis", "Who can join", [0, 1], ["Private (code)", "Public"], "pub_", func(k: int) -> void: _host["pub"] = k == 1)
	_pill_row(box, "Max", "Seats", [2, 3, 4, 5, 6, 7, 8], ["2", "3", "4", "5", "6", "7", "8"], "max_", func(k: int) -> void: _host["max"] = k)
	_pill_row(box, "Bots", "Bots", [0, 1, 2, 3, 4, 5, 6, 7], ["0", "1", "2", "3", "4", "5", "6", "7"], "bots_", func(k: int) -> void: _host["bots"] = k)
	var hint := Label.new()
	hint.name = "Hint"
	hint.theme_type_variation = &"MutedLabel"
	hint.add_theme_font_size_override("font_size", 16)
	hint.text = "Game type and arena: your last Play setup (online plays Classic-style games)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 20)
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var cancel := Button.new()
	cancel.name = "Cancel"; cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(140, 54)
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.pressed.connect(show_host.bind(false))
	row.add_child(cancel)
	var go := Button.new()
	go.name = "Create"; go.text = "Create room"
	go.theme_type_variation = &"PrimaryButton"
	go.size_flags_horizontal = SIZE_EXPAND_FILL
	go.custom_minimum_size = Vector2(0, 54)
	go.add_theme_font_size_override("font_size", 22)
	go.pressed.connect(func() -> void: host_room())
	row.add_child(go)
	var h: Variant = Settings.get_value("host_opts", {})
	if h is Dictionary:
		for k in ["pub", "max", "bots"]:
			if h.has(k): _host[k] = h[k]
	_host["max"] = clampi(int(_host["max"]), 2, 8); _host["bots"] = clampi(int(_host["bots"]), 0, 7)
	_host_bs["pub_" + str(1 if _host["pub"] else 0)].button_pressed = true
	_host_bs["max_" + str(_host["max"])].button_pressed = true
	_host_bs["bots_" + str(_host["bots"])].button_pressed = true

func show_host(on: bool) -> void:
	host_sheet.visible = on
	if on:
		if str(_ui["rname"].text) == "": _ui["rname"].text = (str(_ui["name"].text).strip_edges().substr(0, 12) if str(_ui["name"].text).strip_edges() != "" else "Player") + "'s room"
		if Tier.is_pc(): (_ui["rname"] as LineEdit).grab_focus.call_deferred()

## Create room: a HostSession with the sheet's options; the game type, arena, floor and bot skill come from the
## last Play setup (Settings), the mode through HostSession.net_mode.
func host_room() -> void:
	if session != null and session.is_active(): return
	var url := str(Settings.get_value("server_url")).strip_edges()
	var nm := str(_ui["name"].text).strip_edges().substr(0, 12)
	if nm == "": nm = "Player"
	Settings.set_value("name", nm)
	Settings.set_value("host_opts", _host.duplicate())
	var mode := HostSession.net_mode(str(Settings.get_value("mode", "classic")))
	var mp := str(Settings.get_value("offline_map", "arena"))
	var allowed := SetupWizard.maps_for(mode)
	if not allowed.has(mp): mp = "arena" if allowed.has("arena") or allowed.is_empty() else str(allowed[0])
	show_host(false)
	session = HostSession.new()
	_bind_session()
	(session as HostSession).begin_host(url, {"name": str(_ui["rname"].text), "pub": _host["pub"], "max": _host["max"], "bots": int(_host["bots"]),
		"mode": mode, "map": mp, "dyn": str(Settings.get_value("dyn", "off")), "diff": str(Settings.get_value("difficulty", "normal"))},
		{"name": nm, "skin": Settings.get_value("skin", "none"), "hat": Settings.get_value("hat", "none"),
		"color": Settings.get_value("color", 0x39b5a8), "cls": Settings.get_value("class", "wobbler")}, str(Settings.get_value("token", "")))
	_refresh_buttons()

func _on_hosted(_code: String) -> void:
	_fill_lobby()
	show_lobby(true)

func _build_lobby() -> void:
	var box := _sheet_frame("Lobby", "Lobby", 620)
	lobby = get_node("Lobby")
	var code := Label.new()
	code.name = "Code"
	code.add_theme_font_size_override("font_size", 22)
	code.theme_type_variation = &"MutedLabel"
	box.add_child(code)
	var grid := GridContainer.new()
	grid.name = "Players"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	var info := Label.new()
	info.name = "Info"
	info.theme_type_variation = &"MutedLabel"
	info.add_theme_font_size_override("font_size", 16)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 20)
	box.add_child(info)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var lv := Button.new()
	lv.name = "Leave"; lv.text = "Leave"
	lv.custom_minimum_size = Vector2(140, 54)
	lv.add_theme_font_size_override("font_size", 20)
	lv.pressed.connect(func() -> void: if session: session.leave("You left the room."))
	row.add_child(lv)
	var st := Button.new()
	st.name = "Start"; st.text = "Start"
	st.theme_type_variation = &"PrimaryButton"
	st.size_flags_horizontal = SIZE_EXPAND_FILL
	st.custom_minimum_size = Vector2(0, 54)
	st.add_theme_font_size_override("font_size", 22)
	st.pressed.connect(func() -> void: if session is HostSession: (session as HostSession).start_match())
	row.add_child(st)

func show_lobby(on: bool) -> void:
	if lobby: lobby.visible = on

## The lobby card from the session: room name / code, a line per player (the host first), Start for the host.
func _fill_lobby() -> void:
	var box := lobby.get_node("Center/Card/Box")
	var hs: HostSession = session as HostSession if session is HostSession else null
	var roster: Array = session.roster if session != null else []
	(box.get_node("Title") as Label).text = (session.room_name if session != null and session.room_name != "" else "Lobby").substr(0, 24)
	var code: Label = box.get_node("Code")
	if session == null: code.text = ""
	elif hs != null: code.text = ("Public room · " if hs.pub else "Room code ") + hs.room_code
	else: code.text = "Room code " + session.room_code.to_upper()
	var grid: GridContainer = box.get_node("Players")
	for c in grid.get_children(): c.queue_free()
	for r: Dictionary in roster:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		l.text = "%s%s" % [r.get("name", "?"), "  (host)" if int(r.get("id", -1)) == 0 else ""]
		grid.add_child(l)
	var seats := hs.opt_max if hs != null else int(session.lobby.get("max", 0)) if session != null else 0
	var info: Label = box.get_node("Info")
	info.text = "%d / %d players" % [roster.size(), seats] + (" · empty seats get bots" if (hs != null and hs.opt_bots) or (hs == null and session != null and session.lobby.get("bots", false)) else "") \
		+ ("" if hs != null else " · waiting for the host to start")
	(box.get_node("Buttons/Start") as Button).visible = hs != null
