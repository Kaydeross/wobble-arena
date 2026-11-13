class_name SettingsScreen
extends UiPage
## The Settings screen (the title's gear, and Settings in the pause menu). A row of section tabs under the header, the
## section's rows under them in a phone-style list (DragScroll: drag to scroll, a tap on a row's words flips its switch):
##   Controls  touch buttons (auto / on / off), button size and opacity, left-handed, look speed for touch and for the
##             mouse / controller, invert up-down look, aim hold or toggle (mouse / controller), the controls picture
##             (ui/controls_help.gd) and the how-to cards again (ui/intro_cards.gd)
##   Camera    Manual / Auto-centre, distance, field of view
##   Graphics  effects Auto / Low / Medium / High (world/fx.gd), screen shake, show FPS
##   Audio     sound on / off, main volume, sound effects volume (the SFX bus, autoload Sfx)
##   Gameplay  knock-out replays (kill cam), damage numbers
##   Account   who you are, Open account (the title's Account sheet; in a match it says where to find it)
##   About     version and build, privacy policy, credits, the game server address (advanced)
## Every control writes its Settings key at once (Settings persists it and emits `changed`, the game applies it live)
## and follows `changed` from elsewhere (F3 toggles the FPS, for example).

signal account_requested

const SECTIONS := ["controls", "camera", "graphics", "audio", "gameplay", "account", "about"]
const NAMES := {"controls": "Controls", "camera": "Camera", "graphics": "Graphics", "audio": "Audio", "gameplay": "Gameplay",
	"account": "Account", "about": "About"}
const PRIVACY_URL := "https://kaydeross.github.io/wobble-arena/privacy.html"
const TOUCH := 62.0                ## canvas px: 45 pt on an iPhone in landscape (Apple asks 44)
const ROW_H := 66.0
const CTRL_W := 330.0

var in_match := false             ## opened from the pause menu: no Account sheet here
var section := "controls"
var tabs := {}                    ## section -> tab Button
var tab_box: HBoxContainer
var scroll: DragScroll
var rows: VBoxContainer
var ctl := {}                     ## Settings key -> its control (CheckButton / HSlider / {value: Button} for choices)
var ui := {}                      ## other named controls of the current section ("help", "intro", "account", ...)
var help: ControlsHelp
var intro: IntroCards

func _init() -> void:
	super._init()
	name = "Settings"

func _ready() -> void:
	build_frame("Settings")
	var tscroll := ScrollContainer.new()         # one row of section tabs; scrolls sideways only if a window is very narrow
	tscroll.name = "TabScroll"
	tscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tscroll.follow_focus = true
	col.add_child(tscroll)
	tab_box = HBoxContainer.new()
	tab_box.name = "Tabs"
	tab_box.size_flags_horizontal = SIZE_EXPAND_FILL
	tab_box.add_theme_constant_override("separation", 6)
	tscroll.add_child(tab_box)
	var g := ButtonGroup.new()
	for s: String in SECTIONS:
		var b := Button.new()
		b.name = "Tab_" + s
		b.text = NAMES[s]
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(0, TOUCH)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 19)
		b.pressed.connect(show_section.bind(s))
		tab_box.add_child(b)
		tabs[s] = b
	var page := PanelContainer.new()
	page.name = "Page"
	page.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(page)
	scroll = DragScroll.new()
	scroll.name = "Scroll"
	page.add_child(scroll)
	rows = VBoxContainer.new()
	rows.name = "Rows"
	rows.size_flags_horizontal = SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	scroll.add_child(rows)
	scroll.tapped.connect(_on_row_tapped)
	help = ControlsHelp.new()
	add_child(help)
	help.closed.connect(_focus_tab)
	intro = IntroCards.new()
	add_child(intro)
	intro.closed.connect(_focus_tab)
	Settings.changed.connect(_on_setting)
	super._ready()
	show_section(section)

func open() -> void:
	super.open()
	show_section(section)

func open_section(s: String) -> void:
	open()
	show_section(s)

## One step back: the controls picture or the how-to first, then the screen.
func back() -> bool:
	if intro.visible: intro.finish(); return true
	if help.visible: help.close(); return true
	close()
	return true

func _focus_tab() -> void:
	if Tier.is_pc() and visible: (tabs[section] as Button).grab_focus.call_deferred()

# ============================== sections ==============================

func show_section(s: String) -> void:
	if not tabs.has(s): return
	section = s
	(tabs[s] as Button).set_pressed_no_signal(true)
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	ctl.clear(); ui.clear()
	match s:
		"controls":
			_choice("touch_mode", "Touch buttons", "Auto shows them on phones and tablets", ["auto", "on", "off"], ["Auto", "On", "Off"])
			_slider("touch_scale", "Button size", "", 0.7, 1.4, 0.05, _pct)
			_slider("touch_opacity", "Button opacity", "", 0.3, 1.0, 0.05, _pct)
			_toggle("touch_lefty", "Left-handed", "Buttons on the left, move on the right")
			_slider("sens", "Look speed (touch)", "", 0.3, 2.5, 0.05, _times)
			_slider("mouse_sens", "Look speed (mouse and controller)", "", 0.3, 2.5, 0.05, _times)
			_toggle("invert_y", "Invert up and down look", "")
			_choice("aim_mode", "Aim button", "Mouse and controller. On touch, double-tap to aim.", ["hold", "toggle"], ["Hold", "Toggle"])
			_buttons("Help", [["help", "See the controls", open_help], ["intro", "Show the how-to again", open_intro]])
		"camera":
			_choice("cam_auto_center", "Camera", "Auto-centre swings the camera back behind you as you run", [false, true], ["Manual", "Auto-centre"])
			_slider("cam_dist", "Camera distance", "", 0.7, 1.5, 0.05, _pct)
			_slider("fov", "Field of view", "", 60.0, 90.0, 1.0, func(v: float) -> String: return "%d°" % int(v))
		"graphics":
			var auto_n: String = ["Low", "Medium", "High"][MapBuilder.gfx_q()]
			_choice("effects", "Effects", "Particles, trails and flashes in a match. Auto follows this device (%s)." % auto_n,
				["auto", "low", "medium", "high"], ["Auto", "Low", "Medium", "High"])
			_choice("ui_scale", "Text and button size", "Menus, HUD and touch buttons. Auto keeps buttons finger-sized on this screen.",
				UiScale.MODES, ["Auto", "Small", "Normal", "Large"])
			_toggle("screen_shake", "Screen shake", "The camera shakes on big hits and explosions")
			_toggle("show_fps", "Show frame rate (FPS)", "F3 or a three-finger tap also toggles it")
		"audio":
			_toggle("muted", "Sound", "", true)
			_slider("volume", "Main volume", "", 0.0, 1.0, 0.05, _pct)
			_slider("sfx_volume", "Sound effects", "", 0.0, 1.0, 0.05, _pct)
			_slider("music_volume", "Music", "", 0.0, 1.0, 0.05, _pct)
		"gameplay":
			_toggle("kill_cam", "Knock-out replays", "A short slow-motion replay after a quick knock-out (offline)")
			_toggle("damage_numbers", "Damage numbers", "Numbers pop up over the player you hit")
		"account":
			var u := _account_line()
			_info("Who", u[0], u[1])
			if in_match:
				_info("Where", "Account", "Open your account from the title screen (the chip at the top).")
			else:
				_buttons("Open", [["account", "Open account", func() -> void: account_requested.emit()]])
		"about":
			_info("Version", "Wobblers Arena", version_text())
			_buttons("Links", [["privacy", "Privacy policy", func() -> void: OS.shell_open(PRIVACY_URL)]])
			_info("Credits", "Credits", "Made by Kaydeross. Built with the Godot Engine (godotengine.org). Font: Fredoka (SIL Open Font License).")
			_field("server_url", "Game server (advanced)", "Only change this if a friend runs their own server")
			_server_extras()
	JuicyButton.attach_all(rows)
	scroll.scroll_vertical = 0
	_focus_tab()

static func version_text() -> String:
	var version := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	var build := "dev"
	var cfg := ConfigFile.new()
	if cfg.load("res://build_info.cfg") == OK:
		version = str(cfg.get_value("build", "version", version))
		build = str(cfg.get_value("build", "number", build))
	return "Version %s, build %s" % [version, build]

func _account_line() -> Array:
	var sv := get_node_or_null("/root/Save")
	var cloud: Variant = sv.get("cloud") if sv else null
	if cloud != null and cloud.signed_in():
		var sync: String = cloud.sync_text()
		return ["Signed in as " + str(cloud.user()), sync if sync != "" else "Your progress is saved to your account."]
	return ["Playing as a guest", "Your progress is saved on this device only. Make an account to keep it safe."]

func open_help() -> void:
	help.open()

func open_intro() -> void:
	intro.open()

# ============================== rows ==============================

func _pct(v: float) -> String: return "%d%%" % roundi(v * 100.0)
func _times(v: float) -> String: return "%.2f×" % v

## A row: the words on the left (title + optional sub line), a control on the right.
func _row(n: String, title: String, sub: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.name = n
	r.custom_minimum_size = Vector2(0, ROW_H)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_constant_override("separation", 14)
	rows.add_child(r)
	var v := VBoxContainer.new()
	v.name = "Words"
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_theme_constant_override("separation", 0)
	r.add_child(v)
	var t := Label.new()
	t.name = "Label"
	t.text = title
	t.add_theme_font_size_override("font_size", 21)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(160, 0)
	v.add_child(t)
	if sub != "":
		var s := Label.new()
		s.name = "Sub"
		s.text = sub
		s.theme_type_variation = &"MutedLabel"
		s.add_theme_font_size_override("font_size", 15)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.custom_minimum_size = Vector2(160, 0)
		v.add_child(s)
	return r

## On / off. `invert`: the switch shows the opposite of the stored bool (Sound on = not muted).
func _toggle(key: String, title: String, sub: String, invert := false) -> void:
	var r := _row("Row_" + key, title, sub)
	var cb := CheckButton.new()
	cb.name = "Switch"
	cb.custom_minimum_size = Vector2(96, TOUCH)
	cb.size_flags_vertical = SIZE_SHRINK_CENTER
	cb.set_meta("invert", invert)
	cb.button_pressed = bool(Settings.get_value(key)) != invert
	cb.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on != invert))
	r.add_child(cb)
	r.set_meta("toggle", cb)
	ctl[key] = cb

func _slider(key: String, title: String, sub: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var r := _row("Row_" + key, title, sub)
	var h := HBoxContainer.new()
	h.name = "Ctl"
	h.custom_minimum_size = Vector2(CTRL_W, 0)
	h.add_theme_constant_override("separation", 10)
	r.add_child(h)
	var s := HSlider.new()
	s.name = "Slider"
	s.min_value = lo; s.max_value = hi; s.step = step
	s.custom_minimum_size = Vector2(0, TOUCH)
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.value = float(Settings.get_value(key))
	h.add_child(s)
	var l := Label.new()
	l.name = "Value"
	l.custom_minimum_size = Vector2(76, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.add_theme_font_size_override("font_size", 19)
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	l.text = fmt.call(s.value)
	h.add_child(l)
	s.value_changed.connect(func(v: float) -> void:
		l.text = fmt.call(v)
		Settings.set_value(key, v))
	s.set_meta("value_label", l)
	s.set_meta("fmt", fmt)
	ctl[key] = s

## A row of pills (one pick). `off`: value -> true to disable that pill (not available on this device).
func _choice(key: String, title: String, sub: String, values: Array, names: Array, off: Dictionary = {}) -> void:
	var r := _row("Row_" + key, title, sub)
	var h := HBoxContainer.new()
	h.name = "Ctl"
	h.custom_minimum_size = Vector2(CTRL_W, 0)
	h.add_theme_constant_override("separation", 6)
	r.add_child(h)
	var g := ButtonGroup.new()
	var by := {}
	var cur: Variant = Settings.get_value(key)
	for i in values.size():
		var b := Button.new()
		b.name = "P_" + str(values[i])
		b.text = str(names[i])
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.button_group = g
		b.custom_minimum_size = Vector2(0, TOUCH)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 18)
		b.disabled = bool(off.get(values[i], false))
		if b.disabled: b.tooltip_text = "Not available on this device"
		b.button_pressed = cur == values[i]
		var val: Variant = values[i]
		b.pressed.connect(func() -> void: Settings.set_value(key, val))
		h.add_child(b)
		by[val] = b
	ctl[key] = by

func _buttons(n: String, items: Array) -> void:
	var r := HBoxContainer.new()
	r.name = "Row_" + n
	r.custom_minimum_size = Vector2(0, ROW_H)
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	r.add_theme_constant_override("separation", 12)
	rows.add_child(r)
	for it: Array in items:
		var b := Button.new()
		b.name = str(it[0]).capitalize().replace(" ", "")
		b.text = str(it[1])
		b.custom_minimum_size = Vector2(0, TOUCH)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.size_flags_vertical = SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(it[2])
		r.add_child(b)
		ui[str(it[0])] = b

func _info(n: String, title: String, text: String) -> void:
	_row("Row_" + n, title, text)

func _field(key: String, title: String, sub: String) -> void:
	var r := _row("Row_" + key, title, sub)
	var e := LineEdit.new()
	e.name = "Field"
	e.custom_minimum_size = Vector2(CTRL_W, TOUCH)
	e.size_flags_vertical = SIZE_SHRINK_CENTER
	e.add_theme_font_size_override("font_size", 17)
	e.text = str(Settings.get_value(key))
	e.placeholder_text = Settings.server_default() if key == "server_url" else "ws://server:3000/ws"
	e.text_submitted.connect(func(t: String) -> void: Settings.set_value(key, t.strip_edges()))
	e.focus_exited.connect(func() -> void: if e.text.strip_edges() != "": Settings.set_value(key, e.text.strip_edges()))
	r.add_child(e)
	ctl[key] = e

## Under the server field: which server is active, and a button back to the app's own server.
func _server_extras() -> void:
	var lab := Label.new()
	lab.name = "ServerActive"
	lab.theme_type_variation = &"MutedLabel"
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_font_size_override("font_size", 16)
	lab.text = Settings.server_status_text()
	rows.add_child(lab)
	ui["server_active"] = lab
	_buttons("server_reset", [["server_reset", "Reset to default", func() -> void: Settings.reset("server_url")]])

## A tap on a row's words flips its switch (the switch itself takes taps too).
func _on_row_tapped(c: Control) -> void:
	if c.has_meta("toggle"):
		var cb: CheckButton = c.get_meta("toggle")
		if not cb.disabled: cb.button_pressed = not cb.button_pressed

## Keep the controls in step when a setting changes elsewhere.
func _on_setting(key: String, v: Variant) -> void:
	if key == "server_url" and is_instance_valid(ui.get("server_active")): (ui["server_active"] as Label).text = Settings.server_status_text()
	if not ctl.has(key): return
	var c: Variant = ctl[key]
	if c is CheckButton:
		var want := bool(v) != bool((c as CheckButton).get_meta("invert", false))
		if (c as CheckButton).button_pressed != want: (c as CheckButton).set_pressed_no_signal(want)
	elif c is HSlider:
		var s := c as HSlider
		if not is_equal_approx(s.value, float(v)):
			s.set_value_no_signal(float(v))
			(s.get_meta("value_label") as Label).text = (s.get_meta("fmt") as Callable).call(s.value)
	elif c is Dictionary:
		for val: Variant in c:
			(c[val] as Button).set_pressed_no_signal(val == v)
	elif c is LineEdit and not (c as LineEdit).has_focus():
		(c as LineEdit).text = str(v)
