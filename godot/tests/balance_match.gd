extends SceneTree
## ONE fully-bot match for balance telemetry (driven by tools/run-balance-matrix.js; docs/BALANCE_TELEMETRY.md):
##   godot --headless --path godot --script res://tests/balance_match.gd -- --no-save --seed=7 [--bots=4 (+ the player seat = 5 fighters)] [--seconds=90]
##         [--mode=classic] [--map=arena] [--class=<id> | --classes=a,b,c,d] [--weapon=<id>] [--start=<id>] [--diff=normal]
## --weapon = everyone holds it for the first life; --start = everyone gets it on EVERY life (it replaces the mode's start weapon for
## this run, in memory only), the controlled way to compare one weapon with another. A DLC pack's mode is owned in memory for the run.
## Every seat (the player's too) is a BotBrain; the sim is hand-stepped at its fixed 1/120 s (no rendering, no realtime).
## Prints exactly one result line:  BALANCE {json}
## Deterministic for a given seed: the world seeds combat.rng, the dynamic arena is off and --no-save fixes the start spots.
## Telemetry only: nothing here writes to the sim, apart from the optional class / starting-weapon override before step 1.

const SIM := 1.0 / 120.0

func _initialize() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % k): return a.substr(k.length() + 3)
	return d

func _run() -> void:
	var seed_n := int(_arg("seed", "1"))
	var bots := int(_arg("bots", "4"))
	var seconds := float(_arg("seconds", "90"))
	var mode := _arg("mode", "classic")
	var map := _arg("map", "arena")
	var diff := _arg("diff", "normal")
	var one_class := _arg("class", "")
	var class_list: PackedStringArray = _arg("classes", "").split(",", false)
	var weapon := _arg("weapon", "")
	var start_over := _arg("start", "")
	# A DLC pack's mode (kitchen / xmas / australia) only starts for an owner: own it in memory for this run (--no-save, never
	# written), or the world would quietly fall back to classic.
	var reg: Variant = load("res://dlc/pack_registry.gd")
	var sv := root.get_node_or_null("Save")
	if reg != null and sv != null and bool(reg.is_pack_mode(mode)) and not bool(reg.mode_owned(mode)):
		DlcSave.set_owned(sv.dlc, str(reg.pack_of_mode(mode)), true)
	var world: Node = load("res://world/world.tscn").instantiate()
	world.map_id = map
	world.mode_id = mode
	world.ko_limit = 0
	world.auto_run = false
	world.bot_count = bots                        # World also reads --bots= itself; fighters = bots + the player's seat (a mode may fix its own count)
	world.player_class = "wobbler"
	world.rng_seed = maxi(1, seed_n)
	world.hp_setting = 200.0
	world.dyn_choice = "off"
	world.destruct_choice = "off"
	world.difficulty = diff
	root.add_child(world)
	var sim: MatchSim = world.sim
	var c := sim.combat
	sim.controllers[sim.player] = BotBrain.new(sim.difficulty, diff)      # the player slot plays like a bot
	var fs: Array = sim.fighters
	# The player seat is a human in a real match (full damage, default speed); here it must be a bot like the others, or its class
	# would look stronger: give it the bots' difficulty damage scale and run speed (tooling only: set before the first step).
	sim.player.dmg_scale = float(sim.difficulty.get("dmg", 0.45))
	sim.player.phys.speed = float(sim.difficulty.get("speed", 4.4))
	# Class assignment: default = the sim's own (rotating) class order; --class sets everyone; --classes sets seat by seat.
	var cls_rng := CombatRng.new(maxi(1, seed_n) * 7919 + 13)             # a private stream (never combat.rng)
	for i in fs.size():
		var cid := ""
		if one_class != "": cid = one_class
		elif i < class_list.size(): cid = class_list[i]
		if cid == "" or not c.classes.has(cid): continue
		var f: FighterState = fs[i]
		f.set_class(cid, c.classes[cid])
		f.hp = c.max_hp(f)
	if start_over != "" and c.weapons_data.has(start_over):
		c.mode["start"] = start_over                 # every respawn hands it out again (Combat.respawn reads mode.start)
		for f: FighterState in fs:
			c.clear_inventory(f); c.set_weapon(f, "spatula"); c.pickup(f, start_over)
	if weapon != "" and c.weapons_data.has(weapon):
		for f: FighterState in fs:
			c.pickup(f, weapon)
	var start_w: Array = []
	for f: FighterState in fs: start_w.append(f.weapon)
	var idx := {}
	for i in fs.size(): idx[fs[i]] = i
	var picks: Array = []
	var crates: Array = []
	var last_ko: Array = []
	var weapon_picks: Array = []
	var weapon_dmg: Array = []          # per fighter: damage dealt while each weapon was in hand
	var weapon_secs: Array = []         # per fighter: seconds each weapon was in hand
	var dmg_prev: Array = []
	for i in fs.size():
		picks.append(0); crates.append(0); last_ko.append(0.0); weapon_picks.append({}); weapon_dmg.append({}); weapon_secs.append({})
		dmg_prev.append(float((fs[i] as FighterState).st["dmg"]))
	for i in fs.size():                  # a weapon handed out at the start (the mode's start weapon, --start, --weapon) is one pick
		var w0 := String((fs[i] as FighterState).weapon)
		if w0 != "" and w0 != "spatula": weapon_picks[i][w0] = 1
	var ko_events: Array = []
	var crate_drops := {}               # crates that fell, by content key (weapons, heal, power-ups)
	var ko_times: Array = []
	var falls_t := {}
	var steps := int(seconds / SIM)
	var t0 := Time.get_ticks_msec()
	for s in steps:
		world.sim_step(SIM)
		var evs: Array = c.events
		for e: Dictionary in evs:
			var ty := String(e.get("type", ""))
			if ty == "ko":
				var v: FighterState = e.get("victim")
				var k: FighterState = e.get("killer")
				var t := sim.elapsed()
				var kill := k != null
				if kill:
					var ki: int = idx[k]
					ko_events.append({"t": snappedf(t, 0.01), "killer": ki, "victim": idx.get(v, -1), "weapon": String(e.get("weapon", "")),
						"wkey": k.weapon if k.weapon != "" else "spatula",
						"ttk": snappedf(t - float(last_ko[ki]), 0.01), "fall": bool(e.get("fall", false))})
					last_ko[ki] = t
					ko_times.append(snappedf(t, 0.01))
			elif ty == "respawn":
				var rf: FighterState = e.get("f")
				if idx.has(rf): last_ko[idx[rf]] = sim.elapsed()
			elif ty == "crate":
				var ck := String((e.get("crate", {}) as Dictionary).get("key", ""))
				crate_drops[ck] = int(crate_drops.get(ck, 0)) + 1
			elif ty == "crate_take":
				var tf: FighterState = e.get("f")
				if idx.has(tf): crates[idx[tf]] += 1
			elif ty == "pickup":
				var pf: FighterState = e.get("f")
				if s > 0 and idx.has(pf) and not bool(e.get("ammo_only", false)):   # step 0 only replays the set-up hand-outs (counted below)
					var key := String(e.get("key", ""))
					weapon_picks[idx[pf]][key] = int(weapon_picks[idx[pf]].get(key, 0)) + 1
		c.events = []
		for i in fs.size():
			var hf: FighterState = fs[i]
			var wk := hf.weapon if hf.weapon != "" else "spatula"
			weapon_secs[i][wk] = float(weapon_secs[i].get(wk, 0.0)) + SIM
			var dnow := float(hf.st["dmg"])
			if dnow != dmg_prev[i]:
				weapon_dmg[i][wk] = float(weapon_dmg[i].get(wk, 0.0)) + dnow - float(dmg_prev[i])
				dmg_prev[i] = dnow
	for i in fs.size():
		for k: String in weapon_dmg[i]: weapon_dmg[i][k] = snappedf(float(weapon_dmg[i][k]), 0.1)
		for k: String in weapon_secs[i]: weapon_secs[i][k] = snappedf(float(weapon_secs[i][k]), 0.01)
	var out_f: Array = []
	var tot_ko := 0
	var tot_falls := 0
	for i in fs.size():
		var f: FighterState = fs[i]
		var st: Dictionary = f.st
		tot_ko += f.ko; tot_falls += int(st["falls"])
		out_f.append({"seat": i, "class_id": f.class_id, "weapon_start": start_w[i], "weapon_end": f.weapon, "kos": f.ko,
			"deaths": int(st["deaths"]), "falls": int(st["falls"]), "hits": int(st["hits"]), "dmg": snappedf(float(st["dmg"]), 0.1),
			"crates_picked": crates[i], "weapon_picks": weapon_picks[i],
			"weapon_dmg": weapon_dmg[i], "weapon_secs": weapon_secs[i]})
	var winner := -1
	var best := -1
	var tie := false
	for i in fs.size():
		var f: FighterState = fs[i]
		if f.ko > best: best = f.ko; winner = i; tie = false
		elif f.ko == best: tie = true
	if tie or best <= 0: winner = -1
	var res := {"seed": seed_n, "mode": sim.combat.mode_id, "mode_asked": mode, "start": start_over, "map": map, "diff": diff, "seconds_simulated": snappedf(sim.elapsed(), 0.01),
		"fighters": out_f, "total_kos": tot_ko, "total_ringouts": tot_falls, "crate_drops": crate_drops,
		"first_ko_time": ko_times[0] if ko_times.size() > 0 else null, "ko_times": ko_times, "ko_events": ko_events, "winner": winner,
		"real_s": snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)}
	print("BALANCE " + JSON.stringify(res))
	world.queue_free()
	quit(0)
