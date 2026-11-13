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
##   change_request  at the boss phases (66 / 33 % health): the boss (and you) get a random different tool; giant_scale
##                   makes the boss a Giant (the manager flags big_t).
## `counts` / `fired` record what fired and when (tests).

const CRATE_R := 2.8
const CRATE_DMG := 30.0
const CRATE_FORCE := 12.0
const CRATE_DROP_Y := 16.0
const PAD_R := 1.5
const PAD_BASE_POWER := 17.0
const PAD_COUNT := 3
const SHRINK_BOTH_D := 64.0

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
var _root: Node3D = null
var _swap_pool: Array = []
var _was_holding := true

func setup(manager: ArcadeManager, s: MatchSim, stage: Dictionary, p_rng: RandomNumberGenerator) -> void:
	m = manager
	sim = s
	rng = p_rng
	evs = []
	for e: Dictionary in stage.get("events", []):
		var every := float(e.get("every", 0.0))
		evs.append({"type": str(e["type"]), "every": every, "params": e.get("params", {}), "t": every, "done": false})
	for k: String in ["hammer", "wirewhip", "blower", "pipewrench", "nailgun", "jackhammer", "spiritlevel", "tapemeasure", "cementbucket",
			"conelauncher", "anglegrinder", "drill"]:
		if not s.combat.wdata(k).is_empty(): _swap_pool.append(k)
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
		elif e["type"] == "backup_call" and not e["done"]:
			var p: Dictionary = e["params"]
			if m.boss != null and not m.boss.dead and m.boss_frac() <= float(p.get("hp_threshold", 0.5)):
				e["done"] = true
				_backup(p)
		elif e["type"] == "deadline_shrink":
			_watch_deadline()
	_update_crates(dt)
	_update_pads(dt)

## The manager's boss phase n (1 = 66 %, 2 = 33 %): the change request swaps tools.
func on_phase(n: int) -> void:
	for e: Dictionary in evs:
		if e["type"] == "change_request" and bool((e["params"] as Dictionary).get("random_weapon_swap", true)):
			_change_request(n)

## The stage is over: pads and crates go away.
func finish() -> void:
	for h: Dictionary in _crates: _free(h.get("node")); _free(h.get("ring"))
	_crates.clear()
	for q: Dictionary in _pads: _remove_pad(q)
	_pads.clear()

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
	_fire("load_test")
	_toast(TranslationServer.translate("Load test incoming! Crates falling!"))
	for i in n:
		var x := 0.0
		var z := 0.0
		if i == 0:                                 # the first one lands near you: stay on your toes
			var a := rng.randf_range(0.0, TAU)
			var r := rng.randf_range(0.5, 3.0)
			x = sim.player.phys.px + cos(a) * r
			z = sim.player.phys.pz + sin(a) * r
		else:
			var sp: Array = spots[rng.randi() % spots.size()]
			x = float(sp[0]); z = float(sp[1])
		_crates.append(_new_crate(x, z, warn))

func _new_crate(x: float, z: float, warn: float) -> Dictionary:
	var h := {"x": x, "z": z, "gy": 0.0, "left": warn, "dur": maxf(warn, 0.1), "node": null, "ring": null}
	if world != null:
		var ring := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = CRATE_R; cm.bottom_radius = CRATE_R; cm.height = 0.06; cm.radial_segments = 20
		ring.mesh = cm
		ring.material_override = _unshaded(Color(1.0, 0.18, 0.12, 0.45))
		ring.position = Vector3(x, 0.08, z)
		_fx_root().add_child(ring)
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.5, 1.5, 1.5)
		box.mesh = bm
		box.material_override = _unshaded(Color(0.85, 0.6, 0.18))
		box.position = Vector3(x, CRATE_DROP_Y, z)
		_fx_root().add_child(box)
		h["ring"] = ring; h["node"] = box
	return h

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

func _backup(p: Dictionary) -> void:
	_fire("backup_call")
	_toast(TranslationServer.translate("Supervisor called in backup tradies!"))
	var names: Array = p.get("summon_bots", [])
	for i in int(p.get("summon_count", 2)):
		m.spawn_minion(str(names[i % names.size()]) if names.size() > 0 else "")

func _creep(p: Dictionary) -> void:
	var extra := 0
	for e: FighterState in m.enemies:
		if e != m.boss and not m.downed.has(e): extra += 1
	var room := int(p.get("max_extra", 3)) - extra
	if room <= 0: return
	_fire("scope_creep")
	_toast(TranslationServer.translate("Scope creep! Extra workers arriving!"))
	for i in mini(int(p.get("spawn_extra", 1)), room): m.spawn_minion()

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
	var p := sim.player
	if not p.dead:                                 # you get a new tool too
		var cur := ""
		if p.slot >= 0 and p.slots[p.slot] != null: cur = str(p.slots[p.slot]["key"])
		var key := _random_tool(cur)
		sim.combat.pickup(p, key)
		for i in 3:
			if p.slots[i] != null and p.slots[i]["key"] == key and p.slot != i: sim.combat.equip_slot(p, i)
