class_name TouchLayoutEditor
extends Control
## "Move buttons" (Settings > Controls): a dimmed overlay over the title screen or the paused match behind it (the
## Settings page body is hidden meanwhile) with the real touch buttons drawn in place, draggable with a finger or the
## mouse, and a live dashed boundary for the safe area. The action bar sits at the top inside the safe area, far from
## the buttons at the bottom, so it works in portrait and landscape alike.
##
##   open()    remember the current Settings `touch_layout`, show the buttons, and silence every touch layer
##             (TouchControls.suspend) so dragging can never fire a weapon -- also behind a paused match.
##   drag      a button follows the finger/mouse, clamped entirely inside the safe area; every move writes the draft
##             to Settings at once, so the preview (and any live touch layer) updates in real time.
##   Save      keep the layout (Settings `touch_layout`, JSON {id: [dx, dy]}, screen-space canvas px) and close.
##   Reset     put every button back on the device's own default layout (phone or tablet); Save keeps that.
##   Back      close and put the remembered layout back: dismissing without Save changes nothing.
##
## The offset is applied to the mirrored default position (see input/touch_controls.gd), so left-handed mode mirrors the
## stock layout and keeps each nudge where the player put it on screen. A layout saved on a big screen is clamped, not
## broken, on a small one. Bad/partial JSON is parsed defensively (one bad entry only resets that button).

signal closed
signal saved

const TOUCH := 62.0                       ## canvas px: 45 pt at the UI scale (Apple asks 44)
const MARGIN := Vector4(28, 16, 28, 12)   ## left, top, right, bottom inside the safe area (like ui_page.gd)
const PAD := 12.0                         ## extra grab radius around a button, canvas px
const HINT := "Drag a button where your thumb wants it.\nSave keeps this layout on this device. Back leaves it as it was."
const ORDER := ["fire", "jump", "melee", "context"]

var preview: TouchControls                 ## the real touch layer, in editor_mode: draws the buttons, takes no input
var draft := {}                            ## button id -> Vector2 offset from the device default (canvas px)
var buttons := {}                          ## "back" | "reset" | "save" -> Button
var hint: Label
var frame: Control                         ## draws the live safe-area boundary
var _ui: MarginContainer
var _drag := ""                            ## button id being dragged, "" = none
var _grab := Vector2.ZERO                  ## where the finger grabbed the button, from its centre
var _prev := "{}"                          ## Settings `touch_layout` when the editor opened
var _dirty := false                        ## a drag changed Settings: Back has to put `_prev` back

func _init() -> void:
	name = "TouchLayoutEditor"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _ready() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.02, 0.07, 0.09, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	preview = TouchControls.new()
	preview.name = "Preview"
	preview.editor_mode = true
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(preview)
	frame = SafeAreaFrame.new()
	frame.name = "SafeFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(frame)
	_ui = MarginContainer.new()
	_ui.name = "Ui"
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ui)
	var col := VBoxContainer.new()
	col.name = "Box"
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", UiTheme.SP_3)
	_ui.add_child(col)
	var panel := PanelContainer.new()
	panel.name = "HintPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.box(Color(0.02, 0.07, 0.09, 0.86), 16, UiTheme.PANEL_EDGE, 2, 0))
	col.add_child(panel)
	hint = Label.new()
	hint.name = "Hint"
	hint.text = HINT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 19)
	panel.add_child(hint)
	var row := HBoxContainer.new()            # the action bar: top of the screen, clear of the buttons at the bottom
	row.name = "Bar"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", UiTheme.SP_3)
	col.add_child(row)
	for it: Array in [["back", "Back", close], ["reset", "Reset", reset_draft], ["save", "Save", save]]:
		var b := Button.new()
		b.name = str(it[0]).capitalize()
		b.text = str(it[1])
		b.custom_minimum_size = Vector2(0, TOUCH)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(it[2])
		row.add_child(b)
		buttons[str(it[0])] = b
	get_viewport().size_changed.connect(apply_safe_area)
	apply_safe_area()

## Show the editor. Remembers the saved layout so Back can put it back; silences gameplay touches meanwhile.
func open() -> void:
	if preview == null:
		return
	_prev = str(Settings.get_value("touch_layout", "{}"))
	draft = TouchControls.parse_layout(_prev)
	_drag = ""
	_dirty = false
	preview.visible = true
	preview.queue_redraw()
	frame.queue_redraw()
	TouchControls.suspend = true
	visible = true
	apply_safe_area()

## Keep the draft layout (Settings `touch_layout`) and close.
func save() -> void:
	_dirty = false
	_prev = TouchControls.layout_text(draft)
	Settings.set_value("touch_layout", _prev)
	close()
	saved.emit()

## Back to the device default (phone or tablet), live; Save still has to keep it.
func reset_draft() -> void:
	draft.clear()
	_dirty = true
	_apply_live()
	preview.queue_redraw()

## Close without keeping the draft: the layout from open() goes back.
func close() -> void:
	if not visible:
		return
	_drag = ""
	visible = false
	if _dirty:
		_dirty = false
		Settings.set_value("touch_layout", _prev)
	TouchControls.suspend = false
	if preview != null:
		preview.queue_redraw()
	closed.emit()

func _notification(what: int) -> void:
	# The page is hidden by something other than close() (a menu switch, the title): never leave the touch layers
	# silenced behind it.
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		TouchControls.suspend = false
	elif what == NOTIFICATION_EXIT_TREE:
		TouchControls.suspend = false

## The pause menu is hidden without closing its pages when the match is unpaused (Escape while editing), and a parent's
## visibility does not notify its children: notice it here, revert the draft and unmute the touch layers.
func _process(_dt: float) -> void:
	if visible and not is_visible_in_tree():
		close()

## Margins follow the safe area (notch, home indicator) and the live boundary redraws with them.
func apply_safe_area() -> void:
	if _ui == null or not is_inside_tree():
		return
	var i := SafeArea.insets(get_viewport())
	_ui.add_theme_constant_override("margin_left", int(MARGIN.x + i[0]))
	_ui.add_theme_constant_override("margin_top", int(MARGIN.y + i[1]))
	_ui.add_theme_constant_override("margin_right", int(MARGIN.z + i[2]))
	_ui.add_theme_constant_override("margin_bottom", int(MARGIN.w + i[3]))
	if frame != null:
		frame.queue_redraw()

# ---------------- dragging ----------------

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_begin(mb.position)
		else:
			_drag = ""
	elif e is InputEventScreenTouch:
		var t := e as InputEventScreenTouch
		if t.pressed:
			_begin(t.position)
		else:
			_drag = ""
	elif e is InputEventMouseMotion:
		var mm := e as InputEventMouseMotion
		if _drag != "" and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_move(mm.position)
			accept_event()
	elif e is InputEventScreenDrag:
		if _drag != "":
			_move((e as InputEventScreenDrag).position)
			accept_event()

## Pick up the nearest button under the touch (its circle, plus a little grab room).
func _begin(p: Vector2) -> void:
	var best := ""
	var best_d := INF
	for id: String in ORDER:
		var b: Array = preview.button(id)
		if b.is_empty():
			continue
		var r: Array = preview.button_rect(b)
		var d: float = p.distance_to(r[0])
		if d <= float(r[1]) + PAD and d < best_d:
			best = id
			best_d = d
	if best == "":
		return
	_drag = best
	_grab = p - (preview.button_rect(preview.button(best))[0] as Vector2)
	accept_event()

## Follow the finger, clamped so the whole circle stays inside the safe area, and apply the layout live.
func _move(p: Vector2) -> void:
	if _drag == "":
		return
	var b: Array = preview.button(_drag)
	if b.is_empty():
		return
	var vs := preview.get_viewport_rect().size
	var ins: Array = preview.safe_insets()
	var tablet := TouchControls.is_tablet(vs)
	var base: Array = TouchControls.default_rect(b, vs, ins, preview.lefty, preview.scale_k, tablet)
	var off := TouchControls.clamp_offset(b, vs, ins, preview.lefty, preview.scale_k, tablet,
		(p - _grab) - (base[0] as Vector2))
	draft[_drag] = Vector2(roundf(off.x), roundf(off.y))   # whole canvas px: what the saved JSON stores
	_dirty = true
	_apply_live()
	preview.queue_redraw()
	frame.queue_redraw()

## Write the draft to Settings: Settings.changed makes the preview (and any live touch layer) follow at once.
func _apply_live() -> void:
	Settings.set_value("touch_layout", TouchControls.layout_text(draft))

# ---------------- live safe-area boundary ----------------

## A dimmed overlay is already up; this outlines (and slightly darkens outside) the SafeArea rect the buttons are
## clamped to, so the edges the player can drag to are visible while they drag.
class SafeAreaFrame extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var vp := get_viewport()
		if vp == null:
			return
		var full := get_viewport_rect()
		var safe := SafeArea.rect(vp)
		if safe.size.x <= 0.0 or safe.size.y <= 0.0:
			return
		var outside := Color(0, 0, 0, 0.3)
		if safe.position.y > 0.0:
			draw_rect(Rect2(0.0, 0.0, full.size.x, safe.position.y), outside)
		if safe.end.y < full.size.y:
			draw_rect(Rect2(0.0, safe.end.y, full.size.x, full.size.y - safe.end.y), outside)
		if safe.position.x > 0.0:
			draw_rect(Rect2(0.0, safe.position.y, safe.position.x, safe.size.y), outside)
		if safe.end.x < full.size.x:
			draw_rect(Rect2(safe.end.x, safe.position.y, full.size.x - safe.end.x, safe.size.y), outside)
		var col := Color(UiTheme.ACCENT.r, UiTheme.ACCENT.g, UiTheme.ACCENT.b, 0.9)
		var dash := 12.0
		draw_dashed_line(safe.position, safe.position + Vector2(safe.size.x, 0.0), col, 2.5, dash, true)
		draw_dashed_line(safe.position + Vector2(safe.size.x, 0.0), safe.end, col, 2.5, dash, true)
		draw_dashed_line(safe.end, safe.position + Vector2(0.0, safe.size.y), col, 2.5, dash, true)
		draw_dashed_line(safe.position + Vector2(0.0, safe.size.y), safe.position, col, 2.5, dash, true)
