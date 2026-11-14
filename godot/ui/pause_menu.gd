class_name PauseMenu
extends Control
## The in-match pause menu (world.tscn UI/Pause): Resume, Settings (ui/settings_screen.gd, without the Account
## sheet), Controls (ui/controls_help.gd: the touch layout and gestures), Report or block (online) and Quit to title, which asks first while a
## match is running ("Leave room" online: the world then leaves the room cleanly with session.leave).
## Back (Escape, controller B, Android back) closes the top page: Settings / Controls / the question -> the menu ->
## resume. The world connects `resume_requested` and `quit_requested`, sets `online` and `match_running`.

signal resume_requested
signal quit_requested

var online := false:                ## the label says Leave room and the question talks about the room
	set(v):
		online = v
		if quit_b: _texts()
var match_running: Callable = func() -> bool: return true   ## false once the match is over (no question then)
var players: Callable = func() -> Array: return []          ## online display names (world supplies the live roster)
var card: PanelContainer
var box: VBoxContainer
var resume_b: Button
var settings_b: Button
var help_b: Button
var report_b: Button
var quit_b: Button
var confirm: PanelContainer
var confirm_l: Label
var stay_b: Button
var go_b: Button
var settings: SettingsScreen
var help: ControlsHelp
var safety: SafetySheet

func _init() -> void:
	name = "Pause"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.06, 0.08, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	card = PanelContainer.new()
	card.name = "Panel"
	cc.add_child(card)
	box = VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", UiTheme.SP_3)
	card.add_child(box)
	var t := Label.new()
	t.name = "Label"
	t.text = "Paused"
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_color_override("font_color", UiTheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	resume_b = _btn("Resume", "Resume", true, func() -> void: resume_requested.emit())
	settings_b = _btn("Settings", "Settings", false, open_settings)
	help_b = _btn("Controls", "Controls", false, open_help)
	report_b = _btn("Safety", "Report or block", false, open_safety)
	quit_b = _btn("Title", "Quit to title", false, ask_quit)
	confirm = PanelContainer.new()
	confirm.name = "Confirm"
	confirm.visible = false
	cc.add_child(confirm)
	var cb := VBoxContainer.new()
	cb.name = "Box"
	cb.add_theme_constant_override("separation", 12)
	confirm.add_child(cb)
	confirm_l = Label.new()
	confirm_l.name = "Text"
	confirm_l.add_theme_font_size_override("font_size", 22)
	confirm_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	confirm_l.custom_minimum_size = Vector2(460, 0)
	cb.add_child(confirm_l)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", 12)
	cb.add_child(row)
	stay_b = Button.new()
	stay_b.name = "Stay"
	stay_b.custom_minimum_size = Vector2(200, 62)
	stay_b.size_flags_horizontal = SIZE_EXPAND_FILL
	stay_b.add_theme_font_size_override("font_size", 22)
	stay_b.pressed.connect(func() -> void: show_page("menu"))
	row.add_child(stay_b)
	go_b = Button.new()
	go_b.name = "Go"
	go_b.theme_type_variation = &"PrimaryButton"
	go_b.custom_minimum_size = Vector2(200, 62)
	go_b.size_flags_horizontal = SIZE_EXPAND_FILL
	go_b.add_theme_font_size_override("font_size", 24)
	go_b.pressed.connect(func() -> void: quit_requested.emit())
	row.add_child(go_b)
	settings = SettingsScreen.new()
	settings.in_match = true
	add_child(settings)
	settings.closed.connect(func() -> void: show_page("menu"))
	help = ControlsHelp.new()
	add_child(help)
	help.closed.connect(func() -> void: show_page("menu"))
	safety = SafetySheet.new()
	add_child(safety)
	safety.closed.connect(func() -> void: show_page("menu"))
	_texts()
	JuicyButton.attach_all(card)
	JuicyButton.attach_all(confirm)

func _btn(n: String, text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.name = n
	b.text = text
	b.custom_minimum_size = Vector2(320, 66 if primary else 62)
	b.add_theme_font_size_override("font_size", 28 if primary else 22)
	if primary: b.theme_type_variation = &"PrimaryButton"
	b.pressed.connect(cb)
	box.add_child(b)
	return b

func _texts() -> void:
	quit_b.text = tr("Leave room") if online else tr("Quit to title")
	report_b.visible = online
	confirm_l.text = tr("Leave the room? You'll leave this match and go back to the title.") if online \
		else tr("Quit this match? It won't count, and you'll go back to the title.")
	stay_b.text = tr("Keep playing")
	go_b.text = tr("Leave room") if online else tr("Quit match")

## Shown by the world when it pauses: always the menu first.
func open() -> void:
	visible = true
	show_page("menu")

## "menu" | "settings" | "help" | "confirm"
func show_page(p: String) -> void:
	card.visible = p == "menu"
	confirm.visible = p == "confirm"
	safety.visible = p == "safety"
	if p == "settings": settings.open()
	elif settings.visible: settings.visible = false
	if p == "help": help.open()
	elif help.visible: help.visible = false
	if p == "safety": safety.open(players.call())
	if Tier.is_pc() and visible:
		if p == "menu": resume_b.grab_focus.call_deferred()
		elif p == "confirm": stay_b.grab_focus.call_deferred()

func page() -> String:
	if settings.visible: return "settings"
	if help.visible: return "help"
	if safety.visible: return "safety"
	if confirm.visible: return "confirm"
	return "menu"

func open_settings() -> void: show_page("settings")
func open_help() -> void: show_page("help")
func open_safety() -> void: show_page("safety")

## Quit / Leave room: straight away when the match is already over, else ask first.
func ask_quit() -> void:
	if match_running.call(): show_page("confirm")
	else: quit_requested.emit()

## One step back: a page -> the menu, the menu -> resume.
func back() -> void:
	match page():
		"settings": settings.back()
		"help": help.back()
		"safety": safety.back()
		"confirm": show_page("menu")
		_: resume_requested.emit()

## Escape / Start is the world's pause key: on the menu it resumes (the world handles it), on a page it only goes
## back. Controller B / other ui_cancel keys go back everywhere. Android's back gesture too (or pauses the match).
func _input(e: InputEvent) -> void:
	if not visible: return
	if e.is_action_pressed("pause") and not e.is_echo():
		if page() != "menu":
			back()
			get_viewport().set_input_as_handled()
	elif e.is_action_pressed("ui_cancel") and not e.is_echo():
		back()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if visible: back()
		else: resume_requested.emit()   # the world's toggle: pauses the match
