class_name TitleShowcase
extends Control
## The title screen's DLC showcase (scripts/main.gd): the picture of the 3D stage (ui/showcase_stage.gd: the player's
## wobbler on a site pedestal, a tower crane holding a DLC pack's container) drawn behind the title, plus `overlay`,
## the controls that sit on top of it. Data-driven: the packs come from DLCPacks (dlc/dlc_packs.gd).
##
## IDLE      the container hangs closed, top right of the full-screen stage; a hazard-striped "CONSTRUCTION - NEW" pill
##           hangs under it (a real Button: mouse, touch, keyboard, gamepad and screen readers), and a tap on the
##           container itself is picked with a ray (tap_at, from this control's own gui_input).
## OPENING   the title's own controls fade (ui_k -> 1, the owner hides them), the camera moves in, the crane lowers
##           the container onto the pedestal (dust + thud), the latch lifts and both doors swing open.
## OPENED    the pack's weapons hang on the racks: tap one (ray pick) or focus it (a proxy Button per rack cell) and
##           the wobbler holds it, wearing the pack's hat. Preview only: nothing is saved. Bottom bar: Back,
##           "< SWAP PACK" / "SWAP PACK >" (two packs or more), "TEST IN <ARENA>" (test_requested), and
##           "UNLOCK PACK" (unlock_requested) or an OWNED badge. Ownership is read live from the pack every refresh.
##           The DON'T ENTER sign (top right) leads on to the Construction title (site_requested); on that title the
##           pill and the sign read EXIT SITE instead (`site_exit`).
## SWAPPING  doors shut, the container is hoisted out of the picture, the next pack's comes down and opens.
## CLOSING   doors shut, the container is hoisted back to its hover, the camera and the title return.
##
## Input never locks: every animation is one tween over the stage's pose numbers, started from wherever they are now
## (so open and back can interrupt each other half-way), and anything that cannot be done in the current state is
## ignored, never queued up behind a dead tween. While not IDLE a full-screen catcher keeps taps off the title.

signal test_requested(pack: DLCPackData)
signal unlock_requested(pack: DLCPackData)
signal site_requested()                ## the DON'T ENTER / EXIT SITE sign or pill: the owner switches title
signal ui_changed(k: float)            ## 0 = the title's own controls show, 1 = they are gone
signal state_changed(state: int)

enum State { IDLE, OPENING, OPENED, SWAPPING, CLOSING }

const TOUCH := 60.0                    ## canvas px: 44 pt on a phone in landscape (UiScale)
const GAP := 12.0
const MAX_PIXELS := 2200000.0          ## the stage never renders more than this (phones have 3x screens)

var state: int = State.IDLE
var stage: ShowcaseStage
var view: TextureRect
var overlay: Control                   ## the owner adds this above the title's own controls
var packs: Array[DLCPackData] = []
var index := 0
var speed := 1.0                       ## animation speed (tests run it faster)
var shown := true                      ## the title home is showing (the owner hides the stage behind other pages)
var covered := Callable()              ## -> bool: an opaque page covers the title (no need to render)
var unit := 1.0                        ## touch-size factor (portrait: the canvas is 3 px per pt, so everything grows)
var safe_rect := Rect2()               ## the safe area in canvas px, padding included (the owner sets it)
var site_exit := false                 ## the Construction title is showing: the pill and the sign say EXIT SITE
var ui_k := 0.0: set = _set_ui_k
var thuds := 0                         ## landings so far (tests)

var pill: DlcPill
var site_b: DontEnterSign
var back_b: Button
var prev_b: Button
var next_b: Button
var test_b: Button
var unlock_b: Button
var owned_chip: PanelContainer
var header: PanelContainer
var caption: Label
var catcher: Control
var bar: HBoxContainer
var proxies: Array[Button] = []
var _name_l: Label
var _sub_l: Label
var _lock: Control
var _tw: Tween
var _queued_back := false
var _t := 0.0
var _heavy: Font
var _pixel_scale := 1.0

func _init() -> void:
	name = "Showcase"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay = Control.new()
	overlay.name = "ShowcaseUI"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	_heavy = UiTheme.font(700)
	stage = ShowcaseStage.new()
	add_child(stage)
	view = TextureRect.new()
	view.name = "View"
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.texture = stage.get_texture()
	add_child(view)
	_build_overlay()
	reload_packs()
	resized.connect(_fit)
	overlay.draw.connect(_draw_tag_line)
	gui_input.connect(_on_stage_input)
	_fit()
	_sync_active()

func _exit_tree() -> void:
	if _tw and _tw.is_valid(): _tw.kill()

# ---------------------------------------------------------------- packs

## Reads the registry again (tests add packs) and shows the first pack (or keeps the current one when it still exists).
func reload_packs() -> void:
	var keep := pack().pack_id if pack() != null else ""
	packs = DLCPacks.all(Content.weapons, Content.maps)
	index = 0
	for i in packs.size():
		if packs[i].pack_id == keep: index = i
	stage.set_pack(pack())
	_build_proxies()
	refresh()

func pack() -> DLCPackData:
	return packs[index] if index >= 0 and index < packs.size() else null

## Texts and the lock state (asked from the pack now, never remembered). Call after a purchase or a language change.
func refresh() -> void:
	var p := pack()
	visible = p != null and shown
	if p == null:
		pill.visible = false
		return
	var own := p.is_unlocked
	stage.relabel()
	_name_l.text = tr(p.display_name).to_upper()
	_name_l.add_theme_color_override("font_color", p.accent_color)
	_sub_l.text = tr(p.subtitle)
	_lock.visible = not own
	pill.label = tr("EXIT SITE") if site_exit else tr(p.display_name).to_upper()
	pill.lead = "‹" if site_exit else ""
	pill.tag = "" if (own or site_exit) else tr("NEW")
	pill.tooltip_text = tr("Back to the arena") if site_exit else tr(p.display_name) + ": " + tr(p.subtitle)
	pill.set("accessibility_name", (pill.tooltip_text if site_exit else "%s. %s" % [pill.tooltip_text, tr("Tap to open")]))
	site_b.label = tr("EXIT SITE") if site_exit else tr("DON'T ENTER")
	site_b.tooltip_text = tr("Back to the arena") if site_exit else tr("Enter the Construction site")
	site_b.set("accessibility_name", site_b.tooltip_text)
	var arena := tr(str(Content.get_map(p.arena_id).get("name", p.arena_id)))
	test_b.text = tr("TEST IN %s") % arena.to_upper()
	test_b.tooltip_text = tr("Try every weapon of the pack on its arena. Nothing is saved.")
	unlock_b.text = tr("UNLOCK PACK")
	(owned_chip.get_child(0).get_node("Text") as Label).text = tr("Owned").to_upper()
	unlock_b.visible = not own
	owned_chip.visible = own
	var many := packs.size() > 1
	prev_b.visible = many
	next_b.visible = many
	for i in proxies.size():
		var b := proxies[i]
		var on := i < stage.weapon_ids.size() or i == stage.arena_cell()
		b.visible = on
		if not on: continue
		var nm := arena if i == stage.arena_cell() else tr(str(Content.weapons.get(stage.weapon_ids[i], {}).get("name", stage.weapon_ids[i])))
		b.tooltip_text = nm
		b.set("accessibility_name", nm)
	_caption()
	_layout()

func _caption() -> void:
	var p := pack()
	if p == null: return
	if stage.selected >= 0:
		caption.text = tr(str(Content.weapons.get(stage.weapon_ids[stage.selected], {}).get("name", "")))
	else:
		caption.text = tr("Tap a weapon to try it on")

# ---------------------------------------------------------------- the overlay

func _button(node_name: String, primary := false) -> Button:
	var b := Button.new()
	b.name = node_name
	if primary: b.theme_type_variation = &"PrimaryButton"
	b.add_theme_font_override("font", _heavy)
	b.focus_mode = Control.FOCUS_ALL
	return b

func _build_overlay() -> void:
	catcher = Control.new()
	catcher.name = "Catcher"
	catcher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.visible = false
	catcher.gui_input.connect(_on_catcher_input)
	overlay.add_child(catcher)
	# the pill under the hanging container
	pill = DlcPill.new()
	pill.name = "Pill"
	pill.pressed.connect(func() -> void:
		if site_exit: site_requested.emit()
		else: open())
	overlay.add_child(pill)
	site_b = DontEnterSign.new()
	site_b.name = "Site"
	site_b.pressed.connect(func() -> void:
		if state == State.OPENED: site_requested.emit())
	overlay.add_child(site_b)
	# the pack header (opened)
	header = PanelContainer.new()
	header.name = "Header"
	header.theme_type_variation = &"ChipPanel"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(header)
	var hr := HBoxContainer.new()
	hr.name = "Row"
	hr.add_theme_constant_override("separation", UiTheme.SP_3)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(hr)
	_lock = ConstructionStyle.Padlock.new()
	_lock.name = "Lock"
	_lock.size_flags_vertical = SIZE_SHRINK_CENTER
	hr.add_child(_lock)
	_name_l = Label.new()
	_name_l.name = "Name"
	_name_l.add_theme_font_override("font", _heavy)
	hr.add_child(_name_l)
	_sub_l = Label.new()
	_sub_l.name = "Sub"
	_sub_l.theme_type_variation = &"MutedLabel"
	_sub_l.size_flags_vertical = SIZE_SHRINK_CENTER
	hr.add_child(_sub_l)
	caption = Label.new()
	caption.name = "Caption"
	caption.theme_type_variation = &"HudLabel"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(caption)
	back_b = _button("Back")
	back_b.text = "Back"
	back_b.pressed.connect(func() -> void: back())
	overlay.add_child(back_b)
	bar = HBoxContainer.new()
	bar.name = "Bar"
	bar.add_theme_constant_override("separation", int(GAP))
	bar.alignment = BoxContainer.ALIGNMENT_END
	overlay.add_child(bar)
	prev_b = _button("Prev")
	prev_b.pressed.connect(func() -> void: swap(-1))
	bar.add_child(prev_b)
	test_b = _button("Test")
	test_b.pressed.connect(func() -> void:
		if state == State.OPENED and pack() != null: test_requested.emit(pack()))
	bar.add_child(test_b)
	unlock_b = _button("Unlock", true)
	unlock_b.pressed.connect(func() -> void:
		if state == State.OPENED and pack() != null and not pack().is_unlocked: unlock_requested.emit(pack()))
	bar.add_child(unlock_b)
	owned_chip = PanelContainer.new()
	owned_chip.name = "Owned"
	owned_chip.theme_type_variation = &"ChipPanel"
	owned_chip.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.add_child(owned_chip)
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", UiTheme.SP_2)
	orow.alignment = BoxContainer.ALIGNMENT_CENTER
	owned_chip.add_child(orow)
	var chk := LockerScreen.LockerIcon.new("check", 18)
	chk.size_flags_vertical = SIZE_SHRINK_CENTER
	orow.add_child(chk)
	var ol := Label.new()
	ol.name = "Text"
	ol.text = tr("Owned").to_upper()
	ol.add_theme_font_override("font", _heavy)
	ol.add_theme_color_override("font_color", UiTheme.GOOD)
	orow.add_child(ol)
	next_b = _button("Next")
	next_b.pressed.connect(func() -> void: swap(1))
	bar.add_child(next_b)
	JuicyButton.attach_all(overlay)
	_show_opened_ui()

## One focusable Button per rack cell, laid over the cell every frame: keyboard / gamepad / screen-reader access to
## what a finger does with a ray. They ignore the mouse (the catcher picks), and only show their focus ring.
func _build_proxies() -> void:
	for b: Button in proxies: b.queue_free()
	proxies.clear()
	for i in ShowcaseStage.COLS * ShowcaseStage.ROWS:
		var b := Button.new()
		b.name = "Cell%d" % i
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.focus_mode = Control.FOCUS_ALL
		for st: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var f := UiTheme.box(Color.TRANSPARENT, 10, Color.WHITE, 3, 0)
		f.draw_center = false
		b.add_theme_stylebox_override("focus", f)
		b.pressed.connect(_on_cell.bind(i))
		b.focus_entered.connect(_on_cell_focus.bind(i))
		overlay.add_child(b)
		overlay.move_child(b, catcher.get_index() + 1)
		proxies.append(b)
	_show_opened_ui()

func _on_cell(i: int) -> void:
	if state != State.OPENED: return
	if i == stage.arena_cell(): _say_arena()
	else: select(i)

func _on_cell_focus(i: int) -> void:
	if state == State.OPENED and i < stage.weapon_ids.size(): select(i)

func _say_arena() -> void:
	var p := pack()
	if p == null: return
	caption.text = tr("Arena: %s") % tr(str(Content.get_map(p.arena_id).get("name", p.arena_id)))

## Puts rack weapon `i` in the wobbler's hand (the preview; -1 puts it away).
func select(i: int) -> void:
	if state != State.OPENED and i >= 0: return
	if i == stage.selected: return
	stage.select(i)
	if i >= 0: _sfx("pickup", 0.5)
	_caption()

func _show_opened_ui() -> void:
	var on := state != State.IDLE
	var live := state == State.OPENED
	if catcher == null: return
	catcher.visible = on
	pill.visible = state == State.IDLE and pack() != null
	mouse_filter = Control.MOUSE_FILTER_STOP if state == State.IDLE and shown else Control.MOUSE_FILTER_IGNORE
	for c: Control in [header, caption, back_b, bar, site_b]:
		if c == null: continue
		c.visible = on
		c.modulate.a = ui_k
	for b: Button in [prev_b, next_b, test_b, unlock_b, site_b]:
		if b: b.disabled = not live
	if back_b: back_b.disabled = state == State.CLOSING
	for b: Button in proxies:
		b.focus_mode = Control.FOCUS_ALL if live else Control.FOCUS_NONE
		b.disabled = not live
		if not live and b.has_focus(): b.release_focus()

func _set_ui_k(v: float) -> void:
	ui_k = v
	for c: Control in [header, caption, back_b, bar, site_b]:
		if c: c.modulate.a = v
	ui_changed.emit(v)

# ---------------------------------------------------------------- layout

## Sizes the stage's render target for this control (device pixels, capped) and lays the overlay out.
func _fit() -> void:
	if stage == null or not is_inside_tree(): return
	var k := 1.0
	var vp := get_viewport()
	if vp != null: k = clampf(vp.get_final_transform().get_scale().x, 1.0, 2.0)
	var px := size * k
	if px.x * px.y > MAX_PIXELS: px *= sqrt(MAX_PIXELS / (px.x * px.y))
	_pixel_scale = px.x / maxf(1.0, size.x)
	stage.size = Vector2i(maxi(64, int(px.x)), maxi(64, int(px.y)))
	_layout()

## The owner's numbers: the safe area (the idle scene is framed inside it) and the touch-size factor.
func set_frame(safe: Rect2, u: float) -> void:
	safe_rect = safe
	unit = u
	_layout()

func _norm(r: Rect2) -> Rect2:
	var s := Vector2(maxf(1.0, size.x), maxf(1.0, size.y))
	return Rect2((r.position - global_position) / s, r.size / s)

func _layout() -> void:
	if stage == null or back_b == null or not is_inside_tree(): return
	var s := safe_rect if safe_rect.size.x > 1.0 else Rect2(Vector2.ZERO, size)
	var t := TOUCH * unit
	var fs := int(round(20.0 * minf(unit, 2.0)))
	var portrait := size.y > size.x
	stage.compact = portrait
	pill.font_px = 21.0 * minf(unit, 2.0)
	pill.fit_width(s.size.x * 0.5)          # a long name (CONSTRUCTION, 建造 · 新) steps the font down instead of running off the stage
	pill.min_h = t
	pill.size = pill.get_combined_minimum_size()
	site_b.max_font = 30.0 * minf(unit, 2.0)
	site_b.custom_minimum_size = Vector2(maxf(210.0 * minf(unit, 2.0), t * 3.4), t)
	site_b.size = site_b.custom_minimum_size
	site_b.position = Vector2(s.end.x - site_b.size.x, s.position.y)
	_name_l.add_theme_font_size_override("font_size", int(round(26.0 * minf(unit, 1.8))))
	_sub_l.add_theme_font_size_override("font_size", int(round(18.0 * minf(unit, 1.8))))
	_lock.custom_minimum_size = Vector2(22, 27) * minf(unit, 1.8)
	caption.add_theme_font_size_override("font_size", int(round(22.0 * minf(unit, 2.0))))
	(owned_chip.get_child(0).get_node("Text") as Label).add_theme_font_size_override("font_size", fs)
	owned_chip.custom_minimum_size = Vector2(0, t * 0.8)
	back_b.add_theme_font_size_override("font_size", fs)
	back_b.custom_minimum_size = Vector2(maxf(124.0 * unit, t), t)
	# the bar: one row beside Back when it fits (first with the long swap labels, then with arrows only), else its own row
	var room := s.size.x - back_b.custom_minimum_size.x - GAP * 2.0
	var two_rows := false
	var fs_bar := fs
	for attempt in 3:
		var long := attempt == 0
		var f2 := fs if attempt < 2 else maxi(UiTheme.MIN_FONT + 2, fs - 3)
		fs_bar = f2
		prev_b.text = (tr("‹ SWAP PACK") if long else "‹")
		next_b.text = (tr("SWAP PACK ›") if long else "›")
		prev_b.tooltip_text = tr("Previous pack")
		next_b.tooltip_text = tr("Next pack")
		prev_b.set("accessibility_name", prev_b.tooltip_text)
		next_b.set("accessibility_name", next_b.tooltip_text)
		for b: Button in [prev_b, next_b, test_b, unlock_b]:
			b.add_theme_font_size_override("font_size", f2)
			b.custom_minimum_size = Vector2(t * (1.1 if b == prev_b or b == next_b else 1.0), t)
		bar.size = Vector2.ZERO
		two_rows = bar.get_combined_minimum_size().x > room
		if not two_rows: break
	while two_rows and bar.get_combined_minimum_size().x > s.size.x and fs_bar > FitText.MIN_SIZE:   # the longest words (fr / es): every bar font steps down until one row fits
		fs_bar -= 1
		for b: Button in [prev_b, next_b, test_b, unlock_b]: b.add_theme_font_size_override("font_size", fs_bar)
		bar.size = Vector2.ZERO
	back_b.size = back_b.custom_minimum_size
	back_b.position = Vector2(s.position.x, s.end.y - t)
	var bw := minf(bar.get_combined_minimum_size().x, s.size.x)
	bar.size = Vector2(bw, t)
	var bar_y := s.end.y - t
	if two_rows: bar_y -= t + GAP
	bar.position = Vector2(s.end.x - bw, bar_y)
	var h_room := site_b.position.x - GAP - s.position.x          # the header sits left of the sign: the pack name and its subtitle step down to fit
	var nm_fs := int(round(26.0 * minf(unit, 1.8)))
	var sb_fs := int(round(18.0 * minf(unit, 1.8)))
	header.size = Vector2.ZERO
	while header.get_combined_minimum_size().x > h_room and sb_fs > FitText.MIN_SIZE:
		sb_fs -= 1
		nm_fs = maxi(FitText.MIN_SIZE + 2, nm_fs - 1)
		_name_l.add_theme_font_size_override("font_size", nm_fs)
		_sub_l.add_theme_font_size_override("font_size", sb_fs)
		header.size = Vector2.ZERO
	header.size = header.get_combined_minimum_size()
	var hx := s.position.x + (s.size.x - header.size.x) * 0.5
	header.position = Vector2(minf(hx, site_b.position.x - GAP - header.size.x), s.position.y)   # (the sign has the top right)
	caption.size = Vector2(s.size.x, caption.get_combined_minimum_size().y)
	caption.position = Vector2(s.position.x, bar_y - GAP * 0.5 - caption.size.y)
	var top := header.position.y + header.size.y + GAP
	var open := Rect2(s.position.x, top, s.size.x, maxf(40.0, caption.position.y - GAP * 0.5 - top))
	stage.open_rect = _norm(open)
	stage.idle_rect = _norm(Rect2(s.position + global_position, s.size))
	stage.apply_pose()
	_place()

## The pill under the container and the rack proxies follow the 3D scene.
func _place() -> void:
	if stage == null or pill == null: return
	if pill.visible:
		var a := stage.project(stage.crate_pos() + Vector3(0, 0.0, ShowcaseStage.BOX.z * 0.5)) * size
		var bob := sin(_t * 2.0) * 2.0 * unit
		var c := a + Vector2(0, 16.0 * unit + pill.size.y * 0.5 + bob)
		var s := safe_rect if safe_rect.size.x > 1.0 else Rect2(Vector2.ZERO, size)
		var pos := c - pill.size * 0.5
		pos.x = clampf(pos.x, s.position.x, maxf(s.position.x, s.end.x - pill.size.x))
		pill.position = pos
		overlay.queue_redraw()
	if state != State.IDLE:
		var t := TOUCH * unit
		for i in proxies.size():
			var b := proxies[i]
			if not b.visible: continue
			var r := stage.cell_rect(i)
			var px := Rect2(r.position * size, r.size * size).grow(-3.0)
			var c := px.get_center()
			var sz := Vector2(maxf(px.size.x, minf(t, px.size.x + 6.0)), maxf(px.size.y, minf(t, px.size.y + 6.0)))
			b.size = sz
			b.position = c - sz * 0.5

## The rod the pill hangs on.
func _draw_tag_line() -> void:
	if pill == null or not pill.visible or stage == null: return
	var a := stage.project(stage.crate_pos() + Vector3(0, 0.0, ShowcaseStage.BOX.z * 0.5)) * size
	var b := pill.position + Vector2(pill.size.x * 0.5, 3.0)
	overlay.draw_line(a, b, Color(ConstructionStyle.BLACK, 0.9), 3.0 * unit, true)

## The screen rect (global canvas px) of rack cell `i`: what a finger has to hit.
func cell_screen_rect(i: int) -> Rect2:
	var r := stage.cell_rect(i)
	return Rect2(global_position + r.position * size, r.size * size)

## The screen rect (global canvas px) of the whole container.
func container_screen_rect() -> Rect2:
	var r := stage.screen_rect(ShowcaseStage.box_aabb())
	return Rect2(global_position + r.position * size, r.size * size)

# ---------------------------------------------------------------- input

func _uv(global_pos: Vector2) -> Vector2:
	return (global_pos - global_position) / Vector2(maxf(1.0, size.x), maxf(1.0, size.y))

## A tap on the idle stage (the owner forwards it): opens when it lands on the container.
func tap_at(global_pos: Vector2) -> bool:
	if state != State.IDLE or pack() == null or not shown: return false
	if stage.pick(_uv(global_pos)).get("kind", "") != "container": return false
	return open()

## A tap on the idle stage (this control is the layer under the title's controls): opens when it lands on the container.
func _on_stage_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if tap_at((e as InputEventMouseButton).global_position): accept_event()

func _on_catcher_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT): return
	catcher.accept_event()
	if state != State.OPENED: return                 # mid-animation taps are dropped here, safely
	var hit := stage.pick(_uv((e as InputEventMouseButton).global_position))
	match str(hit.get("kind", "")):
		"weapon": select(int(hit["index"]))
		"arena": _say_arena()

func is_open() -> bool:
	return state != State.IDLE

# ---------------------------------------------------------------- the state machine

func _set_state(s: int) -> void:
	state = s
	_show_opened_ui()
	state_changed.emit(s)

func _new_tween() -> Tween:
	if _tw and _tw.is_valid(): _tw.kill()
	_tw = create_tween()
	_tw.set_speed_scale(maxf(0.01, speed))
	return _tw

## IDLE (or a CLOSING that is still running) -> OPENING -> OPENED. false = ignored in this state.
func open() -> bool:
	if pack() == null or not shown: return false
	if state != State.IDLE and state != State.CLOSING: return false
	_queued_back = false
	_set_state(State.OPENING)
	_layout()
	var fell := stage.lower < 0.9
	var tw := _new_tween()
	tw.tween_property(self, "ui_k", 1.0, 0.3 * (1.0 - ui_k))
	tw.parallel().tween_property(stage, "cam_k", 1.0, 0.65 * (1.0 - stage.cam_k)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(stage, "hoist", 0.0, 0.3 * stage.hoist)
	tw.parallel().tween_property(stage, "lower", 1.0, 0.7 * (1.0 - stage.lower)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if fell: tw.tween_callback(_thud)
	tw.tween_property(stage, "doors", 1.0, 0.6 * (1.0 - stage.doors)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_on_opened)
	if _pc(): back_b.grab_focus.call_deferred()
	return true

func _on_opened() -> void:
	stage.doors = 1.0; stage.lower = 1.0; stage.cam_k = 1.0; stage.hoist = 0.0
	_set_state(State.OPENED)
	_caption()
	if _queued_back:
		_queued_back = false
		back()

## Back (the button, Escape / controller B, Android back): OPENING / OPENED -> CLOSING -> IDLE. A back during a swap
## is remembered and runs when the new container has landed. true = the showcase used the back.
func back() -> bool:
	match state:
		State.IDLE: return false
		State.CLOSING: return true
		State.SWAPPING:
			_queued_back = true
			return true
	stage.select(-1)
	_set_state(State.CLOSING)
	var tw := _new_tween()
	tw.tween_property(stage, "doors", 0.0, 0.32 * stage.doors).set_trans(Tween.TRANS_SINE)
	tw.tween_property(stage, "lower", 0.0, 0.6 * stage.lower).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(stage, "hoist", 0.0, 0.3 * stage.hoist)
	tw.parallel().tween_property(stage, "cam_k", 0.0, 0.6 * stage.cam_k).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(self, "ui_k", 0.0, 0.45 * ui_k)
	tw.tween_callback(_on_closed)
	return true

func _on_closed() -> void:
	stage.doors = 0.0; stage.lower = 0.0; stage.cam_k = 0.0; stage.hoist = 0.0
	ui_k = 0.0
	_set_state(State.IDLE)
	if _pc() and shown: pill.grab_focus.call_deferred()

## OPENED -> SWAPPING -> OPENED on the pack `dir` steps on (wraps). false = ignored (one pack, or not OPENED).
func swap(dir: int) -> bool:
	if state != State.OPENED or packs.size() < 2 or dir == 0: return false
	stage.select(-1)
	_set_state(State.SWAPPING)
	var tw := _new_tween()
	tw.tween_property(stage, "doors", 0.0, 0.28).set_trans(Tween.TRANS_SINE)
	tw.tween_property(stage, "hoist", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_swap_to.bind(posmod(index + dir, packs.size())))
	tw.tween_property(stage, "hoist", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_thud)
	tw.tween_property(stage, "doors", 1.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_on_opened)
	return true

func _swap_to(i: int) -> void:
	index = i
	stage.set_pack(pack())
	refresh()

func _thud() -> void:
	thuds += 1
	stage.thud()
	_sfx("land", 0.9)
	_sfx("clink", 0.35)

## Straight to a resting state without animation (screenshots, tests, the owner leaving the title).
func snap(opened: bool) -> void:
	if _tw and _tw.is_valid(): _tw.kill()
	_queued_back = false
	var k := 1.0 if opened and pack() != null else 0.0
	stage.doors = k; stage.lower = k; stage.cam_k = k; stage.hoist = 0.0
	if k == 0.0: stage.select(-1)
	ui_k = k
	_set_state(State.OPENED if k == 1.0 else State.IDLE)
	_layout()

func _sfx(n: String, vol: float) -> void:
	var sfx := get_node_or_null("/root/Sfx")
	if sfx and stage != null and ShowcaseStage.renders(): sfx.call("play", n, vol)

func _pc() -> bool:
	var tier := get_node_or_null("/root/Tier")
	return tier != null and tier.is_pc()

# ---------------------------------------------------------------- per frame

## Shown / hidden by the owner (the wizard, the Walldrobe and the online tab replace the title home).
func set_shown(on: bool) -> void:
	shown = on
	if not on and state != State.IDLE: snap(false)
	visible = on and pack() != null
	overlay.visible = visible
	_sync_active()

func _sync_active() -> void:
	if stage == null: return
	var on := shown and pack() != null and is_visible_in_tree() and not (covered.is_valid() and bool(covered.call()))
	if on != stage.active: stage.set_active(on)

func _process(dt: float) -> void:
	_t += dt
	_sync_active()
	if not stage.active: return
	_place()
