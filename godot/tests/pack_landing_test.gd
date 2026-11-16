extends SceneTree
## Pack landing pages (ui/pack_landing.gd, pack_landing_scene.gd, pack_landing_stage.gd, pack_landing_arena.gd; data/extra/<pack>/landing.json).
## Run: npm run test:godot-pack-landing
## For all four packs: the landing builds (script errors fail the runner), leaves no orphan nodes behind, its texts exist in all five languages,
## the weapon showcase lists exactly the pack's weapons and cycles, there is exactly ONE SubViewport (the stage) and never more, the particle
## total stays inside PLS.PARTICLE_CAP, the lowest graphics tier has no particles and no animation, headless builds neither stage
## nor particles, and the hub with its landing page lays out at 667x375, 812x375, 852x393, 926x428 and 1024x768 with safe areas, locked and owned,
## in en / fr / es / zh_TW / ja: touch targets >= 44 pt, no clipped text, nothing sticking out of its card, the buttons reachable.

const PACKS := ["construction", "kitchen", "xmas", "australia"]
const NEW_PACKS := ["kitchen", "xmas", "australia"]
const ARENAS := {"kitchen": "kitchen_chaos", "xmas": "toy_workshop", "australia": "backyard_bbq"}
const WEAPONS := {
	"construction": ["pipewrench", "nailgun", "jackhammer", "spiritlevel", "tapemeasure", "cementbucket", "conelauncher", "anglegrinder", "drill"],
	"kitchen": ["fryingpan", "cleaver", "flambetorch", "rollingpin", "peppergrinder", "souppot"],
	"xmas": ["candycane", "snowballcannon", "giftbomb", "tinselwhip", "ornamentlauncher", "toymallet"],
	"australia": ["cricketbat", "aussieboomerang", "thongslapper", "vegemitejar", "bbqtongs", "didgeridooblaster"],
}
const LANGS := ["en", "fr", "es", "zh_TW", "ja"]
const SIZES := [
	[Vector2(667, 375), [0.0, 0.0, 0.0, 0.0]],
	[Vector2(812, 375), [44.0, 0.0, 44.0, 21.0]],
	[Vector2(852, 393), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(926, 428), [59.0, 0.0, 59.0, 21.0]],
	[Vector2(1024, 768), [0.0, 24.0, 0.0, 20.0]],
]
const MIN_TOUCH := 44.0
const MIN_GAP_PT := 8.0
var fails := 0
var cases := 0
var shown_cases := 0
var hidden_cases: Array = []
var dropped := {}         ## "WxH locked|owned lang" -> how many text pieces the band had to leave out at a readable size
var band_h := {}          ## "WxH locked|owned" -> the smallest band height (canvas px) seen
var standins: Array = []
var PL: GDScript          ## the landing scripts are loaded in _run (a --script registers the autoloads after its own compile)
var PLS: GDScript
var PLSTAGE: GDScript
var C: Node

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

func _run() -> void:
	PL = load("res://ui/pack_landing.gd")
	PLS = load("res://ui/pack_landing_scene.gd")
	PLSTAGE = load("res://ui/pack_landing_stage.gd")
	C = root.get_node("Content")
	var content: Node = C
	for pk: String in NEW_PACKS:
		if not content.maps.has(ARENAS[pk]):
			var m: Dictionary = (content.maps["arena"] as Dictionary).duplicate(true)
			m["name"] = {"kitchen": "Kitchen Chaos", "xmas": "Toy Workshop", "australia": "Backyard BBQ"}[pk]
			content.maps[ARENAS[pk]] = m
			standins.append(ARENAS[pk])
	if not standins.is_empty(): print("PACKLANDING stand-in arenas (the pack map generators are not in this tree): %s" % [standins])
	_data_and_texts()
	await _builds_and_orphans()
	await _fx_budget()
	await _layouts()
	root.get_node("Lang").apply("en")
	SafeArea.override = []
	print("PACKLANDING %d layout cases (%d with the full hero band, %d with the one-row band: %s)" % [cases, shown_cases, hidden_cases.size(), hidden_cases.slice(0, 4)])
	print("PACKLANDING band height (canvas px, smallest over packs and languages; the full band needs %d): %s" % [int(PL.MIN_H), band_h])
	print("PACKLANDING pieces left out at a readable size (sum over the four packs): %s" % [dropped])
	print("PACKLANDING %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------------- data and languages ----------------

func _data_and_texts() -> void:
	for pk: String in PACKS:
		var d: Dictionary = PL.load_data(pk)
		check(not d.is_empty(), "%s has a landing.json" % pk)
		check(str(d.get("backdrop", "")) == pk, "%s backdrop kind is its id" % pk)
		check((d.get("features", []) as Array).size() == 3, "%s has three features" % pk)
		var ids: Array = PL.weapon_ids(pk)
		check(ids == WEAPONS[pk], "%s showcase lists exactly its weapons: %s" % [pk, ids])
		var roles: Dictionary = d.get("weapon_roles", {})
		for id: String in WEAPONS[pk]:
			check(roles.has(id), "%s has a role line for %s" % [pk, id])
			check(C.weapons.has(id), "%s weapon %s exists" % [pk, id])
		for k: String in roles: check(WEAPONS[pk].has(k), "%s role line %s is a weapon of the pack" % [pk, k])
		var pal: Dictionary = PL.pal(d)
		for k: String in ["top", "bottom", "glow", "card"]: check(pal.has(k), "%s palette has %s" % [pk, k])
	for loc: String in LANGS:
		root.get_node("Lang").apply(loc)
		for pk: String in PACKS:
			var d: Dictionary = PL.load_data(pk)
			for key: String in PL.texts_of(d):
				var tx := TranslationServer.translate(key)
				check(tx != "", "%s %s: '%s' translates" % [pk, loc, key])
				if loc != "en":
					var same_ok := key == str(d.get("headline", "")) or key.begins_with("Ho Ho")    # a brand word may stay as it is
					check(tx != key or same_ok, "%s %s: '%s' has a %s translation" % [pk, loc, key, loc])
			for id: String in WEAPONS[pk]:
				var nm := str((C.weapons[id] as Dictionary).get("name", id))
				if loc != "en": check(TranslationServer.translate(nm) != nm, "%s %s: weapon name '%s' translates" % [pk, loc, nm])
	root.get_node("Lang").apply("en")

# ---------------- build, free, orphans, showcase ----------------

func _main(vp: SubViewport) -> Control:
	var main: Control = load("res://scenes/main.tscn").instantiate()
	main.auto_intro = false
	main.auto_news = false
	vp.add_child(main)
	return main

func _vp(cs: Vector2) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(cs)
	vp.disable_3d = true
	root.add_child(vp)
	return vp

func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

func _count_vp(n: Node) -> int:
	return n.find_children("*", "SubViewport", true, false).size()

func _builds_and_orphans() -> void:
	PL.force_fx = true
	_fresh(2300)
	var base := -1
	for round in 2:
		for pk: String in PACKS:
			var vp := _vp(Vector2(1170, 540))
			var main := _main(vp)
			main.browser.auto_refresh = false
			main.open_hub(pk)
			for i in 6: await process_frame
			var hub = main.hub
			var l = hub.landing
			check(l != null and l.pack_id == pk, "%s: the hub has its landing page" % pk)
			check(l.weapons == WEAPONS[pk], "%s: landing weapons %s" % [pk, l.weapons])
			check(l.stage_count() == 1 and _count_vp(hub) == 1, "%s: exactly one SubViewport in the hub (%d)" % [pk, _count_vp(hub)])
			check(l.stage.weapon_id == WEAPONS[pk][0], "%s: the stage shows the first weapon" % pk)
			check(l.stage.size.x > 0 and l.stage.render_target_update_mode != SubViewport.UPDATE_DISABLED or not PLSTAGE.renders(), "%s: the stage is set up" % pk)
			# the weapon showcase cycles through every weapon and wraps
			var seen: Array = []
			for k in WEAPONS[pk].size():
				seen.append(l.current_weapon())
				check(l.stage.weapon_id == l.current_weapon(), "%s: stage follows %s" % [pk, l.current_weapon()])
				var wd: Dictionary = C.weapons[l.current_weapon()]
				check(l.w_name.text == tr(str(wd.get("name", ""))), "%s: caption names %s" % [pk, l.current_weapon()])
				check(l.w_role.text != "", "%s: caption has a role line for %s" % [pk, l.current_weapon()])
				l.stage_btn.pressed.emit()
				await process_frame
			check(seen == WEAPONS[pk], "%s: tapping cycles through all weapons in order: %s" % [pk, seen])
			check(l.current_weapon() == WEAPONS[pk][0], "%s: the cycle wraps" % pk)
			l.cycle(-1)
			check(l.current_weapon() == WEAPONS[pk][WEAPONS[pk].size() - 1], "%s: previous wraps backwards" % pk)
			# switching packs by the header tabs keeps ONE SubViewport and rebuilds the page for the new pack
			for other: String in PACKS:
				hub.pick_pack(other)
				for i in 3: await process_frame
				check(l.pack_id == other and _count_vp(hub) == 1, "%s -> %s: one SubViewport, page switched" % [pk, other])
				check(l.weapons == WEAPONS[other], "%s -> %s: weapons switched" % [pk, other])
			# the arena thumbnail is built once, from the arena's boxes
			hub.pick_pack(pk)
			for i in 3: await process_frame
			l._build_arena()
			check(l.arena.box_count() > 5, "%s: the arena thumbnail has boxes (%d)" % [pk, l.arena.box_count()])
			# covered / hidden: nothing runs
			hub.visible = false
			for i in 3: await process_frame
			check(l.stage.render_target_update_mode == SubViewport.UPDATE_DISABLED, "%s: the stage stops rendering while the hub is hidden" % pk)
			check(not l.scene.is_processing(), "%s: the backdrop stops while the hub is hidden" % pk)
			for p: CPUParticles2D in l.scene.particle_nodes(): check(not p.emitting, "%s: particles stop while hidden" % pk)
			hub.visible = true
			vp.queue_free()
			await process_frame
			await process_frame
		if round == 0: base = _orphans()
	await process_frame
	var after := _orphans()
	check(after <= base, "no orphan nodes left behind by the landing pages (%d -> %d)" % [base, after])
	PL.force_fx = false

# ---------------- budgets, tiers, headless ----------------

func _fx_budget() -> void:
	var st: Node = root.get_node("Settings")
	var old: Variant = st.get_value("fx_quality", "auto")
	_fresh(2300)
	for tier: String in ["auto", "medium", "low"]:
		st.set_value("fx_quality", tier)
		for fx: bool in [true, false]:
			PL.force_fx = fx
			for pk: String in PACKS:
				var vp := _vp(Vector2(1170, 540))
				var main := _main(vp)
				main.browser.auto_refresh = false
				main.open_hub(pk)
				for i in 4: await process_frame
				var l = main.hub.landing
				var n: int = l.particle_total()
				var tag := "%s tier %s fx %s" % [pk, tier, fx]
				check(n <= PLS.PARTICLE_CAP, "%s: %d particles <= %d" % [tag, n, PLS.PARTICLE_CAP])
				check(_count_vp(main.hub) <= 1, "%s: at most one SubViewport" % tag)
				if tier == "low":
					check(n == 0 and l.scene.particle_nodes().is_empty(), "%s: the lowest tier has no particles (%d)" % [tag, n])
					check(not l.scene.animate and not l.scene.is_processing(), "%s: the lowest tier draws a still backdrop" % tag)
					if l.stage != null: check(not l.stage.spin, "%s: the lowest tier does not spin the stage" % tag)
				elif fx:
					check(n > 0, "%s: the page has particles" % tag)
					check(l.scene.animate, "%s: the backdrop animates" % tag)
				if not fx:
					check(n == 0 and l.stage_count() == 0 and _count_vp(main.hub) == 0, "%s: headless builds no stage and no particles" % tag)
					check(l.weapons == WEAPONS[pk] and l.headline.text != "", "%s: headless keeps the layout nodes and texts" % tag)
				vp.queue_free()
				await process_frame
	st.set_value("fx_quality", old)
	PL.force_fx = false

# ---------------- layout ----------------

func _layouts() -> void:
	PL.force_fx = true
	for loc: String in LANGS:
		if loc != "en": root.get_node("Lang").apply(loc)
		for sz: Array in SIZES:
			for pk: String in PACKS:
				for owned: bool in [false, true]:
					await _layout_case(sz[0], sz[1], pk, owned, loc)
	PL.force_fx = false

func _layout_case(win: Vector2, ins_pt: Array, pk: String, owned: bool, loc: String) -> void:
	var cs := UiScale.canvas_size(win, "normal", true)
	var k := cs.x / win.x
	var ins := [ins_pt[0] * k, ins_pt[1] * k, ins_pt[2] * k, ins_pt[3] * k]
	SafeArea.override = ins
	cases += 1
	var tag := "%dx%d %s %s %s" % [win.x, win.y, pk, "owned" if owned else "locked", loc]
	_fresh(2300)
	if owned: DlcSave.set_owned(_sv().dlc, pk, true)
	var vp := _vp(cs)
	var main := _main(vp)
	main.browser.auto_refresh = false
	main.open_hub(pk)
	for i in 5: await process_frame
	var hub = main.hub
	var l = hub.landing
	var safe := Rect2(Vector2(ins[0], ins[1]), cs - Vector2(ins[0] + ins[2], ins[1] + ins[3]))
	check(hub.col.get_combined_minimum_size().y <= safe.size.y + 0.5, "%s column min height %.0f fits %.0f" % [tag, hub.col.get_combined_minimum_size().y, safe.size.y])
	check(_count_vp(hub) == 1, "%s one SubViewport" % tag)
	check(l.particle_total() <= PLS.PARTICLE_CAP, "%s particles" % tag)
	var bk := "%dx%d %s" % [win.x, win.y, "owned" if owned else "locked"]
	band_h[bk] = minf(float(band_h.get(bk, 9999.0)), l.size.y)
	if l.shown: shown_cases += 1
	else: hidden_cases.append(tag)
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
			var lb := c as Label
			if lb.autowrap_mode != TextServer.AUTOWRAP_OFF:
				check(lb.size.y + 0.5 >= lb.get_line_count() * lb.get_line_height(), "%s '%s' wraps taller than its box" % [tag, lb.text])
			else:
				check(lb.size.x + 0.5 >= lb.get_minimum_size().x, "%s '%s' squeezed" % [tag, lb.text])
			var holder := _button_above(c)
			if holder != null: check(holder.get_global_rect().grow(1.0).encloses(c.get_global_rect()), "%s '%s' sticks out of its card" % [tag, lb.text])
		elif c is Button and c.text != "" and not c.text.contains("\n"):
			var f := c.get_theme_font("font")
			var w := f.get_string_size(c.text, HORIZONTAL_ALIGNMENT_LEFT, -1, c.get_theme_font_size("font_size")).x
			check(w <= c.size.x - 8.0, "%s button '%s' text is tight" % [tag, c.text])
	for card: Button in [hub.classic_card, hub.arcade_card]:
		var st := card.get_node("Margin/Stack") as Control
		check(st.get_combined_minimum_size().y <= card.size.y - 2.0 * UiTheme.SP_3 + 0.5, "%s card '%s' words fit the card" % [tag, card.name])
	if l.shown:
		var miss := 0
		if not l.tagline.visible: miss += 1
		if not l.w_role.visible: miss += 1
		for f: Label in l.feats:
			if not f.visible: miss += 1
		if miss > 0: dropped["%dx%d %s %s" % [win.x, win.y, "owned" if owned else "locked", loc]] = int(dropped.get("%dx%d %s %s" % [win.x, win.y, "owned" if owned else "locked", loc], 0)) + miss
	_landing_checks(l, tag, k)
	vp.queue_free()
	await process_frame

## The hero band itself: every piece inside the band, nothing overlapping, text not clipped, fonts readable.
func _landing_checks(l, tag: String, k: float) -> void:
	var band := Rect2(Vector2.ZERO, l.size)
	check(l.get_combined_minimum_size().y <= 0.5, "%s the band asks for no height of its own" % tag)
	if not l.shown and not l.mini: return
	var pieces: Array = []
	for c: Control in l.content:
		if not c.visible or c == l.glass or c == l.dots or c == l.fg: continue
		var r := Rect2(c.position, c.size)
		check(band.grow(0.5).encloses(r), "%s band piece '%s' %s inside the band %s" % [tag, c.name, r, band])
		if c is Label:
			var lb := c as Label
			if lb.text == "": continue
			check(lb.get_theme_font_size("font_size") >= UiTheme.MIN_FONT, "%s '%s' font %d" % [tag, lb.text, lb.get_theme_font_size("font_size")])
			if lb.autowrap_mode != TextServer.AUTOWRAP_OFF:
				check(lb.size.y + 0.5 >= lb.get_line_count() * lb.get_line_height(), "%s '%s' clipped by its box" % [tag, lb.text])
				check(lb.get_line_count() <= 4, "%s '%s' wraps to %d lines" % [tag, lb.text, lb.get_line_count()])
			else:
				var f := lb.get_theme_font("font")
				var tw := f.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, lb.get_theme_font_size("font_size")).x
				check(tw <= lb.size.x + 0.5, "%s '%s' wider than its box (%.0f > %.0f)" % [tag, lb.text, tw, lb.size.x])
		pieces.append([c, r])
	for i in pieces.size():
		for j in range(i + 1, pieces.size()):
			var a: Control = pieces[i][0]
			var b: Control = pieces[j][0]
			if (a is Button) != (b is Button) and (a == l.stage_btn or b == l.stage_btn): continue     # the tap target sits on the stage
			var ra: Rect2 = pieces[i][1]
			var rb: Rect2 = pieces[j][1]
			check(not ra.grow(-1.0).intersects(rb.grow(-1.0)), "%s band pieces '%s' and '%s' overlap" % [tag, a.name, b.name])
	if l.shown: check(l.stage_btn.size.x >= 44.0 * k - 0.5 and l.stage_btn.size.y >= 44.0 * k - 0.5, "%s the stage tap target is %.0fx%.0f pt" % [tag, l.stage_btn.size.x / k, l.stage_btn.size.y / k])

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
