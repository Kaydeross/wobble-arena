extends SceneTree
## Touch-layout test (headless): the player-movable on-screen buttons + the tablet default (godot/input/touch_controls.gd,
## godot/ui/touch_layout_editor.gd). Run by tools/test-touch-layout.js (npm run test:godot-touch-layout; that one line is
## not in package.json yet). Checks:
##   1. Settings `touch_layout` "{}" keeps the stock phone layout exactly (every button, every supported phone size).
##   2. Offsets move button_rect; a per-button entry only moves that button.
##   3. Wild offsets are clamped so the whole button circle stays inside the safe area, at 667x375, 812x375, 393x852,
##      1024x768 and 1366x1024 canvas sizes, right- and left-handed, at the largest button scale.
##   4. Left-handed mode mirrors the default layout and applies the same screen-space offset (documented behaviour).
##   5. A tablet-class canvas gets the roomier TABLET_BUTTONS default (bigger edge gaps, same sizes, still apart and
##      inside the safe area); phone canvases never do.
##   6. Malformed / partial JSON falls back to the default (per button, never a crash), also through Settings.
##   7. The editor builds from Settings > Controls > Move buttons, mutes gameplay touches, drags a button (mouse path),
##      writes the setting live, reverts on Back, keeps on Save, and its action bar stays inside the screen in portrait
##      and landscape.
##   godot --headless --path godot --script res://tests/touch_layout_test.gd -- --no-save

## Window size in points + safe-area insets in points, like ui_layout_test.gd / hud_test.gd.
const WINS := [
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(812, 375), [44.0, 0.0, 44.0, 21.0]],
	[Vector2(393, 852), [0.0, 47.0, 0.0, 34.0]],
	[Vector2(1024, 768), [0.0, 20.0, 0.0, 0.0]],
	[Vector2(1366, 1024), [0.0, 24.0, 0.0, 20.0]],
]
## Phones: the stock layout must stay pixel-identical. The last two are tablets.
const PHONE_WINS := 3

var fails := 0
var TC: GDScript          ## loaded in _run: a --script SceneTree is parsed before the autoloads exist, so a
var TE: GDScript          ## parse-time class_name reference to a script that uses Settings would fail (see touch_test.gd)
var SS: GDScript
var st: Node              ## the Settings autoload

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	TC = load("res://input/touch_controls.gd")
	TE = load("res://ui/touch_layout_editor.gd")
	SS = load("res://ui/settings_screen.gd")
	st = root.get_node("Settings")
	st.set_value("touch_mode", "on")
	st.set_value("touch_lefty", false)
	st.set_value("touch_scale", 1.0)
	st.set_value("touch_layout", "{}")
	_default_unchanged()
	_offsets()
	_clamp()
	_lefty()
	_tablet()
	_invalid()
	await _invalid_through_settings()
	await _editor()
	print("TOUCHLAYOUT ok" if fails == 0 else "TOUCHLAYOUT failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

# ---------------- geometry helpers ----------------

## [canvas size, safe-area insets in canvas px, canvas px per pt] for a window in points.
func _geom(win: Vector2, ins_pt: Array) -> Array:
	var vs: Vector2 = UiScale.canvas_size(win, "normal", true)
	var k: float = vs.x / win.x
	var ins: Array = ins_pt.map(func(v: float) -> float: return v * k)
	return [vs, ins, k]

## The pre-change phone formula (button size / distance from the thumb-side edge / distance from the bottom, mirrored
## when left-handed): the reference the "{}" layout must reproduce on phones.
func _stock(b: Array, vs: Vector2, ins: Array, lefty_on: bool) -> Array:
	var u: float = TC.UNIT
	var sz: float = float(b[3]) * u
	var x: float = float(b[4]) * u
	var y: float = float(b[5]) * u
	var cy: float = vs.y - float(ins[3]) - y - sz / 2.0
	var cx: float = (float(ins[0]) + x + sz / 2.0) if lefty_on else (vs.x - float(ins[2]) - x - sz / 2.0)
	return [Vector2(cx, cy), sz / 2.0]

func _same(a: Array, b: Array) -> bool:
	return (a[0] as Vector2).distance_to(b[0] as Vector2) < 0.05 and absf(float(a[1]) - float(b[1])) < 0.02

func _circle(r: Array) -> Rect2:
	var rad: float = r[1]
	return Rect2((r[0] as Vector2) - Vector2(rad, rad), Vector2(rad, rad) * 2.0)

func _inside_safe(r: Array, vs: Vector2, ins: Array) -> bool:
	return TC.safe_rect(vs, ins).grow(0.01).encloses(_circle(r))

func _size_label(win: Vector2) -> String:
	return "%dx%d" % [int(win.x), int(win.y)]

# ---------------- 1. "{}" keeps the stock phone layout ----------------

func _default_unchanged() -> void:
	for wi in WINS.size():
		var c: Array = WINS[wi]
		var win: Vector2 = c[0]
		var g := _geom(win, c[1])
		var vs: Vector2 = g[0]
		var ins: Array = g[1]
		var tablet: bool = TC.is_tablet(vs)
		if wi < PHONE_WINS:
			check(not tablet, "%s is a phone canvas" % _size_label(win))
			for b: Array in TC.BUTTONS:
				var got: Array = TC.rect_in(b, vs, ins, false, 1.0, {}, tablet)
				check(_same(got, _stock(b, vs, ins, false)), "%s %s stock layout with \"{}\" (got %s, want %s)"
					% [_size_label(win), b[0], got[0], _stock(b, vs, ins, false)[0]])
				check(_inside_safe(got, vs, ins), "%s %s stock layout inside the safe area" % [_size_label(win), b[0]])
		else:
			check(tablet, "%s is a tablet canvas" % _size_label(win))
	check(TC.layout_text({}) == "{}", "an empty layout serialises to \"{}\"")
	check(TC.parse_layout("{}").is_empty() and TC.parse_layout("").is_empty(), "\"{}\" and \"\" parse to the default")

# ---------------- 2. offsets move the buttons ----------------

func _offsets() -> void:
	var win := Vector2(812, 375)
	var g := _geom(win, WINS[1][1])
	var vs: Vector2 = g[0]
	var ins: Array = g[1]
	var layout := {"fire": Vector2(-60, -40), "jump": Vector2(20, 10)}
	for b: Array in TC.BUTTONS:
		var base: Array = TC.rect_in(b, vs, ins, false, 1.0, {}, false)
		var moved: Array = TC.rect_in(b, vs, ins, false, 1.0, layout, false)
		var want: Vector2 = layout.get(str(b[0]), Vector2.ZERO)
		check((moved[0] - base[0]).distance_to(want) < 0.01, "%s offset applied exactly (moved %s)"
			% [b[0], moved[0] - base[0]])
	for id: String in ["melee", "context"]:
		var base2: Array = TC.rect_in(TC.default_button(id, false), vs, ins, false, 1.0, {}, false)
		var moved2: Array = TC.rect_in(TC.default_button(id, false), vs, ins, false, 1.0, layout, false)
		check(base2[0].distance_to(moved2[0]) < 0.01, "%s without an entry does not move" % id)
	var parsed: Dictionary = TC.parse_layout(TC.layout_text(layout))
	check(parsed.size() == 2 and (parsed["fire"] as Vector2).is_equal_approx(Vector2(-60, -40)),
		"layout_text -> parse_layout round trip (%s)" % parsed)

# ---------------- 3. clamping ----------------

func _clamp() -> void:
	var wild := {}
	var wild2 := {}
	for id: String in TC.LAYOUT_IDS:
		wild[id] = Vector2(9999, 9999)
		wild2[id] = Vector2(-9999, -9999)
	for c: Array in WINS:
		var win: Vector2 = c[0]
		var g := _geom(win, c[1])
		var vs: Vector2 = g[0]
		var ins: Array = g[1]
		var tablet: bool = TC.is_tablet(vs)
		for lefty_on in [false, true]:
			for b: Array in TC.BUTTONS:
				var r1: Array = TC.rect_in(b, vs, ins, lefty_on, 1.4, wild, tablet)
				var r2: Array = TC.rect_in(b, vs, ins, lefty_on, 1.4, wild2, tablet)
				check(_inside_safe(r1, vs, ins), "%s %s %s far offset clamped inside the safe area (got %s)"
					% [_size_label(win), "lefty" if lefty_on else "right", b[0], r1[0]])
				check(_inside_safe(r2, vs, ins), "%s %s %s far negative offset clamped inside the safe area (got %s)"
					% [_size_label(win), "lefty" if lefty_on else "right", b[0], r2[0]])
	# a layout saved at 1366x1024 still renders inside the safe area of the smallest screen
	var big := _geom(Vector2(1366, 1024), WINS[4][1])
	var saved := {}
	for b: Array in TC.BUTTONS:
		var rr: Array = TC.rect_in(b, big[0], big[1], false, 1.0, wild, true)
		saved[str(b[0])] = (rr[0] as Vector2) - (TC.default_rect(b, big[0], big[1], false, 1.0, true)[0] as Vector2)
	var small := _geom(Vector2(667, 375), WINS[0][1])
	for b: Array in TC.BUTTONS:
		check(_inside_safe(TC.rect_in(b, small[0], small[1], false, 1.0, saved, false), small[0], small[1]),
			"a tablet-saved layout is clamped on the smallest phone %s" % b[0])

# ---------------- 4. left-handed mirror ----------------

func _lefty() -> void:
	var g := _geom(Vector2(812, 375), WINS[1][1])   # symmetric left/right insets: mirror is exact
	var vs: Vector2 = g[0]
	var ins: Array = g[1]
	var layout := {"fire": Vector2(-20, -20), "melee": Vector2(30, 12)}
	for b: Array in TC.BUTTONS:
		var right0: Array = TC.rect_in(b, vs, ins, false, 1.0, {}, false)
		var left0: Array = TC.rect_in(b, vs, ins, true, 1.0, {}, false)
		check(absf((left0[0].x - float(ins[0])) - ((vs.x - float(ins[2])) - right0[0].x)) < 0.01,
			"%s left-handed mirrors the default" % b[0])
		check(absf(left0[0].y - right0[0].y) < 0.01, "%s left-handed keeps the height" % b[0])
		var want: Vector2 = layout.get(str(b[0]), Vector2.ZERO)
		var right1: Array = TC.rect_in(b, vs, ins, false, 1.0, layout, false)
		var left1: Array = TC.rect_in(b, vs, ins, true, 1.0, layout, false)
		check((right1[0] - right0[0]).distance_to(want) < 0.01, "%s right-handed offset is screen space" % b[0])
		check((left1[0] - left0[0]).distance_to(want) < 0.01, "%s left-handed offset is the same screen-space nudge" % b[0])

# ---------------- 5. tablet default ----------------

func _tablet() -> void:
	check(TC.TABLET_MIN_SIDE >= 600.0 and TC.TABLET_MIN_SIDE <= 800.0, "the tablet threshold is documented (%s)" % TC.TABLET_MIN_SIDE)
	check(not TC.is_tablet(Vector2(1108, 512)) and not TC.is_tablet(Vector2(910, 512)),
		"phone canvases are not tablets")
	check(not TC.is_tablet(Vector2(1170, 2537)), "portrait is never a tablet")
	for wi in PHONE_WINS:
		check(not TC.is_tablet(_geom(WINS[wi][0], WINS[wi][1])[0]), "%s is not a tablet" % _size_label(WINS[wi][0]))
	check(TC.TABLET_BUTTONS.size() == TC.BUTTONS.size(), "the tablet table has the same buttons")
	for i in TC.BUTTONS.size():
		check(TC.TABLET_BUTTONS[i][0] == TC.BUTTONS[i][0], "tablet button %d is %s" % [i, TC.BUTTONS[i][0]])
		check(TC.TABLET_BUTTONS[i][3] == TC.BUTTONS[i][3], "tablet %s keeps its size" % TC.BUTTONS[i][0])
	var g := _geom(Vector2(1024, 768), WINS[3][1])
	var vs: Vector2 = g[0]
	var ins: Array = g[1]
	var safe: Rect2 = TC.safe_rect(vs, ins)
	var circles := []
	for b: Array in TC.BUTTONS:
		var phone: Array = TC.rect_in(b, vs, ins, false, 1.0, {}, false)
		var tab: Array = TC.rect_in(b, vs, ins, false, 1.0, {}, true)
		check(not _same(phone, tab), "%s tablet default differs from the phone default" % b[0])
		check(_inside_safe(tab, vs, ins), "%s tablet default inside the safe area" % b[0])
		var phone_gap: float = safe.end.x - (phone[0].x + phone[1])
		var tab_gap: float = safe.end.x - (tab[0].x + tab[1])
		check(tab_gap > phone_gap + 0.5, "%s tablet keeps more room from the edge (%.1f > %.1f)" % [b[0], tab_gap, phone_gap])
		circles.append(tab)
	for i in circles.size():
		for j in range(i + 1, circles.size()):
			var r0: Array = circles[i]
			var r1: Array = circles[j]
			check((r0[0] as Vector2).distance_to(r1[0]) >= float(r0[1]) + float(r1[1]) + 8.0,
				"tablet buttons %d and %d stay apart" % [i, j])
	# 1366x1024 too
	var g2 := _geom(Vector2(1366, 1024), WINS[4][1])
	for b: Array in TC.BUTTONS:
		check(_inside_safe(TC.rect_in(b, g2[0], g2[1], false, 1.0, {}, true), g2[0], g2[1]),
			"%s tablet default inside the safe area at 1366x1024" % b[0])

# ---------------- 6. invalid JSON ----------------

func _invalid() -> void:
	for raw in ["", "{}", "nope", "[1, 2]", "null", "\"fire\"", "42", "{\"fire\": [1]}",
			"{\"fire\": [\"a\", 2]}", "{\"fire\": null}", "{\"nope\": [5, 5]}", null, 12, [], Vector2.ONE]:
		check(TC.parse_layout(raw).is_empty(), "invalid layout %s falls back to the default" % str(raw))
	var partial: Dictionary = TC.parse_layout("{\"fire\": [10, -5], \"jump\": \"left\", \"melee\": [3], \"context\": [1, 2]}")
	check(partial.has("fire") and partial.has("context") and not partial.has("jump") and not partial.has("melee"),
		"partial JSON keeps the good entries only (%s)" % partial)

func _invalid_through_settings() -> void:
	var tc = TC.new()
	root.add_child(tc)
	await process_frame
	tc.visible = true
	var b: Array = tc.button("fire")
	for raw: String in ["{bad json", "", "[]", "{\"fire\": [\"x\", 2]}"]:
		st.set_value("touch_layout", raw)   # Settings.changed -> the touch layer reloads
		var vs: Vector2 = tc.get_viewport_rect().size
		check(_same(tc.button_rect(b), TC.rect_in(b, vs, tc.safe_insets(), tc.lefty, tc.scale_k, {}, TC.is_tablet(vs))),
			"malformed \"%s\" falls back to the default layout in the real control" % raw)
	# the stock layout on the real control matches the old formula (with fake phone insets)
	SafeArea.override = [81.0, 0.0, 81.0, 29.0]
	tc._update_insets()
	var vs2: Vector2 = tc.get_viewport_rect().size
	for bb: Array in TC.BUTTONS:
		check(_same(tc.button_rect(bb), _stock(bb, vs2, tc.safe_insets(), false)),
			"the real control's stock layout with phone insets (%s)" % bb[0])
	check(_same(tc.button_rect(b), _stock(b, vs2, tc.safe_insets(), false)), "button_rect with phone safe-area insets")
	SafeArea.override = []
	tc._update_insets()
	tc.free()

# ---------------- 7. the editor ----------------

func _mouse(ed: Object, p: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = p
	ed._gui_input(e)

func _drag(ed: Object, p: Vector2, to: Vector2) -> void:
	_mouse(ed, p, true)
	var m := InputEventMouseMotion.new()
	m.position = to
	m.button_mask = MOUSE_BUTTON_MASK_LEFT
	ed._gui_input(m)
	_mouse(ed, to, false)

func _editor() -> void:
	var ss = SS.new()
	root.add_child(ss)
	await process_frame
	ss.open_section("controls")
	st.set_value("touch_layout", "{}")
	check(ss.rows.get_node_or_null("Row_TouchLayout") != null, "Controls has a touch-layout row")
	check(ss.ui.has("layout") and ss.ui.has("layout_reset"), "the row has Move buttons and Reset buttons")
	var ed = ss.layout_editor
	check(ed != null and not ed.visible, "the editor exists and starts hidden")
	# a live touch layer behind the editor (a paused match) must go quiet while editing
	var stc = load("res://input/input_state.gd").new()
	var live = TC.new()
	live.state = stc
	root.add_child(live)
	await process_frame
	live.visible = true
	var live_fire: Vector2 = live.button_rect(live.button("fire"))[0]
	ss.ui["layout"].pressed.emit()
	check(ed.visible, "Move buttons opens the editor")
	check(bool(TC.get("suspend")), "gameplay touches are muted while the editor is open")
	check(ed.preview != null and ed.preview.editor_mode and ed.preview.visible, "the editor shows the real touch buttons")
	check(not (ss.get_node("Bg") as Control).visible and not ss.safe.visible,
		"the Settings page is hidden so the editor's dim overlay covers the title / paused match")
	for id: String in TC.LAYOUT_IDS:
		check(not ed.preview.button(id).is_empty(), "the editor can move %s" % id)
		check(_circle(ed.preview.button_rect(ed.preview.button(id))).has_area(), "the editor draws %s" % id)
	# the preview ignores touches completely
	var t := InputEventScreenTouch.new()
	t.index = 0
	t.position = ed.preview.button_rect(ed.preview.button("fire"))[0]
	t.pressed = true
	ed.preview._input(t)
	check(not stc.is_held("fire"), "the editor preview never fires")
	# the real touch layer behind it is muted too
	var t2 := InputEventScreenTouch.new()
	t2.index = 1
	t2.position = live_fire
	t2.pressed = true
	live._input(t2)
	check(not stc.is_held("fire"), "a touch layer behind the editor is muted")
	var t3 := InputEventScreenTouch.new()
	t3.index = 1
	t3.position = live_fire
	t3.pressed = false
	live._input(t3)
	# simulated drag with the mouse path: FIRE 70 px left and 40 px up
	var before: Vector2 = ed.preview.button_rect(ed.preview.button("fire"))[0]
	var live_before: Vector2 = live.button_rect(live.button("fire"))[0]
	_drag(ed, before, before + Vector2(-70, -40))
	var draft: Dictionary = TC.parse_layout(st.get_value("touch_layout"))
	check(draft.has("fire"), "a drag writes the layout to Settings live (%s)" % st.get_value("touch_layout"))
	check((draft.get("fire", Vector2.ZERO) as Vector2).distance_to(Vector2(-70, -40)) < 1.5,
		"the dragged offset is the finger movement (%s)" % draft.get("fire"))
	check((ed.preview.button_rect(ed.preview.button("fire"))[0] - before).distance_to(Vector2(-70, -40)) < 1.5,
		"the button follows the drag")
	check((live.button_rect(live.button("fire"))[0] - live_before).distance_to(Vector2(-70, -40)) < 1.5,
		"a live touch layer follows the editor through Settings.changed")
	# a second drag is clamped at the safe-area edge
	_drag(ed, ed.preview.button_rect(ed.preview.button("fire"))[0], Vector2(-500, -500))
	check(_inside_safe(ed.preview.button_rect(ed.preview.button("fire")), ed.preview.get_viewport_rect().size,
		ed.preview.safe_insets()), "the dragged button stays inside the safe area")
	# the touch path moves a button too (a finger, not the mouse)
	var jp: Vector2 = ed.preview.button_rect(ed.preview.button("jump"))[0]
	var tt := InputEventScreenTouch.new()
	tt.index = 3
	tt.position = jp
	tt.pressed = true
	ed._gui_input(tt)
	var td := InputEventScreenDrag.new()
	td.index = 3
	td.position = jp + Vector2(-40, -30)
	ed._gui_input(td)
	var tu := InputEventScreenTouch.new()
	tu.index = 3
	tu.position = jp + Vector2(-40, -30)
	tu.pressed = false
	ed._gui_input(tu)
	check(TC.parse_layout(st.get_value("touch_layout")).has("jump"), "a touch drag moves a button too")
	# the contextual button can be moved as well (it is only drawn while it applies in a match)
	var cp: Vector2 = ed.preview.button_rect(ed.preview.button("context"))[0]
	_drag(ed, cp, cp + Vector2(-20, -20))
	check(TC.parse_layout(st.get_value("touch_layout")).has("context"), "the context button can be moved too")
	# Back without Save reverts the layout and unmutes the touch layers
	ed.close()
	check(not ed.visible, "Back closes the editor")
	check(str(st.get_value("touch_layout")) == "{}", "Back without Save reverts to the previous layout")
	check(not bool(TC.get("suspend")), "touches are unmuted after Back")
	check((ss.get_node("Bg") as Control).visible and ss.safe.visible, "the Settings page comes back after the editor closes")
	var t4 := InputEventScreenTouch.new()
	t4.index = 2
	t4.position = live_fire
	t4.pressed = true
	live._input(t4)
	check(stc.is_held("fire"), "a live touch layer works again after Back")
	var t5 := InputEventScreenTouch.new()
	t5.index = 2
	t5.position = live_fire
	t5.pressed = false
	live._input(t5)
	# drag + Save keeps it
	ss.ui["layout"].pressed.emit()
	var p2: Vector2 = ed.preview.button_rect(ed.preview.button("fire"))[0]
	_drag(ed, p2, p2 + Vector2(-50, -20))
	ed.save()
	check(not ed.visible, "Save closes the editor")
	var saved := str(st.get_value("touch_layout"))
	check(saved != "{}" and TC.parse_layout(saved).has("fire"), "Save keeps the layout (%s)" % saved)
	check(not bool(TC.get("suspend")), "touches are unmuted after Save")
	# the editor's Reset previews the default; Back still restores the layout from before the editor opened
	ss.ui["layout"].pressed.emit()
	ed.buttons["reset"].pressed.emit()
	check(str(st.get_value("touch_layout")) == "{}", "the editor's Reset previews the default layout")
	ed.close()
	check(str(st.get_value("touch_layout")) == saved, "Back after Reset restores the layout from before the editor opened")
	# Reset buttons (the Settings row) restores the device default at once
	ss.ui["layout_reset"].pressed.emit()
	check(str(st.get_value("touch_layout")) == "{}", "Reset buttons puts the default layout back")
	# the action bar is reachable in landscape and portrait
	ss.ui["layout"].pressed.emit()
	await _editor_bounds(ed, Vector2(812, 375), true)
	await _editor_bounds(ed, Vector2(393, 852), false)
	# the page behind the editor going away (unpause while editing, a menu switch) closes it and unmutes instead of
	# leaving the touch layer dead behind a hidden menu
	var bp: Vector2 = ed.preview.button_rect(ed.preview.button("fire"))[0]
	_drag(ed, bp, bp + Vector2(-30, -10))
	await process_frame
	ss.visible = false
	await process_frame
	check(not ed.visible, "the editor closes when the page behind it is hidden")
	check(not bool(TC.get("suspend")), "touch layers are unmuted when the page behind the editor is hidden")
	check(str(st.get_value("touch_layout")) == "{}", "an unsaved drag is reverted when the page is hidden")
	ss.visible = true
	await process_frame
	ss.ui["layout_reset"].pressed.emit()
	ss.free()
	live.free()

## Resize the root window like a device, then check the editor's action bar is on screen (and 44 pt tall in landscape).
func _editor_bounds(ed: Object, win: Vector2, landscape: bool) -> void:
	var tier: Node = root.get_node("Tier")
	var size0 := root.size
	tier.force_ui_scale = true
	root.size = Vector2i(win)
	tier.apply_ui_scale()
	await process_frame
	ed.apply_safe_area()
	await process_frame
	var vr: Rect2 = ed.get_viewport_rect()
	var pt_k: float = win.x / vr.size.x
	for key: String in ["back", "reset", "save"]:
		var b: Control = ed.buttons[key]
		check(vr.grow(0.5).encloses(Rect2(b.global_position, b.size)), "%s %dx%d %s button inside the screen"
			% ["landscape" if landscape else "portrait", int(win.x), int(win.y), key])
		if landscape:
			check(b.size.y * pt_k >= 44.0 - 0.5, "%s %s button is at least 44 pt (%.1f)" % [_size_label(win), key, b.size.y * pt_k])
	check(bool(ed.visible), "%s %dx%d editor still up after a resize" % ["landscape" if landscape else "portrait", int(win.x), int(win.y)])
	root.size = size0
	tier.force_ui_scale = false
	root.content_scale_factor = 1.0
	await process_frame
	ed.apply_safe_area()
	await process_frame
