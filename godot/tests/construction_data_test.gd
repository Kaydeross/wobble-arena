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

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	_test_weapons()
	_test_stages()
	_test_modes_and_crates()
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
