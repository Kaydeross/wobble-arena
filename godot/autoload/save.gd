class_name SaveProfile
extends Node
## The player's profile (autoload `Save`): coins, what you own (outfits, emotes), the emote slots, the look you wear
## (colour, hat, outfit, class) and lifetime stats. Offline first, in the same shape as the web game's save
## (`snapshot()` in public/index.html ~8663: {v, look, stats, wallet, ...}), so the cloud save (PUT /api/save
## {data, base}) can store either client's blob: get_blob() / apply_blob(). Keys this client does not use (cfg, set,
## map, sens, ...) are kept as they came and written back unchanged.
##
## File: user://profile.json = {"format": FORMAT, "saved_at": unix seconds, "data": <blob>}. Written atomically (a
## temp file, then a rename over the old one). Before each write the previous good file is copied to profile.json.bak
## (at most once a minute, like the web game's wobbleArena.bak); a damaged profile.json loads from the backup.
## A file without "format" is a raw web blob (format 0) and is migrated on the next write.
##
## Coins (web): you start with 500; +5 per K.O. you score; +40 for every finished match and +60 more for a win.
## The equipped look is mirrored into Settings (skin, hat, color, class), which the match, the online `join` info and
## the setup wizard's Character page already read; a class picked in the wizard comes back here.
## `--no-save` (tests) keeps everything in memory.
## Cloud save: `cloud` (net/account_api.gd, a child node) pushes get_blob() to the signed-in account a little after each
## change and pulls / merges the cloud blob after a sign-in; the game never waits for it.

signal changed                       ## coins, owned items, the look or the emote slots changed

const PATH := "user://profile.json"
const FORMAT := 1                    ## the file wrapper version
const BLOB_V := 64                   ## web snapshot().v
const START_COINS := 500
const KO_COINS := 5
const MATCH_COINS := 40
const WIN_COINS := 60
const SLOTS := 3                     ## emote slots (web T / G / H)
const WHEEL_MAX := 8                 ## emotes in the in-match wheel
const BAK_EVERY := 60.0              ## seconds between backups
const STAT_KEYS := ["kos", "best", "streak", "wins", "matches", "secs", "deaths", "onl", "hits"]
const DEFAULT_LOOK := {"color": 0x39b5a8, "hat": "none", "skin": "none", "cls": "wobbler"}

var path := PATH
var persist := true
var coins := START_COINS
var owned: Array = ["wobble"]        ## emotes (web wallet.owned)
var slots: Array = ["wobble", null, null]
var skins: Array = []                ## outfits (web wallet.skins: "none" + the free ones + bought)
var codes: Array = []
var daily := {"d": 0, "s": 0}
var look := DEFAULT_LOOK.duplicate()
var stats := {}
var hist: Array = []
var extra := {}                      ## blob keys this client does not use, kept for the web game
var extra_wallet := {}
var extra_stats := {}
var loaded_from := "new"             ## "file" | "backup" | "new" | "memory"
var cloud_t := 0                     ## the server's save time (PUT /api/save base), mirrored by `cloud`
var cloud: AccountApi                ## accounts + cloud sync (only on the autoload, not on test profiles)

## this match (begin_match .. finish_match)
var match_kos := 0
var match_hits := 0
var match_deaths := 0
var _streak := 0
var _bak_t := -1.0e9
var _syncing := false

func _init() -> void:
	reset()
	if OS.get_cmdline_user_args().has("--no-save"):
		persist = false

func _ready() -> void:
	if persist: load_file()
	else: loaded_from = "memory"
	if cloud == null:
		cloud = AccountApi.new()
		cloud.name = "Cloud"
		cloud.profile = self
		add_child(cloud)
	var st := _settings()
	if st:
		if loaded_from == "new": _adopt_settings(st)
		_push_settings()
		st.changed.connect(_on_setting)

func _settings() -> Node:
	if not is_inside_tree(): return null
	return get_tree().root.get_node_or_null("Settings")

## Back to a fresh profile (500 coins, the free outfits, Wobble Dance).
func reset() -> void:
	coins = START_COINS
	owned = ["wobble"]
	slots = ["wobble", null, null]
	skins = ["none"] + LockerData.free_skins()
	codes = []
	daily = {"d": 0, "s": 0}
	look = DEFAULT_LOOK.duplicate()
	stats = {}
	for k: String in STAT_KEYS: stats[k] = 0
	stats["secs"] = 0.0
	hist = []
	extra = {}; extra_wallet = {}; extra_stats = {}
	match_kos = 0; match_hits = 0; match_deaths = 0; _streak = 0

# ============================== the blob (web snapshot shape) ==============================

func get_blob() -> Dictionary:
	var d := extra.duplicate(true)
	d["v"] = maxi(int(d.get("v", 0)), BLOB_V)
	d["look"] = look.duplicate()
	var s := extra_stats.duplicate(true)
	for k: String in STAT_KEYS: s[k] = stats[k]
	s["secs"] = snappedf(float(stats["secs"]), 0.01)
	s["hist"] = hist.duplicate(true)
	d["stats"] = s
	var w := extra_wallet.duplicate(true)
	w["coins"] = coins
	w["owned"] = owned.duplicate()
	w["slots"] = slots.duplicate()
	w["skins"] = skins.duplicate()
	w["codes"] = codes.duplicate()
	w["daily"] = daily.duplicate()
	d["wallet"] = w
	return d

## Loads a blob (a web save or one of ours), cleaning it like the web load(): unknown items dropped, the free outfits
## and Wobble Dance always owned, outfit emotes granted, slots only hold owned emotes. false if `d` is not a save.
func apply_blob(d: Variant) -> bool:
	if not (d is Dictionary): return false
	reset()
	for k: String in d:
		if not k in ["look", "stats", "wallet"]: extra[k] = d[k]
	var w: Variant = d.get("wallet")
	if w is Dictionary:
		for k: String in w:
			if not k in ["coins", "owned", "slots", "skins", "codes", "daily"]: extra_wallet[k] = w[k]
		if _num(w.get("coins")): coins = maxi(0, floori(float(w["coins"])))
		if w.get("owned") is Array:
			for k in w["owned"]:
				if k is String and LockerData.emote(k).size() > 0 and not owned.has(k): owned.append(k)
		if w.get("skins") is Array:
			for k in w["skins"]:
				if k is String and WobblerLooks.skin_def(k).size() > 0 and not skins.has(k): skins.append(k)
		for k: String in LockerData.free_skins():
			if not skins.has(k): skins.append(k)
		for k: String in skins:
			for id: String in LockerData.skin_emotes(k):
				if not owned.has(id): owned.append(id)
		if w.get("daily") is Dictionary and _num(w["daily"].get("d")):
			daily = {"d": floori(float(w["daily"]["d"])), "s": clampi(int(w["daily"].get("s", 0)), 0, 999)}
		if w.get("codes") is Array:
			for k in w["codes"]: if k is String: codes.append(k)
		if w.get("slots") is Array:
			for i in SLOTS:
				var v: Variant = w["slots"][i] if i < w["slots"].size() else null
				slots[i] = v if v is String and owned.has(v) else null
	var lk: Variant = d.get("look")
	if lk is Dictionary:
		if _num(lk.get("color")) and LockerData.swatch().has(int(lk["color"])): look["color"] = int(lk["color"])
		if lk.get("hat") is String and LockerData.hats().has(lk["hat"]): look["hat"] = lk["hat"]
		if lk.get("skin") is String and skins.has(lk["skin"]): look["skin"] = lk["skin"]
		if lk.get("cls") is String and WobblerLooks.data("classes").has(lk["cls"]): look["cls"] = lk["cls"]
	var s: Variant = d.get("stats")
	if s is Dictionary:
		for k: String in s:
			if not STAT_KEYS.has(k) and k != "hist": extra_stats[k] = s[k]
		for k: String in STAT_KEYS:
			if _num(s.get(k)) and k != "streak": stats[k] = maxf(0.0, float(s[k])) if k == "secs" else maxi(0, int(s[k]))
		if s.get("hist") is Array:
			for h in (s["hist"] as Array).slice(0, 8):
				if h is Dictionary:
					hist.append({"m": str(h.get("m", "")).substr(0, 24), "map": str(h.get("map", "")).substr(0, 24),
						"ko": int(h.get("ko", 0)), "d": int(h.get("d", 0)), "w": 1 if h.get("w") else 0, "o": 1 if h.get("o") else 0})
	changed.emit()
	return true

## The Sandbox arena (SandboxLayout): the blob's cfg (web cfg.custom, cfg.blocks; Godot cfg.blockCols). {} if none.
func sandbox_cfg() -> Dictionary:
	var c: Variant = extra.get("cfg")
	return (c as Dictionary).duplicate(true) if c is Dictionary else {}

## Stores the Sandbox arena (SandboxLayout.to_cfg(): custom, blocks, blockCols) in the blob's cfg, keeping the rest of
## cfg as the web game wrote it, then saves (the cloud save follows `changed`).
func set_sandbox(d: Dictionary) -> void:
	var c: Dictionary = (extra.get("cfg") as Dictionary).duplicate(true) if extra.get("cfg") is Dictionary else {}
	for k: String in ["custom", "blocks", "blockCols"]:
		if d.has(k): c[k] = d[k]
	extra["cfg"] = c
	_commit()

## Nothing played or bought yet (a new device): a cloud save can replace it without asking.
func is_fresh() -> bool:
	return coins == START_COINS and owned == ["wobble"] and skins.size() == 1 + LockerData.free_skins().size() \
		and int(stats["matches"]) == 0 and int(stats["kos"]) == 0 and hist.is_empty()

static func _num(v: Variant) -> bool:
	return (v is int or v is float) and is_finite(float(v))

# ============================== file ==============================

func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)

## Reads `path`, falling back to the backup when the file is damaged. Returns where it came from.
func load_file() -> String:
	reset()
	loaded_from = "new"
	for p: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(p): continue
		var blob: Variant = _read(p)
		if blob != null and apply_blob(blob):
			loaded_from = "file" if p == path else "backup"
			if loaded_from == "backup": push_warning("Save: profile was damaged, loaded the backup")
			return loaded_from
	return loaded_from

## The blob in a profile file (our wrapper of any format, or a raw web blob), or null if it is not readable.
static func _read(p: String) -> Variant:
	var t := FileAccess.get_file_as_string(p)
	if t.length() < 2: return null
	var js := JSON.new()                           # (an instance: a damaged file is not an engine error)
	if js.parse(t) != OK: return null
	var v: Variant = js.data
	if not (v is Dictionary): return null
	if v.has("format"):
		return v.get("data") if v.get("data") is Dictionary else null
	if v.has("wallet") or v.has("look") or v.has("stats"): return v      # format 0: a raw web blob
	return null

## Writes the profile (atomic: temp file + rename; the previous good file becomes the backup). false if not saved.
func save() -> bool:
	if not persist: return false
	var doc := {"format": FORMAT, "saved_at": int(Time.get_unix_time_from_system()), "data": get_blob()}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Save: cannot write " + tmp)
		return false
	f.store_string(JSON.stringify(doc))
	f.close()
	var now := Time.get_ticks_msec() / 1000.0
	if FileAccess.file_exists(path) and now - _bak_t >= BAK_EVERY and _read(path) != null:
		if DirAccess.copy_absolute(_abs(path), _abs(path + ".bak")) == OK: _bak_t = now
	var err := DirAccess.rename_absolute(_abs(tmp), _abs(path))
	if err != OK:                                   # some filesystems refuse to rename over a file
		DirAccess.remove_absolute(_abs(path))
		err = DirAccess.rename_absolute(_abs(tmp), _abs(path))
	return err == OK

func _commit() -> void:
	save()
	changed.emit()

# ============================== look + Settings mirror ==============================

func _push_settings() -> void:
	var st := _settings()
	if st == null: return
	_syncing = true
	st.set_value("skin", look["skin"]); st.set_value("hat", look["hat"])
	st.set_value("color", look["color"]); st.set_value("class", look["cls"])
	_syncing = false

## First run: keep what Settings already had (class picked in the wizard, colour, hat; an outfit only if owned).
func _adopt_settings(st: Node) -> void:
	var c := int(st.get_value("color", look["color"]))
	if LockerData.swatch().has(c): look["color"] = c
	var h := str(st.get_value("hat", "none"))
	if LockerData.hats().has(h): look["hat"] = h
	var s := str(st.get_value("skin", "none"))
	if skins.has(s): look["skin"] = s
	var cl := str(st.get_value("class", "wobbler"))
	if WobblerLooks.data("classes").has(cl): look["cls"] = cl

func _on_setting(key: String, v: Variant) -> void:
	if _syncing: return
	match key:
		"class": if str(v) != look["cls"]: set_class(str(v))
		"skin": if str(v) != look["skin"] and not wear_skin(str(v)): _push_settings()
		"hat": if str(v) != look["hat"]: set_hat(str(v))
		"color": if int(v) != look["color"]: set_color(int(v))

func _set_look(k: String, v: Variant) -> void:
	look[k] = v
	_push_settings()
	_commit()

func set_class(id: String) -> bool:
	if not WobblerLooks.data("classes").has(id): return false
	_set_look("cls", id)
	return true

func set_hat(h: String) -> bool:
	if not LockerData.hats().has(h): return false
	_set_look("hat", h)
	return true

func set_color(c: int) -> bool:
	if not LockerData.swatch().has(c): return false
	_set_look("color", c)
	return true

## Wear an owned outfit ("none" = no outfit). false if not owned.
func wear_skin(k: String) -> bool:
	if not skins.has(k): return false
	_set_look("skin", k)
	return true

# ============================== wallet ==============================

func owns_skin(k: String) -> bool:
	return skins.has(k)

func owns_emote(id: String) -> bool:
	return owned.has(id)

## Why an item can or cannot be bought: "ok", "owned", "coins" (not enough), "not_for_sale".
func buy_check(kind: String, k: String) -> String:
	if kind == "skin":
		if skins.has(k): return "owned"
		if not LockerData.is_shop_skin(k) or WobblerLooks.skin_def(k).is_empty(): return "not_for_sale"
		return "ok" if coins >= LockerData.skin_price(k) else "coins"
	if owned.has(k): return "owned"
	if not LockerData.is_shop_emote(k): return "not_for_sale"
	return "ok" if coins >= LockerData.emote_price(k) else "coins"

func price_of(kind: String, k: String) -> int:
	return LockerData.skin_price(k) if kind == "skin" else LockerData.emote_price(k)

## Coins still missing for an item (0 when you can afford it).
func missing(kind: String, k: String) -> int:
	return maxi(0, price_of(kind, k) - coins)

## Buys an outfit (web buySkin: it is equipped straight away and brings its own emotes) or an emote (web buyEmote: it
## goes into the first free slot). Returns buy_check()'s answer; "ok" means bought.
func buy(kind: String, k: String) -> String:
	var r := buy_check(kind, k)
	if r != "ok": return r
	coins -= price_of(kind, k)
	if kind == "skin":
		skins.append(k)
		for id: String in LockerData.skin_emotes(k):
			if not owned.has(id): _own_emote(id)
		look["skin"] = k
		_push_settings()
	else:
		_own_emote(k)
	_commit()
	return "ok"

func _own_emote(id: String) -> void:
	owned.append(id)
	var free := slots.find(null)
	if free >= 0: slots[free] = id

func add_coins(n: int) -> void:
	coins = maxi(0, coins + n)
	_commit()

## Puts an owned emote in slot `i` (it moves there if it was in another slot, like the web Locker).
func equip_emote(id: String, i: int = 0) -> bool:
	if not owned.has(id) or i < 0 or i >= SLOTS: return false
	var old := slots.find(id)
	if old >= 0: slots[old] = slots[i]
	slots[i] = id
	_commit()
	return true

## The emotes in the match wheel: the slots first, then the other owned emotes (rarest first), WHEEL_MAX at most.
func wheel_emotes() -> Array:
	var out: Array = []
	for s in slots:
		if s != null and not out.has(s): out.append(s)
	var rest := owned.filter(func(id: String) -> bool: return not out.has(id))
	rest.sort_custom(func(a: String, b: String) -> bool: return LockerData.rarity_rank(LockerData.emote_rarity(a)) < LockerData.rarity_rank(LockerData.emote_rarity(b)))
	out.append_array(rest)
	return out.slice(0, WHEEL_MAX)

## The cheapest outfit or emote you do not own yet: {kind, key, name, price} or {} when you own them all.
func next_unlock() -> Dictionary:
	var best := {}
	for k: String in LockerData.shop_skins():
		if not skins.has(k) and (best.is_empty() or LockerData.skin_price(k) < int(best["price"])):
			best = {"kind": "skin", "key": k, "name": LockerData.skin_name(k), "price": LockerData.skin_price(k)}
	for k: String in LockerData.shop_emotes():
		if not owned.has(k) and (best.is_empty() or LockerData.emote_price(k) < int(best["price"])):
			best = {"kind": "emote", "key": k, "name": LockerData.emote_name(k), "price": LockerData.emote_price(k)}
	return best

# ============================== match rewards + stats ==============================

## Coins for a finished match (web endMatch: +40, +60 more for a win) plus the K.O.s in it (web: +5 each, paid as
## they happen).
static func match_coins(kos: int, won: bool) -> int:
	return KO_COINS * kos + MATCH_COINS + (WIN_COINS if won else 0)

func begin_match() -> void:
	match_kos = 0
	match_hits = 0
	match_deaths = 0
	_streak = 0

## A K.O. happened: `mine` = the player scored it (+5 coins), `died` = the player was the one knocked out.
func on_ko(mine: bool, died: bool) -> void:
	if mine:
		match_kos += 1
		_streak += 1
		stats["kos"] += 1
		stats["best"] = maxi(int(stats["best"]), _streak)
		coins += KO_COINS
		changed.emit()
	if died:
		_streak = 0
		match_deaths += 1
		stats["deaths"] += 1

## The player landed a hit.
func on_hit() -> void:
	match_hits += 1
	stats["hits"] += 1

## Seconds played (counted while a match runs and is not paused).
func add_play_time(dt: float) -> void:
	stats["secs"] = float(stats["secs"]) + dt

## The match ended: stats, history, +40 / +100 coins, saved. Returns what the results panel shows:
## {coins (earned this match, K.O.s included), kos, won, total (coins now), next (next_unlock())}.
func finish_match(won: bool, mode_name: String = "", map_name: String = "", online: bool = false) -> Dictionary:
	stats["matches"] += 1
	if won: stats["wins"] += 1
	if online: stats["onl"] += 1
	hist.push_front({"m": mode_name.substr(0, 24), "map": map_name.substr(0, 24), "ko": match_kos, "d": match_deaths, "w": 1 if won else 0, "o": 1 if online else 0})
	if hist.size() > 8: hist.resize(8)
	var bonus := MATCH_COINS + (WIN_COINS if won else 0)
	coins += bonus
	var out := {"coins": bonus + KO_COINS * match_kos, "kos": match_kos, "hits": match_hits, "won": won, "total": coins, "next": next_unlock()}
	_commit()
	return out
