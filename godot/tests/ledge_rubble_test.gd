extends SceneTree
## Ledge cling + throwable rubble (docs/DAMAGE.md "Ledge cling and throwable rubble", WP 0.6-D). Run by
## tools/test-godot-destruct.js:
##   godot --headless --path godot --script res://tests/ledge_rubble_test.gd -- --no-save
##
## 1. Config: godot/data/extra/ledge.json and rubble.json validate; a bad overlay is rejected and the code falls back to
##    the shipped defaults (a broken data edit can never break a match).
## 2. Ledge cling (overlay only): a falling fighter beside a ledge catches it, is pinned, climbs with JUMP (onto the
##    platform) and lets go with CROUCH (with the outward push); a ledge that disappears (broken / moved away) lets go;
##    a hit knocks a hanging fighter off; the player input path climbs / drops; the tuning gate means a match without the
##    overlay never creates a Ledge and a fighter beside the edge just falls (the parity suites' path).
## 3. Bots: a bot that caught a ledge climbs after the overlay's delay; a falling bot beside a ledge steers into it (the
##    edge probe) and then catches it.
## 4. Rubble: a break leaves one chunk; pickup is only allowed when eligible (alive, on its feet, not carried / carrying,
##    not mid-shove, empty-handed) and only in reach; the player SHOVE / FIRE input path picks it up and throws it; a
##    thrown chunk flies, is resolved through Combat.hit (damage, force, the thrower's K.O. credit) and is spent; a dropped
##    chunk lands again; the chunk cap holds; no CombatRng draw from spawning, picking or a non-K.O. hit.
## 5. Bots: a bot walks to a chunk and picks it up, then throws it at a target inside the overlay's window.
## 6. Integration: a real offline destructible match has Rubble wired to Destruct (a break spawns a chunk) and the
##    tuning-off match has neither overlay object.

const DT := 1.0 / 120.0
const PLATFORM := {"minX": -2.0, "maxX": 2.0, "minZ": -2.0, "maxZ": 2.0, "top": 3.0, "bottom": 0.0}
const FLOOR := {"minX": -10.0, "maxX": 10.0, "minZ": -10.0, "maxZ": 10.0, "top": 0.0, "bottom": -1.0}

var fails := 0
var checks := 0
var maps: Dictionary = {}
var data_ledge: Dictionary = {}
var data_rubble: Dictionary = {}

func check(ok: bool, msg: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		if fails <= 60: print("FAIL ", msg)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	maps = load("res://autoload/content.gd").load_json("maps")
	data_ledge = Combat.read_json(Ledge.DATA_PATH)
	data_rubble = Combat.read_json(Rubble.DATA_PATH)
	_config_checks()
	_ledge_checks()
	_ledge_input_checks()
	_ledge_bot_checks()
	_rubble_checks()
	_rubble_input_checks()
	_rubble_bot_checks()
	await _gate_checks()
	print("LEDGE_RUBBLE %s checks=%d fails=%d" % ["ok" if fails == 0 else "FAILED", checks, fails])
	quit(0 if fails == 0 else 1)

# ============================== helpers ==============================

func _match(map_id: String = "arena") -> MatchSim:
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(424242)
	sim.dyn_choice = "off"
	var m: Dictionary = maps[map_id]
	var geo: Dictionary = m.get("geometry", {})
	sim.setup(map_id, m, geo.get("ladders", []), geo.get("bouncePads", []), "wobbler", PlayerControl.new(InputState.new()), 0)
	return sim

## A bare logic match for the overlay classes: no map, the given solids and fighters, the overlay config loaded.
func _bare(solids: Array) -> MatchSim:
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(424242)
	sim.map = {"spawns": [[0, 0]], "wander": 10}
	sim.solids = solids
	sim.combat.solids = solids
	sim.combat.fighters = []
	sim.fighters = sim.combat.fighters
	sim.destruct_seed = 424242
	return sim

func _fighter(sim: MatchSim, x: float, z: float, player := false) -> FighterState:
	var f := FighterState.new()
	f.id = sim.fighters.size()
	f.is_player = player
	f.set_class("wobbler", sim.combat.classes["wobbler"])
	f.phys.place(x, 0.01, z)
	f.hp = 200.0
	sim.fighters.append(f)
	return f

func _has_event(sim: MatchSim, kind: String, sub: String = "") -> bool:
	for e: Dictionary in sim.combat.events:
		if str(e.get("type", "")) != kind: continue
		if sub == "" or str(e.get("kind", "")) == sub: return true
	return false

# ============================== 1. config ==============================

func _config_checks() -> void:
	check(not data_ledge.is_empty() and (data_ledge as Dictionary).get("version") == Ledge.VERSION, "ledge.json loads with its version")
	check(Ledge.validate(data_ledge).is_empty(), "ledge.json validates: %s" % str(Ledge.validate(data_ledge)))
	var lc := Ledge.config(data_ledge)
	check(lc["topMin"] == 1.1 and lc["topMax"] == 2.2 and lc["hangDrop"] == 1.35 and lc["cooldown"] == 0.45, "ledge config values: %s" % str(lc))
	check(not Ledge.validate({}).is_empty(), "empty ledge overlay is rejected")
	var bad := data_ledge.duplicate(true)
	bad["catch"]["topMin"] = 9.0
	check(not Ledge.validate(bad).is_empty(), "ledge with topMin above topMax is rejected")
	var fallback := Ledge.config({"catch": {"reach": -3}})
	check(is_equal_approx(float(fallback["reach"]), -3.0) or is_equal_approx(float(fallback["reach"]), float(Ledge.DEFAULTS["reach"])), "ledge config keeps numeric fields")

	check(not data_rubble.is_empty() and (data_rubble as Dictionary).get("version") == Rubble.VERSION, "rubble.json loads with its version")
	check(Rubble.validate(data_rubble).is_empty(), "rubble.json validates: %s" % str(Rubble.validate(data_rubble)))
	var rc := Rubble.config(data_rubble)
	check(rc["damage"] == 16.0 and rc["force"] == 13.0 and rc["maxChunks"] == 8.0 and rc["botThrowMax"] == 14.0, "rubble config values: %s" % str(rc))
	check(not Rubble.validate({}).is_empty(), "empty rubble overlay is rejected")
	var bad2 := data_rubble.duplicate(true)
	bad2["bot"]["throwMin"] = 30.0
	check(not Rubble.validate(bad2).is_empty(), "rubble with throwMin above throwMax is rejected")

# ============================== 2. ledge cling ==============================

func _ledge_checks() -> void:
	var sim := _match()
	check(sim.ledge != null, "a tuned offline match creates the Ledge overlay")
	if sim.ledge != null: check(sim.ledge.cfg["topMin"] == 1.1, "the match's Ledge loaded the overlay")
	sim.solids = [PLATFORM.duplicate()]
	sim.combat.solids = sim.solids
	var f := _fighter(sim, 2.45, 0.0)
	f.phys.place(2.45, 1.65, 0.0); f.phys.vy = -1.0; f.phys.grounded = false
	# a catch: the body is pinned just outside the face, the feet hang below the top
	sim.ledge.after_step(f, DT)
	check(not f.hang.is_empty(), "walking/falling past a ledge catches it")
	check(absf(f.phys.py - (3.0 - 1.35)) < 0.02, "the hanging feet sit hangDrop below the ledge top (py %.3f)" % f.phys.py)
	check(f.phys.vy == 0.0 and f.phys.vx == 0.0 and not f.phys.grounded, "a hanging fighter is pinned")
	check(_has_event(sim, "ledge", "catch"), "the catch event is emitted")
	# the pin is re-asserted every step (a moving floor / a shove cannot drag it off)
	f.phys.px = 50.0; f.phys.py = -20.0
	sim.ledge.after_step(f, DT)
	check(absf(f.phys.px - float(f.hang["x"])) < 0.001 and absf(f.phys.py - 1.65) < 0.02, "the hang pin is re-asserted")
	# climb with JUMP: onto the platform, just inside the lip, with the recatch cooldown
	sim.combat.events.clear()
	f.phys.want_jump = true
	sim.ledge.after_step(f, DT)
	check(f.hang.is_empty(), "JUMP climbs off the ledge")
	check(f.phys.grounded and f.phys.py > 3.0, "the climb puts the feet on top (py %.3f)" % f.phys.py)
	check(f.phys.px < float(PLATFORM["maxX"]), "the climb moves the body inside the lip (px %.3f)" % f.phys.px)
	check(f.hang_cool > 0.0, "a climb starts the recatch cooldown")
	check(_has_event(sim, "ledge", "climb"), "the climb event is emitted")
	# drop with CROUCH: let go with the outward push
	f.hang_cool = 0.0
	f.phys.place(2.45, 1.65, 0.0); f.phys.vy = -1.0; f.phys.grounded = false
	sim.ledge.after_step(f, DT)
	sim.combat.events.clear()
	f.hang_drop = true
	sim.ledge.after_step(f, DT)
	check(f.hang.is_empty() and f.phys.vx > 0.5, "CROUCH lets go with the outward push")
	check(_has_event(sim, "ledge", "drop"), "the drop event is emitted")
	# a ledge that disappears (broken) lets go
	f.hang_cool = 0.0
	f.phys.place(2.45, 1.65, 0.0); f.phys.vy = -1.0; f.phys.grounded = false
	sim.ledge.after_step(f, DT)
	check(not f.hang.is_empty(), "re-caught for the disappearing-ledge check")
	sim.solids.clear(); sim.combat.solids = sim.solids
	sim.ledge.after_step(f, DT)
	check(f.hang.is_empty(), "a ledge that is gone releases the hang")
	# a hit knocks a hanging fighter off
	sim.solids = [PLATFORM.duplicate()]; sim.combat.solids = sim.solids
	f.hang_cool = 0.0
	f.phys.place(2.45, 1.65, 0.0); f.phys.vy = -1.0; f.phys.grounded = false; f.hp = 200.0
	sim.ledge.after_step(f, DT)
	check(not f.hang.is_empty(), "re-caught for the hit check")
	var r := sim.combat.hit(f, 4.0, 1.0, 0.2, 0.0, 3.0, false, null)
	check(bool(r.get("applied", false)) and f.hang.is_empty(), "a hit knocks a hanging fighter off the ledge")
	# the overlay comments: a rising fighter does not catch (only falling / hanging still)
	f.hang = {}; f.hang_cool = 0.0
	f.phys.place(2.45, 1.65, 0.0); f.phys.vy = 6.0; f.phys.grounded = false
	sim.ledge.after_step(f, DT)
	check(f.hang.is_empty(), "a rising fighter does not catch a ledge")
	# ... nor does a grounded one standing next to it
	f.phys.vy = 0.0; f.phys.grounded = true
	sim.ledge.after_step(f, DT)
	check(f.hang.is_empty(), "a grounded fighter does not catch a ledge")
	sim.dispose()

# ============================== 3. ledge input / gate ==============================

func _ledge_input_checks() -> void:
	var sim := _match()
	sim.solids = [PLATFORM.duplicate()]; sim.combat.solids = sim.solids
	var pc := PlayerControl.new(InputState.new())
	var p := _fighter(sim, 2.45, 0.0)
	p.phys.place(2.45, 1.65, 0.0); p.phys.vy = -1.0; p.phys.grounded = false
	sim.ledge.after_step(p, DT)
	check(not p.hang.is_empty(), "input check: the player caught the ledge")
	p.hang_t = 0.2
	pc.input.hold("script", "jump", true)
	pc.think(p, sim, DT)
	check(p.phys.want_jump, "holding JUMP while hanging asks for the climb")
	p.phys.want_jump = false
	pc.input.hold("script", "crouch", true)
	pc.think(p, sim, DT)
	check(p.hang_drop, "holding CROUCH while hanging asks to let go")
	# a jump held from before the grab does not skip the grab (the input delay)
	p.hang_drop = false
	var p2 := _fighter(sim, 2.45, 0.0)
	p2.phys.place(2.45, 1.65, 0.0); p2.phys.vy = -1.0; p2.phys.grounded = false
	sim.ledge.after_step(p2, DT)
	p2.hang_t = 0.0
	pc.think(p2, sim, DT)
	check(not p2.phys.want_jump, "JUMP held from before the grab waits for the input delay")
	sim.dispose()

# ============================== 4. bots on ledges ==============================

func _bot_sim(solids: Array, bot_x: float, bot_y: float, bot_z: float) -> Array:
	var sim := _bare(solids)
	var pc := PlayerControl.new(InputState.new())
	var player := _fighter(sim, 20.0, 20.0, true)
	sim.player = player
	sim.controllers[player] = pc
	var bot := _fighter(sim, bot_x, bot_z)
	bot.phys.py = bot_y
	bot.dmg_scale = 0.45
	var brain := BotBrain.new({}, "normal")
	brain.ai_t = 10.0
	brain.think_t = 10.0
	brain.los = true
	sim.controllers[bot] = brain
	sim.ledge = Ledge.new()
	sim.ledge.setup(sim)
	return [sim, bot, brain]

func _ledge_bot_checks() -> void:
	# a caught bot climbs after the overlay's delay
	var s := _bot_sim([PLATFORM.duplicate()], 2.45, 1.65, 0.0)
	var sim: MatchSim = s[0]
	var bot: FighterState = s[1]
	var brain: BotBrain = s[2]
	sim.ledge.after_step(bot, DT)
	check(not bot.hang.is_empty(), "a bot catches a ledge like the player")
	brain.think(bot, sim, DT)
	check(not bot.phys.want_jump, "a bot waits before climbing (not instant)")
	bot.hang_t = 0.4
	brain.think(bot, sim, DT)
	check(bot.phys.want_jump, "a bot asks to climb after the delay")
	sim.ledge.after_step(bot, DT)
	check(bot.hang.is_empty() and bot.phys.grounded and bot.phys.py > 3.0, "the bot climbs onto the ledge")
	sim.dispose()
	# the edge probe: a falling bot beside a ledge steers into it, then catches
	var s2 := _bot_sim([PLATFORM.duplicate()], 2.72, 1.6, 0.0)
	var sim2: MatchSim = s2[0]
	var bot2: FighterState = s2[1]
	var brain2: BotBrain = s2[2]
	bot2.phys.vy = -1.0; bot2.phys.grounded = false
	brain2.think(bot2, sim2, DT)
	check(bot2.phys.wish_x < -0.1, "a falling bot steers toward a catchable ledge (wish_x %.3f)" % bot2.phys.wish_x)
	sim2.ledge.after_step(bot2, DT)
	check(not bot2.hang.is_empty(), "the steered bot then catches the ledge")
	sim2.dispose()

# ============================== 5. rubble ==============================

func _rubble_sim() -> MatchSim:
	var sim := _bare([FLOOR.duplicate()])
	var p := _fighter(sim, 0.0, 0.0, true)
	sim.player = p
	sim.controllers[p] = PlayerControl.new(InputState.new())
	var enemy := _fighter(sim, 0.0, 4.0)
	enemy.name = "Enemy"
	sim.rubble = Rubble.new()
	sim.rubble.setup(sim)
	return sim

func _spawn_chunk(sim: MatchSim, x: float, z: float) -> void:
	sim.rubble.spawn_from_break({"x": x, "z": z, "w": 1.0, "h": 1.0, "d": 1.0, "bottom": 0.0, "color": 0xd9534f})

func _rubble_checks() -> void:
	var sim := _rubble_sim()
	var p := sim.player
	var enemy: FighterState = sim.fighters[1]
	check(sim.rubble != null, "a destructible tuned match creates the rubble overlay")
	check(sim.rubble.count() == 0, "a fresh rubble overlay is empty")
	check(sim.rubble.cfg["damage"] == 16.0 and sim.rubble.cfg["botThrowMax"] == 14.0, "the match's Rubble loaded the overlay")
	_spawn_chunk(sim, 0.6, 0.0)
	check(sim.rubble.count() == 1 and str(sim.rubble.chunks[0]["state"]) == "rest", "a break leaves one resting chunk")
	# eligibility: in reach, alive, on its feet, empty-handed
	check(sim.rubble.can_pick(p), "the player beside a chunk may pick it up")
	var c := sim.rubble.try_pickup(p)
	check(not c.is_empty() and p.rubble == 1 and not sim.rubble.held_by(p).is_empty(), "SHOVE picks the chunk up")
	check(sim.rubble.can_pick(p) == false, "a fighter already holding a chunk may not pick another")
	check(sim.rubble.try_pickup(p).is_empty(), "a second pickup is refused")
	check(sim.rubble.try_pickup(enemy).is_empty(), "a chunk out of reach is not picked up")
	sim.rubble.step(DT)
	check(p.rubble == 1 and not sim.rubble.held_by(p).is_empty(), "a held chunk survives a step")
	# throw at the enemy: resolved through Combat.hit, the thrower is the attacker
	var state := sim.combat.rng.state
	check(sim.rubble.throw_at(p, enemy.phys.px, enemy.phys.py + 1.0, enemy.phys.pz), "FIRE throws the chunk")
	check(p.rubble == 0 and sim.rubble.count() == 1 and str(sim.rubble.chunks[0]["state"]) == "fly", "a thrown chunk flies")
	var hit := false
	for i in 300:
		sim.rubble.step(DT)
		if enemy.hp < 200.0: hit = true; break
	check(hit, "a thrown chunk damages the fighter it hits through Combat.hit")
	check(absf(enemy.hp - 184.0) < 0.01, "the rubble overlay's damage applies exactly (hp %.1f)" % enemy.hp)
	check(enemy.last_attacker == p and float(p.st["dmg"]) == 16.0, "the thrower gets the damage / K.O. credit")
	check(sim.rubble.count() == 0, "a chunk is spent on the hit")
	check(_has_event(sim, "rubble", "hit"), "the rubble hit event is emitted")
	check(sim.combat.rng.state == state, "no CombatRng draw from a pickup / throw / non-K.O. hit")
	# drop: a held chunk goes back on the floor and can be picked up again
	sim.combat.events.clear()
	_spawn_chunk(sim, 0.6, 0.0)
	p.shove_cool = 0.0
	sim.rubble.try_pickup(p)
	check(sim.rubble.drop(p) and p.rubble == 0, "SHOVE while holding puts the chunk down")
	for i in 240: sim.rubble.step(DT)
	check(sim.rubble.count() == 1 and str(sim.rubble.chunks[0]["state"]) == "rest", "a dropped chunk lands and rests")
	p.shove_cool = 0.0
	check(not sim.rubble.try_pickup(p).is_empty(), "a landed chunk can be picked up again")
	sim.rubble.drop(p)
	# the cap: never more than maxChunks live
	for i in 12: _spawn_chunk(sim, 0.6, 0.0)
	check(sim.rubble.count() <= int(Rubble.config(data_rubble)["maxChunks"]), "the chunk cap holds (%d)" % sim.rubble.count())
	sim.dispose()

# ============================== 6. rubble input ==============================

func _rubble_input_checks() -> void:
	var sim := _rubble_sim()
	var p := sim.player
	var pc: PlayerControl = sim.controllers[p]
	_spawn_chunk(sim, 0.5, 0.2)
	pc.input.press("shove")
	pc.think(p, sim, DT)
	check(p.rubble == 1, "the SHOVE input picks a chunk up")
	pc.input.hold("script", "fire", true)
	var throws_before: int = sim.rubble.throws
	pc.think(p, sim, DT)
	check(p.rubble == 0 and sim.rubble.throws == throws_before + 1, "the FIRE input throws the held chunk")
	# ineligible states: dead / knocked down / trapped / carrying
	_spawn_chunk(sim, 0.5, 0.2)
	p.shove_cool = 0.0
	var c := sim.rubble.bot_chunk(p, 5.0)
	check(not c.is_empty(), "an eligible chunk is offered for a bot walk")
	sim.rubble.drop(p)
	p.dead = true
	check(not sim.rubble.can_pick(p), "a dead fighter cannot pick rubble up")
	p.dead = false; p.down_t = 0.9
	check(not sim.rubble.can_pick(p), "a knocked-down fighter cannot pick rubble up")
	p.down_t = 0.0; p.trap_t = 1.0
	check(not sim.rubble.can_pick(p), "a trapped fighter cannot pick rubble up")
	p.trap_t = 0.0; p.carried_by = sim.fighters[1]
	check(not sim.rubble.can_pick(p), "a carried fighter cannot pick rubble up")
	p.carried_by = null
	sim.dispose()

# ============================== 7. rubble bots ==============================

func _rubble_bot_checks() -> void:
	var sim := _bare([FLOOR.duplicate()])
	var player := _fighter(sim, 0.0, 0.0, true)
	sim.player = player
	sim.controllers[player] = PlayerControl.new(InputState.new())
	var bot := _fighter(sim, 0.0, 5.0)
	player.phys.place(0.0, 0.01, 20.0)          # out of the throwing window while it picks the chunk up
	var brain := BotBrain.new({}, "normal")
	brain.ai_t = 10.0
	brain.think_t = 10.0
	brain.los = true
	brain.target = player
	sim.controllers[bot] = brain
	sim.rubble = Rubble.new()
	sim.rubble.setup(sim)
	# a bot walks to a chunk in reach and picks it up
	_spawn_chunk(sim, 0.0, 4.5)
	brain.think(bot, sim, DT)
	check(bot.rubble == 1, "a bot picks up rubble that is in reach")
	# ... then throws it at the target inside the window
	player.phys.place(0.0, 0.01, 1.5)
	var throws_before: int = sim.rubble.throws
	brain.think(bot, sim, DT)
	check(sim.rubble.throws == throws_before + 1 and bot.rubble == 0, "a bot throws the held rubble at a target in range")
	var hp := player.hp
	for i in 300:
		sim.rubble.step(DT)
		if player.hp < hp: break
	check(player.hp < hp, "the bot's thrown chunk damages the player")
	check(player.last_attacker == bot, "the bot gets the damage credit")
	sim.dispose()

# ============================== 8. gate / integration ==============================

func _gate_checks() -> void:
	# tuning off (the parity path): no Ledge and no Rubble, so a fighter beside the edge just falls
	var off := MatchSim.new()
	off.combat.damage_rule = "classic"     # the web numbers / bots-parity rule: tuning_active() false
	off.dyn_choice = "off"
	off.destructible = true                # even a destructible match must stay overlay-free without the tuning gate
	var m: Dictionary = maps["arena"]
	var geo: Dictionary = m.get("geometry", {})
	off.setup("arena", m, geo.get("ladders", []), geo.get("bouncePads", []), "wobbler", PlayerControl.new(InputState.new()), 0)
	check(off.ledge == null, "tuning off: no Ledge is created (parity path)")
	check(off.rubble == null, "tuning off: no Rubble is created (parity path)")
	off.solids = [PLATFORM.duplicate()]; off.combat.solids = off.solids
	var f: FighterState = off.player
	f.phys.place(2.45, 1.65, 0.0); f.phys.vy = -1.0; f.phys.grounded = false
	for i in 120: off.step(DT)
	check(f.hang.is_empty(), "tuning off: a falling fighter never hangs")
	check(f.phys.py < 1.0, "tuning off: the fighter just keeps falling (py %.2f)" % f.phys.py)
	off.dispose()
	# a real tuned destructible match: Destruct is wired to Rubble
	var sim := MatchSim.new()
	sim.combat.rng = CombatRng.new(424242)
	sim.dyn_choice = "off"
	sim.destructible = true
	sim.destruct_seed = 424242
	var am: Dictionary = maps["arena"]
	var ag: Dictionary = am.get("geometry", {})
	var parent := Node3D.new()
	root.add_child(parent)
	sim.view_parent = parent
	sim.setup("arena", am, ag.get("ladders", []), ag.get("bouncePads", []), "wobbler", PlayerControl.new(InputState.new()), 0)
	check(sim.destruct != null and sim.destruct.total() > 0, "a destructible match loads breakables")
	check(sim.rubble != null and sim.destruct != null and sim.destruct.rubble == sim.rubble, "Destruct is wired to the Rubble overlay")
	if sim.rubble != null and sim.destruct != null and sim.destruct.total() > 0:
		var before := sim.rubble.count()
		sim.destruct.break_hit(0, 99999.0)
		check(sim.rubble.count() == before + 1, "a prop break spawns one logical rubble chunk")
	sim.dispose()
	parent.queue_free()
	await process_frame
