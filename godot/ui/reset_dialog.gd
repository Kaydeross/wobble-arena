class_name ResetDialog
extends Control
## "Reset everything?" — the irreversible-confirmation prompt for Settings > About > Reset game (logic/reset_game.gd).
## A dimmed backdrop and one card, the same shape as ui/dlc_code_sheet.gd / the pause menu's quit question:
##   body       exactly what is deleted (progress, records, DLC, settings, the sign-in on this device)
##   warning    "This can't be undone on this device." in bright red
##   note       the honest cloud-save caveat (a cloud save is not deleted by this device)
##   Cancel     the default focus and the safe answer: nothing is deleted until the red button is pressed
##   Reset everything   bright red with white bold text, the only control that calls ResetGame
## Esc / controller B / the Android back gesture and a tap on the dark backdrop all cancel (ui/settings_screen.gd
## routes back(), like the other sheets).
##   docs/RESET.md

signal confirmed        ## the player pressed the red button: the caller wipes (never before)
signal closed

const CARD_W := 560.0
const BTN_H := 62.0     ## canvas px: 45 pt on an iPhone in landscape (Apple asks 44)

var card: PanelContainer
var title_l: Label
var body_l: Label
var warning_l: Label
var note_l: Label
var cancel_b: Button
var reset_b: Button

func _init() -> void:
	name = "ResetDialog"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.06, 0.08, 0.9)   # strong enough that nothing behind reads through an irreversible prompt
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if (e is InputEventMouseButton or e is InputEventScreenTouch) and e.pressed: close())   # tapping outside = cancel
	add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(CARD_W, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", UiTheme.SP_3)
	card.add_child(box)
	title_l = _label("Reset everything?", 30, "TitleLabel", UiTheme.TEXT)
	title_l.name = "Title"
	box.add_child(title_l)
	body_l = _label("Deletes all progress: coins, outfits, hats, emotes, classes, stats, records and goals, plus your "
		+ "Construction and Arcade unlocks. Also your settings, touch layout, Kids mode and the sign-in on this device.",
		19, "", UiTheme.TEXT)
	body_l.name = "Body"
	box.add_child(body_l)
	warning_l = _label("This can't be undone on this device.", 21, "", UiTheme.BAD)
	warning_l.name = "Warning"
	warning_l.add_theme_font_override("font", UiTheme.font(700))
	box.add_child(warning_l)
	note_l = _label("A cloud save on your account isn't deleted: signing in again can bring it back.", 16, "MutedLabel", UiTheme.MUTED)
	note_l.name = "Note"
	box.add_child(note_l)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(row)
	cancel_b = Button.new()
	cancel_b.name = "Cancel"
	cancel_b.text = "Cancel"
	cancel_b.custom_minimum_size = Vector2(0, BTN_H)
	cancel_b.size_flags_horizontal = SIZE_EXPAND_FILL
	cancel_b.add_theme_font_size_override("font_size", 22)
	cancel_b.pressed.connect(close)
	row.add_child(cancel_b)
	reset_b = Button.new()
	reset_b.name = "Reset"
	reset_b.text = "Reset everything"
	reset_b.custom_minimum_size = Vector2(0, BTN_H)
	reset_b.size_flags_horizontal = SIZE_EXPAND_FILL
	reset_b.pressed.connect(_on_reset)
	style_danger(reset_b, 22)
	row.add_child(reset_b)
	JuicyButton.attach_all(row)

## Open the prompt. Nothing has been deleted: the caller connects `confirmed` to the wipe. Wiping is the red button.
func open() -> void:
	visible = true
	_focus_cancel.call_deferred()   # safe answer focused: Enter / A cancels, never resets

## Deferred (so the prompt is laid out first) and guarded: a prompt closed before the frame ends (a reset from a
## scene that is already being replaced) must not grab focus on a control that has left the tree.
func _focus_cancel() -> void:
	if visible and is_inside_tree(): cancel_b.grab_focus()

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()

func back() -> bool:
	close()
	return true

## Esc / controller B: cancel (the page's back() also reaches here when it is on top).
func _unhandled_input(e: InputEvent) -> void:
	if not visible: return
	if e.is_action_pressed("ui_cancel") and not e.is_echo():
		close()
		get_viewport().set_input_as_handled()

func _on_reset() -> void:
	if not visible: return
	visible = false          # nothing else can be pressed while the caller wipes
	confirmed.emit()
	closed.emit()

func _label(text: String, font_size: int, variation: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "": l.theme_type_variation = StringName(variation)
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", font_size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(CARD_W - 2.0 * 18.0 - 2.0 * UiTheme.BORDER, 0)   # card content width; wraps inside it
	return l

## The bright-red danger look (the theme has no danger variation; it is built here from the shared palette):
## red fill with a darker red lip, white bold text, a white focus ring for keyboard / controller.
static func style_danger(b: Button, font_size := 22) -> void:
	var red := UiTheme.BAD
	var edge := red.darkened(0.35)
	b.add_theme_stylebox_override("normal", UiTheme.box(red, UiTheme.RADIUS, edge, UiTheme.BORDER, 6, 6))
	b.add_theme_stylebox_override("hover", UiTheme.box(red.lightened(0.12), UiTheme.RADIUS, edge.lightened(0.2), UiTheme.BORDER, 8, 6))
	var pressed := UiTheme.box(red.darkened(0.12), UiTheme.RADIUS, edge, UiTheme.BORDER, 2, 2)
	pressed.content_margin_top += 4
	pressed.shadow_offset = Vector2(0, 1)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", pressed)
	b.add_theme_stylebox_override("disabled", UiTheme.box(Color(red.r, red.g, red.b, 0.5), UiTheme.RADIUS, Color(1, 1, 1, 0.1), UiTheme.BORDER, 0, 4))
	b.add_theme_stylebox_override("focus", UiTheme.box(Color.TRANSPARENT, UiTheme.RADIUS + 3, Color.WHITE, 3, 0))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, Color.WHITE)
	b.add_theme_font_override("font", UiTheme.font(700))
	b.add_theme_font_size_override("font_size", font_size)
