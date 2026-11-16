class_name TutorialOffer
extends Control
## The one-time offer to learn the controls: "Learn the controls? Start / Skip", a small card over the title the first time a
## fresh, persistent profile presses Play or Quick play. Never forced: Skip carries on to the match the player asked for.
## Either answer is remembered (Settings `seen_tutorial`), so it comes once. Never shown when the profile is not saved
## (tests, --no-save) or the player has already played a match.
## Use TutorialOffer.maybe_show(host, next, start): true = the card is up and `next` / `start` will be called by its buttons.

signal answered(start: bool)

var card: PanelContainer
var title_l: Label
var body_l: Label
var start_b: Button
var skip_b: Button

static var test_persist := -1     ## tests: 1 / 0 pretend the profile is / is not saved (-1 = the real Settings.persist)

## Fresh install: saved profile, offer never answered, no match played yet.
static func wanted() -> bool:
	if not (Settings.persist if test_persist < 0 else test_persist == 1): return false
	if bool(Settings.get_value("seen_tutorial", false)): return false
	return int(Save.stats["matches"]) == 0 and Save.hist.is_empty()

static func maybe_show(host: Control, next: Callable, start: Callable) -> bool:
	if not wanted(): return false
	var o := TutorialOffer.new()
	host.add_child(o)
	o.answered.connect(func(go: bool) -> void:
		o.queue_free()
		if go: start.call()
		else: next.call())
	return true

func _init() -> void:
	name = "TutorialOffer"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(520, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", UiTheme.SP_3)
	card.add_child(box)
	title_l = Label.new()
	title_l.name = "Title"
	title_l.text = "Learn the controls?"
	title_l.theme_type_variation = &"TitleLabel"
	title_l.add_theme_color_override("font_color", UiTheme.ACCENT)
	title_l.add_theme_font_size_override("font_size", 34)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_l)
	body_l = Label.new()
	body_l.name = "Body"
	body_l.text = tr("A one-minute practice with your %s controls. Nothing is saved.") % ControlProfile.display_name(ControlProfile.current())
	body_l.add_theme_font_size_override("font_size", 19)
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_l.custom_minimum_size = Vector2(440, 0)
	box.add_child(body_l)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(row)
	skip_b = Button.new()
	skip_b.name = "Skip"
	skip_b.text = "Skip"
	skip_b.custom_minimum_size = Vector2(150, 62)
	skip_b.size_flags_horizontal = SIZE_EXPAND_FILL
	skip_b.add_theme_font_size_override("font_size", 22)
	skip_b.pressed.connect(func() -> void: answer(false))
	row.add_child(skip_b)
	start_b = Button.new()
	start_b.name = "Start"
	start_b.text = "Start"
	start_b.theme_type_variation = &"PrimaryButton"
	start_b.custom_minimum_size = Vector2(190, 62)
	start_b.size_flags_horizontal = SIZE_EXPAND_FILL
	start_b.add_theme_font_size_override("font_size", 24)
	start_b.pressed.connect(func() -> void: answer(true))
	row.add_child(start_b)
	JuicyButton.attach_all(self)
	if Tier.is_pc(): start_b.grab_focus.call_deferred()

func answer(start: bool) -> void:
	Settings.set_value("seen_tutorial", true)
	answered.emit(start)

## Escape / back: the same as Skip.
func _input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") and not e.is_echo():
		answer(false)
		get_viewport().set_input_as_handled()
