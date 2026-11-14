class_name SettingsScreen
extends UiPage
## The Settings screen (the title's gear, and Settings in the pause menu). A row of section tabs under the header, the
## section's rows under them in a phone-style list (DragScroll: drag to scroll, a tap on a row's words flips its switch):
##   Controls  touch buttons (auto / on / off), button size and opacity, left-handed, a move-the-buttons editor
##             (ui/touch_layout_editor.gd) with a reset, look speed for touch and for the mouse / controller, invert
##             up-down look, aim hold or toggle (mouse / controller), the controls picture (ui/controls_help.gd) and
##             the how-to cards again (ui/intro_cards.gd)
##   Camera    Manual / Auto-centre, distance, field of view
##   Graphics  effects Auto / Low / Medium / High (world/fx.gd), screen shake, show FPS, performance readout, leg wobble (docs/RAGDOLL.md), 15-minute soak test (world/soak_run.gd)
##   Audio     sound on / off, main volume, sound effects volume (the SFX bus, autoload Sfx)
##   Gameplay  the game's language (autoload Lang: the device's, or English, 繁體中文, 简体中文, 日本語, Français, Español), aim mode
##             Normal / Advanced (docs/AIM.md), knock-out replays (kill cam), damage numbers
##   Account   who you are, Open account (the title's Account sheet; in a match it says where to find it)
##   About     version and build, privacy policy, credits, the game server address (advanced) and, last and clearly
##             apart from the rest, the bright-red "Reset game…" row (ui/reset_dialog.gd, logic/reset_game.gd,
##             docs/RESET.md). It is not offered in a match: resetting drops the room / match, so it lives on the title's
##             Settings only.
## Every control writes its Settings key at once (Settings persists it and emits `changed`, the game applies it live)
## and follows `changed` from elsewhere (F3 toggles the FPS, for example).

signal account_requested
signal news_requested

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
var code_sheet: DlcCodeSheet      ## the Construction code field: tap the version line 7 times in About (not in a match)
var layout_editor: TouchLayoutEditor   ## Settings > Controls > Move buttons (ui/touch_layout_editor.gd)
var reset_dialog: ResetDialog     ## Settings > About > Reset game: the irreversible confirmation (ui/reset_dialog.gd)
var _ver_taps := 0
var _ver_t := 0

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
	tab_box.add_theme_constant_override("separation", UiTheme.SP_3)
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
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(show_section.bind(s))
		for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:      # slimmer side padding: seven tabs share one row, even in French / Japanese
			var sb := b.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			sb.content_margin_left = 8; sb.content_margin_right = 8
			b.add_theme_stylebox_override(state, sb)
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
	rows.add_theme_constant_override("separation", UiTheme.SP_3)
	scroll.add_child(rows)
	scroll.tapped.connect(_on_row_tapped)
	help = ControlsHelp.new()
	add_child(help)
	help.closed.connect(_focus_tab)
	intro = IntroCards.new()
	add_child(intro)
	intro.closed.connect(_focus_tab)
	code_sheet = DlcCodeSheet.new()
	add_child(code_sheet)
	code_sheet.closed.connect(_focus_tab)
	reset_dialog = ResetDialog.new()
	add_child(reset_dialog)
	reset_dialog.closed.connect(_focus_tab)
	reset_dialog.confirmed.connect(_on_reset_confirmed)
	layout_editor = TouchLayoutEditor.new()
	add_child(layout_editor)
	layout_editor.closed.connect(_on_layout_closed)
	Settings.changed.connect(_on_setting)
	super._ready()
	show_section(section)

func open() -> void:
	super.open()
	show_section(section)

func open_section(s: String) -> void:
	open()
	show_section(s)

## One step back: the reset prompt, the controls picture or the how-to first, then the screen.
func back() -> bool:
	if reset_dialog.visible: reset_dialog.close(); return true   # the prompt is on top and its safe answer is Cancel
	if layout_editor.visible: layout_editor.close(); return true
	if code_sheet.visible: return code_sheet.back()
	if intro.visible: intro.finish(); return true
	if help.visible: help.close(); return true
	close()
	return true

func close() -> void:
	if reset_dialog != null and reset_dialog.visible:
		reset_dialog.close()   # no hidden prompt left waiting behind the closed page
	if layout_editor != null and layout_editor.visible:
		layout_editor.close()   # never leave the editor's touch-layer mute behind a hidden page
	_show_page_body(true)
	super.close()

func _focus_tab() -> void:
	if Tier.is_pc() and visible: _grab_tab_focus.call_deferred()

## Deferred and guarded: after a confirmed reset the title scene is being replaced, so the page may have left the tree.
func _grab_tab_focus() -> void:
	if is_inside_tree() and visible and tabs.has(section): (tabs[section] as Button).grab_focus()

# ============================== sections ==============================

func show_section(s: String) -> void:
	if not tabs.has(s): return
	section = s
	for t: String in tabs: (tabs[t] as Button).set_pressed_no_signal(t == s)   # exactly one lit tab (a jump from the code left the old one gold)
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
			_buttons("TouchLayout", [["layout", "Move buttons", open_touch_layout], ["layout_reset", "Reset buttons", reset_touch_layout]])
			_toggle("kids_mode", "Kids mode", "Auto-aim and auto-fire, and you can't walk off the edge. Offline: half coins, no leaderboard.")
			_slider("sens", "Look speed (touch)", "", 0.3, 2.5, 0.05, _times)
			_slider("mouse_sens", "Look speed (mouse and controller)", "", 0.3, 2.5, 0.05, _times)
			_toggle("invert_y", "Invert up and down look", "")
			_choice("aim_button", "Aim button", "Mouse and controller. On touch, double-tap to aim.", ["hold", "toggle"], ["Hold", "Toggle"])
			_buttons("Help", [["help", "See the controls", open_help], ["intro", "Show the how-to again", open_intro]])
		"camera":
			_choice("cam_auto_center", "Camera", "Auto-centre swings the camera back behind you as you run", [false, true], ["Manual", "Auto-centre"])
			_slider("cam_dist", "Camera distance", "", 0.7, 1.5, 0.05, _pct)
			_slider("fov", "Field of view", "", 60.0, 90.0, 1.0, func(v: float) -> String: return "%d°" % int(v))
		"graphics":
			var auto_n: String = ["Low", "Medium", "High"][MapBuilder.gfx_q()]
			_choice("effects", "Effects", tr("Particles, trails and flashes in a match. Auto follows this device (%s).") % tr(auto_n),
				["auto", "low", "medium", "high"], ["Auto", "Low", "Medium", "High"])
			_choice("ui_scale", "Text and button size", "Menus, HUD and touch buttons. Auto keeps buttons finger-sized on this screen.",
				UiScale.MODES, ["Auto", "Small", "Normal", "Large"])
			_toggle("screen_shake", "Screen shake", "The camera shakes on big hits and explosions")
			_toggle("show_fps", "Show frame rate (FPS)", "F3 or a three-finger tap also toggles it")
			_toggle("perf_overlay", "Performance readout", "Top-left: fps, frame time, CPU / GPU, draws, thermal. For testing on a device.")
			_choice("fps_cap", "Frame rate cap", "A lower cap saves battery and heat on a phone. Max removes the cap.", [30, 60, 120, 0], ["30", "60", "120", "Max"])
			_slider("render_scale", "Render scale", "Renders the 3D scene at a lower resolution; buttons and text stay sharp.", 0.6, 1.0, 0.05, _pct)
			_slider("leg_wobble", "Leg wobble", "Extra random wobble in the legs. Cosmetic only.", 0.0, 1.0, 0.05, _pct)
			if not in_match:
				_info("soak", "15-minute soak test", "An offline Chaos 5v5 bot match logs the frame rate every second. Leave the phone alone: the screen stays on. At the end, tap Copy summary to share the result.")
				_buttons("Soak", [["soak", "Start soak test", func() -> void: SoakRun.launch(get_tree())]])
		"audio":
			_toggle("muted", "Sound", "", true)
			_slider("volume", "Main volume", "", 0.0, 1.0, 0.05, _pct)
			_slider("sfx_volume", "Sound effects", "", 0.0, 1.0, 0.05, _pct)
			_slider("music_volume", "Music", "", 0.0, 1.0, 0.05, _pct)
			_toggle("haptics", "Haptics (vibration)", "A short vibration on hits, K.O.s and explosions. Phones only.")
		"gameplay":
			_language()
			_choice("aim_mode", "Aim mode", "Normal: aim assist, standard damage. Advanced: no aim assist, +25% damage (offline).",
				["normal", "advanced"], ["Normal", "Advanced"])
			_toggle("kill_cam", "K.O. replays", "A short slow-motion replay after a quick K.O. (offline)")
			_toggle("damage_numbers", "Damage numbers", "Numbers pop up over the player you hit")
		"account":
			var u := _account_line()
			_info("Who", u[0], u[1])
			if in_match:
				_info("Where", "Account", "Open your account from the title screen (the chip at the top)")
			else:
				_buttons("Open", [["account", "Open account", func() -> void: account_requested.emit()]])
		"about":
			_info("Version", "Wobblers Arena", version_text())
			var vl := rows.get_node_or_null("Row_Version/Words/Sub") as Label
			if vl and not in_match:
				vl.mouse_filter = Control.MOUSE_FILTER_STOP
				vl.gui_input.connect(_on_version_input)
			var links: Array = [["privacy", "Privacy policy", func() -> void: OS.shell_open(PRIVACY_URL)]]
			if not in_match: links.insert(0, ["news", "What's new", func() -> void: news_requested.emit()])   # the patch notes (moved off the title)
			_buttons("Links", links)
			_info("Credits", "Credits", "Made by Kaydeross. Built with the Godot Engine (godotengine.org). Font: Fredoka (SIL Open Font License).")
			_field("server_url", "Game server (advanced)", "Only change this if a friend runs their own server")
			_server_extras()
			if not in_match: _reset_row()   # last row, clearly apart: the deliberate "start from scratch" switch
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
	return TranslationServer.translate("Version %s, build %s") % [version, build]

func _account_line() -> Array:
	var sv := get_node_or_null("/root/Save")
	var cloud: Variant = sv.get("cloud") if sv else null
	if cloud != null and cloud.signed_in():
		var sync: String = cloud.sync_text()
		return [tr("Signed in as %s") % str(cloud.user()), sync if sync != "" else "Your progress is saved to your account"]
	return ["Playing as a guest", "Your progress is saved on this device only. Create an account to keep it safe."]

func open_help() -> void:
	help.open()

func open_intro() -> void:
	intro.open()

## Settings > Controls > Move buttons: drag the real touch buttons anywhere inside the safe area (ui/touch_layout_editor.gd).
## The Settings page itself is hidden meanwhile, so the editor's dimmed overlay sits over the title / paused match and the
## player can judge the buttons against the screen they play on.
func open_touch_layout() -> void:
	if layout_editor == null:
		return
	_show_page_body(false)
	layout_editor.open()

## Settings > Controls > Reset buttons: back to the device's own default layout at once (phones and tablets differ).
func reset_touch_layout() -> void:
	Settings.set_value("touch_layout", "{}")

## The Settings page body (opaque backdrop + margins + rows) <-> the move-buttons editor over what is behind the page.
func _show_page_body(on: bool) -> void:
	var bg := get_node_or_null("Bg")
	if bg != null:
		(bg as CanvasItem).visible = on
	if safe != null:
		safe.visible = on

func _on_layout_closed() -> void:
	_show_page_body(true)
	_focus_tab()

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

## The language row: one drop-down, every language in its own name (never translated) so it can always be found.
func _language() -> void:
	var r := _row("Row_lang", "Language", "Auto follows this device")
	var ob := OptionButton.new()
	ob.name = "Field"
	ob.custom_minimum_size = Vector2(CTRL_W, TOUCH)
	ob.size_flags_vertical = SIZE_SHRINK_CENTER
	ob.add_theme_font_size_override("font_size", 19)
	ob.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # the names are already in their own language
	var pf := FontVariation.new()                                 # 繁體中文 / 简体中文 / 日本語 need CJK glyphs whatever the game's language is
	pf.base_font = UiTheme.font(700)
	pf.fallbacks = Lang.cjk_fonts()
	ob.add_theme_font_override("font", pf)
	ob.get_popup().add_theme_font_override("font", pf)
	var items: Array = [["auto", tr("Auto") + " (" + _lang_name(Lang.resolve("auto")) + ")"]]
	for l: Array in Lang.list(): items.append([l[0], l[1]])
	var cur := str(Settings.get_value("lang"))
	for i in items.size():
		ob.add_item(items[i][1], i)
		ob.set_item_metadata(i, items[i][0])
		if items[i][0] == cur: ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: Settings.set_value("lang", str(ob.get_item_metadata(i))))
	r.add_child(ob)
	ctl["lang"] = ob

static func _lang_name(c: String) -> String:
	for l: Array in Lang.list():
		if l[0] == c: return l[1]
	return "English"

## A row of pills (one pick). `off`: value -> true to disable that pill (not available on this device).
func _choice(key: String, title: String, sub: String, values: Array, names: Array, off: Dictionary = {}) -> void:
	var r := _row("Row_" + key, title, sub)
	var h := HBoxContainer.new()
	h.name = "Ctl"
	h.custom_minimum_size = Vector2(CTRL_W, 0)
	h.add_theme_constant_override("separation", UiTheme.SP_3)
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

## Settings > About > Reset game: the prompt (ui/reset_dialog.gd). Nothing is deleted until its red button, which lands
## in _on_reset_confirmed.
func open_reset_dialog() -> void:
	if reset_dialog != null: reset_dialog.open()

## The prompt said "Reset everything": sign out, wipe the profile and every preference, remove the known profile files
## and reload the title as a new install (logic/reset_game.gd).
func _on_reset_confirmed() -> void:
	ResetGame.wipe_all()

## The last row of About: a short red warning over one bright-red, full-width button, clearly apart from the normal
## settings rows (the prompt makes it a deliberate two-step action; it is not shown in a match).
func _reset_row() -> void:
	var gap := Control.new()
	gap.name = "ResetGap"
	gap.custom_minimum_size = Vector2(0, UiTheme.SP_5)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(gap)
	var cap := Label.new()
	cap.name = "ResetWarning"
	cap.text = "Deletes all progress and settings. Cannot be undone."
	cap.add_theme_color_override("font_color", UiTheme.BAD)
	cap.add_theme_font_size_override("font_size", 17)
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(cap)
	var r := HBoxContainer.new()
	r.name = "Row_reset_game"
	r.custom_minimum_size = Vector2(0, TOUCH)
	r.add_theme_constant_override("separation", UiTheme.SP_3)
	rows.add_child(r)
	var b := Button.new()
	b.name = "ResetGame"
	b.text = "Reset game…"                       # styled by ResetDialog.style_danger: bright red, white bold text
	b.custom_minimum_size = Vector2(0, TOUCH)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	b.pressed.connect(open_reset_dialog)
	ResetDialog.style_danger(b, 21)
	r.add_child(b)
	ui["reset_game"] = b

func _on_version_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: version_tap()

## One tap on the version line: seven taps in a row (each within 2.5 s of the last) open the Construction code field.
func version_tap() -> void:
	var now := Time.get_ticks_msec()
	if now - _ver_t > 2500: _ver_taps = 0
	_ver_t = now
	_ver_taps += 1
	if _ver_taps >= 7:
		_ver_taps = 0
		code_sheet.open()

## A tap on a row's words flips its switch (the switch itself takes taps too).
func _on_row_tapped(c: Control) -> void:
	if c.has_meta("toggle"):
		var cb: CheckButton = c.get_meta("toggle")
		if not cb.disabled: cb.button_pressed = not cb.button_pressed

## Keep the controls in step when a setting changes elsewhere.
func _on_setting(key: String, v: Variant) -> void:
	if key == "lang":
		if visible: show_section.call_deferred(section)   # sentences built in code (tr) are redone in the new language
		return
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
