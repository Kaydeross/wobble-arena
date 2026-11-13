extends SceneTree
## Every map, audited (run by tools/test-godot-maps.js):
##   godot --headless --path godot --script res://tests/maps_test.gd -- --no-save [--ref FILE]
## For every map in res://data/maps.json plus the generated 'custom' level:
##   - MapBuilder builds it without errors; solids / ladders / bounce pads / floor pads == the web export (maps.json)
##   - every spawn, player start and bot start lands on a solid top (see _on_ground) and is not inside a wall
##   - the web decor (decor/<id>.bin) and look (map_look.json) are there and load; the sky / fog / sun come from it
##   - the arena's pieces that stay still in Godot (moving backdrop pieces, specks, birds) are listed
## --ref FILE: custom levels built by the web game's MAPS.custom.build (tools/test-godot-maps.js writes it) must match.
## Also: every mode's arena list (SetupWizard.maps_for) only has maps that exist and build.
## Prints one AUDIT line per map, then MAPS ok / FAILED.

const R := 0.45
var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var content := root.get_node_or_null("Content")
	if content == null:
		print("FAIL no Content autoload"); quit(1); return
	var ids: Array = content.map_ids().duplicate()
	if not ids.has("custom"): ids.append("custom")              # (Content adds it for the wizard; the audit builds it either way)
	for id: String in ids:
		var m: Dictionary = MapBuilder.custom_map({}) if id == "custom" else content.get_map(id)
		if PillarsMap.IDS.has(id): m = PillarsMap.complete(m)        # built from MAPS.pillars (the export has no boxes)
		_audit(id, m)
	_custom_ref()
	_pillars_ref()
	_mode_lists()
	print("MAPS %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _audit(id: String, m: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var node := MapBuilder.build(id)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var g: Dictionary = m.get("geometry", {})
	var counts := [node.solids.size(), node.ladders.size(), node.pads.size(), node.floor_pads.size()]
	var want := [g.get("boxes", []).size(), g.get("ladders", []).size(), g.get("bouncePads", []).size(), g.get("floorPads", []).size()]
	check(counts == want, "%s solids/ladders/pads/floor pads %s != web %s" % [id, counts, want])
	check(node.get_child_count() > 0, id + " has visuals")
	# spawns on solid ground
	var bad: Array = []
	var pts: Array = []
	for p in m.get("spawns", []): pts.append(p)
	for p in m.get("bots", []): pts.append(p)
	if m.has("player"): pts.append(m["player"])
	var dyn_floor := node.solids.is_empty()       # a level without boxes (none left: Pillars is built by PillarsMap)
	if not dyn_floor:
		for p: Array in pts:
			var y := float(p[2]) if p.size() > 2 else float(m.get("spawnY", 0.0))
			if not _on_ground(node.solids, float(p[0]), float(p[1]), y, p.size() <= 2):
				bad.append(p)
		check(bad.is_empty(), "%s spawns not on solid ground: %s" % [id, bad])
	# web look + decor
	var lk := MapBuilder.look(id)
	var decor := MapBuilder.load_decor(MapBuilder._decor_id(id, m))
	check(not lk.is_empty(), id + " has a web look (map_look.json)")
	check(not decor.is_empty() and node.decor_tris > 0, id + " has web decor (decor/%s.bin)" % id)
	var env := MapBuilder.make_environment(m, id)
	check(env != null and env.fog_enabled, id + " environment")
	var kinds := {}
	for d: Dictionary in decor:
		kinds[int(d["kind"])] = true
		check((d["idx"] as PackedInt32Array).size() % 3 == 0 and (d["pos"] as PackedVector3Array).size() > 0, id + " decor group intact")
		var mx := 0
		for i: int in d["idx"]: mx = maxi(mx, i)
		check(mx < (d["pos"] as PackedVector3Array).size(), id + " decor indices in range")
	var still: Array = []
	if int(lk.get("moving", 0)) > 0: still.append("%d moving backdrop pieces" % int(lk["moving"]))
	if not bool(lk.get("indoor", false)): still.append("specks:" + str(lk.get("specks", "")))
	if bool(lk.get("birds", false)): still.append("birds")
	var mech: Array = []
	if m.has("grip"): mech.append("ice grip %s" % m["grip"])
	if m.get("shrinks", false): mech.append("shrinks")
	if m.has("ceil"): mech.append("dome ceil %s" % m["ceil"])
	if dyn_floor: mech.append("moving pillars (Pillars mode)")
	if m.has("range"): mech.append("range dummies")
	var powers := {}
	for p: Dictionary in node.pads: powers[float(p.get("power", 17))] = true
	if powers.size() and powers.keys() != [17.0]: mech.append("pad power %s" % [powers.keys()])
	print("AUDIT %s | built %.0f ms | solids %d ladders %d pads %d floorpads %d | spawns %d ok%s | decor %d tris, kinds %s | look %s%s | mech %s | still %s" % [
		id, ms, counts[0], counts[1], counts[2], counts[3], pts.size() - bad.size(), (" (" + str(bad.size()) + " bad)") if bad.size() else (" (dynamic floor)" if dyn_floor else ""),
		node.decor_tris, kinds.keys(), "indoor" if lk.get("indoor", false) else ("night" if lk.get("night", false) else "sky"),
		"" if lk.is_empty() else "", ", ".join(mech) if mech.size() else "-", ", ".join(still) if still.size() else "-"])
	node.free()

## A fighter (radius R) dropped at (x, z) from `y` (+ 4 m when the spot gives no height, like tools/check-maps.js)
## lands on a solid top: the highest top under its footprint that is not above where it starts, and no solid it would
## stand in reaches above its feet there.
func _on_ground(solids: Array, x: float, z: float, y: float, free_drop: bool) -> bool:
	var start := y + (4.0 if free_drop else 0.6)
	var land := -INF
	var cover: Array = []
	for s: Dictionary in solids:
		var inside: bool = x > float(s.minX) - R and x < float(s.maxX) + R and z > float(s.minZ) - R and z < float(s.maxZ) + R
		if not inside: continue
		cover.append(s)
		if float(s.top) <= start + 1e-6: land = maxf(land, float(s.top))
	if land == -INF: return false
	for s: Dictionary in cover:
		if float(s.top) > land + 0.56 and float(s.bottom) < land + 1.5: return false
	return true

## The custom level matches MAPS.custom.build for the settings in the reference file.
func _custom_ref() -> void:
	var path := ""
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--ref" and i + 1 < a.size(): path = a[i + 1]
	if path == "":
		print("CUSTOM no reference (run through tools/test-godot-maps.js)"); return
	var ref: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(ref is Array and (ref as Array).size() > 0, "custom reference readable")
	if not (ref is Array): return
	var n := 0
	for r: Dictionary in ref:
		var m := MapBuilder.custom_map(r["cfg"])
		var gb: Array = m["geometry"]["boxes"]
		var wb: Array = r["boxes"]
		var same: bool = gb.size() == wb.size()
		if same:
			for i in gb.size():
				for k in ["x", "z", "w", "d", "h", "y", "color"]:
					if absf(float(gb[i][k]) - float(wb[i][k])) > 1e-6: same = false
		check(same, "custom %s boxes match the web (%d vs %d)" % [r["cfg"], gb.size(), wb.size()])
		var gp: Array = m["geometry"]["bouncePads"]
		var wp: Array = r["pads"]
		var psame: bool = gp.size() == wp.size()
		if psame:
			for i in gp.size():
				if absf(float(gp[i]["x"]) - float(wp[i]["x"])) > 1e-6 or absf(float(gp[i]["z"]) - float(wp[i]["z"])) > 1e-6: psame = false
		check(psame, "custom %s pads match the web" % [r["cfg"]])
		check(str(m["spawns"]) == str(r["spawns"]) or _close(m["spawns"], r["spawns"]), "custom %s spawns match" % [r["cfg"]])
		check(bool(m.has("grip")) == bool(r.get("grip", false)), "custom %s ice grip" % [r["cfg"]])
		n += 1
	print("CUSTOM %d settings match the web generator" % n)

## PillarsMap matches MAPS.pillars build() box for box, and its spawns / player / bot spots.
func _pillars_ref() -> void:
	var path := ""
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--pillars" and i + 1 < a.size(): path = a[i + 1]
	if path == "":
		print("PILLARS no reference (run through tools/test-godot-maps.js)"); return
	var ref: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(ref is Dictionary, "pillars reference readable")
	if not (ref is Dictionary): return
	var m := PillarsMap.complete(root.get_node("Content").get_map("pillars"))
	var gb: Array = m["geometry"]["boxes"]
	var wb: Array = ref["boxes"]
	var same: bool = gb.size() == wb.size()
	if same:
		for i in gb.size():
			for k in ["x", "z", "w", "d", "h", "y", "color"]:
				if absf(float(gb[i][k]) - float(wb[i][k])) > 1e-9: same = false
	check(same, "pillars boxes match the web build() (%d vs %d)" % [gb.size(), wb.size()])
	check(_close(m["spawns"], ref["spawns"]) and _close(m["bots"], ref["bots"]) and _close([m["player"]], [ref["player"]]), "pillars spots match the web")
	var ys := true
	for b: Array in m["bots"]: ys = ys and is_equal_approx(float(b[2]), float(ref["bots"][0][2]))
	check(ys and is_equal_approx(float(m["player"][2]), float(ref["player"][2])), "pillars start heights match")
	print("PILLARS %d boxes, %d spawns match the web build()" % [gb.size(), m["spawns"].size()])
	# Lava Pillars: the web MAPS.pillars2 overrides on top of Pillars, the same boxes, its lake
	var lv: Dictionary = ref.get("lava", {})
	var l2 := PillarsMap.complete(root.get_node("Content").get_map("pillars2"))
	var diff: Array = []
	for k: String in lv:
		if not _same(l2.get(k), lv[k]): diff.append(k)
	check(lv.size() == 10 and diff.is_empty(), "Lava Pillars overrides match the web MAPS.pillars2 (differ: %s)" % [diff])
	check((l2["geometry"]["boxes"] as Array).size() == gb.size() and str(l2.get("only", "")) == "pillars" and float(l2.get("lavaY", 0.0)) == PillarsMap.LAVA_Y, "Lava Pillars: the Pillars boxes, Pillars only, a lava lake")
	var node := MapBuilder.build("pillars2")
	check(node.get_node_or_null("LavaLake") != null and node.decor_tris > 0, "Lava Pillars draws its lake and the exported volcano decor")
	node.free()
	print("PILLARS lava: %d web overrides match, lake at %.1f m" % [lv.size(), PillarsMap.LAVA_Y])

## Deep equality with numbers compared as numbers (JSON gives floats, Godot constants are ints).
func _same(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a), float(b))
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for i in a.size():
			if not _same(a[i], b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for k in a:
			if not b.has(k) or not _same(a[k], b[k]): return false
		return true
	return a == b

func _close(a: Array, b: Array) -> bool:
	if a.size() != b.size(): return false
	for i in a.size():
		if absf(float(a[i][0]) - float(b[i][0])) > 1e-6 or absf(float(a[i][1]) - float(b[i][1])) > 1e-6: return false
	return true

## Every mode the wizard offers lists only maps that exist; classic-style modes list every non-exclusive map;
## exclusive maps (`only`) appear only in their own mode.
func _mode_lists() -> void:
	var content := root.get_node("Content")
	var W := load("res://ui/setup_wizard.gd")
	var all_open: Array = []
	for id: String in content.map_ids():
		var m: Dictionary = content.get_map(id)
		if id != "test" and id != "practice" and str(m.get("only", "")) == "": all_open.append(id)
	for mode: String in W.modes():
		var l: Array = W.maps_for(mode)
		check(l.size() > 0, mode + " has arenas")
		for id: String in l:
			var m: Dictionary = content.get_map(id)
			check(not m.is_empty(), "%s lists a missing map %s" % [mode, id])
			var only := str(m.get("only", ""))
			check(only == "" or only == mode, "%s lists %s, which belongs to %s" % [mode, id, only])
		if ModeRules.maps_for(mode).is_empty():
			for id: String in all_open:
				check(l.has(id), "%s (every arena) is missing %s" % [mode, id])
		print("MODE %s: %d arenas" % [mode, l.size()])
