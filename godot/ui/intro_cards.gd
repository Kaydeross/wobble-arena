class_name IntroCards
extends Control
## The first-run how-to: three cards (move and look, fire and melee, grab crates) on a dimmed backdrop, each with a
## small picture, a title and two lines. Skip closes at once, Next steps on, the last card's button says Let's play.
## Closing (either way) sets Settings `seen_intro`. The title shows it on first launch; Settings > Controls shows it
## again. The words follow the input: touch (TouchControls.wanted()) or keyboard / mouse.

signal closed

const CARDS := [
	["move", "Move and look", "Drag your left thumb to move. Drag on the right side of the screen to look around.",
		"WASD to move, the mouse to look. Click once to grab the mouse; Esc lets it go."],
	["fight", "Fire and melee", "Hold FIRE to shoot. Tap MELEE to shove, hold it to kick. JUMP hops over gaps.",
		"Click to shoot, right-click to aim. E shoves, F kicks, Space jumps."],
	["crate", "Grab the crates", "Crates drop weapons, heals and power-ups. Walk over one to pick it up, then tap a slot at the bottom to switch weapon.",
		"Crates drop weapons, heals and power-ups. Walk over one to pick it up; 1, 2 and 3 switch weapons."],
]

var page := 0
var card: PanelContainer
var pic: Control
var title_l: Label
var body_l: Label
var dots_l: Label
var skip_b: Button
var next_b: Button
var touch := true

func _init() -> void:
	name = "Intro"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

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
	card.custom_minimum_size = Vector2(640, 0)
	cc.add_child(card)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	pic = CardPicture.new()
	pic.name = "Picture"
	pic.custom_minimum_size = Vector2(0, 120)
	box.add_child(pic)
	title_l = Label.new()
	title_l.name = "Title"
	title_l.theme_type_variation = &"TitleLabel"
	title_l.add_theme_font_size_override("font_size", 32)
	title_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_l)
	body_l = Label.new()
	body_l.name = "Body"
	body_l.add_theme_font_size_override("font_size", 19)
	body_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_l.custom_minimum_size = Vector2(560, 0)
	box.add_child(body_l)
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	skip_b = Button.new()
	skip_b.name = "Skip"
	skip_b.text = "Skip"
	skip_b.custom_minimum_size = Vector2(140, 62)
	skip_b.add_theme_font_size_override("font_size", 20)
	skip_b.pressed.connect(finish)
	row.add_child(skip_b)
	dots_l = Label.new()
	dots_l.name = "Dots"
	dots_l.theme_type_variation = &"MutedLabel"
	dots_l.add_theme_font_size_override("font_size", 18)
	dots_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dots_l.size_flags_horizontal = SIZE_EXPAND_FILL
	dots_l.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(dots_l)
	next_b = Button.new()
	next_b.name = "Next"
	next_b.theme_type_variation = &"PrimaryButton"
	next_b.custom_minimum_size = Vector2(190, 62)
	next_b.add_theme_font_size_override("font_size", 24)
	next_b.pressed.connect(next)
	row.add_child(next_b)
	JuicyButton.attach_all(self)

func open() -> void:
	touch = TouchControls.wanted() or not Tier.is_pc()
	visible = true
	go(0)

func go(i: int) -> void:
	page = clampi(i, 0, CARDS.size() - 1)
	var c: Array = CARDS[page]
	(pic as CardPicture).kind = str(c[0])
	pic.queue_redraw()
	title_l.text = str(c[1])
	body_l.text = str(c[2] if touch else c[3])
	dots_l.text = "%d of %d" % [page + 1, CARDS.size()]
	next_b.text = "Let's play" if page == CARDS.size() - 1 else "Next"
	if Tier.is_pc(): next_b.grab_focus.call_deferred()

func next() -> void:
	if page >= CARDS.size() - 1: finish()
	else: go(page + 1)

## Skip or done: remembered, so it does not come back on its own.
func finish() -> void:
	Settings.set_value("seen_intro", true)
	if not visible: return
	visible = false
	closed.emit()

func back() -> bool:
	if page > 0: go(page - 1)
	else: finish()
	return true

## A small drawing per card: the move stick and a look arrow, the FIRE / MELEE buttons, a crate.
class CardPicture extends Control:
	var kind := "move"

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.y * 0.36, 48.0)
		match kind:
			"move":
				var a := c + Vector2(-r * 1.8, 0)
				draw_circle(a, r, Color(1, 1, 1, 0.14))
				draw_arc(a, r, 0, TAU, 40, Color(1, 1, 1, 0.6), 2.0, true)
				draw_circle(a + Vector2(r * 0.35, -r * 0.2), r * 0.45, Color(1, 1, 1, 0.7))
				var b := c + Vector2(r * 1.8, 0)
				for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
					draw_line(b + d * r * 0.3, b + d * r, Color(1, 1, 1, 0.7), 4.0, true)
					var n := Vector2(-d.y, d.x)
					draw_line(b + d * r, b + d * r * 0.7 + n * r * 0.22, Color(1, 1, 1, 0.7), 4.0, true)
					draw_line(b + d * r, b + d * r * 0.7 - n * r * 0.22, Color(1, 1, 1, 0.7), 4.0, true)
			"fight":
				draw_circle(c + Vector2(r * 1.3, r * 0.2), r * 1.05, Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.9))
				draw_circle(c + Vector2(-r * 0.5, -r * 0.35), r * 0.65, Color(0.94, 0.45, 0.35, 0.9))
				draw_circle(c + Vector2(-r * 1.8, r * 0.45), r * 0.72, Color(0.22, 0.71, 0.66, 0.9))
			"crate":
				var s := r * 1.5
				var rr := Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s))
				draw_rect(rr, Color(0.8, 0.55, 0.25), true)
				draw_rect(rr, Color(0.45, 0.28, 0.1), false, 4.0)
				draw_line(rr.position, rr.end, Color(0.45, 0.28, 0.1), 4.0, true)
				draw_line(Vector2(rr.position.x, rr.end.y), Vector2(rr.end.x, rr.position.y), Color(0.45, 0.28, 0.1), 4.0, true)
				draw_circle(c + Vector2(s, -s * 0.35), r * 0.22, UiTheme.ACCENT)
				draw_circle(c + Vector2(-s, -s * 0.2), r * 0.18, Color(0.3, 0.82, 0.54))
