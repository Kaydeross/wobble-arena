class_name ArcadeManager
extends RefCounted
## The Construction DLC Arcade boss rush: a run controller (docs/CONSTRUCTION_DLC.md "Unit D: Arcade").
## A run is six stages (data/extra/construction/stages.json) played one after another in the same World, each on its own
## generated building site (map "sitegen", SiteMap.set_seed(base seed + the stage's map_seed_offset + 1009 per retry),
## else "siteyard"). The player has LIVES lives: dying ends the stage attempt, costs a life and retries the SAME stage on a
## fresh site; out of lives the run is over. A stage is cleared when its boss is down (stages with a boss) or every enemy is
## (the tradies); the crew that is left gives up. Coins (coin_reward + first_clear_bonus) are paid ONCE per stage, the first
## time it is cleared (Save.dlc arcade_clears), arcade_best keeps the furthest stage; the final victory pays bonus coins and
## the exclusive Site Foreman hard hat once (arcade_clears "_victory").
## Everything here is gated on `World.arcade` being set: no other mode runs any of it. The run owns ITS OWN
## RandomNumberGenerator (seeded from the run seed, never the combat RNG), so scripting never moves a random draw.
## World hooks (world/world.gd): begin_stage (top of load_map), setup_sim (after MatchSim.setup), stage_ready (end of load_map),
## step (after every sim step), plus show_panel / close_panel for the cards. The bot AI, physics and combat maths are untouched.
##
## Player SEATS (docs/ARCADE_COOP_PLAN.md §4.1, §5): the run is seat-aware. A seat is one human's fighter; single-player is
## one seat (`[sim.player]`, today's behaviour verbatim), a co-op room has two in room-slot order. The net layer (M1) maps
## its slots onto `seats`: `seat_count` and `seat_names` must be set before the first stage loads, and the world it builds
## puts the seats first in `sim.fighters` (slot k <-> seat k), the stage's crew after. Everything else here loops the seats:
## K.O.s are summed, damage scale is per seat, a downed seat auto-revives after REVIVE_TIME (no life lost) while a teammate
## is still up, and only every seat down fails the attempt (one shared life). `_pay()` returns the per-seat rewards so the
## net layer can hand each client its share; this process still writes one save (the local player's).
##
## ONLINE CO-OP (M1, docs/PROTOCOL.md 6.4): `new_online(start.arc, is_host)` turns the run into the online authority
## (`online = true`). The HOST keeps every rule in this file (crew, stages, lives, events, coins on its own save) and sends
## the display state as `am` (~5 Hz + on change); its seats are the room's slots 0/1, which HostMatch turns into ghosts
## (humans) or keeps as teammate bots. The GUEST is presentation only: `begin_stage` rebuilds the stage's site from
## `arc.seed`, `stage_ready` maps its seats onto the net ghosts and shows a "Waiting for the host" card, and
## `handle_remote` takes the host's `am`. No step, combat or event code runs on the guest.

signal stage_started(index: int)
signal stage_cleared(index: int, summary: Dictionary)
signal stage_failed(index: int)
signal run_over
signal run_won
## Co-op seats: a seat went down (`seconds` until its auto-revive) / came back. The net layer mirrors these as its
## downed-state messages; offline co-op uses them for the HUD.
signal seat_downed(index: int, seconds: float)
signal seat_revived(index: int)

const STAGES_PATH := "res://data/extra/construction/stages.json"
const LIVES := 3
const REVIVE_TIME := 6.0               ## a downed seat comes back after this long while a teammate is still up
const RETRY_SEED_STEP := 1009
const FAIL_DELAY := 1.8                ## seconds the world runs on after you fall, before the card
const CLEAR_DELAY := 1.4               ## ... and after the last enemy goes down
const VICTORY_COINS := 2000
const FOREMAN_HAT := "foreman"
const PHASES := [0.66, 0.33]           ## boss phases (hp fraction)
const PHASE_SPEED := 1.1               ## per phase: speed and damage bumps
const PHASE_DMG := 1.2
const KIT_EVERY := 0.5                 ## how often enemies get their trade tool (and its ammo) topped up
const NO_SWAP := ["heal", "speed", "rage", "shield"]

## The run in progress (null = no Arcade run: every other mode). Cleared by end_run().
static var running: ArcadeManager = null
static var _stages: Array = []
static var _diffs: Dictionary = {}
const DEFAULT_DIFF := "normal"

# ---------------- run state ----------------
var seed_base := 0
var diff := DEFAULT_DIFF               ## easy, normal or nightmare (the table's `difficulties`; nightmare = the numbers as written)
var player_class := ""                 ## the class picked for the run ("" = Settings "class")
var lives := LIVES
var stage := 0                         ## index into stages()
var attempt := 0                       ## retries of this stage (fresh seed offset each)
var state := "idle"                    ## idle, intro, fight, clearing, cleared, failing, failed, over, won
var rng := RandomNumberGenerator.new()
var run_coins := 0
var run_kos := 0
var run_time := 0.0
var history: Array = []                ## per cleared stage: {id, time, kos, coins, first}
var last: Dictionary = {}              ## the summary of the latest stage clear (the card)
var victory: Dictionary = {}           ## {coins, hat, first_hat} once won
# test aids (never set by the game): every bot's skill name, and a multiplier on the player's damage
var difficulty_override := ""
var player_dmg := 1.0
var fixed_seed := 0                    ## > 0: the match RNG seed of every stage (World.rng_seed), for reproducible tests
# ---------------- the seats (player slots) ----------------
## How many player seats the run has: 1 = today's single player, 2 = a co-op room. Set by the net layer (or a couch test)
## before the first load_map; the stage then creates `seat_count` players first in sim.fighters and the crew after.
var seat_count := 1
## Seat order = room-slot order: seats[k] is sim.fighters[k] (slot k). Rebuilt by setup_sim every stage.
var seats: Array = []
## Display names per seat ("" = the game's own label: "You" for seat 0, "Player N" otherwise).
var seat_names: Array = []
## Test/net: a seat played by a bot (still a full seat for down/revive/targeting). Empty = all seats are human.
var seat_bot: Array = []
## Per-seat damage multiplier test aid (k missing or empty -> player_dmg). A seat's dmg_scale gets multiplied by it.
var seat_dmg: Array = []
## Seat index -> seconds left on its auto-revive (only downed seats are in here).
var seat_down := {}
## Seat -> PlayerControl for an extra locally controlled seat (offline co-op / tests); null for the world's own seat.
var seat_controls: Array = []
# ---------------- online co-op (M1) ----------------
## Online co-op room: the net layer owns the slots (seats + crew), the host is the only run authority.
var online := false
## true = the host (runs everything and sends `am`), false = a guest (presentation only, `handle_remote`).
var host_mode := false
## Seat index -> its room slot (`arc.seats`): slot k <-> seat k, but kept explicit so a seat maps to `start.slots`.
var seat_slots: Array = [0]
## The guest's last `am` from the host (tests / the guest's cards and HUD).
var am: Dictionary = {}
var _am_t := 0.0
var _am_state := ""
# ---------------- the stage in play ----------------
var world: Node = null
var sim: MatchSim = null
var events: StageEvents = null
var hud: ArcadeBossHud = null
var enemies: Array = []                ## stage enemies (FighterState): the table's bots, then summoned / creeping ones
var boss: FighterState = null
var downed := {}                       ## FighterState -> true once it went down for good
var kit := {}                          ## FighterState -> its trade tool key
var phase_n := 0
var phase_log: Array = []              ## [stage time, phase number] (tests)
var t_stage := 0.0
var _t_end := 0.0
var _kit_t := 0.0
var _deaths0: Array = []              ## per seat: st["deaths"] when the stage started (a fall counts as going down)
var _seed_saved := -1
var _stage_first := false

# ---------------- the table ----------------

static func stages() -> Array:
	if _stages.is_empty():
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGES_PATH)) if FileAccess.file_exists(STAGES_PATH) else null
		if v is Dictionary and (v as Dictionary).get("stages") is Array: _stages = v["stages"]
	return _stages

## The `difficulties` table of stages.json (id -> multipliers); see its _readme.
static func difficulties() -> Dictionary:
	if _diffs.is_empty():
		stages()
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(STAGES_PATH)) if FileAccess.file_exists(STAGES_PATH) else null
		if v is Dictionary and (v as Dictionary).get("difficulties") is Dictionary: _diffs = v["difficulties"]
	return _diffs

static func diff_def_of(id: String) -> Dictionary:
	var t := difficulties()
	return t.get(id, t.get(DEFAULT_DIFF, {}))

func diff_def() -> Dictionary:
	return diff_def_of(diff)

## Stage coins (and the victory bonus) at this difficulty.
func scaled(coins: int) -> int:
	return roundi(float(coins) * float(diff_def().get("coin_mul", 1.0)))

func stage_coins(d: Dictionary) -> int:
	return scaled(int(d.get("coin_reward", 0))) + scaled(int(d.get("first_clear_bonus", 0)))

static func count() -> int:
	return stages().size()

func stage_def() -> Dictionary:
	return stages()[clampi(stage, 0, count() - 1)]

## The map the stages play on: the generated site, else the Site Yard.
static func site_map() -> String:
	return "sitegen" if Content.maps.has("sitegen") else "siteyard"

## The title's Arcade card: builds a World for a new run (null when the DLC is not owned or the table is missing).
## The caller puts it in the tree (scripts/main.gd: change_scene_to_node).
static func launch(seed_value: int = 0, p_diff: String = DEFAULT_DIFF, p_class: String = "") -> Node:
	if not DlcUnlock.owned() or count() == 0: return null
	var w: Node = load("res://world/world.tscn").instantiate()
	var run := ArcadeManager.new()
	run.start_run(seed_value, p_diff)
	run.player_class = p_class
	if p_class != "": w.player_class = p_class
	w.arcade = run
	w.map_id = site_map()
	w.mode_id = "construction"
	return w

# ---------------- the run ----------------

## An Arcade co-op run built from `start.arc` (docs/PROTOCOL.md 6.4): the host adopts the run as its own authority, a
## guest builds the same stage from the same seeds for presentation. `world.arcade = new_online(...)` before the world
## enters the tree; `begin_stage` then loads `arc.st` (host: 0) on the site of `arc.seed`.
static func new_online(arc: Dictionary, is_host: bool) -> ArcadeManager:
	var m := ArcadeManager.new()
	m.init_online(arc, is_host)
	return m

## new_online's body on an existing instance (headless net tests build it from a runtime-loaded script, so the net layer
## and the tests never statically depend on this DLC script before the autoloads exist).
func init_online(arc: Dictionary, is_host: bool) -> void:
	online = true
	host_mode = is_host
	seed_base = maxi(1, int(arc.get("run", 1)))
	diff = ArcadeCoop.norm_diff(str(arc.get("diff", DEFAULT_DIFF)))
	stage = clampi(int(arc.get("st", 0)), 0, maxi(0, count() - 1))
	attempt = 0
	lives = int(arc.get("lv", ArcadeCoop.lives_for(diff)))
	state = str(arc.get("state", "intro"))
	if not (state in ArcadeCoop.STATES): state = "intro"
	seat_slots = (arc.get("seats", [0]) as Array).duplicate()
	seat_count = clampi(seat_slots.size(), 1, ArcadeCoop.SEATS)
	rng.seed = seed_base
	_seed_saved = SiteMap.current_seed
	running = self

func start_run(p_seed: int = 0, p_diff: String = DEFAULT_DIFF) -> void:
	diff = p_diff if difficulties().has(p_diff) else DEFAULT_DIFF
	seed_base = p_seed if p_seed > 0 else randi_range(1, 900000)
	rng.seed = seed_base
	lives = int(diff_def().get("lives", LIVES)); stage = 0; attempt = 0; state = "idle"
	run_coins = 0; run_kos = 0; run_time = 0.0
	history = []; last = {}; victory = {}
	seats = []; seat_down = {}; seat_controls = []
	_seed_saved = SiteMap.current_seed
	running = self

## Back to normal: the site seed the game had, the arcade flag cleared. Safe to call twice.
func end_run() -> void:
	if running == self: running = null
	if _seed_saved >= 0:
		SiteMap.current_seed = _seed_saved
		_seed_saved = -1
	if hud != null and is_instance_valid(hud): hud.queue_free()
	hud = null
	events = null
	enemies.clear(); downed.clear(); kit.clear()
	if sim != null:
		sim.set_meta("pve_seats", [])          # no stale seat list for a later match in this process
		if sim.has_meta("arcade_run"): sim.remove_meta("arcade_run")
	seats = []; seat_down = {}; seat_controls = []
	boss = null; sim = null; world = null
	online = false; host_mode = false; seat_slots = [0]; am = {}; _am_t = 0.0; _am_state = ""
	state = "idle"

func stage_seed() -> int:
	return seed_base + int(stage_def().get("map_seed_offset", 0)) + attempt * RETRY_SEED_STEP

func is_boss_stage() -> bool:
	return bool(stage_def().get("boss", false))

func is_last_stage() -> bool:
	return stage >= count() - 1

func first_clear() -> bool:
	return not DlcSave.has_cleared(Save.dlc, str(stage_def().get("id", "")), diff)

# ---------------- World hooks ----------------

## Top of World.load_map: the stage's site and match settings. Returns the map id to build.
## Online co-op: the stage/seed/lives come from `start.arc` (which the host rewrites with this stage's live values before
## HostMatch.setup, so the outgoing `start` carries them); a guest rebuilds the same site from `arc.seed`.
func begin_stage(w: Node) -> String:
	world = w
	var mp := site_map()
	var a: Dictionary = {}
	if online:
		a = w.start_msg.get("arc", {}) if w.start_msg.get("arc") is Dictionary else {}
		seat_count = clampi((a.get("seats", [0, 0]) as Array).size(), 1, ArcadeCoop.SEATS)
		seat_slots = (a.get("seats", ArcadeCoop.seat_slots(seat_count)) as Array).duplicate()
		if host_mode:
			state = "intro"                                       # this stage starts at its intro card
			w.start_msg["slots"] = _online_slots(w)               # seats (kept) + the NEW stage's crew
			a = ArcadeCoop.stage_arc(self)                        # the host's live run is the authority
			w.start_msg["arc"] = a                                 # ... and it travels with this stage's `start`
		else:
			stage = clampi(int(a.get("st", stage)), 0, maxi(0, count() - 1))
			diff = ArcadeCoop.norm_diff(str(a.get("diff", diff)))
			lives = int(a.get("lv", lives))
			state = "intro"
		seat_names = _slot_seat_names(w)
		seed_base = maxi(1, int(a.get("run", seed_base)))
		var sd := int(a.get("seed", stage_seed()))
		if mp == "sitegen": SiteMap.set_seed(sd)
		w.mode_id = "construction"
		w.bot_count = ArcadeCoop.crew_count(stage) + maxi(0, seat_count - 1)   # seats first, then the stage's crew
		w.dyn_choice = "off"
		w.difficulty = _stage_skill()
		rng.seed = hash([seed_base, stage, attempt])
		return mp
	var d := stage_def()
	if mp == "sitegen": SiteMap.set_seed(stage_seed())
	w.mode_id = "construction"
	w.bot_count = (d["bots"] as Array).size() + maxi(0, seat_count - 1)   # seats first, then the stage's crew
	w.dyn_choice = "off"                       # a floor that stays put: the shrink is the stage's own event
	w.difficulty = difficulty_override if difficulty_override != "" else str((d["bots"] as Array)[0].get("difficulty", "normal"))
	if fixed_seed > 0: w.rng_seed = fixed_seed + stage * 17 + attempt
	rng.seed = hash([seed_base, stage, attempt])
	state = "intro"
	return mp

## The bot skill of the stage's first bot (ArcadeManager.begin_stage's pick; difficulty_override wins for tests).
func _stage_skill() -> String:
	var d := stage_def()
	var bots: Array = d.get("bots", [])
	var sk := str((bots[0] as Dictionary).get("difficulty", "normal")) if bots.size() > 0 and bots[0] is Dictionary else "normal"
	return difficulty_override if difficulty_override != "" else sk

## The room-slot display names of the player seats, from the `start.slots` table (P1 You / P2 Bluey on the HUD).
func _slot_seat_names(w: Node) -> Array:
	var out: Array = []
	var slots: Array = w.start_msg.get("slots", []) if w.start_msg.get("slots") is Array else []
	for k in seat_count:
		var slot := int(seat_slots[k]) if k < seat_slots.size() else k
		out.append(str((slots[slot] as Dictionary).get("name", "")) if slot >= 0 and slot < slots.size() and slots[slot] is Dictionary else "")
	return out

## The next stage's `start.slots` on the host: the two player seats exactly as they are now (a human guest stays a human,
## a seat nobody plays stays the teammate bot) and then the new stage's crew entries. HostMatch.setup rewrites the crew
## entries with the real bot info before the `start` goes out.
func _online_slots(w: Node) -> Array:
	var old: Array = w.start_msg.get("slots", []) if w.start_msg.get("slots") is Array else []
	var out: Array = []
	for k in seat_count:
		if k < old.size() and old[k] is Dictionary:
			var x: Dictionary = (old[k] as Dictionary).duplicate()
			x["kind"] = "human" if str(x.get("kind", "")) == "human" else "bot"
			x["id"] = k
			out.append(x)
		else:
			out.append(ArcadeCoop.teammate_slot(k, {}))
	for c: Dictionary in ArcadeCoop.crew_slots(diff, stage): out.append(c)
	return out

## After MatchSim.setup: the stage's fighters, tools, health and the scripted events. On a guest it is presentation only:
## the seats are mapped onto the net ghosts in stage_ready and no stage event runs here.
func setup_sim(s: MatchSim) -> void:
	sim = s
	if online and not host_mode:
		s.combat.ffa = false
		seats = []; enemies = []; downed = {}; kit = {}; boss = null; phase_n = 0; phase_log = []
		seat_down = {}; t_stage = 0.0; _t_end = 0.0; _kit_t = 0.0; state = "intro"
		return
	var d := stage_def()
	var c := s.combat
	c.ffa = false                              # the crew fights you, not each other
	_bind_seats(s)                             # the player seats (slot k <-> seat k), the rest is crew
	enemies = []; downed = {}; kit = {}; boss = null; phase_n = 0; phase_log = []; seat_down = {}
	t_stage = 0.0; _t_end = 0.0; _kit_t = 0.0
	if online and host_mode: _dress_teammate_seats(s)   # a seat nobody took is a teammate bot, not a tradie
	var specs: Array = d["bots"]
	var bots: Array = s.fighters.slice(seats.size())
	var giant := _giant_scale(d) > 1.0
	for i in mini(bots.size(), specs.size()):
		_dress(bots[i], specs[i], giant and bool(d.get("boss", false)), i == 0 and bool(d.get("boss", false)))
		enemies.append(bots[i])
	if bool(d.get("boss", false)) and enemies.size() > 0: boss = enemies[0]
	s.pickups.armed_weapon_crates = is_boss_stage()
	s.pickups.armed_weapon_crate_owner = boss
	for k in seats.size():
		var f: FighterState = seats[k]
		f.dmg_scale *= float(seat_dmg[k]) if k < seat_dmg.size() and seat_dmg[k] != null else player_dmg
	_deaths0 = []
	for f: FighterState in seats: _deaths0.append(int(f.st["deaths"]))
	s.set_meta("pve_seats", seats)             # BotBrain.pick_target: the crew hunts every seat, a seat bot hunts the crew
	if online and host_mode: s.set_meta("arcade_run", self)   # HostSession's drop/rejoin seat re-flag (no static dep)
	events = StageEvents.new()
	events.setup(self, s, d, rng)

## Online host: a player seat the room did not fill (`start.slots[k].kind == "bot"`) is the teammate bot. It keeps the
## BotBrain MatchSim gave it (PlayerControl in coop would be wrong) but is dressed like a player seat, so it fights the
## crew (BotBrain's pve_seats branch) and its drops restore the same look.
func _dress_teammate_seats(s: MatchSim) -> void:
	if seats.is_empty() or world == null: return
	var slots: Array = world.start_msg.get("slots", []) if world.start_msg.get("slots") is Array else []
	for k in range(1, seats.size()):
		var f: FighterState = seats[k]
		if f == null or f.is_ghost: continue
		var slot := int(seat_slots[k]) if k < seat_slots.size() else k
		var kind := str((slots[slot] as Dictionary).get("kind", "")) if slot >= 0 and slot < slots.size() and slots[slot] is Dictionary else ""
		if kind != "bot": continue
		_dress_teammate_seat(s, f, k)

## One teammate bot seat as a player seat: the host's class and a friendly (non-tradie) look, a K.O.-clear head, and the
## name the HUD/cards use. Also runs when a guest leaves mid-stage and a bot takes the seat back (refresh_seats(slot)).
func _dress_teammate_seat(s: MatchSim, f: FighterState, k: int) -> void:
	var base: FighterState = seats[0] if seats.size() > 0 else s.player
	f.is_player = true
	f.set_class(base.class_id, s.combat.classes.get(base.class_id, {}))
	f.hp = s.combat.max_hp(f)
	f.dmg_scale = base.dmg_scale
	f.name = ArcadeCoop.TEAMMATE_NAME
	s.looks[f] = {"skin": str(Settings.get_value("skin", "none")), "hat": str(Settings.get_value("hat", "none")),
		"color": 0x4a90d9 if k % 2 == 1 else 0xe86fa5}

## The run's player seats for this stage: sim.fighters[0..seat_count-1] in slot order. Seat 0 is the world's own player;
## an extra seat the net layer made a ghost stays a ghost, and an extra offline seat becomes a second locally played
## fighter (its own PlayerControl + InputState) or, with seat_bot[k], keeps the BotBrain MatchSim gave it.
func _bind_seats(s: MatchSim) -> void:
	seats = []; seat_controls = []
	var online: bool = world != null and world.session != null   # HostMatch.setup dresses the seats right after this
	var n := clampi(seat_count, 1, s.fighters.size())
	for k in n: seats.append(s.fighters[k])
	if seats.is_empty(): seats = [s.player]
	for k in seats.size():
		var f: FighterState = seats[k]
		if k == 0:                                           # the world's own player: PlayerControl is the world's
			seat_controls.append(null)
			continue
		if f.is_ghost:                                       # online co-op seat: the net layer owns it
			seat_controls.append(null)
			continue
		f.is_player = true                                   # a full player seat: crew can hit it, bots pick it, HUD shows it
		if online:                                           # the net layer (HostMatch) dresses and controls this fighter;
			seat_controls.append(null)                       # keep MatchSim's BotBrain so human_to_bot has one to restore
			continue
		f.dmg_scale = 1.0                                    # MatchSim made it a bot: class/health/speed as a player
		f.set_class(s.player.class_id, s.combat.classes.get(s.player.class_id, {}))
		f.hp = s.combat.max_hp(f)
		f.name = seat_name(k)
		# the same outfit as seat 0, a different hi-vis colour (the crew's tradie look would read as an enemy)
		s.looks[f] = {"skin": str(Settings.get_value("skin", "none")), "hat": str(Settings.get_value("hat", "none")),
			"color": 0x4a90d9 if k % 2 == 1 else 0xe86fa5}
		if k < seat_bot.size() and bool(seat_bot[k]):        # a teammate BOT seat: keep its brain, the crew is its prey
			seat_controls.append(null)
			continue
		var pc := PlayerControl.new(InputState.new())        # an extra couch seat: a real local PlayerControl
		s.controllers[f] = pc
		seat_controls.append(pc)

## After the net layer dressed the stage (HostMatch.setup runs between setup_sim and stage_ready): a seat that became a
## ghost belongs to a remote client, so it must not carry local-player flags here. A host-run bot seat stays a player seat.
func _refresh_seats() -> void:
	for k in range(1, seats.size()):
		var f: FighterState = seats[k]
		if f == null: continue
		if f.is_ghost:
			f.is_player = false
			if k < seat_controls.size(): seat_controls[k] = null
		elif not f.left:
			f.is_player = true

## The net layer re-flagged a seat (a guest dropped -> its seat is the teammate bot again, or rejoined -> a ghost):
## HostSession calls this after bot_to_human / human_to_bot. `bot_slot` = the room slot that fell back to a bot, re-dressed
## as a teammate seat (it must not keep the tradie name/look MatchSim gave the placeholder). Never called offline.
func refresh_seats(bot_slot: int = -1) -> void:
	_refresh_seats()
	if bot_slot < 0 or not host_mode or sim == null: return
	var k := seat_slots.find(bot_slot)
	if k <= 0 or k >= seats.size(): return
	var f: FighterState = seats[k]
	if f == null or f.is_ghost or f.left: return
	_dress_teammate_seat(sim, f, k)

## End of World.load_map (the fighters have views): the HUD strip and the stage's intro card.
func stage_ready(w: Node) -> void:
	world = w
	if online and not host_mode:
		state = "intro"
		stage_started.emit(stage)
		_bind_guest_seats()
		w.show_panel(_guest_card())
		return
	if hud == null or not is_instance_valid(hud):
		hud = ArcadeBossHud.new()
		var ui: Node = w.get_node("UI")
		ui.add_child(hud)
		ui.move_child(hud, w.hud.get_index() + 1)
	hud.bind(self)
	events.world = w
	_refresh_seats()                           # the net layer (if any) has dressed the stage by now
	stage_started.emit(stage)
	state = "intro"
	_stage_first = first_clear()
	w.show_panel(ArcadePanels.intro(self, stage_def(), _on_start_pressed))
	_am_send()                                  # "intro" straight away, so the guest shows its waiting card

## A guest's seats are its own fighter and the host's, mapped through the net slots (`arc.seats`: slot k <-> seat k).
## The crew and the boss stay ghosts; they are only presentation here.
func _bind_guest_seats() -> void:
	seats = []; seat_controls = []; seat_down = {}
	var nm: NetMatch = world.net_match if world != null else null
	for k in seat_count:
		var slot := int(seat_slots[k]) if k < seat_slots.size() else k
		var f: FighterState = nm.slot_fighter(slot) if nm != null else null
		if f == null and nm != null: f = nm.sim.player
		seats.append(f)
	if seats.is_empty() and sim != null: seats = [sim.player]

## The guest's stage card: what stage of how many, and that the host starts the fight.
func _guest_card() -> Control:
	var p := PanelContainer.new()
	p.name = "ArcadeGuestIntro"
	p.custom_minimum_size = Vector2(420, 0)
	var box := VBoxContainer.new()
	box.name = "Box"
	box.add_theme_constant_override("separation", 10)
	p.add_child(box)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = tr("Stage %d of %d") % [stage + 1, count()]
	box.add_child(title)
	var nm := Label.new()
	nm.name = "StageName"
	nm.theme_type_variation = &"MutedLabel"
	nm.add_theme_font_size_override("font_size", 24)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.text = tr(str(stage_def().get("name", "")))
	box.add_child(nm)
	var wait := Label.new()
	wait.name = "Waiting"
	wait.add_theme_font_size_override("font_size", 22)
	wait.add_theme_color_override("font_color", UiTheme.ACCENT)
	wait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wait.text = tr("Waiting for the host")
	box.add_child(wait)
	return p

func _on_start_pressed() -> void:
	begin_fight()

## The intro card's Start: the world runs.
func begin_fight() -> void:
	if state != "intro": return
	state = "fight"
	if world != null:
		world.close_panel()
		if world.hud != null: world.hud.toast(tr("Stage %d of %d: %s") % [stage + 1, count(), tr(str(stage_def()["name"]))])
	_am_send()                                  # the guests' "Waiting for the host" card closes with the host's Start

## After every sim step (World.sim_step).
func step(dt: float) -> void:
	if online and not host_mode: return           # a guest runs no stage logic (the host's `am` drives it)
	if sim == null: return
	_am_tick(dt)
	match state:
		"fight": _fight(dt)
		"clearing", "failing":
			_t_end -= dt
			if _t_end <= 0.0: _finish_attempt()

# ---------------- online co-op: the host's `am` display state / the guest's copy ----------------

## Client-safe view of an `am` message from a Godot host (docs/PROTOCOL.md 6.4). Display only: it never advances a
## stage, pays coins or damages anyone here. The guest agent fills the cards / HUD from it (state, lives, boss fraction,
## shrink size, downed slots, the stage summary each save pays from, the victory flag).
func handle_remote(m: Dictionary) -> void:
	if not online or host_mode: return
	var st := int(m.get("st", stage))
	if st != stage: return                       # a stale `am` from before the stage's own `start` rebuilt the world
	am = m.duplicate(true)
	stage = clampi(st, 0, maxi(0, count() - 1))
	lives = int(m.get("lv", lives))
	if m.get("last") is Dictionary and not (m["last"] as Dictionary).is_empty(): last = m["last"]
	state = str(m.get("s", state))
	if state == "fight" and world != null: world.close_panel()

## The host's `am` every ~5 Hz, plus at once when the state changes (intro -> fight -> cleared ...).
func _am_tick(dt: float) -> void:
	if not online or not host_mode: return
	_am_t -= dt
	if _am_t <= 0.0 or state != _am_state: _am_send()

## `{t:"am", st, of, s(state), lv(lives), hf(boss hp fraction), sh(shrink size), dn:[downed seat slots], last, won}`.
func _am_payload() -> Dictionary:
	var sh := 0.0
	if sim != null:
		var r: Dictionary = sim.combat.rules.shrink
		if not r.is_empty(): sh = float(r.get("size", 0.0))
	var dn: Array = []
	for k in downed_seats(): dn.append(int(seat_slots[k]) if k < seat_slots.size() else k)
	var p := {"t": "am", "st": stage, "of": count(), "s": state, "lv": lives, "hf": boss_frac(), "sh": sh,
		"dn": dn, "last": last, "won": state == "won"}
	if not victory.is_empty(): p["vic"] = victory                # the guest pays the victory bonus from its own save
	if phase_n > 0: p["ph"] = phase_n                            # boss phase (the guest's bar / toasts)
	return p

## Send `am` to every guest through the room (HostSession.arcade_send). Also remembers the state, so step's 5 Hz timer
## only sends again when the state moves (intro -> fight -> cleared) or 0.2 s passed.
func _am_send() -> void:
	_am_t = 0.2
	_am_state = state
	if not online or not host_mode or world == null: return
	var s = world.session          # HostSession (typed as GuestSession on World: RefCounted, not a Node)
	if s != null and s.has_method("arcade_send"): s.call("arcade_send", _am_payload())

func _fight(dt: float) -> void:
	t_stage += dt
	run_time += dt
	_kit_t -= dt
	if _kit_t <= 0.0:
		_kit_t = KIT_EVERY
		for e: FighterState in enemies:
			if not downed.has(e) and not e.dead: keep_kit(e)
	# enemies that went down stay down (no respawn) - but a ring-out is not a K.O. (see _revive)
	for e: FighterState in enemies:
		if downed.has(e) or not e.dead: continue
		if e.fell_t: _revive(e)
		else: _down(e)
	if events != null: events.update(dt)
	_phases()
	# the stage is cleared: the boss is down, or everyone is
	var clear := false
	if boss != null: clear = downed.has(boss)
	else:
		clear = not enemies.is_empty()
		for e: FighterState in enemies:
			if not downed.has(e): clear = false
	if clear:
		_cleared()
		return
	_seats(dt)

# ---------------- seats: down / auto-revive / fail ----------------

## Every seat every step: a dead (or fallen) seat goes down; downed seats count their 6 s and come back while a teammate is
## still up; when every seat is down the attempt fails (one shared life). One seat reproduces the old rule exactly: the
## stage fails the same frame its only player dies.
func _seats(dt: float) -> void:
	for k in seats.size():
		if seat_down.has(k): continue
		var f: FighterState = seats[k]
		if f.dead or int(f.st["deaths"]) > int(_deaths0[k]): _seat_down(k)
	var up := living_seats()
	if up.is_empty():
		_failed()
		return
	for k: int in seat_down.keys():
		seat_down[k] = maxf(float(seat_down[k]) - dt, 0.0)
	for k: int in seat_down.keys().duplicate():
		if float(seat_down[k]) <= 0.0: _seat_up(k)

## A seat is down: pinned like a solo player's death (MatchSim must not respawn it) and revived by the manager after 6 s.
func _seat_down(k: int) -> void:
	var f: FighterState = seats[k]
	if not f.dead:                             # a fall/ring-out: the seat is out too, but let the revive bring it back
		f.dead = true
		sim.combat.clear_inventory(f)
		sim.combat.set_weapon(f, "")
	f.elim = true; f.death_t = 1e9
	seat_down[k] = REVIVE_TIME
	seat_downed.emit(k, REVIVE_TIME)

## The seat comes back on the floor, at full health for its class (a fresh fighter: the K.O. cleared its hands), away from
## the fight, with a short invulnerability. No life is lost (lives are the shared run lives).
func _seat_up(k: int) -> void:
	if not seat_down.has(k): return
	seat_down.erase(k)
	var f: FighterState = seats[k]
	var best := _safe_spot()
	sim.combat.place_at(f, float(best[0]), float(best[1]), float(best[2]) if best.size() > 2 else sim.combat.spawn_y)
	f.elim = false; f.dead = false; f.death_t = 0.0; f.fell_t = false; f.invuln = 2.5
	seat_revived.emit(k)

## The safest of a few random bot spots: the farthest from the nearest living seat. The same six draws the old
## single-player revive used (so a solo run's scripted RNG is untouched).
func _safe_spot() -> Array:
	var c := sim.combat
	var spots: Array = sim.map.get("bots", []) + sim.map.get("spawns", [])
	var sh: Dictionary = c.rules.shrink
	if not sh.is_empty():                       # the Project Manager's closing floor: only spots still on it
		var half := float(sh["size"]) / 2.0 - 2.5
		spots = spots.filter(func(sp: Array) -> bool: return absf(float(sp[0])) <= half and absf(float(sp[1])) <= half)
	if spots.is_empty(): spots = [[0.0, 0.0]]
	var best: Array = spots[0]
	var far := -1.0
	for i in 6:
		var sp: Array = spots[rng.randi() % spots.size()]
		var dd := _nearest_seat_dist(float(sp[0]), float(sp[1]))
		if dd > far: far = dd; best = sp
	return best

func _down(e: FighterState) -> void:
	downed[e] = true
	e.elim = true
	e.death_t = 1e9

## A fall off the site is not a K.O.: the fighter goes back on the floor with the health it had. The player's hammer can
## shove a melee boss through a fence gate and off the edge (the probe won stages 5/6 at full health in 2-3 s that way), so
## counting a ring-out as "down" cleared the stage for free. MatchSim._ring_out flags it with fell_t and empties the hands.
func _revive(e: FighterState) -> void:
	var c := sim.combat
	var frac := clampf(e.hp / c.max_hp(e), 0.05, 1.0)
	var best := _safe_spot()
	c.place_at(e, float(best[0]), float(best[1]), float(best[2]) if best.size() > 2 else c.spawn_y)
	e.hp = c.max_hp(e) * frac
	e.death_t = 0.0
	e.fell_t = false
	e.invuln = 1.5
	var key: String = str(kit.get(e, ""))
	if key != "": give_weapon(e, key)          # the fall cleared its hands: it comes back with its trade tool

## The crew gives up when the boss falls: the rest go down with it (the K.O. goes to the nearest living seat).
func _cleared() -> void:
	for e: FighterState in enemies:
		if downed.has(e): continue
		e.invuln = 0.0
		if not e.dead: sim.combat.hit(e, 1e6, 0.0, 1.0, 0.0, 8.0, false, _nearest_seat(e))
		_down(e)
	if events != null: events.finish()
	state = "clearing"
	_t_end = CLEAR_DELAY
	last = _pay()
	stage_cleared.emit(stage, last)

func _failed() -> void:
	if events != null: events.finish()
	for k in seats.size():                      # every downed seat stays down behind the card (solo: the one player)
		var f: FighterState = seats[k]
		if seat_down.has(k) or f.dead or int(f.st["deaths"]) > int(_deaths0[k]):
			f.death_t = 1e9
	sim.player.death_t = 1e9
	state = "failing"
	_t_end = FAIL_DELAY
	stage_failed.emit(stage)

# ---------------- the seat API (the net layer maps its room slots onto these) ----------------

## The fighter of seat k (null out of range). Seats are in room-slot order: seat k is sim.fighters[k].
func seat(k: int) -> FighterState:
	return seats[k] if k >= 0 and k < seats.size() else null

## The seat index of a fighter, -1 when it is not a player seat (crew, minion).
func seat_index(f: FighterState) -> int:
	return seats.find(f)

## The seat's display name: "You" for seat 0 (the world's own player), seat_names[k] when the net layer set one, else
## "Player N". The HUD and the cards use it.
func seat_name(k: int) -> String:
	if k < 0: return ""
	if k < seat_names.size() and str(seat_names[k]) != "": return str(seat_names[k])
	return tr("You") if k == 0 else tr("Player %d") % (k + 1)

## "P1 You" / "P2 Bluey": short enough for the run strip on a phone.
func seat_label(k: int) -> String:
	return "P%d %s" % [k + 1, seat_name(k)]

## A seat is in the fight: not downed, not dead.
func seat_alive(k: int) -> bool:
	var f := seat(k)
	return f != null and not seat_down.has(k) and not f.dead and not f.elim

func seat_is_down(k: int) -> bool:
	return seat_down.has(k)

## Seconds until seat k's auto-revive (0 = up).
func seat_revive_left(k: int) -> float:
	return float(seat_down.get(k, 0.0))

## The seats still in the fight, in seat order.
func living_seats() -> Array:
	var out: Array = []
	for k in seats.size():
		if seat_alive(k): out.append(seats[k])
	return out

## The seat indexes that are down (in seat order).
func downed_seats() -> Array:
	var out: Array = []
	for k in seats.size():
		if seat_down.has(k): out.append(k)
	return out

func all_seats_down() -> bool:
	for k in seats.size():
		if not seat_down.has(k) and not seats[k].dead: return false
	return not seats.is_empty()

## The PlayerControl of an extra locally controlled seat (offline co-op / tests); null for seat 0 (the world's own
## PlayerControl) and for a net-layer ghost.
func seat_control(k: int) -> PlayerControl:
	return seat_controls[k] if k >= 0 and k < seat_controls.size() else null

## The living seat nearest to `from` (the nearest-player rule for K.O. credit / enemy revives).
func _nearest_seat(from: FighterState) -> FighterState:
	var best: FighterState = null
	var bd := 1e9
	for f: FighterState in living_seats():
		var dx := f.phys.px - from.phys.px
		var dz := f.phys.pz - from.phys.pz
		var dd := dx * dx + dz * dz
		if dd < bd: bd = dd; best = f
	if best != null: return best
	return seats[0] if not seats.is_empty() else sim.player

## Distance from (x, z) to the NEAREST living seat (enemy revives and minion spawns keep away from the whole team).
func _nearest_seat_dist(x: float, z: float) -> float:
	var bd := -1.0
	for f: FighterState in living_seats():
		var dx := f.phys.px - x
		var dz := f.phys.pz - z
		var dd := sqrt(dx * dx + dz * dz)
		if bd < 0.0 or dd < bd: bd = dd
	return maxf(bd, 0.0)

## Coins and records for the stage just cleared (once per first clear). The card summary keeps its single-player keys
## (kos = the seats' K.O.s summed, coins = what this save gets); `seats` carries each seat's share so the net layer can
## pay every client without this process writing a second save.
func _pay() -> Dictionary:
	var d := stage_def()
	var id := str(d["id"])
	var first := not DlcSave.has_cleared(Save.dlc, id, diff)
	var coins := 0
	if first:
		coins = stage_coins(d)
		DlcSave.mark_cleared(Save.dlc, id, diff)
	DlcSave.set_best(Save.dlc, diff, stage + 1)
	if coins > 0: Save.coins += coins
	Save.commit()
	var per: Array = []
	var kos := 0
	for k in seats.size():
		var sk := int(seats[k].ko)
		kos += sk
		per.append({"seat": k, "name": seat_name(k), "kos": sk, "coins": coins, "first": first,
			"reward": scaled(int(d.get("coin_reward", 0))), "bonus": scaled(int(d.get("first_clear_bonus", 0))) if first else 0})
	run_coins += coins
	run_kos += kos
	var out := {"id": id, "stage": stage, "name": str(d["name"]), "time": t_stage, "kos": kos, "coins": coins, "first": first,
		"reward": scaled(int(d.get("coin_reward", 0))), "bonus": scaled(int(d.get("first_clear_bonus", 0))) if first else 0,
		"seats": per}
	history.append(out)
	return out

func _finish_attempt() -> void:
	if state == "clearing":
		state = "cleared"
		if is_last_stage(): _win()
		else: world.show_panel(ArcadePanels.clear(self, last, next_stage, quit_run))
	elif state == "failing":
		lives -= 1
		if lives <= 0:
			state = "over"
			run_over.emit()
			world.show_panel(ArcadePanels.over(self, quit_run))
		else:
			state = "failed"
			world.show_panel(ArcadePanels.failed(self, retry_stage, quit_run))

## The final victory: bonus coins and the Site Foreman hat, once. As with _pay(), each seat's share is in `seats`; this
## process pays this save once.
func _win() -> void:
	var first := not DlcSave.won_diff(Save.dlc, diff)     # the victory bonus is paid once per difficulty
	var hat_first := DlcSave.HAT_DIFFS.has(diff) and not DlcSave.won_arcade(Save.dlc)
	var coins := 0
	if first:
		coins = scaled(VICTORY_COINS)
		DlcSave.mark_cleared(Save.dlc, DlcSave.VICTORY, diff)
		Save.coins += coins
		Save.commit()
		run_coins += coins
	var hat_owned := DlcSave.won_arcade(Save.dlc)
	victory = {"coins": coins, "hat": FOREMAN_HAT, "first": first, "hat_first": hat_first, "hat_owned": hat_owned, "diff": diff}
	var per: Array = []
	for k in seats.size():
		per.append({"seat": k, "name": seat_name(k), "coins": coins, "first": first,
			"hat_first": hat_first, "hat_owned": hat_owned})
	victory["seats"] = per
	state = "won"
	run_won.emit()
	world.show_panel(ArcadePanels.won(self, quit_run))

func next_stage() -> void:
	if state != "cleared" or is_last_stage(): return
	stage += 1
	attempt = 0
	_reload()

func retry_stage() -> void:
	if state != "failed": return
	attempt += 1
	_reload()

func _reload() -> void:
	if world != null: world.load_map.call_deferred(world.map_id)

func quit_run() -> void:
	if world != null: world._on_title_pressed()

# ---------------- fighters ----------------

func _giant_scale(d: Dictionary) -> float:
	for ev: Dictionary in d.get("events", []):
		var s := float((ev.get("params", {}) as Dictionary).get("giant_scale", 1.0))
		if s > 1.0: return s
	return 1.0

## One stage bot from its table entry: name, look, tool, health, damage, speed and skill. Boss scale like Giant (big_t).
func _dress(b: FighterState, spec: Dictionary, giant: bool, is_boss := false) -> void:
	var c := sim.combat
	b.name = str(spec.get("name", b.name))
	sim.looks[b] = {"skin": str(spec.get("skin", "builder")), "hat": str(spec.get("hat", "none")), "color": int(spec.get("color", 0xf08a3c))}
	var dn := difficulty_override if difficulty_override != "" else str(spec.get("difficulty", "normal"))
	if not Content.difficulties.has(dn): dn = "normal"
	var dd: Dictionary = Content.difficulties[dn]
	var brain := BotBrain.new(dd, dn)
	brain.ai_t = rng.randf_range(0.5, 3.0)
	b.kick_cool = rng.randf_range(1.0, 4.0)
	brain.strafe = 1.0 if rng.randf() < 0.5 else -1.0
	sim.controllers[b] = brain
	var df := diff_def()
	b.phys.speed = float(dd.get("speed", 4.4)) * float(spec.get("speed", 1.0)) * float(df.get("speed_mul", 1.0))
	b.dmg_scale = float(dd.get("dmg", 0.45)) * float(spec.get("dmg_scale", 1.0)) * float(df.get("dmg_mul", 1.0))
	var hp := enemy_hp(float(spec.get("hp", 1.0)), is_boss)
	if giant:
		b.big_t = 1e9                          # Chaos' Giant flags: 1.5 x model and hit spheres, double health, harder hits
		b.dmg_scale /= 1.5                     # ... so the table's damage and health stay what they say
		hp /= 2.0
	b.cls_hp = hp
	b.heal_frac = float(df.get("boss_heal", b.heal_frac))   # a Health Pack heals an enemy only a little (5 / 8 / 10 %)
	b.hp = c.max_hp(b)
	give_weapon(b, str(spec.get("weapon", "hammer")))

## A table hp multiplier at this difficulty: x hp_mul, never below the floor (boss / non-boss), never above the table's own value.
func enemy_hp(table_hp: float, is_boss: bool) -> float:
	var df := diff_def()
	var floor_hp := float(df.get("boss_hp_floor" if is_boss else "hp_floor", 0.0))
	return minf(table_hp, maxf(table_hp * float(df.get("hp_mul", 1.0)), floor_hp))

## The fighter's trade tool in hand (replaces whatever else it carried).
func give_weapon(f: FighterState, key: String) -> void:
	var c := sim.combat
	if c.wdata(key).is_empty(): key = "hammer"
	kit[f] = key
	c.clear_inventory(f)
	c.set_weapon(f, "spatula")
	c.pickup(f, key)
	for i in 3:
		if f.slots[i] != null and f.slots[i]["key"] == key and f.slot != i: c.equip_slot(f, i)

## Keeps the melee kit and its ammo up. A gun taken from a crate is deliberately not part of the kit: it runs dry and
## the boss goes back to melee, rather than becoming an endless turret.
func keep_kit(f: FighterState) -> void:
	var key: String = kit.get(f, "")
	if key == "": return
	var wd := sim.combat.wdata(key)
	if str(wd.get("type", "")) != "melee": return
	var have := false
	for sl: Variant in f.slots:
		if sl != null and sl["key"] == key:
			have = true
			if float(sl["ammo"]) < maxf(2.0, float(wd.get("ammo", 0)) * 0.3):
				sl["ammo"] = maxf(float(sl["ammo"]), float(wd.get("ammo", 0)))
	if not have and not f.dead: give_weapon(f, key)

## One more enemy (backup call, scope creep): a tradie from the first stage's crew (or the named one) at a bot spot.
func spawn_minion(name_hint: String = "") -> FighterState:
	if sim == null or world == null: return null
	var crew: Array = stages()[0]["bots"]
	var spec: Dictionary = crew[rng.randi() % crew.size()]
	for s: Dictionary in crew:
		if name_hint != "" and str(s["name"]) == name_hint: spec = s
	var f := sim.add_fighter("wobbler")
	var spots: Array = sim.map.get("bots", []) + sim.map.get("spawns", [])
	var sh: Dictionary = sim.combat.rules.shrink       # the Project Manager's closing floor: only spots still on it
	if not sh.is_empty():
		var half := float(sh["size"]) / 2.0 - 2.5
		spots = spots.filter(func(sp: Array) -> bool: return absf(float(sp[0])) <= half and absf(float(sp[1])) <= half)
		if spots.is_empty(): spots = [[0.0, 0.0]]
	var best: Array = [0.0, 0.0]
	var far := -1.0
	for k in 6:                                # a bot spot, the farthest of a few picks from the nearest seat
		var sp: Array = spots[rng.randi() % spots.size()] if spots.size() > 0 else [0.0, 0.0]
		var dd := _nearest_seat_dist(float(sp[0]), float(sp[1]))
		if dd > far: far = dd; best = sp
	sim.combat.place_at(f, float(best[0]), float(best[1]), float(best[2]) if best.size() > 2 else sim.combat.spawn_y)
	f.yaw = rng.randf_range(0.0, TAU); f.face_yaw = f.yaw
	f.invuln = 1.5
	_dress(f, spec, false)
	enemies.append(f)
	world.add_view(f)
	return f

func alive_enemies() -> int:
	var n := 0
	for e: FighterState in enemies:
		if not downed.has(e): n += 1
	return n

func boss_frac() -> float:
	if boss == null: return 0.0
	return clampf(boss.hp / sim.combat.max_hp(boss), 0.0, 1.0) if not boss.dead else 0.0

## The boss' fight is on: the bar shows.
func boss_active() -> bool:
	return boss != null and state == "fight" and not downed.has(boss)

## Boss phases: at 66 % and 33 % health the boss gets faster and hits harder, with a toast; the stage's change request
## (The Client) also swaps tools.
func _phases() -> void:
	if boss == null or phase_n >= PHASES.size(): return
	if boss_frac() > float(PHASES[phase_n]) or boss.dead: return
	phase_n += 1
	phase_log.append([t_stage, phase_n])
	boss.phys.speed *= PHASE_SPEED
	boss.dmg_scale *= PHASE_DMG
	var key := "%s is fired up!" if phase_n == 1 else "%s is furious!"
	sim.combat.ev({"type": "toast", "text": tr(key) % boss.name})
	if events != null: events.on_phase(phase_n)

## The finished-run tidy: results for the title card.
func summary() -> Dictionary:
	return {"stage": stage + 1, "of": count(), "lives": lives, "coins": run_coins, "kos": run_kos, "time": run_time}

static func fmt_time(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]
