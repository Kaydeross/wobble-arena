extends SceneTree
## DLC packs data test (phase A of On Fire / Ho Ho Ho / Hey Mate, docs/PACKS_BRIEF.md): for every pack below the
## manifest registers, its 6 weapons exist and stay pack-only, the pack mode registers with valid weapon references and a
## pack-only crate pool, the Arcade table has 6 stages x 3 difficulties with unique boss bar colours and a 1.5x Giant
## final boss, an unknown stage event is ignored, and every player-facing key resolves in the five languages.
## Data only: no combat code is exercised beyond a short smoke match per weapon.

const PACKS := {
	"kitchen": {
		"name": "On Fire",
		"weapons": ["fryingpan", "cleaver", "flambetorch", "rollingpin", "peppergrinder", "souppot"],
		"stages": ["line_cooks", "pastry_chef", "grill_master", "dishie_bot", "food_critic", "chef_inferno"],
		"events": ["dinner_rush", "ingredient_drop"],
		"extra_keys": ["6 Weapons + Kitchen Chaos", "Dinner Rush!", "Order Up!"],
	},
	"xmas": {
		"name": "Ho Ho Ho",
		"weapons": ["candycane", "snowballcannon", "giftbomb", "tinselwhip", "ornamentlauncher", "toymallet"],
		"stages": ["elf_workshop", "snowman", "reindeer", "nutcracker", "grumpy_gus", "big_santa"],
		"events": ["ice_zone", "gift_barrage"],
		"extra_keys": ["6 Weapons + Toy Workshop", "Ice Alert!", "Gift Drop!"],
	},
	"australia": {
		"name": "Hey Mate",
		"weapons": ["cricketbat", "aussieboomerang", "thongslapper", "vegemitejar", "bbqtongs", "didgeridooblaster"],
		"stages": ["backyard_mates", "grill_sergeant", "cricket_captain", "thong_champ", "outback_ollie", "big_bruce"],
		"events": ["hoist_sweep", "sausage_sizzle"],
		"extra_keys": ["6 Weapons + Backyard BBQ", "Sizzle Time!", "Hoist Sweep!"],
	},
}
const DIFFS := ["easy", "normal", "nightmare"]
const LANGS := ["zh_TW", "zh_CN", "ja", "fr", "es"]
const EXISTING_EVENTS := ["backup_call", "change_request"]    ## already implemented by StageEvents / ArcadeManager
const MELEE_IDS := ["hammer", "wirewhip", "spatula", "bat", "mallet", "katana", "trident", "glove"]
const MAX_DMG := 40.0       ## the strongest comparable shared melee (bat 40) / ball (cement bucket 26) / knife (34)
const MAX_FORCE := 30.0     ## the Giant Mallet / snowball cannon
const SMOKE_SECONDS := 3.0

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _json(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null

func _run() -> void:
	_test_registry()
	for pid: String in PACKS:
		_test_weapons(pid)
		_test_mode(pid)
		_test_stages(pid)
		_test_i18n(pid)
	_test_unknown_event()
	_test_cross_pack()
	await _smoke()
	print("PACKS-DATA %s" % ("ok" if fails == 0 else "FAILED (%d)" % fails))
	quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------- registry
func _test_registry() -> void:
	var cs: Variant = load("res://autoload/content.gd")
	check(cs != null, "content.gd loads")
	if cs == null: return
	var ids: Array = cs.pack_ids()
	check(ids.has("construction"), "construction still registered")
	for pid: String in PACKS:
		check(ids.has(pid), "%s: registered with Content" % pid)
		var reg: Dictionary = cs.pack(pid)
		check(str(reg.get("name", "")) == PACKS[pid]["name"], "%s: display name is %s" % [pid, PACKS[pid]["name"]])
		check(int(reg.get("version", 0)) == 1, "%s: version 1" % pid)
		check(reg.get("requires") is Array and (reg["requires"] as Array).is_empty(), "%s: requires []" % pid)
		for sec: String in ["weapons", "modes", "stages"]:
			var f: String = cs.pack_section_file(pid, sec)
			check(f == "res://data/extra/%s/%s.json" % [pid, sec] and FileAccess.file_exists(f), "%s: %s section resolves (%s)" % [pid, sec, f])
		check(cs.pack_section_file(pid, "classes") == "", "%s: declares no classes" % pid)
	for e: Variant in cs.scan_errors():
		check(false, "Content scan error: %s" % str(e))
	ids = ids.duplicate()
	var sorted_ids := ids.duplicate(); sorted_ids.sort()
	check(ids == sorted_ids, "registry is sorted by pack id")

# ---------------------------------------------------------------- weapons
func _test_weapons(pid: String) -> void:
	var raw: Variant = _json("res://data/extra/%s/weapons.json" % pid)
	check(raw is Dictionary, "%s: weapons.json parses" % pid)
	var tbl: Dictionary = raw if raw is Dictionary else {}
	var shared: Dictionary = _json("res://data/weapons.json")
	var want: Array = PACKS[pid]["weapons"]
	var keys: Array = []
	for k: String in tbl:
		if not k.begins_with("_"): keys.append(k)
	check(keys.size() == 6, "%s: exactly 6 weapons (%d)" % [pid, keys.size()])
	var c := Combat.new()
	c.load_content("res://data")
	for wid: String in want:
		check(tbl.has(wid), "%s: has weapon %s" % [pid, wid])
		check(not shared.has(wid), "%s: %s does not clash with a shared weapon id" % [pid, wid])
		check(c.weapons_data.has(wid), "%s: Combat.weapons_data holds %s" % [pid, wid])
		check(ExtraWeapons.is_extra(wid), "%s: ExtraWeapons knows %s" % [pid, wid])
		var w: Dictionary = tbl.get(wid, {})
		check(w.get(pid + "Only") == true and str(w.get("pack", "")) == pid, "%s: %s is flagged pack-only" % [pid, wid])
		check(str(w.get("name", "")).length() > 0, "%s: %s has a name" % [pid, wid])
		check(float(w.get("cooldown", 0.0)) > 0.0, "%s: %s cooldown > 0" % [pid, wid])
		check(float(w.get("stiff", 0.0)) > 0.0, "%s: %s stiff > 0" % [pid, wid])
		check(float(w.get("dmg", -1.0)) >= 0.0 and float(w.get("dmg", 0.0)) <= MAX_DMG, "%s: %s dmg within 0..%d" % [pid, wid, int(MAX_DMG)])
		check(float(w.get("force", -1.0)) >= 0.0 and float(w.get("force", 0.0)) <= MAX_FORCE, "%s: %s force within 0..%d" % [pid, wid, int(MAX_FORCE)])
		check(int(w.get("ammo", 0)) > 0, "%s: %s ammo > 0" % [pid, wid])
		check(int(w.get("color", -1)) >= 0, "%s: %s has a colour" % [pid, wid])
		check(float(w.get("speedMul", 0.0)) > 0.0, "%s: %s speedMul > 0" % [pid, wid])
		var t := str(w.get("type", ""))
		match t:
			"melee":
				for f: String in ["swingTime", "tip", "thick"]:
					check(float(w.get(f, 0.0)) > 0.0, "%s: %s melee %s > 0" % [pid, wid, f])
				check(w.has("lift") and w.has("topple"), "%s: %s melee has lift and topple" % [pid, wid])
				check(float(w.get("topple", 0.0)) <= 0.85, "%s: %s topple <= the Giant Mallet's 0.85" % [pid, wid])
				check(["whack", "clink"].has(str(w.get("hitSfx", ""))), "%s: %s valid hitSfx" % [pid, wid])
			"gun":
				var st := str(w.get("style", ""))
				check(float(w.get("range", 0.0)) > 0.0, "%s: %s gun has range" % [pid, wid])
				if st == "flame": check(float(w.get("burn", 0.0)) > 0.0, "%s: %s flame has burn" % [pid, wid])
				elif st == "punch": check(w.has("maxForce") and w.has("topple"), "%s: %s punch has maxForce and topple" % [pid, wid])
				else: check(int(w.get("pellets", 0)) > 0 and w.has("spread"), "%s: %s gun has pellets and spread" % [pid, wid])
			"ball": check(float(w.get("throwSpeed", 0.0)) > 0.0, "%s: %s ball has throwSpeed" % [pid, wid])
			"knife": check(float(w.get("speed", 0.0)) > 0.0, "%s: %s knife has speed" % [pid, wid])
			_: check(false, "%s: %s uses unsupported type %s (new combat code is not allowed)" % [pid, wid, t])
	var kinds := {}
	for wid: String in want: kinds[str((tbl.get(wid, {}) as Dictionary).get("type", ""))] = true
	check(kinds.has("melee") and kinds.has("gun") and kinds.has("ball") and kinds.has("knife") or pid == "kitchen" and kinds.has("melee") and kinds.has("gun") and kinds.has("ball"), "%s: weapon kinds follow the brief" % pid)

# ---------------------------------------------------------------- mode + crates
func _test_mode(pid: String) -> void:
	var raw: Variant = _json("res://data/modes.json")
	var modes: Dictionary = ModeRules.merge_extra(raw if raw is Dictionary else {})
	check(modes.has(pid), "%s: mode registers (mode id = pack id)" % pid)
	var m: Dictionary = modes.get(pid, {})
	check(str(m.get("name", "")) == PACKS[pid]["name"], "%s: mode name" % pid)
	check(str(m.get("desc", "")).length() > 0 and not str(m.get("desc", "")).ends_with("."), "%s: mode desc, no trailing full stop" % pid)
	var c := Combat.new()
	c.load_content("res://data")
	var allow: Array = m.get("allowWeapons", [])
	var weights: Dictionary = m.get("dropWeights", {})
	var drops: Dictionary = _json("res://data/drops.json")
	var base: Dictionary = drops.get("base", {})
	for wid: String in PACKS[pid]["weapons"]:
		check(allow.has(wid), "%s: allowWeapons holds %s" % [pid, wid])
		check(float(weights.get(wid, 0.0)) > 0.0, "%s: dropWeights has %s > 0" % [pid, wid])
	for wid in allow: check(c.weapons_data.has(str(wid)), "%s: allowWeapons entry %s exists" % [pid, wid])
	for wid: String in weights: check(c.weapons_data.has(wid), "%s: dropWeights entry %s exists" % [pid, wid])
	for k in m.get("dropAllow", []): check(base.has(str(k)), "%s: dropAllow entry %s has a base crate weight" % [pid, k])
	check(c.weapons_data.has(str(m.get("start", ""))), "%s: start weapon exists" % pid)
	check(PACKS[pid]["weapons"].has(str(m.get("start", ""))), "%s: starts with a pack weapon" % pid)
	for other: String in PACKS:
		if other == pid: continue
		for wid: String in PACKS[other]["weapons"]:
			check(not allow.has(wid) and not weights.has(wid), "%s: mode does not use %s's %s" % [pid, other, wid])
	# The crate pool: only allowed keys, every pack weapon shows up, never the Construction tools.
	var sim := MatchSim.new()
	sim.combat.set_mode(pid)
	sim.combat.rng = CombatRng.new(777)
	var seen := {}
	for i in 1500:
		var key := sim.pickups.pick_crate_key()
		seen[key] = true
	sim.dispose()
	for wid: String in PACKS[pid]["weapons"]:
		check(seen.has(wid), "%s: crates drop %s" % [pid, wid])
	for key: String in seen:
		check(key != "" and (weights.has(key) or m.get("dropAllow", []).has(key)), "%s: crate key %s is in the mode's pool" % [pid, key])
	# Pack weapons are never in a normal (non-pack) pool.
	for other_mode: String in ["classic", "melee", "guns", "construction", "chaos", "giant"]:
		var s2 := MatchSim.new()
		s2.combat.set_mode(other_mode)
		s2.combat.rng = CombatRng.new(99)
		for i in 400:
			var k := s2.pickups.pick_crate_key()
			check(not PACKS[pid]["weapons"].has(k), "%s: %s crates never drop %s" % [pid, other_mode, k])
			if PACKS[pid]["weapons"].has(k): break
		s2.dispose()

# ---------------------------------------------------------------- stages
func _test_stages(pid: String) -> void:
	var cs: Variant = load("res://autoload/content.gd")
	var data: Variant = _json(str(cs.pack_section_file(pid, "stages")))
	check(data is Dictionary, "%s: stages parse" % pid)
	var d: Dictionary = data if data is Dictionary else {}
	check(str(d.get("_readme", "")).length() > 0, "%s: stages has _readme" % pid)
	var diffs: Dictionary = d.get("difficulties", {})
	var cons: Dictionary = _json("res://data/extra/construction/stages.json")
	for df: String in DIFFS:
		check(diffs.has(df), "%s: difficulty %s exists" % [pid, df])
		check(diffs.get(df) == (cons["difficulties"] as Dictionary).get(df), "%s: difficulty %s equals Construction's" % [pid, df])
		for f: String in ["hp_mul", "hp_floor", "boss_hp_floor", "dmg_mul", "speed_mul", "event_mul", "lives", "coin_mul", "boss_heal", "melee_force_mul", "melee_topple_mul"]:
			check((diffs.get(df, {}) as Dictionary).has(f), "%s: difficulty %s has %s" % [pid, df, f])
	var stages: Array = d.get("stages", [])
	check(stages.size() == 6, "%s: 6 stages (%d)" % [pid, stages.size()])
	var cosmetics: Dictionary = _json("res://data/cosmetics.json")
	var hats: Array = cosmetics.get("hats", [])
	var skins: Dictionary = cosmetics.get("skins", {})
	var c := Combat.new()
	c.load_content("res://data")
	var colours := {}
	var crew_names := []
	var pack_weapons: Array = PACKS[pid]["weapons"]
	var twist := {}
	for i in stages.size():
		var st: Dictionary = stages[i]
		var sid := str(st.get("id", ""))
		check(sid == (PACKS[pid]["stages"] as Array)[mini(i, 5)], "%s: stage %d id is %s" % [pid, i + 1, sid])
		check(str(st.get("name", "")).length() > 0 and str(st.get("tagline", "")).length() > 0, "%s: stage %s has name and tagline" % [pid, sid])
		var is_boss := bool(st.get("boss", false))
		check(is_boss == (i > 0), "%s: stage %s boss flag (only stage 1 is a crew)" % [pid, sid])
		var col := int(st.get("hp_bar_color", -1))
		check(col >= 0 and col <= 0xffffff, "%s: stage %s hp_bar_color is a colour" % [pid, sid])
		check(not colours.has(col), "%s: stage %s hp_bar_color is unique (%d)" % [pid, sid, col])
		colours[col] = true
		check(int(st.get("coin_reward", 0)) > 0 and int(st.get("first_clear_bonus", 0)) > 0, "%s: stage %s pays coins" % [pid, sid])
		check(st.get("map_seed_offset") is int or st.get("map_seed_offset") is float, "%s: stage %s map_seed_offset" % [pid, sid])
		var bots: Array = st.get("bots", [])
		check(bots.size() == (4 if i == 0 else 1), "%s: stage %s crew size %d" % [pid, sid, bots.size()])
		for b: Dictionary in bots:
			if i == 0: crew_names.append(str(b.get("name", "")))
			check(str(b.get("name", "")).length() > 0, "%s: bot name in %s" % [pid, sid])
			check(skins.has(str(b.get("skin", ""))), "%s: skin %s exists" % [pid, b.get("skin", "")])
			check(hats.has(str(b.get("hat", ""))), "%s: hat %s exists" % [pid, b.get("hat", "")])
			var wid := str(b.get("weapon", ""))
			check(c.weapons_data.has(wid), "%s: bot weapon %s exists" % [pid, wid])
			var tp := str((c.weapons_data.get(wid, {}) as Dictionary).get("type", ""))
			if is_boss:
				check(tp == "melee", "%s: boss %s starts with a melee tool (%s)" % [pid, sid, wid])
				check(pack_weapons.has(wid), "%s: boss %s carries a pack weapon" % [pid, sid])
			else:
				check(pack_weapons.has(wid) or MELEE_IDS.has(wid), "%s: crew weapon %s is a pack or shared melee weapon" % [pid, wid])
			var hp := float(b.get("hp", 0.0))
			check(hp >= 1.0 and hp <= 6.0, "%s: bot hp %.2f in [1, 6] (%s)" % [pid, hp, sid])
			var ds := float(b.get("dmg_scale", 0.0))
			check(ds >= 0.6 and ds <= 1.8, "%s: bot dmg_scale %.2f in [0.6, 1.8] (%s)" % [pid, ds, sid])
			check(float(b.get("speed", 0.0)) > 0.0, "%s: bot speed > 0 (%s)" % [pid, sid])
			check(["easy", "normal", "hard", "insane"].has(str(b.get("difficulty", ""))), "%s: bot difficulty valid (%s)" % [pid, sid])
			check(int(b.get("color", -1)) >= 0, "%s: bot colour (%s)" % [pid, sid])
		var giant := 1.0
		for e: Dictionary in st.get("events", []):
			var ty := str(e.get("type", ""))
			check(ty.length() > 0 and float(e.get("every", -1.0)) >= 0.0 and e.get("params") is Dictionary, "%s: event %s in %s has type, every >= 0, params" % [pid, ty, sid])
			check(EXISTING_EVENTS.has(ty) or (PACKS[pid]["events"] as Array).has(ty), "%s: event type %s is existing or this pack's canonical id" % [pid, ty])
			if (PACKS[pid]["events"] as Array).has(ty):
				twist[ty] = true
				check(float(e.get("every", 0.0)) > 0.0, "%s: periodic event %s has every > 0" % [pid, ty])
			if ty == "backup_call":
				for n in (e["params"] as Dictionary).get("summon_bots", []):
					check(crew_names.has(str(n)), "%s: summon %s is a stage-1 crew member" % [pid, n])
			giant = maxf(giant, float((e.get("params", {}) as Dictionary).get("giant_scale", 1.0)))
		if i == 5:
			check(is_equal_approx(giant, 1.5), "%s: final boss %s is a 1.5x Giant (giant_scale %.2f)" % [pid, sid, giant])
			check(str((bots[0] as Dictionary).get("difficulty", "")) == "insane", "%s: final boss is insane" % pid)
		else:
			check(giant == 1.0, "%s: only the final boss is a Giant (%s)" % [pid, sid])
	for ev_id: String in PACKS[pid]["events"]:
		check(twist.has(ev_id), "%s: the Arcade twist event %s is recorded in the data" % [pid, ev_id])
	print("STAGES %-9s 6 stages x 3 difficulties, %d unique bar colours, twist events %s" % [pid, colours.size(), str(twist.keys())])

## An unknown stage event type must be ignored by StageEvents.update. (The real pack events, dinner_rush etc., need a running match: tests/pack_maps_test.gd runs each one.)
func _test_unknown_event() -> void:
	var se: Variant = load("res://dlc/construction/stage_events.gd").new()   # loaded at run time: the script needs the Content autoload
	se.evs = [
		{"type": "zz_unknown_event", "every": 1.0, "params": {}, "t": 1.0, "done": false},
		{"type": "zz_unknown_once", "every": 0.0, "params": {}, "t": 0.0, "done": false},
	]
	for i in 5: se.update(0.5)
	check(se.t > 2.0 and se.fired.is_empty() and se.counts.is_empty(), "unknown stage events are ignored without firing anything")
	check(not se.has("nope"), "StageEvents.has is false for an id that is not scheduled")

# ---------------------------------------------------------------- i18n
func _test_i18n(pid: String) -> void:
	var strings: Variant = _json("res://i18n/strings.json")
	check(strings is Dictionary, "i18n strings.json parses")
	if not (strings is Dictionary): return
	var keys: Array = [PACKS[pid]["name"]]
	keys.append_array(PACKS[pid]["extra_keys"])
	var m: Dictionary = (_json("res://data/extra/%s/modes.json" % pid) as Dictionary)[pid]
	keys.append(str(m["desc"]))
	var tbl: Dictionary = _json("res://data/extra/%s/weapons.json" % pid)
	for wid: String in PACKS[pid]["weapons"]: keys.append(str(tbl[wid]["name"]))
	var cs: Variant = load("res://autoload/content.gd")
	var d: Dictionary = _json(str(cs.pack_section_file(pid, "stages")))
	for st: Dictionary in d["stages"]:
		keys.append(str(st["name"]))
		keys.append(str(st["tagline"]))
		check(str(st["name"]) == str((st["bots"] as Array)[0]["name"]) or not bool(st["boss"]), "%s: boss name equals its stage name (%s)" % [pid, st["id"]])
	for k in keys:
		var key := str(k)
		check(strings.has(key), "%s: i18n key present: %s" % [pid, key])
		if not strings.has(key): continue
		var row: Dictionary = strings[key]
		for l: String in LANGS:
			check(str(row.get(l, "")).strip_edges() != "", "%s: %s has %s" % [pid, key, l])
	print("I18N %-9s %d keys x %d languages" % [pid, keys.size(), LANGS.size()])

# ---------------------------------------------------------------- cross pack
func _test_cross_pack() -> void:
	var seen_w := {}
	var seen_c := {}
	var cs: Variant = load("res://autoload/content.gd")
	var cons: Dictionary = _json("res://data/extra/construction/stages.json")
	for st: Dictionary in cons["stages"]: seen_c[int(st["hp_bar_color"])] = "construction"
	for pid: String in PACKS:
		for wid: String in PACKS[pid]["weapons"]:
			check(not seen_w.has(wid), "weapon id %s is unique across packs" % wid)
			seen_w[wid] = pid
		var d: Dictionary = _json(str(cs.pack_section_file(pid, "stages")))
		for st: Dictionary in d["stages"]:
			var col := int(st["hp_bar_color"])
			check(not seen_c.has(col), "%s/%s hp_bar_color is distinct from other packs (%s)" % [pid, st["id"], str(seen_c.get(col, ""))])
			seen_c[col] = pid
	check(seen_w.size() == 18, "18 pack weapons in total (%d)" % seen_w.size())
	check(ExtraWeapons.ids().size() >= 27, "ExtraWeapons holds the 9 Construction tools and the 18 pack weapons")

# ---------------------------------------------------------------- smoke
## Each pack weapon in a real pack-mode match (Site Yard, 3 bots) in the player's and the bots' hands for a few seconds:
## it must fire / swing, and raise no errors or non-finite state. Also proves each pack mode boots.
func _smoke() -> void:
	for pid: String in PACKS:
		for tid: String in PACKS[pid]["weapons"]:
			var world: Node = load("res://world/world.tscn").instantiate()
			world.map_id = "siteyard"
			world.mode_id = pid
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
			check(p.weapon == tid, "smoke %s: player holds %s (%s)" % [pid, tid, p.weapon])
			var ammo0 := 0.0
			if p.current_slot() != null: ammo0 = float(p.current_slot()["ammo"])
			var ammo1 := ammo0
			var acted := false
			var bad := 0
			for i in int(round(SMOKE_SECONDS * 60.0)):
				var tg: FighterState = null
				var bd := 1e9
				for f: FighterState in sim.fighters:
					if f == p or f.dead: continue
					var dd := Vector2(f.phys.px - p.phys.px, f.phys.pz - p.phys.pz).length()
					if dd < bd: bd = dd; tg = f
				var go := Vector2.ZERO
				if tg != null:
					var dv := Vector2(tg.phys.px - p.phys.px, tg.phys.pz - p.phys.pz)
					world.cam.yaw = atan2(dv.x, dv.y)
					world.cam.pitch = -0.1
					go = Vector2(0, 1) if dv.length() > 2.0 else Vector2.ZERO
				st.set_move("script", go)
				st.hold("script", "fire", i % 60 < 45)
				world.tick(1.0 / 60.0)
				if p.swing >= 0.0: acted = true
				var gone := true
				for sl in p.slots:
					if sl != null and sl["key"] == tid:
						gone = false
						ammo1 = minf(ammo1, float(sl["ammo"]))
				if gone: ammo1 = 0.0
				for f: FighterState in sim.fighters:
					for v in [f.phys.px, f.phys.py, f.phys.pz, f.phys.vx, f.phys.vy, f.phys.vz, f.hp]:
						if not is_finite(v): bad += 1
			check(acted or ammo1 < ammo0, "smoke %s: %s fires/swings (ammo %.0f -> %.0f, swing %s)" % [pid, tid, ammo0, ammo1, acted])
			check(bad == 0, "smoke %s: %s keeps state finite (%d bad)" % [pid, tid, bad])
			print("SMOKE %-9s %-18s ammo %.0f->%.0f swing=%s hits=%d" % [pid, tid, ammo0, ammo1, acted, int(world.counts.get("hit", 0))])
			world.queue_free()
			await process_frame
			await process_frame
