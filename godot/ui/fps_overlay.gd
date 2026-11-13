extends CanvasLayer
## FPS overlay (autoload `FpsOverlay`): a small pill at the top centre with FPS, frame time, renderer, Tier,
## 3D resolution scale and draw calls, plus the average and 1% low FPS over the last 10 s.
## Shown when Settings `show_fps` is on (title options, pause menu); F3 or a three-finger tap toggles it so
## testers can open it on a device. Reads Performance monitors only.

const WINDOW := 10.0         ## seconds of frame times kept for avg / 1% low
const REFRESH := 0.25
const TAP_SPREAD := 0.25     ## three fingers must land within this many seconds...
const TAP_HOLD := 0.6        ## ...and all lift before this long after the first

var _panel: PanelContainer
var _perf: PerfOverlay = null           ## Settings `perf_overlay`: the four-line device readout (ui/perf_overlay.gd), only while on
var _top: Label
var _bot: Label
var _times := PackedFloat64Array()     ## frame dt, oldest first
var _sum := 0.0
var _refresh := 0.0
var _avg := 0.0
var _low := 0.0
var _taps := {}                        ## touch index -> time it went down
var _tap_start := -1.0
var _tap_max := 0
var _now := 0.0

func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.09, 0.11, 0.72)
	sb.border_color = Color(1, 0.812, 0.353, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 3; sb.content_margin_bottom = 4
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	_top = _line(box, 15, Color(1, 1, 1))
	_bot = _line(box, 12, Color(0.75, 0.85, 0.88))
	_panel.anchor_left = 0.0; _panel.anchor_right = 0.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_END
	get_tree().root.window_input.connect(_on_window_input)
	Settings.changed.connect(func(k, _v):
		if k == "show_fps": _sync()
		elif k == "perf_overlay": _sync_perf())
	_sync()
	_sync_perf()

func _line(parent: Node, fs: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _sync() -> void:
	visible = bool(Settings.get_value("show_fps", false))
	if visible:
		_refresh = REFRESH   # fill the text on the next frame

## The device readout exists only while Settings `perf_overlay` is on (and the soak run is not showing its own).
func _sync_perf() -> void:
	var on := bool(Settings.get_value("perf_overlay", false))
	if on and _perf == null:
		_perf = PerfOverlay.new()
		_perf.name = "PerfOverlay"
		get_tree().root.add_child.call_deferred(_perf)   # not a child of this layer: hiding the FPS pill must not hide it
	elif not on and _perf != null:
		_perf.queue_free()
		_perf = null

func toggle() -> void:
	Settings.set_value("show_fps", not bool(Settings.get_value("show_fps", false)))

## Sees every event before the scene does (the touch layer marks its touches handled).
func _on_window_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_F3:
		toggle()
	elif e is InputEventScreenTouch:
		_three_finger(e)

func _three_finger(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _taps.is_empty():
			_tap_start = _now; _tap_max = 0
		_taps[e.index] = _now
		if _now - _tap_start <= TAP_SPREAD:
			_tap_max = maxi(_tap_max, _taps.size())
		else:
			_tap_max = 0   # a finger joined late: an ordinary multi-touch, not a gesture
	else:
		_taps.erase(e.index)
		if _taps.is_empty():
			if _tap_max == 3 and _now - _tap_start <= TAP_HOLD:
				toggle()
			_tap_max = 0

## Average and 1% low FPS over the frame times kept (the 1% low is the mean of the slowest 1% of frames).
static func stats(times: PackedFloat64Array) -> Vector2:
	if times.is_empty(): return Vector2.ZERO
	var s := 0.0
	for t in times: s += t
	var sorted := times.duplicate()
	sorted.sort()
	var n := maxi(1, times.size() / 100)
	var worst := 0.0
	for i in n: worst += sorted[sorted.size() - 1 - i]
	worst /= n
	return Vector2(times.size() / maxf(s, 1e-6), 1.0 / maxf(worst, 1e-6))

func _process(dt: float) -> void:
	_now += dt
	if not visible: return
	_times.append(dt); _sum += dt
	while _sum > WINDOW and _times.size() > 1:
		_sum -= _times[0]
		_times.remove_at(0)
	_refresh += dt
	if _refresh < REFRESH: return
	_refresh = 0.0
	var st := stats(_times)
	_avg = st.x; _low = st.y
	var fps := Engine.get_frames_per_second()
	var vp := get_viewport()
	var top_inset: float = SafeArea.insets(vp)[1]
	_top.text = tr("%d fps   %.1f ms   avg %.0f   1%% low %.0f") % [fps, dt * 1000.0, _avg, _low]
	var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_bot.text = tr("%s · %s · 3D x%.2f · %d draws") % [renderer_name(), Tier.tier_name(), vp.scaling_3d_scale, draws]
	_place(top_inset)

## Timing lives below the score instead of the notification band at the top centre. This keeps
## objective banners readable and gives the compact telemetry a stable corner.
func _place(top_inset: float) -> void:
	var ins := SafeArea.insets(get_viewport())
	var pos := Vector2(float(ins[0]) + 14.0, top_inset + 4.0)
	var found := get_tree().root.find_children("*", "MatchHud", true, false)
	if not found.is_empty():
		var score := found[0].get_node_or_null("Score") as Control
		if score and score.is_visible_in_tree():
			pos = Vector2(score.position.x, score.position.y + score.size.y * score.scale.y + 6.0)
	_panel.position = pos

func rect() -> Rect2:
	return Rect2(_panel.position, _panel.size)

static func renderer_name() -> String:
	var m := RenderingServer.get_current_rendering_method()
	return TranslationServer.translate({"forward_plus": "Forward+", "mobile": "Mobile", "gl_compatibility": "Compatibility"}.get(m, m))
