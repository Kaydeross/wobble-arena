extends Control
## HUD health bar (bottom left): class name, "hp / max" against the class's max HP, a fill that eases to the new
## value, a pale damage trail that waits a moment then drains after it, and a red pulse below 30 %.

const W := 300.0
const H := 62.0
const TRAIL_WAIT := 0.45
const TRAIL_SPEED := 0.55      ## fraction of the bar per second

var hp := 1.0                  ## 0..1 target
var hp_text := ""
var cls_text := ""
var _shown := 1.0              ## eased fill
var _trail := 1.0
var _trail_wait := 0.0
var _pulse := 0.0
var _font: Font
var _font_b: Font

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, H)
	size = custom_minimum_size
	_font = get_theme_default_font()
	_font_b = UiTheme.font(700)

func set_value(k: float, txt: String, cls: String) -> void:
	k = clampf(k, 0.0, 1.0)
	if k < hp - 0.001:
		_trail_wait = TRAIL_WAIT            # took damage: the trail holds, then drains
		_trail = maxf(_trail, _shown)
	hp = k
	hp_text = txt
	cls_text = cls

func tick(dt: float) -> void:
	_shown = lerpf(_shown, hp, 1.0 - exp(-dt * 14.0))
	if hp > _trail: _trail = hp
	elif _trail_wait > 0.0: _trail_wait -= dt
	else: _trail = maxf(hp, _trail - TRAIL_SPEED * dt)
	_pulse = _pulse + dt * 6.0 if hp < 0.3 and hp > 0.0 else 0.0
	queue_redraw()

static func hp_color(k: float) -> Color:
	if k > 0.5: return UiTheme.GOOD
	if k > 0.25: return UiTheme.WARN
	return UiTheme.BAD

func _draw() -> void:
	var low := hp < 0.3 and hp > 0.0
	var pl := 0.5 + 0.5 * sin(_pulse) if low else 0.0
	var panel := UiTheme.box(Color(UiTheme.PANEL.r, UiTheme.PANEL.g, UiTheme.PANEL.b, 0.78), 14,
		Color(1, 1, 1, 0.14).lerp(Color(1, 0.3, 0.28, 0.95), pl), 2, 5)
	if low:
		panel.shadow_color = Color(1, 0.2, 0.2, 0.25 + 0.35 * pl)
		panel.shadow_size = int(6 + 8 * pl)
		panel.shadow_offset = Vector2.ZERO
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	# class name + numbers
	draw_string_outline(_font_b, Vector2(14, 24), cls_text, HORIZONTAL_ALIGNMENT_LEFT, W * 0.55, 17, 4, Color(0, 0, 0, 0.25))
	draw_string(_font_b, Vector2(14, 24), cls_text, HORIZONTAL_ALIGNMENT_LEFT, W * 0.55, 17, UiTheme.MUTED)
	var tw := _font_b.get_string_size(hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(_font_b, Vector2(size.x - 14 - tw, 25), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	# bar: back, trail, fill, gloss, border
	var bar := Rect2(12, 32, size.x - 24, 18)
	var back := UiTheme.box(Color(0, 0, 0, 0.45), 9, Color(0, 0, 0, 0), 0, 0)
	draw_style_box(back, bar)
	if _trail > _shown + 0.002:
		var tr := UiTheme.box(Color(1, 0.93, 0.85, 0.85), 9, Color(0, 0, 0, 0), 0, 0)
		draw_style_box(tr, Rect2(bar.position, Vector2(maxf(bar.size.x * _trail, 18), bar.size.y)))
	if _shown > 0.003:
		var c := hp_color(_shown)
		if low: c = c.lerp(Color(1, 0.55, 0.5), pl * 0.5)
		var fill := UiTheme.box(c, 9, c.darkened(0.25), 0, 0)
		fill.border_width_bottom = 3
		var fw := maxf(bar.size.x * _shown, 18)
		draw_style_box(fill, Rect2(bar.position, Vector2(fw, bar.size.y)))
		var gloss := UiTheme.box(Color(1, 1, 1, 0.28), 5, Color(0, 0, 0, 0), 0, 0)
		draw_style_box(gloss, Rect2(bar.position + Vector2(5, 3), Vector2(maxf(fw - 10, 4), 4)))
	var edge := UiTheme.box(Color(0, 0, 0, 0), 9, Color(1, 1, 1, 0.3), 2, 0)
	edge.draw_center = false
	draw_style_box(edge, bar)
