class_name StageEvents
extends RefCounted
## The Arcade stage events (data/extra/construction/stages.json `events`), driven by the ArcadeManager every sim step. Chaos
## (logic/mode_rules.gd) is the precedent: timed things announced with a toast; this class has its OWN RandomNumberGenerator
## (the manager's, seeded from the run seed), so the combat RNG and every other mode are never touched. Event types:
##   load_test       every N s: crate_count crates drop on random spots (one near you); a red ring warns warning_time
##                   seconds ahead, then the crate lands and hurts anyone under it (the boss too).
##   revision_pads   every N s: 3 boost pads appear for `duration` s (bounce power x boost_mul).
##   backup_call     once, when the boss is at hp_threshold: summon_count tradies (summon_bots names) join in.
##   deadline_shrink the floor shrinks with the Mega / Shrink mode machinery (ModeRules.shrink): holds `every` s, then
##                   closes in at `rate` m/s down to min_floor, breathes back out and closes again.
##   scope_creep     every N s: spawn_extra more tradies, at most max_extra alive at once.
##   change_request  at the boss phases (the stage table's hp thresholds, default 66 / 33 %): the boss (and you) get a
##                   random different melee tool; giant_scale makes the boss a Giant (the manager flags big_t).
##   weapon_drop     every N s on a boss stage: a gun or thrown tool arrives as a real pickup crate. The boss may take
##                   it while holding its melee kit; its ammo is not topped up.
## `counts` / `fired` record what fired and when (tests). `active_events()` is the online co-op host's `am.ev` source
## (docs/ARCADE_COOP_PLAN.md M4): the warning rings still on the floor, so a guest can draw the same red / amber rings
## without simulating the event (presentation only, the damage and the summon stay here).

const CRATE_R := 2.8
const CRATE_DMG := 30.0
const CRATE_FORCE := 12.0
const CRATE_DROP_Y := 16.0
const BACKUP_R := 1.6
const PAD_R := 1.5
const PAD_BASE_POWER := 17.0
const PAD_COUNT := 3
const SHRINK_BOTH_D := 64.0
const BOSS_RANGED := ["nailgun", "jackhammer", "anglegrinder", "conelauncher", "cementbucket"]

var m: ArcadeManager
var world: Node
var sim: MatchSim
var rng: RandomNumberGenerator
var evs: Array = []                    ## {type, every, params, t (seconds to the next), done}
var counts := {}                       ## type -> times fired
var fired: Array = []                  ## [stage time, type]
var t := 0.0
var _crates: Array = []                ## {x, z, gy, left, dur, node, ring}
var _pads: Array = []                  ## {pad, left, node}
var _summons: Array = []               ## {name, spot, left, node}: a backup call's warning rings, then the spawn
var _root: Node3D = null
var _swap_pool: Array = []
var _weapon_drop_cid := 900000
var _was_holding := true
var _ev_id := 0                        ## a stable id per warning event: `am.ev` dedupes the guest's rings by it

func setup(manager: ArcadeManager, s: MatchSim, stage: Dictionary, p_rng: RandomNumberGenerator) -> void:
	m = manager
	sim = s
	rng = p_rng
	evs = []
	for e: Dictionary in stage.get("events", []):
		var every := float(e.get("every", 0.0)) * float(manager.diff_def().get("event_mul", 1.0))     # easier = events come less often
		evs.append({"type": str(e["type"]), "every": every, "params": e.get("params", {}), "t": every, "done": false})
	for k: String in ["hammer", "wirewhip", "blower", "pipewrench", "nailgun", "jackhammer", "spiritlevel", "tapemeasure", "cementbucket",
			"conelauncher", "anglegrinder", "drill"]:
		if str(s.combat.wdata(k).get("type", "")) == "melee": _swap_pool.append(k)
	for e: Dictionary in evs:
		if e["type"] == "deadline_shrink": _setup_deadline(e)

func has(type: String) -> bool:
	for e: Dictionary in evs:
		if e["type"] == type: return true
	return false

func _toast(text: String) -> void:
	sim.combat.ev({"type": "toast", "text": text})

func _fire(type: String) -> void:
	counts[type] = int(counts.get(type, 0)) + 1
	fired.append([m.t_stage, type])

## A stable id for one warning event (a falling crate, a pending summon): the host sends it in `am.ev` and the guest
## keys its warning rings by it, so a repeated `am` neither doubles nor loses a ring.
func _next_ev_id() -> int:
	_ev_id += 1
	return _ev_id

## `am.ev` (M4): every warning ring still active on the floor, as {t:"load_test"|"backup_call", id, x, z, warn} where
## `warn` = seconds left before it lands/joins. Presentation only: the guest draws matching rings from these; it never
## damages, spawns crates or runs a timer itself.
func active_events() -> Array:
	var out: Array = []
	for h: Dictionary in _crates:
		out.append({"t": "load_test", "id": int(h["id"]), "x": snappedf(float(h["x"]), 0.01), "z": snappedf(float(h["z"]), 0.01),
			"warn": snappedf(maxf(float(h["left"]), 0.0), 0.1)})
	for s: Dictionary in _summons:
		var spot: Array = s["spot"]
		out.append({"t": "backup_call", "id": int(s["id"]), "x": snappedf(float(spot[0]), 0.01), "z": snappedf(float(spot[1]), 0.01),
			"warn": snappedf(maxf(float(s["left"]), 0.0), 0.1)})
	return out

# ---------------- per step ----------------

func update(dt: float) -> void:
	t += dt
	for e: Dictionary in evs:
		var every: float = e["every"]
		if every > 0.0 and e["type"] != "deadline_shrink":
			e["t"] -= dt
			if e["t"] <= 0.0:
				e["t"] += every
				match str(e["type"]):
					"load_test": _load_test(e["params"])
					"revision_pads": _revision(e["params"])
					"scope_creep": _creep(e["params"])
					"weapon_drop": _weapon_drop(e["params"])
		elif e["type"] == "backup_call" and not e["done"]:
			var p: Dictionary = e["params"]
			if m.boss != null and not m.boss.dead and m.boss_frac() <= float(p.get("hp_threshold", 0.5)):
				e["done"] = true
				_backup(p)
		elif e["type"] == "deadline_shrink":
			_watch_deadline()
	_update_crates(dt)
	_update_pads(dt)
	_update_summons(dt)

## The manager's boss phase n (1 = the first threshold): the change request swaps tools. The thresholds are the stage's
## own data (`change_request.params.phases`, PHASES fallback), so a phase the table does not list never swaps anything.
func on_phase(n: int) -> void:
	var ths: Array = m.phases() if m != null else ArcadeManager.PHASES
	for e: Dictionary in evs:
		if e["type"] != "change_request": continue
		if n < 1 or n > ths.size(): continue
		if bool((e["params"] as Dictionary).get("random_weapon_swap", true)):
			_change_request(n)

## The stage is over: pads and crates go away, and a pending backup call is cancelled (no ring, no late spawn).
func finish() -> void:
	for h: Dictionary in _crates: _free(h.get("node")); _free(h.get("ring"))
	_crates.clear()
	for q: Dictionary in _pads: _remove_pad(q)
	_pads.clear()
	for s: Dictionary in _summons: _free(s.get("node"))
	_summons.clear()

func _free(n: Variant) -> void:
	if n != null and is_instance_valid(n): (n as Node).queue_free()

func _fx_root() -> Node3D:
	if _root == null or not is_instance_valid(_root):
		_root = Node3D.new()
		_root.name = "StageEvents"
		world.add_child(_root)
	return _root

# ---------------- load_test ----------------

func _floor_spots() -> Array:
	var out: Array = []
	for sp: Variant in sim.pickups.spots:
		var a: Array = sp
		if a.size() < 3 or float(a[2]) <= 0.2: out.append(a)
	if out.is_empty(): out.append([0.0, 0.0])
	return out

func _load_test(p: Dictionary) -> void:
	var n := int(p.get("crate_count", 3))
	var warn := float(p.get("warning_time", 2.5))
	var spots := _floor_spots()
	var live: Array = m.living_seats()               # one crate near each player seat first (solo: near you)
	if live.is_empty(): live = [sim.player]
	_fire("load_test")
	_toast(TranslationServer.translate("Load test incoming! Crates falling!"))
	for i in n:
		var x := 0.0
		var z := 0.0
		if i < live.size():                            # the first ones land near the players: stay on your toes
			var seat: FighterState = live[i]
			var a := rng.randf_range(0.0, TAU)
			var r := rng.randf_range(0.5, 3.0)
			x = seat.phys.px + cos(a) * r
			z = seat.phys.pz + sin(a) * r
		else:
			var sp: Array = spots[rng.randi() % spots.size()]
			x = float(sp[0]); z = float(sp[1])
		_crates.append(_new_crate(x, z, warn))

func _new_crate(x: float, z: float, warn: float) -> Dictionary:
	var h := {"id": _next_ev_id(), "x": x, "z": z, "gy": 0.0, "left": warn, "dur": maxf(warn, 0.1), "node": null, "ring": null}
	if world != null:
		var ring := _warning_ring(x, z, 0.0, CRATE_R, Color(1.0, 0.18, 0.12, 0.45))
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.5, 1.5, 1.5)
		box.mesh = bm
		box.material_override = _unshaded(Color(0.85, 0.6, 0.18))
		box.position = Vector3(x, CRATE_DROP_Y, z)
		_fx_root().add_child(box)
		h["ring"] = ring; h["node"] = box
	return h

## A flat warning ring on the floor: red for a load-test crate, amber for a backup tradie.
func _warning_ring(x: float, z: float, gy: float, radius: float, col: Color) -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius; cm.bottom_radius = radius; cm.height = 0.06; cm.radial_segments = 20
	ring.mesh = cm
	ring.material_override = _unshaded(col)
	ring.position = Vector3(x, gy + 0.08, z)
	_fx_root().add_child(ring)
	return ring

func _unshaded(c: Color) -> StandardMaterial3D:
	var mt := StandardMaterial3D.new()
	mt.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mt.albedo_color = c
	if c.a < 1.0: mt.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mt

func _update_crates(dt: float) -> void:
	for i in range(_crates.size() - 1, -1, -1):
		var h: Dictionary = _crates[i]
		h["left"] -= dt
		var k := clampf(1.0 - float(h["left"]) / float(h["dur"]), 0.0, 1.0)
		if h["node"] != null and is_instance_valid(h["node"]):
			(h["node"] as Node3D).position.y = lerpf(CRATE_DROP_Y, 0.75, k * k)
			(h["node"] as Node3D).rotation.y += dt * 2.0
		if h["left"] <= 0.0:
			_land(h)
			_free(h.get("node")); _free(h.get("ring"))
			_crates.remove_at(i)

## The crate lands: everyone near the spot (on the floor, not up a scaffold) is hit and thrown.
func _land(h: Dictionary) -> void:
	var c := sim.combat
	for f: FighterState in sim.fighters:
		if f.dead or f.is_ghost: continue
		var dx := f.phys.px - float(h["x"])
		var dz := f.phys.pz - float(h["z"])
		var d := sqrt(dx * dx + dz * dz)
		if d > CRATE_R or absf(f.phys.py - float(h["gy"])) > 2.2: continue
		var nx := dx / d if d > 0.01 else 0.0
		var nz := dz / d if d > 0.01 else 1.0
		c.hit(f, CRATE_DMG, nx, 0.7, nz, CRATE_FORCE, false, null)
	c.ev({"type": "sfx", "name": "drop"})
	if world != null and world.has_method("add_shake"): world.add_shake(0.5)

# ---------------- revision_pads ----------------

func _revision(p: Dictionary) -> void:
	var dur := float(p.get("duration", 8.0))
	var mul := float(p.get("boost_mul", 1.6))
	var spots := _floor_spots()
	_fire("revision_pads")
	_toast(TranslationServer.translate("Revision pads active! Step carefully!"))
	for i in PAD_COUNT:
		var sp: Array = spots[rng.randi() % spots.size()]
		var pad := {"x": float(sp[0]), "z": float(sp[1]), "r": PAD_R, "power": PAD_BASE_POWER * mul, "temp": true}
		sim.pads.append(pad)
		var node: Node3D = null
		if world != null:
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = PAD_R; cm.bottom_radius = PAD_R; cm.height = 0.12; cm.radial_segments = 18
			mi.mesh = cm
			mi.material_override = _unshaded(Color(0.2, 0.9, 0.45))
			mi.position = Vector3(pad["x"], 0.1, pad["z"])
			_fx_root().add_child(mi)
			node = mi
		_pads.append({"pad": pad, "left": dur, "node": node})

func _update_pads(dt: float) -> void:
	for i in range(_pads.size() - 1, -1, -1):
		var q: Dictionary = _pads[i]
		q["left"] -= dt
		if q["node"] != null and is_instance_valid(q["node"]):       # blinks out in the last second
			(q["node"] as Node3D).visible = q["left"] > 1.0 or int(q["left"] * 8.0) % 2 == 0
		if q["left"] <= 0.0:
			_remove_pad(q)
			_pads.remove_at(i)

func _remove_pad(q: Dictionary) -> void:
	sim.pads.erase(q["pad"])
	_free(q.get("node"))

# ---------------- backup_call / scope_creep ----------------

## One backup call: every summoned tradie gets a visible ground ring first, then joins after `warning_time` s (1.5 s in
## the table). The old version spawned on the first frame the boss crossed 50 % HP with no cue, which was a silent
## difficulty spike; the ring gives the player time to move and makes the "pressed" moment readable.
func _backup(p: Dictionary) -> void:
	_fire("backup_call")
	var warn := maxf(0.1, float(p.get("warning_time", 1.5)))
	var names: Array = p.get("summon_bots", [])
	_toast(TranslationServer.translate("Backup incoming! Watch the warning ring."))
	for i in int(p.get("summon_count", 2)):
		var spot: Array = m.pick_minion_spot()
		var gy := float(spot[2]) if spot.size() > 2 else 0.0
		var ring := _warning_ring(float(spot[0]), float(spot[1]), gy, BACKUP_R, Color(1.0, 0.55, 0.1, 0.5))
		_summons.append({"id": _next_ev_id(), "name": str(names[i % names.size()]) if names.size() > 0 else "", "spot": spot, "left": warn, "node": ring})

func _update_summons(dt: float) -> void:
	for i in range(_summons.size() - 1, -1, -1):
		var s: Dictionary = _summons[i]
		s["left"] -= dt
		if s["left"] > 0.0: continue
		_free(s.get("node"))
		_summons.remove_at(i)
		m.spawn_minion(str(s["name"]), s["spot"])
		_toast(TranslationServer.translate("Supervisor called in backup tradies!"))

func _creep(p: Dictionary) -> void:
	var extra := 0
	for e: FighterState in m.enemies:
		if e != m.boss and not m.downed.has(e): extra += 1
	var room := int(p.get("max_extra", 3)) - extra
	if room <= 0: return
	_fire("scope_creep")
	_toast(TranslationServer.translate("Scope creep! Extra workers arriving!"))
	for i in mini(int(p.get("spawn_extra", 1)), room): m.spawn_minion()

# ---------------- weapon_drop ----------------

## A boss-stage weapon crate. The stage owns the random draw; the crate pickup itself stays on the normal physics path,
## so either the player or the boss can claim it. Only the boss is allowed to take it while already holding a melee tool.
func _weapon_drop(p: Dictionary) -> void:
	if m.boss == null or m.boss.dead or m.downed.has(m.boss): return
	var keys: Array = BOSS_RANGED.filter(func(k: String) -> bool: return not sim.combat.wdata(k).is_empty())
	if keys.is_empty() or sim.pickups.spots.is_empty(): return
	_fire("weapon_drop")
	_toast(TranslationServer.translate("Tool crate incoming! First to it keeps the advantage."))
	var count := maxi(1, int(p.get("weapon_count", 1)))
	for i in count:
		var key: String = keys[rng.randi() % keys.size()]
		var spots := _floor_spots()
		var sp: Array = spots[rng.randi() % spots.size()]
		_weapon_drop_cid += 1
		sim.pickups.spawn_at(key, sp, _weapon_drop_cid)

# ---------------- deadline_shrink ----------------

## The floor closes in with the Mega / Shrink machinery: ModeRules.shrink on the generated site's floor (box 0).
func _setup_deadline(e: Dictionary) -> void:
	if sim.solids.is_empty(): return
	var p: Dictionary = e["params"]
	var box: Variant = sim.solids[0]
	var size := float(box.maxX) - float(box.minX)
	var mn := minf(float(p.get("min_floor", 18.0)), size)
	var rate_s := maxf(1.0, (size - mn) / maxf(0.1, float(p.get("rate", 2.0))))      # `rate` m/s as ModeRules' seconds to the minimum
	var spots: Array = []
	for sp: Variant in sim.pickups.spots: spots.append(sp)
	sim.combat.rules.shrink = {"S0": size, "size": size, "start": size, "min": mn, "max": size, "dir": -1, "cycle": 0,
		"hold": float(e["every"]), "both": true, "D": size, "rate": rate_s, "rest": -1.0, "box": box, "id": sim.map_id, "spots": spots}
	_was_holding = true

func _watch_deadline() -> void:
	var s: Dictionary = sim.combat.rules.shrink
	if s.is_empty(): return
	var holding: bool = s["hold"] > 0.0
	if _was_holding and not holding and int(s["dir"]) == -1:
		_fire("deadline_shrink")
		_toast(TranslationServer.translate("Deadline approaching! Floor is shrinking!"))
	_was_holding = holding

# ---------------- change_request ----------------

func _random_tool(not_this: String) -> String:
	var pool: Array = _swap_pool.filter(func(k: String) -> bool: return k != not_this)
	return pool[rng.randi() % pool.size()] if pool.size() > 0 else not_this

func _change_request(n: int) -> void:
	_fire("change_request")
	_toast(TranslationServer.translate("Change request approved! Weapons swapped!"))
	if m.boss != null and not m.boss.dead:
		m.give_weapon(m.boss, _random_tool(str(m.kit.get(m.boss, ""))))
	for p: FighterState in m.living_seats():       # every live player seat gets a new tool too
		if p.dead: continue
		var cur := ""
		if p.slot >= 0 and p.slots[p.slot] != null: cur = str(p.slots[p.slot]["key"])
		var key := _random_tool(cur)
		sim.combat.pickup(p, key)
		for i in 3:
			if p.slots[i] != null and p.slots[i]["key"] == key and p.slot != i: sim.combat.equip_slot(p, i)
