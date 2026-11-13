class_name DlcCodeSheet
extends Control
## "Enter code": a small sheet with one text field, over the Construction hub or Settings > About. Checks the code with
## DlcUnlock.redeem and says "Unlocked everything" or "Wrong code". The text is cleared after every try and never logged.

signal redeemed        ## the code was right (everything is unlocked)
signal closed

var card: PanelContainer
var field: LineEdit
var msg: Label
var submit_b: Button
var close_b: Button

func _init() -> void:
	name = "CodeSheet"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.06, 0.08, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var cc := CenterContainer.new()
	cc.name = "Center"
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	card = PanelContainer.new()
	card.name = "Card"
	card.custom_minimum_size = Vector2(480, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", UiTheme.SP_3)
	card.add_child(box)
	var t := Label.new()
	t.name = "Title"
	t.text = "Enter code"
	t.theme_type_variation = &"TitleLabel"
	t.add_theme_font_size_override("font_size", 30)
	box.add_child(t)
	field = LineEdit.new()
	field.name = "Field"
	field.placeholder_text = "Code"
	field.custom_minimum_size = Vector2(0, 62)
	field.add_theme_font_size_override("font_size", 22)
	field.max_length = 64
	field.set_meta("user_text", true)
	field.text_submitted.connect(func(_t: String) -> void: submit())
	box.add_child(field)
	msg = Label.new()
	msg.name = "Msg"
	msg.theme_type_variation = &"MutedLabel"
	msg.add_theme_font_size_override("font_size", 18)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(0, 26)
	box.add_child(msg)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(row)
	close_b = Button.new()
	close_b.name = "Close"
	close_b.text = "Close"
	close_b.custom_minimum_size = Vector2(0, 62)
	close_b.size_flags_horizontal = SIZE_EXPAND_FILL
	close_b.add_theme_font_size_override("font_size", 22)
	close_b.pressed.connect(close)
	row.add_child(close_b)
	submit_b = Button.new()
	submit_b.name = "Submit"
	submit_b.text = "Submit"
	submit_b.theme_type_variation = &"PrimaryButton"
	submit_b.custom_minimum_size = Vector2(0, 62)
	submit_b.size_flags_horizontal = SIZE_EXPAND_FILL
	submit_b.add_theme_font_size_override("font_size", 22)
	submit_b.pressed.connect(submit)
	row.add_child(submit_b)
	JuicyButton.attach_all(row)

func open() -> void:
	field.text = ""
	msg.text = ""
	submit_b.disabled = DlcUnlock.owned() and Save.codes.has("dev")
	visible = true
	if Tier.is_pc(): field.grab_focus.call_deferred()

func close() -> void:
	if not visible: return
	field.text = ""
	field.release_focus()
	visible = false
	closed.emit()

func back() -> bool:
	close()
	return true

## Tries the typed code. true = right (the sheet stays open with the good news).
func submit() -> bool:
	var code := field.text
	field.text = ""
	if code.strip_edges() == "":
		return false
	if DlcUnlock.cooldown_left() > 0.0:
		_say("Wait a moment", UiTheme.WARN)
		return false
	if DlcUnlock.redeem(code):
		_say("Unlocked everything", UiTheme.GOOD)
		submit_b.disabled = true
		Sfx.play("pickup")
		redeemed.emit()
		return true
	_say("Wrong code", UiTheme.BAD)
	return false

func _say(t: String, c: Color) -> void:
	msg.text = tr(t)
	msg.add_theme_color_override("font_color", c)
