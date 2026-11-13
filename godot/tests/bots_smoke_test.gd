extends SceneTree
## Bots playing on their own (run by tools/test-bots.js after the parity test):
##   godot --headless --path godot --script res://tests/bots_smoke_test.gd -- --no-save [--minutes=12] [--only=<diff>]
## Every difficulty plays `minutes` simulated minutes of Classic on three maps (open arena, rooftops with gaps, temple
## with walls and steps) with 5 bots, the player driven by a BotBrain too. Checks, per bot:
##   - self ring-outs (a fall with nobody's hit in the last 10 s): at most MAX_SELF_FALLS per bot-hour, except
##     knockouts the bot could not help (counted as normal K.O.s);
##   - stuck spells (wanting to move for STUCK_SPELL s in a row while staying within 0.5 m): none longer than MAX_STUCK s;
##   - the bots fought (K.O.s happen) and state stays finite.
## Then 10 fighters (9 bots + the player's BotBrain) on arenaxl: prints the bot AI's cost per sim step and per frame.

const FRAME := 1.0 / 20.0           ## coarse frames (World.tick caps at 0.05): the sim still steps at 1/120
const MAPS := ["arena", "rooftops", "temple"]
const DIFFS := ["easy", "normal", "hard", "insane"]
const MAX_SELF_FALLS_PER_HOUR := 6.0
const MAX_STUCK := 8.0              ## s: longest time a bot may push without getting anywhere

var fails := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL ", what)

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _run() -> void:
	var minutes := 12.0
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--minutes="): minutes = float(a.substr(10))
		if a.begins_with("--only="): only = a.substr(7)
	var t0 := Time.get_ticks_msec()
	for diff: String in DIFFS:
		if only != "" and diff != only: continue
		for m: String in MAPS:
			await _play(diff, m, minutes)
	await _cost()
	print("BOTS-SMOKE %s (%.0fs real)" % ["ok" if fails == 0 else "FAILED (%d)" % fails, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0 if fails == 0 else 1)

func _world(map: String, diff: String, bots: int, mode: String = "classic") -> Node:
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = map
	world.mode_id = mode
	world.ko_limit = 0
	world.auto_run = false
	world.bot_count = bots
	world.player_class = "wobbler"
	world.rng_seed = 4242
	world.hp_setting = 200.0
	world.dyn_choice = "off"
	world.difficulty = diff
	root.add_child(world)
	var sim: MatchSim = world.sim
	var pb := BotBrain.new(sim.difficulty, diff)        # the player plays like a bot, so nobody stands around
	sim.controllers[sim.player] = pb
	return world

func _play(diff: String, map: String, minutes: float) -> void:
	var t0 := Time.get_ticks_msec()
	var world := _world(map, diff, 5)
	var sim: MatchSim = world.sim
	var c := sim.combat
	var bots: Array = sim.fighters.slice(1)
	var self_falls := 0
	var falls := 0
	var stuck_long := 0.0
	var stuck_total := 0.0
	var spell := {}
	var last := {}
	var nonfinite := 0
	var next_sample := 1.0
	var frames := int(minutes * 60.0 / FRAME)
	for i in frames:
		var knocked := {}
		var falls0 := {}
		for f: FighterState in bots:
			knocked[f] = f.last_attacker != null and f.last_attacker != f and c.time - f.last_hit_time < 10.0
			falls0[f] = int(f.st["falls"])
		world.tick(FRAME)
		for f: FighterState in bots:
			var df := int(f.st["falls"]) - int(falls0[f])
			if df > 0:
				falls += df
				if not knocked[f]: self_falls += df
		if sim.elapsed() >= next_sample:             # once a second: did it get anywhere while it wanted to move?
			next_sample += 1.0
			for f: FighterState in bots:
				var p := f.phys
				var here := Vector2(p.px, p.pz)
				var wants := not f.dead and f.down_t <= 0.0 and f.stun <= 0.0 and f.swing < 0.0 and Vector2(p.wish_x, p.wish_z).length() > 0.3
				var moved: float = here.distance_to(last[f]) if last.has(f) else 99.0
				if wants and moved < 0.5:
					spell[f] = float(spell.get(f, 0.0)) + 1.0; stuck_total += 1.0
					stuck_long = maxf(stuck_long, spell[f])
				else: spell[f] = 0.0
				last[f] = here
				for v in [p.px, p.py, p.pz, f.hp]:
					if not is_finite(v): nonfinite += 1
	var kos := 0
	var escapes := 0
	for f: FighterState in sim.fighters:
		kos += f.ko
		var br: Variant = sim.controllers.get(f)
		if br is BotBrain: escapes += br.escapes
	var bot_hours := bots.size() * minutes / 60.0
	var tag := "%s/%s" % [diff, map]
	print("SMOKE %-16s %4.0f min kos=%d falls=%d self_falls=%d (%.1f per bot-hour) stuck: longest=%.0fs total=%.0fs escapes=%d think=%.1fus/step (%.1fs real)" % [
		tag, minutes, kos, falls, self_falls, self_falls / bot_hours, stuck_long, stuck_total, escapes,
		float(sim.think_us) / maxf(1.0, sim.elapsed() * 120.0), (Time.get_ticks_msec() - t0) / 1000.0])
	check(self_falls / bot_hours <= MAX_SELF_FALLS_PER_HOUR, "%s: %d self ring-outs (%.1f per bot-hour > %.0f)" % [tag, self_falls, self_falls / bot_hours, MAX_SELF_FALLS_PER_HOUR])
	check(stuck_long <= MAX_STUCK, "%s: a bot stayed stuck %.0f s (> %.0f)" % [tag, stuck_long, MAX_STUCK])
	check(kos > 0, "%s: the bots fought (%d K.O.s)" % [tag, kos])
	check(nonfinite == 0, "%s: state finite" % tag)
	world.queue_free()
	await process_frame

## The bot AI's frame cost with 10 fighters (9 bots + the player's brain) on a big map.
func _cost() -> void:
	var world := _world("arenaxl", "insane", 9)
	var sim: MatchSim = world.sim
	for i in 60: world.tick(FRAME)            # settle
	sim.think_us = 0
	var steps0 := sim.elapsed()
	var us := 0
	var n := 600
	for i in n:
		var a := Time.get_ticks_usec()
		world.tick(FRAME)
		us += Time.get_ticks_usec() - a
	var steps := (sim.elapsed() - steps0) * 120.0
	print("COST 10 bots: think %.1f us per sim step (%.3f ms per 60 Hz frame = 2 steps), whole tick %.2f ms per %.0f ms frame" % [
		float(sim.think_us) / steps, float(sim.think_us) / steps * 2.0 / 1000.0, us / 1000.0 / n, FRAME * 1000.0])
	world.queue_free()
	await process_frame
