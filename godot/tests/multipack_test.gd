extends SceneTree
## Multi-pack DLC (dlc/pack_registry.gd, DlcUnlock / DlcSave per pack, ArcadeManager / ArcadeCoop per pack, the hub, the title
## showcase, the wizard, Quick Play). Run: npm run test:godot-multipack
## The pack arenas (kitchen_chaos, toy_workshop, backyard_bbq) come from phase C's map generators. While a build does not
## have them, STAND-INS (a copy of the 'arena' entry under the pack's arena id) are registered so the plumbing can still be
## tested, and the tests that need the REAL generator say "SKIP real map" instead of passing silently.

const PACKS := ["construction", "kitchen", "xmas", "australia"]
const NEW_PACKS := ["kitchen", "xmas", "australia"]
const ARENAS := {"kitchen": "kitchen_chaos", "xmas": "toy_workshop", "australia": "backyard_bbq"}
const MODES := {"kitchen": "kitchen", "xmas": "xmas", "australia": "australia"}
const SIZES := [
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(1194, 834), [0.0, 24.0, 0.0, 20.0]],
]
const MIN_TOUCH := 44.0
const MIN_GAP_PT := 8.0
var DU: GDScript          ## autoload users are loaded in _run (a --script registers the autoloads after its own compile)
var SW: GDScript
var QP: GDScript
var AM: GDScript
var fails := 0
var cases := 0
var standins: Array = []
var made: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _sv() -> Node:
	return root.get_node("Save")

func _fresh(coins := 0) -> void:
	_sv().reset()
	_sv().coins = coins

func _profile() -> SaveProfile:
	var s := SaveProfile.new()
	s.persist = false
	made.append(s)
	return s

func _run() -> void:
	DU = load("res://dlc/construction/dlc_unlock.gd")
	SW = load("res://ui/setup_wizard.gd")
	QP = load("res://logic/quick_play.gd")
	AM = load("res://dlc/construction/arcade_manager.gd")
	var content: Node = root.get_node("Content")
	for pk: String in NEW_PACKS:
		if not content.maps.has(ARENAS[pk]):
			var m: Dictionary = (content.maps["arena"] as Dictionary).duplicate(true)
			m["name"] = {"kitchen": "Kitchen Chaos", "xmas": "Toy Workshop", "australia": "Backyard BBQ"}[pk]
			content.maps[ARENAS[pk]] = m
			standins.append(ARENAS[pk])
	if not standins.is_empty(): print("MULTIPACK stand-in arenas (phase C maps not in this tree): %s" % [standins])
	_registry()
	_ownership()
	_migration()
	_wizard_and_quick()
	_gate()
	_tables()
	await _arcade_runs()
	await _hub_flow()
	await _hub_layouts()
	await _showcase()
	for n in made: pass
	print("MULTIPACK %d hub layout cases (3 sizes x 4 packs x locked/owned x 5 languages)" % cases)
	print("MULTIPACK %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------------- registry ----------------

func _registry() -> void:
	check(PackRegistry.ids() == PACKS, "the registry lists the four packs in hub order (%s)" % [PackRegistry.ids()])
	for pk: String in NEW_PACKS:
		check(PackRegistry.mode_of(pk) == MODES[pk] and PackRegistry.pack_of_mode(MODES[pk]) == pk, "%s: its mode" % pk)
		check(PackRegistry.maps(pk) == [ARENAS[pk]], "%s: its arena comes from hub.json" % pk)
		check(PackRegistry.price(pk) == 1500 and PackRegistry.in_wizard(pk), "%s: 1500 coins, listed in the wizard" % pk)
		check(root.get_node("Content").modes.has(MODES[pk]), "%s: the mode is merged" % pk)
	check(not PackRegistry.in_wizard("construction") and PackRegistry.pack_of_mode("classic") == "", "Construction stays hub-only; classic is no pack mode")
	check(ModeRules.maps_for("kitchen") == ["kitchen_chaos"] and ModeRules.maps_for("construction") == ["siteyard", "sitegen"], "ModeRules.maps_for reads the pack data and keeps Construction's list")
	check(not DU.known("nope") and not DU.owned(null, "nope") and not PackRegistry.has(""), "an unknown pack is never owned")

# ---------------- ownership, buying ----------------

func _ownership() -> void:
	var s := _profile()
	for pk: String in PACKS: check(not DU.owned(s, pk), "%s locked by default" % pk)
	check(DU.price("kitchen") == 1500 and DU.price() == 1500 and DU.PRICE == 1500, "1500 coins each")
	s.coins = 1499
	check(not DU.buy(s, "kitchen") and s.coins == 1499 and DU.missing(s, "kitchen") == 1, "1499 coins cannot buy On Fire")
	s.coins = 4000
	check(DU.buy(s, "kitchen") and s.coins == 2500 and DU.owned(s, "kitchen"), "buying On Fire takes 1500 once")
	check(not DU.buy(s, "kitchen") and s.coins == 2500, "a second buy changes nothing")
	check(not DU.owned(s, "xmas") and not DU.owned(s, "australia") and not DU.owned(s, "construction"), "buying one pack owns no other")
	check(DU.buy(s, "xmas") and s.coins == 1000 and not DU.buy(s, "australia") and s.coins == 1000, "Ho Ho Ho bought, Hey Mate refused when short")
	check(not DU.buy(s, "nope") and s.coins == 1000, "an unknown pack cannot be bought")
	check(PackRegistry.owned_ids(s) == ["kitchen", "xmas"], "owned_ids are the bought packs (%s)" % [PackRegistry.owned_ids(s)])
	# the shape Phase B reads: dlc.packs[pack] = {owned, arcade_clears{diff: [ids]}}
	check(s.dlc["packs"]["kitchen"]["owned"] == true and s.dlc["packs"]["kitchen"]["arcade_clears"]["normal"] is Array, "dlc.packs.<pack> = {owned, arcade_clears}")
	DlcSave.mark_cleared(s.dlc, DlcSave.VICTORY, "normal", "kitchen")
	check(DlcSave.won_arcade(s.dlc, "kitchen") and not DlcSave.won_arcade(s.dlc, "xmas") and not DlcSave.won_arcade(s.dlc), "a victory is per pack")
	check(s.dlc["packs"]["kitchen"]["arcade_clears"]["normal"].has("_victory"), "the victory is the stage id _victory under its difficulty")
	var back := _profile()
	check(back.apply_blob(JSON.parse_string(JSON.stringify(s.get_blob()))) and DU.owned(back, "kitchen") and DU.owned(back, "xmas")
		and not DU.owned(back, "australia") and DlcSave.won_arcade(back.dlc, "kitchen"), "ownership and wins survive a save round trip")
	# the developer code owns every pack
	var d := _profile()
	check(DU.redeem_with("x", DU.hash_of("x"), d) == DU.dev_code_allowed(), "dev code accepted in a debug build only")
	if DU.dev_code_allowed():
		for pk: String in PACKS: check(DU.owned(d, pk), "the dev code owns %s" % pk)
	# a purchase the server refuses is rolled back for its pack only
	var r := _profile()
	r.coins = 5000
	DU.buy(r, "xmas")
	DU.buy(r, "kitchen")
	r._wallet_spend_rejected({"kind": "dlc", "key": "xmas"}, {})
	check(not DU.owned(r, "xmas") and DU.owned(r, "kitchen"), "a refused wallet spend un-owns that pack only")

# ---------------- migration ----------------

func _migration() -> void:
	# a save from before the extra packs: Construction owned with Arcade progress, no `v`, no `packs`
	var old := {"owned": true, "bonus": true, "arcade_best": {"easy": 6, "normal": 3, "nightmare": 2},
		"arcade_clears": {"easy": ["tradies", "_victory"], "normal": ["tradies"], "nightmare": []}}
	var c := DlcSave.clean(old)
	check(c["owned"] == true and c["bonus"] == true and c["v"] == DlcSave.VERSION and c["packs"] == {}, "an old-shape save keeps Construction and gains v/packs (%s)" % [c])
	check(DlcSave.best(c, "easy") == 6 and DlcSave.best(c, "normal") == 3 and DlcSave.won_diff(c, "easy") and DlcSave.has_cleared(c, "tradies", "normal"), "its Arcade progress is intact")
	check(not DlcSave.won_arcade(c), "an Easy win alone gives no hat")
	var s := _profile()
	check(s.apply_blob({"v": 1, "wallet": {"coins": 700}, "dlc": old}) and DU.owned(s) and s.coins == 700 and DlcSave.best(s.dlc, "easy") == 6, "an old blob loads with Construction owned")
	for pk: String in NEW_PACKS: check(not DU.owned(s, pk), "...and no new pack owned (%s)" % pk)
	var oldest := DlcSave.clean({"owned": true, "arcade_best": 4, "arcade_clears": ["engineer"]})
	check(oldest["owned"] == true and DlcSave.best(oldest, "nightmare") == 4 and DlcSave.has_cleared(oldest, "engineer", "nightmare"), "the pre-difficulty shape still moves to Nightmare")
	check(DlcSave.is_fresh(DlcSave.clean(null)) and DlcSave.is_fresh(DlcSave.clean({})), "nothing or {} is a fresh dlc")
	# hostile packs: bad ids / types are dropped, the Construction slot cannot be hijacked from `packs`
	var h := DlcSave.clean({"owned": false, "packs": {"Bad Id": {"owned": true}, "construction": {"owned": true}, "kitchen": {"owned": true, "arcade_best": {"easy": 999}}, "x": 5}})
	check(not h["owned"] and not (h["packs"] as Dictionary).has("Bad Id") and not (h["packs"] as Dictionary).has("construction") and h["packs"]["kitchen"]["owned"] == true
		and h["packs"]["kitchen"]["arcade_best"]["easy"] == 99 and not (h["packs"] as Dictionary).has("x"), "a hostile packs table is cleaned")
	check(JSON.stringify(DlcSave.clean(c)) == JSON.stringify(c), "clean() is idempotent (migrating twice is the same)")

# ---------------- wizard, quick play, gates ----------------

func _wizard_and_quick() -> void:
	var sv := _sv()
	_fresh()
	var base: Array = SW.modes()
	for pk: String in NEW_PACKS: check(not base.has(MODES[pk]), "locked: %s is not a wizard game type" % pk)
	check(not QP.modes().has("kitchen"), "locked: Quick Play never rolls a pack mode")
	DlcSave.set_owned(sv.dlc, "kitchen", true)
	check(SW.modes().has("kitchen") and not SW.modes().has("xmas"), "owning On Fire lists only its mode")
	check(QP.modes().has("kitchen") and not QP.modes().has("xmas"), "...in Quick Play too")
	check(SW.maps_for("kitchen") == ["kitchen_chaos"], "the pack mode offers only its arena (%s)" % [SW.maps_for("kitchen")])
	var shown := false
	for sec: Array in SW.sections():
		if (sec[1] as Array).has("kitchen"): shown = true
		check(not (sec[1] as Array).has("xmas"), "no section lists a pack that is not owned")
	check(shown, "the wizard has a section that lists On Fire")
	check(SW.mode_short("kitchen") == "Pans, flames and flying soup" and str(SW.mode_info("kitchen").get("icon")) == "flame", "the mode card line and icon come from wizard.json")
	DlcSave.set_owned(sv.dlc, "kitchen", false)
	check(not SW.modes().has("kitchen"), "losing the pack (a refused spend) hides it again")
	var rng := RandomNumberGenerator.new()
	for i in 200:
		rng.seed = i
		var o: Dictionary = QP.pick(rng)
		check(not PackRegistry.is_pack_mode(str(o["mode"])), "a non-owner's quick match is never a pack mode")
		if fails > 5: break
	DlcSave.set_owned(sv.dlc, "xmas", true)
	var rolled := false
	for i in 400:
		rng.seed = i
		var o2: Dictionary = QP.pick(rng)
		if o2["mode"] == "xmas":
			rolled = true
			check(o2["map"] == "toy_workshop", "a quick Ho Ho Ho match plays its arena (%s)" % o2["map"])
			break
	check(rolled, "an owner's Quick Play can roll Ho Ho Ho")
	_fresh()

func _gate() -> void:
	_fresh()
	check(ModeRules.owned_mode("kitchen") == "classic" and ModeRules.owned_mode("australia") == "classic", "a non-owner's pack mode falls back to classic (saved choice / deep link)")
	check(ModeRules.owned_mode("construction") == "construction" and ModeRules.owned_mode("melee") == "melee", "Construction's mode and normal modes are untouched")
	DlcSave.set_owned(_sv().dlc, "kitchen", true)
	check(ModeRules.owned_mode("kitchen") == "kitchen", "an owner keeps it")
	# the world itself: a non-owner asking for the pack mode plays classic
	_fresh()
	var w: Node = load("res://world/world.tscn").instantiate()
	w.map_id = "kitchen_chaos"
	w.mode_id = "kitchen"
	w.auto_run = false
	root.add_child(w)
	check(w.sim.combat.mode_id == "classic", "World: a non-owner's kitchen start is classic (%s)" % w.sim.combat.mode_id)
	w.queue_free()
	_fresh()
	check(AM.call("launch", 1, "normal", "", null, 1, "kitchen") == null, "a non-owner cannot launch a pack Arcade")
	check(AM.call("launch", 1, "normal", "", null, 1, "nope") == null, "an unknown pack cannot launch")
	var nw: Node = AM.call("launch", 1, "normal")
	check(nw == null, "Construction's Arcade is still gated by its own ownership")
	# the hub refuses too
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.auto_intro = false
	main.auto_news = false
	vp.add_child(main)
	var got: Array = []
	main.hub.start_requested.connect(func(o: Dictionary) -> void: got.append(o))
	main.open_hub("kitchen")
	check(main.hub.pack_id == "kitchen" and main.hub.classic_b.disabled and main.hub.arcade_b.disabled, "the hub opens locked on On Fire")
	main.hub.open_pre()
	main.hub.start()
	check(got.is_empty() and not main.hub.pre.visible, "a locked hub starts nothing")
	vp.queue_free()

# ---------------- stage tables ----------------

func _tables() -> void:
	for pk: String in PACKS:
		check(ArcadeCoop.count(pk) == 6 and ArcadeCoop.difficulties(pk).has("easy") and ArcadeCoop.difficulties(pk).has("normal") and ArcadeCoop.difficulties(pk).has("nightmare"), "%s: 6 stages, 3 difficulties" % pk)
		check(ArcadeCoop.crew_count(0) >= 0 and ArcadeCoop.stage_def(0, pk).get("boss", false) == false and ArcadeCoop.stage_def(1, pk).get("boss", false) == true, "%s: stage 1 is the crew, stage 2 a boss" % pk)
		check(ArcadeCoop.stages(pk).size() == 6 and (ArcadeCoop.stage_def(0, pk).get("bots", []) as Array).size() > 1, "%s: stage 1 spawns a crew" % pk)
		var big := 0
		for i in 6:
			for ev: Dictionary in ArcadeCoop.stage_def(i, pk).get("events", []):
				if float((ev.get("params", {}) as Dictionary).get("giant_scale", 1.0)) == 1.5: big = i + 1
		check(big == 6, "%s: the final boss is the 1.5x Giant (stage %d)" % [pk, big])
	check(ArcadeCoop.mode_id("kitchen") == "kitchen" and ArcadeCoop.mode_id() == "construction", "run mode ids follow the pack")
	check(ArcadeCoop.stages_path("xmas").ends_with("xmas/stages.json") and ArcadeCoop.stages_path().ends_with("construction/stages.json"), "stage paths come from the registry")

# ---------------- Arcade, in a world, per pack ----------------

func _launch(pk: String, stage: int, diff: String) -> Node:
	var w: Node = AM.call("launch", 4242, diff, "", null, 1, pk)
	if w == null: return null
	w.arcade.difficulty_override = "easy"
	w.arcade.fixed_seed = 900
	w.arcade.stage = stage
	w.auto_run = false
	root.add_child(w)
	return w

func _arcade_runs() -> void:
	for pk: String in PACKS:
		_fresh(5000)
		DU.buy(null, pk)
		for pair: Array in [[0, "easy"], [1, "normal"], [5, "nightmare"]]:
			var stage: int = pair[0]
			var diff: String = pair[1]
			var w := _launch(pk, stage, diff)
			check(w != null, "%s: Arcade launches for the owner (stage %d %s)" % [pk, stage + 1, diff])
			if w == null: continue
			for i in 4: await process_frame
			var arc = w.arcade
			var want := ArcadeCoop.stage_def(stage, pk)
			check(arc.pack == pk and w.mode_id == ArcadeCoop.mode_id(pk), "%s: the run knows its pack and mode" % pk)
			check(arc.enemies.size() == (want["bots"] as Array).size(), "%s stage %d: the crew spawned (%d)" % [pk, stage + 1, arc.enemies.size()])
			if bool(want.get("boss", false)):
				check(arc.boss != null, "%s stage %d: a boss spawned" % [pk, stage + 1])
				if stage == 5 and arc.boss != null:
					check(is_equal_approx(arc._giant_scale(want), 1.5), "%s: the final boss is scaled 1.5x" % pk)
			check(AM.get("running") == arc and ArcadeCoop.active == pk, "%s: the run is the active pack" % pk)
			check(arc.diff_def().get("lives") == ArcadeCoop.difficulties(pk)[diff]["lives"], "%s: %s resolves from its own table" % [pk, diff])
			# a clear is saved under THIS pack only
			arc.stage = stage
			var dlc_before := JSON.stringify(_sv().dlc.get("arcade_best"))
			DlcSave.mark_cleared(_sv().dlc, str(want["id"]), diff, pk)
			DlcSave.set_best(_sv().dlc, diff, stage + 1, pk)
			check(DlcSave.best(_sv().dlc, diff, pk) == stage + 1 and (pk == "construction" or JSON.stringify(_sv().dlc.get("arcade_best")) == dlc_before), "%s: progress lands in its own slot" % pk)
			arc.end_run()
			w.queue_free()
			await process_frame
		check(AM.get("running") == null and ArcadeCoop.active == "construction", "%s: the run ends and the default pack returns" % pk)
	if standins.is_empty(): print("MULTIPACK real pack arenas present")
	else: print("MULTIPACK SKIP real map: Arcade ran on stand-in arenas %s; re-run after merging phase C" % [standins])
	# a full-pack pay path on the real pay code: first clear pays once, into the pack's slot
	_fresh(5000)
	DU.buy(null, "kitchen")
	var w2 := _launch("kitchen", 0, "normal")
	for i in 3: await process_frame
	var arc2 = w2.arcade
	var c0: int = _sv().coins
	arc2.stage = 0
	var first: bool = arc2.first_clear()
	check(first, "kitchen: stage 1 is a first clear")
	DlcSave.mark_cleared(_sv().dlc, "line_cooks", "normal", "kitchen")
	check(not arc2.first_clear() and c0 == _sv().coins, "kitchen: marked cleared once")
	arc2.end_run()
	w2.queue_free()
	await process_frame

# ---------------- the hub ----------------

func _main(vp: SubViewport) -> Control:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.auto_intro = false
	main.auto_news = false
	vp.add_child(main)
	return main

func _hub_flow() -> void:
	_fresh(3200)
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	vp.disable_3d = true
	root.add_child(vp)
	var main := _main(vp)
	await process_frame
	await process_frame
	var hub = main.hub
	main.open_hub()
	check(hub.pack_id == "construction" and hub.title_l.text == "Construction" and hub.tabs.get_child_count() == 4, "the hub opens on Construction with four pack badges")
	for pk: String in NEW_PACKS:
		hub.pick_pack(pk)
		await process_frame
		check(hub.pack_id == pk and hub.title_l.text == PackRegistry.display_name(pk) and (hub._tab_bs[pk] as Button).button_pressed, "%s: picked" % pk)
		check(hub.classic_b.disabled and hub.buy_row.visible and hub.buy_b.text.contains("1500"), "%s locked: Buy / Unlock for 1500 coins" % pk)
		var desc := (hub.classic_card.get_node("Margin/Stack/Desc") as Label).text
		check(desc == PackRegistry.text(pk, "classic_desc"), "%s: its own card line" % pk)
		var coins0: int = _sv().coins
		check(hub.buy() and _sv().coins == coins0 - 1500 and hub.pack_owned() and not hub.buy_row.visible, "%s: Buy takes 1500 coins and unlocks" % pk)
		check(not hub.classic_b.disabled and not hub.arcade_b.disabled, "%s owned: Classic and Arcade are usable" % pk)
		check(not hub.buy() and _sv().coins == coins0 - 1500, "%s: a second buy changes nothing" % pk)
		_sv().coins = 3200
		var got: Array = []
		var cb := func(o: Dictionary) -> void: got.append(o)
		hub.start_requested.connect(cb)
		hub.classic_b.pressed.emit()
		check(hub.pre.visible and hub.title_l.text == "Classic" and not hub.pre.get_node("Rows/Seed").visible, "%s: Classic opens the pre-match card without a site seed" % pk)
		hub.start()
		check(got.size() == 1 and got[0]["mode"] == MODES[pk] and got[0]["map"] == ARENAS[pk], "%s: Start asks for its mode and arena (%s)" % [pk, got])
		hub.start_requested.disconnect(cb)
		hub.back()
		var taps := [0]
		var tc := func() -> void: taps[0] += 1
		hub.arcade_requested.connect(tc)
		hub.arcade_b.pressed.emit()
		check(hub.arc_step == 1, "%s: Arcade opens the class step" % pk)
		hub.arcade_next()
		for d: String in ["easy", "normal", "nightmare"]: hub.pick_diff(d)
		hub.arcade_next()
		check(taps[0] == 1 and hub.pack_id == pk, "%s: Start hands over to main.play_arcade for this pack" % pk)
		hub.arcade_requested.disconnect(tc)
		hub.back()
		hub.back()
	hub.pick_pack("construction")
	check(hub.classic_b.disabled and hub.pack_id == "construction", "buying the new packs left Construction locked")
	# open_pack / deep link: a pack the registry does not have opens Construction
	hub.close()
	main.open_hub("nope")
	check(hub.pack_id == "construction", "an unknown pack opens Construction")
	vp.queue_free()
	await process_frame

# layout at phone and tablet sizes, safe areas, touch targets, text, in en / fr / ja
func _hub_layouts() -> void:
	for loc: String in ["en", "fr", "es", "zh_TW", "ja"]:
		if loc != "en": root.get_node("Lang").apply(loc)
		for sz: Array in SIZES:
			for pk: String in PACKS:
				for owned: bool in [false, true]:
					await _layout_case(sz[0], sz[1], pk, owned, loc)
	root.get_node("Lang").apply("en")
	SafeArea.override = []

func _layout_case(win: Vector2, ins_pt: Array, pk: String, owned: bool, loc: String) -> void:
	var cs := UiScale.canvas_size(win, "normal", true)
	var k := cs.x / win.x
	var ins := [ins_pt[0] * k, ins_pt[1] * k, ins_pt[2] * k, ins_pt[3] * k]
	SafeArea.override = ins
	cases += 1
	var tag := "%dx%d %s %s %s" % [win.x, win.y, pk, "owned" if owned else "locked", loc]
	_fresh(2300)
	if owned: DlcSave.set_owned(_sv().dlc, pk, true)
	var vp := SubViewport.new()
	vp.size = Vector2i(cs)
	vp.disable_3d = true
	root.add_child(vp)
	var main := _main(vp)
	main.browser.auto_refresh = false
	main.open_hub(pk)
	for i in 5: await process_frame
	var hub = main.hub
	var safe := Rect2(Vector2(ins[0], ins[1]), cs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	check(hub.col.get_combined_minimum_size().y <= safe.size.y + 0.5, "%s column min height %.0f fits %.0f" % [tag, hub.col.get_combined_minimum_size().y, safe.size.y])
	var all: Array = []
	_gather(hub, all)
	var items: Array = []
	for c: Control in all:
		if c is BaseButton:
			var r := c.get_global_rect()
			check(r.size.x > 0.0, "%s '%s' visible" % [tag, _nm(c)])
			if r.size.x <= 0.0: continue
			items.append([c, r])
			check(safe.grow(0.5).encloses(r), "%s '%s' %s inside the safe area" % [tag, _nm(c), r])
			check(minf(r.size.x, r.size.y) >= MIN_TOUCH * k - 0.5, "%s '%s' touch target %.1f pt" % [tag, _nm(c), minf(r.size.x, r.size.y) / k])
	for i in items.size():
		for j in range(i + 1, items.size()):
			var a: Control = items[i][0]
			var b: Control = items[j][0]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a): continue
			check(_gap(items[i][1], items[j][1]) >= MIN_GAP_PT * k - 0.6, "%s '%s' / '%s' too close" % [tag, _nm(a), _nm(b)])
	for c: Control in all:
		if c is Label and c.text != "":
			var l := c as Label
			if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
				check(l.size.y + 0.5 >= l.get_line_count() * l.get_line_height(), "%s '%s' wraps taller than its box" % [tag, l.text])
			else:
				check(l.size.x + 0.5 >= l.get_minimum_size().x, "%s '%s' squeezed" % [tag, l.text])
			var holder := _button_above(c)
			if holder != null: check(holder.get_global_rect().grow(1.0).encloses(c.get_global_rect()), "%s '%s' sticks out of its card" % [tag, l.text])
		elif c is Button and c.text != "" and not c.text.contains("\n"):
			var f := c.get_theme_font("font")
			var w := f.get_string_size(c.text, HORIZONTAL_ALIGNMENT_LEFT, -1, c.get_theme_font_size("font_size")).x
			check(w <= c.size.x - 8.0, "%s button '%s' text is tight" % [tag, c.text])
	for card: Button in [hub.classic_card, hub.arcade_card]:
		var st := card.get_node("Margin/Stack") as Control
		check(st.get_combined_minimum_size().y <= card.size.y - 2.0 * UiTheme.SP_3 + 0.5, "%s card '%s' words fit the card" % [tag, card.name])
	vp.queue_free()
	await process_frame

func _gather(n: Node, out: Array) -> void:
	for c in n.get_children():
		if not (c is Control) or not (c as Control).is_visible_in_tree(): continue
		out.append(c)
		_gather(c, out)

func _nm(c: Control) -> String:
	var t: Variant = c.get("text")
	return str(t) if t != null and str(t) != "" else str(c.name)

func _gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(maxf(a.position.x - b.end.x, b.position.x - a.end.x), 0.0)
	var dy := maxf(maxf(a.position.y - b.end.y, b.position.y - a.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)

func _button_above(c: Control) -> Button:
	var p := c.get_parent()
	while p != null:
		if p is Button: return p as Button
		p = p.get_parent()
	return null

# ---------------- the title showcase ----------------

func _showcase() -> void:
	_fresh(0)
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	root.add_child(vp)
	var main := _main(vp)
	for i in 3: await process_frame
	var sc = main.showcase
	var ids: Array = []
	for p in sc.packs: ids.append(p.pack_id)
	check(ids == PACKS, "the showcase lists the four packs in order (%s)" % [ids])
	var got_play: Array = []
	var got_unlock: Array = []
	sc.play_requested.connect(func(p: Variant) -> void: got_play.append(p.pack_id))
	sc.unlock_requested.connect(func(p: Variant) -> void: got_unlock.append(p.pack_id))
	sc.speed = 50.0
	sc.snap(true)
	for pk: String in PACKS:
		var i := ids.find(pk)
		sc.index = i
		sc._swap_to(i)
		sc.snap(true)
		await process_frame
		var p = sc.pack()
		check(p.pack_id == pk and sc.stage.weapon_ids.size() == 6 or pk == "construction", "%s: its container shows the weapons" % pk)
		check(sc.badge.kind == p.badge_kind() and sc.badge.kind != "", "%s: the header badge is %s" % [pk, sc.badge.kind])
		check(sc.unlock_b.visible and not sc.play_b.visible, "%s locked: UNLOCK PACK" % pk)
		check(sc.site_b.visible == (pk == "construction"), "%s: the DON'T ENTER sign is Construction's only" % pk)
		sc.unlock_b.pressed.emit()
		check(got_unlock.back() == pk, "%s: UNLOCK PACK asks for this pack's hub" % pk)
		DlcSave.set_owned(_sv().dlc, pk, true)
		sc.refresh()
		await process_frame
		check(not sc.unlock_b.visible and (sc.play_b.visible == (pk != "construction")) and (sc.owned_chip.visible == (pk == "construction")), "%s owned: PLAY / OWNED" % pk)
		if pk != "construction":
			sc.play_b.pressed.emit()
			check(got_play.back() == pk, "%s: PLAY opens its hub" % pk)
		# touch targets and the safe frame
		var f: Rect2 = Rect2(Vector2.ZERO, sc.size)
		for b: Button in [sc.back_b, sc.prev_b, sc.next_b, sc.test_b, sc.play_b if sc.play_b.visible else sc.unlock_b]:
			if b.visible: check(b.size.x >= 40.0 and b.size.y >= 40.0 and f.encloses(Rect2(b.global_position, b.size)), "%s: '%s' is a touch target inside the stage" % [pk, b.text])
	# swiping and the buttons cycle
	sc.index = 0
	sc._swap_to(0)
	sc.snap(true)
	sc.swap(1)
	await sc.state_changed
	for i in 40:
		if sc.state == sc.State.OPENED: break
		await process_frame
	check(sc.pack().pack_id == "kitchen", "SWAP PACK > goes to the next pack (%s)" % sc.pack().pack_id)
	sc.swap(-1)
	for i in 80:
		if sc.state == sc.State.OPENED and sc.pack().pack_id == "construction": break
		await process_frame
	check(sc.pack().pack_id == "construction", "SWAP PACK < goes back")
	vp.queue_free()
	await process_frame
