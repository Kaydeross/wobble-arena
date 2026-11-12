class_name DragScroll
extends ScrollContainer
## A vertical ScrollContainer for card grids that behaves like a phone list on touch and mouse:
##   - drag anywhere (on a card too) to scroll, release to fling with inertia (FRICTION), clamped at the ends;
##   - a tap (press + release with less than TAP_SLOP movement) picks the card under the finger: it emits that card's
##     `pressed`, so a drag never selects anything; a tap that stops a running fling only stops it;
##   - the mouse wheel / trackpad keeps the built-in ScrollContainer behaviour (PC);
##   - keyboard / gamepad focus still presses cards (ui_accept) and follow_focus keeps the focused card in view.
## Cards are added with `add_card(button)`: their button_mask is cleared (so a mouse press does not press them: this
## container decides) and mouse_filter is PASS (hover still shows, the events reach this container).
## Emulated mouse events (touch -> mouse, device -1) are handled like real ones; ScreenTouch/ScreenDrag are then
## swallowed so the built-in touch scrolling does not run as well.
## `reveal(control)` scrolls so a card is in view (centred when the content is taller than the view).
## Used by ui/setup_wizard.gd; tests/ui_layout_test.gd drives it with mouse and touch events.

signal tapped(card: Control)

const TAP_SLOP := 14.0          ## canvas units a press may move and still be a tap (about 10 pt on an iPhone)
const FRICTION := 5.0           ## fling velocity decay per second (exp)
const MIN_FLING := 40.0         ## px/s below which a fling stops
const MAX_FLING := 5000.0

var dragging := false           ## past TAP_SLOP: this press scrolls, it will not pick a card
var velocity := 0.0             ## fling speed, px/s (positive = content moves up, scroll grows)
var _down := false
var _press_pos := Vector2.ZERO  ## global position of the press
var _last_pos := Vector2.ZERO
var _last_t := 0.0
var _start_scroll := 0.0
var _stopped_fling := false
var _scroll_f := 0.0            ## sub-pixel scroll position while flinging

func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	follow_focus = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(false)

func _ready() -> void:
	_style_bar()

## A card the container picks on tap. Hover still works; presses come here.
func add_card(b: BaseButton) -> void:
	b.button_mask = 0
	b.mouse_filter = Control.MOUSE_FILTER_PASS

func max_scroll() -> float:
	var c := _content()
	return maxf(0.0, (c.size.y if c else 0.0) - size.y)

func _content() -> Control:
	for c in get_children():
		if c is Control and not (c is ScrollBar): return c
	return null

## Scrolls so `c` (a descendant of the content) is fully in view, centred when there is room to scroll.
func reveal(c: Control) -> void:
	if c == null or not is_ancestor_of(c): return
	var content := _content()
	var y := c.get_global_rect().position.y - content.get_global_rect().position.y
	var target := y - (size.y - c.size.y) * 0.5
	velocity = 0.0
	set_process(false)
	scroll_vertical = int(clampf(target, 0.0, max_scroll()))

func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch or e is InputEventScreenDrag:
		accept_event()   # the emulated mouse events drive us; keep the built-in touch scroll out of it
		return
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT: return   # wheel: built-in
		accept_event()
		var gp := _global(mb.position)
		if mb.pressed: _press(gp)
		else: _release(gp)
	elif e is InputEventMouseMotion and _down:
		accept_event()
		_move(_global((e as InputEventMouseMotion).position))

## Event positions arrive in this control's local space (the viewport transforms them as they bubble up).
func _global(local: Vector2) -> Vector2:
	return get_global_transform() * local

func _now() -> float:
	return Time.get_ticks_usec() / 1e6

func _press(gp: Vector2) -> void:
	_down = true
	dragging = false
	_stopped_fling = absf(velocity) > 200.0
	velocity = 0.0
	set_process(false)
	_press_pos = gp
	_last_pos = gp
	_last_t = _now()
	_start_scroll = scroll_vertical

func _move(gp: Vector2) -> void:
	if not dragging and gp.distance_to(_press_pos) > TAP_SLOP:
		dragging = true
	if dragging:
		var t := _now()
		var dt := maxf(t - _last_t, 1e-3)
		var inst := -(gp.y - _last_pos.y) / dt
		velocity = lerpf(velocity, inst, 0.6) if dt < 0.1 else inst
		_scroll_f = clampf(_start_scroll - (gp.y - _press_pos.y), 0.0, max_scroll())
		scroll_vertical = int(round(_scroll_f))
		_last_t = t
	_last_pos = gp

func _release(gp: Vector2) -> void:
	if not _down: return
	_down = false
	if dragging:
		dragging = false
		if _now() - _last_t > 0.08: velocity = 0.0   # finger rested before lifting: no fling
		velocity = clampf(velocity, -MAX_FLING, MAX_FLING)
		_scroll_f = scroll_vertical
		set_process(absf(velocity) > MIN_FLING)
		return
	velocity = 0.0
	if _stopped_fling: return
	var card := card_at(gp)
	if card:
		if card is BaseButton and not (card as BaseButton).disabled:
			(card as BaseButton).pressed.emit()
		tapped.emit(card)

## The card (a direct child of the content) under a global point, or null.
func card_at(gp: Vector2) -> Control:
	var content := _content()
	if content == null or not get_global_rect().has_point(gp): return null
	for c in content.get_children():
		if c is Control and (c as Control).visible and (c as Control).get_global_rect().has_point(gp): return c
	return null

func _process(dt: float) -> void:
	_scroll_f += velocity * dt
	var m := max_scroll()
	if _scroll_f <= 0.0 or _scroll_f >= m:
		_scroll_f = clampf(_scroll_f, 0.0, m)
		velocity = 0.0
	velocity *= exp(-FRICTION * dt)
	scroll_vertical = int(round(_scroll_f))
	if absf(velocity) < MIN_FLING:
		velocity = 0.0
		set_process(false)

## A wider, always readable scroll bar (a rounded yellow-white grabber on a dark track).
func _style_bar() -> void:
	var bar := get_v_scroll_bar()
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.25)
	track.set_corner_radius_all(5)
	track.content_margin_left = 5; track.content_margin_right = 5
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var g := StyleBoxFlat.new()
		g.bg_color = Color(1, 1, 1, 0.55) if k == "grabber" else UiTheme.ACCENT
		g.set_corner_radius_all(5)
		g.content_margin_left = 5; g.content_margin_right = 5
		bar.add_theme_stylebox_override(k, g)
	bar.custom_minimum_size.x = 10
