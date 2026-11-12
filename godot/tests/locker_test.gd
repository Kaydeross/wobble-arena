extends SceneTree
## Locker / Shop / emotes test (headless): buy and equip rules (autoload/save.gd), the Locker / Shop screen flow
## (ui/locker.gd: try on, buy with a confirm, not enough coins, wear, emote preview), the Wobbler emotes
## (actors/emote_poses.gd: every emote poses finite values, ends on time, stops on a swing, hides the weapon), and the
## in-match emote button (ui/emote_wheel.gd: a touch on it opens the wheel and does not reach the touch layer, a pick
## dances, T plays slot 1) plus the results panel rewards. Also the Godot-only classes (logic/extra_classes.gd: paid and
## secret ones, their unlocks, the Class tab) and every look the Locker preview can show (_previews: each outfit on each
## class, each hat on each class, the hat cards) builds a whole character: head, torso, legs and arms that sit on the
## body, and the auto-fitted camera keeps all of it in the shot.
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
	_class_rules()
	_emotes()
	await _screen()
	await _previews()
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

func _class_rules() -> void:
	var s := SaveProfile.new()
	s.persist = false
	var all: Dictionary = WobblerLooks.data("classes")
	check(all.has("tank") and all.has("ghost") and (load("res://autoload/content.gd").load_json("classes") as Dictionary).size() == 5, "extra classes merged, shared data untouched")
	var c := Combat.new()
	c.load_content()
	check(c.classes.has("tank") and c.classes["tank"]["hp"] == ExtraClasses.data()["tank"]["hp"], "Combat sees the extra classes")
	c.dispose()
	for id in ["wobbler", "bruiser", "kid", "elder", "alien"]: check(s.owns_class(id), "shared class %s is free" % id)
	var paid := 0
	var secret := 0
	for id: String in ExtraClasses.data():
		var d: Dictionary = ExtraClasses.data()[id]
		for k in ["hp", "spd", "acc", "air", "jump", "kb", "dmg", "rate", "reload", "ammo", "wob", "size", "head", "wide"]:
			check(d.has(k) and float(d[k]) > 0.3 and float(d[k]) < 2.5, "class %s has a sane %s" % [id, k])
		check(not s.owns_class(id), "%s starts locked" % id)
		if ExtraClasses.price(id) > 0: paid += 1
		if ExtraClasses.is_hidden(id):
			secret += 1
			check(not ExtraClasses.unlock(id).is_empty(), "%s has an unlock goal" % id)
	check(paid >= 2 and secret >= 2, "paid (%d) and secret (%d) classes" % [paid, secret])
	check(not s.set_class("tank") and s.look["cls"] == "wobbler", "a locked class cannot be picked")
	check(s.buy_check("class", "tank") == "coins" and s.buy_check("class", "ghost") == "not_for_sale", "paid needs coins, secret is not for sale")
	s.add_coins(1000)
	check(s.buy("class", "tank") == "ok" and s.coins == 0 and s.owns_class("tank") and s.look["cls"] == "tank", "buy a class: paid, picked")
	check(s.buy("class", "tank") == "owned", "cannot buy a class twice")
	s.stats["matches"] = 9
	check(not s.owns_class("ghost") and s.class_progress("ghost") == 9, "secret: 9 of 10 matches")
	s.begin_match()
	var r := s.finish_match(false)
	check(s.owns_class("ghost") and s.set_class("ghost") and r.get("classes", []) == ["ghost"], "the 10th match unlocks Boo and the results say so (%s)" % [r.get("classes")])
	s.begin_match()
	check(not s.finish_match(true).has("classes"), "announced once")
	var b := s.get_blob()
	check(b["wallet"]["classes"] == ["tank"], "bought classes are saved")
	var s2 := SaveProfile.new()
	s2.persist = false
	check(s2.apply_blob(b) and s2.owns_class("tank") and s2.owns_class("ghost") and s2.look["cls"] == "ghost", "a loaded save keeps classes and the secret pick")
	b["stats"]["matches"] = 0
	check(s2.apply_blob(b) and s2.look["cls"] == "wobbler", "a secret class not unlocked in the save falls back")
	s.free(); s2.free()

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
	check(l.cards.has("tank") and l.cards["tank"].has_node("Lock") and str((l.cards["tank"].find_child("L", true, false) as Label).text) == str(ExtraClasses.price("tank")), "paid class: padlock and price")
	check((l.cards["ghost"].find_child("Name", true, false) as Label).text == "???" and l.cards["ghost"].find_child("Art", true, false).modulate == l.SILHOUETTE, "secret class: ??? silhouette")
	l.cards["ghost"].pressed.emit()
	check(l.preview_tr.modulate == l.SILHOUETTE and l.action_b.text == "Secret" and not l.action_b.disabled and l.info_l.text.contains("Play 10 matches · 0/10"), "secret class preview is a silhouette with its goal (%s)" % l.info_l.text)
	l.act()
	check(l.msg_l.text.contains("Play 10 matches"), "tapping a secret class says how to unlock it")
	l.cards["dash"].pressed.emit()
	check(l.preview_tr.modulate == Color.WHITE and l.action_state() == "coins", "paid class you cannot afford yet")
	sv.add_coins(1200)
	l.act()
	check(l.confirm.visible and l.buy_confirmed() == "ok" and sv.look["cls"] == "dash" and sv.owns_class("dash"), "buy a class in the Locker")
	l._show_tab("color")
	check(l.tab_bs["color"].text == "Colour" and l.sub_l.text.contains("no outfit"), "the Colour tab says what it is for")
	l.cards[str(LockerData.swatch()[2])].pressed.emit()
	check(l.stage.wobbler().skin_key == "none" and l.info_l.text.contains("Hidden under"), "colour preview takes the outfit off (%s)" % l.info_l.text)
	l._show_tab("emote")
	check(l.cards.has("pirouette") and l.cards["pirouette"].has_node("Lock"), "outfit emotes are shown locked")
	var icons := 0
	for k: String in l.cards:
		if l.cards[k].find_child("Art", true, false) is EmoteIcon: icons += 1
	check(icons == l.cards.size(), "every emote card has an icon (%d / %d)" % [icons, l.cards.size()])
	for id: String in LockerData.all_emotes(): check(EmoteIcon.GLYPHS.has(id), "emote %s has its own glyph" % id)
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

## Every outfit on every class, every hat on every class, and the hat cards: the Locker preview builds a whole
## character (head, torso, legs, arms attached), and the fitted camera has all of it in view.
func _previews() -> void:
	var sv: SaveProfile = root.get_node("Save")
	sv.reset()
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await process_frame
	main.open_locker(false, "skin")
	var st = main.locker.stage
	var bad := 0
	var n := 0
	var classes: Array = WobblerLooks.data("classes").keys()
	for cl: String in classes:
		for sk: String in ["none"] + LockerData.all_skins():
			st.preview({"cls": cl, "skin": sk, "hat": "none", "color": WobblerLooks.DEFAULT_COLOR})
			n += 1
			var why: String = _whole(st, "body")
			if why != "":
				_bad(bad, "preview %s / %s: %s" % [cl, sk, why])
				bad += 1
		for h: String in LockerData.hats():
			st.preview({"cls": cl, "skin": "none", "hat": h, "color": WobblerLooks.DEFAULT_COLOR})
			n += 1
			var why: String = _whole(st, "body")
			if why == "" and h != "none":
				var w: Wobbler = st.wobbler()
				if w.hat == null or not w.hat.visible or w.hat.find_children("*", "MeshInstance3D", true, false).is_empty(): why = "hat not built"
			if why != "":
				_bad(bad, "preview %s / hat %s: %s" % [cl, h, why])
				bad += 1
	for h: String in LockerData.hats():                    # the Hats tab cards (head close-up)
		var be: Array = main.locker.bake_entry("hat", h)
		st.looks[be[0]] = be[1]
		st.pose(be[0], 0.0)
		n += 1
		var why: String = _in_view(st, "head")
		if why != "":
			_bad(bad, "hat card %s: %s" % [h, why])
			bad += 1
	check(bad == 0, "%d of %d previews incomplete" % [bad, n])
	main.close_locker()
	vp.queue_free()
	await process_frame

func _bad(count: int, what: String) -> void:            # print the first few, the total is checked after
	if count < 12: check(false, what)
	else: fails += 1

## "" when the stage's wobbler is a whole character and fully in the camera's view, else what is wrong.
func _whole(st, frame: String) -> String:
	var w: Wobbler = st.wobbler()
	var vis := func(n: Node) -> bool: return n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree()
	var boxes: Array = []                                  # [node, global AABB] of every visible mesh
	for mi: MeshInstance3D in w.find_children("*", "MeshInstance3D", true, false):
		if vis.call(mi): boxes.append([mi, mi.global_transform * mi.mesh.get_aabb()])
	var head_c := w.neck.global_transform * Vector3(0, 0.32, 0)
	var torso_c := w.body.global_transform * Vector3(0, 0.425, 0)
	var head := false
	var torso := false
	for b: Array in boxes:
		var bb: AABB = (b[1] as AABB).grow(0.02)
		if bb.has_point(head_c): head = true
		if bb.has_point(torso_c): torso = true
	if not head: return "no head"
	if not torso: return "no torso"
	for l: Node3D in w.legs:
		if not vis.call(l.get_node("Thigh")): return "missing leg"
	for sh: Node3D in [w.arm_l, w.shoulder]:               # arms sit on the body, not floating next to it
		var p := sh.global_position
		var near := INF
		for b: Array in boxes:
			var mi: Node = b[0]
			if w.arm_l.is_ancestor_of(mi) or w.arm.is_ancestor_of(mi) or w.legs[0].is_ancestor_of(mi) or w.legs[1].is_ancestor_of(mi): continue
			var bb: AABB = b[1]
			near = minf(near, (p.clamp(bb.position, bb.end) - p).length())
		if near > 0.3: return "arm floats %.2f from the body" % near
	return _in_view(st, frame)

func _in_view(st, frame: String) -> String:
	var cam := st.get_node("Cam") as Camera3D
	var b: Array = st.model_bounds(frame)
	var pv: Node3D = st.get_node("Pivot")
	for yaw: float in [0.0, PI / 2.0, PI]:
		for p: Vector3 in [Vector3(0, b[0], 0), Vector3(0, b[1], 0), Vector3(b[2], (b[0] + b[1]) * 0.5, 0), Vector3(-b[2], b[1], 0)]:
			var g := pv.global_transform.origin + p.rotated(Vector3.UP, yaw)
			if not cam.is_position_in_frustum(g): return "cut off at %s (bounds %s)" % [p, b]
	return ""

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
