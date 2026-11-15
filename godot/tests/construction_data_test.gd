extends SceneTree
## Construction DLC Unit A data test:
## Tests extra weapons, stages, mode isolation, and crate pool rules.

const EXPECTED_TOOLS := [
	"pipewrench", "nailgun", "jackhammer", "spiritlevel",
	"tapemeasure", "cementbucket", "conelauncher", "anglegrinder", "drill"
]

const EXPECTED_STAGES := [
	"tradies", "engineer", "designer", "supervisor", "project_manager", "the_client"
]

var fails := 0
const MELEE := ["hammer", "wirewhip", "pipewrench", "spiritlevel", "tapemeasure", "drill", "mallet", "bat", "katana", "trident", "spatula", "glove"]

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

const SMOKE_SECONDS := 4.0

## Every tool in a real Construction match (Site Yard, 3 bots) in the player's and the bots' hands for a few seconds:
## it must fire/swing, hit something at some point (not asserted per tool), and raise no errors or non-finite state.
func _smoke_tools() -> void:
	for tid: String in EXPECTED_TOOLS:
		var world: Node = load("res://world/world.tscn").instantiate()
		world.map_id = "siteyard"
		world.mode_id = "construction"
		world.auto_run = false
		world.bot_count = 3
		world.rng_seed = 4242
		world.hp_setting = 100.0
		root.add_child(world)
		var sim: MatchSim = world.sim
		var p := sim.player
		var st: InputState = world.input.state
		for f: FighterState in sim.fighters:
			sim.combat.pickup(f, tid)
			for i in 3:
				if f.slots[i] != null and f.slots[i]["key"] == tid: sim.combat.equip_slot(f, i)
		check(p.weapon == tid, "smoke: player holds %s (%s)" % [tid, p.weapon])
		var ammo0 := 0.0
		if p.current_slot() != null: ammo0 = float(p.current_slot()["ammo"])
		var ammo1 := ammo0
		var acted := false
		var bot_acted := false
		var bad := 0
		for i in int(round(SMOKE_SECONDS * 60.0)):
			var tg: FighterState = null
			var bd := 1e9
			for f: FighterState in sim.fighters:
				if f == p or f.dead: continue
				var d := Vector2(f.phys.px - p.phys.px, f.phys.pz - p.phys.pz).length()
				if d < bd: bd = d; tg = f
			var go := Vector2.ZERO
			if tg != null:
				var dv := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
				world.cam.yaw = atan2(dv.x, dv.y)
				world.cam.pitch = -0.1
				go = Vector2(0, 1) if dv.length() > 2.0 else Vector2.ZERO
			st.set_move("script", go)
			st.hold("script", "fire", i % 60 < 45)   # held, then released (throwing tools fly on release)
			world.tick(1.0 / 60.0)
			if p.swing >= 0.0: acted = true
			var fired := true
			for sl in p.slots:
				if sl != null and sl["key"] == tid:
					fired = false
					ammo1 = minf(ammo1, float(sl["ammo"]))
			if fired: ammo1 = 0.0   # the tool ran dry and left the slot
			for f: FighterState in sim.fighters:
				if not f.is_player and f.weapon == tid and f.swing >= 0.0: bot_acted = true
				for v in [f.phys.px, f.phys.py, f.phys.pz, f.phys.vx, f.phys.vy, f.phys.vz, f.hp]:
					if not is_finite(v): bad += 1
		var used: bool = acted or ammo1 < ammo0
		check(used, "smoke: %s fires/swings (ammo %.0f -> %.0f, swing %s)" % [tid, ammo0, ammo1, acted])
		check(bad == 0, "smoke: %s keeps state finite (%d bad)" % [tid, bad])
		print("SMOKE %-13s ammo %.0f->%.0f swing=%s bot_swing=%s hits=%d" % [tid, ammo0, ammo1, acted, bot_acted, int(world.counts.get("hit", 0))])
		world.queue_free()
		await process_frame
		await process_frame

func _run() -> void:
	_test_weapons()
	_test_stages()
	_test_modes_and_crates()
	_test_packs()
	_test_json_cache()
	await _smoke_tools()
	print("CONSTRUCTION-DATA %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _test_weapons() -> void:
	var path := "res://data/extra/construction/weapons.json"
	check(FileAccess.file_exists(path), "extra weapons file exists")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(raw is Dictionary, "extra weapons parses as dictionary")
	var extra_d: Dictionary = raw if raw is Dictionary else {}

	# 1. Check all 9 tools exist
	for tid in EXPECTED_TOOLS:
		check(extra_d.has(tid), "extra weapons has %s" % tid)

	# 2. Check no id clash with shared/weapons.json
	var shared_raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/weapons.json"))
	var shared_w: Dictionary = shared_raw if shared_raw is Dictionary else {}
	for tid in EXPECTED_TOOLS:
		check(not shared_w.has(tid), "no id clash in shared weapons for %s" % tid)

	# 3. Check each tool schema and fields
	for tid in EXPECTED_TOOLS:
		var w: Dictionary = extra_d.get(tid, {})
		check(w.get("constructionOnly") == true, "%s has constructionOnly: true" % tid)
		check(w.has("name") and str(w["name"]).length() > 0, "%s has name" % tid)
		check(w.has("type") and str(w["type"]).length() > 0, "%s has type" % tid)
		check(w.has("cooldown") and float(w["cooldown"]) > 0.0, "%s has positive cooldown" % tid)
		check(w.has("stiff") and float(w["stiff"]) > 0.0, "%s has positive stiff" % tid)
		check(w.has("dmg") and float(w["dmg"]) >= 0.0, "%s has non-negative dmg" % tid)
		check(w.has("force") and float(w["force"]) >= 0.0, "%s has non-negative force" % tid)
		check(w.has("ammo") and int(w["ammo"]) > 0, "%s has positive ammo" % tid)
		check(w.has("color") and int(w["color"]) >= 0, "%s has color" % tid)
		check(w.has("speedMul") and float(w["speedMul"]) > 0.0, "%s has speedMul" % tid)

		var t: String = w.get("type", "")
		if t == "melee":
			check(w.has("swingTime") and float(w["swingTime"]) > 0.0, "%s melee has swingTime" % tid)
			check(w.has("tip") and float(w["tip"]) > 0.0, "%s melee has tip" % tid)
			check(w.has("thick") and float(w["thick"]) > 0.0, "%s melee has thick" % tid)
			check(w.has("lift"), "%s melee has lift" % tid)
			check(w.has("topple"), "%s melee has topple" % tid)
			check(w.has("hitSfx") and (w["hitSfx"] == "whack" or w["hitSfx"] == "clink"), "%s melee has valid hitSfx" % tid)
		elif t == "gun":
			var style: String = w.get("style", "")
			if style == "punch":
				check(w.has("range") and float(w["range"]) > 0.0, "%s punch gun has range" % tid)
				check(w.has("maxForce"), "%s punch gun has maxForce" % tid)
				check(w.has("topple"), "%s punch gun has topple" % tid)
			elif style == "flame":
				check(w.has("range") and float(w["range"]) > 0.0, "%s flame gun has range" % tid)
				check(w.has("burn") and float(w["burn"]) > 0.0, "%s flame gun has burn" % tid)
			else:
				check(w.has("pellets") and int(w["pellets"]) > 0, "%s gun has pellets" % tid)
				check(w.has("range") and float(w["range"]) > 0.0, "%s gun has range" % tid)
				check(w.has("spread"), "%s gun has spread" % tid)
		elif t == "ball":
			check(w.has("throwSpeed") and float(w["throwSpeed"]) > 0.0, "%s ball has throwSpeed" % tid)
		elif t == "knife":
			check(w.has("speed") and float(w["speed"]) > 0.0, "%s knife has speed" % tid)
		else:
			check(false, "%s uses unsupported type %s" % [tid, t])

	# 4. ExtraWeapons helper tests & merge purity
	check(ExtraWeapons.ids().size() == EXPECTED_TOOLS.size(), "ExtraWeapons.ids() count matches")
	for tid in EXPECTED_TOOLS:
		check(ExtraWeapons.is_extra(tid), "ExtraWeapons.is_extra(%s)" % tid)
	check(not ExtraWeapons.is_extra("hammer"), "ExtraWeapons.is_extra('hammer') is false")
	check(not ExtraWeapons.is_extra("katana"), "ExtraWeapons.is_extra('katana') is false")

	var dup_shared: Dictionary = shared_w.duplicate(true)
	var merged: Dictionary = ExtraWeapons.merge(dup_shared)
	for k in shared_w:
		check(merged[k] == shared_w[k], "shared weapon %s unchanged after merge" % k)
	for tid in EXPECTED_TOOLS:
		check(merged.has(tid), "merged dictionary contains %s" % tid)

	# 5. Combat and Content integration
	var c := Combat.new()
	c.load_content("res://data")
	for tid in EXPECTED_TOOLS:
		check(c.weapons_data.has(tid), "Combat.weapons_data contains %s" % tid)

	print("WEAPONS ok (9 tools validated, schema & merge purity verified)")

func _test_stages() -> void:
	var path := "res://data/extra/construction/stages.json"
	check(FileAccess.file_exists(path), "stages file exists")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(raw is Dictionary, "stages parsed as dictionary")
	var data: Dictionary = raw if raw is Dictionary else {}

	check(data.has("_readme") and str(data["_readme"]).length() > 0, "stages has _readme")
	check(data.has("stages") and data["stages"] is Array, "stages has stages array")
	var stages_arr: Array = data.get("stages", [])
	check(stages_arr.size() == 6, "stages count is 6 (got %d)" % stages_arr.size())

	var cosmetics_raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/cosmetics.json"))
	var cosmetics: Dictionary = cosmetics_raw if cosmetics_raw is Dictionary else {}
	var hats: Array = cosmetics.get("hats", [])
	var skins: Dictionary = cosmetics.get("skins", {})

	var c := Combat.new()
	c.load_content("res://data")
	var all_weapons: Dictionary = c.weapons_data

	var seen_ids := {}
	for st_idx in stages_arr.size():
		var st = stages_arr[st_idx]
		check(st is Dictionary, "stage %d is dictionary" % st_idx)
		if not (st is Dictionary): continue
		var sid: String = st.get("id", "")
		check(EXPECTED_STAGES.has(sid), "stage id %s is expected" % sid)
		check(not seen_ids.has(sid), "stage id %s is unique" % sid)
		seen_ids[sid] = true

		check(st.has("name") and str(st["name"]).length() > 0, "stage %s has name" % sid)
		check(st.has("tagline") and str(st["tagline"]).length() > 0, "stage %s has tagline" % sid)
		check(st.has("boss") and st["boss"] is bool, "stage %s has boss boolean" % sid)
		check(st.has("hp_bar_color") and int(st["hp_bar_color"]) >= 0, "stage %s has hp_bar_color" % sid)
		check(st.has("map_seed_offset") and (st["map_seed_offset"] is int or st["map_seed_offset"] is float), "stage %s has map_seed_offset" % sid)
		check(int(st.get("coin_reward", 0)) > 0, "stage %s has positive coin_reward" % sid)
		check(int(st.get("first_clear_bonus", 0)) > 0, "stage %s has positive first_clear_bonus" % sid)

		var bots: Array = st.get("bots", [])
		check(bots.size() > 0, "stage %s has bots" % sid)
		if bool(st.get("boss", false)):
			check(not bots.is_empty() and MELEE.has(str((bots[0] as Dictionary).get("weapon", ""))), "boss %s starts with a melee tool" % sid)
		for b in bots:
			check(b is Dictionary, "bot in stage %s is dictionary" % sid)
			if not (b is Dictionary): continue
			check(str(b.get("name", "")).length() > 0, "bot has name in %s" % sid)
			var skin_id: String = b.get("skin", "")
			check(skins.has(skin_id), "bot skin %s exists in %s" % [skin_id, sid])
			var hat_id: String = b.get("hat", "")
			check(hats.has(hat_id), "bot hat %s exists in %s" % [hat_id, sid])
			var wep: String = b.get("weapon", "")
			check(all_weapons.has(wep), "bot weapon %s exists in %s" % [wep, sid])

			var hp_mult := float(b.get("hp", 0.0))
			check(hp_mult >= 1.0 and hp_mult <= 6.0, "bot hp %f in [1.0, 6.0] in %s" % [hp_mult, sid])
			var dmg_scale := float(b.get("dmg_scale", 0.0))
			check(dmg_scale >= 0.6 and dmg_scale <= 1.8, "bot dmg_scale %f in [0.6, 1.8] in %s" % [dmg_scale, sid])
			var spd := float(b.get("speed", 0.0))
			check(spd > 0.0, "bot speed %f is positive in %s" % [spd, sid])
			var diff: String = b.get("difficulty", "")
			check(["easy", "normal", "hard", "insane"].has(diff), "bot diff %s valid in %s" % [diff, sid])

		var events: Array = st.get("events", [])
		for ev in events:
			check(ev is Dictionary, "event in stage %s is dictionary" % sid)
			if not (ev is Dictionary): continue
			check(str(ev.get("type", "")).length() > 0, "event has type in %s" % sid)
			check(ev.has("every") and float(ev["every"]) >= 0.0, "event has every in %s" % sid)
			check(ev.has("params") and ev["params"] is Dictionary, "event has params dictionary in %s" % sid)

	check(seen_ids.size() == 6, "all 6 stages validated")
	print("STAGES ok (6 stages, bots, cosmetics & events verified)")

func _test_modes_and_crates() -> void:
	var raw_modes = JSON.parse_string(FileAccess.get_file_as_string("res://data/modes.json"))
	var modes: Dictionary = ModeRules.merge_extra(raw_modes if raw_modes is Dictionary else {})

	check(modes.has("construction"), "modes has construction")
	var c_allow: Array = modes["construction"].get("allowWeapons", [])
	for tid in EXPECTED_TOOLS:
		check(c_allow.has(tid), "construction mode allowWeapons contains %s" % tid)
	# The 9 tools also need crate weights: shared/drops.json is the web export and cannot carry Godot-only keys.
	var c_weights: Dictionary = modes["construction"].get("dropWeights", {})
	for tid in EXPECTED_TOOLS:
		check(c_weights.has(tid) and float(c_weights.get(tid, 0.0)) > 0.0, "construction crate weights contain %s" % tid)

	# Verify no other mode allows the extra tools
	for mid: String in modes:
		if mid == "construction": continue
		var m_allow: Array = modes[mid].get("allowWeapons", [])
		for tid in EXPECTED_TOOLS:
			check(not m_allow.has(tid), "%s mode does not allow %s" % [mid, tid])

	# Crate pool check via MatchSim for other modes
	var sim_classic := MatchSim.new()
	sim_classic.combat.set_mode("classic")
	sim_classic.combat.rng = CombatRng.new(1234)
	for i in 500:
		var key := sim_classic.pickups.pick_crate_key()
		check(not EXPECTED_TOOLS.has(key), "classic crate never drops DLC tool %s" % key)
		if EXPECTED_TOOLS.has(key): break
	sim_classic.dispose()

	var sim_melee := MatchSim.new()
	sim_melee.combat.set_mode("melee")
	sim_melee.combat.rng = CombatRng.new(5678)
	for i in 500:
		var key := sim_melee.pickups.pick_crate_key()
		check(not EXPECTED_TOOLS.has(key), "melee crate never drops DLC tool %s" % key)
		if EXPECTED_TOOLS.has(key): break
	sim_melee.dispose()

	print("MODES-AND-CRATES ok (construction extended, all other modes isolated)")

# ============================== DLC packs (Sprint 4.1) ==============================
## The Construction DLC's data is now a generic pack (res://data/extra/<pack_id>/pack.json, Content.load_dlc_packs):
## 1. every shipped manifest parses/validates and declares the files the registry publishes;
## 2. the packed tables are byte-equal to the legacy (pre-pack) hardcoded merge: weapons, classes, modes and stages;
## 3. a synthetic user:// pack tree (valid + malformed manifests, a missing dependency, a reserved section) scans in
##    deterministic sorted order and reports every bad manifest instead of crashing;
## 4. Content.reload() re-scans and produces identical tables, and Content.load_dlc_packs() is the documented entry point.
## The synthetic tree lives under user:// so the test never writes into res://.

const PACK_DIR := "user://dlc_pack_test"
const CONSTRUCTION_DIR := "res://data/extra/construction/"

func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

func _write_json(path: String, data: Variant) -> void:
	_write_text(path, JSON.stringify(data, " "))

func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null: return
	f.store_string(text)
	f.close()

func _rm_rf(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null: return
	for f: String in d.get_files(): DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(f)))
	for sub: String in d.get_directories(): _rm_rf(path.path_join(sub))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

## The pre-pack algorithm as an oracle (formerly ModeRules.merge_extra's two hardcoded files), so the refactor is held to
## "same modes, same additive edits, byte-equal".
func _legacy_merge_modes(shared: Variant) -> Dictionary:
	var modes: Dictionary = (shared as Dictionary).duplicate(true) if shared is Dictionary else {}
	_apply_legacy_modes_file(modes, "res://data/extra/modes.json")
	_apply_legacy_modes_file(modes, CONSTRUCTION_DIR + "modes.json")
	return modes

func _apply_legacy_modes_file(modes: Dictionary, path: String) -> void:
	if not FileAccess.file_exists(path): return
	var x: Variant = _json(path)
	if not (x is Dictionary): return
	for k: String in x:
		if k.begins_with("_") or not (x[k] is Dictionary): continue
		if modes.has(k):
			var src: Dictionary = x[k]
			var dst: Dictionary = modes[k]
			if src.has("allowWeapons") and dst.get("allowWeapons") is Array:
				for w in src["allowWeapons"]:
					if not (dst["allowWeapons"] as Array).has(w): dst["allowWeapons"].append(w)
			if src.get("dropWeights") is Dictionary:
				var weights: Dictionary = dst.get("dropWeights", {})
				for w: String in src["dropWeights"]: weights[w] = float(src["dropWeights"][w])
				dst["dropWeights"] = weights
			continue
		var m: Dictionary = (x[k] as Dictionary).duplicate(true)
		if not m.has("allowWeapons"):
			m["allowWeapons"] = (modes.get(str(m.get("allowFrom", "classic")), {}) as Dictionary).get("allowWeapons", []).duplicate()
		modes[k] = m

## A JSON table without author-comment (`_`-prefixed) and non-object keys, like the merged hook data().
func _strip_author_keys(v: Variant) -> Dictionary:
	var out := {}
	if v is Dictionary:
		for k: String in v:
			if k.begins_with("_") or not (v[k] is Dictionary): continue
			out[k] = v[k]
	return out

func _test_packs() -> void:
	var content: Variant = root.get_node_or_null("Content")
	check(content != null, "packs: Content autoload present")
	if content == null: return
	var cs: Variant = load("res://autoload/content.gd")
	check(cs != null, "packs: content.gd script loadable")
	if cs == null: return

	# 1. Every shipped pack.json parses, validates and is in the registry.
	var ids: Array = cs.pack_ids()
	check(ids == ["construction"], "packs: registry is [construction] (got %s)" % str(ids))
	var reg: Dictionary = cs.pack("construction")
	check(str(reg.get("name", "")) == "Construction", "packs: construction name")
	check(int(reg.get("version", 0)) == 1, "packs: construction version 1")
	check(reg.get("requires") is Array and (reg["requires"] as Array).is_empty(), "packs: construction requires []")
	var shipped := 0
	var dirs := DirAccess.get_directories_at("res://data/extra")
	dirs.sort()
	for d: String in dirs:
		var mf := "res://data/extra/%s/pack.json" % d
		if not FileAccess.file_exists(mf): continue
		shipped += 1
		var raw: Variant = _json(mf)
		check(raw is Dictionary, "packs: shipped manifest parses (%s)" % mf)
		if not (raw is Dictionary): continue
		check(str((raw as Dictionary).get("id", "")) == d, "packs: shipped manifest id matches its folder (%s)" % d)
		check(str((raw as Dictionary).get("name", "")) != "", "packs: shipped manifest has a name (%s)" % d)
		check(cs.pack_ids().has(d), "packs: shipped manifest is in the registry (%s)" % d)
	check(shipped >= 1, "packs: at least one shipped pack.json")

	# 2. Section files resolve through the registry (no hardcoded construction path in the merge hooks/ArcadeCoop).
	check(cs.pack_section_file("construction", "weapons") == CONSTRUCTION_DIR + "weapons.json", "packs: weapons file via registry")
	check(cs.pack_section_file("construction", "modes") == CONSTRUCTION_DIR + "modes.json", "packs: modes file via registry")
	check(cs.pack_section_file("construction", "stages") == CONSTRUCTION_DIR + "stages.json", "packs: stages file via registry")
	check(cs.pack_section_file("construction", "classes") == "", "packs: undeclared section resolves to ''")
	check(cs.pack_section_file("nope", "weapons") == "", "packs: unknown pack resolves to ''")
	check(cs.pack_section_file("construction", "nope") == "", "packs: unknown section resolves to ''")
	check(cs.pack_paths("modes") == [CONSTRUCTION_DIR + "modes.json"], "packs: pack_paths(modes) order")

	# 3. Byte/machine-equal legacy compare: the pack tables are exactly the pre-refactor files/merge result.
	var legacy_weapons: Dictionary = _json(CONSTRUCTION_DIR + "weapons.json") if _json(CONSTRUCTION_DIR + "weapons.json") is Dictionary else {}
	check(ExtraWeapons.data() == legacy_weapons, "packs: ExtraWeapons.data() == construction/weapons.json (byte-equal)")
	var legacy_classes: Dictionary = _strip_author_keys(_json("res://data/extra/classes.json"))
	check(ExtraClasses.data() == legacy_classes, "packs: ExtraClasses.data() == data/extra/classes.json (byte-equal)")
	var merged_modes: Dictionary = ModeRules.merge_extra((_json("res://data/modes.json") as Dictionary).duplicate(true))
	var legacy_modes: Dictionary = _legacy_merge_modes(_json("res://data/modes.json"))
	check(merged_modes == legacy_modes, "packs: ModeRules.merge_extra == legacy merge (byte-equal)")
	var content_modes := merged_modes.duplicate(true)
	content_modes.erase("pillars")                          # Content.reload drops the removed Pillars mode after the merge
	check(content.get("modes") == content_modes, "packs: Content.modes == legacy merge result")
	var legacy_stages: Dictionary = _json(CONSTRUCTION_DIR + "stages.json") if _json(CONSTRUCTION_DIR + "stages.json") is Dictionary else {}
	check(ArcadeCoop.stages_path() == CONSTRUCTION_DIR + "stages.json", "packs: ArcadeCoop.stages_path resolves via the registry")
	check(ArcadeCoop.table() == legacy_stages, "packs: ArcadeCoop.table() == stages.json (byte-equal)")
	check(ArcadeCoop.count() == 6, "packs: ArcadeCoop.count() == 6")

	# 4. Synthetic packs under user://: deterministic sorted order, malformed manifests reported but never fatal.
	_rm_rf(PACK_DIR)
	_write_json(PACK_DIR + "/alpha/pack.json", {"id": "alpha", "name": "Alpha", "weapons": "weapons.json"})
	_write_json(PACK_DIR + "/alpha/weapons.json", {"testblaster": {"name": "Test Blaster", "type": "melee", "dmg": 7}})
	_write_json(PACK_DIR + "/zeta/pack.json", {"id": "zeta", "name": "Zeta", "weapons": "weapons.json"})
	_write_json(PACK_DIR + "/zeta/weapons.json", {"testblaster": {"name": "Zeta Blaster", "type": "melee", "dmg": 1},
		"zetatool": {"name": "Zeta Tool", "type": "melee"}})
	_write_json(PACK_DIR + "/reserved/pack.json", {"id": "reserved", "name": "Reserved", "maps": "maps.json"})   # documented future section: warned, ignored, pack kept
	_write_json(PACK_DIR + "/noid/pack.json", {"name": "No id"})
	_write_json(PACK_DIR + "/wrongid/pack.json", {"id": "mismatch", "name": "Wrong id"})
	_write_json(PACK_DIR + "/escape/pack.json", {"id": "escape", "name": "Escape", "weapons": "../shared.json"})
	_write_json(PACK_DIR + "/missing/pack.json", {"id": "missing", "name": "Missing", "weapons": "nope.json"})
	_write_json(PACK_DIR + "/badreq/pack.json", {"id": "badreq", "name": "Bad requires", "requires": ["not_shipped"]})
	_write_text(PACK_DIR + "/badjson/pack.json", "{ this is not json")
	check(cs.scan_dlc_packs("user://definitely_not_a_pack_dir").is_empty(), "packs: a missing pack dir scans to []")
	check(cs.scan_errors().size() == 1, "packs: a missing pack dir is reported once")
	var synth: Array = cs.scan_dlc_packs(PACK_DIR)
	var synth_ids: Array = []
	for p: Dictionary in synth: synth_ids.append(str(p["id"]))
	check(synth_ids == ["alpha", "reserved", "zeta"], "packs: synthetic registry sorted by id, broken sections rejected the pack (got %s)" % str(synth_ids))
	var err_text := ""
	for e: Variant in cs.scan_errors(): err_text += str(e) + "\n"
	check(cs.scan_errors().size() >= 6, "packs: malformed manifests reported (%d errors)" % cs.scan_errors().size())
	check(err_text.contains("malformed manifest"), "packs: invalid JSON reported")
	check(err_text.contains("without an id"), "packs: missing id reported")
	check(err_text.contains("does not match its directory"), "packs: id/folder mismatch reported")
	check(err_text.contains("inside the pack"), "packs: path escape reported")
	check(err_text.contains("file is missing"), "packs: missing section file reported")
	check(err_text.contains("requires missing pack"), "packs: missing dependency reported")
	var bad_count := int(cs.scan_errors().size())
	var alpha_weapons := ""
	for p: Dictionary in synth:
		if str(p["id"]) == "alpha": alpha_weapons = str((p["sections"] as Dictionary).get("weapons", ""))
	check(alpha_weapons == PACK_DIR + "/alpha/weapons.json", "packs: synthetic section path")
	_rm_rf(PACK_DIR)
	check(not DirAccess.dir_exists_absolute(PACK_DIR), "packs: synthetic tree cleaned up")

	# 5. Content.reload() re-scans and is byte-idempotent; malformed synthetic packs never entered the real registry.
	var before := {
		"weapons": (content.get("weapons") as Dictionary).duplicate(true),
		"modes": (content.get("modes") as Dictionary).duplicate(true),
		"classes": (content.get("classes") as Dictionary).duplicate(true),
		"maps": (content.get("maps") as Dictionary).duplicate(true),
	}
	content.reload()
	check(content.get("weapons") == before["weapons"], "packs: reload() keeps weapons")
	check(content.get("modes") == before["modes"], "packs: reload() keeps modes")
	check(content.get("classes") == before["classes"], "packs: reload() keeps classes")
	check(content.get("maps") == before["maps"], "packs: reload() keeps maps")
	check(ExtraWeapons.data() == legacy_weapons, "packs: hooks still byte-equal after reload()")

	# 6. The documented autoload entry point: Content.load_dlc_packs() scans res://data/extra/*/pack.json itself.
	check(content.load_dlc_packs().size() == 1, "packs: Content.load_dlc_packs() finds the shipped pack")
	check(cs.pack_ids() == ["construction"], "packs: Content.load_dlc_packs() refreshes the registry")
	check(ExtraWeapons.data() == legacy_weapons, "packs: hooks follow the registry generation")

	print("PACKS ok (1 shipped pack; weapons/classes/modes/stages byte-equal; %d synthetic manifests, %d reported as malformed; reload idempotent)" % [synth.size(), bad_count])



# ============================== parsed-JSON cache (post-v0.4.0 Sprint 4.2) ==============================
## The seven shared content files are decoded once per process by Content's static parsed-JSON cache, every caller gets a
## deep copy, two match setups decode nothing extra, and reload() invalidates + re-decodes. API in
## godot/autoload/content.gd: cache_generation() / json_parses() / json_parse_count(path) / json_cache_entries(); see
## docs/GODOT_ARCH.md "JSON cache".
const CACHE_FILES := ["weapons", "modes", "classes", "cosmetics", "difficulties", "crate-rates", "drops"]

func _cache_path(file_name: String) -> String:
	return "res://data/%s.json" % file_name

func _cache_setup(sim: MatchSim, map_node: Variant) -> void:
	sim.setup("farm", map_node.map, map_node.ladders, map_node.pads, "wobbler", PlayerControl.new(InputState.new()), 0, "normal", false)

func _test_json_cache() -> void:
	var content: Variant = root.get_node_or_null("Content")
	check(content != null, "cache: Content autoload present")
	if content == null: return
	var cs: Variant = load("res://autoload/content.gd")
	var cap := int(cs.get_script_constant_map().get("JSON_CACHE_MAX", 0))
	check(cap >= 64, "cache: JSON_CACHE_MAX is a real bound (%d)" % cap)

	# --- 1. from a known counter start, reload() decodes each shipped file exactly once
	cs.reset_json_cache_counters()
	var gen0: int = cs.cache_generation()
	content.reload()
	check(cs.cache_generation() > gen0, "cache: reload() bumps the generation (%d -> %d)" % [gen0, cs.cache_generation()])
	for f: String in CACHE_FILES:
		check(cs.json_parse_count(_cache_path(f)) == 1, "cache: %s decoded once by reload() (%d)" % [f, cs.json_parse_count(_cache_path(f))])
	var gen1: int = cs.cache_generation()
	# repeated reads are cache hits and always distinct deep copies
	var w1: Variant = cs.read_json("res://data/weapons.json")
	var w2: Variant = cs.read_json("res://data/weapons.json")
	check(w1 == w2 and not is_same(w1, w2), "cache: read_json returns equal but distinct deep copies")
	check(cs.json_parse_count("res://data/weapons.json") == 1 and cs.json_cache_hits() > 0, "cache: repeated reads are hits, not decodes")

	# --- 2. two match setups: 0 extra decodes, equal tables as distinct copies
	var map_node: Variant = MapBuilder.build("farm")
	check(map_node != null, "cache: farm map builds for the match setups")
	if map_node == null: return
	var warm := MatchSim.new()
	_cache_setup(warm, map_node)
	warm.dispose()
	check(cs.json_parse_count("res://data/extra/weapon_tuning.json") == 1, "cache: balance overlay decoded once (%d)" % cs.json_parse_count("res://data/extra/weapon_tuning.json"))
	var t0: int = cs.json_parses()
	var s1 := MatchSim.new()
	_cache_setup(s1, map_node)
	var s2 := MatchSim.new()
	_cache_setup(s2, map_node)
	check(cs.json_parses() == t0, "cache: two MatchSim setups decoded %d files (want 0)" % (cs.json_parses() - t0))
	check(cs.cache_generation() == gen1, "cache: a match setup did not invalidate the cache")
	for f: String in ["difficulties", "cosmetics", "drops", "crate-rates"]:
		check(cs.json_parse_count(_cache_path(f)) == 1, "cache: match table %s is still one decode" % f)
	check(s1.difficulty == s2.difficulty, "cache: the two matches' difficulties are equal")
	check(not is_same(s1.difficulty, s2.difficulty), "cache: the two matches share one difficulty dictionary")
	check(s1.combat.weapons_data == content.weapons, "cache: a match's weapons table equals Content.weapons")
	check(not is_same(s1.combat.weapons_data, content.weapons), "cache: a match's weapons table is the cached dictionary")
	check(not is_same(s1.combat.weapons_data, s2.combat.weapons_data), "cache: two matches share one weapons dictionary")
	check(s1.combat.damage != null and not is_same(s1.combat.damage, s2.combat.damage), "cache: two matches share one damage table")

	# --- 3. mutating one match's copy leaks nowhere (the other match nor the cache)
	var cache_diff: Dictionary = (content.difficulties as Dictionary).duplicate(true)
	var cache_weapons: Dictionary = (content.weapons as Dictionary).duplicate(true)
	var b_diff: Dictionary = s2.difficulty.duplicate(true)
	var b_weapons: Dictionary = s2.combat.weapons_data.duplicate(true)
	s1.difficulty["dmg"] = 999.0
	s1.combat.weapons_data["spatula"]["cooldown"] = 0.001
	check(s2.difficulty == b_diff, "cache: mutating one match's difficulty leaked into the other match")
	check(s2.combat.weapons_data == b_weapons, "cache: mutating one match's weapons leaked into the other match")
	check(content.difficulties == cache_diff and content.weapons == cache_weapons, "cache: mutating a match's copy leaked into Content")

	# --- 4. reload() refreshes: generation up, each file re-decoded once, matches after it decode nothing
	var gen2: int = cs.cache_generation()
	content.reload()
	check(cs.cache_generation() > gen2, "cache: second reload() bumps the generation again")
	for f: String in CACHE_FILES:
		check(cs.json_parse_count(_cache_path(f)) == 2, "cache: reload() re-decoded %s once (%d)" % [f, cs.json_parse_count(_cache_path(f))])
	check(content.weapons == cache_weapons and content.difficulties == cache_diff, "cache: reload() keeps the shipped tables")
	var parse_summary := []
	for f: String in CACHE_FILES:
		parse_summary.append("%s=%d" % [f, cs.json_parse_count(_cache_path(f))])
	print("PARSES decodes per file after two reload() cycles (each reload re-decodes once; two MatchSim setups add 0): %s + weapon_tuning=1" % " ".join(parse_summary))
	check(cs.json_parse_count("res://data/extra/weapon_tuning.json") == 1, "cache: reload() left the balance overlay pending")
	var s3 := MatchSim.new()
	_cache_setup(s3, map_node)                        # the overlay is not one of reload()'s tables: it decodes once more
	check(cs.json_parse_count("res://data/extra/weapon_tuning.json") == 2, "cache: the first match after reload() re-decoded the overlay")
	var t1: int = cs.json_parses()
	var s4 := MatchSim.new()
	_cache_setup(s4, map_node)
	check(cs.json_parses() == t1, "cache: a second match after reload() decoded %d files (want 0)" % (cs.json_parses() - t1))
	check(s3.combat.weapons_data == content.weapons, "cache: the match after reload() sees the refreshed table")

	# --- 5. bounded + the missing-file contract survives the cache
	check(cs.json_cache_entries() > 0 and cs.json_cache_entries() <= cap, "cache: bounded (%d <= %d entries)" % [cs.json_cache_entries(), cap])
	check(cs.load_json("__content_cache_missing__").is_empty(), "cache: a missing data file still returns {}")
	check(cs.read_json("res://data/__content_cache_missing__.json") == null, "cache: a missing file decodes to null")
	s1.dispose(); s2.dispose(); s3.dispose(); s4.dispose()
	map_node.free()
	print("JSON-CACHE ok (%d shared files decoded once per process; 0 decodes for repeated match setups; deep copies isolated; reload() bumps generation %d -> %d and re-decodes; cache %d/%d entries)" % [
		CACHE_FILES.size(), gen0, cs.cache_generation(), cs.json_cache_entries(), cap])
