extends Control
## Title scene, readable in two seconds: the logo, one huge "Play" (offline, against computer players: opens the setup
## wizard, ui/setup_wizard.gd: Game type -> Arena -> Players -> Character -> Start), and an icon dock with "Quick play"
## (logic/quick_play.gd: an all-random offline match straight away, no wizard: random arena and mode), "Online" (the
## online panel), Walldrobe, Shop and Goals. The online
## panel: your name, the public room list (ui/room_browser.gd: tap a room to join, Refresh, the row / kind of room,
## empty / error states), "Join with a code" for private rooms (GuestSession), "Host a room" (the host sheet: room name,
## room type Versus / Arcade co-op, public / private, seats, bots -> HostSession) and an account button; both roles wait
## in the lobby sheet (the players, Start for the host, Leave). An Arcade co-op room is the Construction DLC's two-seat
## boss rush: its lobby starts with two players, or with one and the teammate bot ("Start with bot"); a guest cannot
## start it.
## A chip saying who you are ("Guest" or "Signed in as NAME"; tap it for the Account sheet, ui/account_sheet.gd),
## a gear for the Settings screen (ui/settings_screen.gd: Controls, Camera, Graphics, Audio, Gameplay, Account,
## About) and a coin chip (tap: the Shop). On the very first launch the how-to cards (ui/intro_cards.gd) show once.
## Back everywhere: the Back buttons, Escape / controller B (ui_cancel) and Android's back gesture (go_back(): the top
## sheet or page closes; on the title itself nothing happens, the app never quits on back).
## Laid out with containers inside a safe-area MarginContainer so nothing overlaps at any aspect ratio
## (tests/ui_layout_test.gd checks 852x393, 667x375, 1170x540 and 1280x720 on every page and sheet).
## Layout (docs/TITLE.md, "Hero Stage"): the 3D STAGE (ui/title_showcase.gd: your wobbler big on a site pedestal and a
## tower crane holding a DLC pack's container) fills the whole screen behind everything. On top, in the safe area: the
## logo (two lines) top left; the coin chip (tap: the Shop), the account chip and the gear top right; the icon dock
## bottom left (Quick play, Online, Walldrobe, Shop, Goals: ui/title_dock.gd); one huge Play button bottom right with the
## version under it. The single DLC entry is the hazard-striped CONSTRUCTION pill hanging from the container (tap it, or
## the container: the showcase opens). Landscape only.
## Command line (after `--`): --join=ROOM [--server=ws://host:3000/ws] [--name=NAME] joins straight away;
## --mode=ID / --map=ID preselect the wizard (the world reads them too when it starts).

const WORLD := "res://world/world.tscn"
const DLC_TIPS := [
	"Hard hats on. Mind the open edges: one big swing and you are off the slab.",
	"Scaffold towers and timber stacks make good cover.",
	"Site rule: knock fighters off the slab for a K.O.",
]
const TRIAL_BOTS := 2              ## bots in a DLC test drive (easy ones: it is a place to try the tools)
const MARGIN := Vector4(28, 18, 28, 14)   ## left, top, right, bottom padding inside the safe area (the other pages)
const HOME_MARGIN := Vector4(28, 16, 28, 20)   ## the same on the title home: a little more air under the dock and Play
const TIPS := [
	"Tip: push the stick to the edge to sprint.",
	"Tip: knock other players off the edge to score.",
	"Tip: crates drop weapons, heals and power-ups.",
	"Tip: kick and shove work even without a weapon.",
	"Tip: the edge of the arena is not your friend.",
	"Tip: a dash gets you across gaps your legs can't.",
	"Tip: Spring Glove does no damage, but it sends people flying.",
	"Tip: hit the head for extra damage. Rude, but effective.",
	"Tip: falling over is part of the fun. Get back up and bonk someone.",
	"Tip: goals refresh every day. Free coins, no catch.",
]
const ONLINE_SUB := "Needs internet · public rooms or a code"

## The tip the Play button's tooltip carries (the title has no room for a tip line any more).
var tip_text := ""

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
@onready var hero: Control = $Safe/Hero               ## the title home's own controls: the dock, Play and the version line
var play: Button                   ## the huge yellow Play button (bottom right)
var online_b: Button               ## Online (dock)
var dock: TitleDock                ## the icon dock (bottom left)
var coins_chip: PanelContainer     ## the coin count (top right); tap: the Shop
var _coins_l: Label
var showcase: TitleShowcase        ## the 3D stage behind the title + its controls (ui/title_showcase.gd)
var quick_b: Button                ## Quick play (dock): a random arena and mode straight into an offline match (logic/quick_play.gd)
@onready var status: Label = get_node(O + "Foot/Status")
var wizard: SetupWizard
var locker: LockerScreen            ## the Walldrobe / Shop screen (hidden until opened)
var locker_b: Button
var shop_b: Button
var goals_b: Button
var goals: GoalsScreen              ## the Goals screen (title: Goals)
var hub: ConstructionHub            ## the Construction DLC hub (Play on the Construction title, UNLOCK PACK)
var dlc := false                    ## the Construction title is showing (never saved: the app always opens on the normal title)
var _wipe: DlcTransition
var news_dot: Control
var news: WhatsNew                  ## the What's new card (patch notes; opens once per new version)
var settings: SettingsScreen        ## the Settings screen (gear)
var intro: IntroCards               ## the first-run how-to (also Settings > Controls)
var browser: RoomBrowser            ## public rooms in the online panel
## true / false: show the how-to on start or not; null = when it was never seen (not in tests: they run with --no-save)
var auto_intro: Variant = null
## true / false: open the What's new card on start when the newest notes are unseen or not; null = when unseen (not in tests)
var auto_news: Variant = null
var _ui := {}
var account: AccountSheet           ## the Account sheet (title chip)
var chip: PanelContainer
var host_sheet: Control             ## "Host a room": name, room type, public / private, seats, bots
var lobby: Control                  ## the room's lobby: players, Start / Start with bot (host only), Leave
var _host := {"type": "versus", "pub": false, "max": 4, "bots": 2, "mode": "classic", "lim": -1, "hp": 200, "grav": 1.0, "kb": 1.0, "crate": "normal", "inf": false, "dyn": "off"}
var _host_bs := {}                  ## "type_versus/coop", "pub_0/1", "max_N", "bots_N" -> Button
var _host_tab := "Room"             ## the Host sheet's current tab
var _join_kind := ""                ## the room-list row's kind the next join expects ("" = any kind)

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
	_build_hero()
	_build_showcase()                 # (before the sheets below, so every page and sheet opens on top of it)
	_build_coins()
	_build_wipe()
	(get_node(O + "Head/Back") as Button).pressed.connect(show_tab.bind(false))
	gear.icon = _gear_icon()
	gear.pressed.connect(show_settings.bind(true))
	settings = SettingsScreen.new()
	add_child(settings)
	settings.closed.connect(func() -> void: if Tier.is_pc(): gear.grab_focus.call_deferred())
	settings.account_requested.connect(func() -> void: open_account())
	goals = GoalsScreen.new()
	add_child(goals)
	goals.closed.connect(func() -> void:
		_refresh_dock()
		if Tier.is_pc(): goals_b.grab_focus.call_deferred())
	hub = ConstructionHub.new()
	add_child(hub)
	hub.start_requested.connect(play_offline)
	hub.arcade_requested.connect(play_arcade)
	hub.closed.connect(func() -> void:
		_refresh_dock()
		showcase.refresh()             # (it may have been bought: UNLOCK PACK becomes OWNED)
		if Tier.is_pc(): (showcase.test_b if showcase.is_open() else showcase.pill).grab_focus.call_deferred())
	news = WhatsNew.new()
	add_child(news)
	news.closed.connect(func() -> void:
		_news_dot()
		if Tier.is_pc() and not settings.visible: gear.grab_focus.call_deferred())
	settings.news_requested.connect(open_news)
	_news_dot()
	_build_host_sheet()
	_build_lobby()
	tip_text = tr(TIPS[randi() % TIPS.size()])
	account = AccountSheet.new()
	add_child(account)
	account.closed.connect(func() -> void:
		if settings.visible: settings.show_section(settings.section)   # the Account section shows who you are now
		elif Tier.is_pc(): gear.grab_focus.call_deferred())
	Save.cloud.done.connect(func(_op: String, _ok: bool, _msg: String) -> void: _refresh_login())
	Save.cloud.changed.connect(_refresh_login)
	RemoteConfig.refreshed.connect(func(_ok: bool) -> void: _refresh_remote_gates())
	_build_chip()
	_build_online()
	_refresh_remote_gates()
	_status(tr(notice) if notice != "" else tr("Pick a room, or join a friend with their code."))
	if session != null:
		_bind_session()
		_status((tr(notice) + "  " if notice != "" else "") + session.status)
		_on_roster(session.roster)
	var join := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--join="): join = a.substr(7)
		elif a.begins_with("--server="): Settings.set_value("server_url", a.substr(9))
		elif a.begins_with("--name="): _ui["name"].text = a.substr(7)
		elif a.begins_with("--mode=") and SetupWizard.modes().has(a.substr(7)): wizard.set_mode(a.substr(7))
		elif a.begins_with("--map=") and Content.maps.has(a.substr(6)): wizard.set_map(a.substr(6))
	_tip_room()
	show_tab(notice != "" or session != null or join != "")
	if join != "" and session == null:
		_ui["room"].text = join
		join_room()
	JuicyButton.attach_all(self)
	if not Save.cloud.pending.is_empty(): account.open("conflict")   # a cloud conflict found during a match
	get_viewport().size_changed.connect(apply_safe_area)
	get_viewport().size_changed.connect(_tip_room)
	apply_safe_area()
	if Tier.is_pc():
		play.grab_focus.call_deferred()   # keyboard / gamepad start on Play
	get_tree().set_quit_on_go_back(false)  # Android back never quits from a menu: go_back() handles it
	intro = IntroCards.new()
	add_child(intro)
	intro.closed.connect(func() -> void: if Tier.is_pc(): play.grab_focus.call_deferred())
	var first: bool = auto_intro if auto_intro is bool else (Settings.persist and not bool(Settings.get_value("seen_intro", false)))
	var quiet := session == null and join == "" and notice == ""
	var newest := WhatsNew.newest_version()
	# A brand-new player does not need the old notes. Mark them seen on the FIRST visit whichever card opens: before, this
	# only ran when the intro did not open, so a new player's first return to the title (after Play / Quick play) popped
	# What's new.
	if first and Save.persist: Save.mark_news_seen(newest)
	if first and quiet: intro.open()
	else:
		var unseen: bool = auto_news if auto_news is bool else (Save.persist and newest != "" and newest != Save.last_seen_news)
		if unseen and quiet and not first: news.open()

## Back (Escape / controller B via ui_cancel, Android's back gesture): close the top thing. The wizard and the Walldrobe
## handle ui_cancel themselves; the back gesture reaches them through here. On the bare title nothing happens.
func go_back() -> bool:
	if intro.visible: return intro.back()
	if account.visible: return account.back()
	if news.visible: return news.back()      # (opened from Settings > About: it sits on top of Settings)
	if settings.visible: return settings.back()
	if goals.visible: return goals.back()
	if hub.visible: return hub.back()
	if lobby.visible:
		if session: session.leave("You left the room.")
		show_lobby(false)
		return true
	if host_sheet.visible: show_host(false); return true
	if showcase.is_open(): return showcase.back()      # the open DLC container: doors shut, back to the title
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
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready() and is_inside_tree():
		apply_safe_area.call_deferred()       # the rail fits its words again
		showcase.refresh.call_deferred()

func _process(dt: float) -> void:
	if session != null:
		session.poll(dt)

## The offline arenas for a mode (SetupWizard.maps_for).
func maps_for(mode: String) -> Array:
	return SetupWizard.maps_for(mode)

## The 3D stage (ui/title_showcase.gd): its picture fills the whole screen behind the title's controls, its own controls
## (the CONSTRUCTION pill, and Back / the pack bar while a container is open) on top of them. The stage itself is the tap
## layer under the controls (a tap on the container opens it: the title's containers ignore the mouse for that); while a
## container opens the title's controls fade out and come back on Back.
func _build_showcase() -> void:
	showcase = TitleShowcase.new()
	add_child(showcase)
	move_child(showcase, $Background.get_index() + 1)
	add_child(showcase.overlay)
	move_child(showcase.overlay, safe.get_index() + 1)
	showcase.covered = func() -> bool:
		return (settings != null and settings.visible) or (goals != null and goals.visible) or (hub != null and hub.visible)
	showcase.ui_changed.connect(_on_showcase_ui)
	showcase.test_requested.connect(play_trial)
	showcase.unlock_requested.connect(func(_p: DLCPackData) -> void: open_hub())   # the existing unlock flow: coins or the code
	showcase.site_requested.connect(toggle_dlc)                                    # DON'T ENTER / EXIT SITE: the Construction title
	Save.changed.connect(showcase.refresh)
	$Background.stage_3d = true

## The open container takes the screen: the title's own controls fade with `k` (1 = gone, and out of the focus order).
func _on_showcase_ui(k: float) -> void:
	safe.modulate.a = 1.0 - k
	safe.visible = k < 0.995

## The stage and the title's controls belong to the title home: other pages (wizard, Walldrobe, online tab) replace them.
func _home_layers() -> void:
	var on := col.visible and home.visible
	hero.visible = on
	coins_chip.visible = on
	showcase.set_shown(on)
	apply_safe_area()

## The stage's frame: the padded safe area (the idle scene is framed inside it) and the touch-size factor.
func _push_frame() -> void:
	if showcase == null or not is_inside_tree(): return
	var vs := get_viewport_rect().size
	var l := float(safe.get_theme_constant("margin_left"))
	var t := float(safe.get_theme_constant("margin_top"))
	var r := float(safe.get_theme_constant("margin_right"))
	var b := float(safe.get_theme_constant("margin_bottom"))
	showcase.set_frame(Rect2(l, t, vs.x - l - r, vs.y - t - b), _unit())

## Touch-size factor: 1 in landscape (UiScale keeps 60 canvas px at 44 pt there). A portrait window shows the same
## 1170 px wide canvas on a third of the points, so the title's controls grow until 60 * unit px is 44 pt again.
func _unit() -> float:
	var vs := get_viewport_rect().size
	return 1.0 if vs.y <= vs.x else clampf(vs.y / vs.x * 1.12, 1.0, 2.45)

## A DLC test drive (the showcase's "TEST IN <arena>"): a solo sandbox on the pack's arena with every weapon of the
## pack on the floor round the start. Open to everyone, owner or not: the world's `trial` flag keeps coins, stats,
## goals and history untouched, and nothing here touches the unlock (docs/TITLE.md).
func play_trial(p: DLCPackData) -> void:
	if p == null or not Content.maps.has(p.arena_id): return
	if session != null: session.leave("")
	var world: Node = load(WORLD).instantiate()
	world.map_id = p.arena_id
	world.mode_id = p.test_mode if Content.modes.has(p.test_mode) else "classic"
	world.bot_count = TRIAL_BOTS
	world.difficulty = "easy"
	world.ko_limit = 0
	world.dyn_choice = "off"
	world.trial = true
	world.trial_weapons = Array(p.real_weapons(Content.weapons))
	get_tree().change_scene_to_node(world)

## The title's own controls: the icon dock (Quick play, Online, Walldrobe, Shop, Goals), the huge Play button and the
## version line (all in `hero`, laid out by apply_safe_area). Routes are the ones the old menu rail had.
func _build_hero() -> void:
	home.add_theme_constant_override("separation", UiTheme.SP_3)
	home.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock = TitleDock.new()
	hero.add_child(dock)
	quick_b = dock.add_item("Quick", "quick", "Quick play")
	quick_b.tooltip_text = tr("Random arena and mode")
	quick_b.pressed.connect(quick_play)
	online_b = dock.add_item("Online", "online", "Online")
	online_b.tooltip_text = tr(ONLINE_SUB)
	online_b.pressed.connect(show_tab.bind(true))
	locker_b = dock.add_item("Locker", "wall", "Walldrobe")
	locker_b.tooltip_text = tr("What you own")
	locker_b.pressed.connect(open_locker.bind(false))
	shop_b = dock.add_item("Shop", "shop", "Shop")
	shop_b.pressed.connect(open_locker.bind(true))
	goals_b = dock.add_item("Goals", "goals", "Goals")
	goals_b.pressed.connect(open_goals)
	play = Button.new()
	play.name = "Play"
	play.theme_type_variation = &"PrimaryButton"
	play.set("accessibility_name", "Play")
	var pr := HBoxContainer.new()                  # the triangle and the word (a Button's own icon would not centre beside its text)
	pr.name = "Row"
	pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.add_theme_constant_override("separation", 14)
	play.add_child(pr)
	var pi := TextureRect.new()
	pi.name = "Icon"
	pi.texture = _play_icon()
	pi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pi.modulate = UiTheme.INK
	pr.add_child(pi)
	var pl := Label.new()
	pl.name = "Big"
	pl.text = "Play"
	pl.add_theme_font_override("font", UiTheme.font(700))
	pl.add_theme_color_override("font_color", UiTheme.INK)
	pl.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.add_child(pl)
	play.pressed.connect(func() -> void: if dlc: open_hub() else: open_wizard())   # on the Construction title Play opens the hub
	hero.add_child(play)
	hero.move_child(play, 0)
	Save.changed.connect(_refresh_dock)
	_refresh_dock()

## The coin chip (top right, beside the account chip and the gear): tap it for the Shop.
func _build_coins() -> void:
	coins_chip = PanelContainer.new()
	coins_chip.name = "Coins"
	coins_chip.theme_type_variation = &"ChipPanel"
	coins_chip.mouse_filter = Control.MOUSE_FILTER_STOP
	coins_chip.focus_mode = Control.FOCUS_ALL
	coins_chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var sb := UiTheme.box(Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.9), 99, UiTheme.PANEL_EDGE, UiTheme.BORDER, 4)
	sb.content_margin_left = 10; sb.content_margin_right = 16; sb.content_margin_top = 5; sb.content_margin_bottom = 5
	coins_chip.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coins_chip.add_child(row)
	var ic := LockerScreen.LockerIcon.new("coin", 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	_coins_l = Label.new()
	_coins_l.name = "Amount"
	_coins_l.add_theme_font_size_override("font_size", 20)
	_coins_l.add_theme_font_override("font", UiTheme.font(700))
	_coins_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coins_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_coins_l)
	var top := $Safe/Col/Top
	top.add_child(coins_chip)
	top.move_child(coins_chip, $Safe/Col/Top/GuestChip.get_index())
	coins_chip.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT) or (e is InputEventScreenTouch and e.pressed) \
				or e.is_action_pressed("ui_accept"):
			coins_chip.accept_event()
			open_locker(true))
	coins_chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_refresh_dock()

## The Play button's triangle (no image files), drawn dark so it sits on the yellow like the label.
static func _play_icon() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var a := Vector2(14, 8)
	var b := Vector2(14, 56)
	var c := Vector2(54, 32)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := minf(minf(_edge(p, a, b), _edge(p, b, c)), _edge(p, c, a))   # inside when all three are positive
			var cov := clampf(d + 0.5, 0.0, 1.0)
			if cov > 0.0: img.set_pixel(x, y, Color(1, 1, 1, cov))
	return ImageTexture.create_from_image(img)

static func _edge(p: Vector2, a: Vector2, b: Vector2) -> float:
	var e := b - a
	return (e.x * (p.y - a.y) - e.y * (p.x - a.x)) / e.length() * -1.0

## Quick play: a random game type, arena, class, floor, bot count and bot skill; straight into the offline match (no
## wizard). The world takes the class and the floor from Settings, so those two are written first (like the
## Construction hub's Start); play_offline gets the four keys it takes.
func quick_play() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var over := QuickPlay.pick(rng)
	Settings.set_value("class", str(over["class"]))
	Settings.set_value("dyn", str(over["dyn"]))
	play_offline({"mode": over["mode"], "map": over["map"], "bots": over["bots"], "difficulty": over["difficulty"]})

## The tape wipe that plays between the normal and the Construction title (the DON'T ENTER / EXIT SITE sign and pill).
func _build_wipe() -> void:
	_wipe = DlcTransition.new()
	_wipe.name = "Wipe"
	add_child(_wipe)

## A gold dot on the gear while the newest patch notes are unseen (What's new lives in Settings > About, one button fewer on the title).
func _news_dot() -> void:
	if news_dot == null:
		news_dot = Control.new()
		news_dot.name = "Dot"
		news_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		news_dot.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		news_dot.offset_left = -20; news_dot.offset_right = -6; news_dot.offset_top = 6; news_dot.offset_bottom = 20
		news_dot.draw.connect(func() -> void:
			news_dot.draw_circle(Vector2(7, 7), 8.0, UiTheme.INK)
			news_dot.draw_circle(Vector2(7, 7), 6.0, UiTheme.ACCENT))
		gear.add_child(news_dot)
	var newest := WhatsNew.newest_version()
	news_dot.visible = newest != "" and newest != Save.last_seen_news

## The coin count, the Shop's and the Goals' tooltips, and the badge on the Goals tile (how many goals wait to be claimed).
func _refresh_dock() -> void:
	if _coins_l: _coins_l.text = str(Save.coins)
	if coins_chip: coins_chip.tooltip_text = tr("You have %d coins") % Save.coins
	if shop_b: shop_b.tooltip_text = tr("You have %d coins") % Save.coins
	if goals_b:
		var n := Save.goals_to_claim()
		goals_b.set_badge(n)
		goals_b.tooltip_text = (tr("%d to claim") % n) if n > 0 else tr("Daily coin goals")
	if is_node_ready(): apply_safe_area.call_deferred()

## The Goals screen over the title.
func open_goals() -> void:
	goals.open()

## The Construction hub (Classic / Arcade, the DLC unlock) over the title.
func open_hub() -> void:
	hub.open()

## The What's new card over the title.
func open_news() -> void:
	news.open()

## The Walldrobe (shop = false) or the Shop instead of the title column.
func open_locker(shop_mode: bool = false, tab: String = "") -> void:
	col.visible = false
	_home_layers()
	wizard.visible = false
	locker.visible = true
	locker.open(shop_mode, tab)

func close_locker() -> void:
	locker.visible = false
	col.visible = true
	_home_layers()
	showcase.stage.refresh_look()       # the look may have changed: the wobbler on the stage wears it
	if wizard.stage:                    # the look may have changed: the Character page renders it again
		wizard.stage.baked.clear()
		wizard.stage.current = ""
	_refresh_dock()
	if Tier.is_pc(): locker_b.grab_focus.call_deferred()

## The title (Play / Play online with friends) or the online panel.
func show_tab(online: bool) -> void:
	browser.url = str(Settings.get_value("server_url"))
	if online and session == null and _remote_online_blocked():
		_status("Online play is temporarily unavailable. You can keep playing offline." if not RemoteConfig.update_required()
			else "Please update Wobblers Arena before playing online.")
		return
	home.visible = not online
	online_panel.visible = online
	_home_layers()                            # (the dock, Play and the stage leave with the home; the logo fits the header again)
	_tip_room()
	if online and Tier.is_pc(): (get_node(O + "Head/Back") as Button).grab_focus.call_deferred()
	elif not online and Tier.is_pc(): online_b.grab_focus.call_deferred()

func _remote_online_blocked() -> bool:
	return RemoteConfig.killed("online") or RemoteConfig.update_required()

func _refresh_remote_gates() -> void:
	var blocked := _remote_online_blocked()
	online_b.disabled = blocked and session == null
	online_b.modulate.a = 0.5 if online_b.disabled else 1.0
	online_b.tooltip_text = ("Update the game to play online." if RemoteConfig.update_required()
		else ("Online play is temporarily unavailable." if RemoteConfig.killed("online") else ONLINE_SUB))

## The tip (the Play button's tooltip, with the last setup).
func _tip_room() -> void:
	play.tooltip_text = (tr("Last time: %s") % wizard.summary_line()) + "\n" + tip_text

## The setup wizard (page 0 = Game type) instead of the title column.
func open_wizard(p: int = 0) -> void:
	col.visible = false
	_home_layers()
	wizard.visible = true
	wizard.go(p)

func close_wizard() -> void:
	wizard.visible = false
	col.visible = true
	_home_layers()
	_tip_room()
	if Tier.is_pc(): play.grab_focus.call_deferred()

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

## Status line in the online panel; while connected the Online button's tooltip shows it too.
func _status(t: String) -> void:
	status.text = t
	status.tooltip_text = t
	if session != null and session.is_active(): online_b.tooltip_text = tr("Connected · %s") % t

## The logo in the header: as big as the room beside the chip and the gear allows (the online tab keeps a compact one:
## the room list needs the height). When even a small single line does not fit (a long account name on a small phone)
## the two words stack.
func _fit_logo(avail: float, max_font: int) -> void:
	var logo := $Safe/Col/Top/Logo as WobbleLogo
	for two: bool in [false, true]:
		logo.lines = WobbleLogo.names(two)
		var f := mini(max_font, 46) if two else max_font
		var floor_f := 22 if two else 38
		while f >= floor_f:
			logo.font_size = f
			if logo.get_combined_minimum_size().x <= avail: return
			f -= 2

## The title home's logo: two lines (WOBBLERS / ARENA), `max_font` unless the room beside the chips is narrower.
func _fit_logo_two(avail: float, max_font: int) -> void:
	var logo := $Safe/Col/Top/Logo as WobbleLogo
	logo.lines = WobbleLogo.names(true)
	var f := max_font
	while f > 24:
		logo.font_size = f
		if logo.get_combined_minimum_size().x <= avail: return
		f -= 2

## The safe area's height in canvas px (the viewport minus the phone insets).
func _safe_height() -> float:
	var i := SafeArea.insets(get_viewport())
	return get_viewport_rect().size.y - float(i[1]) - float(i[3])

## Safe-area insets (notch, home indicator) plus our own padding, then the title home: the logo and the chips in the top
## row (Safe/Col/Top), the dock bottom left, Play bottom right with the version under it (Safe/Hero, anchored to the
## corners of the padded safe area). Landscape; the other pages (wizard, Walldrobe, online tab) keep the old padding
## and take the column.
func apply_safe_area() -> void:
	if not is_inside_tree(): return
	var i := SafeArea.insets(get_viewport())
	var vs := get_viewport_rect().size
	var u := _unit()
	var home_on := hero.visible
	var safe_h := _safe_height()
	var short := safe_h < 620.0 and not home_on      # (the online panel and the wizard need the height on small phones)
	var m: Vector4 = HOME_MARGIN if home_on else MARGIN * (Vector4(1, 0.45, 1, 0.45) if short else Vector4.ONE)
	safe.add_theme_constant_override("margin_left", int(m.x + i[0]))
	safe.add_theme_constant_override("margin_top", int(m.y + i[1]))
	safe.add_theme_constant_override("margin_right", int(m.z + i[2]))
	safe.add_theme_constant_override("margin_bottom", int(m.w + i[3]))
	var inner := Vector2(vs.x - float(int(m.x + i[0]) + int(m.z + i[2])), vs.y - float(int(m.y + i[1]) + int(m.w + i[3])))
	col.add_theme_constant_override("separation", UiTheme.SP_3 if short else UiTheme.SP_4)
	var k := minf(u, 2.0)
	gear.custom_minimum_size = Vector2(60, 60) * u
	gear.expand_icon = u > 1.0
	gear.add_theme_constant_override("icon_max_width", int(34.0 * u))
	if chip: chip.custom_minimum_size = Vector2(60.0 * u, 60.0 * u)
	who.add_theme_font_size_override("font_size", int(round(17.0 * k)))
	if coins_chip: coins_chip.custom_minimum_size = Vector2(0, 60.0 * u)
	if _coins_l: _coins_l.add_theme_font_size_override("font_size", int(round(20.0 * k)))
	col.size_flags_horizontal = Control.SIZE_FILL
	col.size_flags_vertical = Control.SIZE_FILL
	var top := $Safe/Col/Top as HBoxContainer
	var logo := $Safe/Col/Top/Logo as WobbleLogo
	for c: Control in [gear, chip, coins_chip]:
		if c: c.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if home_on else Control.SIZE_SHRINK_CENTER
	logo.size_flags_vertical = Control.SIZE_SHRINK_BEGIN if home_on else Control.SIZE_SHRINK_CENTER
	if home_on:
		_fit_hero(inner, u)
		# the logo: two lines, as big as 5 % of the width (the mock's 44 pt on an 852 pt phone), never wider than what the chips leave
		var chips_w := gear.custom_minimum_size.x + (chip.get_combined_minimum_size().x if chip else 90.0) + coins_chip.get_combined_minimum_size().x + 3.0 * 16.0 + 24.0
		_fit_logo_two(inner.x - chips_w, int(clampf(inner.x * 0.057 * minf(u, 1.9), 40.0, 92.0)))
	else:
		var chip_w: float = chip.get_combined_minimum_size().x if chip else 90.0
		var max_font := 46 if online_panel.visible else (int(68.0 * minf(u, 1.9)) if not short else 58)
		_fit_logo(inner.x - chip_w - gear.custom_minimum_size.x - 3.0 * 16.0 - 2.0, max_font)
	top.add_theme_constant_override("separation", 12 if home_on else 16)
	for sheet: String in ["HostSheet", "Lobby"]:      # a sheet's card is centred in the safe area, not on the whole screen
		var cc := get_node_or_null(sheet + "/Center") as Control
		if cc:
			cc.offset_left = float(i[0]); cc.offset_top = float(i[1]); cc.offset_right = -float(i[2]); cc.offset_bottom = -float(i[3])
	var hint := get_node_or_null("HostSheet/Center/Card/Box/Hint")
	if hint: hint.visible = get_viewport_rect().size.y >= 500.0      # on the shortest canvases the arena hint gives way (it is in the tooltip too)
	_push_frame.call_deferred()

## Dock bottom left, Play bottom right, the version under it: each anchored to its corner of the hero area.
func _fit_hero(inner: Vector2, u: float) -> void:
	var k := minf(u, 2.0)
	var ph := clampf(inner.y * 0.21, 84.0 * k, 128.0 * k)
	var pw := clampf(inner.x * 0.31, 250.0 * k, 400.0 * k)
	var d := dock.fit(k, inner.x - pw - 28.0 * k)          # (the dock never runs into Play, whatever the words are)
	_corner(dock, false, d, Vector2.ZERO)
	var build := hero.get_node("Build") as Label
	build.add_theme_font_size_override("font_size", int(round(14.0 * minf(u, 1.8))))
	var bs := build.get_combined_minimum_size()
	_corner(build, true, bs, Vector2.ZERO)
	var big := play.get_node("Row/Big") as Label
	var icon_w := ph * 0.42
	var row_gap := float((play.get_node("Row") as BoxContainer).get_theme_constant("separation"))
	var room := pw - icon_w - row_gap - 2.0 * 18.0 * k           # the word's room inside the button: its width minus the triangle, the gap and the padding
	FitText.label(big, int(ph * 0.6), room, 18)                  # "Play" keeps its size; 開始遊戲 / Jugar step down until the word fits
	(play.get_node("Row/Icon") as TextureRect).custom_minimum_size = Vector2(icon_w, icon_w)
	play.custom_minimum_size = Vector2(pw, ph)
	var lift := bs.y + 2.0
	if inner.y > inner.x: lift += d.y + 12.0 * k      # (portrait is not a target, but Play must never sit on the dock)
	_corner(play, true, Vector2(pw, ph), Vector2(0, lift))

## Anchors `c` to the bottom right (right = true) or bottom left corner of the hero area, `gap` away from it.
func _corner(c: Control, right: bool, sz: Vector2, gap: Vector2) -> void:
	c.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT if right else Control.PRESET_BOTTOM_LEFT, false)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_bottom = -gap.y
	c.offset_top = -gap.y - sz.y
	if right:
		c.offset_right = -gap.x
		c.offset_left = -gap.x - sz.x
	else:
		c.offset_left = gap.x
		c.offset_right = gap.x + sz.x

# ---------------- online ----------------

## The logged-in account's username (what online play uses as the player name), or "" when signed out.
func _account_name() -> String:
	if Save == null or Save.cloud == null or not Save.cloud.signed_in(): return ""
	return Safety.clean_name(Save.cloud.user()).substr(0, 12)

## Online name field: locked to the account name while signed in (no fake names online); free only when signed out
## (offline / REQUIRE_LOGIN=0 servers and headless tests).
func _sync_online_name() -> void:
	var an := _account_name()
	var ed := _ui["name"] as LineEdit
	if an != "":
		ed.text = an
		ed.editable = false
		ed.tooltip_text = tr("Online play uses your account name.")
	else:
		ed.editable = true
		ed.tooltip_text = ""

## The name used for any online role.
func _online_name() -> String:
	var an := _account_name()
	if an != "": return an
	var nm := str(_ui["name"].text).strip_edges().substr(0, 12)
	return nm if nm != "" else "Player"

func _build_online() -> void:
	var n := O + "Main/Side/"
	_ui["room"] = get_node(n + "CodeRow/Room")
	_ui["name"] = get_node(O + "Head/Name")
	_ui["join"] = get_node(n + "CodeRow/Join")
	_ui["leave"] = get_node(n + "CodeRow/Leave")
	_ui["roster"] = get_node(O + "Foot/Roster")
	_ui["room"].text = str(Settings.get_value("room_code", ""))
	_ui["name"].text = str(Settings.get_value("name", "Player"))
	_ui["name"].text_changed.connect(func(t: String) -> void:
		if _account_name() != "": return
		var clean := Safety.clean_name(t).substr(0, 12)
		if clean != "" and not Safety.bad_name(clean): Settings.set_value("name", clean))
	_sync_online_name()
	_ui["join"].pressed.connect(join_room)
	var rl := _ui["room"] as LineEdit
	rl.placeholder_text = "4-digit code"
	rl.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	rl.text_changed.connect(func(t: String) -> void:      # typed codes are 4 digits; list picks set the text in code (no signal)
		var digits := ""
		for ch in t:
			if ch >= "0" and ch <= "9": digits += ch
		if digits != t:
			var c := rl.caret_column
			rl.text = digits
			rl.caret_column = mini(c, digits.length()))
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
	ab.pressed.connect(func() -> void: open_account())
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
	chip.custom_minimum_size = Vector2(0, 60)
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
	if _ui.has("name"): _sync_online_name()
	var u := Save.cloud.user()
	var logged := Save.cloud.signed_in()
	_ui["acct"].text = (tr("Signed in as %s") % u) if logged else tr("Pick a name to host")
	_ui["acct"].tooltip_text = tr("Your account") if logged else tr("Hosting a room needs a name. Joining works as a guest.")
	who.text = (tr("Signed in as %s") % u.substr(0, 12)) if logged and u != "" else tr("Guest")
	var sync := Save.cloud.sync_text()
	who.tooltip_text = ((tr("Account: pick a name to save to the cloud") if not logged else tr("Signed in: %s") % u) + ("\n" + sync if sync != "" else ""))
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

## A room from the public list: the row says what kind of room it is (`kind`), so the join asks the server for that
## kind (a PvP screen never mistakes an Arcade co-op room for a normal one, docs/PROTOCOL.md 1.1/1.2).
func join_room_id(id: String) -> void:
	if session != null and session.is_active(): return
	_ui["room"].text = id
	_join_kind = ""
	for r: Dictionary in browser.rooms:
		if str(r.get("id", "")) == id:
			var k := str(r.get("kind", ""))
			if k == "pvp" or k == "arcade-coop": _join_kind = k
			break
	join_room()

func join_room() -> void:
	if session != null and session.is_active(): return
	var expect_kind := _join_kind
	_join_kind = ""
	var url := str(Settings.get_value("server_url")).strip_edges()
	var room := str(_ui["room"].text).strip_edges()      # the server matches codes case-insensitively
	var nm := _online_name()
	if room == "":
		_status("Type the room code your friend gave you, or pick a room from the list.")
		return
	Settings.set_value("room_code", room); Settings.set_value("name", nm)
	session = GuestSession.new()
	_bind_session()
	session.begin(url, room, {"name": nm, "skin": Settings.get_value("skin", "none"), "hat": Settings.get_value("hat", "none"),
		"color": Settings.get_value("color", 0x39b5a8), "cls": Settings.get_value("class", "wobbler")}, str(Settings.get_value("token", "")), expect_kind)
	_refresh_buttons()

func _bind_session() -> void:
	session.status_changed.connect(_on_status)
	session.ended.connect(_on_ended)
	session.roster_changed.connect(_on_roster)
	session.match_started.connect(_enter_match)
	session.promoted.connect(_on_promoted)
	if session is HostSession: (session as HostSession).hosted.connect(_on_hosted)
	_refresh_buttons()

func _unbind_session() -> void:
	session.status_changed.disconnect(_on_status)
	session.ended.disconnect(_on_ended)
	session.roster_changed.disconnect(_on_roster)
	session.match_started.disconnect(_enter_match)
	if session.promoted.is_connected(_on_promoted): session.promoted.disconnect(_on_promoted)
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
	for e: Dictionary in r: names.append(Safety.display_name(str(e.get("name", ""))))
	_ui["roster"].text = tr("In the room: %s") % ", ".join(names)
	if session != null and session.is_active() and (session.slot >= 0 or session.is_host()) and not session.started:
		_fill_lobby()
		show_lobby(true)

## `start` from the host: into the match (the world takes the session over). An Arcade co-op `start` carries `arc`: the
## world gets the run (host or guest side) and the generated site's map, and the usual hooks rebuild each stage.
func _enter_match(s: Dictionary) -> void:
	if not is_inside_tree(): return
	var run: Variant = s.get("arc")
	_unbind_session()
	show_lobby(false)
	var world: Node = load(WORLD).instantiate()
	world.session = session
	world.start_msg = s
	if ArcadeCoop.arc_valid(run):
		world.arcade = ArcadeManager.new_online(run, session is HostSession)
		world.map_id = str(s.get("map", ArcadeCoop.site_map()))
		world.mode_id = "construction"
	session = null
	get_tree().change_scene_to_node.call_deferred(world)

## Starts the offline match the wizard describes (map, mode, bots, bot skill; class and floor via Settings).
## `over` (the Construction hub's Start: {mode, map, bots, difficulty}, its Settings keys already written) replaces the
## wizard's picks; the wizard's own Settings are then left alone.
func play_offline(over: Dictionary = {}) -> void:
	if session != null: session.leave("")
	if over.is_empty(): wizard.save()
	var world: Node = load(WORLD).instantiate()
	world.map_id = str(over.get("map", wizard.map_id))
	world.mode_id = str(over.get("mode", wizard.mode_id))
	world.bot_count = int(over.get("bots", wizard.bots))
	world.difficulty = str(over.get("difficulty", wizard.diff))
	world.build_mode = world.mode_id == "sandbox"     # Sandbox opens the arena in build mode (ui/build_hud.gd)
	if world.map_id == SiteMap.ID:    # the generated building site: the hub's seed, or a new random site every match (0)
		var s := int(Settings.get_value("site_seed", 0))
		SiteMap.set_seed(s if s > 0 else randi_range(1, 2147483646))
	get_tree().change_scene_to_node(world)

## The Construction hub's Arcade card: a new boss rush run (dlc/construction/arcade_manager.gd; locked players get nothing).
func play_arcade() -> void:
	var cls := str(Settings.get_value("class", "wobbler"))
	if not Content.classes.has(cls) or not SetupWizard.owns_class(cls): cls = "wobbler"
	var world: Node = ArcadeManager.launch(0, str(Settings.get_value("arcade_diff", "normal")), cls)
	if world == null: return
	if session != null: session.leave("")
	get_tree().change_scene_to_node(world)

## The online co-op entry: the Host sheet's "Room type: Arcade co-op" creates one of these through host_room(). The run
## owns the rules (HP, gravity, knockback, crates and the K.O. limit come from the stage table), so only the name, who
## can join, the kind and `Settings arcade_diff` / `arcade_ff` matter. Two seats; an empty one is the teammate bot, so the
## host may start with one player ("Start with bot", lobby) or wait for a friend. The run is the same as before: the
## `arcade` room opts and `start.arc` / `am` messages are unchanged (docs/PROTOCOL.md 6.4).
func coop_host_opts() -> Dictionary:
	var diff := ArcadeCoop.norm_diff(str(Settings.get_value("arcade_diff", "normal")))
	var nm := _online_name()
	var rn := str(_ui["rname"].text).strip_edges().substr(0, 24) if _ui.has("rname") else ""
	if rn == "": rn = tr("%s's co-op run") % nm
	return {"name": rn, "pub": bool(_host["pub"]), "max": ArcadeCoop.SEATS, "bots": 1, "mode": "construction",
		"map": ArcadeCoop.site_map(), "arcade": true, "arcade_diff": diff, "arcade_ff": bool(Settings.get_value("arcade_ff", false)),
		"diff": diff, "dyn": "off", "hp": 200, "grav": 1.0, "kb": 1.0, "crate": "normal", "inf": false, "lim": 0}

## The host's own player info for a co-op room (a class the player owns, else the default).
func coop_host_info() -> Dictionary:
	var nm := _online_name()
	var cls := str(Settings.get_value("class", "wobbler"))
	if not Content.classes.has(cls) or not SetupWizard.owns_class(cls): cls = "wobbler"
	return {"name": nm, "skin": Settings.get_value("skin", "none"), "hat": Settings.get_value("hat", "none"),
		"color": Settings.get_value("color", 0x39b5a8), "cls": cls}

## Create the room from the Host sheet: a normal Versus room, or (Room type: Arcade co-op) the two-seat Construction
## boss rush. Both share the same lobby, code sharing, room browser and HostSession.
func host_room() -> void:
	if session != null and session.is_active(): return
	var coop := str(_host["type"]) == "coop"
	if coop and not DlcUnlock.owned():
		_status(tr("Unlock Construction first: the Arcade co-op room is part of the Construction DLC."))
		return
	var url := str(Settings.get_value("server_url")).strip_edges()
	var nm := _online_name()
	Settings.set_value("name", nm)
	Settings.set_value("host_opts", _host.duplicate())
	var mode := HostSession.online_mode(str(_host["mode"]))
	show_host(false)
	session = HostSession.new()
	_bind_session()
	if coop:
		(session as HostSession).begin_host(url, coop_host_opts(), coop_host_info(), str(Settings.get_value("token", "")))
	else:
		(session as HostSession).begin_host(url, {"name": str(_ui["rname"].text), "pub": _host["pub"], "max": _host["max"], "bots": int(_host["bots"]),
			"mode": mode, "map": _host_map(mode), "dyn": str(_host["dyn"]), "diff": str(Settings.get_value("difficulty", "normal")),
			"lim": int(_host["lim"]), "hp": int(_host["hp"]), "grav": float(_host["grav"]), "kb": float(_host["kb"]), "crate": str(_host["crate"]),
			"inf": bool(_host["inf"])},
			{"name": nm, "skin": Settings.get_value("skin", "none"), "hat": Settings.get_value("hat", "none"),
			"color": Settings.get_value("color", 0x39b5a8), "cls": Settings.get_value("class", "wobbler")}, str(Settings.get_value("token", "")))
	_refresh_buttons()

# ---------------- hosting and the lobby ----------------

func _sheet_frame(sheet_name: String, title: String, min_w: float) -> VBoxContainer:
	var sh := Control.new()
	sh.name = sheet_name
	sh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sh.visible = false
	add_child(sh)
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.06, 0.08, 0.86)   # strong enough that the panel behind never reads through
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

## One labelled row of toggle pills (the setup wizard's style). Returns the row.
func _pill_row(box: Control, row_name: String, label: String, keys: Array, names: Array, prefix: String, on_pick: Callable, label_w := 110.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_child(row)
	var l := Label.new()
	l.name = "Label"
	l.text = label
	l.theme_type_variation = &"MutedLabel"
	l.add_theme_font_size_override("font_size", 18)
	l.custom_minimum_size = Vector2(label_w, 0)
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
		b.custom_minimum_size = Vector2(60, HOST_ROW_H)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(on_pick.bind(keys[i]))
		row.add_child(b)
		_host_bs[prefix + str(keys[i])] = b
	return row

## Host sheet rules (index keys: node names cannot hold "0.5").
const HOST_ROW_H := 60.0
const HOST_LIMS := [-1, 0, 5, 10, 20, 30]
const HOST_LIM_NAMES := ["Auto", "None", "5", "10", "20", "30"]
const HOST_TABS := ["Room", "Mode", "Rules"]

## "Host a room": three tabs so it fits a phone in landscape without scrolling. Room: name, who can join, seats,
## bots. Mode: game type (‹ ›), K.O. limit, arena floor. Rules: health, gravity + ammo, knockback, crates. The
## choices are remembered (Settings host_opts) and go out in the `start` rules (HostSession.set_rules).
func _build_host_sheet() -> void:
	var box := _sheet_frame("HostSheet", "Host a room", 640)
	host_sheet = get_node("HostSheet")
	box.add_theme_constant_override("separation", UiTheme.SP_3)
	var h: Variant = Settings.get_value("host_opts", {})
	if h is Dictionary:
		for k in _host.keys():
			if h.has(k): _host[k] = h[k]
	_host["max"] = clampi(int(_host["max"]), 2, 8); _host["bots"] = clampi(int(_host["bots"]), 0, 7)
	if not h is Dictionary or not (h as Dictionary).has("mode"): _host["mode"] = str(Settings.get_value("mode", "classic"))
	if not h is Dictionary or not (h as Dictionary).has("dyn"): _host["dyn"] = str(Settings.get_value("dyn", "off"))
	_host["mode"] = HostSession.online_mode(str(_host["mode"]))
	if not HOST_LIMS.has(int(_host["lim"])): _host["lim"] = -1
	if not HostSession.HPS.has(int(_host["hp"])): _host["hp"] = 200
	if not HostSession.GRAVS.has(float(_host["grav"])): _host["grav"] = 1.0
	if not HostSession.KBS.has(float(_host["kb"])): _host["kb"] = 1.0
	if not HostSession.CRATES.has(str(_host["crate"])): _host["crate"] = "normal"
	if not Dynamics.KINDS.has(str(_host["dyn"])): _host["dyn"] = "off"
	var head := HBoxContainer.new()               # the title and the tabs share one row (fits 375 pt tall phones)
	head.name = "Head"
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	var title: Label = box.get_node("Title")
	title.size_flags_vertical = SIZE_SHRINK_CENTER
	title.reparent(head)
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.size_flags_horizontal = SIZE_EXPAND_FILL
	tabs.add_theme_constant_override("separation", UiTheme.SP_3)
	head.add_child(tabs)
	var tg := ButtonGroup.new()
	for t: String in HOST_TABS:
		var b := Button.new()
		b.name = t; b.text = t
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true; b.button_group = tg
		b.custom_minimum_size = Vector2(0, HOST_ROW_H)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(show_host_tab.bind(t))
		tabs.add_child(b)
	for t: String in HOST_TABS:
		var pg := VBoxContainer.new()
		pg.name = t
		pg.add_theme_constant_override("separation", UiTheme.SP_3)
		box.add_child(pg)
	var room: VBoxContainer = box.get_node("Room")
	var name_row := HBoxContainer.new()               # the room name and the room type share one row (the sheet fits a phone)
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", UiTheme.SP_3)
	room.add_child(name_row)
	var nm := LineEdit.new()
	nm.name = "RoomName"
	nm.placeholder_text = "Room name"
	nm.max_length = 24
	nm.custom_minimum_size = Vector2(0, HOST_ROW_H)
	nm.size_flags_horizontal = SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", 18)
	name_row.add_child(nm)
	_ui["rname"] = nm
	var tll := Label.new()
	tll.name = "TypeLabel"
	tll.text = "Type"
	tll.theme_type_variation = &"MutedLabel"
	tll.add_theme_font_size_override("font_size", 18)
	tll.size_flags_vertical = SIZE_SHRINK_CENTER
	name_row.add_child(tll)
	var tgroup := ButtonGroup.new()                  # Versus / Arcade co-op: the kind of room (docs/PROTOCOL.md 1.1)
	for pair: Array in [["versus", "Versus"], ["coop", "Arcade co-op"]]:
		var b := Button.new()
		b.name = "P" + str(pair[0])
		b.text = str(pair[1])
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = tgroup
		b.custom_minimum_size = Vector2(92 if pair[0] == "versus" else 156, HOST_ROW_H)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(set_host_type.bind(str(pair[0])))
		name_row.add_child(b)
		_host_bs["type_" + str(pair[0])] = b
	_pill_row(room, "Vis", "Who can join", [0, 1], ["Private (code)", "Public"], "pub_", func(k: int) -> void: _host["pub"] = k == 1)
	_pill_row(room, "Max", "Seats", [2, 3, 4, 5, 6, 7, 8], ["2", "3", "4", "5", "6", "7", "8"], "max_", func(k: int) -> void: _host["max"] = k)
	_pill_row(room, "Bots", "Bots", [0, 1, 2, 3, 4, 5, 6, 7], ["0", "1", "2", "3", "4", "5", "6", "7"], "bots_", func(k: int) -> void: _host["bots"] = k)
	var mode: VBoxContainer = box.get_node("Mode")
	var mr := HBoxContainer.new()
	mr.name = "Game"
	mr.add_theme_constant_override("separation", UiTheme.SP_3)
	mode.add_child(mr)
	var ml := Label.new()
	ml.name = "Label"; ml.text = "Game"
	ml.theme_type_variation = &"MutedLabel"
	ml.add_theme_font_size_override("font_size", 18)
	ml.custom_minimum_size = Vector2(110, 0)
	ml.size_flags_vertical = SIZE_SHRINK_CENTER
	mr.add_child(ml)
	for side: Array in [["Prev", "‹", -1], ["Name", "", 0], ["Next", "›", 1]]:
		var b := Button.new()
		b.name = side[0]; b.text = side[1]
		b.custom_minimum_size = Vector2(64 if side[2] != 0 else 0, HOST_ROW_H)
		b.add_theme_font_size_override("font_size", 26 if side[2] != 0 else 19)
		if side[2] == 0:
			b.size_flags_horizontal = SIZE_EXPAND_FILL
			b.clip_text = true
			b.pressed.connect(step_host_mode.bind(1))
		else: b.pressed.connect(step_host_mode.bind(side[2]))
		mr.add_child(b)
	var mh := Label.new()
	mh.name = "ModeHint"
	mh.theme_type_variation = &"MutedLabel"
	mh.add_theme_font_size_override("font_size", 15)
	mh.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mh.custom_minimum_size = Vector2(0, 40)
	mode.add_child(mh)
	_pill_row(mode, "Lim", "K.O. limit", range(HOST_LIMS.size()), HOST_LIM_NAMES, "lim_", func(i: int) -> void: _host["lim"] = HOST_LIMS[i])
	var dk: Array = Dynamics.KINDS.duplicate()
	var dn: Array = []
	for k: String in dk: dn.append(Dynamics.NAMES[k])
	_pill_row(mode, "Floor", "Floor", dk, dn, "dyn_", func(k: String) -> void: _host["dyn"] = k)
	var rules: VBoxContainer = box.get_node("Rules")
	_pill_row(rules, "Hp", "Health", HostSession.HPS, HostSession.HPS, "hp_", func(k: int) -> void: _host["hp"] = k)
	var pair := HBoxContainer.new()
	pair.name = "Pair"
	pair.add_theme_constant_override("separation", UiTheme.SP_4)
	rules.add_child(pair)
	_pill_row(pair, "Grav", "Gravity", [0, 1, 2], ["Low", "Normal", "High"], "grav_", func(i: int) -> void: _host["grav"] = HostSession.GRAVS[i])
	_pill_row(pair, "Inf", "Ammo", [0, 1], ["Normal", "Infinite"], "inf_", func(i: int) -> void: _host["inf"] = i == 1, 64.0)
	_pill_row(rules, "Kb", "Knockback", range(HostSession.KBS.size()), ["0.5x", "1x", "1.5x", "2x", "3x"], "kb_", func(i: int) -> void: _host["kb"] = HostSession.KBS[i])
	_pill_row(rules, "Crate", "Crates", HostSession.CRATES, ["Few", "Normal", "Many", "Chaos"], "crate_", func(k: String) -> void: _host["crate"] = k)
	var hint := Label.new()
	hint.name = "Hint"
	hint.theme_type_variation = &"MutedLabel"
	hint.add_theme_font_size_override("font_size", 15)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 20)
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(row)
	var cancel := Button.new()
	cancel.name = "Cancel"; cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(140, HOST_ROW_H)
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.pressed.connect(show_host.bind(false))
	row.add_child(cancel)
	var go := Button.new()
	go.name = "Create"; go.text = "Create room"
	go.theme_type_variation = &"PrimaryButton"
	go.size_flags_horizontal = SIZE_EXPAND_FILL
	go.custom_minimum_size = Vector2(0, HOST_ROW_H)
	go.add_theme_font_size_override("font_size", 22)
	go.pressed.connect(func() -> void: host_room())
	row.add_child(go)
	_host_bs["pub_" + str(1 if _host["pub"] else 0)].button_pressed = true
	_host_bs["max_" + str(_host["max"])].button_pressed = true
	_host_bs["bots_" + str(_host["bots"])].button_pressed = true
	_host_bs["lim_" + str(HOST_LIMS.find(int(_host["lim"])))].button_pressed = true
	_host_bs["dyn_" + str(_host["dyn"])].button_pressed = true
	_host_bs["hp_" + str(int(_host["hp"]))].button_pressed = true
	_host_bs["grav_" + str(HostSession.GRAVS.find(float(_host["grav"])))].button_pressed = true
	_host_bs["inf_" + str(1 if _host["inf"] else 0)].button_pressed = true
	_host_bs["kb_" + str(HostSession.KBS.find(float(_host["kb"])))].button_pressed = true
	_host_bs["crate_" + str(_host["crate"])].button_pressed = true
	show_host_tab("Room")
	_show_host_mode()
	set_host_type(str(_host["type"]))

## One tab of the Host sheet.
func show_host_tab(t: String) -> void:
	if str(_host["type"]) == "coop" and t != "Room": t = "Room"
	_host_tab = t
	var box := host_sheet.get_node("Center/Card/Box")
	for n: String in HOST_TABS:
		(box.get_node(n) as Control).visible = n == t
		(box.get_node("Head/Tabs/" + n) as Button).set_pressed_no_signal(n == t)
	_host_hint()

## The Host sheet's room type: "versus" (a normal PvP room) or "coop" (the two-seat Arcade co-op room). An Arcade room
## has fixed seats (two, the empty one is the teammate bot) and no Host-sheet rules, so Seats/Bots and the Mode/Rules
## tabs are hidden/disabled; it can still be public or private like any room. Only DLC owners can open one.
func set_host_type(t: String) -> void:
	var coop := t == "coop" and DlcUnlock.owned()
	if t == "coop" and not coop:
		_status(tr("Unlock Construction first: the Arcade co-op room is part of the Construction DLC."))
	_host["type"] = "coop" if coop else "versus"
	if _host_bs.has("type_versus"):
		(_host_bs["type_versus"] as Button).set_pressed_no_signal(not coop)
		(_host_bs["type_coop"] as Button).set_pressed_no_signal(coop)
		(_host_bs["type_coop"] as Button).disabled = not DlcUnlock.owned()
	var box := host_sheet.get_node("Center/Card/Box")
	(box.get_node("Room/Max") as Control).visible = not coop
	(box.get_node("Room/Bots") as Control).visible = not coop
	for t2: String in ["Mode", "Rules"]:
		(box.get_node("Head/Tabs/" + t2) as Button).disabled = coop
	if coop and _host_tab != "Room":
		show_host_tab("Room")
	else:
		_host_hint()

## ‹ / ›: the previous / next online game type.
func step_host_mode(d: int) -> void:
	var ms := HostSession.online_modes()
	var i := ms.find(str(_host["mode"]))
	_host["mode"] = ms[posmod(i + d, ms.size())]
	_show_host_mode()

func set_host_mode(m: String) -> void:
	_host["mode"] = HostSession.online_mode(m)
	_show_host_mode()

func _show_host_mode() -> void:
	var box := host_sheet.get_node("Center/Card/Box/Mode")
	var m := str(_host["mode"])
	(box.get_node("Game/Name") as Button).text = tr(HostSession.mode_name(m)) + (tr("  (app)") if HostSession.app_only(m) else "")
	var blurb := tr(ModeRules.blurb(m, HostSession.all_modes()))
	var t := blurb + ("." if blurb != "" and not blurb.ends_with(".") and not blurb.ends_with("。") else "")
	t += (" " if t != "" else "") + (tr("App only: a web player in the room makes it Classic.") if HostSession.app_only(m) else tr("Web and app players."))
	(box.get_node("ModeHint") as Label).text = t
	_host_hint()

## Under the tabs: what the room plays. An Arcade co-op room says so (its rules come from the stage table and its
## difficulty/friendly fire from the Arcade screen's Settings); a Versus room names its arena (the last Play setup's).
func _host_hint() -> void:
	if host_sheet == null: return
	var hint: Label = host_sheet.get_node("Center/Card/Box/Hint")
	if str(_host["type"]) == "coop":
		hint.custom_minimum_size.y = 44.0                      # two wrapped lines at font 15
		hint.text = tr("Arcade co-op: two seats, a teammate bot fills the empty one, the stages set the rules. Difficulty: %s.") \
			% tr(_arcade_diff_name())
		return
	hint.custom_minimum_size.y = 20.0
	var mp := _host_map(str(_host["mode"]))
	hint.text = tr("Arena: %s (from your last Play setup).") % str(Content.get_map(mp).get("name", mp))

## The Arcade difficulty the co-op room will play (Settings arcade_diff, picked on the Arcade screen).
func _arcade_diff_name() -> String:
	return ConstructionHub.diff_name(ArcadeCoop.norm_diff(str(Settings.get_value("arcade_diff", "normal"))))


## The arena for game type `mode`: the last Play setup's if allowed online, else the mode's first one.
func _host_map(mode: String) -> String:
	var mp := str(Settings.get_value("offline_map", "arena"))
	var allowed: Array = SetupWizard.maps_for(mode).filter(func(id: String) -> bool: return GuestSession.data("maps").has(id))
	if not allowed.has(mp): mp = "arena" if allowed.has("arena") or allowed.is_empty() else str(allowed[0])
	return mp

func show_host(on: bool) -> void:
	host_sheet.visible = on
	if on:
		var coop_b: Button = _host_bs["type_coop"]
		coop_b.disabled = not DlcUnlock.owned()
		coop_b.tooltip_text = (tr("Two seats on the Construction boss rush: a friend takes the second one, or a bot does.")
			if DlcUnlock.owned() else tr("Unlock Construction first"))
		set_host_type(str(_host["type"]))
		if str(_ui["rname"].text) == "": _ui["rname"].text = tr("%s's room") % _online_name()
		show_host_tab("Room")
		if Tier.is_pc(): (_ui["rname"] as LineEdit).grab_focus.call_deferred()

func _on_hosted(_code: String) -> void:
	_fill_lobby()
	show_lobby(true)
	if session is HostSession and (session as HostSession).arcade:
		# the Arcade co-op room is hosted from the online Host sheet: say exactly how the run starts (the code is in the card)
		_status((tr("Your Arcade co-op room is open and in the room list. ") if (session as HostSession).pub
			else tr("Share the room code. ")) + tr("Start needs two players, or start with the teammate bot."))

## Host migration while on the title / lobby: the new HostSession replaces the guest one.
func _on_promoted(hs: GuestSession) -> void:
	_unbind_session()
	session = hs
	_bind_session()
	_status(hs.status)
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
	grid.add_theme_constant_override("h_separation", UiTheme.SP_4)
	grid.add_theme_constant_override("v_separation", UiTheme.SP_1)
	box.add_child(grid)
	var info := Label.new()
	info.name = "Info"
	info.theme_type_variation = &"MutedLabel"
	info.add_theme_font_size_override("font_size", 16)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0, 20)
	box.add_child(info)
	var rl := Label.new()
	rl.name = "Rules"
	rl.add_theme_font_size_override("font_size", 16)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.custom_minimum_size = Vector2(0, 20)
	box.add_child(rl)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(row)
	var lv := Button.new()
	lv.name = "Leave"; lv.text = "Leave"
	lv.custom_minimum_size = Vector2(140, 60)
	lv.add_theme_font_size_override("font_size", 20)
	lv.pressed.connect(func() -> void: if session: session.leave("You left the room."))
	row.add_child(lv)
	var sb := Button.new()
	sb.name = "StartBot"; sb.text = "Start with bot"     # Arcade co-op only: 1 human + the teammate bot (solo testing)
	sb.custom_minimum_size = Vector2(0, 60)
	sb.add_theme_font_size_override("font_size", 20)
	sb.pressed.connect(_lobby_start.bind(true))
	row.add_child(sb)
	var st := Button.new()
	st.name = "Start"; st.text = "Start"
	st.theme_type_variation = &"PrimaryButton"
	st.size_flags_horizontal = SIZE_EXPAND_FILL
	st.custom_minimum_size = Vector2(0, 60)
	st.add_theme_font_size_override("font_size", 22)
	st.pressed.connect(_lobby_start.bind(false))
	row.add_child(st)

## Start from the lobby (host only). `with_bot` = the co-op "Start with bot": one player and the teammate bot; a plain
## Start on an Arcade co-op room is refused until a second player is in (HostSession.can_start / start_match guard).
func _lobby_start(with_bot := false) -> void:
	if not (session is HostSession): return
	var hs := session as HostSession
	if hs.arcade and not with_bot and not hs.can_start():
		_status(tr("Start needs two players. Wait for a friend, or start with the teammate bot."))
		_fill_lobby()
		return
	hs.start_match(with_bot)

## The room is an Arcade co-op room (a Godot host says so; a guest reads the kind label the host puts in the roster).
func _is_coop_room() -> bool:
	if session == null: return false
	if session is HostSession: return (session as HostSession).arcade
	return str(session.lobby.get("modeName", "")) == HostSession.ARCADE_LABEL

func show_lobby(on: bool) -> void:
	if lobby: lobby.visible = on

## The lobby card from the session: room name / kind / code, a line per player (the host first), what the room plays,
## Leave and Start for the host. An Arcade co-op room also has "Start with bot" while the room has one player, and its
## Start stays disabled until a second player is in; a guest always waits for the host.
func _fill_lobby() -> void:
	var box := lobby.get_node("Center/Card/Box")
	var hs: HostSession = session as HostSession if session is HostSession else null
	var roster: Array = session.roster if session != null else []
	var coop := _is_coop_room()
	(box.get_node("Title") as Label).text = (session.room_name if session != null and session.room_name != "" else tr("Lobby")).substr(0, 24)
	var code: Label = box.get_node("Code")
	if session == null:
		code.text = ""
	elif hs != null:
		if hs.arcade:
			code.text = (tr("Arcade co-op · public room %s") % hs.room_code) if hs.pub else (tr("Arcade co-op · room code %s") % hs.room_code)
		else:
			code.text = (tr("Public room · %s") % hs.room_code) if hs.pub else (tr("Room code %s") % hs.room_code)
	elif coop:
		code.text = tr("Arcade co-op · room code %s") % session.room_code.to_upper()
	else:
		code.text = tr("Room code %s") % session.room_code.to_upper()
	var grid: GridContainer = box.get_node("Players")
	for c in grid.get_children(): c.queue_free()
	for r: Dictionary in roster:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 20)
		l.custom_minimum_size.x = 250
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.text = "%s%s%s" % [r.get("name", "?"), tr("  (host)") if int(r.get("id", -1)) == 0 else "", tr("  (web)") if hs != null and int(r.get("id", -1)) != 0 and not r.has("gd") else ""]
		grid.add_child(l)
	var seats := hs.opt_max if hs != null else int(session.lobby.get("max", 0)) if session != null else 0
	var info: Label = box.get_node("Info")
	if coop:
		if hs != null:
			info.text = (tr("%d / %d players · ready to start") % [roster.size(), seats]) if hs.can_start() \
				else tr("1 / 2 players · waiting for a friend (or start with the bot)")
		else:
			info.text = tr("%d / %d players · waiting for the host to start") % [roster.size(), seats]
	else:
		info.text = tr("%d / %d players") % [roster.size(), seats] + (tr(" · empty seats get bots") if (hs != null and hs.opt_bots) or (hs == null and session != null and session.lobby.get("bots", false)) else "") \
			+ ("" if hs != null else tr(" · waiting for the host to start"))
	var rl: Label = box.get_node("Rules")
	if coop:
		if hs != null:
			rl.text = tr("Arcade co-op · %s difficulty · the stages set the rules") % tr(_arcade_diff_name())
		else:
			rl.text = tr("Arcade co-op · the stages set the rules")
	elif hs != null:
		rl.text = HostSession.rules_text(hs.rules_list())
	elif session != null and session.lobby.get("rl") is Dictionary: rl.text = HostSession.rules_text(session.lobby["rl"])
	elif session != null and str(session.lobby.get("modeName", "")) != "": rl.text = "%s · %s" % [session.lobby["modeName"], session.lobby.get("map", "")]
	else: rl.text = ""
	rl.visible = rl.text != ""
	var start_b: Button = box.get_node("Buttons/Start")
	var bot_b: Button = box.get_node("Buttons/StartBot")
	start_b.visible = hs != null
	bot_b.visible = hs != null and hs.arcade and not hs.can_start()
	start_b.disabled = hs != null and hs.arcade and not hs.can_start()

# ---------------- Construction title (the DON'T ENTER wipe) ----------------

func toggle_dlc() -> void:
	set_dlc(not dlc)

## Switch between the normal and the Construction title. Animated: hazard tape sweeps across, the title changes under
## it, the tape clears and the logo and Play button drop in. Play on the Construction title opens the hub.
func set_dlc(on: bool, animated := true) -> void:
	if on == dlc or _wipe.busy: return
	if not animated:
		_apply_dlc(on)
		return
	_wipe.banner = tr("CONSTRUCTION SITE") if on else tr("BACK TO THE ARENA")
	_wipe.run(_apply_dlc.bind(on), _drop_in)

func _apply_dlc(on: bool) -> void:
	dlc = on
	$Background.mix = 1.0 if on else 0.0
	var logo: WobbleLogo = $Safe/Col/Top/Logo
	if on: logo.set_palette(Color(0.92, 0.9, 0.84), HazardTape.YELLOW, Color(0.1, 0.08, 0.06))
	else: logo.set_palette(WobbleLogo.WHITE, WobbleLogo.YELLOW, WobbleLogo.INK)
	showcase.site_exit = on                   # (the pill and the opened sign say EXIT SITE on the Construction title)
	if showcase.is_open(): showcase.snap(false)   # (the tape hides the container going back up)
	showcase.refresh()
	var tips: Array = DLC_TIPS if on else TIPS
	tip_text = tr(tips[randi() % tips.size()])
	_tip_room()
	if quick_b: quick_b.visible = not on      # the Construction title starts through its hub, not a quick random match
	apply_safe_area.call_deferred()

## Logo and Play button thump in after the tape clears.
func _drop_in() -> void:
	for n: Control in [$Safe/Col/Top/Logo, play]:
		n.pivot_offset = n.size / 2.0
		n.scale = Vector2.ONE * 1.18
		n.modulate.a = 0.0
		var tw := n.create_tween().set_parallel(true)
		tw.tween_property(n, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "modulate:a", 1.0, 0.2)
