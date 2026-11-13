class_name DlcTransition
extends Control
## Full-screen "hazard tape" wipe used to switch the title between the normal and the Construction DLC look.
## Bands of striped tape slide in from alternating sides until the screen is covered, a banner pops up, the caller
## swaps the title (`mid`) while it is hidden, then the tape slides off the other way. Blocks input while it runs.

const BANDS := 7
const STAGGER := 0.08

var banner := "CONSTRUCTION SITE"
var busy := false
var p := 0.0:
	set(v): p = v; queue_redraw()
var _t := 0.0
var _font: Font

func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	z_index = 100

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

## cover (0.55 s) -> `mid` -> hold (0.45 s) -> uncover (0.55 s) -> `done`.
func run(mid: Callable, done: Callable = Callable()) -> void:
	if busy: return
	busy = true
	visible = true
	p = 0.0
	if _font == null: _font = UiTheme.font(700)
	var tw := create_tween()
	tw.tween_property(self, "p", 1.0, 0.55)
	tw.tween_callback(func() -> void: if mid.is_valid(): mid.call())
	tw.tween_interval(0.45)
	tw.tween_property(self, "p", 2.0, 0.55)
	tw.tween_callback(func() -> void:
		visible = false
		busy = false
		if done.is_valid(): done.call())

func _band_rect(i: int) -> Rect2:
	var h := size.y / BANDS
	var k := 1.0 / (1.0 - (BANDS - 1) * STAGGER)
	var x0 := 0.0   # covered span, in "enter from the left" coordinates
	var x1 := 0.0
	if p <= 1.0:
		x1 = size.x * ease(clampf((p - i * STAGGER) * k, 0.0, 1.0), -2.0)
	else:
		x0 = size.x * ease(clampf((p - 1.0 - i * STAGGER) * k, 0.0, 1.0), -2.0)
		x1 = size.x
	if i % 2 == 1:   # odd bands come from the right
		var a := size.x - x1
		var b := size.x - x0
		x0 = a; x1 = b
	return Rect2(x0, i * h, x1 - x0, h + 1.0)

func _draw() -> void:
	for i in BANDS:
		var r := _band_rect(i)
		if r.size.x < 1.0: continue
		var dir := 1.0 if i % 2 == 0 else -1.0
		Hazard.stripes(self, r, 26.0, _t * 70.0 * dir + i * 13.0, Hazard.YELLOW if i % 2 == 0 else Hazard.BLACK, Hazard.BLACK if i % 2 == 0 else Hazard.YELLOW)
		draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), Hazard.BLACK)
	# banner while fully covered
	var a := clampf(1.0 - absf(p - 1.0) / 0.18, 0.0, 1.0)
	if a <= 0.0 or _font == null: return
	var pop := 0.82 + 0.18 * ease(a, 0.4)
	var w := minf(size.x * 0.86, 920.0) * pop
	var h := 118.0 * pop
	var box := Rect2((size.x - w) / 2.0, (size.y - h) / 2.0, w, h)
	draw_rect(box.grow(8.0), Hazard.YELLOW)
	draw_rect(box, Hazard.BLACK)
	var fs := int(clampf(w / (banner.length() * 0.62), 24.0, 66.0) * pop)
	var tw := _font.get_string_size(banner, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := Vector2(box.position.x + (w - tw) / 2.0, box.position.y + (h + _font.get_ascent(fs) - _font.get_descent(fs)) / 2.0)
	draw_string(_font, base, banner, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Hazard.YELLOW.lerp(Color.WHITE, 0.0))
