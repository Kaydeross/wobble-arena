extends SceneTree
## Touch-layer regression test (headless): a finger release that never arrives, an iOS finger index reused for a new
## role without a release, focus loss / interrupted touches, and the orphan sweep must never leave an action held in
## the shared InputState (the on-device "FIRE stays held after the finger lifts" bug). Scripted
## InputEventScreenTouch events drive a real TouchControls added to the root. Also checks the performance readout's
## held-actions line, which makes such a stuck control visible on device.
##   godot --headless --path godot --script res://tests/touch_test.gd -- --no-save   (npm run test:godot-touch)

var fails := 0
var tc: Node            ## the TouchControls under test (loaded at run time: a SceneTree script is parsed before the
var st                    ## autoloads exist, so a parse-time reference to scripts that use Settings would fail)

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var settings: Node = root.get_node("Settings")
	settings.set_value("touch_mode", "on")
	tc = load("res://input/touch_controls.gd").new()
	st = load("res://input/input_state.gd").new()
	tc.state = st
	root.add_child(tc)
	tc.visible = true
	var vs := root.get_visible_rect().size
	var fire: Vector2 = tc.button_rect(tc.button("fire"))[0]
	var jump: Vector2 = tc.button_rect(tc.button("jump"))[0]
	var melee: Vector2 = tc.button_rect(tc.button("melee"))[0]
	var look := Vector2(vs.x * 0.62, vs.y * 0.38)
	check(tc.visible and not tc.button("fire").is_empty(), "touch layer built (viewport %s, FIRE at %s)" % [vs, fire])

	# a. a release that never arrives: FIRE stays down; a second finger presses and releases FIRE, which must clear it
	_reset()
	_press(0, fire)
	check(st.is_held("fire"), "a: first finger holds FIRE")
	_press(1, fire)              # no release for finger 0: the second press must take the button over
	_release(1, fire)
	check(not st.is_held("fire"), "a: releasing the second finger clears the stuck FIRE")

	# b. iOS reuses a finger index: the same index goes down on the look area without a release
	_reset()
	_press(0, fire)
	check(st.is_held("fire"), "b: FIRE held before the index is reused")
	_press(0, look)              # same index 0, new role, no release for FIRE
	check(not st.is_held("fire"), "b: reusing the finger releases what it held (FIRE)")
	check(tc.look_held(), "b: the reused finger now looks")
	_release(0, look)
	check(not tc.look_held(), "b: look released")
	check(not st.is_held("fire"), "b: nothing held after the reused finger is released")

	# c. focus loss and interrupted touches: the OS takes the touch away (Control Centre, banner, cancel)
	_reset()
	_press(0, fire)
	tc.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not st.is_held("fire"), "c: focus out releases FIRE")
	_reset()
	_press(0, fire)
	tc.notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not st.is_held("fire"), "c: window focus out releases FIRE")
	_reset()
	_press(0, fire)
	tc.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	check(not st.is_held("fire"), "c: app pause releases FIRE")
	_reset()
	_press(0, fire)
	_send(_event(0, fire, false, true))
	check(not st.is_held("fire"), "c: a cancelled touch releases FIRE")
	_reset()
	_press(0, melee)
	_send(_event(0, melee, false, true))
	check(not st.peek("shove"), "c: a cancelled MELEE does not emit a shove tap")

	# d. orphan sweep: a held button whose touch entry is gone is released on the next frame
	_reset()
	_press(0, fire)
	tc._touch.erase(0)   # the finger record vanished (a platform-desynced touch) but FIRE is still marked down
	check(st.is_held("fire"), "d: orphaned FIRE is still held before the sweep")
	tc._process(0.016)
	check(not st.is_held("fire"), "d: _process releases a held button with no finger on it")
	_reset()
	_press(0, melee)
	tc._touch.erase(0)
	tc._process(0.016)
	check(not st.peek("shove"), "d: an orphaned MELEE is dropped, not shoved")

	# release_all keeps releasing everything (pause button, leaving the match)
	_reset()
	_press(0, fire)
	tc.release_all()
	check(not st.is_held("fire"), "release_all releases FIRE")

	# the device readout: the actions held right now per source, so a stuck touch control is visible on device
	_reset()
	_press(0, fire)
	_press(1, jump)
	check(st.held_report() == "touch fire+jump", "held report: touch fire+jump (%s)" % st.held_report())
	st.hold("key", "sprint", true)
	check(st.held_report() == "key sprint | touch fire+jump", "held report adds a source (%s)" % st.held_report())
	st.hold("key", "sprint", false)
	check(st.held_report() == "touch fire+jump", "held report omits empty sources (%s)" % st.held_report())
	var row := {"fps": 60.0, "frame_ms_avg": 16.7, "frame_ms_p95": 17.2, "cpu_ms": 4.1, "gpu_ms": 6.2,
		"draws": 612, "objects": 1234, "tier": "MID", "thermal": "n/a", "mem_mb": 310.0}
	var ov_script := load("res://ui/perf_overlay.gd") as GDScript
	check(ov_script.format(row, "", "held: touch fire").ends_with("\nheld: touch fire"), "perf readout appends the held line")
	check(not ov_script.format(row).contains("held:"), "perf readout is unchanged without a held line")
	# the overlay finds the running match's input state and reports it
	var pi = load("res://input/player_input.gd").new()
	pi.state = st
	root.add_child(pi)
	pi.set_process(false)          # a later frame must not poll real keys into the touched state
	var ov = ov_script.new()
	root.add_child(ov)
	check(ov.held_line() == "held: touch fire+jump", "perf readout finds the match input state (%s)" % ov.held_line())
	_release(0, fire)
	_release(1, jump)
	check(ov.held_line() == "held: none", "perf readout shows no held actions after release")

	print("TOUCH ok" if fails == 0 else "TOUCH failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

# ---------------- scripted touches ----------------

func _event(i: int, p: Vector2, pressed: bool, canceled := false) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = i
	e.position = p
	e.pressed = pressed
	e.canceled = canceled
	return e

func _send(e: InputEventScreenTouch) -> void:
	tc._input(e)

func _press(i: int, p: Vector2) -> void:
	_send(_event(i, p, true))

func _release(i: int, p: Vector2) -> void:
	_send(_event(i, p, false))

func _reset() -> void:
	tc.release_all()
	st.clear()
