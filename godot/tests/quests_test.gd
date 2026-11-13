extends SceneTree
## Coin goals test (headless): logic/quests.gd (3 daily goals picked by the date, the same on every run, new ones the
## next day; the weekly challenge; milestones from lifetime stats; the play streak and the first-win-of-the-day bonus;
## claim once), the save blob (autoload/save.gd "quests" key: round trip, an old save without it loads unchanged, junk
## is cleaned, the web game's snapshot() never writes it, the blob stays small), the results line
## (ui/results_rewards.gd) and the Goals screen (ui/goals_screen.gd: opened from the title's Goals button, rows inside
## the safe area, not overlapping, 44 pt buttons, a claim pays and the button says Claimed).
##   godot --headless --path godot --script res://tests/quests_test.gd -- --no-save   (npm run test:godot-quests)

const DAY := 20400                 ## a fixed day (2025-11-08) so the picks are reproducible

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	_logic()
	_save()
	_results()
	await _screen()
	print("Quests ok" if fails == 0 else "Quests checks failed (%d)" % fails)
	quit(0 if fails == 0 else 1)

func _row(rows: Array, key: String) -> Dictionary:
	for r: Dictionary in rows:
		if r["key"] == key: return r
	return {}

func _logic() -> void:
	var a := Quests.daily_ids(DAY)
	check(a.size() == 3 and a == Quests.daily_ids(DAY), "3 daily goals, the same for the same day (%s)" % [a])
	check(a[0] != a[1] and a[1] != a[2] and a[0] != a[2], "daily goals are different")
	var differ := 0
	var seen := {}
	for d in 30:
		if Quests.daily_ids(DAY + d) != a: differ += 1
		for id: String in Quests.daily_ids(DAY + d): seen[id] = true
	check(differ >= 20 and seen.size() == Quests.DAILY.size(), "goals change day to day and every goal comes up (%d, %d)" % [differ, seen.size()])
	for e: Dictionary in Quests.DAILY: check(int(e["coins"]) >= 50 and int(e["coins"]) <= 150, "daily %s pays 50-150" % e["id"])
	check(Quests.week_of(DAY) == Quests.week_of(DAY + 1) or Quests.week_of(DAY + 1) == Quests.week_of(DAY) + 1, "weeks")
	var q := Quests.fresh()
	var st := {"wins": 0, "kos": 0, "onl": 0}
	var rows := Quests.rows(q, DAY, st)
	check(rows.size() == 3 + 1 + 1 + Quests.ACHIEVEMENTS.size(), "rows: 3 daily, bonus, weekly, milestones (%d)" % rows.size())
	check(rows.filter(func(r: Dictionary) -> bool: return r["done"]).is_empty(), "nothing done on a fresh profile")
	# a winning match with K.O.s, a headshot and melee K.O.s, in Classic
	var before := Quests.done_keys(q, DAY, st)
	st = {"wins": 1, "kos": 4, "onl": 0}
	var g := Quests.on_match(q, {"won": true, "kos": 4, "hits": 20, "heads": 1, "mkos": 3, "mode": "classic"}, DAY, st, before)
	var keys: Array = g["done"].map(func(d: Dictionary) -> String: return d["key"])
	check(keys.has("a:first_win") and keys.has("a:first_head"), "first win and first headshot milestones done (%s)" % [keys])
	check(g["streak"] == Quests.STREAK_BASE and g["days"] == 1, "first win of the day pays the streak bonus (%d)" % g["streak"])
	rows = Quests.rows(q, DAY, st)
	for id: String in Quests.daily_ids(DAY):
		var r := _row(rows, "d:" + id)
		var e := Quests._def(Quests.DAILY, id)
		var want := {"wins": 1, "kos": 4, "matches": 1, "hits": 20, "heads": 1, "mkos": 3, "modes": 1}[e["stat"]] as int
		check(r["p"] == mini(want, int(e["n"])) and r["done"] == (want >= int(e["n"])), "daily %s progress %d / %d" % [id, r["p"], r["n"]])
		check(keys.has("d:" + id) == r["done"], "daily %s reported as completed this match" % id)
	# claims
	check(Quests.claim(q, "a:first_win", DAY, st) == 100 and Quests.claim(q, "a:first_win", DAY, st) == 0, "a milestone is claimed once")
	check(Quests.claim(q, "a:kos100", DAY, st) == 0, "an unfinished goal cannot be claimed")
	check(Quests.claim(q, "bogus", DAY, st) == 0, "unknown key")
	# the second win the same day: no second streak bonus; the goals done earlier are not "new" again
	before = Quests.done_keys(q, DAY, st)
	st["wins"] = 2
	g = Quests.on_match(q, {"won": true, "kos": 0, "mode": "melee"}, DAY, st, before)
	check(g["streak"] == 0, "one streak bonus a day")
	check(not g["done"].map(func(d: Dictionary) -> String: return d["key"]).has("a:first_head"), "a goal is announced once")
	check(int(q["d"]["matches"]) == 2 and (q["d"]["m"] as Array) == ["classic", "melee"], "matches and game types today")
	# next day: new goals, counters reset, the streak grows, the weekly carries on within the week
	var wk_before := int(q["w"]["matches"])
	g = Quests.on_match(q, {"won": true, "mode": "duel"}, DAY + 1, st, [])
	check(q["ids"] == Quests.daily_ids(DAY + 1) and int(q["d"]["matches"]) == 1 and q["d"]["m"] == ["duel"], "a new day: new goals, counters from zero")
	check(g["days"] == 2 and g["streak"] == Quests.STREAK_BASE + Quests.STREAK_STEP, "day 2 of a streak pays more (%d)" % g["streak"])
	if Quests.week_of(DAY + 1) == Quests.week_of(DAY): check(int(q["w"]["matches"]) == wk_before + 1, "the weekly counts across days")
	g = Quests.on_match(q, {"won": true, "mode": "duel"}, DAY + 3, st, [])
	check(g["days"] == 1 and g["streak"] == Quests.STREAK_BASE and int(q["streak"]["best"]) == 2, "a missed day restarts the streak, the best is kept")
	check(Quests.streak_coins(50) == Quests.STREAK_BASE + Quests.STREAK_STEP * (Quests.STREAK_MAX - 1), "the streak bonus is capped")
	# daily bonus: all three claimed -> the bonus row is done
	var q2 := Quests.fresh()
	var big := {"won": true, "kos": 99, "hits": 999, "heads": 99, "mkos": 99, "mode": "classic"}
	for m: String in ["classic", "melee", "duel"]:
		big["mode"] = m
		Quests.on_match(q2, big, DAY, {"wins": 3}, [])
	rows = Quests.rows(q2, DAY, {"wins": 3})
	check(_row(rows, "bonus")["done"], "all three daily goals done -> the bonus is ready")
	check(Quests.claim(q2, "bonus", DAY, {"wins": 3}) == Quests.DAILY_BONUS, "daily bonus paid")
	var w := rows.filter(func(r: Dictionary) -> bool: return r["group"] == "weekly")[0] as Dictionary
	check(int(w["coins"]) == 400, "the weekly pays 400")
	# milestones from lifetime stats + every game type
	var q3 := Quests.fresh()
	for m: String in Quests.MODES: Quests.on_match(q3, {"mode": m}, DAY, {}, [])
	rows = Quests.rows(q3, DAY, {"kos": 100, "onl": 1, "wins": 0})
	check(_row(rows, "a:all_modes")["done"] and _row(rows, "a:kos100")["done"] and _row(rows, "a:online")["done"] and not _row(rows, "a:wins25")["done"], "milestones read lifetime stats and the game types tried")
	Quests.on_match(q3, {"mode": "sandbox"}, DAY, {}, [])
	check((q3["t"]["modes"] as Array).size() == Quests.MODES.size(), "game types outside the list do not count")

func _save() -> void:
	var s := SaveProfile.new()
	s.persist = false
	s.day_override = DAY
	check(s.get_blob().has("quests") and s.goals_to_claim() == 0, "a new profile has fresh goals")
	s.begin_match()
	s.on_hit(true); s.on_hit(false)
	s.on_ko(true, false, true)
	s.on_ko(true, false, false)
	var r := s.finish_match(true, "Classic", "Arena", false, "classic")
	check(s.match_heads == 1 and s.match_mkos == 1 and int(s.quests["t"]["heads"]) == 1 and int(s.quests["t"]["mkos"]) == 1, "headshots and melee K.O.s counted")
	check(r["streak"] == Quests.STREAK_BASE and r["coins"] == SaveProfile.match_coins(2, true), "the match payout is unchanged, the streak bonus is extra")
	check(r["total"] == 500 + SaveProfile.match_coins(2, true) + Quests.STREAK_BASE and s.coins == r["total"], "streak bonus added (%d)" % s.coins)
	check((r["goals"] as Array).size() >= 2, "the results get the goals completed (%s)" % [r["goals"]])
	var n := s.goals_to_claim()
	var c0 := s.coins
	check(s.claim_goal("a:first_win") == 100 and s.coins == c0 + 100 and s.goals_to_claim() == n - 1, "claim pays the coins")
	# round trip
	var b := s.get_blob()
	var s2 := SaveProfile.new()
	s2.persist = false
	s2.day_override = DAY
	check(s2.apply_blob(b) and s2.quests == Quests.clean(b["quests"]) and s2.get_blob()["quests"] == b["quests"], "goals survive a save round trip")
	check(s2.claim_goal("a:first_win") == 0 and s2.goals_to_claim() == n - 1, "a claimed goal stays claimed after loading")
	check(not s2.extra.has("quests"), "the quests key is not kept twice")
	# an old save (no quests key, a web blob) loads unchanged, with fresh goals
	var old := {"v": 64, "cfg": {"mode": "ffa"}, "look": {"color": LockerData.swatch()[2], "hat": "crown", "skin": "none", "cls": "kid"},
		"stats": {"kos": 120, "wins": 3, "matches": 9, "onl": 0}, "wallet": {"coins": 1234, "owned": ["wobble", "dab"], "skins": ["none"]}}
	var s3 := SaveProfile.new()
	s3.persist = false
	s3.day_override = DAY
	check(s3.apply_blob(old.duplicate(true)) and s3.coins == 1234 and s3.owns_emote("dab") and s3.look["hat"] == "crown" and int(s3.stats["kos"]) == 120, "an old save loads unchanged")
	check(s3.quests["ids"] == [] or s3.quests["day"] == -1 or s3.quests["ids"] == Quests.daily_ids(DAY), "fresh goals for an old save")
	var ob := s3.get_blob()
	for k: String in old: check(ob.has(k), "old key %s kept" % k)
	check(ob["cfg"] == old["cfg"] and ob["wallet"]["coins"] == 1234, "old blob values unchanged")
	var rows := s3.goal_rows()
	check(_row(rows, "a:first_win")["done"] and _row(rows, "a:kos100")["done"] and not _row(rows, "a:first_win")["claimed"], "earlier wins / K.O.s count for milestones")
	# junk in the quests key is cleaned
	var junk := old.duplicate(true)
	junk["quests"] = {"day": "x", "ids": ["win1", 5, "nope", "win1"], "dc": ["kos10"], "a": ["first_win", "zzz"], "t": {"heads": -4, "modes": [1, "classic"]},
		"streak": {"n": 1e99, "best": "?"}, "d": {"wins": NAN, "m": "classic"}}
	check(s3.apply_blob(junk) and s3.quests["a"] == ["first_win"] and int(s3.quests["t"]["heads"]) == 0 and s3.quests["t"]["modes"] == ["classic"] and s3.quests["day"] == -1, "junk goals data is cleaned")
	check(s3.goal_rows().size() == 5 + Quests.ACHIEVEMENTS.size(), "cleaned goals still list every row")
	s3.apply_blob("nope")
	# the web game: snapshot() lists its own keys only (it ignores and never writes "quests"); the server takes the blob
	var html := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../public/index.html"))
	var at := html.find("function snapshot()")
	check(at > 0, "web snapshot() found")
	if at > 0:
		var line := html.substr(at, html.find("\n", at) - at)
		check(not line.contains("quests") and not line.contains("...") and line.contains("wallet: Object.assign({}, wallet)"), "the web save builds its own keys (ignores quests)")
	var js := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../accounts.js"))
	var m := RegEx.create_from_string("SAVE_MAX\\s*=\\s*(\\d+)\\s*\\*\\s*1024").search(js)
	check(m != null and JSON.stringify(b).length() < int(m.get_string(1)) * 1024 / 20, "the blob stays well under the server's save limit")
	s.free(); s2.free(); s3.free()

func _results() -> void:
	var RR: GDScript = load("res://ui/results_rewards.gd")    # (loaded, not named: it needs the autoloads)
	var r := {"coins": 140, "kos": 2, "won": true, "total": 900, "next": {}, "goals": [{"text": "Win a match", "coins": 100, "key": "d:win1"}], "streak": 30, "days": 2}
	var t: String = RR.goals_text(r)
	check(t.begins_with("+100 goal completed: Win a match") and t.contains("First win today +30 (2-day streak)"), "results line (%s)" % t)
	r["goals"] = [{"text": "A", "coins": 100}, {"text": "B", "coins": 50}]
	check(RR.goals_text(r).begins_with("+150: 2 goals completed"), "several goals")
	check(RR.goals_text({"coins": 40}) == "", "no line without goals")
	var box: Control = RR.make(r)
	check(box.find_child("Goals", true, false) != null, "the results panel shows the goals line")
	box.free()

func _screen() -> void:
	var sv: SaveProfile = root.get_node("Save")
	sv.reset()
	sv.day_override = DAY
	sv.begin_match()
	sv.on_ko(true, false, true)
	sv.finish_match(true, "Classic", "Arena", false, "classic")
	var vp := SubViewport.new()
	vp.size = Vector2i(1170, 540)
	vp.disable_3d = true
	root.add_child(vp)
	var main: Control = load("res://scenes/main.tscn").instantiate()
	vp.add_child(main)
	await process_frame
	var gb: Button = main.goals_b
	var n := sv.goals_to_claim()
	check(n > 0 and (gb.get_node("Stack/Sub") as Label).text == "%d to claim" % n, "the title's Goals button says how many to claim (%s)" % (gb.get_node("Stack/Sub") as Label).text)
	gb.pressed.emit()
	for i in 3: await process_frame
	var gs = main.goals
	check(gs.visible and gs.title_l.text == "Goals", "Goals opens")
	check(gs.claim_bs.size() == sv.goal_rows().size(), "a button per goal")
	var safe: Rect2 = Rect2(Vector2.ZERO, Vector2(vp.size))
	var prev := Rect2()
	for k: String in gs.claim_bs:
		var b: Button = gs.claim_bs[k]
		var r := b.get_global_rect()
		check(b.size.y >= 60.0 and b.size.x >= 60.0, "%s button big enough to tap (%s)" % [k, b.size])
		check(r.end.x <= safe.end.x + 0.5, "%s button inside the screen" % k)
		if prev.size.x > 0.0: check(not r.grow(-0.5).intersects(prev.grow(-0.5)), "%s button overlaps the one above" % k)
		prev = r
		var row: Control = b.get_parent()
		var words: Control = row.get_node("Words")
		check(not words.get_global_rect().grow(-0.5).intersects(r.grow(-0.5)), "%s words and button apart" % k)
	var b0: Button = gs.claim_bs["a:first_win"]
	check(b0.text == "Claim +100" and not b0.disabled, "a done goal: Claim (%s)" % b0.text)
	check(gs.claim_bs["a:kos100"].disabled and gs.claim_bs["a:kos100"].text == "+300", "an open goal shows its reward, disabled")
	var c0 := sv.coins
	check(gs.claim("a:first_win") == 100 and sv.coins == c0 + 100, "claiming pays")
	check(gs.claim_bs["a:first_win"].text == "Claimed" and gs.claim_bs["a:first_win"].disabled, "then it says Claimed")
	check(gs.coins_l.text == str(sv.coins), "the coins in the header follow")
	check(gs.streak_l.text.contains("1 day"), "the play streak shows (%s)" % gs.streak_l.text)
	check(main.go_back() and not gs.visible, "Back closes Goals")
	check((gb.get_node("Stack/Sub") as Label).text == ("%d to claim" % (n - 1) if n > 1 else "Daily coin goals"), "the Goals button follows the claims")
	sv.reset()
	sv.day_override = -1
	vp.queue_free()
	await process_frame
