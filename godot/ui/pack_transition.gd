class_name PackTransition
extends Control
## The full-screen transition that plays when a pack is entered from the pack selector (ui/pack_selector.gd), one per pack,
## all drawn in code (Control._draw, one canvas_item shader, no imported art or video):
##   construction  the hazard-tape wipe (ui/dlc_transition.gd, reused as it is) with its banner
##   kitchen       "On Fire": a flame wall climbs the screen (shaders/pack_flame_wipe.gdshader), embers, a frying-pan CLANG
##   xmas          "Ho Ho Ho": snow swirls, wrapping paper closes, a ribbon cross wraps it and a bow pops; it unwraps again
##   australia     "Hey Mate": dusty red wipe in three layers, a sunburst, a spinning boomerang with speed streaks, a crack
##   lite          the lowest graphics tier (Tier.q() == 0, Settings > Graphics > Effects: Low): a plain colour wipe + fade
## Every style is a function of one number, `p` (0..1 over `dur` seconds): cover 0 -> 0.5, `on_done` runs at p = 0.5 (the screen is hidden:
## the caller opens the pack's hub underneath), reveal 0.5 -> 1, every curve eased and every element on an overlapping envelope. So a screenshot at any p is exact
## (`scrub`), and tests can step it by hand.
##
## Safety: input never waits on it. A tap / key / pad button skips it (the hub opens at once if it had not yet); a safety timer
## ends it at 2x its length + 1 s however the frame loop behaves; it frees itself. Headless runs (DisplayServer headless, no
## `force_run`) skip the animation and run the same end logic at once. Particles are drawn from small pooled arrays (<= 60)
## with a local RandomNumberGenerator (never combat.rng); the only shader is the one fullscreen flame ColorRect.
##
## API: PackTransition.play(pack_id, parent, on_done, on_end) -> the node.
##   on_done  at the switch point: the screen is fully covered, open the hub now.
##   on_end   after the reveal (or a skip): the transition is gone.

const FIRE := preload("res://ui/transitions/pack_transition_fire.gd")
const XMAS := preload("res://ui/transitions/pack_transition_xmas.gd")
const OUTBACK := preload("res://ui/transitions/pack_transition_outback.gd")
const SITE := preload("res://ui/transitions/pack_transition_site.gd")
const LITE := preload("res://ui/transitions/pack_transition_lite.gd")

const SWITCH_AT := 0.5
const DURATION := {"construction": 1.3, "kitchen": 1.15, "xmas": 1.35, "australia": 1.2}
const MAX_PARTICLES := 60

## Tests: animate even under the headless dummy driver (a short `speed` keeps them fast), and pick a style by hand.
static var force_run := false
static var speed := 1.0                ## duration scale (tests: 0.05); 1.0 in the game
static var force_style := ""           ## tests / shots: "" = by tier
static var live := 0                   ## transitions running right now (tests: must be 0 afterwards)
static var played := 0                 ## transitions started so far (tests)

var pack_id := ""
var style := ""
var dur := 1.2
var t := 0.0
var p := 0.0
var manual := false                    ## screenshots / tests: nothing advances `p` but scrub()
var accent := Color("#ffc21a")
var label := ""                        ## the pack's name (translated, upper case) for the banner
var rng := RandomNumberGenerator.new()
var switched := false
var finished := false
var skipped := false
var instant := false                   ## headless: no animation, the end logic runs at once
var on_done := Callable()
var on_end := Callable()
var font: Font
var _impl: RefCounted
var _cue_i := 0
var _timer: SceneTreeTimer

static func tier_lite() -> bool:
	var loop := Engine.get_main_loop()
	var tier: Node = (loop as SceneTree).root.get_node_or_null("Tier") if loop is SceneTree else null
	return tier != null and int(tier.quality()) == 0     # Tier.Quality.LOW: the web build, or Settings > Graphics > Effects: Low

## The style a pack plays right now ("lite" on the lowest graphics tier).
static func style_for(id: String) -> String:
	if force_style != "": return force_style
	if tier_lite(): return "lite"
	return {"construction": "site", "kitchen": "fire", "xmas": "xmas", "australia": "outback"}.get(id, "lite")

static func duration_of(id: String) -> float:
	var s := style_for(id)
	return (0.9 if s == "lite" else float(DURATION.get(id, 1.2))) * speed

## Starts the transition for `pack_id` over `parent`. See the class comment for the two callbacks.
static func play(pack_id_: String, parent: Node, done: Callable = Callable(), end: Callable = Callable()) -> PackTransition:
	var n := PackTransition.new()
	n.setup(pack_id_, done, end)
	played += 1
	if parent == null or not is_instance_valid(parent):
		n.free()
		if done.is_valid(): done.call()
		if end.is_valid(): end.call()
		return null
	live += 1
	n.instant = DisplayServer.get_name() == "headless" and not force_run
	parent.add_child(n)
	if n.instant:
		n._finish()            # no frames to animate: the same end logic, at once
	return n

func setup(id: String, done: Callable, end: Callable) -> void:
	pack_id = id
	on_done = done
	on_end = end
	style = style_for(id)
	dur = maxf(0.05, duration_of(id))
	accent = PackRegistry.accent(id) if PackRegistry.has(id) else Color("#ffc21a")
	label = tr(PackRegistry.display_name(id)).to_upper() if PackRegistry.has(id) else ""
	rng.seed = hash("pack-transition:" + id)       # the same jitter every time: a screenshot is reproducible
	name = "PackTransition"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 200
	font = UiTheme.font(700)
	match style:
		"fire": _impl = FIRE.new()
		"xmas": _impl = XMAS.new()
		"outback": _impl = OUTBACK.new()
		"site": _impl = SITE.new()
		_: _impl = LITE.new()

func _ready() -> void:
	if instant or finished: return
	if _impl != null: _impl.setup(self)
	if not manual:
		# the safety net: ends the transition whatever the frame loop does (a paused tree, a hitching frame, a bug in a style)
		_timer = get_tree().create_timer(dur * 2.0 + 1.0, true, false, true)
		_timer.timeout.connect(_finish)
	queue_redraw()

func _exit_tree() -> void:
	if not finished:
		finished = true
		live = maxi(0, live - 1)

func _process(dt: float) -> void:
	if manual or finished: return
	t += minf(dt, 0.05)
	_set_p(t / dur)

func _set_p(v: float) -> void:
	p = clampf(v, 0.0, 1.0)
	while _impl != null and _cue_i < _impl.cues.size() and p >= float(_impl.cues[_cue_i][0]):
		_sfx(str(_impl.cues[_cue_i][1]), float(_impl.cues[_cue_i][2]))
		_cue_i += 1
	if p >= SWITCH_AT and not switched: _switch()
	if _impl != null and not finished: _impl.tick(self)
	if p >= 1.0: _finish()
	else: queue_redraw()

## Screenshots / tests: show moment `v` (0..1) without any clock (call on a `manual` node).
func scrub(v: float) -> void:
	_set_p(v)
	if _impl != null: _impl.tick(self)
	queue_redraw()

func _switch() -> void:
	if switched: return
	switched = true
	if on_done.is_valid(): on_done.call()

## Tap, key or pad button: the transition ends now (the hub opens first when it had not yet).
func skip() -> void:
	if finished: return
	skipped = true
	_finish()

func _input(e: InputEvent) -> void:
	if finished or manual: return
	var hit: bool = (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed) \
		or (e is InputEventKey and e.pressed and not e.echo) or (e is InputEventJoypadButton and e.pressed)
	if hit:
		get_viewport().set_input_as_handled()
		skip()

func _finish() -> void:
	if finished: return
	finished = true
	live = maxi(0, live - 1)
	if not switched: _switch()
	if _timer != null and _timer.timeout.is_connected(_finish): _timer.timeout.disconnect(_finish)
	var cb := on_end
	if is_inside_tree(): queue_free()
	if cb.is_valid(): cb.call()

func _draw() -> void:
	if _impl != null and not finished: _impl.draw(self)

func _sfx(n: String, vol: float) -> void:
	var loop := Engine.get_main_loop()
	var a: Node = (loop as SceneTree).root.get_node_or_null("Audio") if loop is SceneTree else null
	if a != null and a.has_method("play"): a.call("play", n, vol)

# ---------------------------------------------------------------- shared drawing helpers

static func smooth(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

static func seg(v: float, a: float, b: float) -> float:
	return clampf((v - a) / maxf(0.0001, b - a), 0.0, 1.0)

static func out_back(x: float, k := 1.70158) -> float:
	x = clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + (k + 1.0) * x * x * x + k * x * x

static func out_cubic(x: float) -> float:
	x = 1.0 - clampf(x, 0.0, 1.0)
	return 1.0 - x * x * x

static func in_out(x: float) -> float:
	return smooth(x)

## 0 -> 1 over the first half (the screen fills), and 0 -> 1 over the second (it empties). Styles ease these (smooth) themselves.
func cover() -> float:
	return seg(p, 0.0, 0.5)

func reveal() -> float:
	return seg(p, 0.5, 1.0)

## A smooth bell: eases in over a0..a1, holds, eases out over b0..b1 (overlapping envelopes, never a pop).
static func env(v: float, a0: float, a1: float, b0: float, b1: float) -> float:
	return smooth(seg(v, a0, a1)) * (1.0 - smooth(seg(v, b0, b1)))

## The pack's name as a banner centred on `centre`, fitted to `max_w` (never clipped), with an outline.
func banner(text: String, centre: Vector2, max_w: float, fill: Color, outline: Color, alpha := 1.0, pop := 1.0, base_fs := 64) -> void:
	banner_on(self, text, centre, max_w, fill, outline, alpha, pop, base_fs)

## banner() on another CanvasItem (an overlay child that is drawing right now).
func banner_on(c: CanvasItem, text: String, centre: Vector2, max_w: float, fill: Color, outline: Color, alpha := 1.0, pop := 1.0, base_fs := 64) -> void:
	if alpha <= 0.01 or text == "": return
	var fs := FitText.size_for(font, text, base_fs, max_w / maxf(0.2, pop), 16)
	fs = int(round(fs * pop))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pos := Vector2(centre.x - w * 0.5, centre.y + (font.get_ascent(fs) - font.get_descent(fs)) * 0.5)
	var ol := maxi(3, int(fs * 0.12))
	c.draw_string_outline(font, pos + Vector2(0, fs * 0.05), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, Color(0, 0, 0, 0.35 * alpha))
	c.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ol, Color(outline, alpha))
	c.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(fill, alpha))

## A filled regular-ish polygon from points (helper: skips degenerate input).
func poly(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() >= 3 and c.a > 0.003: draw_colored_polygon(pts, c)

## A polygon that may be self-intersecting (a wipe front): drawn as a strip of quads so it never fails to triangulate.
func poly_safe(pts: PackedVector2Array, c: Color) -> void:
	var n := pts.size() / 2
	if n < 2 or c.a <= 0.003: return
	for i in n - 1:
		var q := PackedVector2Array([pts[i], pts[i + 1], pts[pts.size() - 2 - i], pts[pts.size() - 1 - i]])
		draw_colored_polygon(q, c)

## A four-point sparkle.
func sparkle(c: Vector2, r: float, col: Color) -> void:
	if r < 0.5 or col.a <= 0.01: return
	var k := r * 0.22
	poly(PackedVector2Array([c + Vector2(0, -r), c + Vector2(k, -k), c + Vector2(r, 0), c + Vector2(k, k), c + Vector2(0, r), c + Vector2(-k, k), c + Vector2(-r, 0), c + Vector2(-k, -k)]), col)

## The shortest screen side, the unit the styles size things in.
func unit() -> float:
	return minf(size.x, size.y)
