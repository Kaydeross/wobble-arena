class_name DlcPill
extends Button
## The title's single DLC entry: a compact hazard-striped pill ("CONSTRUCTION" and a small NEW tag) that hangs from the
## container on the 3D stage (ui/title_showcase.gd). A plain Button, so mouse, touch, keyboard, gamepad and screen readers
## all work. Drawn: black plate, hazard-tape frame, yellow face, bold black label. `tag` is the small black chip after the
## label ("" hides it); `lead` is an optional first glyph (the "back" arrow of EXIT SITE).

@export var label := "CONSTRUCTION":
	set(v): label = v; _refit()
@export var tag := "NEW":
	set(v): tag = v; _refit()
@export var lead := "":
	set(v): lead = v; _refit()

## Label size in canvas px (the owner scales it with the touch-size factor).
var font_px := 21.0:
	set(v): font_px = v; _refit()
var min_h := 60.0:
	set(v): min_h = v; _refit()

const EDGE := 5.0
var _font: Font

func _init() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = _want()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	text = ""
	for s in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		add_theme_stylebox_override(s, StyleBoxEmpty.new())
	for s: Signal in [mouse_entered, mouse_exited, button_down, button_up, focus_entered, focus_exited]:
		s.connect(queue_redraw)

func _f() -> Font:
	if _font == null: _font = UiTheme.font(700)
	return _font

func _tag_fs() -> int:
	return maxi(UiTheme.MIN_FONT, int(round(font_px * 0.62)))

func _lead_w() -> float:
	return _f().get_string_size(lead + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_px)).x if lead != "" else 0.0

func _tag_w() -> float:
	return _f().get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, _tag_fs()).x + font_px * 0.7 if tag != "" else 0.0

## A Button's own minimum size ignores the script's _get_minimum_size, so the pill sets custom_minimum_size.
func _refit() -> void:
	custom_minimum_size = _want()
	queue_redraw()

func _want() -> Vector2:
	var tw := _f().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font_px)).x
	var gap := font_px * 0.45 if tag != "" else 0.0
	return Vector2(_lead_w() + tw + gap + _tag_w() + 2.0 * (EDGE + font_px * 0.75), maxf(min_h, font_px * 1.9 + EDGE * 2.0))

func _draw() -> void:
	var f := _f()
	var mode := get_draw_mode()
	var pressed := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
	var hovered := mode == DRAW_HOVER or mode == DRAW_HOVER_PRESSED
	var r := Rect2(Vector2(0, 2.0 if pressed else 0.0), size - Vector2(0, 4.0))
	draw_rect(Rect2(r.position + Vector2(0, 4.0), r.size).grow(-1.0), Color(0, 0, 0, 0.4))
	draw_rect(r.grow(-1.0), HazardTape.BLACK)
	HazardTape.stripes(self, r.grow(-2.0), 8.0, 0.0)
	var face := r.grow(-2.0 - EDGE)
	var yellow := HazardTape.YELLOW.lightened(0.12 if hovered else 0.0)
	var fsb := UiTheme.box(yellow, 8, HazardTape.BLACK, 2, 0)
	draw_style_box(fsb, face)
	var fs := int(font_px)
	var tw := f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var gap := font_px * 0.45 if tag != "" else 0.0
	var total := _lead_w() + tw + gap + _tag_w()
	var x := face.position.x + (face.size.x - total) * 0.5
	var base_y := face.position.y + (face.size.y + f.get_ascent(fs) - f.get_descent(fs)) * 0.5
	if lead != "":
		draw_string(f, Vector2(x, base_y), lead, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HazardTape.BLACK)
		x += _lead_w()
	draw_string(f, Vector2(x, base_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HazardTape.BLACK)
	x += tw + gap
	if tag != "":
		var tfs := _tag_fs()
		var th := f.get_height(tfs) + 6.0
		var chip := Rect2(x, face.position.y + (face.size.y - th) * 0.5, _tag_w(), th)
		draw_style_box(UiTheme.box(HazardTape.BLACK, 7, HazardTape.BLACK, 0, 0), chip)
		var ttw := f.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x
		draw_string(f, Vector2(chip.position.x + (chip.size.x - ttw) * 0.5, chip.position.y + (chip.size.y + f.get_ascent(tfs) - f.get_descent(tfs)) * 0.5), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, HazardTape.YELLOW)
	if has_focus():
		draw_style_box(_ring(), Rect2(Vector2.ZERO, size).grow(3.0))

var _ring_sb: StyleBoxFlat
func _ring() -> StyleBoxFlat:
	if _ring_sb == null:
		_ring_sb = UiTheme.box(Color.TRANSPARENT, 14, Color.WHITE, 3, 0)
		_ring_sb.draw_center = false
	return _ring_sb
