class_name ArcadeBossHud
extends Control
## The Arcade run's top-centre HUD: a small run strip ("Stage 3 / 6   Lives 2") and, while a boss stands, its health bar in the
## stage's bar colour (name inside, phase ticks at 66 / 33 %). World._update_mode_ui calls place() every frame: it hangs under
## the toast band (MatchHud.TOP_STACK, the slot the team board uses), between the K.O. panel and the radar (and the kill feed
## when it reaches this far), and returns where the mode line may start, so nothing here overlaps the toast, team board or
## mode line (docs/UI_REVIEW.md: MIN_FONT, MIN_GAP). Pure presentation: it reads the ArcadeManager and never changes it.

const STRIP_FONT := 17
const BAR_FONT := 15
const BAR_H := 24.0
const STRIP_H := 24.0
const MIN_W := 170.0
const MAX_W := 380.0
const GAP := 6.0

var m: ArcadeManager
var strip: Label
var bar: Control
var name_l: Label
var pct_l: Label
var _shown := 1.0

func _init() -> void:
	name = "ArcadeHud"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _ready() -> void:
	strip = Label.new()
	strip.name = "Strip"
	strip.theme_type_variation = &"HudLabel"
	strip.add_theme_font_size_override("font_size", STRIP_FONT)
	strip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	bar = Control.new()
	bar.name = "Bar"
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(_draw_bar)
	add_child(bar)
	name_l = _bar_label("BossName", HORIZONTAL_ALIGNMENT_LEFT)
	pct_l = _bar_label("BossPct", HORIZONTAL_ALIGNMENT_RIGHT)

func _bar_label(n: String, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.name = n
	l.theme_type_variation = &"HudLabel"
	l.add_theme_font_size_override("font_size", BAR_FONT)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	l.add_theme_constant_override("outline_size", 5)                 # white text stays readable on any bar colour
	l.add_theme_color_override("font_outline_color", Color(0.04, 0.07, 0.09, 0.95))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(l)
	return l

func bind(manager: ArcadeManager) -> void:
	m = manager
	_shown = 1.0

## The boss bar shows only while a boss is alive in a run.
func boss_visible() -> bool:
	return m != null and visible and bar != null and bar.visible

## The whole HUD rectangle (tests).
func rect() -> Rect2:
	return Rect2(position, size)

static func color_of(i: int) -> Color:
	return Color.from_rgba8((i >> 16) & 255, (i >> 8) & 255, i & 255)

## Lays the strip and bar out under `top` (canvas y) and returns the y the next element (mode line) may start at.
func place(w: Node, top: float, delta: float = 0.0) -> float:
	if m == null or strip == null or m.sim == null or w.results_open() or not (m.state in ["fight", "clearing", "failing"]):
		visible = false
		return top
	visible = true
	var vs := get_viewport_rect().size
	var hud: Control = w.hud
	var lo := 0.0
	var hi := vs.x
	var sc: Control = hud.get_node("Score")
	lo = sc.position.x + sc.size.x * sc.scale.x + 10.0
	var rd: Control = hud.get_node("Radar")
	hi = rd.position.x - 10.0
	var show_bar := m.boss_active()
	var h := STRIP_H + (BAR_H + 2.0 if show_bar else 0.0)
	var fd: Control = hud.get_node_or_null("Feed")
	if fd != null and fd.get_child_count() > 0 and fd.position.y < top + h:    # a kill feed that reaches under the radar
		hi = minf(hi, fd.position.x - 10.0)
	var width := clampf(minf(MAX_W, hi - lo), MIN_W, MAX_W)
	var x := clampf(vs.x / 2.0 - width / 2.0, lo, maxf(lo, hi - width))
	strip.text = "%s   %s" % [tr("Stage %d / %d") % [m.stage + 1, ArcadeManager.count()], tr("Lives %d") % m.lives]
	strip.size = Vector2(width, STRIP_H)
	strip.position = Vector2.ZERO
	bar.visible = show_bar
	if show_bar:
		bar.position = Vector2(0.0, STRIP_H + 2.0)
		bar.size = Vector2(width, BAR_H)
		var f := m.boss_frac()
		_shown = move_toward(_shown, f, maxf(delta, 0.0) * 1.2) if delta > 0.0 else f
		name_l.text = tr(m.boss.name)
		pct_l.text = "%d%%" % ceili(f * 100.0)
		pct_l.size = Vector2(46.0, BAR_H)
		pct_l.position = Vector2(width - 46.0 - 6.0, 0.0)
		name_l.size = Vector2(width - 46.0 - 18.0, BAR_H)
		name_l.position = Vector2(8.0, 0.0)
		bar.queue_redraw()
	position = Vector2(x, top)
	size = Vector2(width, h)
	return top + h + GAP

func _draw_bar() -> void:
	if m == null or m.boss == null: return
	var w := bar.size.x
	var col := color_of(int(m.stage_def().get("hp_bar_color", 0xffa500)))
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.09, 0.11, 0.86)
	back.set_corner_radius_all(8)
	back.border_color = Color(1, 1, 1, 0.28)
	back.set_border_width_all(2)
	back.draw(bar.get_canvas_item(), Rect2(Vector2.ZERO, bar.size))
	var inner := Rect2(Vector2(3, 3), Vector2((w - 6.0) * clampf(_shown, 0.0, 1.0), bar.size.y - 6.0))
	if inner.size.x > 0.5:
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(col.r, col.g, col.b, 0.9)
		fill.set_corner_radius_all(6)
		fill.draw(bar.get_canvas_item(), inner)
	for ph: float in ArcadeManager.PHASES:        # phase ticks at 66 / 33 %
		var tx := 3.0 + (w - 6.0) * ph
		bar.draw_line(Vector2(tx, 1.0), Vector2(tx, bar.size.y - 1.0), Color(1, 1, 1, 0.8), 2.0)
