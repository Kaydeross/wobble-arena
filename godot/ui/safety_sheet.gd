class_name SafetySheet
extends Control
## Online match safety card: choose another player, report them with a reason, or block their display name locally.

signal closed

var card: PanelContainer
var players: OptionButton
var reasons: OptionButton
var details: LineEdit
var status: Label
var report_b: Button
var block_b: Button
var _names: Array = []

func _init() -> void:
	name = "Safety"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.06, 0.08, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	card = PanelContainer.new()
	card.custom_minimum_size = Vector2(minf(560.0, get_viewport_rect().size.x - 48.0), 0)
	center.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	var title := Label.new()
	title.text = "Report or block"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	box.add_child(title)
	players = OptionButton.new()
	players.custom_minimum_size = Vector2(0, 56)
	players.add_theme_font_size_override("font_size", 20)
	box.add_child(players)
	reasons = OptionButton.new()
	reasons.custom_minimum_size = Vector2(0, 56)
	reasons.add_theme_font_size_override("font_size", 19)
	for item: Array in [["harassment", "Harassment"], ["name", "Offensive name"], ["cheating", "Cheating"], ["spam", "Spam"], ["other", "Other"]]:
		reasons.add_item(tr(item[1]))
		reasons.set_item_metadata(reasons.item_count - 1, item[0])
	box.add_child(reasons)
	details = LineEdit.new()
	details.custom_minimum_size = Vector2(0, 56)
	details.placeholder_text = "What happened? (optional)"
	details.max_length = 240
	box.add_child(details)
	status = Label.new()
	status.theme_type_variation = &"MutedLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	report_b = _button("Report", true, _send)
	row.add_child(report_b)
	block_b = _button("Block", false, _block)
	row.add_child(block_b)
	var close_b := _button("Close", false, close)
	row.add_child(close_b)
	JuicyButton.attach_all(card)
	visible = false

func _button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	if primary: b.theme_type_variation = &"PrimaryButton"
	b.pressed.connect(cb)
	return b

func open(names: Array) -> void:
	_names = []
	players.clear()
	for raw in names:
		var original := Safety.clean_name(str(raw))
		var n := Safety.display_name(original)
		if original == "" or original == "You" or n in ["Player", "Blocked Player"] or _names.has(original): continue
		_names.append(original)
		players.add_item(n)
		players.set_item_metadata(players.item_count - 1, original)
	var can := not _names.is_empty()
	players.disabled = not can
	report_b.disabled = not can
	block_b.disabled = not can
	status.text = "Choose another player." if can else "No other players in this room."
	details.text = ""
	visible = true
	card.pivot_offset = card.size / 2.0
	card.scale = Vector2(0.92, 0.92)
	card.modulate.a = 0.0
	var tw := card.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.24)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 0.14)
	if Tier.is_pc() and can: players.grab_focus.call_deferred()

func _selected() -> String:
	return str(players.get_item_metadata(players.selected)) if players.selected >= 0 and players.selected < players.item_count else ""

func _send() -> void:
	var target := _selected()
	if target == "": return
	report_b.disabled = true
	status.text = "Sending…"
	Safety.report(target, "", str(reasons.get_item_metadata(reasons.selected)), details.text,
		func(ok: bool, msg: String) -> void:
			report_b.disabled = false
			status.text = msg)

func _block() -> void:
	var target := _selected()
	if target == "" or not Safety.block(target):
		status.text = "That player is already blocked."
		return
	status.text = tr("%s is blocked on this device.") % target
	report_b.disabled = true
	block_b.disabled = true

func close() -> void:
	visible = false
	closed.emit()

func back() -> bool:
	if not visible: return false
	close()
	return true
