extends SceneTree
## Controls profile, Controls screen and the interactive training (run by tools/test-tutorial.js):
##   godot --headless --path godot --script res://tests/tutorial_test.gd -- --no-save
## 1. ControlProfile: the profile per platform (desktop keyboard, a touch device / Touch buttons "On" = touch, a controller
##    press = gamepad and a key / mouse = keyboard live, touch devices stay touch); labels READ from the real bindings:
##    rebind an action and the label, the hint line and the training prompt change.
## 2. The Controls screen shows ONLY the active profile, the Touch | Keyboard | Gamepad switch works, the old run-on keys
##    paragraph is gone, SHOVE and KICK are on the board, Training is there (hidden online).
## 3. The training in the real world, once per profile (keyboard, gamepad, touch): each step advances ONLY on its real input
##    (the wrong input does not), through the same device paths the game uses (key / pad events into PlayerInput, screen
##    touches into TouchControls); a mid-training device switch redoes the prompt; Skip, Exit, Replay; the finish card.
## 4. Nothing is saved: the Save blob is identical afterwards and the only Settings key that changed is seen_tutorial.
## 5. The first-play offer: shown once for a fresh persistent profile (never when the profile is not saved), Skip / Start,
##    remembered; the HUD hint line; no leaked nodes.
## Classes are loaded at run time (a SceneTree script is parsed before the autoloads exist).

var fails := 0
var checks := 0
var CP: GDScript
var TS: GDScript
var TUT: GDScript
var OFFER: GDScript
var HELP: GDScript
var changed_keys := {}

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	if not OS.get_cmdline_user_args().has("--no-save"):
		print("TUTORIAL needs --no-save (it changes Settings)")
		quit(1)
		return
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func frames(n: int) -> void:
	for i in n: await process_frame

func until(cond: Callable, sec: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > sec * 1000.0: return false
		await process_frame
	return true

func _st() -> Node:
	return root.get_node("Settings")

func _run() -> void:
	CP = load("res://input/control_profile.gd")
	TS = load("res://logic/tutorial_steps.gd")
	TUT = load("res://world/tutorial.gd")
	OFFER = load("res://ui/tutorial_offer.gd")
	HELP = load("res://ui/controls_help.gd")
	_st().changed.connect(func(k: String, _v: Variant) -> void: changed_keys[k] = true)
	var nodes0 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var blob0 := JSON.stringify(root.get_node("Save").get_blob())
	_profile()
	await _bindings()
	await _controls_screen()
	changed_keys.clear()
	for p: String in ["keyboard", "gamepad", "touch"]:
		await _training(p)
	await _training_extras()
	check(JSON.stringify(root.get_node("Save").get_blob()) == blob0, "the training never changes the Save (coins, stats, quests, news...)")
	var bad: Array = []
	for k: String in changed_keys:
		if k != "seen_tutorial" and k != "touch_mode": bad.append(k)    # (touch_mode: this test's own "pretend it is a phone")
	check(bad.is_empty(), "the training changes no Setting but seen_tutorial (%s)" % str(bad))
	check(changed_keys.has("seen_tutorial") and bool(_st().get_value("seen_tutorial")), "finishing sets seen_tutorial")
	await _offer()
	await _hints()
	CP.call("reset")
	await frames(4)
	var nodes1 := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("NODES before=%d after=%d orphans=%d" % [nodes0, nodes1, orphans])
	check(nodes1 <= nodes0 + 2 and orphans == 0, "no leaked nodes (%d -> %d, %d orphans)" % [nodes0, nodes1, orphans])
	print("TUTORIAL %s (%d checks)" % ["ok" if fails == 0 else "FAILED (%d)" % fails, checks])
	quit(0 if fails == 0 else 1)

# ---------------- 1. profile ----------------

func _key(code: int, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e

func _pad(btn: int, pressed := true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = pressed
	return e

func _profile() -> void:
	var tier: Node = root.get_node("Tier")
	CP.call("reset")
	check(CP.call("current") == "keyboard", "a desktop starts on keyboard")
	CP.call("note_event", _pad(JOY_BUTTON_A))
	check(CP.call("current") == "gamepad", "a pad button switches to gamepad")
	var small := InputEventJoypadMotion.new()
	small.axis = JOY_AXIS_LEFT_X; small.axis_value = 0.1
	CP.call("note_event", _key(KEY_W))
	check(CP.call("current") == "keyboard", "a key switches back to keyboard")
	CP.call("note_event", small)
	check(CP.call("current") == "keyboard", "stick drift does not switch to gamepad")
	var big := InputEventJoypadMotion.new()
	big.axis = JOY_AXIS_LEFT_X; big.axis_value = 0.9
	CP.call("note_event", big)
	check(CP.call("current") == "gamepad", "a pushed stick switches to gamepad")
	var mb := InputEventMouseButton.new()
	mb.pressed = true; mb.button_index = MOUSE_BUTTON_LEFT
	CP.call("note_event", mb)
	check(CP.call("current") == "keyboard", "a mouse click switches to keyboard")
	# touch devices stay touch whatever else is pressed
	var kind0: int = tier.kind
	tier.kind = tier.Kind.MOBILE
	check(CP.call("current") == "touch", "a phone / tablet (Tier MOBILE) is touch")
	CP.call("note_event", _pad(JOY_BUTTON_A))
	CP.call("note_event", _key(KEY_E))
	check(CP.call("current") == "touch", "touch devices stay touch (a key or pad press does not switch)")
	_st().set_value("touch_mode", "off")
	check(CP.call("current") != "touch", "Touch buttons Off on a phone: not touch")
	_st().set_value("touch_mode", "auto")
	tier.kind = tier.Kind.WEB
	check(CP.call("current") == ("touch" if DisplayServer.is_touchscreen_available() else "keyboard"), "web: touch only when the browser has a touchscreen")
	tier.kind = kind0
	CP.call("reset")
	_st().set_value("touch_mode", "on")
	check(CP.call("current") == "touch", "Touch buttons On: touch")
	_st().set_value("touch_mode", "auto")
	CP.set("force", "gamepad")
	check(CP.call("current") == "gamepad", "force pins a profile")
	CP.call("reset")
	check(CP.call("current") == "keyboard", "reset: back to automatic")

# ---------------- labels come from the real bindings ----------------

func _bindings() -> void:
	var C := CP
	check(C.call("names", "shove", "keyboard") == ["E"] and C.call("names", "kick", "keyboard") == ["F"], "keyboard: SHOVE is E, KICK is F (from the InputMap)")
	check(C.call("name_of", "fire", "keyboard") == "Left mouse", "keyboard: fire is the left mouse button")
	check((C.call("names", "aim", "keyboard") as Array) == ["Right mouse", "Z"], "keyboard: aim is right mouse / Z: %s" % str(C.call("names", "aim", "keyboard")))
	check(C.call("name_of", "jump", "keyboard") == "Space" and C.call("name_of", "pause", "keyboard") == "Esc", "keyboard: Space jumps, Esc pauses")
	check(C.call("move_text", "keyboard") == "W A S D", "keyboard: move text is W A S D (%s)" % C.call("move_text", "keyboard"))
	check(C.call("name_of", "swap", "keyboard") == "Wheel down" and C.call("name_of", "swap_back", "keyboard") == "Wheel up", "keyboard: the wheel cycles weapons")
	check(C.call("emote_text", "keyboard") == "T G H", "keyboard: emote keys T G H")
	check(C.call("name_of", "shove", "gamepad") == "RB" and C.call("name_of", "kick", "gamepad") == "B", "gamepad: SHOVE is RB, KICK is B")
	check(C.call("name_of", "fire", "gamepad") == "RT" and C.call("name_of", "aim", "gamepad") == "LT", "gamepad: RT fires, LT aims")
	check(C.call("name_of", "jump", "gamepad") == "A" and C.call("name_of", "reload", "gamepad") == "X" and C.call("name_of", "swap", "gamepad") == "Y", "gamepad: A jump, X reload, Y next weapon")
	check(C.call("name_of", "dash", "gamepad") == "LB" and C.call("name_of", "pause", "gamepad") == "Start", "gamepad: LB dash, Start pause")
	check(C.call("name_of", "shove", "touch") == "Melee" and C.call("name_of", "kick", "touch") == "Melee" and C.call("name_of", "fire", "touch") == "Fire", "touch: shove / kick are the MELEE button (read from TouchControls.BUTTONS)")
	# rebind: the label, the hint, the prompt and the Controls board follow
	InputMap.action_erase_events("shove")
	InputMap.action_add_event("shove", _key(KEY_G))
	check(C.call("name_of", "shove", "keyboard") == "G", "rebinding SHOVE to G changes its label")
	check("G" in str(C.call("hint_line", "keyboard")), "the hint line follows the rebinding")
	check(TS.call("plain", "shove", "keyboard") == "Press G to shove", "the training prompt follows the rebinding: %s" % TS.call("plain", "shove", "keyboard"))
	var h: Control = HELP.new()
	root.add_child(h)
	h.open()
	await frames(3)
	var caps := _cap_texts(h)
	check(caps.has("G") and not caps.has("E"), "the Controls board follows the rebinding (%s)" % str(caps))
	h.queue_free()
	InputMap.action_erase_events("shove")
	InputMap.action_add_event("shove", _key(KEY_E))
	InputMap.action_add_event("shove", _pad(JOY_BUTTON_RIGHT_SHOULDER))
	var pe: InputEventJoypadButton = null
	for e: InputEvent in InputMap.action_get_events("kick"):
		if e is InputEventJoypadButton: pe = e
	InputMap.action_erase_event("kick", pe)
	InputMap.action_add_event("kick", _pad(JOY_BUTTON_X))
	check(C.call("name_of", "kick", "gamepad") == "X", "rebinding the pad KICK to X changes its label")
	InputMap.action_erase_events("kick")
	var kk := _key(KEY_F)
	InputMap.action_add_event("kick", kk)
	InputMap.action_add_event("kick", _pad(JOY_BUTTON_B))
	check(C.call("name_of", "shove", "keyboard") == "E" and C.call("name_of", "kick", "gamepad") == "B" and C.call("name_of", "kick", "keyboard") == "F", "bindings restored")
	for p: String in ["keyboard", "gamepad", "touch"]:
		for id in range(TS.call("count")):
			var sid: String = TS.call("step", id)["id"]
			var txt: String = TS.call("plain", sid, p)
			check(txt != "" and not "%" in txt, "%s prompt for %s is a full sentence (%s)" % [p, sid, txt])

func _is_cap(n: Node) -> bool:
	return n is Control and n.get("hot") != null and n.get("fs") != null and n.get("text") != null

func _cap_texts(n: Node) -> Array:
	var out: Array = []
	if _is_cap(n): out.append(n.get("text"))
	for c in n.get_children(): out.append_array(_cap_texts(c))
	return out

# ---------------- 2. the Controls screen ----------------

func _visible_pages(h: Control) -> Array:
	var out: Array = []
	for k: String in h.pages:
		if (h.pages[k] as Control).visible: out.append(k)
	return out

func _controls_screen() -> void:
	for p: String in ["keyboard", "gamepad", "touch"]:
		CP.set("force", p)
		var h: Control = HELP.new()
		root.add_child(h)
		h.open()
		await frames(3)
		check(_visible_pages(h) == [p] and h.shown == p, "Controls opens on %s only (%s)" % [p, str(_visible_pages(h))])
		check((h.tabs[p] as Button).button_pressed, "the %s tab is preselected" % p)
		check(h.pic != null and h.pic.is_visible_in_tree(), "%s: the picture / board is shown" % p)
		check(h.training_b.visible and h.training_b.size.y >= 44.0, "%s: Training button is there" % p)
		for q: String in h.tabs:
			check((h.tabs[q] as Button).size.y >= 44.0, "tab %s is at least 44 tall" % q)
		check(not _text_has(h, "WASD move"), "%s: the old run-on keys paragraph is gone" % p)
		if p == "keyboard":
			var caps := _cap_texts(h)
			check(caps.has("E") and caps.has("F") and caps.has("Left mouse") and caps.has("Space") and caps.has("Shift"), "keyboard board: E, F, Left mouse, Space, Shift (%s)" % str(caps))
			var hot := 0
			for n in _all(h):
				if _is_cap(n) and n.get("hot"): hot += 1
			check(hot == 2, "SHOVE and KICK are the two yellow keycaps (%d)" % hot)
			check(_text_has(h, "SHOVE") and _text_has(h, "KICK"), "SHOVE and KICK are named")
		if p == "gamepad":
			var pad: Control = h.pic
			check(pad != null and pad.has_method("words_for") and (pad.call("words_for", "RB") as Array).has("SHOVE") and (pad.call("words_for", "B") as Array).has("KICK"), "controller: RB is SHOVE, B is KICK")
		# the switch
		for q: String in ["touch", "keyboard", "gamepad"]:
			(h.tabs[q] as Button).pressed.emit()
			await frames(1)
			check(_visible_pages(h) == [q], "switch to %s shows only %s (%s)" % [q, q, str(_visible_pages(h))])
		h.can_train = false
		check(not h.training_b.visible, "online: no Training button")
		h.queue_free()
		await frames(2)
	CP.call("reset")

func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children(): out.append_array(_all(c))
	return out

func _text_has(n: Node, s: String) -> bool:
	for x in _all(n):
		if x is Label and s in (x as Label).text: return true
		if x is Button and s in (x as Button).text: return true
	return false

# ---------------- 3. the training ----------------

func _world() -> Node:
	var w: Node = TUT.call("make_world")
	w.auto_run = false
	root.add_child(w)
	await frames(3)
	w.tick(0.016)
	var t: Node = w.get("_tut")
	t.set("cheer_time", 0.05)
	return w

func _step_now(w: Node) -> String:
	return str((w.get("_tut") as Node).call("current_id"))

func _wait_step(w: Node, id: String, sec := 6.0) -> bool:
	return await until(func() -> bool:
		w.tick(0.016)
		return _step_now(w) == id, sec)

func _ev(p: Vector2, idx := 0, pressed := true) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = idx; e.position = p; e.pressed = pressed
	return e

func _center(r: Rect2) -> Vector2:
	return r.position + r.size * 0.5

## Does the real input for step `id` on profile `p`.
func _do(w: Node, id: String, p: String) -> void:
	var inp: Node = w.input
	var st: InputState = inp.state
	var tc: Node = w.touch
	var vs := w.get_viewport().get_visible_rect().size
	match id:
		"move":
			if p == "touch":
				var home: Vector2 = tc.stick_home()
				tc._input(_ev(home))
				var d := InputEventScreenDrag.new()
				d.index = 0; d.position = home + Vector2(60, -60); d.relative = Vector2(60, -60)
				tc._input(d)
			else:
				Input.action_press("move_forward")
		"look":
			if p == "touch":
				var a := Vector2(vs.x * 0.62, vs.y * 0.3)
				tc._input(_ev(a, 1))
				for i in 12:
					var d := InputEventScreenDrag.new()
					d.index = 1; d.position = a + Vector2(30 * (i + 1), 0); d.relative = Vector2(30, 0)
					tc._input(d)
				tc._input(_ev(a + Vector2(360, 0), 1, false))
			else:
				for i in 4: st.add_look(0.5, 0.05)   # (mouse motion needs a captured mouse; a pad's right stick needs a real pad)
		"jump":
			if p == "touch":
				tc._input(_ev(_btn(tc, "jump"), 2))
			else:
				Input.action_press("jump")
		"fire":
			if p == "touch": tc._input(_ev(_btn(tc, "fire"), 3))
			else: st.hold("script", "fire", true)   # (the mouse only counts once it is captured; "script" is the source nothing else clears)
		"aim":
			if p == "touch":
				var a := Vector2(vs.x * 0.62, vs.y * 0.3)
				for i in 2:
					tc._input(_ev(a, 4)); tc._input(_ev(a, 4, false))
			else: st.hold("script", "aim", true)
		"reload": _tap(w, p, "reload", KEY_R, JOY_BUTTON_X, "context")
		"shove": _tap(w, p, "shove", KEY_E, JOY_BUTTON_RIGHT_SHOULDER, "melee")
		"kick":
			if p == "touch":
				tc._input(_ev(_btn(tc, "melee"), 5))
				tc._process(0.4)
				tc._input(_ev(_btn(tc, "melee"), 5, false))
			else: _tap(w, p, "kick", KEY_F, JOY_BUTTON_B, "")
		"weapon":
			if p == "touch": tc._input(_ev(_center(tc.hotbar_slot_rect(1)), 6)); tc._input(_ev(_center(tc.hotbar_slot_rect(1)), 6, false))
			elif p == "gamepad": inp._unhandled_input(_pad(JOY_BUTTON_Y))
			else: inp._unhandled_input(_key(KEY_2))
		"dash": _tap(w, p, "dash", KEY_V, JOY_BUTTON_LEFT_SHOULDER, "context")
		"spatula":
			if p == "touch": tc._input(_ev(_center(tc.hotbar_slot_rect(3)), 7)); tc._input(_ev(_center(tc.hotbar_slot_rect(3)), 7, false))
			elif p == "gamepad": inp._unhandled_input(_pad(JOY_BUTTON_Y))
			else: inp._unhandled_input(_key(KEY_2))
		"pause":
			if p == "touch":
				var r: Rect2 = tc.pause_rect()
				tc._input(_ev(_center(r), 8)); tc._input(_ev(_center(r), 8, false))
			elif p == "gamepad": inp._unhandled_input(_pad(JOY_BUTTON_START))
			else: inp._unhandled_input(_key(KEY_ESCAPE))

func _btn(tc: Node, id: String) -> Vector2:
	return tc.button_rect(tc.button(id))[0]

func _tap(w: Node, p: String, action: String, key: int, pad: int, touch_btn: String) -> void:
	var tc: Node = w.touch
	if p == "touch":
		tc._refresh_context()
		var pos := _btn(tc, touch_btn)
		tc._input(_ev(pos, 9))
		tc._input(_ev(pos, 9, false))
	elif p == "gamepad": w.input._unhandled_input(_pad(pad))
	else: w.input._unhandled_input(_key(key))

## Let go of everything the scripted player holds.
func _release(w: Node) -> void:
	for a: String in ["move_forward", "jump", "fire", "aim"]: Input.action_release(a)
	var st: InputState = w.input.state
	for s: String in ["key", "pad", "touch", "script"]:
		for a: String in ["fire", "aim", "jump"]: st.hold(s, a, false)
	st.aim_toggle = false
	if w.touch != null: w.touch.release_all()

## A wrong input for step `id` (one that must not complete it).
func _wrong(w: Node, id: String, p: String) -> void:
	var inp: Node = w.input
	match id:
		_: inp._unhandled_input(_key(KEY_X) if p != "gamepad" else _pad(JOY_BUTTON_BACK))      # recover: nothing to do on the ground

func _training(p: String) -> void:
	CP.set("force", p)
	_st().set_value("touch_mode", "on" if p == "touch" else "auto")
	var size0 := root.size
	if p == "touch": root.size = Vector2i(1170, 540)
	var w: Node = await _world()
	var t: Node = w.get("_tut")
	check(w.trial and w.tutorial and t != null, "%s: a training world (trial, tutorial)" % p)
	check(w.sim.player.weapon == "ak" and w.sim.player.slots[1] != null and w.sim.player.slots[1]["key"] == "katana", "%s: AK in hand, katana in slot 2" % p)
	check(w.sim.pickups.list.is_empty(), "%s: the range rack is cleared" % p)
	check(t.get("card").get("prompt_l").text != "", "%s: the coach card shows a prompt" % p)
	var order: Array = []
	for i in TS.call("count"): order.append(TS.call("step", i)["id"])
	for id: String in order:
		check(await _wait_step(w, id), "%s: reached step %s" % [p, id])
		if _step_now(w) != id: break
		check(t.call("prompt_text") == TS.call("plain", id, p), "%s/%s: the card shows the %s prompt" % [p, id, p])
		# the wrong input does not advance
		if p != "touch": _wrong(w, id, p)
		await frames(3)
		w.tick(0.016)
		check(_step_now(w) == id, "%s/%s: the wrong input does not complete it" % [p, id])
		if id == "pause" and p == "touch": w.tick(0.016)
		await until(func() -> bool:
			w.tick(0.016)
			return w.sim.player.down_t <= 0.0 and w.sim.player.stun <= 0.0, 4.0)
		if OS.get_cmdline_user_args().has("--trace"): print("TRACE ", p, " ", id, " weapon=", w.sim.player.weapon, " idx=", t.get("index"), " ctx=", w.touch.context_action(), " reloading=", w.sim.player.reloading, " mag=", w.sim.player.slots[0]["mag"], " slot=", w.sim.player.slot)
		_do(w, id, p)
		if OS.get_cmdline_user_args().has("--trace") and id == "spatula":
			for k in 8:
				w.tick(0.016); await process_frame
				print("  tick ", k, " weapon=", w.sim.player.weapon, " slot=", w.sim.player.slot, " peek=", w.input.state.peek("slot2"), " live=", t.call("_live"), " hit=", t.get("_hit"), " paused=", w.paused)
		var did: bool = await until(func() -> bool:
			w.tick(0.016)
			return t.get("cheering") or _step_now(w) != id or t.get("is_done"), 4.0)
		var pl: Object = w.sim.player
		check(did, "%s/%s: the real input completes it (weapon %s slot %d down %.2f stun %.2f cool %.2f hit %s step %s ctx %s reloading %s ctxpos %s touch %s)" % [p, id, pl.weapon, pl.slot, pl.down_t, pl.stun, pl.cool, str(t.get("_hit")), _step_now(w), w.touch.context_action(), str(pl.reloading), str(_btn(w.touch, "context")), str(w.touch._touch)])
		_release(w)
		if id == "pause":
			check(w.paused, "%s: the pause menu is up" % p)
			check(not t.get("card").get("finish").visible, "%s: the finish card waits behind the pause menu" % p)
			w._toggle_pause()
			await frames(3)
		await until(func() -> bool:
			w.tick(0.016)
			return _step_now(w) != id or t.get("is_done"), 3.0)
	check(await until(func() -> bool: return t.get("card").get("finish").visible, 4.0), "%s: the finish card appears" % p)
	check(t.get("is_done"), "%s: the training is done" % p)
	check(w.sim.player.hp > 0 and not w.sim.player.dead, "%s: the player was never K.O.'d" % p)
	w.queue_free()
	await frames(3)
	if p == "touch": root.size = size0
	_st().set_value("touch_mode", "auto")
	CP.call("reset")

func _training_extras() -> void:
	# a mid-training switch from keyboard to gamepad redoes the prompt
	CP.call("reset")
	var w: Node = await _world()
	var t: Node = w.get("_tut")
	await _wait_step(w, "move")
	check(t.call("prompt_text") == "Move with W A S D", "starts with the keyboard prompt (%s)" % t.call("prompt_text"))
	CP.call("note_event", _pad(JOY_BUTTON_A))
	await frames(3)
	check(str(t.get("card").get("prompt_l").text).contains("Left stick") and t.get("profile") == "gamepad", "a pad press mid-training: the prompt now names the stick")
	CP.call("note_event", _key(KEY_W))
	await frames(3)
	check(t.get("profile") == "keyboard" and str(t.get("card").get("prompt_l").text).contains("W A S D"), "a key press: back to the keyboard prompt")
	# Skip: the next step, without the input; the loadout follows the step
	var n0: int = t.get("index")
	t.call("skip")
	await frames(2)
	check(t.get("index") == n0 + 1, "Skip step moves on")
	for i in 8: t.call("skip")
	check(_step_now(w) == "dash" and w.sim.player.weapon == "katana", "skipping to Dash puts the katana in hand (%s, %s)" % [_step_now(w), w.sim.player.weapon])
	t.call("skip")
	t.call("skip")
	check(t.get("is_done") or _step_now(w) == "pause", "skipping runs on to the end")
	t.call("skip")
	await frames(2)
	check(t.get("is_done") and t.get("card").get("finish").visible, "skipping every step ends on the finish card")
	var f: Control = t.get("card").get("finish")
	check(f.visible and f.size.y > 0 and (t.get("card").get("play_b") as Button).size.y >= 44.0, "the finish card has Play / Replay / Back at 44+")
	# Replay: a fresh world with the first step; Exit: out of the world
	t.get("card").get("replay_b").pressed.emit()
	var found: Array = []
	await until(func() -> bool:
		for c in root.get_children():
			if c != w and c.get("tutorial") == true: found.append(c)
		return not found.is_empty(), 5.0)
	var nw: Node = found[0] if not found.is_empty() else null
	check(nw != null, "Replay builds a new training world")
	await frames(3)
	check(nw != null and nw.get("_tut") != null and nw.get("_tut").call("current_id") == "move", "the replayed training starts at Move")
	if nw != null: nw.free()
	if is_instance_valid(w): w.free()
	await frames(2)
	# Exit goes to the title (change_scene_to_file): check the call path, then clean up
	var w2: Node = await _world()
	var left := false
	w2.child_exiting_tree.connect(func(_n: Node) -> void: left = true)
	var t2: Node = w2.get("_tut")
	check(t2.get("card").get("exit_b") is Button and (t2.get("card").get("exit_b") as Button).size.y >= 44.0, "Exit is a 44+ button on the card")
	w2.queue_free()
	await frames(3)
	CP.call("reset")

# ---------------- 5. the offer and the hint ----------------

func _offer() -> void:
	var st := _st()
	var save: Node = root.get_node("Save")
	OFFER.set("test_persist", 0)
	check(not OFFER.call("wanted"), "never offered for a profile that is not saved (tests, --no-save)")
	var host := Control.new()
	root.add_child(host)
	check(not OFFER.call("maybe_show", host, Callable(), Callable()), "maybe_show does nothing without a saved profile")
	OFFER.set("test_persist", 1)
	st.set_value("seen_tutorial", false)
	check(int(save.stats["matches"]) == 0 and OFFER.call("wanted"), "offered to a fresh saved profile")
	var got: Array = []
	check(OFFER.call("maybe_show", host, func() -> void: got.append("next"), func() -> void: got.append("start")), "the offer card is shown")
	await frames(2)
	var card: Control = host.get_node_or_null("TutorialOffer")
	check(card != null and (card.get("skip_b") as Button).size.y >= 44.0 and (card.get("start_b") as Button).size.y >= 44.0, "the card has Start and Skip, 44+ tall")
	check(str(card.get("body_l").text).contains("Keyboard"), "the card names the active controls (%s)" % card.get("body_l").text)
	card.get("skip_b").pressed.emit()
	await frames(2)
	check(got == ["next"] and bool(st.get_value("seen_tutorial")), "Skip carries on to the match and remembers")
	check(not OFFER.call("wanted") and not OFFER.call("maybe_show", host, Callable(), Callable()), "never asked a second time")
	st.set_value("seen_tutorial", false)
	got.clear()
	OFFER.call("maybe_show", host, func() -> void: got.append("next"), func() -> void: got.append("start"))
	await frames(2)
	host.get_node("TutorialOffer").get("start_b").pressed.emit()
	await frames(2)
	check(got == ["start"] and bool(st.get_value("seen_tutorial")), "Start opens the training and remembers")
	# an experienced profile is never offered it
	st.set_value("seen_tutorial", false)
	save.stats["matches"] = 3
	check(not OFFER.call("wanted"), "never offered after a match was played")
	save.stats["matches"] = 0
	# the title's Play and Quick play go through it; the title itself has no new control
	st.set_value("seen_tutorial", false)
	var m: Control = load("res://scenes/main.tscn").instantiate()
	m.set("auto_intro", false)
	m.set("auto_news", false)
	root.add_child(m)
	await frames(3)
	m.call("quick_play")
	await frames(2)
	check(m.get_node_or_null("TutorialOffer") != null, "Quick play asks the fresh player first")
	m.get_node("TutorialOffer").get("start_b").pressed.emit()
	await frames(4)
	var cur: Node = null
	for c in root.get_children():
		if c.get("tutorial") == true: cur = c
	check(cur != null, "Start there opens the training world")
	if cur != null: cur.free()
	OFFER.set("test_persist", -1)
	host.queue_free()
	if is_instance_valid(m): m.queue_free()
	await frames(3)

func _hints() -> void:
	var st := _st()
	st.set_value("seen_tutorial", false)
	st.set_value("ctl_hint_matches", 0)
	check(CP.call("hint_wanted"), "a new player gets the hint line")
	CP.set("force", "keyboard")
	check(CP.call("hint_line") == "Shove: E  ·  Kick: F  ·  Jump: Space", "keyboard hint: %s" % CP.call("hint_line"))
	CP.set("force", "gamepad")
	check(CP.call("hint_line") == "Shove: RB  ·  Kick: B  ·  Jump: A", "gamepad hint: %s" % CP.call("hint_line"))
	CP.set("force", "touch")
	check("Melee" in str(CP.call("hint_line")), "touch hint names MELEE: %s" % CP.call("hint_line"))
	CP.call("reset")
	# the counter: persistent profiles only, two matches, then nothing; the training turns it off for good
	CP.call("note_match")
	check(int(st.get_value("ctl_hint_matches", 0)) == 0, "an unsaved profile never counts matches")
	st.set_value("ctl_hint_matches", 3)
	check(not CP.call("hint_wanted"), "after two matches the hint is gone")
	st.set_value("ctl_hint_matches", 0)
	st.set_value("seen_tutorial", true)
	check(not CP.call("hint_wanted"), "after the training the hint is gone")
	# the HUD shows it in a real match, never in the training
	st.set_value("seen_tutorial", false)
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = "arena"; w.auto_run = false; w.bot_count = 1; w.dyn_choice = "off"
	root.add_child(w)
	await frames(3)
	w.tick(0.016)
	var hint: Label = w.hud.get("_hint")
	check("Shove:" in hint.text, "the HUD hint line shows the shove / kick keys in a match (%s)" % hint.text)
	st.set_value("seen_tutorial", true)
	w.tick(0.016)
	check(not "Shove:" in hint.text, "and no control hint once the training is done")
	w.queue_free()
	var tw: Node = await _world()
	st.set_value("seen_tutorial", false)
	tw.tick(0.016)
	check(not "Shove:" in (tw.hud.get("_hint") as Label).text, "no match hint line inside the training")
	tw.queue_free()
	st.set_value("seen_tutorial", false)
	await frames(3)
