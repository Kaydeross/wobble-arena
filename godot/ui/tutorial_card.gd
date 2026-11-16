class_name TutorialCard
extends Control
## The training's overlay (world/tutorial.gd drives it): a small coach card at the top centre (the step's prompt with the
## real key / button highlighted, a row of progress dots, Skip and Exit), the "Nice!" cheer between steps, the finish card
## ("You're ready!": Play / Replay / Back) and, on touch, a pulse ring over the real on-screen control the step is about.
## Full-screen but only the card and the buttons take touches; it sits under the pause menu, over the HUD and touch layer.

signal skip_pressed
signal exit_pressed
signal play_pressed
signal replay_pressed
signal back_pressed

const TOUCH_H := 62.0            ## button height, canvas px (45 pt at the UI scale, like the other pages)
const HILITE := "[bgcolor=#ffcf5a][color=#10242b] %s [/color][/bgcolor]"

var card: PanelContainer
var prompt_l: RichTextLabel
var dots: Dots
var skip_b: Button
var exit_b: Button
var finish: PanelContainer
var finish_title: Label
var play_b: Button
var replay_b: Button
var back_b: Button
var pulse: Pulse
var _ins := [0.0, 0.0, 0.0, 0.0]

func _init() -> void:
	name = "TutorialCard"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	pulse = Pulse.new()
	pulse.name = "Pulse"
	add_child(pulse)
	card = PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = &"HudPanel"
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(card)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	card.add_child(row)
	var left := VBoxContainer.new()
	left.name = "Text"
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	left.size_flags_vertical = SIZE_SHRINK_CENTER
	left.add_theme_constant_override("separation", UiTheme.SP_2)
	row.add_child(left)
	prompt_l = RichTextLabel.new()
	prompt_l.name = "Prompt"
	prompt_l.bbcode_enabled = true
	prompt_l.fit_content = true
	prompt_l.scroll_active = false
	prompt_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_l.add_theme_font_size_override("normal_font_size", 22)
	prompt_l.add_theme_color_override("default_color", UiTheme.TEXT)
	prompt_l.size_flags_horizontal = SIZE_EXPAND_FILL
	prompt_l.custom_minimum_size = Vector2(300, 0)
	left.add_child(prompt_l)
	dots = Dots.new()
	dots.name = "Dots"
	dots.custom_minimum_size = Vector2(0, 14)
	left.add_child(dots)
	skip_b = _button("Skip", "Skip step", false, 120)
	skip_b.pressed.connect(func() -> void: skip_pressed.emit())
	row.add_child(skip_b)
	exit_b = _button("Exit", "Exit", false, 96)
	exit_b.pressed.connect(func() -> void: exit_pressed.emit())
	row.add_child(exit_b)
	_build_finish()
	get_viewport().size_changed.connect(layout)
	JuicyButton.attach_all(self)
	layout.call_deferred()

func _button(n: String, text: String, primary: bool, w: float) -> Button:
	var b := Button.new()
	b.name = n
	b.text = text
	b.theme_type_variation = &"PrimaryButton" if primary else &"Button"
	b.custom_minimum_size = Vector2(w, TOUCH_H)
	b.add_theme_font_size_override("font_size", 20)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	return b

func _build_finish() -> void:
	finish = PanelContainer.new()
	finish.name = "Finish"
	finish.visible = false
	finish.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(finish)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", UiTheme.SP_3)
	finish.add_child(box)
	finish_title = Label.new()
	finish_title.name = "Title"
	finish_title.text = "You're ready!"
	finish_title.theme_type_variation = &"TitleLabel"
	finish_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	finish_title.add_theme_font_size_override("font_size", 38)
	finish_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(finish_title)
	var sub := Label.new()
	sub.name = "Sub"
	sub.text = "Nothing in training was saved. Time to bonk some wobblers."
	sub.theme_type_variation = &"MutedLabel"
	sub.add_theme_font_size_override("font_size", 18)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.custom_minimum_size = Vector2(440, 0)
	box.add_child(sub)
	var br := HBoxContainer.new()
	br.name = "Buttons"
	br.add_theme_constant_override("separation", UiTheme.SP_3)
	box.add_child(br)
	play_b = _button("Play", "Play", true, 150)
	play_b.size_flags_horizontal = SIZE_EXPAND_FILL
	play_b.pressed.connect(func() -> void: play_pressed.emit())
	br.add_child(play_b)
	replay_b = _button("Replay", "Replay", false, 150)
	replay_b.size_flags_horizontal = SIZE_EXPAND_FILL
	replay_b.pressed.connect(func() -> void: replay_pressed.emit())
	br.add_child(replay_b)
	back_b = _button("Back", "Back", false, 150)
	back_b.size_flags_horizontal = SIZE_EXPAND_FILL
	back_b.pressed.connect(func() -> void: back_pressed.emit())
	br.add_child(back_b)

## Top centre, inside the safe area; the finish card in the middle.
func layout() -> void:
	if card == null or not is_inside_tree(): return
	_ins = SafeArea.insets(get_viewport())
	var vs := get_viewport_rect().size
	var w := clampf(vs.x - 2.0 * (150.0 + maxf(float(_ins[0]), float(_ins[2]))), 420.0, minf(760.0, vs.x - 16.0))
	card.custom_minimum_size = Vector2(w, 0)
	card.size = Vector2(w, 0)
	card.reset_size()
	card.position = Vector2((vs.x - card.size.x) * 0.5, 8.0 + float(_ins[1]))
	finish.reset_size()
	finish.position = ((vs - finish.size) * 0.5).floor()

func _process(_dt: float) -> void:
	if card != null and card.visible and absf(card.position.x - (get_viewport_rect().size.x - card.size.x) * 0.5) > 1.0:
		layout()

## Show step `i` of `n`: the sentence with the key names highlighted (`keys` fill the %s holes in order).
func set_prompt(text: String, keys: Array, i: int, n: int) -> void:
	var hi: Array = []
	for k in keys: hi.append(HILITE % str(k).replace("[", "[lb]"))
	prompt_l.text = (text % hi) if not hi.is_empty() else text
	dots.set_state(i, n)
	finish.visible = false
	card.visible = true
	layout.call_deferred()

## The green "Nice!" that replaces the prompt for a moment.
func set_cheer(text: String, i: int, n: int) -> void:
	prompt_l.text = "[color=#4bd18a]✓  %s[/color]" % text
	dots.set_state(i + 1, n)
	layout.call_deferred()

func show_finish() -> void:
	card.visible = false
	finish.visible = true
	pulse.target = {}
	layout.call_deferred()
	if Tier.is_pc(): play_b.grab_focus.call_deferred()

func hide_finish() -> void:
	finish.visible = false
	card.visible = true

## The progress dots: done = green, current = yellow and bigger, to come = dim.
class Dots extends Control:
	var cur := 0
	var total := 1
	func set_state(i: int, n: int) -> void:
		cur = i
		total = n
		custom_minimum_size = Vector2(n * 20.0, 14)
		queue_redraw()
	func _draw() -> void:
		for k in total:
			var c := Vector2(8.0 + k * 20.0, size.y * 0.5)
			if k < cur:
				draw_circle(c, 6.0, UiTheme.GOOD)
			elif k == cur:
				draw_circle(c, 7.0, UiTheme.ACCENT)
				draw_arc(c, 9.0, 0.0, TAU, 20, Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.45), 2.0, true)
			else:
				draw_circle(c, 5.0, Color(1, 1, 1, 0.28))

## The pulse ring over a real touch control: target = {"c": Vector2, "r": float} (a circle) or {"rect": Rect2}.
class Pulse extends Control:
	var target := {}:
		set(v):
			target = v
			set_process(not v.is_empty())
			queue_redraw()
	var _t := 0.0
	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)
	func _process(dt: float) -> void:
		_t += dt
		queue_redraw()
	func _draw() -> void:
		if target.is_empty(): return
		var k := 0.5 + 0.5 * sin(_t * 5.0)
		var col := Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.55 + 0.45 * k)
		if target.has("rect"):
			var r: Rect2 = (target["rect"] as Rect2).grow(5.0 + 6.0 * k)
			draw_style_box(UiTheme.box(Color(1, 0.81, 0.35, 0.10 + 0.10 * k), 14, col, 4, 0), r)
		else:
			var c: Vector2 = target["c"]
			var r: float = float(target["r"]) + 6.0 + 10.0 * k
			draw_circle(c, r, Color(1, 0.81, 0.35, 0.08 + 0.08 * k))
			draw_arc(c, r, 0.0, TAU, 48, col, 5.0, true)
