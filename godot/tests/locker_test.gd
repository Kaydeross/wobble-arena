extends SceneTree
## Locker / Shop / emotes test (headless): buy and equip rules (autoload/save.gd), the Locker / Shop screen flow
## (ui/locker.gd: try on, buy with a confirm, not enough coins, wear, emote preview), the Wobbler emotes
## (actors/emote_poses.gd: every emote poses finite values, ends on time, stops on a swing, hides the weapon), and the
## in-match emote button (ui/emote_wheel.gd: a touch on it opens the wheel and does not reach the touch layer, a pick
## dances, T plays slot 1) plus the results panel rewards.
##   godot --headless --path godot --script res://tests/locker_test.gd -- --no-save   (npm run test:godot-locker)

const FRAME := 1.0 / 60.0
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	_rules()
	_emotes()
	await _screen()
	await _wheel()
	print("Locker ok" if fails == 0 else "Locker checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _rules() -> void:
	var s := SaveProfile.new()
	s.persist = false
	check(s.buy_check("skin", "hero") == "coins" and s.buy("skin", "hero") == "coins" and s.coins == 500, "too few coins: nothing bought")
	check(s.missing("skin", "hero") == 1000, "missing coins (%d)" % s.missing("skin", "hero"))
	check(s.buy("skin", "cowboy") == "ok" and s.coins == 100 and s.owns_skin("cowboy") and s.look["skin"] == "cowboy", "outfit bought and worn")
	check(s.buy("skin", "cowboy") == "owned" and s.coins == 100, "cannot buy twice")
	check(s.buy_check("skin", "dev") == "not_for_sale" and s.buy_check("skin", "zzz") == "not_for_sale", "code / unknown outfits are not for sale")
	check(s.buy_check("emote", "pirouette") == "not_for_sale" and s.buy_check("emote", "devspin") == "not_for_sale", "outfit / code emotes are not for sale")
	check(not s.wear_skin("hero") and s.wear_skin("hoodie") and s.wear_skin("none"), "wear only owned outfits")
	s.add_coins(5000)
	check(s.buy("skin", "ballerina") == "ok" and s.owns_emote("pirouette") and s.slots.has("pirouette"), "Ballerina brings Grand Pirouette into a slot")
	check(s.buy("emote", "flip") == "ok" and s.slots == ["wobble", "pirouette", "flip"], "a bought emote fills the free slot (%s)" % [s.slots])
	check(s.buy("emote", "dab") == "ok" and s.slots.size() == 3 and not s.slots.has("dab"), "no free slot: owned but not slotted")
	check(s.equip_emote("dab", 0) and s.slots[0] == "dab" and s.equip_emote("flip", 0) and s.slots == ["flip", "pirouette", "dab"], "equip moves an emote between slots (%s)" % [s.slots])
	check(not s.equip_emote("nova", 0), "cannot equip an emote you do not own")
	for id in ["hip", "clap", "disco", "sit", "robot", "spin", "griddy"]: s.owned.append(id)
	var wh := s.wheel_emotes()
	check(wh.size() == SaveProfile.WHEEL_MAX and wh.slice(0, 3) == s.slots, "wheel: slots first, 8 at most (%s)" % [wh])
	check(not s.set_hat("zzz") and s.set_hat("crown") and not s.set_color(123) and s.set_color(LockerData.swatch()[1]) and s.set_class("kid") and not s.set_class("zzz"), "free hats / colours / classes, validated")
	s.free()

func _emotes() -> void:
	var w: Wobbler = load("res://actors/wobbler.tscn").instantiate()
	root.add_child(w)
	w.set_weapon("smg")
	for id: String in LockerData.all_emotes():
		var dur := float(LockerData.emote(id)["dur"])
		var t := 0.0
		while t <= dur:
			var p := EmotePoses.pose(id, t, dur, 0.4)
			var ok := is_finite(p["yaw"]) and is_finite(p["hop"]) and is_finite(p["lx"]) and is_finite(p["lz"]) and is_finite(p["crouch"])
			if p["aim"] != null: ok = ok and (p["aim"] as Vector3).is_finite()
			if not ok:
				check(false, "emote %s pose finite at %.2f" % [id, t]); break
			t += 0.1
	check(w.play_emote("griddy") and w.is_emoting(), "plays an emote")
	check(not w._weapon_nodes["smg"].visible, "the weapon is put away while dancing")
	for i in 60: w.animate(FRAME)
	check(w.is_emoting() and (absf(w.e_lz) > 0.0 or w.e_hop > 0.0), "the emote moves the body")
	for i in 200: w.animate(FRAME)
	check(not w.is_emoting() and w._weapon_nodes["smg"].visible, "ends after its length, weapon back")
	w.play_emote("wobble")
	w.apply_state({"pos": Vector3.ZERO, "swing": 0.2})
	w.animate(FRAME)
	check(not w.is_emoting(), "a swing stops the emote")
	w.apply_state({"pos": Vector3.ZERO, "swing": -1.0, "dead": true})
	check(not w.play_emote("wobble") and not w.play_emote("nope"), "no dancing while K.O.'d or with an unknown id")
	w.queue_free()

func _screen() -> void:
	var sv: SaveProfile = root.get_node("Save")
	sv.reset()
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await process_frame
	check((main.shop_b.get_node("Stack/Sub") as Label).text == "You have 500 coins", "title Shop button shows the coins")
	main.locker_b.pressed.emit()
	await process_frame
	var l = main.locker
	check(l.visible and not main.get_node("Safe/Col").visible and l.title_l.text == "Locker" and l.tabs().size() == 5, "Locker opens with 5 tabs")
	check(l.picked() == "none" and l.action_b.text == "Wearing" and l.action_b.disabled, "worn outfit picked, nothing to do")
	l._show_tab("skin")
	l.cards["hero"].pressed.emit()
	check(l.picked() == "hero" and l.action_state() == "coins" and l.action_b.text == "Need 1000 more", "a locked outfit you cannot afford (%s)" % l.action_b.text)
	check(l.stage.current.contains("hero"), "tapping a card tries it on")
	check(l.cards["hero"].has_node("Lock") and not l.cards["hoodie"].has_node("Lock"), "padlock on locked cards only")
	l.act()
	check(not l.confirm.visible and l.msg_l.text.contains("1000 more coins"), "not enough coins is explained: %s" % l.msg_l.text)
	l.cards["cowboy"].pressed.emit()
	check(l.action_state() == "buy" and l.action_b.text == "Buy for 400", "affordable outfit: Buy")
	l.act()
	check(l.confirm.visible and l.confirm_title.text == "Buy Sheriff?", "Buy asks first")
	l.show_confirm(false)
	check(sv.coins == 500 and not sv.owns_skin("cowboy"), "Cancel buys nothing")
	l.act()
	check(l.buy_confirmed() == "ok" and sv.coins == 100 and sv.look["skin"] == "cowboy" and not l.confirm.visible, "confirmed: bought and worn")
	check(str(root.get_node("Settings").get_value("skin")) == "cowboy", "the match / wizard see the new outfit")
	check(l.action_b.text == "Wearing" and not l.cards["cowboy"].has_node("Lock"), "card unlocked")
	l._show_tab("hat")
	l.cards["crown"].pressed.emit()
	l.act()
	check(sv.look["hat"] == "crown", "wear a hat")
	l._show_tab("color")
	l.cards[str(LockerData.swatch()[3])].pressed.emit()
	l.act()
	check(sv.look["color"] == LockerData.swatch()[3], "use a colour")
	l._show_tab("class")
	l.cards["bruiser"].pressed.emit()
	l.act()
	check(sv.look["cls"] == "bruiser" and str(root.get_node("Settings").get_value("class")) == "bruiser", "pick a class")
	l._show_tab("emote")
	check(l.cards.has("pirouette") and l.cards["pirouette"].has_node("Lock"), "outfit emotes are shown locked")
	l.cards["dab"].pressed.emit()
	check(l.stage.wobbler().emote_id == "dab", "an emote card plays on the preview")
	check(l.action_state() == "coins" and l.action_b.text.begins_with("Need"), "a locked emote shows its price gap in the Locker")
	l.switch_b.pressed.emit()
	check(l.shop and l.title_l.text == "Shop" and l.tabs() == ["skin", "emote"] and l.cards.size() == LockerData.shop_skins().size(), "Shop: outfits for sale")
	l._show_tab("emote")
	check(l.cards.size() == LockerData.shop_emotes().size() and not l.cards.has("pirouette") and not l.cards.has("wobble"), "Shop: emotes for sale only")
	sv.add_coins(1000)
	l.cards["dab"].pressed.emit(); l.act(); l.buy_confirmed()
	check(sv.owns_emote("dab") and sv.coins == 800 and sv.slots.has("dab"), "buy an emote in the Shop (%d)" % sv.coins)
	l.back_b.pressed.emit()
	check(not l.visible and main.get_node("Safe/Col").visible, "Back returns to the title")
	sv.reset()
	sv._push_settings()
	vp.queue_free()
	await process_frame

func _wheel() -> void:
	var sv: SaveProfile = root.get_node("Save")
	sv.reset()
	sv.add_coins(1000)
	sv.buy("emote", "griddy")
	var st: Node = root.get_node("Settings")
	st.set_value("touch_mode", "on")
	root.size = Vector2i(1170, 540)                # window = canvas, so pushed touches land where they are aimed
	var world: Node = load("res://world/world.tscn").instantiate()
	world.auto_run = false
	world.bot_count = 2
	world.rng_seed = 5
	world.dyn_choice = "off"
	root.add_child(world)
	await process_frame
	for i in 30: world.tick(FRAME)
	var ew = world.emote_wheel
	check(ew.get_index() == world.get_node("UI").get_child_count() - 1, "emote wheel is last in the UI layer")
	check(ew.shown(), "emote button shown in a match")
	var c: Vector2 = ew.button_rect().get_center()
	var t := InputEventScreenTouch.new(); t.index = 3; t.position = c; t.pressed = true
	root.push_input(t)
	check(ew.is_open and not world.touch._touch.has(3), "a touch on the emote button opens the wheel, the touch layer never sees it")
	t = InputEventScreenTouch.new(); t.index = 3; t.position = c; t.pressed = false
	root.push_input(t)
	check(ew.is_open, "the wheel stays open after the finger lifts")
	check(ew._list == sv.wheel_emotes() and ew._list.has("griddy"), "the wheel lists your emotes (%s)" % [ew._list])
	var pos: Vector2 = ew.item_centers()[ew._list.find("griddy")]
	t = InputEventScreenTouch.new(); t.index = 4; t.position = pos; t.pressed = true
	root.push_input(t)
	check(not ew.is_open and world.player_view.wobbler.emote_id == "griddy", "picking an emote dances it on the player's wobbler")
	t = InputEventScreenTouch.new(); t.index = 4; t.position = pos; t.pressed = false
	root.push_input(t)
	var far := InputEventScreenTouch.new(); far.index = 5; far.position = Vector2(200, 300); far.pressed = true
	root.push_input(far)
	check(world.touch._touch.has(5), "other touches still reach the touch layer")
	far = InputEventScreenTouch.new(); far.index = 5; far.position = Vector2(200, 300); far.pressed = false
	root.push_input(far)
	world.player_view.wobbler.stop_emote()
	var k := InputEventKey.new(); k.physical_keycode = KEY_T; k.keycode = KEY_T; k.pressed = true
	root.push_input(k)
	check(world.player_view.wobbler.emote_id == str(sv.slots[0]), "T plays emote slot 1")
	# results panel: coins, K.O.s, unlock progress
	sv.begin_match()
	sv.on_ko(true, false)
	world._reward = sv.finish_match(true, "Classic", "Arena")
	world._show_offline_results(true, "")
	var rw: Node = world._results.find_child("Rewards", true, false)
	check(rw != null and (rw.find_child("Earned", true, false) as Label).text == "+105 coins", "results show the coins earned")
	check((rw.find_child("Next", true, false) as Label).text != "" and rw.find_child("Bar", true, false) != null, "results show the unlock progress")
	check(not ew.shown(), "no emote button over the results")
	world.free()
	st.set_value("touch_mode", "auto")
	sv.reset()
	sv._push_settings()
	await process_frame
