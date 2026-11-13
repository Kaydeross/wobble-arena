class_name WobbleLogo
extends Control
## The game logo like the web title: heavy rounded capitals, letters alternating white / warm yellow, a dark outline,
## a drop shadow and a slight per-letter tilt (optionally bobbing). Used by the title screen and to render the
## launch-screen PNG (tests/brand_shots.gd).

@export var lines: PackedStringArray = PackedStringArray(["WOBBLERS ARENA"])
@export var font_size := 64:
	set(v): font_size = v; update_minimum_size(); queue_redraw()
@export var animate := false
@export var outline := 0.16        ## outline width as a fraction of the font size

const WHITE := Color(1, 1, 1)
const YELLOW := Color(1.0, 0.812, 0.353)
const INK := Color(0.0627, 0.1686, 0.2078)

var col_a := WHITE      ## even letters
var col_b := YELLOW     ## odd letters
var ink := INK          ## outline

var _t := 0.0
var _font: Font

## Recolour the letters (the Construction DLC title uses hazard yellow / concrete on near-black).
func set_palette(a: Color, b: Color, outline_col: Color) -> void:
	col_a = a; col_b = b; ink = outline_col
	queue_redraw()

func _ready() -> void:
	_font = UiTheme.font(700)
	update_minimum_size()
	set_process(animate)

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _line_h() -> float:
	return font_size * 1.08

func _get_minimum_size() -> Vector2:
	if _font == null: _font = UiTheme.font(700)
	var w := 0.0
	for l in lines:
		w = maxf(w, _line_w(l))
	return Vector2(w + font_size * outline * 2.0, _line_h() * lines.size() + font_size * 0.18)

func _line_w(l: String) -> float:
	var w := 0.0
	for ch in l:
		w += _adv(ch)
	return w

func _adv(ch: String) -> float:
	if ch == " ": return font_size * 0.32
	return _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x - font_size * 0.02

func _draw() -> void:
	if _font == null: return
	var ow := int(font_size * outline)
	var asc := _font.get_ascent(font_size)
	var idx := 0
	for li in lines.size():
		var l: String = lines[li]
		var x := (size.x - _line_w(l)) / 2.0
		var base_y := (size.y - _line_h() * lines.size()) / 2.0 + li * _line_h() + asc * 0.92 + font_size * 0.04
		for ch in l:
			var a := _adv(ch)
			if ch != " ":
				var rot := deg_to_rad(3.5 if idx % 2 == 0 else -3.0)
				var bob := 0.0
				if animate:
					bob = sin(_t * 2.6 + idx * 0.7) * font_size * 0.03
					rot += sin(_t * 2.0 + idx * 1.3) * 0.025
				var c := Vector2(x + a / 2.0, base_y - asc * 0.35 + bob)
				draw_set_transform(c, rot, Vector2.ONE)
				var o := Vector2(-a / 2.0, asc * 0.35)
				var fill := col_a if idx % 2 == 0 else col_b
				draw_string_outline(_font, o + Vector2(0, font_size * 0.09), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ow, Color(0, 0, 0, 0.35))
				draw_string_outline(_font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, ow, ink)
				draw_string(_font, o, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fill)
				idx += 1
			x += a
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
