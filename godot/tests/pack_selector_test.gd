extends SceneTree
## Pack selector, pack transitions and the tester switch (headless; tools/test-pack-selector.js, npm run test:godot-pack-selector):
##   godot --headless --path godot --script res://tests/pack_selector_test.gd -- --no-save
## 1. The selector lists the four packs in the hub's order; arrows, page dots, keyboard, swipe and a tap on a side card move it;
##    it clamps at both ends; locked and owned states (texts, ENTER label); ENTER on a locked pack goes to the unlock flow
##    (no transition), on an owned pack plays that pack's transition and opens its hub (signal), for all four packs.
## 2. Every transition (construction, kitchen, xmas, australia and the lowest-tier one): headless it ends at once with the same
##    callbacks; forced to animate (a test hook, short duration) it covers, calls on_done once at the switch point, ends inside its
##    safety timeout and leaves no node behind; a tap / key skips it at once; a stalled one still ends by its safety timer; every
##    moment of it draws without errors; particle and shader budgets; durations; the tier switch.
## 3. The tester switch: a release build refuses the secret code unless RemoteConfig tester_unlock is true; one code owns ALL packs.
## 4. Layout: 667x375, 812x375, 852x393, 926x428, 1024x768 and 390x844 portrait x 4 packs x locked / owned x en fr es zh_TW ja:
##    inside the safe area, touch targets >= 44 pt, no clipped or overlapping text, the page's words inside the centred card.

const PACKS := ["construction", "kitchen", "xmas", "australia"]
const SIZES := [
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(812, 375), [44.0, 0.0, 44.0, 21.0]],
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(926, 428), [47.0, 0.0, 47.0, 21.0]],
	[Vector2(1024, 768), [0.0, 0.0, 0.0, 20.0]],
	[Vector2(390, 844), [0.0, 47.0, 0.0, 34.0]],
]
const LANGS := ["en", "fr", "es", "zh_TW", "ja"]
const MIN_TOUCH := 44.0
const MIN_GAP_PT := 8.0
const TEST_CODE := "throwaway-code-123"

var PS: GDScript
var PT: GDScript
var DU: GDScript
var RC: GDScript
var fails := 0
var made: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _sv() -> Node:
	return root.get_node("Save")

func _fresh(coins := 2300) -> void:
	_sv().reset()
	_sv().coins = coins

func _profile() -> SaveProfile:
	var s := SaveProfile.new()
	s.persist = false
	made.append(s)
	return s

func _run() -> void:
	PS = load("res://ui/pack_selector.gd")
	PT = load("res://ui/pack_transition.gd")
	DU = load("res://dlc/construction/dlc_unlock.gd")
	RC = load("res://autoload/remote_config.gd")
	var content: Node = root.get_node("Content")
	var standins: Array = []
	for kv in [["kitchen_chaos", "Kitchen Chaos"], ["toy_workshop", "Toy Workshop"], ["backyard_bbq", "Backyard BBQ"]]:
		if not content.maps.has(kv[0]):
			var m: Dictionary = (content.maps["arena"] as Dictionary).duplicate(true)
			m["name"] = kv[1]
			content.maps[kv[0]] = m
			standins.append(kv[0])
	await _selector()
	await _flow()
	await _transitions()
	await _title_flow()
	_tester_switch()
	await _layouts()
	for n: Node in made: n.free()
	for id: String in standins: content.maps.erase(id)
	print("PACK SELECTOR ok" if fails == 0 else "PACK SELECTOR checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _vp(sz: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = sz
	vp.disable_3d = true
	root.add_child(vp)
	return vp

func _selector_in(vp: SubViewport) -> Control:
	var sel: Control = PS.new()
	vp.add_child(sel)
	return sel

# ---------------- 1. the deck ----------------

func _selector() -> void:
	_fresh()
	var vp := _vp(Vector2i(1170, 540))
	var sel := _selector_in(vp)
	sel.open_at("")
	for i in 3: await process_frame
	var ids: Array = []
	for d: Resource in sel.packs: ids.append(d.pack_id)
	check(ids == PACKS, "the selector lists all four packs in order (%s)" % [ids])
	check(ids == PackRegistry.ids(), "...which is the hub's order (PackRegistry.ids)")
	check(sel.cards.size() == 4 and sel.dots.size() == 4, "one card and one page dot per pack")
	check(sel.current_id() == "construction" and sel.index == 0, "it opens on the first pack")
	check(sel.prev_b.disabled and not sel.next_b.disabled, "the previous arrow is dimmed on the first pack")
	# arrows
	sel.next_b.pressed.emit()
	check(sel.current_id() == "kitchen", "the next arrow moves to On Fire")
	sel.next_b.pressed.emit()
	sel.next_b.pressed.emit()
	check(sel.current_id() == "australia" and sel.next_b.disabled, "the arrows reach the last pack and clamp there")
	check(not sel.step(1) and sel.current_id() == "australia", "past the end nothing moves (clamp, no wrap)")
	sel.prev_b.pressed.emit()
	check(sel.current_id() == "xmas", "the previous arrow moves back")
	# the page dots
	sel.dots[0].pressed.emit()
	check(sel.current_id() == "construction", "a page dot jumps to its pack")
	sel.dots[3].pressed.emit()
	check(sel.current_id() == "australia", "the last page dot jumps to Hey Mate")
	check(not sel.go_to(3) and sel.go_to(1) and sel.current_id() == "kitchen", "go_to the current pack is a no-op")
	sel.go_to(-5)
	check(sel.current_id() == "construction", "go_to clamps below zero")
	# keyboard: ui_right / ui_left
	var ev := InputEventAction.new()
	ev.action = "ui_right"
	ev.pressed = true
	sel._input(ev)
	check(sel.current_id() == "kitchen", "the right key moves forward")
	var ev2 := InputEventAction.new()
	ev2.action = "ui_left"
	ev2.pressed = true
	sel._input(ev2)
	sel._input(ev2)
	check(sel.current_id() == "construction", "the left key moves back and clamps")
	# swipe: drag left over the stage by about one card spacing
	for i in 3: await process_frame
	var sp: float = sel._spacing()
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = Vector2(600, 150)
	sel._on_stage_input(mb)
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(600 - sp, 150)
	mm.relative = Vector2(-sp, 0)
	sel._on_stage_input(mm)
	check(sel.pos > 0.5, "dragging left follows the finger (pos %.2f)" % sel.pos)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(600 - sp, 150)
	sel._on_stage_input(up)
	check(sel.current_id() == "kitchen", "a swipe left settles on the next pack")
	# a swipe back
	mb.position = Vector2(300, 150)
	sel._on_stage_input(mb)
	mm.position = Vector2(300 + sp, 150)
	mm.relative = Vector2(sp, 0)
	sel._on_stage_input(mm)
	up.position = Vector2(300 + sp, 150)
	sel._on_stage_input(up)
	check(sel.current_id() == "construction", "a swipe right goes back")
	# a tiny drag is a tap, not a swipe; a tap on the right-hand card brings it to the middle
	await create_timer(1.0).timeout
	var right: Control = sel.cards[1]
	var tap_at: Vector2 = right.position + right.size * 0.5
	mb.position = tap_at
	sel._on_stage_input(mb)
	up.position = tap_at
	sel._on_stage_input(up)
	check(sel.current_id() == "kitchen", "a tap on a side card centres it")
	# the animated position settles on the index (real time: the spring runs on the frame delta)
	await create_timer(1.2).timeout
	check(is_equal_approx(sel.pos, float(sel.index)), "the deck settles (pos %.3f index %d)" % [sel.pos, sel.index])
	# only the centred card takes the full size, the others are smaller and dimmer
	var mid: Control = sel.cards[sel.index]
	var side: Control = sel.cards[0]
	check(mid.scale.x > side.scale.x and mid.modulate.a > side.modulate.a, "the centred card is bigger and brighter")
	check(mid.z_index > side.z_index, "...and in front")
	vp.queue_free()
	await process_frame

func _own(id: String, on: bool) -> void:
	DlcSave.set_owned(_sv().dlc, id, on)

func _flow() -> void:
	_fresh()
	var vp := _vp(Vector2i(1170, 540))
	var sel := _selector_in(vp)
	var unlocks: Array = []
	var plays: Array = []
	sel.unlock_requested.connect(func(id: String) -> void: unlocks.append(id))
	sel.play_requested.connect(func(id: String) -> void: plays.append(id))
	sel.open_at("")
	for i in 3: await process_frame
	for i in 4:
		sel.go_to(i)
		var d: Resource = sel.current()
		check(not sel.owned(i) and not sel.cards[i].is_owned, "%s starts locked" % PACKS[i])
		check(sel.enter_b.text == "UNLOCK PACK", "%s: the big button says UNLOCK PACK (%s)" % [PACKS[i], sel.enter_b.text])
		check(sel.cards[i].lock.visible and sel.cards[i].status_l.text == str(DU.price(PACKS[i])), "%s: padlock and price (%s)" % [PACKS[i], sel.cards[i].status_l.text])
		var played0: int = PT.played
		sel.enter_b.pressed.emit()
		check(unlocks.back() == PACKS[i] and plays.is_empty(), "%s: ENTER on a locked pack opens the unlock flow" % PACKS[i])
		check(PT.played == played0 and PT.live == 0, "%s: no transition for a locked pack" % PACKS[i])
		check(sel.visible, "%s: the selector stays up while the unlock flow opens (the owner decides)" % PACKS[i])
	check(unlocks == PACKS, "the unlock flow was asked for each pack in turn")
	# owned: the state texts change and ENTER plays the transition, then the hub opens (headless: at once)
	for i in 4:
		_fresh()
		_own(PACKS[i], true)
		sel.reload()
		sel.open_at(PACKS[i])
		for k in 2: await process_frame
		check(sel.owned(i) and sel.cards[i].is_owned, "%s is owned now" % PACKS[i])
		check(sel.enter_b.text == "PLAY", "%s: the big button says PLAY" % PACKS[i])
		check(not sel.cards[i].lock.visible and sel.cards[i].status_l.text == "OWNED", "%s: OWNED, no padlock" % PACKS[i])
		for j in 4:
			if j != i: check(not sel.owned(j), "%s owned does not own %s" % [PACKS[i], PACKS[j]])
		plays.clear()
		var played0: int = PT.played
		var ended := [false]
		sel.enter()
		check(plays == [PACKS[i]], "%s: ENTER plays the transition, then the hub opens (%s)" % [PACKS[i], plays])
		check(PT.played == played0 + 1, "%s: one transition played" % PACKS[i])
		check(PT.live == 0 and not sel.busy, "%s: headless, it is already over" % PACKS[i])
		check(not sel.visible, "%s: the selector closed behind the transition" % PACKS[i])
		sel.visible = true
	# Back / ENTER spam: busy blocks a second ENTER (forced animation)
	_fresh()
	_own("kitchen", true)
	sel.reload()
	sel.open_at("kitchen")
	PT.force_run = true
	PT.speed = 0.05
	plays.clear()
	var n0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	sel.enter()
	check(sel.busy and PT.live == 1, "an animated transition is running")
	sel.enter()
	check(PT.live == 1, "ENTER again while it runs starts nothing new")
	for i in 400:
		if PT.live == 0: break
		await process_frame
	check(PT.live == 0 and not sel.busy and plays == ["kitchen"], "it ended, the hub opened once (%s)" % [plays])
	await process_frame
	check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) <= n0, "no node left behind (%d -> %d)" % [n0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	PT.force_run = false
	PT.speed = 1.0
	vp.queue_free()
	await process_frame

# ---------------- the title wiring ----------------

func _title_flow() -> void:
	_fresh(5000)
	var vp := _vp(Vector2i(1170, 540))
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.auto_intro = false
	main.auto_news = false
	vp.add_child(main)
	main.browser.auto_refresh = false
	for i in 4: await process_frame
	check(main.selector != null and not main.selector.visible, "the title has a pack selector, closed")
	# the Packs chip of the opened container opens it
	main.showcase.snap(true)
	for i in 3: await process_frame
	check(main.showcase.packs_b.is_visible_in_tree() and main.showcase.packs_b.size.y >= 60.0 - 0.5, "the opened container shows a Packs chip (60 px or more)")
	main.showcase.packs_b.pressed.emit()
	check(main.selector.visible and main.selector.current_id() == main.showcase.pack().pack_id, "the Packs chip opens the selector on the pack in view")
	check(main.go_back() and not main.selector.visible, "Back / Escape closes the selector")
	main.showcase.snap(false)
	# a locked pack: UNLOCK PACK opens the hub on it, the selector steps aside, the hub's Back returns to the selector
	main.open_packs("xmas")
	main.selector.enter()
	check(main.hub.visible and main.hub.pack_id == "xmas" and not main.selector.visible, "UNLOCK PACK on a locked pack opens the hub on that pack")
	check(main.hub.back() and main.selector.visible and main.selector.current_id() == "xmas", "the hub's Back returns to the selector on the same pack")
	main.selector.back()
	# an owned pack: PLAY plays the transition and opens its hub
	_own("australia", true)
	main.open_packs("australia")
	var played0: int = PT.played
	main.selector.enter()
	check(PT.played == played0 + 1 and main.hub.visible and main.hub.pack_id == "australia" and not main.selector.visible, "PLAY on an owned pack opens that pack's hub")
	check(PT.live == 0, "...and the transition is gone")
	main.hub.back()
	check(main.selector.visible, "Back from that hub: the selector again")
	main.selector.back()
	check(not main.selector.visible and not main.hub.visible, "Back from the selector: the title")
	vp.queue_free()
	await process_frame

# ---------------- 2. transitions ----------------

func _drive(id: String, style: String, tag: String) -> void:
	var vp := _vp(Vector2i(852, 393))
	var calls := {"done": 0, "end": 0, "done_at": -1.0}
	PT.force_style = style
	PT.force_run = true
	PT.speed = 0.04
	var n0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var t0 := Time.get_ticks_msec()
	var node: Control = PT.play(id, vp, func() -> void:
		calls["done"] += 1
		calls["done_at"] = (Time.get_ticks_msec() - t0) / 1000.0, func() -> void: calls["end"] += 1)
	check(node != null and PT.live == 1, "%s: it runs (animated)" % tag)
	check(calls["done"] == 0, "%s: the hub does not open before the screen is covered" % tag)
	var dur: float = node.dur
	for i in 3000:
		if node == null or not is_instance_valid(node) or node.finished: break
		await process_frame
	var took := (Time.get_ticks_msec() - t0) / 1000.0
	check(calls["done"] == 1 and calls["end"] == 1, "%s: on_done once and on_end once (%d, %d)" % [tag, calls["done"], calls["end"]])
	check(took <= dur * 2.0 + 1.0, "%s: ended inside its safety timeout (%.2f s of %.2f s)" % [tag, took, dur * 2.0 + 1.0])
	check(calls["done_at"] >= 0.0 and calls["done_at"] <= took + 0.01, "%s: the switch came before the end" % tag)
	await process_frame
	check(PT.live == 0, "%s: nothing running afterwards" % tag)
	check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) <= n0 + 1, "%s: no orphan nodes (%d -> %d)" % [tag, n0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	# tap to skip
	var c2 := {"done": 0, "end": 0}
	PT.speed = 1.0
	var node2: Control = PT.play(id, vp, func() -> void: c2["done"] += 1, func() -> void: c2["end"] += 1)
	for i in 3: await process_frame
	check(c2["done"] == 0 and c2["end"] == 0 and not node2.finished, "%s: still playing after a few frames at full length" % tag)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	node2._input(click)
	check(c2["done"] == 1 and c2["end"] == 1 and node2.finished and node2.skipped, "%s: a tap skips it at once (the hub opens first)" % tag)
	await process_frame
	check(PT.live == 0, "%s: skipped and gone" % tag)
	# a key skips too, a mouse release does not
	var c3 := {"done": 0, "end": 0}
	var node3: Control = PT.play(id, vp, func() -> void: c3["done"] += 1, func() -> void: c3["end"] += 1)
	var rel := InputEventMouseButton.new()
	rel.button_index = MOUSE_BUTTON_LEFT
	rel.pressed = false
	node3._input(rel)
	check(not node3.finished, "%s: the button release that started it does not skip it" % tag)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	node3._input(key)
	check(c3["done"] == 1 and c3["end"] == 1, "%s: a key skips it" % tag)
	await process_frame
	# a stalled transition (nothing ticks it) still ends by its safety timer
	PT.speed = 0.04
	var c4 := {"done": 0, "end": 0}
	var node4: Control = PT.play(id, vp, func() -> void: c4["done"] += 1, func() -> void: c4["end"] += 1)
	node4.set_process(false)
	var dur4: float = node4.dur
	var t1 := Time.get_ticks_msec()
	for i in 4000:
		if c4["end"] > 0: break
		await process_frame
	var stalled := (Time.get_ticks_msec() - t1) / 1000.0
	check(c4["done"] == 1 and c4["end"] == 1 and stalled <= dur4 * 2.0 + 1.6, "%s: a stalled transition ends by its safety timer (%.2f s)" % [tag, stalled])
	await process_frame
	check(PT.live == 0, "%s: no transition left running" % tag)
	PT.force_style = ""
	PT.force_run = false
	PT.speed = 1.0
	vp.queue_free()
	await process_frame

func _transitions() -> void:
	_fresh()
	# headless: the same end logic at once
	for id: String in PACKS:
		var calls := {"done": 0, "end": 0}
		var node: Control = PT.play(id, root, func() -> void: calls["done"] += 1, func() -> void: calls["end"] += 1)
		check(calls["done"] == 1 and calls["end"] == 1 and PT.live == 0, "%s: headless it finishes at once with both callbacks" % id)
		await process_frame
		check(node == null or not is_instance_valid(node), "%s: and the node is gone" % id)
	# no parent: the callbacks still run (never a soft lock)
	var c := {"done": 0, "end": 0}
	check(PT.play("kitchen", null, func() -> void: c["done"] += 1, func() -> void: c["end"] += 1) == null and c["done"] == 1 and c["end"] == 1, "no parent: the callbacks run, nothing hangs")
	# styles and durations
	for id: String in PACKS:
		var d: float = PT.duration_of(id)
		check(d >= 0.9 and d <= 1.4, "%s: duration %.2f s is 0.9 to 1.4 s" % [id, d])
	check(PT.style_for("construction") == "site" and PT.style_for("kitchen") == "fire" and PT.style_for("xmas") == "xmas" and PT.style_for("australia") == "outback", "one style per pack")
	check(PT.style_for("nope") == "lite", "an unknown pack gets the plain wipe")
	# the budgets
	var fire: GDScript = load("res://ui/transitions/pack_transition_fire.gd")
	var xmas: GDScript = load("res://ui/transitions/pack_transition_xmas.gd")
	var out: GDScript = load("res://ui/transitions/pack_transition_outback.gd")
	check(fire.N_JETS + fire.N_EMBERS + fire.N_STEAM <= PT.MAX_PARTICLES, "kitchen: at most %d particles" % PT.MAX_PARTICLES)
	check(xmas.N_FLAKES + xmas.N_SPARKS <= PT.MAX_PARTICLES, "xmas: at most %d particles" % PT.MAX_PARTICLES)
	check(out.N_DUST <= PT.MAX_PARTICLES, "australia: at most %d particles" % PT.MAX_PARTICLES)
	# the lowest tier: the simple wipe
	var st: Node = root.get_node("Settings")
	var was: Variant = st.get_value("fx_quality", "auto")
	st.set_value("fx_quality", "low")
	check(PT.style_for("kitchen") == "lite" and PT.style_for("construction") == "lite" and PT.style_for("xmas") == "lite", "Effects: Low plays the plain fade + wipe for every pack")
	check(PT.duration_of("kitchen") <= 1.0, "...and it is short")
	st.set_value("fx_quality", was)
	check(PT.style_for("kitchen") == "fire", "the normal tier plays the flame wipe again")
	# every moment of every style draws (scrubbed by hand), at a phone and a portrait size, with one shader rect at most
	for style: String in ["site", "fire", "xmas", "outback", "lite"]:
		for sz: Vector2i in [Vector2i(852, 393), Vector2i(390, 844), Vector2i(667, 375)]:
			var vp := _vp(sz)
			PT.force_style = style
			var id: String = {"site": "construction", "fire": "kitchen", "xmas": "xmas", "outback": "australia", "lite": "kitchen"}[style]
			var n: Control = PT.new()
			n.setup(id, Callable(), Callable())
			n.manual = true
			vp.add_child(n)
			var shaded := 0
			for ch in n.get_children():
				if ch is CanvasItem and (ch as CanvasItem).material != null: shaded += 1
			check(shaded <= 1, "%s: at most one fullscreen shader rect (%d)" % [style, shaded])
			for p: float in [0.0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.45, 0.5, 0.55, 0.6, 0.7, 0.8, 0.9, 0.99]:
				n.scrub(p)
				await process_frame
			check(n.switched and not n.finished, "%s: scrubbing to 0.99 switched but did not finish" % style)
			n.scrub(1.0)
			check(n.finished, "%s: p = 1 finishes it" % style)
			await process_frame
			PT.force_style = ""
			vp.queue_free()
	await process_frame
	for id: String in PACKS: await _drive(id, "", id)
	await _drive("kitchen", "lite", "lite")
	check(PT.live == 0, "every transition is accounted for (%d live)" % PT.live)

# ---------------- 3. the tester switch ----------------

func _tester_switch() -> void:
	var rc: Node = root.get_node("RemoteConfig")
	var saved: Dictionary = rc.values
	DU.reset_attempts()
	check(RC.DEFAULTS["tester_unlock"] == false and RC.validate({})["tester_unlock"] == false, "tester_unlock defaults to false")
	check(RC.validate({"tester_unlock": "true"})["tester_unlock"] == false and RC.validate({"tester_unlock": 1})["tester_unlock"] == false, "only a real JSON true switches it on")
	var bundled: Dictionary = RC.read_config(RC.BUNDLED_PATH)
	check(bundled.has("tester_unlock") and bundled["tester_unlock"] == false, "the bundled config says false")
	# 1. a debug build: accepted, whatever the flag says
	DU.release_override = 0
	rc.values = RC.validate({})
	check(not DU.is_release() and DU.dev_code_allowed(), "debug build: the code is allowed (flag off)")
	var s := _profile()
	check(DU.redeem_with(TEST_CODE, DU.hash_of(TEST_CODE), s), "debug build: the code is accepted")
	for id: String in PACKS: check(DU.owned(s, id), "debug build: %s is owned" % id)
	# 2. a release build with the flag off: refused, nothing changes
	DU.release_override = 1
	DU.reset_attempts()
	check(DU.is_release() and not DU.tester_unlock() and not DU.dev_code_allowed(), "release build, flag off: the code is not allowed")
	var r := _profile()
	var before := JSON.stringify(r.get_blob())
	check(not DU.redeem_with(TEST_CODE, DU.hash_of(TEST_CODE), r), "release build, flag off: the right code is refused")
	check(JSON.stringify(r.get_blob()) == before, "...and the profile did not change")
	for id: String in PACKS: check(not DU.owned(r, id), "release build, flag off: %s stays locked" % id)
	# 3. a release build with the flag on: accepted, ALL four packs owned with their outfits and hats, one code
	rc.values = RC.validate({"tester_unlock": true})
	check(DU.tester_unlock() and DU.dev_code_allowed(), "release build, flag on: the code is allowed")
	var r2 := _profile()
	check(DU.redeem_with(TEST_CODE, DU.hash_of(TEST_CODE), r2), "release build, flag on: the code is accepted")
	var hidden: Array = PackRegistry.hidden_hats(r2)
	for id: String in PACKS:
		check(DU.owned(r2, id) and PackRegistry.owned(id, r2), "release build, flag on: %s is owned" % id)
		for k: String in LockerData.pack_skins(id): check(r2.skins.has(k), "%s: outfit %s granted" % [id, k])
		for h: String in PackRegistry.hats(id): check(not hidden.has(h), "%s: hat %s is listed for the owner" % [id, h])
	check(PackRegistry.owned_ids(r2) == PackRegistry.ids(), "one code owns every pack the registry knows")
	check(r2.coins >= DU.DEV_COINS, "the code's coins are paid")
	# 4. flipping the flag back (a config refresh) closes the door again, with no restart
	rc.values = RC.validate({"tester_unlock": false})
	DU.reset_attempts()
	check(not DU.dev_code_allowed() and not DU.redeem_with(TEST_CODE, DU.hash_of(TEST_CODE), _profile()), "a refreshed config with the flag off refuses the code again")
	# 5. a release build: the Settings 7-tap entry follows the same function (hidden with the flag off, open with it on)
	var ss: GDScript = load("res://ui/settings_screen.gd")
	var vp := _vp(Vector2i(1170, 540))
	var scr: Control = ss.new()
	vp.add_child(scr)
	rc.values = RC.validate({"tester_unlock": false})
	scr.open()
	for i in 7: scr.version_tap()
	check(not scr.code_sheet.visible, "release build, flag off: seven taps open nothing")
	rc.values = RC.validate({"tester_unlock": true})
	for i in 7: scr.version_tap()
	check(scr.code_sheet.visible, "release build, flag on: seven taps open the code field")
	scr.code_sheet.close()
	vp.queue_free()
	DU.release_override = -1
	rc.values = saved
	check(DU.dev_code_allowed() == not OS.has_feature("release"), "the real build flag is back (override cleared)")
	DU.reset_attempts()

# ---------------- 4. layouts ----------------

func _layouts() -> void:
	for loc: String in LANGS:      # Japanese last and left on: Godot logs font errors at exit when a CJK language is switched back
		if loc != "en": root.get_node("Lang").apply(loc)
		for sz: Array in SIZES:
			for id: String in PACKS:
				for own: bool in [false, true]:
					await _layout_case(sz[0], sz[1], id, own, loc)
	SafeArea.override = []

func _gather(n: Node, out: Array, skip: Array) -> void:
	for c in n.get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree() or skip.has(c): continue
		out.append(c)
		_gather(c, out, skip)

func _shown(c: Control) -> Rect2:
	var r := c.get_global_rect()
	var p := c.get_parent()
	while p != null and r.size.x > 0.0 and r.size.y > 0.0:
		if p is Control and (p as Control).clip_contents: r = r.intersection((p as Control).get_global_rect())
		p = p.get_parent()
	return r if r.size.x > 0.0 and r.size.y > 0.0 else Rect2()

func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)

func _nm(c: Control) -> String:
	var t: Variant = c.get("text")
	return str(t) if t != null and str(t) != "" else str(c.name)

func _layout_case(win: Vector2, ins_pt: Array, id: String, own: bool, loc: String) -> void:
	var cs := UiScale.canvas_size(win, "normal", true)
	var k := cs.x / win.x
	var ins := [ins_pt[0] * k, ins_pt[1] * k, ins_pt[2] * k, ins_pt[3] * k]
	SafeArea.override = ins
	var tag := "%dx%d %s %s %s" % [win.x, win.y, id, "owned" if own else "locked", loc]
	_fresh()
	if own: _own(id, true)
	var vp := _vp(Vector2i(cs))
	var sel := _selector_in(vp)
	sel.open_at(id)
	for i in 4: await process_frame
	var portrait := win.y > win.x
	var unit: float = sel.unit
	var safe_r := Rect2(Vector2(ins[0], ins[1]), cs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	check(sel.is_visible_in_tree(), "%s: page shown" % tag)
	check(sel.current_id() == id, "%s: centred on the pack" % tag)
	var card: Control = sel.cards[sel.index]
	var skip: Array = [sel.backdrop]
	for c: Control in sel.cards:
		if c != card: skip.append(c)
	var all: Array = []
	_gather(sel.safe, all, skip)
	var items: Array = []
	for c: Control in all:
		if c is BaseButton:
			var r := _shown(c)
			check(r.size.x > 0.0, "%s: '%s' is visible" % [tag, _nm(c)])
			if r.size.x <= 0.0: continue
			items.append([c, r])
			check(safe_r.grow(0.5).encloses(r), "%s: '%s' %s inside the safe area %s" % [tag, _nm(c), r, safe_r])
			check(minf(r.size.x, r.size.y) >= MIN_TOUCH * k - 0.5, "%s: '%s' touch target %s px = %.1f pt" % [tag, _nm(c), r.size, minf(r.size.x, r.size.y) / k])
	check(items.size() >= 8, "%s: back, 4 dots, 2 arrows and ENTER are all there (%d buttons)" % [tag, items.size()])
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Control = items[i][0]
			var b: Control = items[j][0]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a): continue
			var g := _gap(items[i][1], items[j][1])
			check(g >= MIN_GAP_PT * k - 0.6, "%s: '%s' and '%s' are %.1f pt apart (need 8)" % [tag, _nm(a), _nm(b), g / k])
	# the cards: the centred one is inside the stage and the stage inside the safe area
	var stage_r: Rect2 = (sel.stage as Control).get_global_rect()
	check(safe_r.grow(0.5).encloses(stage_r), "%s: the stage %s is inside the safe area" % [tag, stage_r])
	var card_r := card.get_global_rect()
	check(stage_r.grow(0.5).encloses(card_r), "%s: the centred card %s fits the stage %s" % [tag, card_r, stage_r])
	check(card_r.size.x >= 200.0 and card_r.size.y >= 150.0, "%s: the card is a real size %s" % [tag, card_r.size])
	# words: every label in the head, the foot and the card shows whole, at a readable size, inside its box
	var texts: Array = []
	for c: Control in all:
		if (c is Label or c is Button) and str(c.get("text")) != "": texts.append(c)
	var rects: Array = []
	for c: Control in texts:
		var txt: String = c.get("text")
		var fs := c.get_theme_font_size("font_size")
		var floor_fs := UiTheme.MIN_FONT if (c is Button or card.is_ancestor_of(c) == false) else FitText.MIN_SIZE
		check(fs >= floor_fs, "%s: '%s' font %d under %d" % [tag, txt, fs, floor_fs])
		var f := c.get_theme_font("font")
		if c is Label:
			var l := c as Label
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
				check(l.size.y + 0.5 >= l.get_line_count() * l.get_line_height(), "%s: '%s' wraps taller than its box (%d lines, %.0f of %.0f)" % [tag, txt, l.get_line_count(), l.get_line_count() * l.get_line_height(), l.size.y])
				check(l.get_visible_line_count() == l.get_line_count(), "%s: '%s' lines are cut" % [tag, txt])
			else:
				var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				check(l.size.x + 1.0 >= w, "%s: '%s' squeezed (%.0f in %.0f)" % [tag, txt, w, l.size.x])
		else:
			if not txt.contains("\n"):
				var w2 := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				check(w2 <= c.size.x - 8.0 or c.name.begins_with("Dot_"), "%s: button '%s' text %.0f is tight in %.0f" % [tag, txt, w2, c.size.x])
		if card.is_ancestor_of(c):
			var lr := c.get_global_rect()
			check(card_r.grow(1.0).encloses(lr), "%s: '%s' %s sticks out of its card %s" % [tag, txt, lr, card_r])
			rects.append([c, lr])
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a2: Control = rects[i][0]
			var b2: Control = rects[j][0]
			if a2.is_ancestor_of(b2) or b2.is_ancestor_of(a2): continue
			check(not (rects[i][1] as Rect2).grow(-1.0).intersects(rects[j][1]), "%s: '%s' overlaps '%s'" % [tag, _nm(a2), _nm(b2)])
	check(card.status.get_global_rect().size.x > 0.0 and card_r.grow(1.0).encloses(card.status.get_global_rect()), "%s: the state row is inside the card" % tag)
	check(card_r.grow(1.0).encloses(card.badge.get_global_rect()), "%s: the badge is inside the card" % tag)
	check(card_r.grow(1.0).encloses(card.rail.get_global_rect()), "%s: the pattern rail is inside the card" % tag)
	check(card.badge.get_global_rect().size.x >= 56.0, "%s: the badge is big (%.0f)" % [tag, card.badge.get_global_rect().size.x])
	# the big button is the biggest thing in the foot and says the right word
	check(sel.enter_b.text == ("PLAY" if own else "UNLOCK PACK") or loc != "en", "%s: ENTER says %s" % [tag, sel.enter_b.text])
	check(sel.enter_b.get_global_rect().size.y >= MIN_TOUCH * k - 0.5, "%s: ENTER is a real button" % tag)
	if portrait:
		check(unit > 1.5, "%s: portrait grows the touch size (%.2f)" % [tag, unit])
		check(sel.dots_row.get_parent() == sel.dots_bar, "%s: portrait puts the page dots in their own row" % tag)
	else:
		check(sel.dots_row.get_parent() == sel.head, "%s: landscape keeps the page dots in the header" % tag)
	vp.queue_free()
	await process_frame
