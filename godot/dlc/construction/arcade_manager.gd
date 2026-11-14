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
	if sim != null: sim.set_meta("pve_seats", [])          # no stale seat list for a later match in this process
	seats = []; seat_down = {}; seat_controls = []
	boss = null; sim = null; world = null
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
func begin_stage(w: Node) -> String:
	world = w
	var d := stage_def()
	var mp := site_map()
	if mp == "sitegen": SiteMap.set_seed(stage_seed())
	w.mode_id = "construction"
	w.bot_count = (d["bots"] as Array).size() + maxi(0, seat_count - 1)   # seats first, then the stage's crew
	w.dyn_choice = "off"                       # a floor that stays put: the shrink is the stage's own event
	w.difficulty = difficulty_override if difficulty_override != "" else str((d["bots"] as Array)[0].get("difficulty", "normal"))
	if fixed_seed > 0: w.rng_seed = fixed_seed + stage * 17 + attempt
	rng.seed = hash([seed_base, stage, attempt])
	state = "intro"
	return mp

## After MatchSim.setup: the stage's fighters, tools, health and the scripted events.
func setup_sim(s: MatchSim) -> void:
	sim = s
	var d := stage_def()
	var c := s.combat
	c.ffa = false                              # the crew fights you, not each other
	_bind_seats(s)                             # the player seats (slot k <-> seat k), the rest is crew
	enemies = []; downed = {}; kit = {}; boss = null; phase_n = 0; phase_log = []; seat_down = {}
	t_stage = 0.0; _t_end = 0.0; _kit_t = 0.0
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
	events = StageEvents.new()
	events.setup(self, s, d, rng)

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
		if f.is_ghost:
			f.is_player = false
			if k < seat_controls.size(): seat_controls[k] = null
		elif not f.left:
			f.is_player = true

## End of World.load_map (the fighters have views): the HUD strip and the stage's intro card.
func stage_ready(w: Node) -> void:
	world = w
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

func _on_start_pressed() -> void:
	begin_fight()

## The intro card's Start: the world runs.
func begin_fight() -> void:
	if state != "intro": return
	state = "fight"
	if world != null:
		world.close_panel()
		if world.hud != null: world.hud.toast(tr("Stage %d of %d: %s") % [stage + 1, count(), tr(str(stage_def()["name"]))])

## After every sim step (World.sim_step).
func step(dt: float) -> void:
	if sim == null: return
	match state:
		"fight": _fight(dt)
		"clearing", "failing":
			_t_end -= dt
			if _t_end <= 0.0: _finish_attempt()

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
