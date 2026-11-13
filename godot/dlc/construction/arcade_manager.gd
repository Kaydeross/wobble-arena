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

signal stage_started(index: int)
signal stage_cleared(index: int, summary: Dictionary)
signal stage_failed(index: int)
signal run_over
signal run_won

const STAGES_PATH := "res://data/extra/construction/stages.json"
const LIVES := 3
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
var _deaths0 := 0
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
	w.bot_count = (d["bots"] as Array).size()
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
	enemies = []; downed = {}; kit = {}; boss = null; phase_n = 0; phase_log = []
	t_stage = 0.0; _t_end = 0.0; _kit_t = 0.0
	var specs: Array = d["bots"]
	var bots: Array = s.fighters.slice(1)
	var giant := _giant_scale(d) > 1.0
	for i in mini(bots.size(), specs.size()):
		_dress(bots[i], specs[i], giant and bool(d.get("boss", false)), i == 0 and bool(d.get("boss", false)))
		enemies.append(bots[i])
	if bool(d.get("boss", false)) and enemies.size() > 0: boss = enemies[0]
	s.player.dmg_scale *= player_dmg
	_deaths0 = int(s.player.st["deaths"])
	events = StageEvents.new()
	events.setup(self, s, d, rng)

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
	var p := sim.player
	_kit_t -= dt
	if _kit_t <= 0.0:
		_kit_t = KIT_EVERY
		for e: FighterState in enemies:
			if not downed.has(e) and not e.dead: keep_kit(e)
	# enemies that went down stay down (no respawn)
	for e: FighterState in enemies:
		if not downed.has(e) and e.dead: _down(e)
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
	if p.dead or int(p.st["deaths"]) > _deaths0:
		_failed()

func _down(e: FighterState) -> void:
	downed[e] = true
	e.elim = true
	e.death_t = 1e9

## The crew gives up when the boss falls: the rest go down with it (K.O.s count for the player).
func _cleared() -> void:
	for e: FighterState in enemies:
		if downed.has(e): continue
		e.invuln = 0.0
		if not e.dead: sim.combat.hit(e, 1e6, 0.0, 1.0, 0.0, 8.0, false, sim.player)
		_down(e)
	if events != null: events.finish()
	state = "clearing"
	_t_end = CLEAR_DELAY
	last = _pay()
	stage_cleared.emit(stage, last)

func _failed() -> void:
	if events != null: events.finish()
	sim.player.death_t = 1e9
	state = "failing"
	_t_end = FAIL_DELAY
	stage_failed.emit(stage)

## Coins and records for the stage just cleared (once per first clear).
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
	var kos := int(sim.player.ko)
	run_coins += coins
	run_kos += kos
	var out := {"id": id, "stage": stage, "name": str(d["name"]), "time": t_stage, "kos": kos, "coins": coins, "first": first,
		"reward": scaled(int(d.get("coin_reward", 0))), "bonus": scaled(int(d.get("first_clear_bonus", 0))) if first else 0}
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

## The final victory: bonus coins and the Site Foreman hat, once.
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
	victory = {"coins": coins, "hat": FOREMAN_HAT, "first": first, "hat_first": hat_first, "hat_owned": DlcSave.won_arcade(Save.dlc), "diff": diff}
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

## Keeps the tool and its ammo up (the tradies' tools wear out, bosses never run dry).
func keep_kit(f: FighterState) -> void:
	var key: String = kit.get(f, "")
	if key == "": return
	var wd := sim.combat.wdata(key)
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
	var best: Array = [0.0, 0.0]
	var far := -1.0
	for k in 6:                                # a bot spot, the farthest of a few picks from the player
		var sp: Array = spots[rng.randi() % spots.size()] if spots.size() > 0 else [0.0, 0.0]
		var dd := Vector2(float(sp[0]) - sim.player.phys.px, float(sp[1]) - sim.player.phys.pz).length()
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
