class_name UiPage
extends Control
## A full-screen page over whatever is behind it (the title or a paused match): an opaque teal backdrop, a safe-area
## margin (SafeArea insets + MARGIN, updated when the window changes) and a column whose first row is the header:
## a Back button and the page title. Subclasses add their content to `col` and implement back().
## Used by ui/settings_screen.gd and ui/controls_help.gd.

signal closed

const MARGIN := Vector4(28, 16, 28, 12)   ## left, top, right, bottom padding inside the safe area
const BACK_SIZE := Vector2(124, 62)       ## 62 canvas px = 45 pt on an iPhone in landscape (Apple asks 44)

var safe: MarginContainer
var col: VBoxContainer
var head: HBoxContainer
var back_b: Button
var title_l: Label

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func build_frame(title: String) -> void:
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.color = Color(0.035, 0.11, 0.137, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	safe = MarginContainer.new()
	safe.name = "Safe"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(safe)
	col = VBoxContainer.new()
	col.name = "Col"
	col.add_theme_constant_override("separation", 10)
	safe.add_child(col)
	head = HBoxContainer.new()
	head.name = "Head"
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	back_b = Button.new()
	back_b.name = "Back"
	back_b.text = "Back"
	back_b.custom_minimum_size = BACK_SIZE
	back_b.add_theme_font_size_override("font_size", 22)
	back_b.pressed.connect(func() -> void: back())
	head.add_child(back_b)
	title_l = Label.new()
	title_l.name = "Title"
	title_l.text = title
	title_l.theme_type_variation = &"TitleLabel"
	title_l.add_theme_font_size_override("font_size", 34)
	title_l.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(title_l)

func _ready() -> void:
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()

func apply_safe_area() -> void:
	if safe == null or not is_inside_tree(): return
	var i := SafeArea.insets(get_viewport())
	safe.add_theme_constant_override("margin_left", int(MARGIN.x + i[0]))
	safe.add_theme_constant_override("margin_top", int(MARGIN.y + i[1]))
	safe.add_theme_constant_override("margin_right", int(MARGIN.z + i[2]))
	safe.add_theme_constant_override("margin_bottom", int(MARGIN.w + i[3]))

func open() -> void:
	apply_safe_area()
	visible = true
	if Tier.is_pc(): back_b.grab_focus.call_deferred()

## One step back (true = handled). The base page just closes.
func back() -> bool:
	close()
	return true

func close() -> void:
	if not visible: return
	visible = false
	closed.emit()
