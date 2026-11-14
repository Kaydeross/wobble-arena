class_name ArcadeCoop
extends RefCounted
## Arcade co-op room helpers (docs/ARCADE_COOP_PLAN.md M1, protocol docs/PROTOCOL.md 6.4): the single place that builds a
## room's player-seat + crew slot table and the `start.arc` run snapshot the host sends with every stage.
##
## slots = [seat0, seat1, crew0, crew1, …] (the positional table MatchSim/HostMatch already use: slot k <-> sim.fighters[k])
## and `arc` = {run, st, of, diff, seed, seats:[0,1], crew:[2,…], boss, big, state, lv, ff}:
##   run   the run seed (seed_base; stage_seed = run + the stage's map_seed_offset + 1009 * attempt)
##   st/of this stage index (0-based) and the stage count
##   seed  this stage's generated-site seed (SiteMap.set_seed; the guest rebuilds the same site from it)
##   seats/crew which slots are player seats and which are the stage's crew bots (the boss is crew[0])
##   boss  the boss' slot (-1 on a stage without one), big = the 1.5x Client visual
##   state/lv the host's run state ("intro" per stage) and the shared lives
##   ff    co-op friendly fire between the two seats (owner decision: false by default; hub toggle Settings arcade_ff)
## The stage table (res://data/extra/construction/stages.json) is read here once and nowhere else in the net layer.
## ArcadeManager stays the run authority; `stage_arc(manager)` snapshots its live state for the next `start`.

const STAGES_PATH := "res://data/extra/construction/stages.json"
const SEATS := 2                              ## owner decision: two players per room
const TEAMMATE_NAME := "Teammate Bot"
const DEFAULT_DIFF := "normal"
const RETRY_SEED_STEP := 1009                 ## ArcadeManager.RETRY_SEED_STEP (a retry gets a fresh site)
const U32 := 0xFFFFFFFF
const STATES := ["idle", "intro", "fight", "clearing", "cleared", "failing", "failed", "over", "won"]

static var _table: Dictionary = {}

## The parsed stages table ({difficulties, stages}).
static func table() -> Dictionary:
	if _table.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGES_PATH)) if FileAccess.file_exists(STAGES_PATH) else null
		if v is Dictionary: _table = v
	return _table

static func stages() -> Array:
	var s: Variant = table().get("stages", [])
	return s if s is Array else []

static func count() -> int:
	return stages().size()

static func stage_def(stage: int) -> Dictionary:
	var list := stages()
	if list.is_empty(): return {}
	var i := clampi(stage, 0, list.size() - 1)
	return list[i] if list[i] is Dictionary else {}

static func difficulties() -> Dictionary:
	var d: Variant = table().get("difficulties", {})
	return d if d is Dictionary else {}

## A difficulty id the table knows (unknown -> normal).
static func norm_diff(id: String) -> String:
	return id if difficulties().has(id) else DEFAULT_DIFF

## The shared run lives at this difficulty (ArcadeManager start_run reads the same numbers).
static func lives_for(diff: String) -> int:
	var dd: Dictionary = difficulties().get(norm_diff(diff), {})
	return int(dd.get("lives", 3))

## The generated site of a stage: seed_base + the stage's offset + a fresh offset per retry (ArcadeManager.stage_seed).
static func stage_seed(run: int, stage: int, attempt: int = 0) -> int:
	return run + int(stage_def(stage).get("map_seed_offset", 0)) + attempt * RETRY_SEED_STEP

## The map the run plays on (the generated site when it exists, else the Site Yard). The Content autoload is looked up
## at runtime: the net tests compile this script before the autoloads exist (a static reference would fail that compile).
static func site_map() -> String:
	var c := _content()
	if c != null and c.get("maps") is Dictionary and (c.get("maps") as Dictionary).has("sitegen"): return "sitegen"
	return "siteyard"

static func _content() -> Node:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree): return null
	return (loop as SceneTree).root.get_node_or_null("Content")

static func is_boss(stage: int) -> bool:
	return bool(stage_def(stage).get("boss", false))

static func stage_name(stage: int) -> String:
	return str(stage_def(stage).get("name", ""))

## The stage's giant scale (the Client's 1.5x look): > 1 = `arc.big`, the boss is drawn big by the guest.
static func is_big(stage: int) -> bool:
	for ev: Variant in stage_def(stage).get("events", []):
		if ev is Dictionary and ev.get("params") is Dictionary:
			if float((ev["params"] as Dictionary).get("giant_scale", 1.0)) > 1.0: return true
	return false

## How many crew bots the stage sends (its `bots` entry count).
static func crew_count(stage: int) -> int:
	var b: Variant = stage_def(stage).get("bots", [])
	return (b as Array).size() if b is Array else 0

## The room slots of the stage's crew: right after the seats.
static func crew_ids(stage: int, seat_count: int = SEATS) -> Array:
	var out: Array = []
	for i in crew_count(stage): out.append(clampi(seat_count, 1, SEATS) + i)
	return out

## The boss' room slot: crew[0] on a boss stage, -1 otherwise.
static func boss_slot(stage: int, seat_count: int = SEATS) -> int:
	return clampi(seat_count, 1, SEATS) if is_boss(stage) and crew_count(stage) > 0 else -1

static func seat_slots(seat_count: int = SEATS) -> Array:
	var out: Array = []
	for k in clampi(seat_count, 1, SEATS): out.append(k)
	return out

## `start.arc` for one stage, from explicit values (the host's first start and the tests).
static func arc_for_stage(run: int, diff: String, stage: int, lives: int, state: String = "intro",
		seat_count: int = SEATS, attempt: int = 0, ff: bool = false) -> Dictionary:
	var d := norm_diff(diff)
	var st := clampi(stage, 0, maxi(0, count() - 1))
	return {"run": maxi(1, run), "st": st, "of": count(), "diff": d, "seed": stage_seed(maxi(1, run), st, attempt),
		"seats": seat_slots(seat_count), "crew": crew_ids(st, seat_count), "boss": boss_slot(st, seat_count),
		"big": is_big(st), "state": state if state in STATES else "intro", "lv": maxi(0, lives), "ff": ff}

## The arc of a brand-new run (stage 0).
static func run_start_arc(run: int, diff: String, seat_count: int = SEATS, ff: bool = false) -> Dictionary:
	return arc_for_stage(run, diff, 0, lives_for(diff), "intro", seat_count, 0, ff)

## The live arc of an ArcadeManager (dynamic: it does not reference the class, so there is no class_name cycle):
## the next stage's `start` and a mid-match rejoin both use exactly this snapshot. `m` is an ArcadeManager object, so
## these are Object.get(property) reads (one argument), not Dictionary.get.
static func stage_arc(m) -> Dictionary:
	var stage := int(m.get("stage"))
	var seats := int(m.get("seat_count"))
	return arc_for_stage(int(m.get("seed_base")), str(m.get("diff")), stage, int(m.get("lives")),
		str(m.get("state")), seats, int(m.get("attempt")), bool(m.get("friendly_fire")))

## The crew slots of a stage: bot entries as `start.slots` / MatchSim expect them (id = its room slot, after the seats).
## The look/name come from the stage table; `cls` is the placeholder class MatchSim gives that bot in slot order (the
## host's HostMatch rewrites the whole entry with the real bot info when the stage is set up).
static func crew_slots(diff: String, stage: int) -> Array:
	var out: Array = []
	var bots: Array = stage_def(stage).get("bots", [])
	var seats := SEATS
	for i in bots.size():
		var spec: Dictionary = bots[i] if bots[i] is Dictionary else {}
		var slot := seats + i
		var cls: String = MatchSim.BOT_CLASS_ORDER[(slot - 1) % MatchSim.BOT_CLASS_ORDER.size()]
		out.append({"kind": "bot", "id": slot, "name": str(spec.get("name", "Bot")),
			"skin": str(spec.get("skin", "builder")), "hat": str(spec.get("hat", "none")),
			"color": int(spec.get("color", 0x39b5a8)), "cls": cls})
	return out

## A seat nobody took: the teammate bot the room may start with (the owner's 1 human + 1 bot lobby).
static func teammate_slot(id: int, info: Dictionary) -> Dictionary:
	return {"kind": "bot", "id": id, "name": TEAMMATE_NAME,
		"skin": str(info.get("skin", "none")), "hat": str(info.get("hat", "none")),
		"color": int(info.get("color", 0x39b5a8)), "cls": str(info.get("cls", "wobbler"))}

## Is `a` a usable `start.arc`? (an online Arcade world needs at least a stage, a run seed and its seats)
static func arc_valid(a: Variant) -> bool:
	if not (a is Dictionary): return false
	var d: Dictionary = a
	if not (d.get("seats") is Array) or (d["seats"] as Array).is_empty(): return false
	if not (d.get("run") is float or d.get("run") is int): return false
	if not (d.get("st") is float or d.get("st") is int): return false
	return count() > 0

## A one-line summary for logs / tests: "st=0/6 diff=normal seed=1234 seats=[0,1] crew=[2,3,4,5] boss=-1 big=false".
static func arc_text(a: Dictionary) -> String:
	return "st=%d/%d diff=%s seed=%d seats=%s crew=%s boss=%d big=%s state=%s lv=%d" % [
		int(a.get("st", -1)), int(a.get("of", count())), str(a.get("diff", "?")), int(a.get("seed", -1)),
		str(a.get("seats", [])), str(a.get("crew", [])), int(a.get("boss", -1)), str(bool(a.get("big", false))),
		str(a.get("state", "?")), int(a.get("lv", -1))]
