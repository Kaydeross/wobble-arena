class_name Quests
extends RefCounted
## Coin goals (Godot only; the Goals screen, ui/goals_screen.gd, and a line on the results panel, ui/results_rewards.gd):
##   Daily      3 goals a day, picked from DAILY by the date (the same 3 for everyone on that day), 50-150 coins each,
##              plus DAILY_BONUS once all three are done.
##   Weekly     one bigger goal a week (WEEKLY, picked by the week number), WEEKLY_COINS.
##   Milestones one-time rewards (ACHIEVEMENTS) from lifetime stats (SaveProfile.stats) and the tallies kept here.
##   Streak     playing on consecutive days: the first win of a day pays STREAK_BASE + STREAK_STEP per extra day (capped).
## Progress only moves at the end of a match (SaveProfile.finish_match -> on_match); rewards are claimed by hand
## (claim). The state is one Dictionary kept in the save blob under "quests" (an additive key: the web game ignores it
## and old saves load with fresh goals). Pure functions on that Dictionary; `day` = local days since 1970 (today()).
## Not on a simulation path (no MatchSim rng), so parity is untouched.

const DAILY := [
	{"id": "win1", "text": "Win a match", "stat": "wins", "n": 1, "coins": 100},
	{"id": "kos10", "text": "Get 10 K.O.s", "stat": "kos", "n": 10, "coins": 80},
	{"id": "modes3", "text": "Play 3 different game types", "stat": "modes", "n": 3, "coins": 120},
	{"id": "melee3", "text": "Get 3 K.O.s with melee weapons", "stat": "mkos", "n": 3, "coins": 90},
	{"id": "head3", "text": "Land 3 headshots", "stat": "heads", "n": 3, "coins": 70},
	{"id": "play3", "text": "Finish 3 matches", "stat": "matches", "n": 3, "coins": 60},
	{"id": "hits60", "text": "Land 60 hits", "stat": "hits", "n": 60, "coins": 50},
	{"id": "wins3", "text": "Win 3 matches", "stat": "wins", "n": 3, "coins": 150},
]
const DAILY_N := 3
const DAILY_BONUS := 100
const WEEKLY := [
	{"id": "wkos30", "text": "Get 30 K.O.s this week", "stat": "kos", "n": 30, "coins": 400},
	{"id": "wwins5", "text": "Win 5 matches this week", "stat": "wins", "n": 5, "coins": 400},
	{"id": "wplay10", "text": "Finish 10 matches this week", "stat": "matches", "n": 10, "coins": 400},
	{"id": "wmelee10", "text": "Get 10 melee K.O.s this week", "stat": "mkos", "n": 10, "coins": 400},
]
const WEEKLY_COINS := 400
## Lifetime goals. stat: a SaveProfile stat ("wins", "kos", "onl") or one of ours ("heads", "mkos", "modes", "streak").
const ACHIEVEMENTS := [
	{"id": "first_win", "text": "Get your first win", "stat": "wins", "n": 1, "coins": 100},
	{"id": "first_head", "text": "Land your first headshot", "stat": "heads", "n": 1, "coins": 100},
	{"id": "online", "text": "Play an online match", "stat": "onl", "n": 1, "coins": 150},
	{"id": "all_modes", "text": "Try every game type", "stat": "modes", "n": -1, "coins": 300},
	{"id": "kos100", "text": "Get 100 K.O.s in total", "stat": "kos", "n": 100, "coins": 300},
	{"id": "melee25", "text": "Get 25 melee K.O.s", "stat": "mkos", "n": 25, "coins": 200},
	{"id": "wins25", "text": "Win 25 matches", "stat": "wins", "n": 25, "coins": 300},
	{"id": "streak7", "text": "Play 7 days in a row", "stat": "streak", "n": 7, "coins": 250},
]
## The game types "Try every game type" counts (the Practice Range and Sandbox have no real end).
const MODES := ["classic", "melee", "guns", "ninja", "duel", "t2", "t3", "t4", "mega", "giant", "gungame", "tdm",
	"deathmatch", "sudden", "chaos", "pillars", "explosive", "lowg", "construction"]
const STREAK_BASE := 20
const STREAK_STEP := 10
const STREAK_MAX := 6              ## days the streak bonus keeps growing
const COUNTERS := ["wins", "kos", "matches", "hits", "heads", "mkos"]

# ============================== state ==============================

## Local days since 1970-01-01.
static func today() -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return floori((Time.get_unix_time_from_system() + bias * 60.0) / 86400.0)

## Weeks start on Monday (day 0 was a Thursday).
static func week_of(day: int) -> int:
	return floori((day + 3) / 7.0)

static func fresh() -> Dictionary:
	return {"day": -1, "d": _period(), "ids": [], "dc": [], "db": 0,
		"week": -1, "w": _period(), "wid": "", "wc": 0,
		"a": [], "t": {"heads": 0, "mkos": 0, "modes": []},
		"streak": {"last": -1, "n": 0, "best": 0, "win": -1}}

static func _period() -> Dictionary:
	var p := {"m": []}
	for k: String in COUNTERS: p[k] = 0
	return p

## A clean copy of a saved state (anything odd is dropped, unknown ids too). Not a Dictionary -> fresh().
static func clean(v: Variant) -> Dictionary:
	var q := fresh()
	if not (v is Dictionary): return q
	var d: Dictionary = v
	q["day"] = _int(d.get("day"), -1)
	q["week"] = _int(d.get("week"), -1)
	q["d"] = _clean_period(d.get("d"))
	q["w"] = _clean_period(d.get("w"))
	q["ids"] = _ids(d.get("ids"), DAILY).slice(0, DAILY_N)
	q["dc"] = _ids(d.get("dc"), DAILY).filter(func(id: String) -> bool: return q["ids"].has(id))
	q["db"] = 1 if _int(d.get("db"), 0) == 1 else 0
	var wid: Variant = d.get("wid")
	q["wid"] = wid if wid is String and not _def(WEEKLY, wid).is_empty() else ""
	q["wc"] = 1 if _int(d.get("wc"), 0) == 1 and q["wid"] != "" else 0
	q["a"] = _ids(d.get("a"), ACHIEVEMENTS)
	var t: Variant = d.get("t")
	if t is Dictionary:
		q["t"]["heads"] = maxi(0, _int(t.get("heads"), 0))
		q["t"]["mkos"] = maxi(0, _int(t.get("mkos"), 0))
		q["t"]["modes"] = _modes(t.get("modes"))
	var s: Variant = d.get("streak")
	if s is Dictionary:
		q["streak"] = {"last": _int(s.get("last"), -1), "n": clampi(_int(s.get("n"), 0), 0, 9999),
			"best": clampi(_int(s.get("best"), 0), 0, 9999), "win": _int(s.get("win"), -1)}
	if q["ids"].size() != DAILY_N: q["day"] = -1        # a broken daily set: picked again
	if q["wid"] == "": q["week"] = -1
	return q

static func _clean_period(v: Variant) -> Dictionary:
	var p := _period()
	if v is Dictionary:
		for k: String in COUNTERS: p[k] = maxi(0, _int(v.get(k), 0))
		p["m"] = _modes(v.get("m"))
	return p

static func _int(v: Variant, dflt: int) -> int:
	return int(v) if (v is int or v is float) and is_finite(float(v)) else dflt

static func _ids(v: Variant, table: Array) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if x is String and not out.has(x) and not _def(table, x).is_empty(): out.append(x)
	return out

static func _modes(v: Variant) -> Array:
	var out: Array = []
	if v is Array:
		for x in v:
			if x is String and (x as String).length() <= 24 and not out.has(x): out.append(x)
			if out.size() >= 64: break
	return out

static func _def(table: Array, id: String) -> Dictionary:
	for e: Dictionary in table:
		if e["id"] == id: return e
	return {}

## A small deterministic hash (same on every device), so a day's goals are the same everywhere.
static func _hash(n: int) -> int:
	var h := (n * 2654435761 + 40503) & 0x7fffffff
	h = ((h >> 13) ^ h) * 1274126177 & 0x7fffffff
	return (h >> 16) ^ h

## The 3 daily goal ids for a day (distinct, picked from DAILY by the date).
static func daily_ids(day: int) -> Array:
	var pool: Array = DAILY.map(func(e: Dictionary) -> String: return e["id"])
	var out: Array = []
	var h := _hash(day)
	for i in DAILY_N:
		var j := h % pool.size()
		out.append(pool[j])
		pool.remove_at(j)
		h = _hash(h + i + 1)
	return out

static func weekly_id(week: int) -> String:
	return WEEKLY[_hash(week * 7 + 3) % WEEKLY.size()]["id"]

## New day / week: new goals, counters back to zero (the streak and the milestones carry on).
static func roll(q: Dictionary, day: int) -> void:
	if int(q["day"]) != day:
		q["day"] = day
		q["ids"] = daily_ids(day)
		q["d"] = _period()
		q["dc"] = []
		q["db"] = 0
	var wk := week_of(day)
	if int(q["week"]) != wk:
		q["week"] = wk
		q["wid"] = weekly_id(wk)
		q["w"] = _period()
		q["wc"] = 0

# ============================== progress ==============================

## A finished match. `m` = {won, kos, hits, heads, mkos, mode (id), online}; `stats` = the lifetime stats after it.
## Returns {done: [{text, coins}] goals this match completed, streak: coins for the first win of the day (paid by the
## caller), days: the streak length}. `before` = done_keys() when the match began (goals done earlier are not new).
static func on_match(q: Dictionary, m: Dictionary, day: int, stats: Dictionary, before: Array = []) -> Dictionary:
	roll(q, day)
	var add := {"wins": 1 if m.get("won", false) else 0, "kos": int(m.get("kos", 0)), "matches": 1,
		"hits": int(m.get("hits", 0)), "heads": int(m.get("heads", 0)), "mkos": int(m.get("mkos", 0))}
	for p: Dictionary in [q["d"], q["w"]]:
		for k: String in COUNTERS: p[k] = int(p[k]) + maxi(0, int(add[k]))
		var md := str(m.get("mode", ""))
		if md != "" and not (p["m"] as Array).has(md): (p["m"] as Array).append(md)
	q["t"]["heads"] = int(q["t"]["heads"]) + maxi(0, int(add["heads"]))
	q["t"]["mkos"] = int(q["t"]["mkos"]) + maxi(0, int(add["mkos"]))
	var mode := str(m.get("mode", ""))
	if MODES.has(mode) and not (q["t"]["modes"] as Array).has(mode): (q["t"]["modes"] as Array).append(mode)
	var s: Dictionary = q["streak"]
	if int(s["last"]) != day:
		s["n"] = int(s["n"]) + 1 if int(s["last"]) == day - 1 else 1
		s["last"] = day
		s["best"] = maxi(int(s["best"]), int(s["n"]))
	var bonus := 0
	if m.get("won", false) and int(s["win"]) != day:
		s["win"] = day
		bonus = streak_coins(int(s["n"]))
	var done: Array = []
	for r: Dictionary in rows(q, day, stats):
		if r["done"] and not r["claimed"] and not before.has(r["key"]): done.append({"text": r["text"], "coins": r["coins"], "key": r["key"]})
	return {"done": done, "streak": bonus, "days": int(s["n"])}

## The coins of the first win of a day on day `n` of a streak.
static func streak_coins(n: int) -> int:
	return STREAK_BASE + STREAK_STEP * clampi(n - 1, 0, STREAK_MAX - 1)

## Keys of the goals done right now (claimed or not), so a match can tell which ones it completed.
static func done_keys(q: Dictionary, day: int, stats: Dictionary) -> Array:
	var out: Array = []
	for r: Dictionary in rows(q, day, stats):
		if r["done"]: out.append(r["key"])
	return out

static func _val(q: Dictionary, p: Dictionary, stat: String) -> int:
	if stat == "modes": return (p["m"] as Array).size()
	return int(p.get(stat, 0))

static func _life(q: Dictionary, stats: Dictionary, stat: String) -> int:
	match stat:
		"heads", "mkos": return int(q["t"][stat])
		"modes": return (q["t"]["modes"] as Array).size()
		"streak": return int(q["streak"]["best"])
	return int(stats.get(stat, 0))

## Every goal as a row for the Goals screen, in order: the 3 daily ones, the daily bonus, the weekly one, then the
## milestones. {key, group ("daily" | "bonus" | "weekly" | "ach"), text, p, n, coins, done, claimed}.
static func rows(q: Dictionary, day: int, stats: Dictionary) -> Array:
	roll(q, day)
	var out: Array = []
	var all_done := true
	for id: String in q["ids"]:
		var e := _def(DAILY, id)
		var p := _val(q, q["d"], e["stat"])
		var dn := p >= int(e["n"])
		all_done = all_done and dn
		out.append({"key": "d:" + id, "group": "daily", "text": e["text"], "p": mini(p, int(e["n"])), "n": int(e["n"]),
			"coins": int(e["coins"]), "done": dn, "claimed": (q["dc"] as Array).has(id)})
	var nd: int = out.filter(func(r: Dictionary) -> bool: return r["done"]).size()
	out.append({"key": "bonus", "group": "bonus", "text": "All three daily goals", "p": nd, "n": DAILY_N, "coins": DAILY_BONUS,
		"done": all_done, "claimed": int(q["db"]) == 1})
	var we := _def(WEEKLY, q["wid"])
	var wp := _val(q, q["w"], we["stat"])
	out.append({"key": "w:" + str(we["id"]), "group": "weekly", "text": we["text"], "p": mini(wp, int(we["n"])), "n": int(we["n"]),
		"coins": WEEKLY_COINS, "done": wp >= int(we["n"]), "claimed": int(q["wc"]) == 1})
	for e: Dictionary in ACHIEVEMENTS:
		var n := MODES.size() if int(e["n"]) < 0 else int(e["n"])
		var v := _life(q, stats, e["stat"])
		out.append({"key": "a:" + str(e["id"]), "group": "ach", "text": e["text"], "p": mini(v, n), "n": n, "coins": int(e["coins"]),
			"done": v >= n, "claimed": (q["a"] as Array).has(e["id"])})
	return out

## Goals done and not claimed yet.
static func claimable(q: Dictionary, day: int, stats: Dictionary) -> int:
	return rows(q, day, stats).filter(func(r: Dictionary) -> bool: return r["done"] and not r["claimed"]).size()

## Claims a goal: its coins (the caller adds them), 0 if it is not done or already claimed.
static func claim(q: Dictionary, key: String, day: int, stats: Dictionary) -> int:
	for r: Dictionary in rows(q, day, stats):
		if r["key"] != key: continue
		if not r["done"] or r["claimed"]: return 0
		var id := key.substr(2)
		match r["group"]:
			"daily": (q["dc"] as Array).append(id)
			"bonus": q["db"] = 1
			"weekly": q["wc"] = 1
			"ach": (q["a"] as Array).append(id)
		return int(r["coins"])
	return 0
