class_name Pickups
extends RefCounted
## Weapon crates that fall from the sky, ported from the web game (pickCrateKey, spawnDrop, updatePickups,
## public/index.html ~6086-6250). Pure logic: the world draws `list` and reacts to `combat.events`
## ("crate", "crate_land", "crate_take", "crate_gone", "toast").
## Weights and rarities come from res://data/drops.json (shared/drops.json), the rate from crate-rates.json.

## Weapons bots walk to when empty-handed (BOT_GUNS ~6180, bot tuning that is not in shared/).
const BOT_GUNS := ["net", "flame", "katana", "boomerang", "shuriken", "bow", "glauncher", "cluster", "knife", "snake", "snow",
	"ak", "smg", "minigun", "revolver", "mammoth", "typhoon", "uzi", "shotgun", "sniper", "rocket", "meteor", "bat", "glove",
	"mallet", "trident", "snow"]
const PU_TIMERS := {"speed": "spd_t", "rage": "rage_t", "shield": "shield_t"}
const MAX_CRATES := 10
const LIFETIME := 45.0

var combat: Combat
var drops := {}                  ## drops.json
var rates := {}                  ## crate-rates.json
var crate_rate := "normal"       ## cfg.crate
var wstate := {}                 ## cfg.wstate: weapon key -> off/rare/normal/often
var spots: Array = []            ## MAPS[map].drops ([x, z, floor y?])
var no_crates := false           ## MAPS[map].noCrates or a Weapon Ladder mode
var drop_timer := 2.5
## Only drop weapons the Godot port can use yet (Phase 1 slice). false = the web game's full pool.
var ported_only := true
## Live crates: {id, key, spot (index), gy, x, z, y, vy, grounded, open, t, age}
var list: Array = []
## permQ: rack weapons (Practice Range / Test Map, place_perm) that were taken come back here after 2.5 s: {key, x, z, t}.
var perm_q: Array = []
var _next_id := 0
## Online guest: only the host drops crates; they arrive as `crate`/`crates` messages (spawn_at) and leave on `take`.
var remote := false
## Arcade boss stages: their owner may take a ranged weapon crate even while carrying its melee kit.
var armed_weapon_crates := false
var armed_weapon_crate_owner: FighterState = null

func _init(c: Combat, drops_data: Dictionary, rates_data: Dictionary) -> void:
	combat = c
	drops = drops_data
	rates = rates_data

## loadMap: the crate spots of a map, first crate after 1 s.
func set_map(map: Dictionary) -> void:
	spots = map.get("drops", [])
	no_crates = bool(map.get("noCrates", false)) or bool(combat.mode.get("ladder", false))
	list.clear()
	perm_q.clear()
	drop_timer = 1.0

## pickCrateKey: weighted by each weapon's rarity setting, only what the mode allows. "" = nothing allowed.
func pick_crate_key() -> String:
	var tot := 0.0
	var ents: Array = []
	var al: Dictionary = drops.get("allow", {})
	var allow: Array = al.get(combat.mode_id, combat.mode["dropAllow"] if combat.mode.get("dropAllow") is Array else al.get(str(combat.mode.get("dropsAs", "")), []))   # Godot-only modes borrow a pool
	var base: Dictionary = drops.get("base", {})
	var mult: Dictionary = drops.get("mult", {})
	var tuned: Dictionary = combat.tuned_drops if combat.tuning_active() else {}   # weapon_tuning.json crate weights
	for k: String in base:
		if not allow.has(k): continue
		if ported_only and not usable(k): continue
		var w := float(tuned.get(k, base[k])) * float(mult.get(wstate.get(k, "normal"), 1.0))
		if combat.mode_id == "ninja":   # Ninja: fewer shuriken, more of the other ninja weapons
			w *= float({"shuriken": 0.4, "knife": 1.3, "katana": 1.5, "typhoon": 1.5}.get(k, 1.0))
		if w > 0.0:
			ents.append([k, w]); tot += w
	if tot == 0.0:
		return ""
	var r := combat.rng.next() * tot
	for e: Array in ents:
		r -= e[1]
		if r <= 0.0: return e[0]
	return ents[ents.size() - 1][0]

## spawnDrop: a crate falls at a free crate spot. Returns the crate or {}.
func spawn_drop(force_key: String = "") -> Dictionary:
	if list.size() >= MAX_CRATES and force_key == "":
		return {}
	var key := force_key if force_key != "" else pick_crate_key()
	if key == "" or spots.is_empty():
		return {}
	var used := {}
	for p: Dictionary in list: used[p["spot"]] = true
	var si := int(floor(combat.rng.next() * spots.size()))
	var i := 0
	while i < 12 and used.has(si):
		si = int(floor(combat.rng.next() * spots.size())); i += 1
	var spot: Array = spots[si]
	var gy := float(spot[2]) if spot.size() > 2 else 0.0
	_next_id += 1
	var p := {"id": _next_id, "key": key, "spot": si, "gy": gy, "x": float(spot[0]), "z": float(spot[1]), "y": 26.0 + gy, "vy": 0.0,
		"grounded": false, "open": 0.0, "t": 0.0, "age": 0.0}
	list.append(p)
	combat.ev({"type": "crate", "crate": p})
	combat.ev({"type": "toast", "text": tr("Crate incoming: %s! Look up") % tr(label(key))})
	return p

## spawnDrop(key, {x, z}): a weapon laid out on the floor (the Practice Range rack, the Test Map grid). Already landed
## and open, never expires, and comes back 2.5 s after somebody takes it (permQ). No random numbers, no toast.
func place_perm(key: String, x: float, z: float) -> Dictionary:
	_next_id += 1
	var p := {"id": _next_id, "key": key, "spot": -1, "gy": 0.0, "x": x, "z": z, "y": 0.4, "vy": 0.0,
		"grounded": true, "open": 1.0, "t": 0.0, "age": 0.0, "perm": true}
	list.append(p)
	combat.ev({"type": "crate", "crate": p})
	return p

## spawnDrop(key, null, spot) for a crate the host announced (`crate` message): `spot` = [x, z, floor y?] as in
## MAPS[map].drops, `cid` = the host's crate id (sent back in `take`). Returns the crate or {} for junk.
func spawn_at(key: String, spot: Variant, cid: int) -> Dictionary:
	if not (spot is Array) or spot.size() < 2 or cid <= 0 or find_cid(cid) >= 0:
		return {}
	if key != "heal" and not drops.get("powerups", {}).has(key) and combat.wdata(key).is_empty():
		return {}
	var x := NetSnapshot.num(spot[0], -500.0, 500.0, NAN)
	var z := NetSnapshot.num(spot[1], -500.0, 500.0, NAN)
	if is_nan(x) or is_nan(z):
		return {}
	var gy := NetSnapshot.num(spot[2], -100.0, 200.0, 0.0) if spot.size() > 2 else 0.0
	var si := -1
	for k in spots.size():
		if is_equal_approx(float(spots[k][0]), x) and is_equal_approx(float(spots[k][1]), z): si = k
	_next_id += 1
	var p := {"id": _next_id, "cid": cid, "key": key, "spot": si, "gy": gy, "x": x, "z": z, "y": 26.0 + gy, "vy": 0.0,
		"grounded": false, "open": 0.0, "t": 0.0, "age": 0.0}
	list.append(p)
	combat.ev({"type": "crate", "crate": p})
	combat.ev({"type": "toast", "text": tr("Crate incoming: %s! Look up") % tr(label(key))})
	return p

## Index in `list` of the crate with the host's id `cid`, or -1.
func find_cid(cid: int) -> int:
	for i in list.size():
		if int(list[i].get("cid", 0)) == cid: return i
	return -1

## Somebody else took crate `cid` (`take` message).
func remove_cid(cid: int) -> bool:
	var i := find_cid(cid)
	if i < 0: return false
	var p: Dictionary = list[i]
	list.remove_at(i)
	combat.ev({"type": "crate_gone", "crate": p})
	return true

## Heal, power-ups and the weapons whose behaviour is ported (melee, hitscan guns incl. shotgun/Uzi/minigun, thrown knives,
## the Air Blower).
func usable(key: String) -> bool:
	if key == "heal" or PU_TIMERS.has(key): return true
	var w := combat.wdata(key)
	match String(w.get("type", "")):
		"melee", "blower": return true
		"gun": return true
	return Weapons.LAUNCH.has(String(w.get("type", "")))

## Display name of a drop key (weapon, heal or power-up).
func label(key: String) -> String:
	if key == "heal": return str(drops.get("heal", {}).get("name", "Health Pack"))
	var pu: Dictionary = drops.get("powerups", {})
	if pu.has(key): return str(pu[key].get("name", key))
	return str(combat.wdata(key).get("name", key))

## botWants: bots grab health when hurt, every power-up, and a weapon only when empty-handed. Arcade bosses may also
## take a ranged weapon crate while their melee kit is in hand; the crate replaces what they hold for that pickup.
func bot_wants(b: FighterState, p: Dictionary) -> bool:
	if not combat.brawl: return false
	var key: String = p["key"]
	if key == "heal": return b.hp < combat.max_hp(b) * 0.85
	if drops.get("powerups", {}).has(key): return true
	var w := combat.wdata(key)
	var is_ranged := BOT_GUNS.has(key) or (combat.mode_id == "construction" and ["gun", "knife", "ball"].has(str(w.get("type", ""))))
	if not is_ranged: return false
	return b.slot < 0 or (armed_weapon_crates and (armed_weapon_crate_owner == null or armed_weapon_crate_owner == b))

## updatePickups: drop timer, falling, landing, being picked up, expiring.
func update(dt: float) -> void:
	for i in range(perm_q.size() - 1, -1, -1):
		var q: Dictionary = perm_q[i]
		q["t"] -= dt
		if q["t"] <= 0.0:
			perm_q.remove_at(i)
			place_perm(q["key"], q["x"], q["z"])
	drop_timer -= dt
	if not no_crates and not remote and drop_timer <= 0.0:
		drop_timer = combat.rng.range_f(3, 5) * float(rates.get(crate_rate, 0.42))
		spawn_drop()
	for i in range(list.size() - 1, -1, -1):
		var p: Dictionary = list[i]
		p["age"] += dt; p["t"] += dt
		if not p["grounded"]:
			p["vy"] -= 14.0 * dt; p["y"] += p["vy"] * dt
			if p["y"] <= p["gy"] + 0.4:
				p["y"] = p["gy"] + 0.4; p["vy"] = 0.0; p["grounded"] = true
				combat.ev({"type": "crate_land", "crate": p})
		if p["grounded"] and p["open"] < 1.0:
			p["open"] = minf(1.0, p["open"] + dt / 0.7)
		if p["grounded"]:
			var taker: FighterState = null
			for f: FighterState in combat.fighters:
				if f.dead or f.is_ghost: continue
				if not f.is_player and not bot_wants(f, p): continue
				var dx: float = f.phys.px - p["x"]
				var dz: float = f.phys.pz - p["z"]
				if dx * dx + dz * dz < 1.3 * 1.3 and absf(f.phys.py - (p["y"] - 0.4)) < 2.0:
					_take(f, p["key"]); taker = f
					break
			if taker != null:
				if p.get("perm", false): perm_q.append({"key": p["key"], "x": p["x"], "z": p["z"], "t": 2.5})
				list.remove_at(i)
				combat.ev({"type": "crate_take", "crate": p, "f": taker})
				continue
		if p["age"] > LIFETIME and not p.get("perm", false):
			list.remove_at(i)
			combat.ev({"type": "crate_gone", "crate": p})

func _take(f: FighterState, key: String) -> void:
	if key == "heal":
		f.hp = minf(combat.max_hp(f), f.hp + combat.max_hp(f) * f.heal_frac)
		if f.is_player: combat.ev({"type": "toast", "text": "+%d health!" % roundi(f.heal_frac * 100.0)})
	elif PU_TIMERS.has(key):
		f.set(PU_TIMERS[key], 12.0)
		if f.is_player: combat.ev({"type": "toast", "text": str(drops.get("powerups", {}).get(key, {}).get("msg", key))})
	else:
		var boss_pickup := armed_weapon_crates and armed_weapon_crate_owner == f
		combat.pickup(f, key)
		if boss_pickup:
			for i in 3:
				if f.slots[i] != null and str(f.slots[i]["key"]) == key:
					combat.equip_slot(f, i)
					break
