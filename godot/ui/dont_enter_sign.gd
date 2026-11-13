class_name DontEnterSign
extends Button
## The yellow / black construction-site warning sign that opens (and, once inside, leaves) the Construction DLC
## title. A plain Button, so mouse, touch, keyboard and gamepad all work. Drawn: hazard-tape border, bold black
## label, a slowly scrolling stripe and a pulsing amber warning glow.

@export var label := "DON'T ENTER":
	set(v): label = v; queue_redraw()

const EDGE := 5.0
var _t := 0.0
var _font: Font

func _init() -> void:
	custom_minimum_size = Vector2(200, 46)
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())

func _ready() -> void:
	_font = UiTheme.font(700)
	tooltip_text = label.capitalize()

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _draw() -> void:
	if _font == null: _font = UiTheme.font(700)
	var r := Rect2(Vector2.ZERO, size)
	# pulsing amber glow behind the sign
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	draw_rect(r.grow(3.0 + pulse * 3.0), Color(1.0, 0.7, 0.1, 0.12 + 0.16 * pulse), false, 4.0)
	# black plate, hazard-tape frame, yellow face
	draw_rect(r, Hazard.BLACK)
	Hazard.stripes(self, r.grow(-2.0), 8.0, _t * 14.0)
	var face := r.grow(-2.0 - EDGE)
	draw_rect(face, Hazard.BLACK)
	draw_rect(face.grow(-2.0), Hazard.YELLOW)
	var fs := 21
	var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var asc := _font.get_ascent(fs)
	var base := Vector2((size.x - tw) / 2.0, (size.y + asc - _font.get_descent(fs)) / 2.0)
	draw_string(_font, base, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Hazard.BLACK)
	if has_focus():
		draw_rect(r.grow(2.0), Color.WHITE, false, 3.0)
