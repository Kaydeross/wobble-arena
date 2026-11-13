extends SceneTree
## Profile save test (headless, autoload/save.gd): defaults, blob round trip (file and get_blob/apply_blob), atomic
## write + backup recovery from a damaged file, format versioning (a raw web blob, a newer wrapper), web-blob
## cleaning, unknown keys kept for the web game, the Settings mirror, match rewards, and parity with the web game:
## the coin formula and every shop price read from public/index.html.
##   godot --headless --path godot --script res://tests/save_test.gd -- --no-save   (npm run test:godot-save)

const P := "user://save_test_profile.json"
var fails := 0
var made: Array = []

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _fresh() -> SaveProfile:
	var s := SaveProfile.new()
	s.path = P
	s.persist = true
	made.append(s)
	return s

func _clean() -> void:
	for e in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(P + e): DirAccess.remove_absolute(ProjectSettings.globalize_path(P + e))

func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func _run() -> void:
	_clean()
	# defaults (web wallet)
	var s := _fresh()
	check(s.coins == 500 and s.owned == ["wobble"] and s.skins.size() == 1 + LockerData.free_skins().size() and s.skins.has("hoodie"), "fresh profile: 500 coins, free outfits, Wobble Dance")
	check(s.load_file() == "new", "no file = new")
	# round trip through the file
	s.coins = 1234
	s.buy("skin", "cowboy")
	s.buy("emote", "dab")
	s.set_hat("crown"); s.set_color(LockerData.swatch()[2]); s.set_class("bruiser")
	s.on_ko(true, false); s.on_hit(); s.add_play_time(12.5)
	s.extra["cfg"] = {"mode": "classic", "count": 3.0}; s.extra["sens"] = 1.2
	check(s.save(), "save writes")
	check(not FileAccess.file_exists(P + ".tmp"), "no temp file left")
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(P))
	check(doc is Dictionary and int(doc["format"]) == SaveProfile.FORMAT and int(doc["data"]["v"]) == 64, "file wrapper + web blob version")
	var s2 := _fresh()
	check(s2.load_file() == "file", "loads the file")
	check(JSON.stringify(s2.get_blob()) == JSON.stringify(s.get_blob()), "file round trip keeps the blob\n%s\n%s" % [JSON.stringify(s2.get_blob()), JSON.stringify(s.get_blob())])
	check(s2.coins == 1234 - 400 + 5 - 300 and s2.skins.has("cowboy") and s2.owned.has("dab") and s2.look["skin"] == "cowboy" and s2.look["hat"] == "crown" and s2.look["cls"] == "bruiser", "round trip values (%d coins)" % s2.coins)
	check(int(s2.stats["kos"]) == 1 and int(s2.stats["hits"]) == 1 and absf(float(s2.stats["secs"]) - 12.5) < 0.01, "stats round trip")
	check(s2.get_blob()["cfg"]["count"] == 3 and is_equal_approx(float(s2.get_blob()["sens"]), 1.2), "keys for the web game kept")
	# blob round trip in memory (the cloud API shape)
	var s3 := _fresh()
	check(s3.apply_blob(JSON.parse_string(JSON.stringify(s.get_blob()))) and JSON.stringify(s3.get_blob()) == JSON.stringify(s.get_blob()), "get_blob / apply_blob round trip (JSON)")
	check(not s3.apply_blob("nope") and not s3.apply_blob(null), "apply_blob refuses a non-save")
	# backup: the second write backs up the first; a damaged file loads the backup
	s.coins = 777
	s._bak_t = -1.0e9                                   # (buy() saved already this minute; back up the explicit save)
	check(s.save(), "second save")
	check(FileAccess.file_exists(P + ".bak"), "backup written")
	_write(P, "{\"format\":1,\"data\":{\"wallet\":")     # cut off mid-write
	var s4 := _fresh()
	check(s4.load_file() == "backup" and s4.coins == s2.coins, "damaged profile loads the backup (%s, %d)" % [s4.loaded_from, s4.coins])
	_write(P + ".bak", "garbage")
	var s5 := _fresh()
	check(s5.load_file() == "new" and s5.coins == 500, "both damaged: a fresh profile")
	# versioning: a raw web blob (format 0) is read and migrated on the next write; a newer wrapper is still read
	_clean()
	_write(P, JSON.stringify({"v": 60, "look": {"skin": "ballerina", "hat": "zzz", "color": 0x39b5a8, "cls": "kid"},
		"wallet": {"coins": 2500.7, "owned": ["wobble", "hip", "bogus", "hip"], "skins": ["none", "ballerina", "gone"], "slots": ["hip", "bogus", "wobble"]},
		"stats": {"kos": 9, "wins": 2, "matches": 5, "secs": 100, "hist": [{"m": "Classic", "ko": 3, "w": 1}]}, "cfg": {"mode": "ffa"}}))
	var w := _fresh()
	check(w.load_file() == "file", "raw web blob loads")
	check(w.coins == 2500 and w.owned.has("hip") and not w.owned.has("bogus") and w.owned.count("hip") == 1, "web wallet cleaned (%s)" % [w.owned])
	check(w.skins.has("ballerina") and not w.skins.has("gone") and w.skins.has("hoodie"), "outfits cleaned, free ones added")
	check(w.owned.has("pirouette"), "Ballerina brings Grand Pirouette")
	check(w.slots == ["hip", null, "wobble"], "slots hold owned emotes only (%s)" % [w.slots])
	check(w.look["skin"] == "ballerina" and w.look["hat"] == "none" and w.look["cls"] == "kid", "look cleaned")
	check(int(w.stats["kos"]) == 9 and w.hist.size() == 1 and w.hist[0]["ko"] == 3, "web stats + history read")
	w.save()
	var d2: Variant = JSON.parse_string(FileAccess.get_file_as_string(P))
	check(int(d2["format"]) == SaveProfile.FORMAT and d2["data"]["cfg"]["mode"] == "ffa", "migrated to the wrapper, web keys kept")
	_write(P, JSON.stringify({"format": 99, "data": {"wallet": {"coins": 42}}}))
	var fut := _fresh()
	check(fut.load_file() == "file" and fut.coins == 42, "a newer file format still loads its data")
	_clean()
	# coin formula + prices parity with the web game
	_parity()
	# rewards
	var r := _fresh()
	r.persist = false
	r.begin_match()
	r.on_ko(true, false); r.on_ko(true, false); r.on_ko(false, true); r.on_ko(true, false)
	check(r.coins == 515 and int(r.stats["best"]) == 2 and int(r.stats["deaths"]) == 1, "K.O.s pay 5 each, streak + deaths (%d)" % r.coins)
	var sum := r.finish_match(true, "Classic", "Arena")
	check(r.coins == 615 + int(sum["streak"]) and sum["coins"] == 115 and sum["kos"] == 3 and sum["coins"] == SaveProfile.match_coins(3, true), "a win pays 40 + 60 (%s)" % [sum])
	check(int(sum["streak"]) == Quests.STREAK_BASE and sum["total"] == r.coins, "the first win of the day adds the streak bonus on top (logic/quests.gd)")
	check(int(r.stats["matches"]) == 1 and int(r.stats["wins"]) == 1 and r.hist[0]["ko"] == 3 and r.hist[0]["d"] == 1, "match stats + history")
	r.begin_match()
	check(r.finish_match(false)["coins"] == 40 and SaveProfile.match_coins(0, false) == 40, "a loss pays 40")
	check(not sum["next"].is_empty() and int(sum["next"]["price"]) == 150, "next unlock is the cheapest (%s)" % [sum["next"]])
	# the autoload mirrors the look into Settings and back (memory only under --no-save)
	var sv: SaveProfile = root.get_node("Save")
	var st: Node = root.get_node("Settings")
	check(not sv.persist and sv.loaded_from == "memory", "--no-save keeps the profile in memory")
	sv.set_hat("halo")
	check(str(st.get_value("hat")) == "halo", "hat mirrored to Settings")
	st.set_value("class", "elder")
	check(sv.look["cls"] == "elder", "class picked in Settings comes back to the profile")
	st.set_value("skin", "hero")
	check(sv.look["skin"] != "hero" and str(st.get_value("skin")) == sv.look["skin"], "an outfit you do not own is refused")
	sv.set_hat("none"); st.set_value("class", "wobbler")
	for n: Node in made: n.free()
	print("Save ok" if fails == 0 else "Save checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _parity() -> void:
	var js := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../public/index.html"))
	check(js.length() > 100000, "read public/index.html")
	check(js.contains("const wallet = { coins: %d," % SaveProfile.START_COINS), "start coins match the web (%d)" % SaveProfile.START_COINS)
	check(js.contains("wallet.coins += %d; updateCoins();" % SaveProfile.KO_COINS), "K.O. coins match the web (%d)" % SaveProfile.KO_COINS)
	check(js.contains("addCoins(%d + (won ? %d : 0)" % [SaveProfile.MATCH_COINS, SaveProfile.WIN_COINS]), "match / win coins match the web")
	# the Godot-only "quests" key (coin goals): the web snapshot() builds its own key list, so the web game ignores it
	# (and drops it when it saves); a web blob without it loads with fresh goals, and the key is not kept twice
	var snap := js.substr(js.find("function snapshot()"), 600)
	check(snap.begins_with("function snapshot()") and not snap.contains("quests"), "the web save ignores the quests key")
	var g := _fresh()
	g.persist = false
	var gb := g.get_blob()
	check(gb.has("quests") and gb["quests"] is Dictionary, "the blob carries the goals")
	gb.erase("quests")
	check(g.apply_blob(gb) and g.quests == Quests.fresh() and not g.extra.has("quests") and not g.get_blob()["wallet"].has("quests"), "an old blob without quests loads with fresh goals")
	# the Godot-only "dlc" key (Construction DLC: dlc/construction/dlc_save.gd): ignored by the web, additive, absent until used
	check(snap.begins_with("function snapshot()") and not snap.contains("dlc"), "the web save ignores the dlc key")
	check(not gb.has("dlc") and g.dlc == DlcSave.fresh(), "a profile that never touched the DLC writes no dlc key")
	g.dlc["owned"] = true
	g.dlc["arcade_best"] = 3
	g.dlc["arcade_clears"] = ["tradies", "engineer", "designer"]
	var db := g.get_blob()
	check(db.has("dlc") and db["dlc"]["owned"] == true and int(db["dlc"]["arcade_best"]) == 3, "the blob carries the dlc state")
	var g2 := _fresh()
	g2.persist = false
	check(g2.apply_blob(db) and g2.dlc == g.dlc and not g2.extra.has("dlc"), "the dlc key round-trips through apply_blob (and is not kept twice)")
	var db_js: Variant = JSON.parse_string(JSON.stringify(db))      # through JSON, like the file and the cloud (ints come back as floats)
	var g3 := _fresh()
	g3.persist = false
	check(g3.apply_blob(db_js) and g3.dlc["owned"] == true and int(g3.dlc["arcade_best"]) == 3 and g3.dlc["arcade_clears"].size() == 3, "the dlc key survives JSON")
	db.erase("dlc")
	check(g2.apply_blob(db) and g2.dlc == DlcSave.fresh(), "an old blob without dlc loads as locked, nothing else changed")
	db["dlc"] = {"owned": "yes", "arcade_best": -4, "arcade_clears": [5, "x", "x"], "junk": 1}
	check(g2.apply_blob(db) and g2.dlc == {"owned": false, "arcade_best": 0, "arcade_clears": ["x"], "bonus": false}, "a damaged dlc key is cleaned (%s)" % [g2.dlc])
	var shop := js.substr(js.find("const SKIN_SHOP = {"), 1200)
	for k: String in LockerData.data()["skin_shop"]:
		var e: Array = LockerData.data()["skin_shop"][k]
		check(shop.contains("%s: [%d, '%s']" % [k, int(e[0]), e[1]]), "outfit price %s %d matches the web" % [k, int(e[0])])
	var em := js.substr(js.find("const EMOTES = {"), 9000)
	for k: String in LockerData.all_emotes():
		var re := RegEx.create_from_string("\\n  %s: \\{ name: '([^']*)', price: (\\d+), dur: ([\\d.]+)" % k)
		var m := re.search(em)
		check(m != null and int(m.get_string(2)) == LockerData.emote_price(k) and is_equal_approx(float(m.get_string(3)), float(LockerData.emote(k)["dur"])), "emote %s price / length match the web" % k)
	for k: String in LockerData.free_skins(): check(js.contains("'%s'" % k), "free outfit %s" % k)
	var src := FileAccess.get_file_as_string("res://actors/emote_poses.gd")
	for k: String in LockerData.all_emotes():
		check(src.contains("\"%s\":" % k), "emote %s has a pose" % k)
